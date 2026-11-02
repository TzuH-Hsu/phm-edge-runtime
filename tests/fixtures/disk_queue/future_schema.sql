-- SPDX-License-Identifier: Apache-2.0
-- A later version's database: one extra column and one extra table, user_version 2.
CREATE TABLE queue_items (
  seq          INTEGER PRIMARY KEY AUTOINCREMENT,
  item_key     BLOB    NOT NULL UNIQUE,
  timestamp_ms INTEGER,
  payload      BLOB    NOT NULL,
  origin       TEXT
);
CREATE INDEX queue_items_timestamp ON queue_items (timestamp_ms);
CREATE TABLE queue_drop_record (
  id              INTEGER PRIMARY KEY,
  dropped_total   INTEGER NOT NULL DEFAULT 0,
  dropped_from_ms INTEGER,
  dropped_to_ms   INTEGER,
  period_open     INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE queue_annotations (
  item_seq INTEGER NOT NULL,
  note     TEXT
);
INSERT INTO queue_drop_record (id, dropped_total, dropped_from_ms, dropped_to_ms, period_open)
  VALUES (1, 1, 1767225500000, 1767225500000, 0);
INSERT INTO queue_items (item_key, timestamp_ms, payload, origin)
  VALUES (X'6675742d30303031', 1767225600000, X'01', 'later-version');
INSERT INTO queue_items (item_key, timestamp_ms, payload, origin)
  VALUES (X'6675742d30303032', NULL, X'0203', NULL);
INSERT INTO queue_annotations (item_seq, note) VALUES (1, 'kept by the later version');
PRAGMA user_version = 2;
