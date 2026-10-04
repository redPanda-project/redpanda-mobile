import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:redpanda/domain/message_direction.dart';
import 'package:redpanda/domain/message_lifecycle.dart';

part 'database.g.dart';

class Users extends Table {
  TextColumn get uuid => text()();
  TextColumn get username => text()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get publicKey => text().nullable()();

  @override
  Set<Column> get primaryKey => {uuid};
}

// T152: the row class is named `ChannelRow` so it does not collide with the
// light client's domain `Channel` — app files used to import one of the two
// libraries with `hide Channel`. Same pattern as `GroupChannelRow` and
// `NodeScoreRow`.
@DataClassName('ChannelRow')
class Channels extends Table {
  /// The conversation id: `SHA256(channel_pk)` as hex (spec Decision 1).
  ///
  /// T114: this is THE identifier of a 1:1 conversation. It used to be called
  /// `uuid` here, `channelId` in the repositories and `peerUuid` in the chat
  /// screen — four names (with `Messages.conversationId`) for one string. The
  /// app layer says `conversationId` now; the SQL column keeps its historical
  /// name so no migration is needed.
  TextColumn get conversationId => text().named('uuid')();
  TextColumn get label => text()();
  TextColumn get encryptionKey => text()(); // HEX encoded, 32 bytes (k_enc)

  // T44 (QR v4): the 32-byte channel secret shared by the QR. Everything else
  // (k_enc, the channel identity keypair, the rendezvous record keypair) is
  // derived from it. HEX encoded. Nullable only for the migration path; every
  // v4 channel has it.
  TextColumn get channelSecret => text().nullable()(); // HEX encoded, 32 bytes

  // Ed25519 channel identity keypair (T44: derived from channelSecret). The
  // private seed exists only on the device that generated the channel — it is
  // the local role marker (creator vs joiner); a device joining via QR holds
  // only the public key.
  TextColumn get authPrivateKey => text().nullable()(); // HEX encoded
  TextColumn get authPublicKey => text()(); // HEX encoded, 32 bytes

  // OH descriptor of the COUNTERPART's PRIMARY mailbox (for sending messages
  // to them). Mirrors the first entry of counterpartOhSet below.
  //
  // T114: the Dart names say "counterpart" (the human on the other side of
  // this conversation) instead of "peer", which in the light client means a
  // full node. The SQL column names are pinned with `named(...)` to the
  // historical `peer_oh_*` spelling, so this is a pure code-level rename with
  // no migration and no risk to existing databases.
  TextColumn get counterpartOhEndpoint =>
      text().nullable().named('peer_oh_endpoint')();
  TextColumn get counterpartOhId =>
      text().nullable().named('peer_oh_id')(); // HEX encoded
  TextColumn get counterpartOhPublicKey =>
      text().nullable().named('peer_oh_public_key')(); // HEX encoded

  // T42 multi-OH: the counterpart's FULL known mailbox set as a JSON array of
  // OHDescriptor maps ({ep,id,pk}). A send deposits into every entry; the
  // receiver deduplicates by message id. Grown/replaced by the in-band
  // `oh_update` announce. Null until the first announce arrives.
  TextColumn get counterpartOhSet => text().nullable().named('peer_oh_set')();

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
  Set<Column> get primaryKey => {conversationId};
}

// MS05: outstanding reverse-garlic session tags issued with our RGBs.
// A fetched reply is only accepted when its tag is found here (single-use);
// losing a row silently discards the matching reply, hence persistent.
class SessionTags extends Table {
  TextColumn get tag => text()(); // 16 bytes, hex (32 chars)
  TextColumn get conversationId =>
      text().references(Channels, #conversationId).named('channel_id')();
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
      text().references(Channels, #conversationId)();
  // T143 (TD155): there is no `sender_id` any more. It used to carry three
  // meanings (own user uuid / the conversation id standing in for "them" /
  // a group member id) and nothing read it after T114. The author of a row is
  // stated by two facts instead, see [senderMemberId].
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
  //
  // T143 (TD155): together with [direction] this IS the author identity —
  // one meaning per value, no lookup against the conversation needed:
  //   direction == outgoing                       -> the local user
  //   direction == incoming, senderMemberId null  -> the 1:1 counterpart
  //                                                  (the conversation)
  //   direction == incoming, senderMemberId set   -> that group member
  TextColumn get senderMemberId => text().nullable()();

  // T114: which way the message travelled ([MessageDirection]). Explicit
  // instead of derived from the former sender_id/status — see message_direction.dart.
  // The default is only for the v17 -> v18 upgrade path; both insert paths
  // in MessageRepository set it.
  IntColumn get direction =>
      integer().withDefault(const Constant(MessageDirection.outgoing))();
}

// MS08: one row per group this device is a member of. The crypto state
// (sender chains, outer keys, epoch archive) is a JSON snapshot from the
// network isolate (pattern = Channels.ratchetState) and is key material —
// on-device only, never exported.
@DataClassName('GroupChannelRow')
class GroupChannels extends Table {
  // 32-byte group id (hex) — also the conversation id of the own group OH.
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
  // The 1:1 conversation the proposal arrived on (the reply path for the
  // accept).
  TextColumn get conversationId => text().named('channel_id')();
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
  TextColumn get conversationId => text().nullable().named('channel_id')();

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

  /// The schema every migration path has to arrive at. A constant so tests
  /// can enumerate the historic versions (`2 .. currentSchemaVersion - 1`)
  /// without an instance (T124).
  static const int currentSchemaVersion = 19;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: _atomic((Migrator m, int from, int to) async {
        // T124 (TD149): a device runs ONE onUpgrade(from, schemaVersion), so
        // every step below sees the database as the PREVIOUS steps left it —
        // not as the app of that version left it. `createTable` always uses
        // the CURRENT Dart schema, so a table (re-)created by an earlier step
        // already carries every column a later step would add: an unguarded
        // `addColumn` after such a step throws `duplicate column name`, and
        // because `user_version` is only bumped after a successful migration
        // that is a crash loop on every launch, not a one-off error.
        // Therefore EVERY `addColumn` carries a lower bound naming the version
        // at which the table stopped being (re-)created underneath it. The
        // multi-jump test in test/database/migration_test.dart runs
        // onUpgrade(v, schemaVersion) for every historic v and is the guard.
        if (from < 2) {
          await m.createTable(channels);
        }
        if (from < 3) {
          await m.createTable(peers);
        }
        if (from < 4) {
          // `peers` is created from the CURRENT schema above, which already
          // has node_id — only a database that already had the v3 table needs
          // the column added.
          if (from >= 3) {
            await m.addColumn(peers, peers.nodeId);
          }
        }
        if (from < 5) {
          // Destructive migration for dev: Recreate Channels table to match new schema
          // (deleteTable is DROP TABLE IF EXISTS — no try/catch: inside the
          // migration transaction a swallowed error could leave the rest of
          // the upgrade running in autocommit, T143).
          await m.deleteTable(channels.actualTableName);
          await m.createTable(channels);
        }
        if (from < 6) {
          // Add OH columns to Channels and create OutboundHandles table.
          // Only a database that already had the v5 `channels` table needs
          // them; below that the step above re-created the table from the
          // current schema, which has the columns. This used to be a
          // try/catch that swallowed the duplicate-column error (and, with
          // it, the second and third ALTER plus any unrelated failure).
          if (from >= 5) {
            await m.addColumn(channels, channels.counterpartOhEndpoint);
            await m.addColumn(channels, channels.counterpartOhId);
            await m.addColumn(channels, channels.counterpartOhPublicKey);
          }
          await m.createTable(outboundHandles);
        }
        if (from < 7) {
          // MS02: dedup, retry tracking and persistent fetch cursor
          await m.addColumn(messages, messages.messageId);
          await m.addColumn(messages, messages.retryCount);
          await m.addColumn(messages, messages.lastRetryAt);
          // `outbound_handles` is created from the CURRENT schema in the v6
          // step above, which already has last_cursor — only a database that
          // already had the v6 table needs the column added.
          if (from >= 6) {
            await m.addColumn(outboundHandles, outboundHandles.lastCursor);
          }
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
          // (testnet, spec section 7). Both sides re-create channels via a
          // fresh v3 QR code.
          for (final table in <TableInfo>[
            messages,
            channels,
            outboundHandles,
          ]) {
            // DROP TABLE IF EXISTS — a missing table is not an error.
            await m.deleteTable(table.actualTableName);
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
        if (from < 16 && to >= 16) {
          // T42 multi-OH: full counterpart mailbox set (JSON array). Non-destructive.
          // The lower bound is 9, not 2: the v9 step above re-creates
          // `channels` from the current schema, which already declares
          // peer_oh_set. With `from >= 2` every v2..v8 database died here
          // with `duplicate column name: peer_oh_set` — the same crash T114
          // fixed for `direction` (TD149).
          if (from >= 9) {
            await m.addColumn(channels, channels.counterpartOhSet);
          }
        }
        if (from < 17 && to >= 17) {
          // T44 (QR v4): the channel is a keypair; the 32-byte channel secret
          // is now the source of truth (k_enc, identity and rendezvous keys are
          // derived from it). QR v3 is invalid without a migration path
          // (spec Decision 1) — existing channels cannot be upgraded and are
          // dropped so both sides re-pair with a fresh v4 QR. Destructive by design.
          for (final table in <TableInfo>[
            messages,
            channels,
            outboundHandles,
          ]) {
            // DROP TABLE IF EXISTS — a missing table is not an error.
            await m.deleteTable(table.actualTableName);
          }
          await m.createTable(channels);
          await m.createTable(messages);
          await m.createTable(outboundHandles);
          await m.createIndex(idxMessagesConvMessageId);
        }
        if (from < 18 && to >= 18) {
          // T114: message direction becomes an explicit column instead of the
          // two heuristics the chat screen used. Backfilled with EXACTLY those
          // heuristics so nothing on screen moves side:
          //   groups: incoming <=> status == received (the only writer of that
          //           status is insertIncomingIfNew, and no transition leads
          //           into or out of it, see MessageLifecycle)
          //   1:1:    incoming <=> sender_id == conversation_id (the channel id
          //           stands in for "them"; own rows carry the user's uuid)
          // The union of both is safe: an outgoing row can satisfy neither.
          // The `from < 17` step above DROPs and re-creates `messages` from
          // the CURRENT Dart schema, which already declares `direction` — so
          // adding it again would throw `duplicate column name: direction`
          // and, because `user_version` is only bumped after a successful
          // migration, put the app in a crash loop on every launch. Guarded
          // exactly like `senderMemberId` (v14) and `failedOverAt` (v15) are
          // guarded against their own recreate step. Verified: without the
          // guard `onUpgrade(16, 18)` throws, with it both 16 -> 18 and
          // 17 -> 18 pass (see migration_test).
          if (from >= 17) {
            await m.addColumn(messages, messages.direction);
          }
          // Only when `messages` predates the v17 re-creation: below that the
          // table was just re-created from the CURRENT schema, is empty, and
          // since v19 no longer has `sender_id` (T143) — the UPDATE would
          // throw `no such column` and crash-loop every v2..v16 database.
          if (from >= 17) {
            await m.database.customStatement(
              'UPDATE messages SET direction = ${MessageDirection.incoming} '
              'WHERE status = ${MessageStatus.received} '
              'OR sender_id = conversation_id',
            );
          }
        }
        if (from < 19 && to >= 19) {
          // T143 (TD155): `sender_id` meant three things depending on the row
          // and is dropped; the author is `direction` + `sender_member_id`
          // (see the column comment). Backfill rule per conversation type:
          //   outgoing rows (any type): sender_id was the local user's uuid
          //     -> nothing to keep, `direction` already says "me".
          //   incoming 1:1 rows: sender_id was the conversation id
          //     -> nothing to keep, the conversation IS the counterpart.
          //   incoming group rows (incl. groups left since): sender_id was
          //     the member id. MS08 has always written the same id into
          //     sender_member_id as well; copy it over for any row where
          //     that did not happen, so no group author is lost with the
          //     column.
          // Only a `messages` table that predates the v17 re-creation still
          // has `sender_id` (below that it came from the current schema, see
          // the v18 step) — hence `from >= 17`, like the v18 backfill.
          if (from >= 17) {
            // Group rows are recognised by `sender_id <> conversation_id`,
            // not by a join on group_channels: leaving a group deletes its
            // group_channels row but keeps its messages, and those authors
            // must survive too. An incoming 1:1 row always had
            // sender_id = conversation_id, so it can never match.
            await m.database.customStatement(
              'UPDATE messages SET sender_member_id = sender_id '
              'WHERE direction = ${MessageDirection.incoming} '
              'AND sender_member_id IS NULL '
              'AND sender_id <> conversation_id',
            );
            await m.dropColumn(messages, 'sender_id');
          }
        }
      }),
    );
  }

  /// Runs [body] and the `user_version` bump in ONE transaction (T143).
  ///
  /// drift runs `onUpgrade` without a transaction and writes `user_version`
  /// in a separate statement afterwards. A process killed in between (OOM,
  /// swipe-away, iOS watchdog during the table rewrite of a DROP COLUMN)
  /// left the database half-migrated at the OLD version, and the next launch
  /// re-ran steps that are not repeatable — `duplicate column name` for an
  /// `addColumn`, `no such column: sender_id` for the v18/v19 backfills — on
  /// every launch. SQLite DDL and `PRAGMA user_version` are transactional,
  /// so a kill now rolls the whole upgrade back and the next launch starts
  /// it again from the same `from`; drift's own version write afterwards
  /// writes the same value again.
  static OnUpgrade _atomic(OnUpgrade body) {
    return (Migrator m, int from, int to) => m.database.transaction(() async {
      await body(m, from, to);
      await m.database.customStatement('PRAGMA user_version = $to');
    });
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
