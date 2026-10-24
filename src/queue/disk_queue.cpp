// SPDX-License-Identifier: Apache-2.0
#include "phm/runtime/queue/disk_queue.hpp"

#include <sqlite3.h>

#include <algorithm>
#include <condition_variable>
#include <cstdint>
#include <limits>
#include <mutex>
#include <utility>

#include "queue/schema.hpp"

namespace phm::runtime::queue {
namespace {

using std::chrono::milliseconds;
using std::chrono::steady_clock;

// wait_for_items() waits in slices of at most this length, so a very long
// timeout never reaches the clock's limits.
constexpr auto kMaxWaitSlice = std::chrono::hours{1};

struct ConnectionCloser {
  void operator()(sqlite3* db) const noexcept { sqlite3_close_v2(db); }
};
using Connection = std::unique_ptr<sqlite3, ConnectionCloser>;

Unexpected<QueueError> failure(QueueErrc code, std::string message) {
  return Unexpected<QueueError>{QueueError{code, 0, std::move(message)}};
}

Unexpected<QueueError> sqlite_failure(QueueErrc code, sqlite3* db) {
  return Unexpected<QueueError>{QueueError{code, sqlite3_extended_errcode(db), sqlite3_errmsg(db)}};
}

Unexpected<QueueError> sqlite_failure(QueueErrc code, int sqlite_code, std::string_view what) {
  std::string message{what};
  message += ": ";
  message += sqlite3_errstr(sqlite_code);
  return Unexpected<QueueError>{QueueError{code, sqlite_code, std::move(message)}};
}

std::int64_t to_ms(Timestamp timestamp) noexcept { return timestamp.time_since_epoch().count(); }

Timestamp from_ms(std::int64_t ms) noexcept { return Timestamp{milliseconds{ms}}; }

bool valid_key(std::string_view key) noexcept { return !key.empty() && key.size() <= kMaxKeyBytes; }

// One prepared statement, finalised on destruction.
class Statement {
 public:
  Statement(sqlite3* db, std::string_view sql) noexcept
      : rc_(sqlite3_prepare_v2(db, sql.data(), static_cast<int>(sql.size()), &stmt_, nullptr)) {}
  ~Statement() { sqlite3_finalize(stmt_); }
  Statement(const Statement&) = delete;
  Statement& operator=(const Statement&) = delete;
  Statement(Statement&&) = delete;
  Statement& operator=(Statement&&) = delete;

  [[nodiscard]] bool ok() const noexcept { return rc_ == SQLITE_OK; }

  // A zero-length blob is bound as X'' rather than NULL.
  bool bind_blob(int index, const void* data, std::size_t size) noexcept {
    if (ok()) {
      rc_ = size == 0 ? sqlite3_bind_zeroblob(stmt_, index, 0)
                      : sqlite3_bind_blob64(stmt_, index, data, static_cast<sqlite3_uint64>(size),
                                            SQLITE_STATIC);
    }
    return ok();
  }

  bool bind_int64(int index, std::int64_t value) noexcept {
    if (ok()) {
      rc_ = sqlite3_bind_int64(stmt_, index, value);
    }
    return ok();
  }

  bool bind_optional_int64(int index, std::optional<std::int64_t> value) noexcept {
    if (ok()) {
      rc_ = value ? sqlite3_bind_int64(stmt_, index, *value) : sqlite3_bind_null(stmt_, index);
    }
    return ok();
  }

  // SQLITE_ROW, SQLITE_DONE or the error; an earlier failure is returned as is.
  int step() noexcept {
    if (!ok()) {
      return rc_;
    }
    const int rc = sqlite3_step(stmt_);
    if (rc != SQLITE_ROW && rc != SQLITE_DONE) {
      rc_ = rc;
    }
    return rc;
  }

  // Steps a statement that returns no row; true when it completed.
  bool run() noexcept { return step() == SQLITE_DONE; }

  [[nodiscard]] std::int64_t int64_at(int column) const noexcept {
    return sqlite3_column_int64(stmt_, column);
  }

  [[nodiscard]] std::optional<std::int64_t> optional_int64_at(int column) const noexcept {
    if (sqlite3_column_type(stmt_, column) == SQLITE_NULL) {
      return std::nullopt;
    }
    return sqlite3_column_int64(stmt_, column);
  }

  [[nodiscard]] std::span<const std::byte> blob_at(int column) const noexcept {
    const void* data = sqlite3_column_blob(stmt_, column);  // before column_bytes
    const int size = sqlite3_column_bytes(stmt_, column);
    if (data == nullptr || size <= 0) {
      return {};
    }
    return {static_cast<const std::byte*>(data), static_cast<std::size_t>(size)};
  }

 private:
  sqlite3_stmt* stmt_ = nullptr;
  int rc_ = SQLITE_OK;
};

// BEGIN IMMEDIATE on construction; rolls back on destruction unless committed.
class WriteTransaction {
 public:
  explicit WriteTransaction(sqlite3* db) noexcept
      : db_(db),
        active_(sqlite3_exec(db, "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) == SQLITE_OK) {}
  ~WriteTransaction() {
    if (active_ && sqlite3_get_autocommit(db_) == 0) {
      sqlite3_exec(db_, "ROLLBACK", nullptr, nullptr, nullptr);
    }
  }
  WriteTransaction(const WriteTransaction&) = delete;
  WriteTransaction& operator=(const WriteTransaction&) = delete;
  WriteTransaction(WriteTransaction&&) = delete;
  WriteTransaction& operator=(WriteTransaction&&) = delete;

  [[nodiscard]] bool begun() const noexcept { return active_; }

  bool commit() noexcept {
    if (sqlite3_exec(db_, "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK) {
      return false;  // the destructor rolls back
    }
    active_ = false;
    return true;
  }

 private:
  sqlite3* db_;
  bool active_;
};

// Smallest and largest timestamp of the stored non-exempt items.
struct TimestampRange {
  std::optional<std::int64_t> min;
  std::optional<std::int64_t> max;
};

// Strictly more than the span apart is full; with fewer than two non-exempt
// items min equals max, which is never full.
bool range_is_full(const TimestampRange& range, std::uint64_t span_ms) noexcept {
  if (!range.min || !range.max || *range.max < *range.min) {
    return false;
  }
  // Unsigned arithmetic gives the exact difference of any two int64 values.
  const std::uint64_t difference =
      static_cast<std::uint64_t>(*range.max) - static_cast<std::uint64_t>(*range.min);
  return difference > span_ms;
}

std::uint64_t span_to_ms(std::chrono::seconds span) noexcept {
  constexpr std::uint64_t kMsPerSecond = 1000;
  const auto seconds = static_cast<std::uint64_t>(span.count());
  if (seconds > std::numeric_limits<std::uint64_t>::max() / kMsPerSecond) {
    return std::numeric_limits<std::uint64_t>::max();
  }
  return seconds * kMsPerSecond;
}

// A stored item found by key on the write connection.
struct FoundItem {
  std::int64_t seq = 0;
  std::optional<std::int64_t> timestamp_ms;
};

QueueResult<std::optional<FoundItem>> find_item(sqlite3* db, std::string_view key) {
  Statement stmt(db, "SELECT seq, timestamp_ms FROM queue_items WHERE item_key = ?1");
  stmt.bind_blob(1, key.data(), key.size());
  const int rc = stmt.step();
  if (rc == SQLITE_ROW) {
    return std::optional<FoundItem>{FoundItem{stmt.int64_at(0), stmt.optional_int64_at(1)}};
  }
  if (rc == SQLITE_DONE) {
    return std::optional<FoundItem>{};
  }
  return sqlite_failure(QueueErrc::write_failed, db);
}

QueueResult<TimestampRange> read_range(sqlite3* db, QueueErrc on_error) {
  // Two scalar subqueries, so each uses the timestamp index for its endpoint;
  // one min() and max() aggregate would scan every row.
  Statement stmt(db,
                 "SELECT (SELECT min(timestamp_ms) FROM queue_items), "
                 "(SELECT max(timestamp_ms) FROM queue_items)");
  if (stmt.step() != SQLITE_ROW) {
    return sqlite_failure(on_error, db);
  }
  return TimestampRange{stmt.optional_int64_at(0), stmt.optional_int64_at(1)};
}

QueueResult<std::int64_t> count_items(sqlite3* db, QueueErrc on_error) {
  Statement stmt(db, "SELECT count(seq) FROM queue_items");
  if (stmt.step() != SQLITE_ROW) {
    return sqlite_failure(on_error, db);
  }
  return stmt.int64_at(0);
}

// Counts one drop of an item with this timestamp: starts a drop period when
// none is open, otherwise extends the open one.
bool record_drop(sqlite3* db, std::int64_t timestamp_ms) {
  Statement stmt(db,
                 "UPDATE queue_drop_record SET dropped_total = dropped_total + 1, "
                 "dropped_from_ms = CASE WHEN period_open = 0 THEN ?1 ELSE dropped_from_ms END, "
                 "dropped_to_ms = ?1, period_open = 1 WHERE id = 1");
  stmt.bind_int64(1, timestamp_ms);
  return stmt.run() && sqlite3_changes(db) == 1;
}

bool close_drop_period(sqlite3* db) {
  Statement stmt(db,
                 "UPDATE queue_drop_record SET period_open = 0 WHERE id = 1 AND period_open <> 0");
  return stmt.run();
}

bool insert_item(sqlite3* db, const NewItem& item) {
  Statement stmt(db,
                 "INSERT INTO queue_items (item_key, timestamp_ms, payload) VALUES (?1, ?2, ?3)");
  stmt.bind_blob(1, item.key.data(), item.key.size());
  stmt.bind_optional_int64(
      2, item.timestamp ? std::optional<std::int64_t>{to_ms(*item.timestamp)} : std::nullopt);
  stmt.bind_blob(3, item.payload.data(), item.payload.size());
  return stmt.run();
}

bool delete_item(sqlite3* db, std::int64_t seq) {
  Statement stmt(db, "DELETE FROM queue_items WHERE seq = ?1");
  stmt.bind_int64(1, seq);
  return stmt.run();
}

QueueResult<Connection> open_connection(const std::string& file, int flags) {
  sqlite3* raw = nullptr;
  const int rc = sqlite3_open_v2(file.c_str(), &raw, flags, nullptr);
  Connection db{raw};
  if (rc != SQLITE_OK) {
    if (db == nullptr) {
      return sqlite_failure(QueueErrc::open_failed, rc, "cannot open the database");
    }
    return sqlite_failure(QueueErrc::open_failed, db.get());
  }
  sqlite3_extended_result_codes(db.get(), 1);
  if (const int code = detail::configure_connection(db.get()); code != SQLITE_OK) {
    return sqlite_failure(QueueErrc::open_failed, code,
                          "cannot set journal_mode = WAL and synchronous = FULL");
  }
  return db;
}

std::string key_from_bytes(std::span<const std::byte> bytes) {
  std::string key(bytes.size(), '\0');
  std::ranges::transform(bytes, key.begin(), [](std::byte b) { return static_cast<char>(b); });
  return key;
}

}  // namespace

struct DiskQueue::Impl {
  Impl(Connection write_connection, Connection read_connection, std::uint64_t span,
       std::int64_t stored_items) noexcept
      : writer(std::move(write_connection)),
        reader(std::move(read_connection)),
        span_ms(span),
        item_count(stored_items) {}

  // A private implementation struct: its members are used by DiskQueue only.
  // NOLINTBEGIN(misc-non-private-member-variables-in-classes)
  // Members are destroyed in reverse order: the read connection closes first.
  Connection writer;
  Connection reader;
  std::uint64_t span_ms;

  std::mutex write_mutex;  // serialises every use of writer and item_count
  std::int64_t item_count;

  std::mutex read_mutex;  // serialises every use of reader

  std::mutex wake_mutex;  // guards generation
  std::condition_variable_any wake;
  std::uint64_t generation = 0;  // incremented after every committed enqueue
  // NOLINTEND(misc-non-private-member-variables-in-classes)

  QueueResult<RemoveOutcome> remove(std::string_view key, bool as_dropped);
  QueueResult<std::vector<StoredItem>> read_batch(std::int64_t limit);
  QueueResult<bool> has_items();
  void notify_waiters();
};

QueueResult<std::unique_ptr<DiskQueue>> DiskQueue::open(const std::filesystem::path& database_path,
                                                        std::chrono::seconds capacity_span) {
  if (capacity_span <= std::chrono::seconds::zero()) {
    return failure(QueueErrc::invalid_argument, "capacity_span must be at least one second");
  }
  const std::string file = database_path.string();
  auto writer = open_connection(file, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE);
  if (!writer) {
    return Unexpected<QueueError>{writer.error()};
  }
  if (const int code = detail::apply_schema(writer.value().get()); code != SQLITE_OK) {
    return sqlite_failure(QueueErrc::open_failed, code, "cannot apply the queue schema");
  }
  auto stored = count_items(writer.value().get(), QueueErrc::open_failed);
  if (!stored) {
    return Unexpected<QueueError>{stored.error()};
  }
  auto reader = open_connection(file, SQLITE_OPEN_READWRITE);
  if (!reader) {
    return Unexpected<QueueError>{reader.error()};
  }
  auto impl = std::make_unique<Impl>(std::move(writer).value(), std::move(reader).value(),
                                     span_to_ms(capacity_span), stored.value());
  return std::unique_ptr<DiskQueue>(new DiskQueue(std::move(impl)));
}

DiskQueue::DiskQueue(std::unique_ptr<Impl> impl) : impl_(std::move(impl)) {}

DiskQueue::~DiskQueue() = default;

QueueResult<EnqueueOutcome> DiskQueue::enqueue(const NewItem& item) {
  if (!valid_key(item.key)) {
    return failure(QueueErrc::invalid_argument, "key must be 1 to 256 bytes");
  }
  if (item.payload.size() > kMaxPayloadBytes) {
    return failure(QueueErrc::invalid_argument, "payload is larger than kMaxPayloadBytes");
  }
  Impl& q = *impl_;
  {
    const std::lock_guard lock(q.write_mutex);
    sqlite3* db = q.writer.get();
    WriteTransaction tx(db);
    if (!tx.begun()) {
      return sqlite_failure(QueueErrc::write_failed, db);
    }
    auto existing = find_item(db, item.key);
    if (!existing) {
      return Unexpected<QueueError>{existing.error()};
    }
    if (existing.value()) {
      return EnqueueOutcome::already_stored;  // nothing written; the destructor rolls back
    }
    if (item.timestamp) {
      auto range = read_range(db, QueueErrc::write_failed);
      if (!range) {
        return Unexpected<QueueError>{range.error()};
      }
      if (range_is_full(range.value(), q.span_ms)) {
        if (!record_drop(db, to_ms(*item.timestamp)) || !tx.commit()) {
          return sqlite_failure(QueueErrc::write_failed, db);
        }
        return EnqueueOutcome::rejected_full;
      }
    }
    if (q.item_count >= kMaxItemCount) {
      return failure(QueueErrc::item_limit_reached, "kMaxItemCount items are stored");
    }
    // Storing a non-exempt item ends the open drop period, if any.
    if (!insert_item(db, item) || (item.timestamp && !close_drop_period(db)) || !tx.commit()) {
      return sqlite_failure(QueueErrc::write_failed, db);
    }
    ++q.item_count;
  }
  q.notify_waiters();
  return EnqueueOutcome::stored;
}

QueueResult<RemoveOutcome> DiskQueue::Impl::remove(std::string_view key, bool as_dropped) {
  if (!valid_key(key)) {
    return failure(QueueErrc::invalid_argument, "key must be 1 to 256 bytes");
  }
  const std::lock_guard lock(write_mutex);
  sqlite3* db = writer.get();
  WriteTransaction tx(db);
  if (!tx.begun()) {
    return sqlite_failure(QueueErrc::write_failed, db);
  }
  auto found = find_item(db, key);
  if (!found) {
    return Unexpected<QueueError>{found.error()};
  }
  const std::optional<FoundItem>& match = found.value();
  if (!match) {
    return RemoveOutcome::not_found;
  }
  if (as_dropped && !match->timestamp_ms) {
    return failure(QueueErrc::exempt_not_droppable, "an exempt item cannot be counted as dropped");
  }
  const std::optional<std::int64_t> dropped_at = as_dropped ? match->timestamp_ms : std::nullopt;
  if (!delete_item(db, match->seq) || (dropped_at && !record_drop(db, *dropped_at)) ||
      !tx.commit()) {
    return sqlite_failure(QueueErrc::write_failed, db);
  }
  --item_count;
  return RemoveOutcome::removed;
}

QueueResult<RemoveOutcome> DiskQueue::remove(std::string_view key) {
  return impl_->remove(key, false);
}

QueueResult<RemoveOutcome> DiskQueue::remove_as_dropped(std::string_view key) {
  return impl_->remove(key, true);
}

QueueResult<std::vector<StoredItem>> DiskQueue::Impl::read_batch(std::int64_t limit) {
  const std::lock_guard lock(read_mutex);
  sqlite3* db = reader.get();
  Statement stmt(db,
                 "SELECT item_key, timestamp_ms, payload FROM queue_items ORDER BY seq LIMIT ?1");
  stmt.bind_int64(1, limit);
  std::vector<StoredItem> items;
  for (;;) {
    const int rc = stmt.step();
    if (rc == SQLITE_DONE) {
      return items;
    }
    if (rc != SQLITE_ROW) {
      return sqlite_failure(QueueErrc::read_failed, db);
    }
    std::optional<Timestamp> timestamp;
    if (const auto ms = stmt.optional_int64_at(1)) {
      timestamp = from_ms(*ms);
    }
    const std::span<const std::byte> payload = stmt.blob_at(2);
    items.push_back(
        StoredItem{key_from_bytes(stmt.blob_at(0)), timestamp, {payload.begin(), payload.end()}});
  }
}

QueueResult<std::optional<StoredItem>> DiskQueue::peek_head() const {
  auto batch = impl_->read_batch(1);
  if (!batch) {
    return Unexpected<QueueError>{batch.error()};
  }
  if (batch.value().empty()) {
    return std::optional<StoredItem>{};
  }
  return std::optional<StoredItem>{std::move(batch.value().front())};
}

QueueResult<std::vector<StoredItem>> DiskQueue::peek_batch(std::size_t max_items) const {
  if (max_items == 0) {
    return failure(QueueErrc::invalid_argument, "max_items must be at least 1");
  }
  constexpr auto kLimitMax = static_cast<std::size_t>(std::numeric_limits<std::int64_t>::max());
  return impl_->read_batch(static_cast<std::int64_t>(std::min(max_items, kLimitMax)));
}

QueueResult<Watermark> DiskQueue::watermark() const {
  Impl& q = *impl_;
  const std::lock_guard lock(q.read_mutex);
  sqlite3* db = q.reader.get();
  Statement stmt(db,
                 "SELECT count(seq), coalesce(sum(length(payload)), 0), min(timestamp_ms) "
                 "FROM queue_items");
  if (stmt.step() != SQLITE_ROW) {
    return sqlite_failure(QueueErrc::read_failed, db);
  }
  Watermark mark;
  mark.item_count =
      static_cast<std::int32_t>(std::min<std::int64_t>(stmt.int64_at(0), kMaxItemCount));
  mark.payload_bytes = stmt.int64_at(1);
  if (const auto oldest = stmt.optional_int64_at(2)) {
    mark.oldest = from_ms(*oldest);
  }
  return mark;
}

QueueResult<DropRecord> DiskQueue::drop_record() const {
  Impl& q = *impl_;
  const std::lock_guard lock(q.read_mutex);
  sqlite3* db = q.reader.get();
  // One statement, so the drop record and the full state come from one snapshot;
  // each endpoint is a scalar subquery that uses the timestamp index.
  Statement stmt(db,
                 "SELECT dropped_total, dropped_from_ms, dropped_to_ms, "
                 "(SELECT min(timestamp_ms) FROM queue_items), "
                 "(SELECT max(timestamp_ms) FROM queue_items) "
                 "FROM queue_drop_record WHERE id = 1");
  const int rc = stmt.step();
  if (rc == SQLITE_DONE) {
    return failure(QueueErrc::read_failed, "the drop record row is missing");
  }
  if (rc != SQLITE_ROW) {
    return sqlite_failure(QueueErrc::read_failed, db);
  }
  DropRecord record;
  record.full = range_is_full({stmt.optional_int64_at(3), stmt.optional_int64_at(4)}, q.span_ms);
  record.dropped_total = stmt.int64_at(0);
  if (const auto from = stmt.optional_int64_at(1)) {
    record.dropped_from = from_ms(*from);
  }
  if (const auto to = stmt.optional_int64_at(2)) {
    record.dropped_to = from_ms(*to);
  }
  return record;
}

QueueResult<bool> DiskQueue::is_full() const {
  Impl& q = *impl_;
  const std::lock_guard lock(q.read_mutex);
  auto range = read_range(q.reader.get(), QueueErrc::read_failed);
  if (!range) {
    return Unexpected<QueueError>{range.error()};
  }
  return range_is_full(range.value(), q.span_ms);
}

QueueResult<bool> DiskQueue::Impl::has_items() {
  const std::lock_guard lock(read_mutex);
  sqlite3* db = reader.get();
  Statement stmt(db, "SELECT seq FROM queue_items ORDER BY seq LIMIT 1");
  const int rc = stmt.step();
  if (rc != SQLITE_ROW && rc != SQLITE_DONE) {
    return sqlite_failure(QueueErrc::read_failed, db);
  }
  return rc == SQLITE_ROW;
}

void DiskQueue::Impl::notify_waiters() {
  {
    const std::lock_guard lock(wake_mutex);
    ++generation;
  }
  wake.notify_all();
}

// The token is taken by value as the public header declares it.
QueueResult<WaitOutcome> DiskQueue::wait_for_items(
    std::stop_token stop,  // NOLINT(performance-unnecessary-value-param)
    std::chrono::milliseconds timeout) const {
  Impl& q = *impl_;
  const auto start = steady_clock::now();
  const auto room =
      std::chrono::duration_cast<milliseconds>(steady_clock::time_point::max() - start);
  const auto deadline = timeout >= room ? steady_clock::time_point::max()
                                        : start + std::max(timeout, milliseconds::zero());
  for (;;) {
    std::uint64_t seen = 0;
    {
      const std::lock_guard lock(q.wake_mutex);
      seen = q.generation;
    }
    // An enqueue that commits after this check changes generation, so the
    // wait below returns at once instead of missing it.
    auto has_items = q.has_items();
    if (!has_items) {
      return Unexpected<QueueError>{has_items.error()};
    }
    if (has_items.value()) {
      return WaitOutcome::items_available;
    }
    if (stop.stop_requested()) {
      return WaitOutcome::stop_requested;
    }
    const auto now = steady_clock::now();
    if (now >= deadline) {
      return WaitOutcome::timed_out;
    }
    const auto slice_end = deadline - now > kMaxWaitSlice ? now + kMaxWaitSlice : deadline;
    std::unique_lock lock(q.wake_mutex);
    static_cast<void>(
        q.wake.wait_until(lock, stop, slice_end, [&q, seen] { return q.generation != seen; }));
  }
}

}  // namespace phm::runtime::queue
