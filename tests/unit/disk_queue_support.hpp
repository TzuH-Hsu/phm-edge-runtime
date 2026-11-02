// SPDX-License-Identifier: Apache-2.0
// Helpers shared by the disk queue tests: temporary database files, fixture
// files, byte strings and a plain SQLite connection for the test's own SQL.
#pragma once

#include <gtest/gtest.h>
#include <sqlite3.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <memory>
#include <optional>
#include <phm/runtime/queue/disk_queue.hpp>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace phm::runtime::queue::test {

// 2026-01-01T00:00:00Z in milliseconds since the epoch.
inline constexpr std::int64_t kT0 = 1767225600000;
inline constexpr std::chrono::seconds kSpan{60};

inline Timestamp at_ms(std::int64_t ms) { return Timestamp{std::chrono::milliseconds{ms}}; }

inline std::vector<std::byte> hex_bytes(std::string_view hex) {
  if (hex.size() % 2 != 0) {
    throw std::invalid_argument("odd number of hex digits");
  }
  std::vector<std::byte> bytes;
  bytes.reserve(hex.size() / 2);
  for (std::size_t i = 0; i < hex.size(); i += 2) {
    bytes.push_back(static_cast<std::byte>(std::stoul(std::string(hex.substr(i, 2)), nullptr, 16)));
  }
  return bytes;
}

inline std::filesystem::path fixture_path(std::string_view relative) {
  return std::filesystem::path{PHM_RUNTIME_FIXTURE_DIR} / relative;
}

inline std::string read_file(const std::filesystem::path& path) {
  const std::ifstream in(path, std::ios::binary);
  if (!in) {
    throw std::runtime_error("cannot read " + path.string());
  }
  std::ostringstream text;
  text << in.rdbuf();
  return text.str();
}

// A fresh directory per test, removed with everything in it at the end.
class TempDir {
 public:
  TempDir() {
    static std::atomic<int> counter{0};
    const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
    std::string name = "phm-disk-queue-" + std::to_string(::getpid()) + "-";
    name += info == nullptr ? std::string{"none"} : std::string{info->name()};
    name += "-" + std::to_string(counter.fetch_add(1));
    dir_ = std::filesystem::temp_directory_path() / name;
    std::filesystem::remove_all(dir_);
    std::filesystem::create_directories(dir_);
  }
  ~TempDir() {
    std::error_code ignored;
    std::filesystem::remove_all(dir_, ignored);
  }
  TempDir(const TempDir&) = delete;
  TempDir& operator=(const TempDir&) = delete;
  TempDir(TempDir&&) = delete;
  TempDir& operator=(TempDir&&) = delete;

  [[nodiscard]] const std::filesystem::path& path() const { return dir_; }
  [[nodiscard]] std::filesystem::path database() const { return dir_ / "queue.db"; }

 private:
  std::filesystem::path dir_;
};

// A plain SQLite connection the test uses next to the queue's own.
class RawConnection {
 public:
  explicit RawConnection(const std::filesystem::path& file) {
    if (sqlite3_open_v2(file.string().c_str(), &db_, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
                        nullptr) != SQLITE_OK) {
      throw std::runtime_error("cannot open " + file.string());
    }
  }
  ~RawConnection() { sqlite3_close_v2(db_); }
  RawConnection(const RawConnection&) = delete;
  RawConnection& operator=(const RawConnection&) = delete;
  RawConnection(RawConnection&&) = delete;
  RawConnection& operator=(RawConnection&&) = delete;

  [[nodiscard]] sqlite3* get() const { return db_; }

  void exec(const std::string& sql) const {
    char* message = nullptr;
    if (sqlite3_exec(db_, sql.c_str(), nullptr, nullptr, &message) != SQLITE_OK) {
      const std::string text = message == nullptr ? "unknown error" : message;
      sqlite3_free(message);
      throw std::runtime_error(text);
    }
  }

  // The first column of the first row as text; empty optional for NULL or no row.
  [[nodiscard]] std::optional<std::string> query_text(const std::string& sql) const {
    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
      throw std::runtime_error(sqlite3_errmsg(db_));
    }
    std::optional<std::string> value;
    if (sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL) {
      const void* text = sqlite3_column_text(stmt, 0);
      value = std::string{static_cast<const char*>(text)};
    }
    sqlite3_finalize(stmt);
    return value;
  }

 private:
  sqlite3* db_ = nullptr;
};

inline NewItem new_item(std::string_view key, std::optional<std::int64_t> timestamp_ms,
                        const std::vector<std::byte>& payload) {
  return NewItem{key, timestamp_ms ? std::optional<Timestamp>{at_ms(*timestamp_ms)} : std::nullopt,
                 payload};
}

inline StoredItem stored_item(std::string key, std::optional<std::int64_t> timestamp_ms,
                              std::string_view payload_hex) {
  return StoredItem{std::move(key),
                    timestamp_ms ? std::optional<Timestamp>{at_ms(*timestamp_ms)} : std::nullopt,
                    hex_bytes(payload_hex)};
}

inline std::vector<std::string> keys_of(const std::vector<StoredItem>& items) {
  std::vector<std::string> keys;
  keys.reserve(items.size());
  for (const auto& item : items) {
    keys.push_back(item.key);
  }
  return keys;
}

inline std::unique_ptr<DiskQueue> open_queue(const std::filesystem::path& file,
                                             std::chrono::seconds span = kSpan) {
  auto queue = DiskQueue::open(file, span);
  if (!queue) {
    ADD_FAILURE() << "open failed: " << queue.error().message;
    return nullptr;
  }
  return std::move(queue).value();
}

// One row of tests/fixtures/disk_queue/operations.tsv.
struct OperationRow {
  std::string op;
  std::string key;
  std::optional<std::int64_t> timestamp_ms;
  std::vector<std::byte> payload;
  std::string expected;
};

inline std::vector<OperationRow> load_operations() {
  std::istringstream lines(read_file(fixture_path("disk_queue/operations.tsv")));
  std::vector<OperationRow> rows;
  std::string line;
  while (std::getline(lines, line)) {
    if (line.empty() || line.front() == '#') {
      continue;
    }
    std::vector<std::string> fields;
    std::istringstream cells(line);
    std::string cell;
    while (std::getline(cells, cell, '\t')) {
      fields.push_back(cell);
    }
    if (fields.size() != 5) {
      throw std::runtime_error("operations.tsv: expected 5 fields in: " + line);
    }
    OperationRow row{fields[0], fields[1], std::nullopt, {}, fields[4]};
    if (fields[2] != "-") {
      row.timestamp_ms = std::stoll(fields[2]);
    }
    if (fields[3] != "-") {
      row.payload = hex_bytes(fields[3]);
    }
    rows.push_back(std::move(row));
  }
  return rows;
}

inline std::string errc_name(QueueErrc code) {
  switch (code) {
    case QueueErrc::invalid_argument:
      return "invalid_argument";
    case QueueErrc::open_failed:
      return "open_failed";
    case QueueErrc::write_failed:
      return "write_failed";
    case QueueErrc::read_failed:
      return "read_failed";
    case QueueErrc::item_limit_reached:
      return "item_limit_reached";
    case QueueErrc::exempt_not_droppable:
      return "exempt_not_droppable";
  }
  return "unknown";
}

// Runs one fixture row and returns its result in the fixture's spelling.
inline std::string run_operation(DiskQueue& queue, const OperationRow& row) {
  if (row.op == "enqueue") {
    auto result = queue.enqueue(new_item(row.key, row.timestamp_ms, row.payload));
    if (!result) {
      return "error:" + errc_name(result.error().code);
    }
    switch (result.value()) {
      case EnqueueOutcome::stored:
        return "stored";
      case EnqueueOutcome::already_stored:
        return "already_stored";
      case EnqueueOutcome::rejected_full:
        return "rejected_full";
    }
    return "unknown";
  }
  auto result = row.op == "remove" ? queue.remove(row.key) : queue.remove_as_dropped(row.key);
  if (!result) {
    return "error:" + errc_name(result.error().code);
  }
  return result.value() == RemoveOutcome::removed ? "removed" : "not_found";
}

// Runs rows [first, last) and checks each result against the fixture.
inline void run_rows(DiskQueue& queue, const std::vector<OperationRow>& rows, std::size_t first,
                     std::size_t last) {
  for (std::size_t i = first; i < last && i < rows.size(); ++i) {
    EXPECT_EQ(run_operation(queue, rows[i]), rows[i].expected)
        << "row " << (i + 1) << ": " << rows[i].op << " " << rows[i].key;
  }
}

}  // namespace phm::runtime::queue::test
