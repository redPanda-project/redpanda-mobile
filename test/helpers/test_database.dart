import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:redpanda/database/database.dart';
import 'package:sqlite3/open.dart';

bool _overrideApplied = false;

/// Opens an in-memory [AppDatabase] for tests.
///
/// On Linux the sqlite3 package only tries `libsqlite3.so`, which requires
/// the dev package; fall back to the runtime library `libsqlite3.so.0`.
AppDatabase createTestDatabase() {
  if (!_overrideApplied && Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, _openSqliteOnLinux);
    _overrideApplied = true;
  }
  return AppDatabase.forTesting(NativeDatabase.memory());
}

DynamicLibrary _openSqliteOnLinux() {
  try {
    return DynamicLibrary.open('libsqlite3.so');
  } on ArgumentError {
    return DynamicLibrary.open('libsqlite3.so.0');
  }
}
