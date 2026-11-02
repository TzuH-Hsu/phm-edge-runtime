// SPDX-License-Identifier: Apache-2.0
// Behaviour of DiskQueue: order, removal, the span bound, the drop record,
// limits, error results and waking a waiting consumer.
#include <gtest/gtest.h>
#include <sqlite3.h>

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <future>
#include <phm/runtime/queue/disk_queue.hpp>
#include <span>
#include <stop_token>
#include <string>
#include <thread>
#include <vector>

#include "disk_queue_support.hpp"

namespace phm::runtime::queue::test {
namespace {

using std::chrono::milliseconds;
using std::chrono::seconds;

// open() takes no default span: a call with the path alone does not compile.
template <typename Path>
concept OpenableWithoutSpan = requires(const Path& path) { DiskQueue::open(path); };
static_assert(!OpenableWithoutSpan<std::filesystem::path>);

// The fixture's members are shared with the TEST_F bodies, as GoogleTest intends.
// NOLINTBEGIN(cppcoreguidelines-non-private-member-variables-in-classes,misc-non-private-member-variables-in-classes)
class DiskQueueTest : public ::testing::Test {
 protected:
  void SetUp() override {
    queue_ = open_queue(dir_.database());
    ASSERT_NE(queue_, nullptr);
    rows_ = load_operations();
    ASSERT_EQ(rows_.size(), 14U);
  }

  [[nodiscard]] std::vector<StoredItem> all_items() const {
    auto items = queue_->peek_batch(100);
    EXPECT_TRUE(items.has_value());
    return items ? items.value() : std::vector<StoredItem>{};
  }

  TempDir dir_;
  std::unique_ptr<DiskQueue> queue_;
  std::vector<OperationRow> rows_;
};
// NOLINTEND(cppcoreguidelines-non-private-member-variables-in-classes,misc-non-private-member-variables-in-classes)

TEST_F(DiskQueueTest, NewQueueIsEmpty) {
  EXPECT_EQ(queue_->watermark().value(), (Watermark{0, 0, std::nullopt}));
  EXPECT_EQ(queue_->drop_record().value(), (DropRecord{false, 0, std::nullopt, std::nullopt}));
  EXPECT_FALSE(queue_->is_full().value());
  EXPECT_EQ(queue_->peek_head().value(), std::nullopt);
  EXPECT_TRUE(queue_->peek_batch(5).value().empty());
}

TEST_F(DiskQueueTest, FixtureRowsGiveTheExpectedResults) {
  run_rows(*queue_, rows_, 0, rows_.size());
}

TEST_F(DiskQueueTest, ItemsAreReadInWriteOrderAndReadingRemovesNothing) {
  run_rows(*queue_, rows_, 0, 5);
  EXPECT_EQ(queue_->watermark().value(), (Watermark{5, 13, at_ms(kT0)}));
  EXPECT_EQ(queue_->peek_head().value(), stored_item("item-0001", kT0, "00"));
  const std::vector<StoredItem> expected{
      stored_item("item-0001", kT0, "00"),
      stored_item("item-0002", kT0 + 30'000, "0001ff00"),
      stored_item("item-0003", std::nullopt, ""),
      stored_item("item-0004", kT0 + 60'000, "7b2276223a317d"),
      stored_item("item-0005", kT0 + 61'000, "ff"),
  };
  EXPECT_EQ(queue_->peek_batch(10).value(), expected);
  // Reading again returns the same items: nothing was removed.
  EXPECT_EQ(queue_->peek_batch(10).value(), expected);
  EXPECT_EQ(queue_->watermark().value().item_count, 5);
}

TEST_F(DiskQueueTest, BatchReadReturnsAtMostNItemsFromTheHead) {
  run_rows(*queue_, rows_, 0, 5);
  EXPECT_EQ(keys_of(queue_->peek_batch(2).value()),
            (std::vector<std::string>{"item-0001", "item-0002"}));
  EXPECT_EQ(queue_->peek_batch(10).value().size(), 5U);
  const auto zero = queue_->peek_batch(0);
  ASSERT_FALSE(zero.has_value());
  EXPECT_EQ(zero.error().code, QueueErrc::invalid_argument);
}

TEST_F(DiskQueueTest, BatchOfOneOnAQueueOfOne) {
  const auto payload = hex_bytes("01");
  ASSERT_EQ(queue_->enqueue(new_item("item-0001", kT0, payload)).value(), EnqueueOutcome::stored);
  EXPECT_EQ(queue_->peek_batch(1).value(),
            (std::vector<StoredItem>{stored_item("item-0001", kT0, "01")}));
}

TEST_F(DiskQueueTest, OnlyTheDeletedItemDisappears) {
  run_rows(*queue_, rows_, 0, 5);
  ASSERT_EQ(queue_->remove("item-0003").value(), RemoveOutcome::removed);
  EXPECT_EQ(keys_of(all_items()),
            (std::vector<std::string>{"item-0001", "item-0002", "item-0004", "item-0005"}));
}

TEST_F(DiskQueueTest, SpanEqualToTheBoundIsNotFull) {
  run_rows(*queue_, rows_, 0, 4);  // T0 .. T0+60 s: exactly the span
  EXPECT_FALSE(queue_->is_full().value());
  run_rows(*queue_, rows_, 4, 5);  // row 5 is stored and widens the span to 61 s
  EXPECT_TRUE(queue_->is_full().value());
}

TEST_F(DiskQueueTest, FullQueueRefusesNonExemptItemsAndKeepsTheStoredOnes) {
  run_rows(*queue_, rows_, 0, 5);
  const auto before = all_items();
  run_rows(*queue_, rows_, 5, 7);  // rows 6 and 7: rejected_full
  EXPECT_EQ(all_items(), before);
  EXPECT_EQ(queue_->drop_record().value(),
            (DropRecord{true, 2, at_ms(kT0 + 62'000), at_ms(kT0 + 63'000)}));
  run_rows(*queue_, rows_, 7, 8);  // row 8: an exempt item is stored while full
  EXPECT_EQ(all_items().size(), 6U);
  EXPECT_EQ(queue_->drop_record().value().dropped_total, 2);
}

TEST_F(DiskQueueTest, DuplicateKeyWhileFullIsAlreadyStoredAndNotADrop) {
  run_rows(*queue_, rows_, 0, 9);  // row 9: item-0002 again
  const auto items = all_items();
  ASSERT_GE(items.size(), 2U);
  EXPECT_EQ(items[1], stored_item("item-0002", kT0 + 30'000, "0001ff00"));
  EXPECT_EQ(queue_->drop_record().value().dropped_total, 2);
}

TEST_F(DiskQueueTest, EndStateMatchesTheFixture) {
  run_rows(*queue_, rows_, 0, rows_.size());
  EXPECT_EQ(keys_of(all_items()), (std::vector<std::string>{"item-0002", "item-0003", "item-0005",
                                                            "item-0008", "item-0009"}));
  EXPECT_EQ(queue_->watermark().value(), (Watermark{5, 10, at_ms(kT0 + 30'000)}));
  EXPECT_EQ(queue_->drop_record().value(),
            (DropRecord{false, 3, at_ms(kT0 + 60'000), at_ms(kT0 + 60'000)}));
}

TEST_F(DiskQueueTest, StoringAnExemptItemDoesNotEndTheDropPeriod) {
  run_rows(*queue_, rows_, 0, 7);  // a period T0+62 s .. T0+63 s is open
  const auto exempt = hex_bytes("aa");
  ASSERT_EQ(queue_->enqueue(new_item("item-0100", std::nullopt, exempt)).value(),
            EnqueueOutcome::stored);
  // The next refusal extends the open period instead of starting a new one.
  const auto payload = hex_bytes("bb");
  ASSERT_EQ(queue_->enqueue(new_item("item-0101", kT0 + 64'000, payload)).value(),
            EnqueueOutcome::rejected_full);
  EXPECT_EQ(queue_->drop_record().value(),
            (DropRecord{true, 3, at_ms(kT0 + 62'000), at_ms(kT0 + 64'000)}));
}

TEST_F(DiskQueueTest, RemoveAsDroppedOnAnExemptItemChangesNothing) {
  run_rows(*queue_, rows_, 0, 3);
  const auto before = all_items();
  const auto result = queue_->remove_as_dropped("item-0003");
  ASSERT_FALSE(result.has_value());
  EXPECT_EQ(result.error().code, QueueErrc::exempt_not_droppable);
  EXPECT_EQ(all_items(), before);
  EXPECT_EQ(queue_->drop_record().value().dropped_total, 0);
}

TEST_F(DiskQueueTest, RemovingItemsCanEndTheFullState) {
  run_rows(*queue_, rows_, 0, 5);
  ASSERT_TRUE(queue_->is_full().value());
  ASSERT_EQ(queue_->remove("item-0001").value(), RemoveOutcome::removed);
  EXPECT_FALSE(queue_->is_full().value());
}

// GoogleTest's assertion macros count as branches; the test itself is linear.
// NOLINTNEXTLINE(readability-function-cognitive-complexity)
TEST_F(DiskQueueTest, ArbitraryBytesRoundTripUnchanged) {
  std::vector<std::byte> every_value;
  for (int b = 0; b <= 0xff; ++b) {
    every_value.push_back(static_cast<std::byte>(b));
  }
  const auto zeros = hex_bytes("000000ff00");
  const std::vector<std::byte> empty;
  ASSERT_EQ(queue_->enqueue(new_item("bytes-all", kT0, every_value)).value(),
            EnqueueOutcome::stored);
  ASSERT_EQ(queue_->enqueue(new_item("bytes-zero", kT0, zeros)).value(), EnqueueOutcome::stored);
  ASSERT_EQ(queue_->enqueue(new_item("bytes-empty", std::nullopt, empty)).value(),
            EnqueueOutcome::stored);
  const auto items = all_items();
  ASSERT_EQ(items.size(), 3U);
  EXPECT_EQ(items[0].payload, every_value);
  EXPECT_EQ(items[1].payload, zeros);
  EXPECT_TRUE(items[2].payload.empty());
  EXPECT_EQ(queue_->watermark().value().payload_bytes, 256 + 5);
}

TEST_F(DiskQueueTest, KeyLimits) {
  const auto payload = hex_bytes("01");
  const std::string longest(kMaxKeyBytes, 'k');
  const std::string too_long(kMaxKeyBytes + 1, 'k');
  EXPECT_EQ(queue_->enqueue(new_item(longest, kT0, payload)).value(), EnqueueOutcome::stored);
  EXPECT_EQ(queue_->enqueue(new_item(too_long, kT0, payload)).error().code,
            QueueErrc::invalid_argument);
  EXPECT_EQ(queue_->enqueue(new_item("", kT0, payload)).error().code, QueueErrc::invalid_argument);
  EXPECT_EQ(queue_->remove("").error().code, QueueErrc::invalid_argument);
  EXPECT_EQ(queue_->remove_as_dropped(too_long).error().code, QueueErrc::invalid_argument);
  EXPECT_EQ(all_items().size(), 1U);
}

// kMaxPayloadBytes is checked against a real row: the longest key with the
// largest payload is written, one byte more is refused before any write.
// Needs about 2 GB of memory and 1 GB of disk.
// NOLINTNEXTLINE(readability-function-cognitive-complexity)
TEST_F(DiskQueueTest, LargestPayloadIsWritableAndOneByteMoreIsInvalid) {
  const std::vector<std::byte> payload(kMaxPayloadBytes + 1, std::byte{0x5a});
  const std::span<const std::byte> largest{payload.data(), kMaxPayloadBytes};
  const std::string key(kMaxKeyBytes, 'k');
  const std::string other_key(kMaxKeyBytes, 'o');
  const auto stored = queue_->enqueue(NewItem{key, at_ms(kT0), largest});
  ASSERT_TRUE(stored.has_value()) << stored.error().message;
  EXPECT_EQ(stored.value(), EnqueueOutcome::stored);
  const auto too_large = queue_->enqueue(NewItem{other_key, at_ms(kT0), payload});
  ASSERT_FALSE(too_large.has_value());
  EXPECT_EQ(too_large.error().code, QueueErrc::invalid_argument);
  const auto depth = queue_->watermark().value();
  EXPECT_EQ(depth.item_count, 1);
  EXPECT_EQ(depth.payload_bytes, static_cast<std::int64_t>(kMaxPayloadBytes));
}

TEST_F(DiskQueueTest, KeysAreComparedByteForByte) {
  const auto payload = hex_bytes("01");
  const std::string with_zero{"key\0a", 5};
  const std::string other_zero{"key\0b", 5};
  EXPECT_EQ(queue_->enqueue(new_item(with_zero, kT0, payload)).value(), EnqueueOutcome::stored);
  EXPECT_EQ(queue_->enqueue(new_item(other_zero, kT0, payload)).value(), EnqueueOutcome::stored);
  EXPECT_EQ(queue_->enqueue(new_item("key", kT0, payload)).value(), EnqueueOutcome::stored);
  EXPECT_EQ(keys_of(all_items()), (std::vector<std::string>{with_zero, other_zero, "key"}));
}

TEST_F(DiskQueueTest, ARemovedKeyCanBeUsedAgainAndGoesToTheTail) {
  const auto payload = hex_bytes("01");
  ASSERT_EQ(queue_->enqueue(new_item("item-0001", kT0, payload)).value(), EnqueueOutcome::stored);
  ASSERT_EQ(queue_->enqueue(new_item("item-0002", kT0, payload)).value(), EnqueueOutcome::stored);
  ASSERT_EQ(queue_->remove("item-0001").value(), RemoveOutcome::removed);
  ASSERT_EQ(queue_->enqueue(new_item("item-0001", kT0, payload)).value(), EnqueueOutcome::stored);
  EXPECT_EQ(keys_of(all_items()), (std::vector<std::string>{"item-0002", "item-0001"}));
}

// GoogleTest's assertion macros count as branches; the test itself is linear.
// NOLINTNEXTLINE(readability-function-cognitive-complexity)
TEST_F(DiskQueueTest, LockedDatabaseIsWriteFailedNotRejectedFull) {
  const auto payload = hex_bytes("01");
  // Make the queue full first, so a wrong answer would be rejected_full.
  ASSERT_EQ(queue_->enqueue(new_item("item-0001", kT0, payload)).value(), EnqueueOutcome::stored);
  ASSERT_EQ(queue_->enqueue(new_item("item-0002", kT0 + 61'000, payload)).value(),
            EnqueueOutcome::stored);
  ASSERT_TRUE(queue_->is_full().value());
  const auto before = all_items();
  {
    const RawConnection other(dir_.database());
    other.exec("BEGIN EXCLUSIVE");
    const auto result = queue_->enqueue(new_item("item-0100", kT0, payload));
    ASSERT_FALSE(result.has_value());
    EXPECT_EQ(result.error().code, QueueErrc::write_failed);
    EXPECT_EQ(result.error().sqlite_code, SQLITE_BUSY);
    const auto removed = queue_->remove("item-0001");
    ASSERT_FALSE(removed.has_value());
    EXPECT_EQ(removed.error().code, QueueErrc::write_failed);
    // Reads do not wait for the other connection's write transaction.
    EXPECT_EQ(all_items(), before);
    other.exec("ROLLBACK");
  }
  EXPECT_EQ(queue_->drop_record().value().dropped_total, 0);
  EXPECT_EQ(all_items(), before);
}

TEST(DiskQueueOpen, SpanOfZeroOrLessIsInvalidAndCreatesNoFile) {
  const TempDir dir;
  for (const seconds span : {seconds{0}, seconds{-1}}) {
    const auto queue = DiskQueue::open(dir.database(), span);
    ASSERT_FALSE(queue.has_value());
    EXPECT_EQ(queue.error().code, QueueErrc::invalid_argument);
    EXPECT_FALSE(std::filesystem::exists(dir.database()));
  }
}

TEST(DiskQueueOpen, FileThatIsNotADatabaseIsOpenFailed) {
  const TempDir dir;
  {
    std::ofstream out(dir.database(), std::ios::binary);
    out << "this is not a database\n";
  }
  const auto queue = DiskQueue::open(dir.database(), kSpan);
  ASSERT_FALSE(queue.has_value());
  EXPECT_EQ(queue.error().code, QueueErrc::open_failed);
  EXPECT_EQ(queue.error().sqlite_code, SQLITE_NOTADB);
}

TEST(DiskQueueOpen, MissingDirectoryIsOpenFailed) {
  const TempDir dir;
  const auto queue = DiskQueue::open(dir.path() / "missing" / "queue.db", kSpan);
  ASSERT_FALSE(queue.has_value());
  EXPECT_EQ(queue.error().code, QueueErrc::open_failed);
}

TEST_F(DiskQueueTest, WaitReturnsAtOnceWhenItemsAreStored) {
  const auto payload = hex_bytes("01");
  ASSERT_EQ(queue_->enqueue(new_item("item-0001", kT0, payload)).value(), EnqueueOutcome::stored);
  const std::stop_source never;
  EXPECT_EQ(queue_->wait_for_items(never.get_token(), milliseconds{0}).value(),
            WaitOutcome::items_available);
}

TEST_F(DiskQueueTest, WaitTimesOutOnAnEmptyQueue) {
  const std::stop_source never;
  EXPECT_EQ(queue_->wait_for_items(never.get_token(), milliseconds{20}).value(),
            WaitOutcome::timed_out);
}

TEST_F(DiskQueueTest, WaitReturnsWhenStopIsRequested) {
  // request_stop() is not const in every standard library.
  // NOLINTNEXTLINE(misc-const-correctness)
  std::stop_source stop;
  auto waiter = std::async(std::launch::async, [this, token = stop.get_token()] {
    return queue_->wait_for_items(token, std::chrono::hours{1});
  });
  stop.request_stop();
  ASSERT_EQ(waiter.wait_for(seconds{30}), std::future_status::ready);
  EXPECT_EQ(waiter.get().value(), WaitOutcome::stop_requested);
}

TEST_F(DiskQueueTest, WaitingConsumerIsWokenByACommittedWrite) {
  const std::stop_source never;
  std::promise<void> started;
  auto waiter = std::async(std::launch::async, [this, &started, token = never.get_token()] {
    started.set_value();
    return queue_->wait_for_items(token, std::chrono::hours{1});
  });
  started.get_future().wait();
  const auto payload = hex_bytes("01");
  ASSERT_EQ(queue_->enqueue(new_item("item-0001", kT0, payload)).value(), EnqueueOutcome::stored);
  // The timeout is an hour: only the wake-up can make the waiter return in time.
  ASSERT_EQ(waiter.wait_for(seconds{30}), std::future_status::ready);
  EXPECT_EQ(waiter.get().value(), WaitOutcome::items_available);
}

// GoogleTest's assertion macros count as branches.
// NOLINTNEXTLINE(readability-function-cognitive-complexity)
TEST_F(DiskQueueTest, OneWriterAndOneSenderKeepTheOrder) {
  constexpr int kItems = 200;
  std::jthread writer([this] {
    const auto payload = hex_bytes("01");
    for (int i = 0; i < kItems; ++i) {
      const std::string key = "item-" + std::to_string(i);
      ASSERT_EQ(queue_->enqueue(new_item(key, std::nullopt, payload)).value(),
                EnqueueOutcome::stored);
    }
  });
  std::vector<std::string> received;
  const std::stop_source never;
  while (received.size() < static_cast<std::size_t>(kItems)) {
    ASSERT_EQ(queue_->wait_for_items(never.get_token(), seconds{30}).value(),
              WaitOutcome::items_available);
    // Keep the result alive: the loop must not iterate over a temporary's member.
    const auto batch = queue_->peek_batch(16);
    ASSERT_TRUE(batch.has_value());
    for (const auto& item : batch.value()) {
      ASSERT_EQ(queue_->remove(item.key).value(), RemoveOutcome::removed);
      received.push_back(item.key);
    }
  }
  writer.join();
  for (int i = 0; i < kItems; ++i) {
    EXPECT_EQ(received[static_cast<std::size_t>(i)], "item-" + std::to_string(i));
  }
  EXPECT_EQ(queue_->watermark().value(), (Watermark{0, 0, std::nullopt}));
}

}  // namespace
}  // namespace phm::runtime::queue::test
