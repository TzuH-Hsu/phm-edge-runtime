// SPDX-License-Identifier: Apache-2.0
#include "queue/schema.hpp"

#include <sqlite3.h>

namespace phm::runtime::queue::detail {
namespace {

// Schema version 1. Every later version only adds tables and nullable or
// defaulted columns, so these statements stay valid on any later database.
constexpr const char* kCreateSchemaSql = R"sql(
CREATE TABLE IF NOT EXISTS queue_items (
  seq          INTEGER PRIMARY KEY AUTOINCREMENT,
  item_key     BLOB    NOT NULL UNIQUE,
  timestamp_ms INTEGER,
  payload      BLOB    NOT NULL
);
CREATE INDEX IF NOT EXISTS queue_items_timestamp ON queue_items (timestamp_ms);
CREATE TABLE IF NOT EXISTS queue_drop_record (
  id              INTEGER PRIMARY KEY,
  dropped_total   INTEGER NOT NULL DEFAULT 0,
  dropped_from_ms INTEGER,
  dropped_to_ms   INTEGER,
  period_open     INTEGER NOT NULL DEFAULT 0
);
INSERT OR IGNORE INTO queue_drop_record (id) VALUES (1);
)sql";

int last_error(sqlite3* db) noexcept { return sqlite3_extended_errcode(db); }

int exec(sqlite3* db, const char* sql) noexcept {
  if (sqlite3_exec(db, sql, nullptr, nullptr, nullptr) != SQLITE_OK) {
    return last_error(db);
  }
  return SQLITE_OK;
}

// Runs a statement that returns one row of one column and hands the column to
// on_row. Returns SQLITE_OK or the extended result code of the failure.
template <typename OnRow>
int query_one(sqlite3* db, const char* sql, OnRow on_row) noexcept {
  sqlite3_stmt* stmt = nullptr;
  if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) != SQLITE_OK) {
    return last_error(db);
  }
  int rc = sqlite3_step(stmt);
  if (rc == SQLITE_ROW) {
    on_row(stmt);
    rc = SQLITE_OK;
  } else {
    rc = last_error(db);
    if (rc == SQLITE_OK) {
      rc = SQLITE_ERROR;  // no row: the pragma did not answer
    }
  }
  sqlite3_finalize(stmt);
  return rc;
}

int user_version(sqlite3* db, int& version) noexcept {
  return query_one(db, "PRAGMA user_version",
                   [&version](sqlite3_stmt* stmt) { version = sqlite3_column_int(stmt, 0); });
}

int create_or_upgrade(sqlite3* db) noexcept {
  if (const int rc = exec(db, kCreateSchemaSql); rc != SQLITE_OK) {
    return rc;
  }
  int version = 0;
  if (const int rc = user_version(db, version); rc != SQLITE_OK) {
    return rc;
  }
  if (version < kSchemaVersion) {
    // kSchemaVersion is 1; PRAGMA takes no bound parameters.
    static_assert(kSchemaVersion == 1, "update the PRAGMA below with the version");
    return exec(db, "PRAGMA user_version = 1");
  }
  return SQLITE_OK;
}

}  // namespace

int configure_connection(sqlite3* db) noexcept {
  bool is_wal = false;
  int rc = query_one(db, "PRAGMA journal_mode = WAL", [&is_wal](sqlite3_stmt* stmt) {
    const void* text = sqlite3_column_text(stmt, 0);
    is_wal = text != nullptr && sqlite3_stricmp(static_cast<const char*>(text), "wal") == 0;
  });
  if (rc != SQLITE_OK) {
    return rc;
  }
  if (!is_wal) {
    return SQLITE_ERROR;
  }
  if (rc = exec(db, "PRAGMA synchronous = FULL"); rc != SQLITE_OK) {
    return rc;
  }
  int synchronous = -1;
  rc = query_one(db, "PRAGMA synchronous",
                 [&synchronous](sqlite3_stmt* stmt) { synchronous = sqlite3_column_int(stmt, 0); });
  if (rc != SQLITE_OK) {
    return rc;
  }
  constexpr int kSynchronousFull = 2;
  return synchronous == kSynchronousFull ? SQLITE_OK : SQLITE_ERROR;
}

int apply_schema(sqlite3* db) noexcept {
  if (const int rc = exec(db, "BEGIN IMMEDIATE"); rc != SQLITE_OK) {
    return rc;
  }
  if (const int rc = create_or_upgrade(db); rc != SQLITE_OK) {
    static_cast<void>(exec(db, "ROLLBACK"));
    return rc;
  }
  if (const int rc = exec(db, "COMMIT"); rc != SQLITE_OK) {
    if (sqlite3_get_autocommit(db) == 0) {
      static_cast<void>(exec(db, "ROLLBACK"));
    }
    return rc;
  }
  return SQLITE_OK;
}

}  // namespace phm::runtime::queue::detail
