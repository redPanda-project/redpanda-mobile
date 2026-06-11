import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

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

  // OH Descriptor of the peer (for sending messages to them)
  TextColumn get peerOhEndpoint => text().nullable()();
  TextColumn get peerOhId => text().nullable()(); // HEX encoded
  TextColumn get peerOhPublicKey => text().nullable()(); // HEX encoded

  // Metadata
  DateTimeColumn get lastSeen => dateTime().nullable()(); // Last message time?

  @override
  Set<Column> get primaryKey => {uuid};
}

// Dedup is scoped per conversation: the sender-chosen message_id is only
// unique within a channel, so the uniqueness constraint spans
// (conversationId, messageId). Rows with a NULL messageId (locally composed
// outgoing messages) are exempt — SQLite treats NULLs as distinct in a unique
// index, so multiple such rows coexist freely.
@TableIndex(
  name: 'idx_messages_conv_message_id',
  columns: {#conversationId, #messageId},
  unique: true,
)
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get conversationId =>
      text().references(Channels, #uuid)(); // Updated reference
  TextColumn get senderId => text()();
  TextColumn get content => text()();
  DateTimeColumn get timestamp => dateTime()();
  IntColumn get status => integer()(); // Enum index
  IntColumn get type => integer()(); // Enum index

  // Network-level message id (hex) for deduplication of fetched messages.
  TextColumn get messageId => text().nullable()();

  // Number of failed send attempts (for retry with exponential backoff).
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  // Time of the last send attempt; basis for the backoff calculation.
  DateTimeColumn get lastRetryAt => dateTime().nullable()();
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

class OutboundHandles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get ohId =>
      text()(); // HEX encoded, 20-byte KademliaId (40 hex chars)
  BlobColumn get keypairBytes => blob()(); // Serialized ECDSA keypair
  TextColumn get serverEndpoint => text()();
  DateTimeColumn get expiresAt => dateTime()();
  TextColumn get channelId => text().nullable()();

  // Highest acknowledged mailbox sequence id; fetches resume from here
  // after an app restart so old messages are not fetched again.
  IntColumn get lastCursor => integer().withDefault(const Constant(0))();
}

@DriftDatabase(tables: [Users, Channels, Messages, Peers, OutboundHandles])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests: run against an in-memory executor instead of the device DB.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

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
        if (from < 6) {
          // Add OH columns to Channels and create OutboundHandles table
          try {
            await m.addColumn(channels, channels.peerOhEndpoint);
            await m.addColumn(channels, channels.peerOhId);
            await m.addColumn(channels, channels.peerOhPublicKey);
          } catch (e) {
            // Columns might already exist if channels was recreated in step 5
          }
          await m.createTable(outboundHandles);
        }
        if (from < 7) {
          // MS02: dedup, retry tracking and persistent fetch cursor
          await m.addColumn(messages, messages.messageId);
          await m.addColumn(messages, messages.retryCount);
          await m.addColumn(messages, messages.lastRetryAt);
          await m.addColumn(outboundHandles, outboundHandles.lastCursor);
          // The global-unique message-id index from MS02 (idx_messages_message_id)
          // is replaced in v8 below by a per-conversation composite index, so
          // for fresh installs that started at v7 we still create the old one
          // here and drop it in the v8 step to keep the path uniform.
          await m.database.customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_message_id '
            'ON messages (message_id)',
          );
        }
        if (from < 8) {
          // MS03/C1: scope dedup per conversation. Drop the global unique index
          // on message_id and replace it with a composite unique index on
          // (conversation_id, message_id) so the same sender message id can
          // recur across different channels and an empty/null id never
          // black-holes a channel.
          await m.database.customStatement(
            'DROP INDEX IF EXISTS idx_messages_message_id',
          );
          await m.createIndex(idxMessagesConvMessageId);
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
