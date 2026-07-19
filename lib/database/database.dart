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
  TextColumn get encryptionKey => text()(); // HEX encoded, 32 bytes

  // Ed25519 channel auth keypair (MS03). The private seed exists only on
  // the device that generated the channel; peers joining via QR code hold
  // only the public key.
  TextColumn get authPrivateKey => text().nullable()(); // HEX encoded
  TextColumn get authPublicKey => text()(); // HEX encoded, 32 bytes

  // OH Descriptor of the peer (for sending messages to them)
  TextColumn get peerOhEndpoint => text().nullable()();
  TextColumn get peerOhId => text().nullable()(); // HEX encoded
  TextColumn get peerOhPublicKey => text().nullable()(); // HEX encoded

  // Metadata
  DateTimeColumn get lastSeen => dateTime().nullable()(); // Last message time?

  // MS03b: serialized channel ratchet state (RatchetSession.toJson). Key
  // material — lives only in this on-device database and is never exported
  // in the QR code or any backup that leaves the device.
  TextColumn get ratchetState => text().nullable()();

  // MS05: latest unused ReverseGarlicBlock received from the channel
  // partner (serialized, hex). Single-use — cleared once a reply used it.
  // Only the newest RGB is kept (each incoming message carries a fresh one).
  TextColumn get pendingRgb => text().nullable()();

  @override
  Set<Column> get primaryKey => {uuid};
}

// MS05: outstanding reverse-garlic session tags issued with our RGBs.
// A fetched reply is only accepted when its tag is found here (single-use);
// losing a row silently discards the matching reply, hence persistent.
class SessionTags extends Table {
  TextColumn get tag => text()(); // 16 bytes, hex (32 chars)
  TextColumn get channelId => text().references(Channels, #uuid)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {tag};
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

  // MS08: authenticated sender member id (hex) for incoming group messages;
  // null for 1:1 messages and own outgoing messages.
  TextColumn get senderMemberId => text().nullable()();
}

// MS08: one row per group this device is a member of. The crypto state
// (sender chains, outer keys, epoch archive) is a JSON snapshot from the
// network isolate (pattern = Channels.ratchetState) and is key material —
// on-device only, never exported.
@DataClassName('GroupChannelRow')
class GroupChannels extends Table {
  // 32-byte group id (hex) — also the channelId of the own group OH.
  TextColumn get groupId => text()();
  TextColumn get label => text()();
  BoolColumn get isAdmin => boolean().withDefault(const Constant(false))();

  // Own group identity: member id = Ed25519 verify key (hex); the signing
  // seed and X25519 private key never leave the device.
  TextColumn get myMemberId => text()();
  TextColumn get mySignSeed => text()();
  TextColumn get myX25519Priv => text()();

  IntColumn get keyEpoch => integer().withDefault(const Constant(0))();
  TextColumn get cryptoState => text().nullable()();

  // Sealed rotation boxes not yet delivered (JSON: member id hex → payload
  // hex) — the epoch secret is deleted at install, so unsent boxes must
  // survive restarts (MS08, Decision 10).
  TextColumn get pendingRotations => text().nullable()();

  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {groupId};
}

// MS08: the authoritative member list per group (replaced wholesale by each
// key rotation).
@DataClassName('GroupMemberRow')
class GroupMembers extends Table {
  TextColumn get groupId => text().references(GroupChannels, #groupId)();
  // Ed25519 verify key (hex, 64 chars) — the member identity.
  TextColumn get memberId => text()();
  TextColumn get displayName => text()();
  TextColumn get ohId => text().nullable()(); // 20-byte mailbox id, hex
  TextColumn get ohEndpoint => text().nullable()();
  TextColumn get x25519Pub => text()();
  IntColumn get role => integer()(); // 0 = admin, 1 = member

  @override
  Set<Column> get primaryKey => {groupId, memberId};
}

// MS08: buffered group items of a not-yet-installed key epoch
// (Decision 10) — the fetch acknowledgement already deleted them
// server-side, so they must survive restarts until the rotation arrives.
@DataClassName('GroupPendingItemRow')
class GroupPendingItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get groupId => text().references(GroupChannels, #groupId)();
  BlobColumn get payload => blob()();
  DateTimeColumn get receivedAt => dateTime()();
}

// MS08: pending group invites (proposal received over a 1:1 channel,
// Decision 8) until the user accepts or dismisses them.
@DataClassName('GroupInviteRow')
class GroupInvites extends Table {
  TextColumn get groupId => text()();
  TextColumn get groupName => text()();
  // Pinned admin identity from the proposal: rotations must be signed by it.
  TextColumn get adminMemberId => text()();
  // The 1:1 channel the proposal arrived on (the reply path for the accept).
  TextColumn get channelId => text()();
  DateTimeColumn get receivedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {groupId};
}

// MS08: per-member delivery receipts for outgoing group messages
// (Decision 13: routed/delivered aggregate over ALL members).
@DataClassName('MessageReceiptRow')
class MessageReceipts extends Table {
  TextColumn get conversationId => text()(); // group id
  TextColumn get messageId => text()(); // network message id (hex)
  TextColumn get memberId => text()();
  BoolColumn get routed => boolean().withDefault(const Constant(false))();
  BoolColumn get delivered => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {conversationId, messageId, memberId};
}

// MS06: R-ACK-based reliability of known full nodes (garlic hop candidates).
// Written from NodeScore snapshots emitted by the network isolate and fed
// back on startup so scores survive app restarts. The row class is renamed
// to avoid clashing with the light client's NodeScore domain class.
@DataClassName('NodeScoreRow')
class NodeScores extends Table {
  TextColumn get nodeId => text()(); // 20-byte KademliaId, hex (40 chars)
  IntColumn get successCount => integer().withDefault(const Constant(0))();
  IntColumn get failureCount => integer().withDefault(const Constant(0))();
  IntColumn get avgLatencyMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUpdated => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {nodeId};
}

class Peers extends Table {
  TextColumn get address => text()();
  TextColumn get nodeId => text().nullable()();

  /// MS04: 32-byte X25519 encryption public key (hex, 64 chars) from the
  /// peer exchange — required for the peer to qualify as a garlic hop.
  TextColumn get encryptionPublicKey => text().nullable()();
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

  // T21: set when this handle was created by an automatic OH failover
  // (the previous host node was unreachable). Surfaced on the channel
  // status page.
  DateTimeColumn get failedOverAt => dateTime().nullable()();
}

@DriftDatabase(
  tables: [
    Users,
    Channels,
    Messages,
    Peers,
    OutboundHandles,
    SessionTags,
    NodeScores,
    GroupChannels,
    GroupMembers,
    GroupPendingItems,
    GroupInvites,
    MessageReceipts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests: run against an in-memory executor instead of the device DB.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 15;

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
        // The `to >= 9` guard keeps the per-step migration tests (which
        // simulate intermediate upgrades like 6 → 7) meaningful; in
        // production `to` is always the current schemaVersion.
        if (from < 9 && to >= 9) {
          // MS03: breaking crypto migration (Ed25519/X25519/AES-GCM, channel
          // key model v3). Old channels (shared-secret K_auth, old channel-id
          // scheme), their messages and the brainpool OH keypairs are
          // incompatible with the new protocol — destructive recreation
          // (testnet, spec section 7). Both peers re-create channels via a
          // fresh v3 QR code.
          for (final table in <TableInfo>[
            messages,
            channels,
            outboundHandles,
          ]) {
            try {
              await m.deleteTable(table.actualTableName);
            } catch (_) {
              // table might not exist on odd upgrade paths
            }
          }
          await m.createTable(channels);
          await m.createTable(messages);
          await m.createTable(outboundHandles);
          await m.createIndex(idxMessagesConvMessageId);
        }
        if (from == 9 && to >= 10) {
          // MS03b: per-channel ratchet state — non-destructive. Only DBs
          // already at v9 need the new column; older DBs received it through
          // the v9 table recreation above (createTable uses the current
          // schema).
          await m.addColumn(channels, channels.ratchetState);
        }
        if (from >= 3 && from < 11 && to >= 11) {
          // MS04: X25519 encryption public key of known peers (garlic hop
          // candidates) — non-destructive. DBs older than v3 receive the
          // column through createTable(peers) above (current schema).
          await m.addColumn(peers, peers.encryptionPublicKey);
        }
        if (from < 12 && to >= 12) {
          // MS05: reverse-garlic session state — non-destructive. The
          // session_tags table is new; the pending RGB column only needs
          // adding for DBs whose channels table predates this version (DBs
          // below v9 were recreated above with the current schema).
          await m.createTable(sessionTags);
          if (from >= 9) {
            await m.addColumn(channels, channels.pendingRgb);
          }
        }
        if (from < 13 && to >= 13) {
          // MS06: persisted R-ACK node scores — non-destructive.
          await m.createTable(nodeScores);
        }
        if (from < 14 && to >= 14) {
          // MS08: group chat — non-destructive. New group tables plus the
          // sender attribution column on messages (only needed for DBs whose
          // messages table predates this version; below v9 it was recreated
          // above with the current schema).
          await m.createTable(groupChannels);
          await m.createTable(groupMembers);
          await m.createTable(groupPendingItems);
          await m.createTable(groupInvites);
          await m.createTable(messageReceipts);
          if (from >= 9) {
            await m.addColumn(messages, messages.senderMemberId);
          }
        }
        if (from < 15 && to >= 15) {
          // T21: OH failover marker — non-destructive. DBs below v9 were
          // recreated above with the current schema.
          if (from >= 9) {
            await m.addColumn(outboundHandles, outboundHandles.failedOverAt);
          }
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
