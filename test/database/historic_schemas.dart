/// The historic DDL of every schema version this app ever shipped (T124,
/// TD149).
///
/// A device that has not opened the app for a while runs ONE
/// `onUpgrade(from, schemaVersion)` covering many steps, so every step has to
/// survive what the earlier steps did to the database. Testing that needs a
/// database that really looks like version `from` — reshaping a current
/// database with `ALTER TABLE ... DROP COLUMN` (what the per-step tests do)
/// cannot reach the old versions, whose tables were dropped and re-created
/// twice since.
///
/// [ddlForSchemaVersion] replays the DDL a fresh install of that version
/// executed. The statements are hand-written rather than snapshotted, because
/// drift's generated DDL is not in the repository at those commits; they are
/// derived from `lib/database/database.dart` at the commit that introduced
/// each version:
///
/// | v  | commit    | change                                              |
/// |----|-----------|-----------------------------------------------------|
/// | 2  | `ae0b0d3` | initial commit: users, channels (v2 shape), messages |
/// | 3  | —         | never declared by any commit; peers without node_id  |
/// | 4  | `5dbce06` | peers.node_id                                        |
/// | 5  | `b5c9c4d` | channels re-created (label/encryption/auth key)      |
/// | 6  | `1dd8043` | channels.peer_oh_*, outbound_handles                 |
/// | 7  | `9faf04c` | MS02 dedup/retry/cursor + global message-id index    |
/// | 8  | `81e2554` | per-conversation unique index                        |
/// | 9  | `469b01c` | MS03 destructive re-creation, Ed25519 key model      |
/// | 10 | `7147ba9` | channels.ratchet_state                               |
/// | 11 | `1b6856f` | peers.encryption_public_key                          |
/// | 12 | `14cfa40` | session_tags, channels.pending_rgb                   |
/// | 13 | `4ee7dad` | node_scores                                          |
/// | 14 | `97f462a` | MS08 group tables, messages.sender_member_id         |
/// | 15 | `c19475d` | outbound_handles.failed_over_at                      |
/// | 16 | `3b27ed8` | channels.peer_oh_set                                 |
/// | 17 | `02e1805` | T44 destructive re-creation, channels.channel_secret |
///
/// Version 1 is deliberately absent: the initial commit already declares
/// `schemaVersion => 2`, so no build of this app ever wrote a v1 database, and
/// its shape (a `Contacts` table that the v2 step replaced with `channels`)
/// has never existed in this repository.
library;

const _v2 = <String>[
  'CREATE TABLE users ('
      'uuid TEXT NOT NULL UNIQUE, '
      'username TEXT NOT NULL, '
      'avatar_url TEXT NULL, '
      'public_key TEXT NULL, '
      'PRIMARY KEY (uuid))',
  'CREATE TABLE channels ('
      'uuid TEXT NOT NULL UNIQUE, '
      'username TEXT NOT NULL, '
      'private_key TEXT NULL, '
      'last_seen INTEGER NULL, '
      'is_online INTEGER NOT NULL DEFAULT 0, '
      'PRIMARY KEY (uuid))',
  'CREATE TABLE messages ('
      'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      'conversation_id TEXT NOT NULL REFERENCES channels (uuid), '
      'sender_id TEXT NOT NULL, '
      'content TEXT NOT NULL, '
      'timestamp INTEGER NOT NULL, '
      'status INTEGER NOT NULL, '
      'type INTEGER NOT NULL)',
];

/// `messages` as of v7 (MS02 columns), used by the v9 re-creation.
const _messagesV9 =
    'CREATE TABLE messages ('
    'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    'conversation_id TEXT NOT NULL REFERENCES channels (uuid), '
    'sender_id TEXT NOT NULL, '
    'content TEXT NOT NULL, '
    'timestamp INTEGER NOT NULL, '
    'status INTEGER NOT NULL, '
    'type INTEGER NOT NULL, '
    'message_id TEXT NULL, '
    'retry_count INTEGER NOT NULL DEFAULT 0, '
    'last_retry_at INTEGER NULL)';

const _outboundHandlesV9 =
    'CREATE TABLE outbound_handles ('
    'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    'oh_id TEXT NOT NULL, '
    'keypair_bytes BLOB NOT NULL, '
    'server_endpoint TEXT NOT NULL, '
    'expires_at INTEGER NOT NULL, '
    'channel_id TEXT NULL, '
    'last_cursor INTEGER NOT NULL DEFAULT 0)';

const _convMessageIdIndex =
    'CREATE UNIQUE INDEX idx_messages_conv_message_id '
    'ON messages (conversation_id, message_id)';

/// What a fresh install at version `v` did on top of version `v - 1`.
const _steps = <int, List<String>>{
  3: <String>[
    'CREATE TABLE peers ('
        'address TEXT NOT NULL UNIQUE, '
        'average_latency_ms INTEGER NOT NULL DEFAULT 9999, '
        'success_count INTEGER NOT NULL DEFAULT 0, '
        'failure_count INTEGER NOT NULL DEFAULT 0, '
        'last_seen INTEGER NULL, '
        'PRIMARY KEY (address))',
  ],
  4: <String>['ALTER TABLE peers ADD COLUMN node_id TEXT NULL'],
  5: <String>[
    'DROP TABLE channels',
    'CREATE TABLE channels ('
        'uuid TEXT NOT NULL, '
        'label TEXT NOT NULL, '
        'encryption_key TEXT NOT NULL, '
        'authentication_key TEXT NOT NULL, '
        'last_seen INTEGER NULL, '
        'PRIMARY KEY (uuid))',
  ],
  6: <String>[
    'ALTER TABLE channels ADD COLUMN peer_oh_endpoint TEXT NULL',
    'ALTER TABLE channels ADD COLUMN peer_oh_id TEXT NULL',
    'ALTER TABLE channels ADD COLUMN peer_oh_public_key TEXT NULL',
    'CREATE TABLE outbound_handles ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'oh_id TEXT NOT NULL, '
        'keypair_bytes BLOB NOT NULL, '
        'server_endpoint TEXT NOT NULL, '
        'expires_at INTEGER NOT NULL, '
        'channel_id TEXT NULL)',
  ],
  7: <String>[
    'ALTER TABLE messages ADD COLUMN message_id TEXT NULL',
    'ALTER TABLE messages ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE messages ADD COLUMN last_retry_at INTEGER NULL',
    'ALTER TABLE outbound_handles '
        'ADD COLUMN last_cursor INTEGER NOT NULL DEFAULT 0',
    'CREATE UNIQUE INDEX idx_messages_message_id ON messages (message_id)',
  ],
  8: <String>['DROP INDEX idx_messages_message_id', _convMessageIdIndex],
  9: <String>[
    'DROP TABLE messages',
    'DROP TABLE channels',
    'DROP TABLE outbound_handles',
    'CREATE TABLE channels ('
        'uuid TEXT NOT NULL, '
        'label TEXT NOT NULL, '
        'encryption_key TEXT NOT NULL, '
        'auth_private_key TEXT NULL, '
        'auth_public_key TEXT NOT NULL, '
        'peer_oh_endpoint TEXT NULL, '
        'peer_oh_id TEXT NULL, '
        'peer_oh_public_key TEXT NULL, '
        'last_seen INTEGER NULL, '
        'PRIMARY KEY (uuid))',
    _messagesV9,
    _outboundHandlesV9,
    _convMessageIdIndex,
  ],
  10: <String>['ALTER TABLE channels ADD COLUMN ratchet_state TEXT NULL'],
  11: <String>['ALTER TABLE peers ADD COLUMN encryption_public_key TEXT NULL'],
  12: <String>[
    'CREATE TABLE session_tags ('
        'tag TEXT NOT NULL, '
        'channel_id TEXT NOT NULL REFERENCES channels (uuid), '
        'created_at INTEGER NOT NULL, '
        'PRIMARY KEY (tag))',
    'ALTER TABLE channels ADD COLUMN pending_rgb TEXT NULL',
  ],
  13: <String>[
    'CREATE TABLE node_scores ('
        'node_id TEXT NOT NULL, '
        'success_count INTEGER NOT NULL DEFAULT 0, '
        'failure_count INTEGER NOT NULL DEFAULT 0, '
        'avg_latency_ms INTEGER NOT NULL DEFAULT 0, '
        'last_updated INTEGER NULL, '
        'PRIMARY KEY (node_id))',
  ],
  14: <String>[
    'CREATE TABLE group_channels ('
        'group_id TEXT NOT NULL, '
        'label TEXT NOT NULL, '
        'is_admin INTEGER NOT NULL DEFAULT 0, '
        'my_member_id TEXT NOT NULL, '
        'my_sign_seed TEXT NOT NULL, '
        'my_x25519_priv TEXT NOT NULL, '
        'key_epoch INTEGER NOT NULL DEFAULT 0, '
        'crypto_state TEXT NULL, '
        'pending_rotations TEXT NULL, '
        'created_at INTEGER NULL, '
        'PRIMARY KEY (group_id))',
    'CREATE TABLE group_members ('
        'group_id TEXT NOT NULL REFERENCES group_channels (group_id), '
        'member_id TEXT NOT NULL, '
        'display_name TEXT NOT NULL, '
        'oh_id TEXT NULL, '
        'oh_endpoint TEXT NULL, '
        'x25519_pub TEXT NOT NULL, '
        'role INTEGER NOT NULL, '
        'PRIMARY KEY (group_id, member_id))',
    'CREATE TABLE group_pending_items ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'group_id TEXT NOT NULL REFERENCES group_channels (group_id), '
        'payload BLOB NOT NULL, '
        'received_at INTEGER NOT NULL)',
    'CREATE TABLE group_invites ('
        'group_id TEXT NOT NULL, '
        'group_name TEXT NOT NULL, '
        'admin_member_id TEXT NOT NULL, '
        'channel_id TEXT NOT NULL, '
        'received_at INTEGER NOT NULL, '
        'PRIMARY KEY (group_id))',
    'CREATE TABLE message_receipts ('
        'conversation_id TEXT NOT NULL, '
        'message_id TEXT NOT NULL, '
        'member_id TEXT NOT NULL, '
        'routed INTEGER NOT NULL DEFAULT 0, '
        'delivered INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY (conversation_id, message_id, member_id))',
    'ALTER TABLE messages ADD COLUMN sender_member_id TEXT NULL',
  ],
  15: <String>[
    'ALTER TABLE outbound_handles ADD COLUMN failed_over_at INTEGER NULL',
  ],
  16: <String>['ALTER TABLE channels ADD COLUMN peer_oh_set TEXT NULL'],
  17: <String>[
    'DROP TABLE messages',
    'DROP TABLE channels',
    'DROP TABLE outbound_handles',
    'CREATE TABLE channels ('
        'uuid TEXT NOT NULL, '
        'label TEXT NOT NULL, '
        'encryption_key TEXT NOT NULL, '
        'channel_secret TEXT NULL, '
        'auth_private_key TEXT NULL, '
        'auth_public_key TEXT NOT NULL, '
        'peer_oh_endpoint TEXT NULL, '
        'peer_oh_id TEXT NULL, '
        'peer_oh_public_key TEXT NULL, '
        'peer_oh_set TEXT NULL, '
        'last_seen INTEGER NULL, '
        'ratchet_state TEXT NULL, '
        'pending_rgb TEXT NULL, '
        'PRIMARY KEY (uuid))',
    'CREATE TABLE messages ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'conversation_id TEXT NOT NULL REFERENCES channels (uuid), '
        'sender_id TEXT NOT NULL, '
        'content TEXT NOT NULL, '
        'timestamp INTEGER NOT NULL, '
        'status INTEGER NOT NULL, '
        'type INTEGER NOT NULL, '
        'message_id TEXT NULL, '
        'retry_count INTEGER NOT NULL DEFAULT 0, '
        'last_retry_at INTEGER NULL, '
        'sender_member_id TEXT NULL)',
    'CREATE TABLE outbound_handles ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'oh_id TEXT NOT NULL, '
        'keypair_bytes BLOB NOT NULL, '
        'server_endpoint TEXT NOT NULL, '
        'expires_at INTEGER NOT NULL, '
        'channel_id TEXT NULL, '
        'last_cursor INTEGER NOT NULL DEFAULT 0, '
        'failed_over_at INTEGER NULL)',
    _convMessageIdIndex,
  ],
};

/// The lowest schema version a real database can have (see the library doc).
const int oldestReachableSchemaVersion = 2;

/// The DDL a fresh install at [version] executed, in order.
List<String> ddlForSchemaVersion(int version) {
  assert(version >= oldestReachableSchemaVersion);
  return <String>[..._v2, for (var v = 3; v <= version; v++) ..._steps[v]!];
}
