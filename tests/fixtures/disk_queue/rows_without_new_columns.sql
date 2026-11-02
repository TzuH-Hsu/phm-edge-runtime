-- SPDX-License-Identifier: Apache-2.0
-- Version 1 tables; the rows name only item_key, timestamp_ms and payload, and the
-- drop record names only id.
CREATE TABLE queue_items (
  seq          INTEGER PRIMARY KEY AUTOINCREMENT,
  item_key     BLOB    NOT NULL UNIQUE,
  timestamp_ms INTEGER,
  payload      BLOB    NOT NULL
);
CREATE INDEX queue_items_timestamp ON queue_items (timestamp_ms);
CREATE TABLE queue_drop_record (
  id              INTEGER PRIMARY KEY,
  dropped_total   INTEGER NOT NULL DEFAULT 0,
  dropped_from_ms INTEGER,
  dropped_to_ms   INTEGER,
  period_open     INTEGER NOT NULL DEFAULT 0
);
INSERT INTO queue_drop_record (id) VALUES (1);
INSERT INTO queue_items (item_key, timestamp_ms, payload) VALUES (X'6f6c642d30303031', 1767225600000, X'aa');
INSERT INTO queue_items (item_key, timestamp_ms, payload) VALUES (X'6f6c642d30303032', 1767225605000, X'bbcc');
PRAGMA user_version = 1;
