// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <span>
#include <stop_token>
#include <string>
#include <string_view>
#include <vector>

#include "phm/runtime/result.hpp"

namespace phm::runtime::queue {

// Caller-supplied item time, UTC, millisecond resolution. Stored as an
// INTEGER of milliseconds since 1970-01-01T00:00:00Z. Need not be monotonic.
using Timestamp = std::chrono::sys_time<std::chrono::milliseconds>;

// Limits checked before anything is written.
inline constexpr std::size_t kMaxKeyBytes = 256;
// SQLite's default SQLITE_MAX_LENGTH. It caps a whole row, not only one BLOB;
// open() fails when the linked SQLite allows less.
inline constexpr std::size_t kMaxRowBytes = 1'000'000'000;
// A schema version 1 row is a record header of at most 10 bytes (its own size
// and one serial type each for seq, item_key, timestamp_ms and payload), an
// 8-byte timestamp, the key and the payload. 1 KiB covers the 18 bytes and
// leaves room for the columns a later schema version may add.
inline constexpr std::size_t kRowOverheadBytes = 1024;
inline constexpr std::size_t kMaxPayloadBytes = kMaxRowBytes - kMaxKeyBytes - kRowOverheadBytes;
inline constexpr std::int32_t kMaxItemCount = 2'147'483'647;

// One item to enqueue. The views must stay valid for the duration of the call.
struct NewItem {
  std::string_view key;                // idempotency key, 1 to kMaxKeyBytes opaque bytes
  std::optional<Timestamp> timestamp;  // empty: the item is exempt from the span bound
  std::span<const std::byte> payload;  // 0..kMaxPayloadBytes opaque bytes, stored as is
};

// One stored item, as read back.
struct StoredItem {
  std::string key;
  std::optional<Timestamp> timestamp;  // empty: exempt
  std::vector<std::byte> payload;

  friend bool operator==(const StoredItem&, const StoredItem&) = default;
};

enum class EnqueueOutcome : std::uint8_t {
  stored,          // committed; a waiting consumer is woken
  already_stored,  // an item with this key is stored; nothing written, nothing counted
  rejected_full,   // the queue is full; nothing written; counted in the drop record
};

enum class RemoveOutcome : std::uint8_t {
  removed,    // the item is gone (committed)
  not_found,  // no stored item has this key; nothing changed
};

enum class WaitOutcome : std::uint8_t {
  items_available,  // at least one item is stored
  timed_out,        // the timeout elapsed with the queue empty
  stop_requested,   // the stop token was triggered
};

// Contract table "Depth".
struct Watermark {
  std::int32_t item_count = 0;      // 0..kMaxItemCount, exempt items included
  std::int64_t payload_bytes = 0;   // sum of the stored payload sizes
  std::optional<Timestamp> oldest;  // smallest timestamp of a stored non-exempt item

  friend bool operator==(const Watermark&, const Watermark&) = default;
};

// Contract table "Drop record". Persistent; never reset.
struct DropRecord {
  bool full = false;                      // the queue is full now
  std::int64_t dropped_total = 0;         // refusals plus deletions counted as dropped
  std::optional<Timestamp> dropped_from;  // first dropped item of the most recent drop period
  std::optional<Timestamp> dropped_to;    // last dropped item of the most recent drop period

  friend bool operator==(const DropRecord&, const DropRecord&) = default;
};

enum class QueueErrc : std::uint8_t {
  invalid_argument,      // bad key, payload size, span or batch size; nothing touched
  open_failed,           // the file cannot be opened or created, is not a SQLite database,
                         // WAL / synchronous FULL / the schema could not be applied, or
                         // the linked SQLite's length limit is below kMaxRowBytes
  write_failed,          // a write transaction did not commit; nothing changed
  read_failed,           // a read statement failed
  item_limit_reached,    // kMaxItemCount items are stored; not counted as a drop
  exempt_not_droppable,  // remove_as_dropped() on an exempt item; nothing changed
};

struct QueueError {
  QueueErrc code;
  int sqlite_code = 0;    // extended SQLite result code; 0 when the error is not from SQLite
  std::string message{};  // NOLINT(readability-redundant-member-init): for logs; wording not stable
};

template <typename T>
using QueueResult = Result<T, QueueError>;

// Disk-backed FIFO queue of opaque items in one SQLite database file.
// Thread-safe: every member function may be called concurrently from any
// thread. Reads never wait for a write to commit; writes are serialised.
class DiskQueue {
 public:
  // Opens or creates the database at database_path. capacity_span must be
  // greater than zero; there is no default.
  [[nodiscard]] static QueueResult<std::unique_ptr<DiskQueue>> open(
      const std::filesystem::path& database_path, std::chrono::seconds capacity_span);

  DiskQueue(const DiskQueue&) = delete;
  DiskQueue& operator=(const DiskQueue&) = delete;
  DiskQueue(DiskQueue&&) = delete;
  DiskQueue& operator=(DiskQueue&&) = delete;
  ~DiskQueue();  // closes both connections; no call may be in progress

  // Appends an item at the tail, unless the key is already stored or the
  // queue is full and the item is not exempt.
  [[nodiscard]] QueueResult<EnqueueOutcome> enqueue(const NewItem& item);

  // The head item without removing it; empty when the queue is empty.
  [[nodiscard]] QueueResult<std::optional<StoredItem>> peek_head() const;

  // Up to max_items items from the head, in write order, without removing
  // them. max_items must be at least 1.
  [[nodiscard]] QueueResult<std::vector<StoredItem>> peek_batch(std::size_t max_items) const;

  // Deletes the item with this key, wherever it is in the queue.
  [[nodiscard]] QueueResult<RemoveOutcome> remove(std::string_view key);

  // Deletes the item with this key and counts it in the drop record.
  // Exempt items cannot be counted: exempt_not_droppable.
  [[nodiscard]] QueueResult<RemoveOutcome> remove_as_dropped(std::string_view key);

  [[nodiscard]] QueueResult<Watermark> watermark() const;
  [[nodiscard]] QueueResult<DropRecord> drop_record() const;
  [[nodiscard]] QueueResult<bool> is_full() const;

  // Blocks until at least one item is stored, the timeout elapses or stop is
  // requested. Returns at once when the queue is not empty. Woken by
  // enqueue() on this object.
  [[nodiscard]] QueueResult<WaitOutcome> wait_for_items(std::stop_token stop,
                                                        std::chrono::milliseconds timeout) const;

 private:
  struct Impl;
  explicit DiskQueue(std::unique_ptr<Impl> impl);
  std::unique_ptr<Impl> impl_;
};

}  // namespace phm::runtime::queue
