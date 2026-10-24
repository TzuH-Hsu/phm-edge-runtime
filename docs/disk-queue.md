# Disk queue

`phm::runtime::queue::DiskQueue` is a FIFO queue of opaque items kept in one SQLite database file. An application uses it to hold what it has collected until the receiver has acknowledged it: nothing accepted is lost on a restart or a power cut, items leave in the order they were written, the disk used is bounded by a time span, and every item the queue had to refuse is counted. The public header is [`include/phm/runtime/queue/disk_queue.hpp`](../include/phm/runtime/queue/disk_queue.hpp); every fallible call returns `phm::runtime::Result<T, QueueError>` ([`include/phm/runtime/result.hpp`](../include/phm/runtime/result.hpp)) and no exception crosses the API apart from `std::bad_alloc`.

```cpp
auto opened = DiskQueue::open("/var/lib/example/queue.db", std::chrono::seconds{3600});
if (!opened) { /* opened.error().code, .sqlite_code, .message */ }
auto queue = std::move(opened).value();

const std::vector<std::byte> payload = /* ... */;
queue->enqueue({"sample-000042", Timestamp{std::chrono::milliseconds{1767225600000}}, payload});

// Sender thread
queue->wait_for_items(stop_token, std::chrono::seconds{5});
auto batch = queue->peek_batch(32);   // nothing is removed by reading
queue->remove("sample-000042");       // after the receiver acknowledged it
```

## Storage

- One database file, path given by the caller; the directory must exist. The `-wal` and `-shm` files next to it are created as needed.
- Both connections run with `PRAGMA journal_mode = WAL` and `PRAGMA synchronous = FULL`, read back after setting; any other answer fails `open` with `open_failed`. A write counts as stored only once its transaction has committed.
- Payloads are stored byte for byte as `BLOB`s and never parsed. Opening an existing file recovers every item that was not deleted, in its original order.

## Order, keys and removal

- Items are read in write order: `peek_head()` or `peek_batch(n)` (at most `n` items from the head, `n` at least 1). Reading removes nothing; there is no put-at-head operation.
- **Item key** (an open item of the original design, decided as proposed): every item carries a caller-supplied key of 1 to 256 bytes, compared byte for byte and unique among stored items. Items are removed by key with `remove(key)` or `remove_as_dropped(key)`, so the caller needs no identifier from the library. Enqueueing a key that is already stored returns `already_stored`, writes nothing, leaves the stored item unchanged, counts nothing and does not end a drop period; this check comes before the full check. A writer that crashed after a commit but before recording it can therefore retry the same item safely. Once removed, a key may be used again; the new item goes to the tail.

## Capacity

- Each non-exempt item carries a caller-supplied timestamp (`std::chrono::sys_time<std::chrono::milliseconds>`, stored as milliseconds since the Unix epoch). Timestamps need not increase; the queue order is write order.
- The queue is **full** when the largest and the smallest timestamp of the stored non-exempt items differ by strictly more than the span given to `open`. With fewer than two non-exempt items it is not full. The decision is made on the state before the new item: the item that widens the difference past the span is stored, and the next non-exempt item is refused with `rejected_full`. Nothing already stored is removed; removing items can end the full state.
- An item enqueued without a timestamp is **exempt**: it is stored even while the queue is full and is not part of the span.
- The span has no built-in value and is not stored in the database; every `open` uses the span it is given. A span below one second is `invalid_argument`.
- At 2,147,483,647 stored items `enqueue` returns `item_limit_reached`. A non-exempt item that arrives while the queue is also full is refused as `rejected_full` first, because the full check comes before the limit check.

## Drop record

`drop_record()` returns `full`, `dropped_total` and `dropped_from` / `dropped_to`, kept in the same database and never reset.

- A **drop** is a `rejected_full` result or a successful `remove_as_dropped`. Each adds one to `dropped_total`.
- **Drop period** (an open item of the original design, decided as proposed): a drop when no period is open starts one, and `dropped_from` and `dropped_to` both become that item's timestamp; a drop while a period is open sets `dropped_to`. A period ends when `enqueue` returns `stored` for a non-exempt item; storing an exempt item and `already_stored` do not end it. Whether a period is open is stored with the record, so a restart does not end it.
- An exempt item has no timestamp to record, so `remove_as_dropped` on it fails with `exempt_not_droppable` and changes nothing; delete it with `remove`.

`watermark()` reports `item_count` (every stored item), `payload_bytes` (payload sizes only) and `oldest` (the smallest stored non-exempt timestamp).

## Errors

| `QueueErrc` | Meaning |
| --- | --- |
| `invalid_argument` | Bad key, payload size, span or batch size; nothing was read or written |
| `open_failed` | The file cannot be opened or created, is not a SQLite database (`sqlite_code` 26), or WAL, synchronous FULL or the schema could not be applied |
| `write_failed` | The write transaction did not commit; nothing changed and nothing was counted as a drop |
| `read_failed` | A read statement failed |
| `item_limit_reached` | 2,147,483,647 items are stored; not a drop |
| `exempt_not_droppable` | `remove_as_dropped` on an exempt item |

A full queue is never an error, and a failed write is never `rejected_full`. `sqlite_code` carries the extended SQLite result code when the failure comes from SQLite.

## Threads and lifetime

- Every member function may be called from any thread. Inside, one connection serves the writes (`enqueue`, `remove`, `remove_as_dropped`), serialised by a mutex, and another serves the reads; in WAL mode a read never waits for a write to commit.
- `wait_for_items(stop, timeout)` returns at once when the queue is not empty, and otherwise when an `enqueue` on the same object commits, the timeout elapses or stop is requested. A negative timeout is treated as zero.
- One file is opened by one `DiskQueue` at a time. Because the queue is the only writer of its file, the write connection has no busy timeout: a database locked by anything else fails at once with `write_failed`.
- Destroying the queue closes both connections. No call may still be running, and no thread may still be waiting in `wait_for_items` (request stop on its token first).

## Schema

`PRAGMA user_version` records the schema version; this code writes version 1:

| Table | Columns |
| --- | --- |
| `queue_items` | `seq INTEGER PRIMARY KEY AUTOINCREMENT` (write order, never reused), `item_key BLOB NOT NULL UNIQUE`, `timestamp_ms INTEGER` (NULL: exempt), `payload BLOB NOT NULL`; index `queue_items_timestamp` on `timestamp_ms` |
| `queue_drop_record` | One row, `id = 1`: `dropped_total`, `dropped_from_ms`, `dropped_to_ms`, `period_open` |

The schema only grows, so that after an application rollback an older version can keep using a database a newer version has extended:

- Tables and columns are added, never changed or removed; every table, column and index an older version uses is kept.
- A new column is nullable or has a default. No `NOT NULL` column without a default, and no trigger, check or foreign key that would make an older version's `INSERT`, `UPDATE` or `DELETE` fail.
- `open` creates the version 1 tables when they are missing and raises `user_version` to 1 when it is lower. When it is higher, `open` leaves it, uses the tables and columns it knows and ignores the rest.
- Every statement names its columns: `INSERT` lists them and reads never select every column. `scripts/check-sql.py`, run by `make check`, fails on either pattern in any file under `src/`.
- Incompatible schema changes are not supported.

The tests keep one fixture database in the shape of a later version (an extra column and table, `user_version` 2) and one with rows that name only the version 1 columns: [`tests/fixtures/disk_queue/`](../tests/fixtures/disk_queue/).
