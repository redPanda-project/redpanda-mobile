import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// Tables
// ... (imports remain)

// Tables
class Users extends Table {
  TextColumn get uuid => text()();
  TextColumn get username => text()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get publicKey => text().nullable()();

  @override
  Set<Column> get primaryKey => {uuid};
}

class Channels extends Table {
  TextColumn get uuid => text()(); // The Channel ID (Hash of keys)
  TextColumn get label => text()();
  TextColumn get encryptionKey => text()(); // HEX encoded
  TextColumn get authenticationKey => text()(); // HEX encoded

  // Metadata
  DateTimeColumn get lastSeen => dateTime().nullable()(); // Last message time?

  @override
  Set<Column> get primaryKey => {uuid};
}

class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get conversationId =>
      text().references(Channels, #uuid)(); // Updated reference
  TextColumn get senderId => text()();
  TextColumn get content => text()();
  DateTimeColumn get timestamp => dateTime()();
  IntColumn get status => integer()(); // Enum index
  IntColumn get type => integer()(); // Enum index
}

class Peers extends Table {
  TextColumn get address => text()();
  TextColumn get nodeId => text().nullable()();
  IntColumn get averageLatencyMs =>
      integer().withDefault(const Constant(9999))();
  IntColumn get successCount => integer().withDefault(const Constant(0))();
  IntColumn get failureCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSeen => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {address};
}

@DriftDatabase(tables: [Users, Channels, Messages, Peers])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 5; // Incremented schema version to 5 for Channel updates

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.createTable(channels);
        }
        if (from < 3) {
          await m.createTable(peers);
        }
        if (from < 4) {
          await m.addColumn(peers, peers.nodeId);
        }
        if (from < 5) {
          // Destructive migration for dev: Recreate Channels table to match new schema
          try {
            await m.deleteTable(channels.actualTableName);
          } catch (e) {
            // optimize: table might not exist
          }
          await m.createTable(channels);
        }
      },
    );
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'redpanda_db',
      native: const DriftNativeOptions(shareAcrossIsolates: true),
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
  }
}
