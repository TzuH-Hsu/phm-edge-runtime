// SPDX-License-Identifier: Apache-2.0
// Private to the library: connection setup, schema creation and the add-only
// schema upgrade of the disk queue's SQLite database.
#pragma once

struct sqlite3;

namespace phm::runtime::queue::detail {

// The schema version this code writes. A database with a higher
// PRAGMA user_version was extended by a later version; it is used as is.
inline constexpr int kSchemaVersion = 1;

// Sets PRAGMA journal_mode = WAL and PRAGMA synchronous = FULL on one
// connection and reads both back. Returns SQLITE_OK, the extended result code
// of the statement that failed, or SQLITE_ERROR when a pragma reads back a
// different value.
[[nodiscard]] int configure_connection(sqlite3* db) noexcept;

// Creates the version 1 tables and index when they are missing, inserts the
// one drop record row when it is missing and raises PRAGMA user_version to
// kSchemaVersion when it is lower, all in one transaction. Tables, columns and
// a higher user_version written by a later version are left untouched.
// Returns SQLITE_OK or the extended result code of the statement that failed;
// on failure nothing is changed.
[[nodiscard]] int apply_schema(sqlite3* db) noexcept;

}  // namespace phm::runtime::queue::detail
