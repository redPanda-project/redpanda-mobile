import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:redpanda/database/database.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

bool _overrideApplied = false;

/// Opens an in-memory [AppDatabase] for tests.
///
/// On Linux the sqlite3 package only tries `libsqlite3.so`, which requires
/// the dev package; fall back to the runtime library `libsqlite3.so.0`.
AppDatabase createTestDatabase() {
  _ensureSqlite3();
  return AppDatabase.forTesting(NativeDatabase.memory());
}

/// Opens an [AppDatabase] on top of an in-memory database that already holds
/// [ddl] and reports `user_version = version`.
///
/// Drift therefore runs the REAL `onUpgrade(version, schemaVersion)` when the
/// database is first used — the exact code path a phone takes after an update
/// (T124/TD149), including the `user_version` bump that only happens when the
/// whole migration succeeded.
///
/// [onRawDatabase] receives the underlying sqlite3 handle, so a test can
/// inspect the database even after a migration failure has made drift refuse
/// every further query.
AppDatabase createTestDatabaseAtVersion(
  int version,
  List<String> ddl, {
  void Function(Database raw)? onRawDatabase,
}) {
  _ensureSqlite3();
  return AppDatabase.forTesting(
    NativeDatabase.memory(
      setup: (rawDb) {
        for (final statement in ddl) {
          rawDb.execute(statement);
        }
        rawDb.execute('PRAGMA user_version = $version;');
        onRawDatabase?.call(rawDb);
      },
    ),
  );
}

void _ensureSqlite3() {
  if (!_overrideApplied && Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, _openSqliteOnLinux);
    _overrideApplied = true;
  }
}

DynamicLibrary _openSqliteOnLinux() {
  try {
    return DynamicLibrary.open('libsqlite3.so');
  } on ArgumentError {
    return DynamicLibrary.open('libsqlite3.so.0');
  }
}
