// SPDX-License-Identifier: Apache-2.0
// DiskQueue against real SQLite files: the connection pragmas, recovery after
// reopening, and databases written by a later or an earlier version.
#include <gtest/gtest.h>
#include <sqlite3.h>

#include <filesystem>
#include <phm/runtime/queue/disk_queue.hpp>
#include <string>
#include <vector>

#include "disk_queue_support.hpp"
#include "queue/schema.hpp"

namespace phm::runtime::queue::test {
namespace {

TEST(DiskQueueSchema, OpenSetsWalAndSynchronousFull) {
  const TempDir dir;
  const auto queue = open_queue(dir.database());
  ASSERT_NE(queue, nullptr);
  // journal_mode = WAL is stored in the file, so any connection reports it.
  const RawConnection other(dir.database());
  EXPECT_EQ(other.query_text("PRAGMA journal_mode"), "wal");
  EXPECT_EQ(other.query_text("PRAGMA user_version"), "1");
  // synchronous is per connection: check it on a connection set up the way
  // open() sets up both of its own.
  const RawConnection configured(dir.database());
  ASSERT_EQ(detail::configure_connection(configured.get()), SQLITE_OK);
  EXPECT_EQ(configured.query_text("PRAGMA journal_mode"), "wal");
  EXPECT_EQ(configured.query_text("PRAGMA synchronous"), "2");
  // Nothing is written beside the version 1 tables.
  EXPECT_EQ(other.query_text("SELECT group_concat(name, ',') FROM (SELECT name FROM sqlite_master "
                             "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name)"),
            "queue_drop_record,queue_items");
}

TEST(DiskQueueSchema, ReopenRecoversItemsInOrderAndTheDropRecord) {
  const TempDir dir;
  const auto rows = load_operations();
  std::vector<StoredItem> items_before;
  DropRecord record_before;
  Watermark mark_before;
  {
    const auto queue = open_queue(dir.database());
    ASSERT_NE(queue, nullptr);
    run_rows(*queue, rows, 0, rows.size());
    items_before = queue->peek_batch(100).value();
    record_before = queue->drop_record().value();
    mark_before = queue->watermark().value();
  }
  const auto queue = open_queue(dir.database());
  ASSERT_NE(queue, nullptr);
  EXPECT_EQ(
      keys_of(queue->peek_batch(100).value()),
      (std::vector<std::string>{"item-0002", "item-0003", "item-0005", "item-0008", "item-0009"}));
  EXPECT_EQ(queue->peek_batch(100).value(), items_before);
  EXPECT_EQ(queue->drop_record().value(), record_before);
  EXPECT_EQ(queue->watermark().value(), mark_before);
}

TEST(DiskQueueSchema, ReopenKeepsAnOpenDropPeriod) {
  const TempDir dir;
  const auto payload = hex_bytes("01");
  {
    const auto queue = open_queue(dir.database());
    ASSERT_NE(queue, nullptr);
    ASSERT_EQ(queue->enqueue(new_item("item-0001", kT0, payload)).value(), EnqueueOutcome::stored);
    ASSERT_EQ(queue->enqueue(new_item("item-0002", kT0 + 61'000, payload)).value(),
              EnqueueOutcome::stored);
    ASSERT_EQ(queue->enqueue(new_item("item-0003", kT0 + 62'000, payload)).value(),
              EnqueueOutcome::rejected_full);
  }
  const auto queue = open_queue(dir.database());
  ASSERT_NE(queue, nullptr);
  ASSERT_EQ(queue->enqueue(new_item("item-0004", kT0 + 63'000, payload)).value(),
            EnqueueOutcome::rejected_full);
  EXPECT_EQ(queue->drop_record().value(),
            (DropRecord{true, 2, at_ms(kT0 + 62'000), at_ms(kT0 + 63'000)}));
}

TEST(DiskQueueSchema, DatabaseOfALaterVersionIsReadAndWritten) {
  const TempDir dir;
  {
    const RawConnection setup(dir.database());
    setup.exec(read_file(fixture_path("disk_queue/future_schema.sql")));
  }
  const auto queue = open_queue(dir.database());
  ASSERT_NE(queue, nullptr);
  EXPECT_EQ(queue->peek_batch(10).value(),
            (std::vector<StoredItem>{stored_item("fut-0001", kT0, "01"),
                                     stored_item("fut-0002", std::nullopt, "0203")}));
  const auto payload = hex_bytes("05");
  ASSERT_EQ(queue->enqueue(new_item("item-0001", kT0 + 1'000, payload)).value(),
            EnqueueOutcome::stored);
  ASSERT_EQ(queue->remove("fut-0001").value(), RemoveOutcome::removed);
  EXPECT_EQ(queue->drop_record().value(),
            (DropRecord{false, 1, at_ms(1767225500000), at_ms(1767225500000)}));

  const RawConnection other(dir.database());
  // item_key 'item-0001' as a blob.
  EXPECT_EQ(other.query_text("SELECT count(seq) FROM queue_items "
                             "WHERE item_key = X'6974656d2d30303031' AND origin IS NULL"),
            "1");
  EXPECT_EQ(other.query_text("PRAGMA user_version"), "2");
  EXPECT_EQ(other.query_text("SELECT count(item_seq) FROM queue_annotations"), "1");
}

TEST(DiskQueueSchema, RowsWithoutTheNewestColumnsAreRead) {
  const TempDir dir;
  {
    const RawConnection setup(dir.database());
    setup.exec(read_file(fixture_path("disk_queue/rows_without_new_columns.sql")));
  }
  const auto queue = open_queue(dir.database());
  ASSERT_NE(queue, nullptr);
  EXPECT_EQ(queue->peek_batch(10).value(),
            (std::vector<StoredItem>{stored_item("old-0001", kT0, "aa"),
                                     stored_item("old-0002", kT0 + 5'000, "bbcc")}));
  EXPECT_EQ(queue->watermark().value(), (Watermark{2, 3, at_ms(kT0)}));
  EXPECT_EQ(queue->drop_record().value(), (DropRecord{false, 0, std::nullopt, std::nullopt}));
}

}  // namespace
}  // namespace phm::runtime::queue::test
