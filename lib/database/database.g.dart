// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $UsersTable extends Users with TableInfo<$UsersTable, User> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publicKeyMeta = const VerificationMeta(
    'publicKey',
  );
  @override
  late final GeneratedColumn<String> publicKey = GeneratedColumn<String>(
    'public_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [uuid, username, avatarUrl, publicKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<User> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('public_key')) {
      context.handle(
        _publicKeyMeta,
        publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {uuid};
  @override
  User map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return User(
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      publicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key'],
      ),
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }
}

class User extends DataClass implements Insertable<User> {
  final String uuid;
  final String username;
  final String? avatarUrl;
  final String? publicKey;
  const User({
    required this.uuid,
    required this.username,
    this.avatarUrl,
    this.publicKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uuid'] = Variable<String>(uuid);
    map['username'] = Variable<String>(username);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || publicKey != null) {
      map['public_key'] = Variable<String>(publicKey);
    }
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      uuid: Value(uuid),
      username: Value(username),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      publicKey: publicKey == null && nullToAbsent
          ? const Value.absent()
          : Value(publicKey),
    );
  }

  factory User.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return User(
      uuid: serializer.fromJson<String>(json['uuid']),
      username: serializer.fromJson<String>(json['username']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      publicKey: serializer.fromJson<String?>(json['publicKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uuid': serializer.toJson<String>(uuid),
      'username': serializer.toJson<String>(username),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'publicKey': serializer.toJson<String?>(publicKey),
    };
  }

  User copyWith({
    String? uuid,
    String? username,
    Value<String?> avatarUrl = const Value.absent(),
    Value<String?> publicKey = const Value.absent(),
  }) => User(
    uuid: uuid ?? this.uuid,
    username: username ?? this.username,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    publicKey: publicKey.present ? publicKey.value : this.publicKey,
  );
  User copyWithCompanion(UsersCompanion data) {
    return User(
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      username: data.username.present ? data.username.value : this.username,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('User(')
          ..write('uuid: $uuid, ')
          ..write('username: $username, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('publicKey: $publicKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(uuid, username, avatarUrl, publicKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is User &&
          other.uuid == this.uuid &&
          other.username == this.username &&
          other.avatarUrl == this.avatarUrl &&
          other.publicKey == this.publicKey);
}

class UsersCompanion extends UpdateCompanion<User> {
  final Value<String> uuid;
  final Value<String> username;
  final Value<String?> avatarUrl;
  final Value<String?> publicKey;
  final Value<int> rowid;
  const UsersCompanion({
    this.uuid = const Value.absent(),
    this.username = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersCompanion.insert({
    required String uuid,
    required String username,
    this.avatarUrl = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : uuid = Value(uuid),
       username = Value(username);
  static Insertable<User> custom({
    Expression<String>? uuid,
    Expression<String>? username,
    Expression<String>? avatarUrl,
    Expression<String>? publicKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (uuid != null) 'uuid': uuid,
      if (username != null) 'username': username,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (publicKey != null) 'public_key': publicKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersCompanion copyWith({
    Value<String>? uuid,
    Value<String>? username,
    Value<String?>? avatarUrl,
    Value<String?>? publicKey,
    Value<int>? rowid,
  }) {
    return UsersCompanion(
      uuid: uuid ?? this.uuid,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      publicKey: publicKey ?? this.publicKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (publicKey.present) {
      map['public_key'] = Variable<String>(publicKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('uuid: $uuid, ')
          ..write('username: $username, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('publicKey: $publicKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChannelsTable extends Channels with TableInfo<$ChannelsTable, Channel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptionKeyMeta = const VerificationMeta(
    'encryptionKey',
  );
  @override
  late final GeneratedColumn<String> encryptionKey = GeneratedColumn<String>(
    'encryption_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authPrivateKeyMeta = const VerificationMeta(
    'authPrivateKey',
  );
  @override
  late final GeneratedColumn<String> authPrivateKey = GeneratedColumn<String>(
    'auth_private_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _authPublicKeyMeta = const VerificationMeta(
    'authPublicKey',
  );
  @override
  late final GeneratedColumn<String> authPublicKey = GeneratedColumn<String>(
    'auth_public_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerOhEndpointMeta = const VerificationMeta(
    'peerOhEndpoint',
  );
  @override
  late final GeneratedColumn<String> peerOhEndpoint = GeneratedColumn<String>(
    'peer_oh_endpoint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _peerOhIdMeta = const VerificationMeta(
    'peerOhId',
  );
  @override
  late final GeneratedColumn<String> peerOhId = GeneratedColumn<String>(
    'peer_oh_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _peerOhPublicKeyMeta = const VerificationMeta(
    'peerOhPublicKey',
  );
  @override
  late final GeneratedColumn<String> peerOhPublicKey = GeneratedColumn<String>(
    'peer_oh_public_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _peerOhSetMeta = const VerificationMeta(
    'peerOhSet',
  );
  @override
  late final GeneratedColumn<String> peerOhSet = GeneratedColumn<String>(
    'peer_oh_set',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
    'last_seen',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratchetStateMeta = const VerificationMeta(
    'ratchetState',
  );
  @override
  late final GeneratedColumn<String> ratchetState = GeneratedColumn<String>(
    'ratchet_state',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pendingRgbMeta = const VerificationMeta(
    'pendingRgb',
  );
  @override
  late final GeneratedColumn<String> pendingRgb = GeneratedColumn<String>(
    'pending_rgb',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    uuid,
    label,
    encryptionKey,
    authPrivateKey,
    authPublicKey,
    peerOhEndpoint,
    peerOhId,
    peerOhPublicKey,
    peerOhSet,
    lastSeen,
    ratchetState,
    pendingRgb,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channels';
  @override
  VerificationContext validateIntegrity(
    Insertable<Channel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('encryption_key')) {
      context.handle(
        _encryptionKeyMeta,
        encryptionKey.isAcceptableOrUnknown(
          data['encryption_key']!,
          _encryptionKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptionKeyMeta);
    }
    if (data.containsKey('auth_private_key')) {
      context.handle(
        _authPrivateKeyMeta,
        authPrivateKey.isAcceptableOrUnknown(
          data['auth_private_key']!,
          _authPrivateKeyMeta,
        ),
      );
    }
    if (data.containsKey('auth_public_key')) {
      context.handle(
        _authPublicKeyMeta,
        authPublicKey.isAcceptableOrUnknown(
          data['auth_public_key']!,
          _authPublicKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authPublicKeyMeta);
    }
    if (data.containsKey('peer_oh_endpoint')) {
      context.handle(
        _peerOhEndpointMeta,
        peerOhEndpoint.isAcceptableOrUnknown(
          data['peer_oh_endpoint']!,
          _peerOhEndpointMeta,
        ),
      );
    }
    if (data.containsKey('peer_oh_id')) {
      context.handle(
        _peerOhIdMeta,
        peerOhId.isAcceptableOrUnknown(data['peer_oh_id']!, _peerOhIdMeta),
      );
    }
    if (data.containsKey('peer_oh_public_key')) {
      context.handle(
        _peerOhPublicKeyMeta,
        peerOhPublicKey.isAcceptableOrUnknown(
          data['peer_oh_public_key']!,
          _peerOhPublicKeyMeta,
        ),
      );
    }
    if (data.containsKey('peer_oh_set')) {
      context.handle(
        _peerOhSetMeta,
        peerOhSet.isAcceptableOrUnknown(data['peer_oh_set']!, _peerOhSetMeta),
      );
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    }
    if (data.containsKey('ratchet_state')) {
      context.handle(
        _ratchetStateMeta,
        ratchetState.isAcceptableOrUnknown(
          data['ratchet_state']!,
          _ratchetStateMeta,
        ),
      );
    }
    if (data.containsKey('pending_rgb')) {
      context.handle(
        _pendingRgbMeta,
        pendingRgb.isAcceptableOrUnknown(data['pending_rgb']!, _pendingRgbMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {uuid};
  @override
  Channel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Channel(
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      encryptionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encryption_key'],
      )!,
      authPrivateKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_private_key'],
      ),
      authPublicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_public_key'],
      )!,
      peerOhEndpoint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_oh_endpoint'],
      ),
      peerOhId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_oh_id'],
      ),
      peerOhPublicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_oh_public_key'],
      ),
      peerOhSet: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_oh_set'],
      ),
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen'],
      ),
      ratchetState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ratchet_state'],
      ),
      pendingRgb: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pending_rgb'],
      ),
    );
  }

  @override
  $ChannelsTable createAlias(String alias) {
    return $ChannelsTable(attachedDatabase, alias);
  }
}

class Channel extends DataClass implements Insertable<Channel> {
  final String uuid;
  final String label;
  final String encryptionKey;
  final String? authPrivateKey;
  final String authPublicKey;
  final String? peerOhEndpoint;
  final String? peerOhId;
  final String? peerOhPublicKey;
  final String? peerOhSet;
  final DateTime? lastSeen;
  final String? ratchetState;
  final String? pendingRgb;
  const Channel({
    required this.uuid,
    required this.label,
    required this.encryptionKey,
    this.authPrivateKey,
    required this.authPublicKey,
    this.peerOhEndpoint,
    this.peerOhId,
    this.peerOhPublicKey,
    this.peerOhSet,
    this.lastSeen,
    this.ratchetState,
    this.pendingRgb,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uuid'] = Variable<String>(uuid);
    map['label'] = Variable<String>(label);
    map['encryption_key'] = Variable<String>(encryptionKey);
    if (!nullToAbsent || authPrivateKey != null) {
      map['auth_private_key'] = Variable<String>(authPrivateKey);
    }
    map['auth_public_key'] = Variable<String>(authPublicKey);
    if (!nullToAbsent || peerOhEndpoint != null) {
      map['peer_oh_endpoint'] = Variable<String>(peerOhEndpoint);
    }
    if (!nullToAbsent || peerOhId != null) {
      map['peer_oh_id'] = Variable<String>(peerOhId);
    }
    if (!nullToAbsent || peerOhPublicKey != null) {
      map['peer_oh_public_key'] = Variable<String>(peerOhPublicKey);
    }
    if (!nullToAbsent || peerOhSet != null) {
      map['peer_oh_set'] = Variable<String>(peerOhSet);
    }
    if (!nullToAbsent || lastSeen != null) {
      map['last_seen'] = Variable<DateTime>(lastSeen);
    }
    if (!nullToAbsent || ratchetState != null) {
      map['ratchet_state'] = Variable<String>(ratchetState);
    }
    if (!nullToAbsent || pendingRgb != null) {
      map['pending_rgb'] = Variable<String>(pendingRgb);
    }
    return map;
  }

  ChannelsCompanion toCompanion(bool nullToAbsent) {
    return ChannelsCompanion(
      uuid: Value(uuid),
      label: Value(label),
      encryptionKey: Value(encryptionKey),
      authPrivateKey: authPrivateKey == null && nullToAbsent
          ? const Value.absent()
          : Value(authPrivateKey),
      authPublicKey: Value(authPublicKey),
      peerOhEndpoint: peerOhEndpoint == null && nullToAbsent
          ? const Value.absent()
          : Value(peerOhEndpoint),
      peerOhId: peerOhId == null && nullToAbsent
          ? const Value.absent()
          : Value(peerOhId),
      peerOhPublicKey: peerOhPublicKey == null && nullToAbsent
          ? const Value.absent()
          : Value(peerOhPublicKey),
      peerOhSet: peerOhSet == null && nullToAbsent
          ? const Value.absent()
          : Value(peerOhSet),
      lastSeen: lastSeen == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeen),
      ratchetState: ratchetState == null && nullToAbsent
          ? const Value.absent()
          : Value(ratchetState),
      pendingRgb: pendingRgb == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingRgb),
    );
  }

  factory Channel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Channel(
      uuid: serializer.fromJson<String>(json['uuid']),
      label: serializer.fromJson<String>(json['label']),
      encryptionKey: serializer.fromJson<String>(json['encryptionKey']),
      authPrivateKey: serializer.fromJson<String?>(json['authPrivateKey']),
      authPublicKey: serializer.fromJson<String>(json['authPublicKey']),
      peerOhEndpoint: serializer.fromJson<String?>(json['peerOhEndpoint']),
      peerOhId: serializer.fromJson<String?>(json['peerOhId']),
      peerOhPublicKey: serializer.fromJson<String?>(json['peerOhPublicKey']),
      peerOhSet: serializer.fromJson<String?>(json['peerOhSet']),
      lastSeen: serializer.fromJson<DateTime?>(json['lastSeen']),
      ratchetState: serializer.fromJson<String?>(json['ratchetState']),
      pendingRgb: serializer.fromJson<String?>(json['pendingRgb']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uuid': serializer.toJson<String>(uuid),
      'label': serializer.toJson<String>(label),
      'encryptionKey': serializer.toJson<String>(encryptionKey),
      'authPrivateKey': serializer.toJson<String?>(authPrivateKey),
      'authPublicKey': serializer.toJson<String>(authPublicKey),
      'peerOhEndpoint': serializer.toJson<String?>(peerOhEndpoint),
      'peerOhId': serializer.toJson<String?>(peerOhId),
      'peerOhPublicKey': serializer.toJson<String?>(peerOhPublicKey),
      'peerOhSet': serializer.toJson<String?>(peerOhSet),
      'lastSeen': serializer.toJson<DateTime?>(lastSeen),
      'ratchetState': serializer.toJson<String?>(ratchetState),
      'pendingRgb': serializer.toJson<String?>(pendingRgb),
    };
  }

  Channel copyWith({
    String? uuid,
    String? label,
    String? encryptionKey,
    Value<String?> authPrivateKey = const Value.absent(),
    String? authPublicKey,
    Value<String?> peerOhEndpoint = const Value.absent(),
    Value<String?> peerOhId = const Value.absent(),
    Value<String?> peerOhPublicKey = const Value.absent(),
    Value<String?> peerOhSet = const Value.absent(),
    Value<DateTime?> lastSeen = const Value.absent(),
    Value<String?> ratchetState = const Value.absent(),
    Value<String?> pendingRgb = const Value.absent(),
  }) => Channel(
    uuid: uuid ?? this.uuid,
    label: label ?? this.label,
    encryptionKey: encryptionKey ?? this.encryptionKey,
    authPrivateKey: authPrivateKey.present
        ? authPrivateKey.value
        : this.authPrivateKey,
    authPublicKey: authPublicKey ?? this.authPublicKey,
    peerOhEndpoint: peerOhEndpoint.present
        ? peerOhEndpoint.value
        : this.peerOhEndpoint,
    peerOhId: peerOhId.present ? peerOhId.value : this.peerOhId,
    peerOhPublicKey: peerOhPublicKey.present
        ? peerOhPublicKey.value
        : this.peerOhPublicKey,
    peerOhSet: peerOhSet.present ? peerOhSet.value : this.peerOhSet,
    lastSeen: lastSeen.present ? lastSeen.value : this.lastSeen,
    ratchetState: ratchetState.present ? ratchetState.value : this.ratchetState,
    pendingRgb: pendingRgb.present ? pendingRgb.value : this.pendingRgb,
  );
  Channel copyWithCompanion(ChannelsCompanion data) {
    return Channel(
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      label: data.label.present ? data.label.value : this.label,
      encryptionKey: data.encryptionKey.present
          ? data.encryptionKey.value
          : this.encryptionKey,
      authPrivateKey: data.authPrivateKey.present
          ? data.authPrivateKey.value
          : this.authPrivateKey,
      authPublicKey: data.authPublicKey.present
          ? data.authPublicKey.value
          : this.authPublicKey,
      peerOhEndpoint: data.peerOhEndpoint.present
          ? data.peerOhEndpoint.value
          : this.peerOhEndpoint,
      peerOhId: data.peerOhId.present ? data.peerOhId.value : this.peerOhId,
      peerOhPublicKey: data.peerOhPublicKey.present
          ? data.peerOhPublicKey.value
          : this.peerOhPublicKey,
      peerOhSet: data.peerOhSet.present ? data.peerOhSet.value : this.peerOhSet,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
      ratchetState: data.ratchetState.present
          ? data.ratchetState.value
          : this.ratchetState,
      pendingRgb: data.pendingRgb.present
          ? data.pendingRgb.value
          : this.pendingRgb,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Channel(')
          ..write('uuid: $uuid, ')
          ..write('label: $label, ')
          ..write('encryptionKey: $encryptionKey, ')
          ..write('authPrivateKey: $authPrivateKey, ')
          ..write('authPublicKey: $authPublicKey, ')
          ..write('peerOhEndpoint: $peerOhEndpoint, ')
          ..write('peerOhId: $peerOhId, ')
          ..write('peerOhPublicKey: $peerOhPublicKey, ')
          ..write('peerOhSet: $peerOhSet, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('ratchetState: $ratchetState, ')
          ..write('pendingRgb: $pendingRgb')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    uuid,
    label,
    encryptionKey,
    authPrivateKey,
    authPublicKey,
    peerOhEndpoint,
    peerOhId,
    peerOhPublicKey,
    peerOhSet,
    lastSeen,
    ratchetState,
    pendingRgb,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Channel &&
          other.uuid == this.uuid &&
          other.label == this.label &&
          other.encryptionKey == this.encryptionKey &&
          other.authPrivateKey == this.authPrivateKey &&
          other.authPublicKey == this.authPublicKey &&
          other.peerOhEndpoint == this.peerOhEndpoint &&
          other.peerOhId == this.peerOhId &&
          other.peerOhPublicKey == this.peerOhPublicKey &&
          other.peerOhSet == this.peerOhSet &&
          other.lastSeen == this.lastSeen &&
          other.ratchetState == this.ratchetState &&
          other.pendingRgb == this.pendingRgb);
}

class ChannelsCompanion extends UpdateCompanion<Channel> {
  final Value<String> uuid;
  final Value<String> label;
  final Value<String> encryptionKey;
  final Value<String?> authPrivateKey;
  final Value<String> authPublicKey;
  final Value<String?> peerOhEndpoint;
  final Value<String?> peerOhId;
  final Value<String?> peerOhPublicKey;
  final Value<String?> peerOhSet;
  final Value<DateTime?> lastSeen;
  final Value<String?> ratchetState;
  final Value<String?> pendingRgb;
  final Value<int> rowid;
  const ChannelsCompanion({
    this.uuid = const Value.absent(),
    this.label = const Value.absent(),
    this.encryptionKey = const Value.absent(),
    this.authPrivateKey = const Value.absent(),
    this.authPublicKey = const Value.absent(),
    this.peerOhEndpoint = const Value.absent(),
    this.peerOhId = const Value.absent(),
    this.peerOhPublicKey = const Value.absent(),
    this.peerOhSet = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.ratchetState = const Value.absent(),
    this.pendingRgb = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChannelsCompanion.insert({
    required String uuid,
    required String label,
    required String encryptionKey,
    this.authPrivateKey = const Value.absent(),
    required String authPublicKey,
    this.peerOhEndpoint = const Value.absent(),
    this.peerOhId = const Value.absent(),
    this.peerOhPublicKey = const Value.absent(),
    this.peerOhSet = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.ratchetState = const Value.absent(),
    this.pendingRgb = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : uuid = Value(uuid),
       label = Value(label),
       encryptionKey = Value(encryptionKey),
       authPublicKey = Value(authPublicKey);
  static Insertable<Channel> custom({
    Expression<String>? uuid,
    Expression<String>? label,
    Expression<String>? encryptionKey,
    Expression<String>? authPrivateKey,
    Expression<String>? authPublicKey,
    Expression<String>? peerOhEndpoint,
    Expression<String>? peerOhId,
    Expression<String>? peerOhPublicKey,
    Expression<String>? peerOhSet,
    Expression<DateTime>? lastSeen,
    Expression<String>? ratchetState,
    Expression<String>? pendingRgb,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (uuid != null) 'uuid': uuid,
      if (label != null) 'label': label,
      if (encryptionKey != null) 'encryption_key': encryptionKey,
      if (authPrivateKey != null) 'auth_private_key': authPrivateKey,
      if (authPublicKey != null) 'auth_public_key': authPublicKey,
      if (peerOhEndpoint != null) 'peer_oh_endpoint': peerOhEndpoint,
      if (peerOhId != null) 'peer_oh_id': peerOhId,
      if (peerOhPublicKey != null) 'peer_oh_public_key': peerOhPublicKey,
      if (peerOhSet != null) 'peer_oh_set': peerOhSet,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (ratchetState != null) 'ratchet_state': ratchetState,
      if (pendingRgb != null) 'pending_rgb': pendingRgb,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChannelsCompanion copyWith({
    Value<String>? uuid,
    Value<String>? label,
    Value<String>? encryptionKey,
    Value<String?>? authPrivateKey,
    Value<String>? authPublicKey,
    Value<String?>? peerOhEndpoint,
    Value<String?>? peerOhId,
    Value<String?>? peerOhPublicKey,
    Value<String?>? peerOhSet,
    Value<DateTime?>? lastSeen,
    Value<String?>? ratchetState,
    Value<String?>? pendingRgb,
    Value<int>? rowid,
  }) {
    return ChannelsCompanion(
      uuid: uuid ?? this.uuid,
      label: label ?? this.label,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      authPrivateKey: authPrivateKey ?? this.authPrivateKey,
      authPublicKey: authPublicKey ?? this.authPublicKey,
      peerOhEndpoint: peerOhEndpoint ?? this.peerOhEndpoint,
      peerOhId: peerOhId ?? this.peerOhId,
      peerOhPublicKey: peerOhPublicKey ?? this.peerOhPublicKey,
      peerOhSet: peerOhSet ?? this.peerOhSet,
      lastSeen: lastSeen ?? this.lastSeen,
      ratchetState: ratchetState ?? this.ratchetState,
      pendingRgb: pendingRgb ?? this.pendingRgb,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (encryptionKey.present) {
      map['encryption_key'] = Variable<String>(encryptionKey.value);
    }
    if (authPrivateKey.present) {
      map['auth_private_key'] = Variable<String>(authPrivateKey.value);
    }
    if (authPublicKey.present) {
      map['auth_public_key'] = Variable<String>(authPublicKey.value);
    }
    if (peerOhEndpoint.present) {
      map['peer_oh_endpoint'] = Variable<String>(peerOhEndpoint.value);
    }
    if (peerOhId.present) {
      map['peer_oh_id'] = Variable<String>(peerOhId.value);
    }
    if (peerOhPublicKey.present) {
      map['peer_oh_public_key'] = Variable<String>(peerOhPublicKey.value);
    }
    if (peerOhSet.present) {
      map['peer_oh_set'] = Variable<String>(peerOhSet.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    if (ratchetState.present) {
      map['ratchet_state'] = Variable<String>(ratchetState.value);
    }
    if (pendingRgb.present) {
      map['pending_rgb'] = Variable<String>(pendingRgb.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelsCompanion(')
          ..write('uuid: $uuid, ')
          ..write('label: $label, ')
          ..write('encryptionKey: $encryptionKey, ')
          ..write('authPrivateKey: $authPrivateKey, ')
          ..write('authPublicKey: $authPublicKey, ')
          ..write('peerOhEndpoint: $peerOhEndpoint, ')
          ..write('peerOhId: $peerOhId, ')
          ..write('peerOhPublicKey: $peerOhPublicKey, ')
          ..write('peerOhSet: $peerOhSet, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('ratchetState: $ratchetState, ')
          ..write('pendingRgb: $pendingRgb, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES channels (uuid)',
    ),
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
    'sender_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastRetryAtMeta = const VerificationMeta(
    'lastRetryAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastRetryAt = GeneratedColumn<DateTime>(
    'last_retry_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _senderMemberIdMeta = const VerificationMeta(
    'senderMemberId',
  );
  @override
  late final GeneratedColumn<String> senderMemberId = GeneratedColumn<String>(
    'sender_member_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    senderId,
    content,
    timestamp,
    status,
    type,
    messageId,
    retryCount,
    lastRetryAt,
    senderMemberId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('last_retry_at')) {
      context.handle(
        _lastRetryAtMeta,
        lastRetryAt.isAcceptableOrUnknown(
          data['last_retry_at']!,
          _lastRetryAtMeta,
        ),
      );
    }
    if (data.containsKey('sender_member_id')) {
      context.handle(
        _senderMemberIdMeta,
        senderMemberId.isAcceptableOrUnknown(
          data['sender_member_id']!,
          _senderMemberIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}type'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      ),
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      lastRetryAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_retry_at'],
      ),
      senderMemberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_member_id'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final int id;
  final String conversationId;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final int status;
  final int type;
  final String? messageId;
  final int retryCount;
  final DateTime? lastRetryAt;
  final String? senderMemberId;
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.timestamp,
    required this.status,
    required this.type,
    this.messageId,
    required this.retryCount,
    this.lastRetryAt,
    this.senderMemberId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['sender_id'] = Variable<String>(senderId);
    map['content'] = Variable<String>(content);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['status'] = Variable<int>(status);
    map['type'] = Variable<int>(type);
    if (!nullToAbsent || messageId != null) {
      map['message_id'] = Variable<String>(messageId);
    }
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || lastRetryAt != null) {
      map['last_retry_at'] = Variable<DateTime>(lastRetryAt);
    }
    if (!nullToAbsent || senderMemberId != null) {
      map['sender_member_id'] = Variable<String>(senderMemberId);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      senderId: Value(senderId),
      content: Value(content),
      timestamp: Value(timestamp),
      status: Value(status),
      type: Value(type),
      messageId: messageId == null && nullToAbsent
          ? const Value.absent()
          : Value(messageId),
      retryCount: Value(retryCount),
      lastRetryAt: lastRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRetryAt),
      senderMemberId: senderMemberId == null && nullToAbsent
          ? const Value.absent()
          : Value(senderMemberId),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<int>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      content: serializer.fromJson<String>(json['content']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      status: serializer.fromJson<int>(json['status']),
      type: serializer.fromJson<int>(json['type']),
      messageId: serializer.fromJson<String?>(json['messageId']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      lastRetryAt: serializer.fromJson<DateTime?>(json['lastRetryAt']),
      senderMemberId: serializer.fromJson<String?>(json['senderMemberId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'senderId': serializer.toJson<String>(senderId),
      'content': serializer.toJson<String>(content),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'status': serializer.toJson<int>(status),
      'type': serializer.toJson<int>(type),
      'messageId': serializer.toJson<String?>(messageId),
      'retryCount': serializer.toJson<int>(retryCount),
      'lastRetryAt': serializer.toJson<DateTime?>(lastRetryAt),
      'senderMemberId': serializer.toJson<String?>(senderMemberId),
    };
  }

  Message copyWith({
    int? id,
    String? conversationId,
    String? senderId,
    String? content,
    DateTime? timestamp,
    int? status,
    int? type,
    Value<String?> messageId = const Value.absent(),
    int? retryCount,
    Value<DateTime?> lastRetryAt = const Value.absent(),
    Value<String?> senderMemberId = const Value.absent(),
  }) => Message(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    senderId: senderId ?? this.senderId,
    content: content ?? this.content,
    timestamp: timestamp ?? this.timestamp,
    status: status ?? this.status,
    type: type ?? this.type,
    messageId: messageId.present ? messageId.value : this.messageId,
    retryCount: retryCount ?? this.retryCount,
    lastRetryAt: lastRetryAt.present ? lastRetryAt.value : this.lastRetryAt,
    senderMemberId: senderMemberId.present
        ? senderMemberId.value
        : this.senderMemberId,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      content: data.content.present ? data.content.value : this.content,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      status: data.status.present ? data.status.value : this.status,
      type: data.type.present ? data.type.value : this.type,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      lastRetryAt: data.lastRetryAt.present
          ? data.lastRetryAt.value
          : this.lastRetryAt,
      senderMemberId: data.senderMemberId.present
          ? data.senderMemberId.value
          : this.senderMemberId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('content: $content, ')
          ..write('timestamp: $timestamp, ')
          ..write('status: $status, ')
          ..write('type: $type, ')
          ..write('messageId: $messageId, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastRetryAt: $lastRetryAt, ')
          ..write('senderMemberId: $senderMemberId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    senderId,
    content,
    timestamp,
    status,
    type,
    messageId,
    retryCount,
    lastRetryAt,
    senderMemberId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.senderId == this.senderId &&
          other.content == this.content &&
          other.timestamp == this.timestamp &&
          other.status == this.status &&
          other.type == this.type &&
          other.messageId == this.messageId &&
          other.retryCount == this.retryCount &&
          other.lastRetryAt == this.lastRetryAt &&
          other.senderMemberId == this.senderMemberId);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<int> id;
  final Value<String> conversationId;
  final Value<String> senderId;
  final Value<String> content;
  final Value<DateTime> timestamp;
  final Value<int> status;
  final Value<int> type;
  final Value<String?> messageId;
  final Value<int> retryCount;
  final Value<DateTime?> lastRetryAt;
  final Value<String?> senderMemberId;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.content = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.status = const Value.absent(),
    this.type = const Value.absent(),
    this.messageId = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastRetryAt = const Value.absent(),
    this.senderMemberId = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.id = const Value.absent(),
    required String conversationId,
    required String senderId,
    required String content,
    required DateTime timestamp,
    required int status,
    required int type,
    this.messageId = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastRetryAt = const Value.absent(),
    this.senderMemberId = const Value.absent(),
  }) : conversationId = Value(conversationId),
       senderId = Value(senderId),
       content = Value(content),
       timestamp = Value(timestamp),
       status = Value(status),
       type = Value(type);
  static Insertable<Message> custom({
    Expression<int>? id,
    Expression<String>? conversationId,
    Expression<String>? senderId,
    Expression<String>? content,
    Expression<DateTime>? timestamp,
    Expression<int>? status,
    Expression<int>? type,
    Expression<String>? messageId,
    Expression<int>? retryCount,
    Expression<DateTime>? lastRetryAt,
    Expression<String>? senderMemberId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (senderId != null) 'sender_id': senderId,
      if (content != null) 'content': content,
      if (timestamp != null) 'timestamp': timestamp,
      if (status != null) 'status': status,
      if (type != null) 'type': type,
      if (messageId != null) 'message_id': messageId,
      if (retryCount != null) 'retry_count': retryCount,
      if (lastRetryAt != null) 'last_retry_at': lastRetryAt,
      if (senderMemberId != null) 'sender_member_id': senderMemberId,
    });
  }

  MessagesCompanion copyWith({
    Value<int>? id,
    Value<String>? conversationId,
    Value<String>? senderId,
    Value<String>? content,
    Value<DateTime>? timestamp,
    Value<int>? status,
    Value<int>? type,
    Value<String?>? messageId,
    Value<int>? retryCount,
    Value<DateTime?>? lastRetryAt,
    Value<String?>? senderMemberId,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      type: type ?? this.type,
      messageId: messageId ?? this.messageId,
      retryCount: retryCount ?? this.retryCount,
      lastRetryAt: lastRetryAt ?? this.lastRetryAt,
      senderMemberId: senderMemberId ?? this.senderMemberId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (lastRetryAt.present) {
      map['last_retry_at'] = Variable<DateTime>(lastRetryAt.value);
    }
    if (senderMemberId.present) {
      map['sender_member_id'] = Variable<String>(senderMemberId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('content: $content, ')
          ..write('timestamp: $timestamp, ')
          ..write('status: $status, ')
          ..write('type: $type, ')
          ..write('messageId: $messageId, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastRetryAt: $lastRetryAt, ')
          ..write('senderMemberId: $senderMemberId')
          ..write(')'))
        .toString();
  }
}

class $PeersTable extends Peers with TableInfo<$PeersTable, Peer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nodeIdMeta = const VerificationMeta('nodeId');
  @override
  late final GeneratedColumn<String> nodeId = GeneratedColumn<String>(
    'node_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _encryptionPublicKeyMeta =
      const VerificationMeta('encryptionPublicKey');
  @override
  late final GeneratedColumn<String> encryptionPublicKey =
      GeneratedColumn<String>(
        'encryption_public_key',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _averageLatencyMsMeta = const VerificationMeta(
    'averageLatencyMs',
  );
  @override
  late final GeneratedColumn<int> averageLatencyMs = GeneratedColumn<int>(
    'average_latency_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(9999),
  );
  static const VerificationMeta _successCountMeta = const VerificationMeta(
    'successCount',
  );
  @override
  late final GeneratedColumn<int> successCount = GeneratedColumn<int>(
    'success_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _failureCountMeta = const VerificationMeta(
    'failureCount',
  );
  @override
  late final GeneratedColumn<int> failureCount = GeneratedColumn<int>(
    'failure_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
    'last_seen',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    address,
    nodeId,
    encryptionPublicKey,
    averageLatencyMs,
    successCount,
    failureCount,
    lastSeen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'peers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Peer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('node_id')) {
      context.handle(
        _nodeIdMeta,
        nodeId.isAcceptableOrUnknown(data['node_id']!, _nodeIdMeta),
      );
    }
    if (data.containsKey('encryption_public_key')) {
      context.handle(
        _encryptionPublicKeyMeta,
        encryptionPublicKey.isAcceptableOrUnknown(
          data['encryption_public_key']!,
          _encryptionPublicKeyMeta,
        ),
      );
    }
    if (data.containsKey('average_latency_ms')) {
      context.handle(
        _averageLatencyMsMeta,
        averageLatencyMs.isAcceptableOrUnknown(
          data['average_latency_ms']!,
          _averageLatencyMsMeta,
        ),
      );
    }
    if (data.containsKey('success_count')) {
      context.handle(
        _successCountMeta,
        successCount.isAcceptableOrUnknown(
          data['success_count']!,
          _successCountMeta,
        ),
      );
    }
    if (data.containsKey('failure_count')) {
      context.handle(
        _failureCountMeta,
        failureCount.isAcceptableOrUnknown(
          data['failure_count']!,
          _failureCountMeta,
        ),
      );
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {address};
  @override
  Peer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Peer(
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      nodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_id'],
      ),
      encryptionPublicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encryption_public_key'],
      ),
      averageLatencyMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}average_latency_ms'],
      )!,
      successCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}success_count'],
      )!,
      failureCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failure_count'],
      )!,
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen'],
      ),
    );
  }

  @override
  $PeersTable createAlias(String alias) {
    return $PeersTable(attachedDatabase, alias);
  }
}

class Peer extends DataClass implements Insertable<Peer> {
  final String address;
  final String? nodeId;

  /// MS04: 32-byte X25519 encryption public key (hex, 64 chars) from the
  /// peer exchange — required for the peer to qualify as a garlic hop.
  final String? encryptionPublicKey;
  final int averageLatencyMs;
  final int successCount;
  final int failureCount;
  final DateTime? lastSeen;
  const Peer({
    required this.address,
    this.nodeId,
    this.encryptionPublicKey,
    required this.averageLatencyMs,
    required this.successCount,
    required this.failureCount,
    this.lastSeen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['address'] = Variable<String>(address);
    if (!nullToAbsent || nodeId != null) {
      map['node_id'] = Variable<String>(nodeId);
    }
    if (!nullToAbsent || encryptionPublicKey != null) {
      map['encryption_public_key'] = Variable<String>(encryptionPublicKey);
    }
    map['average_latency_ms'] = Variable<int>(averageLatencyMs);
    map['success_count'] = Variable<int>(successCount);
    map['failure_count'] = Variable<int>(failureCount);
    if (!nullToAbsent || lastSeen != null) {
      map['last_seen'] = Variable<DateTime>(lastSeen);
    }
    return map;
  }

  PeersCompanion toCompanion(bool nullToAbsent) {
    return PeersCompanion(
      address: Value(address),
      nodeId: nodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(nodeId),
      encryptionPublicKey: encryptionPublicKey == null && nullToAbsent
          ? const Value.absent()
          : Value(encryptionPublicKey),
      averageLatencyMs: Value(averageLatencyMs),
      successCount: Value(successCount),
      failureCount: Value(failureCount),
      lastSeen: lastSeen == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeen),
    );
  }

  factory Peer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Peer(
      address: serializer.fromJson<String>(json['address']),
      nodeId: serializer.fromJson<String?>(json['nodeId']),
      encryptionPublicKey: serializer.fromJson<String?>(
        json['encryptionPublicKey'],
      ),
      averageLatencyMs: serializer.fromJson<int>(json['averageLatencyMs']),
      successCount: serializer.fromJson<int>(json['successCount']),
      failureCount: serializer.fromJson<int>(json['failureCount']),
      lastSeen: serializer.fromJson<DateTime?>(json['lastSeen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'address': serializer.toJson<String>(address),
      'nodeId': serializer.toJson<String?>(nodeId),
      'encryptionPublicKey': serializer.toJson<String?>(encryptionPublicKey),
      'averageLatencyMs': serializer.toJson<int>(averageLatencyMs),
      'successCount': serializer.toJson<int>(successCount),
      'failureCount': serializer.toJson<int>(failureCount),
      'lastSeen': serializer.toJson<DateTime?>(lastSeen),
    };
  }

  Peer copyWith({
    String? address,
    Value<String?> nodeId = const Value.absent(),
    Value<String?> encryptionPublicKey = const Value.absent(),
    int? averageLatencyMs,
    int? successCount,
    int? failureCount,
    Value<DateTime?> lastSeen = const Value.absent(),
  }) => Peer(
    address: address ?? this.address,
    nodeId: nodeId.present ? nodeId.value : this.nodeId,
    encryptionPublicKey: encryptionPublicKey.present
        ? encryptionPublicKey.value
        : this.encryptionPublicKey,
    averageLatencyMs: averageLatencyMs ?? this.averageLatencyMs,
    successCount: successCount ?? this.successCount,
    failureCount: failureCount ?? this.failureCount,
    lastSeen: lastSeen.present ? lastSeen.value : this.lastSeen,
  );
  Peer copyWithCompanion(PeersCompanion data) {
    return Peer(
      address: data.address.present ? data.address.value : this.address,
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
      encryptionPublicKey: data.encryptionPublicKey.present
          ? data.encryptionPublicKey.value
          : this.encryptionPublicKey,
      averageLatencyMs: data.averageLatencyMs.present
          ? data.averageLatencyMs.value
          : this.averageLatencyMs,
      successCount: data.successCount.present
          ? data.successCount.value
          : this.successCount,
      failureCount: data.failureCount.present
          ? data.failureCount.value
          : this.failureCount,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Peer(')
          ..write('address: $address, ')
          ..write('nodeId: $nodeId, ')
          ..write('encryptionPublicKey: $encryptionPublicKey, ')
          ..write('averageLatencyMs: $averageLatencyMs, ')
          ..write('successCount: $successCount, ')
          ..write('failureCount: $failureCount, ')
          ..write('lastSeen: $lastSeen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    address,
    nodeId,
    encryptionPublicKey,
    averageLatencyMs,
    successCount,
    failureCount,
    lastSeen,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Peer &&
          other.address == this.address &&
          other.nodeId == this.nodeId &&
          other.encryptionPublicKey == this.encryptionPublicKey &&
          other.averageLatencyMs == this.averageLatencyMs &&
          other.successCount == this.successCount &&
          other.failureCount == this.failureCount &&
          other.lastSeen == this.lastSeen);
}

class PeersCompanion extends UpdateCompanion<Peer> {
  final Value<String> address;
  final Value<String?> nodeId;
  final Value<String?> encryptionPublicKey;
  final Value<int> averageLatencyMs;
  final Value<int> successCount;
  final Value<int> failureCount;
  final Value<DateTime?> lastSeen;
  final Value<int> rowid;
  const PeersCompanion({
    this.address = const Value.absent(),
    this.nodeId = const Value.absent(),
    this.encryptionPublicKey = const Value.absent(),
    this.averageLatencyMs = const Value.absent(),
    this.successCount = const Value.absent(),
    this.failureCount = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeersCompanion.insert({
    required String address,
    this.nodeId = const Value.absent(),
    this.encryptionPublicKey = const Value.absent(),
    this.averageLatencyMs = const Value.absent(),
    this.successCount = const Value.absent(),
    this.failureCount = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : address = Value(address);
  static Insertable<Peer> custom({
    Expression<String>? address,
    Expression<String>? nodeId,
    Expression<String>? encryptionPublicKey,
    Expression<int>? averageLatencyMs,
    Expression<int>? successCount,
    Expression<int>? failureCount,
    Expression<DateTime>? lastSeen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (address != null) 'address': address,
      if (nodeId != null) 'node_id': nodeId,
      if (encryptionPublicKey != null)
        'encryption_public_key': encryptionPublicKey,
      if (averageLatencyMs != null) 'average_latency_ms': averageLatencyMs,
      if (successCount != null) 'success_count': successCount,
      if (failureCount != null) 'failure_count': failureCount,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeersCompanion copyWith({
    Value<String>? address,
    Value<String?>? nodeId,
    Value<String?>? encryptionPublicKey,
    Value<int>? averageLatencyMs,
    Value<int>? successCount,
    Value<int>? failureCount,
    Value<DateTime?>? lastSeen,
    Value<int>? rowid,
  }) {
    return PeersCompanion(
      address: address ?? this.address,
      nodeId: nodeId ?? this.nodeId,
      encryptionPublicKey: encryptionPublicKey ?? this.encryptionPublicKey,
      averageLatencyMs: averageLatencyMs ?? this.averageLatencyMs,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
      lastSeen: lastSeen ?? this.lastSeen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (nodeId.present) {
      map['node_id'] = Variable<String>(nodeId.value);
    }
    if (encryptionPublicKey.present) {
      map['encryption_public_key'] = Variable<String>(
        encryptionPublicKey.value,
      );
    }
    if (averageLatencyMs.present) {
      map['average_latency_ms'] = Variable<int>(averageLatencyMs.value);
    }
    if (successCount.present) {
      map['success_count'] = Variable<int>(successCount.value);
    }
    if (failureCount.present) {
      map['failure_count'] = Variable<int>(failureCount.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeersCompanion(')
          ..write('address: $address, ')
          ..write('nodeId: $nodeId, ')
          ..write('encryptionPublicKey: $encryptionPublicKey, ')
          ..write('averageLatencyMs: $averageLatencyMs, ')
          ..write('successCount: $successCount, ')
          ..write('failureCount: $failureCount, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboundHandlesTable extends OutboundHandles
    with TableInfo<$OutboundHandlesTable, OutboundHandle> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboundHandlesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _ohIdMeta = const VerificationMeta('ohId');
  @override
  late final GeneratedColumn<String> ohId = GeneratedColumn<String>(
    'oh_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keypairBytesMeta = const VerificationMeta(
    'keypairBytes',
  );
  @override
  late final GeneratedColumn<Uint8List> keypairBytes =
      GeneratedColumn<Uint8List>(
        'keypair_bytes',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _serverEndpointMeta = const VerificationMeta(
    'serverEndpoint',
  );
  @override
  late final GeneratedColumn<String> serverEndpoint = GeneratedColumn<String>(
    'server_endpoint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelIdMeta = const VerificationMeta(
    'channelId',
  );
  @override
  late final GeneratedColumn<String> channelId = GeneratedColumn<String>(
    'channel_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCursorMeta = const VerificationMeta(
    'lastCursor',
  );
  @override
  late final GeneratedColumn<int> lastCursor = GeneratedColumn<int>(
    'last_cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _failedOverAtMeta = const VerificationMeta(
    'failedOverAt',
  );
  @override
  late final GeneratedColumn<DateTime> failedOverAt = GeneratedColumn<DateTime>(
    'failed_over_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ohId,
    keypairBytes,
    serverEndpoint,
    expiresAt,
    channelId,
    lastCursor,
    failedOverAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbound_handles';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboundHandle> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('oh_id')) {
      context.handle(
        _ohIdMeta,
        ohId.isAcceptableOrUnknown(data['oh_id']!, _ohIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ohIdMeta);
    }
    if (data.containsKey('keypair_bytes')) {
      context.handle(
        _keypairBytesMeta,
        keypairBytes.isAcceptableOrUnknown(
          data['keypair_bytes']!,
          _keypairBytesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_keypairBytesMeta);
    }
    if (data.containsKey('server_endpoint')) {
      context.handle(
        _serverEndpointMeta,
        serverEndpoint.isAcceptableOrUnknown(
          data['server_endpoint']!,
          _serverEndpointMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverEndpointMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('channel_id')) {
      context.handle(
        _channelIdMeta,
        channelId.isAcceptableOrUnknown(data['channel_id']!, _channelIdMeta),
      );
    }
    if (data.containsKey('last_cursor')) {
      context.handle(
        _lastCursorMeta,
        lastCursor.isAcceptableOrUnknown(data['last_cursor']!, _lastCursorMeta),
      );
    }
    if (data.containsKey('failed_over_at')) {
      context.handle(
        _failedOverAtMeta,
        failedOverAt.isAcceptableOrUnknown(
          data['failed_over_at']!,
          _failedOverAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboundHandle map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboundHandle(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      ohId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}oh_id'],
      )!,
      keypairBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}keypair_bytes'],
      )!,
      serverEndpoint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_endpoint'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      )!,
      channelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel_id'],
      ),
      lastCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_cursor'],
      )!,
      failedOverAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}failed_over_at'],
      ),
    );
  }

  @override
  $OutboundHandlesTable createAlias(String alias) {
    return $OutboundHandlesTable(attachedDatabase, alias);
  }
}

class OutboundHandle extends DataClass implements Insertable<OutboundHandle> {
  final int id;
  final String ohId;
  final Uint8List keypairBytes;
  final String serverEndpoint;
  final DateTime expiresAt;
  final String? channelId;
  final int lastCursor;
  final DateTime? failedOverAt;
  const OutboundHandle({
    required this.id,
    required this.ohId,
    required this.keypairBytes,
    required this.serverEndpoint,
    required this.expiresAt,
    this.channelId,
    required this.lastCursor,
    this.failedOverAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['oh_id'] = Variable<String>(ohId);
    map['keypair_bytes'] = Variable<Uint8List>(keypairBytes);
    map['server_endpoint'] = Variable<String>(serverEndpoint);
    map['expires_at'] = Variable<DateTime>(expiresAt);
    if (!nullToAbsent || channelId != null) {
      map['channel_id'] = Variable<String>(channelId);
    }
    map['last_cursor'] = Variable<int>(lastCursor);
    if (!nullToAbsent || failedOverAt != null) {
      map['failed_over_at'] = Variable<DateTime>(failedOverAt);
    }
    return map;
  }

  OutboundHandlesCompanion toCompanion(bool nullToAbsent) {
    return OutboundHandlesCompanion(
      id: Value(id),
      ohId: Value(ohId),
      keypairBytes: Value(keypairBytes),
      serverEndpoint: Value(serverEndpoint),
      expiresAt: Value(expiresAt),
      channelId: channelId == null && nullToAbsent
          ? const Value.absent()
          : Value(channelId),
      lastCursor: Value(lastCursor),
      failedOverAt: failedOverAt == null && nullToAbsent
          ? const Value.absent()
          : Value(failedOverAt),
    );
  }

  factory OutboundHandle.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboundHandle(
      id: serializer.fromJson<int>(json['id']),
      ohId: serializer.fromJson<String>(json['ohId']),
      keypairBytes: serializer.fromJson<Uint8List>(json['keypairBytes']),
      serverEndpoint: serializer.fromJson<String>(json['serverEndpoint']),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
      channelId: serializer.fromJson<String?>(json['channelId']),
      lastCursor: serializer.fromJson<int>(json['lastCursor']),
      failedOverAt: serializer.fromJson<DateTime?>(json['failedOverAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'ohId': serializer.toJson<String>(ohId),
      'keypairBytes': serializer.toJson<Uint8List>(keypairBytes),
      'serverEndpoint': serializer.toJson<String>(serverEndpoint),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
      'channelId': serializer.toJson<String?>(channelId),
      'lastCursor': serializer.toJson<int>(lastCursor),
      'failedOverAt': serializer.toJson<DateTime?>(failedOverAt),
    };
  }

  OutboundHandle copyWith({
    int? id,
    String? ohId,
    Uint8List? keypairBytes,
    String? serverEndpoint,
    DateTime? expiresAt,
    Value<String?> channelId = const Value.absent(),
    int? lastCursor,
    Value<DateTime?> failedOverAt = const Value.absent(),
  }) => OutboundHandle(
    id: id ?? this.id,
    ohId: ohId ?? this.ohId,
    keypairBytes: keypairBytes ?? this.keypairBytes,
    serverEndpoint: serverEndpoint ?? this.serverEndpoint,
    expiresAt: expiresAt ?? this.expiresAt,
    channelId: channelId.present ? channelId.value : this.channelId,
    lastCursor: lastCursor ?? this.lastCursor,
    failedOverAt: failedOverAt.present ? failedOverAt.value : this.failedOverAt,
  );
  OutboundHandle copyWithCompanion(OutboundHandlesCompanion data) {
    return OutboundHandle(
      id: data.id.present ? data.id.value : this.id,
      ohId: data.ohId.present ? data.ohId.value : this.ohId,
      keypairBytes: data.keypairBytes.present
          ? data.keypairBytes.value
          : this.keypairBytes,
      serverEndpoint: data.serverEndpoint.present
          ? data.serverEndpoint.value
          : this.serverEndpoint,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      channelId: data.channelId.present ? data.channelId.value : this.channelId,
      lastCursor: data.lastCursor.present
          ? data.lastCursor.value
          : this.lastCursor,
      failedOverAt: data.failedOverAt.present
          ? data.failedOverAt.value
          : this.failedOverAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboundHandle(')
          ..write('id: $id, ')
          ..write('ohId: $ohId, ')
          ..write('keypairBytes: $keypairBytes, ')
          ..write('serverEndpoint: $serverEndpoint, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('channelId: $channelId, ')
          ..write('lastCursor: $lastCursor, ')
          ..write('failedOverAt: $failedOverAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ohId,
    $driftBlobEquality.hash(keypairBytes),
    serverEndpoint,
    expiresAt,
    channelId,
    lastCursor,
    failedOverAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboundHandle &&
          other.id == this.id &&
          other.ohId == this.ohId &&
          $driftBlobEquality.equals(other.keypairBytes, this.keypairBytes) &&
          other.serverEndpoint == this.serverEndpoint &&
          other.expiresAt == this.expiresAt &&
          other.channelId == this.channelId &&
          other.lastCursor == this.lastCursor &&
          other.failedOverAt == this.failedOverAt);
}

class OutboundHandlesCompanion extends UpdateCompanion<OutboundHandle> {
  final Value<int> id;
  final Value<String> ohId;
  final Value<Uint8List> keypairBytes;
  final Value<String> serverEndpoint;
  final Value<DateTime> expiresAt;
  final Value<String?> channelId;
  final Value<int> lastCursor;
  final Value<DateTime?> failedOverAt;
  const OutboundHandlesCompanion({
    this.id = const Value.absent(),
    this.ohId = const Value.absent(),
    this.keypairBytes = const Value.absent(),
    this.serverEndpoint = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.channelId = const Value.absent(),
    this.lastCursor = const Value.absent(),
    this.failedOverAt = const Value.absent(),
  });
  OutboundHandlesCompanion.insert({
    this.id = const Value.absent(),
    required String ohId,
    required Uint8List keypairBytes,
    required String serverEndpoint,
    required DateTime expiresAt,
    this.channelId = const Value.absent(),
    this.lastCursor = const Value.absent(),
    this.failedOverAt = const Value.absent(),
  }) : ohId = Value(ohId),
       keypairBytes = Value(keypairBytes),
       serverEndpoint = Value(serverEndpoint),
       expiresAt = Value(expiresAt);
  static Insertable<OutboundHandle> custom({
    Expression<int>? id,
    Expression<String>? ohId,
    Expression<Uint8List>? keypairBytes,
    Expression<String>? serverEndpoint,
    Expression<DateTime>? expiresAt,
    Expression<String>? channelId,
    Expression<int>? lastCursor,
    Expression<DateTime>? failedOverAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ohId != null) 'oh_id': ohId,
      if (keypairBytes != null) 'keypair_bytes': keypairBytes,
      if (serverEndpoint != null) 'server_endpoint': serverEndpoint,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (channelId != null) 'channel_id': channelId,
      if (lastCursor != null) 'last_cursor': lastCursor,
      if (failedOverAt != null) 'failed_over_at': failedOverAt,
    });
  }

  OutboundHandlesCompanion copyWith({
    Value<int>? id,
    Value<String>? ohId,
    Value<Uint8List>? keypairBytes,
    Value<String>? serverEndpoint,
    Value<DateTime>? expiresAt,
    Value<String?>? channelId,
    Value<int>? lastCursor,
    Value<DateTime?>? failedOverAt,
  }) {
    return OutboundHandlesCompanion(
      id: id ?? this.id,
      ohId: ohId ?? this.ohId,
      keypairBytes: keypairBytes ?? this.keypairBytes,
      serverEndpoint: serverEndpoint ?? this.serverEndpoint,
      expiresAt: expiresAt ?? this.expiresAt,
      channelId: channelId ?? this.channelId,
      lastCursor: lastCursor ?? this.lastCursor,
      failedOverAt: failedOverAt ?? this.failedOverAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (ohId.present) {
      map['oh_id'] = Variable<String>(ohId.value);
    }
    if (keypairBytes.present) {
      map['keypair_bytes'] = Variable<Uint8List>(keypairBytes.value);
    }
    if (serverEndpoint.present) {
      map['server_endpoint'] = Variable<String>(serverEndpoint.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (channelId.present) {
      map['channel_id'] = Variable<String>(channelId.value);
    }
    if (lastCursor.present) {
      map['last_cursor'] = Variable<int>(lastCursor.value);
    }
    if (failedOverAt.present) {
      map['failed_over_at'] = Variable<DateTime>(failedOverAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboundHandlesCompanion(')
          ..write('id: $id, ')
          ..write('ohId: $ohId, ')
          ..write('keypairBytes: $keypairBytes, ')
          ..write('serverEndpoint: $serverEndpoint, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('channelId: $channelId, ')
          ..write('lastCursor: $lastCursor, ')
          ..write('failedOverAt: $failedOverAt')
          ..write(')'))
        .toString();
  }
}

class $SessionTagsTable extends SessionTags
    with TableInfo<$SessionTagsTable, SessionTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
    'tag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelIdMeta = const VerificationMeta(
    'channelId',
  );
  @override
  late final GeneratedColumn<String> channelId = GeneratedColumn<String>(
    'channel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES channels (uuid)',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tag, channelId, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tag')) {
      context.handle(
        _tagMeta,
        tag.isAcceptableOrUnknown(data['tag']!, _tagMeta),
      );
    } else if (isInserting) {
      context.missing(_tagMeta);
    }
    if (data.containsKey('channel_id')) {
      context.handle(
        _channelIdMeta,
        channelId.isAcceptableOrUnknown(data['channel_id']!, _channelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_channelIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tag};
  @override
  SessionTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionTag(
      tag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag'],
      )!,
      channelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SessionTagsTable createAlias(String alias) {
    return $SessionTagsTable(attachedDatabase, alias);
  }
}

class SessionTag extends DataClass implements Insertable<SessionTag> {
  final String tag;
  final String channelId;
  final DateTime createdAt;
  const SessionTag({
    required this.tag,
    required this.channelId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tag'] = Variable<String>(tag);
    map['channel_id'] = Variable<String>(channelId);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SessionTagsCompanion toCompanion(bool nullToAbsent) {
    return SessionTagsCompanion(
      tag: Value(tag),
      channelId: Value(channelId),
      createdAt: Value(createdAt),
    );
  }

  factory SessionTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionTag(
      tag: serializer.fromJson<String>(json['tag']),
      channelId: serializer.fromJson<String>(json['channelId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tag': serializer.toJson<String>(tag),
      'channelId': serializer.toJson<String>(channelId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SessionTag copyWith({String? tag, String? channelId, DateTime? createdAt}) =>
      SessionTag(
        tag: tag ?? this.tag,
        channelId: channelId ?? this.channelId,
        createdAt: createdAt ?? this.createdAt,
      );
  SessionTag copyWithCompanion(SessionTagsCompanion data) {
    return SessionTag(
      tag: data.tag.present ? data.tag.value : this.tag,
      channelId: data.channelId.present ? data.channelId.value : this.channelId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionTag(')
          ..write('tag: $tag, ')
          ..write('channelId: $channelId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tag, channelId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionTag &&
          other.tag == this.tag &&
          other.channelId == this.channelId &&
          other.createdAt == this.createdAt);
}

class SessionTagsCompanion extends UpdateCompanion<SessionTag> {
  final Value<String> tag;
  final Value<String> channelId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SessionTagsCompanion({
    this.tag = const Value.absent(),
    this.channelId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionTagsCompanion.insert({
    required String tag,
    required String channelId,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : tag = Value(tag),
       channelId = Value(channelId),
       createdAt = Value(createdAt);
  static Insertable<SessionTag> custom({
    Expression<String>? tag,
    Expression<String>? channelId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tag != null) 'tag': tag,
      if (channelId != null) 'channel_id': channelId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionTagsCompanion copyWith({
    Value<String>? tag,
    Value<String>? channelId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SessionTagsCompanion(
      tag: tag ?? this.tag,
      channelId: channelId ?? this.channelId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (channelId.present) {
      map['channel_id'] = Variable<String>(channelId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionTagsCompanion(')
          ..write('tag: $tag, ')
          ..write('channelId: $channelId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NodeScoresTable extends NodeScores
    with TableInfo<$NodeScoresTable, NodeScoreRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NodeScoresTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nodeIdMeta = const VerificationMeta('nodeId');
  @override
  late final GeneratedColumn<String> nodeId = GeneratedColumn<String>(
    'node_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _successCountMeta = const VerificationMeta(
    'successCount',
  );
  @override
  late final GeneratedColumn<int> successCount = GeneratedColumn<int>(
    'success_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _failureCountMeta = const VerificationMeta(
    'failureCount',
  );
  @override
  late final GeneratedColumn<int> failureCount = GeneratedColumn<int>(
    'failure_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _avgLatencyMsMeta = const VerificationMeta(
    'avgLatencyMs',
  );
  @override
  late final GeneratedColumn<int> avgLatencyMs = GeneratedColumn<int>(
    'avg_latency_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastUpdatedMeta = const VerificationMeta(
    'lastUpdated',
  );
  @override
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
    'last_updated',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    nodeId,
    successCount,
    failureCount,
    avgLatencyMs,
    lastUpdated,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'node_scores';
  @override
  VerificationContext validateIntegrity(
    Insertable<NodeScoreRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('node_id')) {
      context.handle(
        _nodeIdMeta,
        nodeId.isAcceptableOrUnknown(data['node_id']!, _nodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeIdMeta);
    }
    if (data.containsKey('success_count')) {
      context.handle(
        _successCountMeta,
        successCount.isAcceptableOrUnknown(
          data['success_count']!,
          _successCountMeta,
        ),
      );
    }
    if (data.containsKey('failure_count')) {
      context.handle(
        _failureCountMeta,
        failureCount.isAcceptableOrUnknown(
          data['failure_count']!,
          _failureCountMeta,
        ),
      );
    }
    if (data.containsKey('avg_latency_ms')) {
      context.handle(
        _avgLatencyMsMeta,
        avgLatencyMs.isAcceptableOrUnknown(
          data['avg_latency_ms']!,
          _avgLatencyMsMeta,
        ),
      );
    }
    if (data.containsKey('last_updated')) {
      context.handle(
        _lastUpdatedMeta,
        lastUpdated.isAcceptableOrUnknown(
          data['last_updated']!,
          _lastUpdatedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {nodeId};
  @override
  NodeScoreRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NodeScoreRow(
      nodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_id'],
      )!,
      successCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}success_count'],
      )!,
      failureCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failure_count'],
      )!,
      avgLatencyMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}avg_latency_ms'],
      )!,
      lastUpdated: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_updated'],
      ),
    );
  }

  @override
  $NodeScoresTable createAlias(String alias) {
    return $NodeScoresTable(attachedDatabase, alias);
  }
}

class NodeScoreRow extends DataClass implements Insertable<NodeScoreRow> {
  final String nodeId;
  final int successCount;
  final int failureCount;
  final int avgLatencyMs;
  final DateTime? lastUpdated;
  const NodeScoreRow({
    required this.nodeId,
    required this.successCount,
    required this.failureCount,
    required this.avgLatencyMs,
    this.lastUpdated,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['node_id'] = Variable<String>(nodeId);
    map['success_count'] = Variable<int>(successCount);
    map['failure_count'] = Variable<int>(failureCount);
    map['avg_latency_ms'] = Variable<int>(avgLatencyMs);
    if (!nullToAbsent || lastUpdated != null) {
      map['last_updated'] = Variable<DateTime>(lastUpdated);
    }
    return map;
  }

  NodeScoresCompanion toCompanion(bool nullToAbsent) {
    return NodeScoresCompanion(
      nodeId: Value(nodeId),
      successCount: Value(successCount),
      failureCount: Value(failureCount),
      avgLatencyMs: Value(avgLatencyMs),
      lastUpdated: lastUpdated == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUpdated),
    );
  }

  factory NodeScoreRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NodeScoreRow(
      nodeId: serializer.fromJson<String>(json['nodeId']),
      successCount: serializer.fromJson<int>(json['successCount']),
      failureCount: serializer.fromJson<int>(json['failureCount']),
      avgLatencyMs: serializer.fromJson<int>(json['avgLatencyMs']),
      lastUpdated: serializer.fromJson<DateTime?>(json['lastUpdated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'nodeId': serializer.toJson<String>(nodeId),
      'successCount': serializer.toJson<int>(successCount),
      'failureCount': serializer.toJson<int>(failureCount),
      'avgLatencyMs': serializer.toJson<int>(avgLatencyMs),
      'lastUpdated': serializer.toJson<DateTime?>(lastUpdated),
    };
  }

  NodeScoreRow copyWith({
    String? nodeId,
    int? successCount,
    int? failureCount,
    int? avgLatencyMs,
    Value<DateTime?> lastUpdated = const Value.absent(),
  }) => NodeScoreRow(
    nodeId: nodeId ?? this.nodeId,
    successCount: successCount ?? this.successCount,
    failureCount: failureCount ?? this.failureCount,
    avgLatencyMs: avgLatencyMs ?? this.avgLatencyMs,
    lastUpdated: lastUpdated.present ? lastUpdated.value : this.lastUpdated,
  );
  NodeScoreRow copyWithCompanion(NodeScoresCompanion data) {
    return NodeScoreRow(
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
      successCount: data.successCount.present
          ? data.successCount.value
          : this.successCount,
      failureCount: data.failureCount.present
          ? data.failureCount.value
          : this.failureCount,
      avgLatencyMs: data.avgLatencyMs.present
          ? data.avgLatencyMs.value
          : this.avgLatencyMs,
      lastUpdated: data.lastUpdated.present
          ? data.lastUpdated.value
          : this.lastUpdated,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NodeScoreRow(')
          ..write('nodeId: $nodeId, ')
          ..write('successCount: $successCount, ')
          ..write('failureCount: $failureCount, ')
          ..write('avgLatencyMs: $avgLatencyMs, ')
          ..write('lastUpdated: $lastUpdated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    nodeId,
    successCount,
    failureCount,
    avgLatencyMs,
    lastUpdated,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NodeScoreRow &&
          other.nodeId == this.nodeId &&
          other.successCount == this.successCount &&
          other.failureCount == this.failureCount &&
          other.avgLatencyMs == this.avgLatencyMs &&
          other.lastUpdated == this.lastUpdated);
}

class NodeScoresCompanion extends UpdateCompanion<NodeScoreRow> {
  final Value<String> nodeId;
  final Value<int> successCount;
  final Value<int> failureCount;
  final Value<int> avgLatencyMs;
  final Value<DateTime?> lastUpdated;
  final Value<int> rowid;
  const NodeScoresCompanion({
    this.nodeId = const Value.absent(),
    this.successCount = const Value.absent(),
    this.failureCount = const Value.absent(),
    this.avgLatencyMs = const Value.absent(),
    this.lastUpdated = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NodeScoresCompanion.insert({
    required String nodeId,
    this.successCount = const Value.absent(),
    this.failureCount = const Value.absent(),
    this.avgLatencyMs = const Value.absent(),
    this.lastUpdated = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : nodeId = Value(nodeId);
  static Insertable<NodeScoreRow> custom({
    Expression<String>? nodeId,
    Expression<int>? successCount,
    Expression<int>? failureCount,
    Expression<int>? avgLatencyMs,
    Expression<DateTime>? lastUpdated,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (nodeId != null) 'node_id': nodeId,
      if (successCount != null) 'success_count': successCount,
      if (failureCount != null) 'failure_count': failureCount,
      if (avgLatencyMs != null) 'avg_latency_ms': avgLatencyMs,
      if (lastUpdated != null) 'last_updated': lastUpdated,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NodeScoresCompanion copyWith({
    Value<String>? nodeId,
    Value<int>? successCount,
    Value<int>? failureCount,
    Value<int>? avgLatencyMs,
    Value<DateTime?>? lastUpdated,
    Value<int>? rowid,
  }) {
    return NodeScoresCompanion(
      nodeId: nodeId ?? this.nodeId,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
      avgLatencyMs: avgLatencyMs ?? this.avgLatencyMs,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (nodeId.present) {
      map['node_id'] = Variable<String>(nodeId.value);
    }
    if (successCount.present) {
      map['success_count'] = Variable<int>(successCount.value);
    }
    if (failureCount.present) {
      map['failure_count'] = Variable<int>(failureCount.value);
    }
    if (avgLatencyMs.present) {
      map['avg_latency_ms'] = Variable<int>(avgLatencyMs.value);
    }
    if (lastUpdated.present) {
      map['last_updated'] = Variable<DateTime>(lastUpdated.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NodeScoresCompanion(')
          ..write('nodeId: $nodeId, ')
          ..write('successCount: $successCount, ')
          ..write('failureCount: $failureCount, ')
          ..write('avgLatencyMs: $avgLatencyMs, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupChannelsTable extends GroupChannels
    with TableInfo<$GroupChannelsTable, GroupChannelRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupChannelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isAdminMeta = const VerificationMeta(
    'isAdmin',
  );
  @override
  late final GeneratedColumn<bool> isAdmin = GeneratedColumn<bool>(
    'is_admin',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_admin" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _myMemberIdMeta = const VerificationMeta(
    'myMemberId',
  );
  @override
  late final GeneratedColumn<String> myMemberId = GeneratedColumn<String>(
    'my_member_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mySignSeedMeta = const VerificationMeta(
    'mySignSeed',
  );
  @override
  late final GeneratedColumn<String> mySignSeed = GeneratedColumn<String>(
    'my_sign_seed',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _myX25519PrivMeta = const VerificationMeta(
    'myX25519Priv',
  );
  @override
  late final GeneratedColumn<String> myX25519Priv = GeneratedColumn<String>(
    'my_x25519_priv',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyEpochMeta = const VerificationMeta(
    'keyEpoch',
  );
  @override
  late final GeneratedColumn<int> keyEpoch = GeneratedColumn<int>(
    'key_epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cryptoStateMeta = const VerificationMeta(
    'cryptoState',
  );
  @override
  late final GeneratedColumn<String> cryptoState = GeneratedColumn<String>(
    'crypto_state',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pendingRotationsMeta = const VerificationMeta(
    'pendingRotations',
  );
  @override
  late final GeneratedColumn<String> pendingRotations = GeneratedColumn<String>(
    'pending_rotations',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    label,
    isAdmin,
    myMemberId,
    mySignSeed,
    myX25519Priv,
    keyEpoch,
    cryptoState,
    pendingRotations,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_channels';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupChannelRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('is_admin')) {
      context.handle(
        _isAdminMeta,
        isAdmin.isAcceptableOrUnknown(data['is_admin']!, _isAdminMeta),
      );
    }
    if (data.containsKey('my_member_id')) {
      context.handle(
        _myMemberIdMeta,
        myMemberId.isAcceptableOrUnknown(
          data['my_member_id']!,
          _myMemberIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_myMemberIdMeta);
    }
    if (data.containsKey('my_sign_seed')) {
      context.handle(
        _mySignSeedMeta,
        mySignSeed.isAcceptableOrUnknown(
          data['my_sign_seed']!,
          _mySignSeedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mySignSeedMeta);
    }
    if (data.containsKey('my_x25519_priv')) {
      context.handle(
        _myX25519PrivMeta,
        myX25519Priv.isAcceptableOrUnknown(
          data['my_x25519_priv']!,
          _myX25519PrivMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_myX25519PrivMeta);
    }
    if (data.containsKey('key_epoch')) {
      context.handle(
        _keyEpochMeta,
        keyEpoch.isAcceptableOrUnknown(data['key_epoch']!, _keyEpochMeta),
      );
    }
    if (data.containsKey('crypto_state')) {
      context.handle(
        _cryptoStateMeta,
        cryptoState.isAcceptableOrUnknown(
          data['crypto_state']!,
          _cryptoStateMeta,
        ),
      );
    }
    if (data.containsKey('pending_rotations')) {
      context.handle(
        _pendingRotationsMeta,
        pendingRotations.isAcceptableOrUnknown(
          data['pending_rotations']!,
          _pendingRotationsMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId};
  @override
  GroupChannelRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupChannelRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      isAdmin: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_admin'],
      )!,
      myMemberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}my_member_id'],
      )!,
      mySignSeed: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}my_sign_seed'],
      )!,
      myX25519Priv: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}my_x25519_priv'],
      )!,
      keyEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}key_epoch'],
      )!,
      cryptoState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}crypto_state'],
      ),
      pendingRotations: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pending_rotations'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
    );
  }

  @override
  $GroupChannelsTable createAlias(String alias) {
    return $GroupChannelsTable(attachedDatabase, alias);
  }
}

class GroupChannelRow extends DataClass implements Insertable<GroupChannelRow> {
  final String groupId;
  final String label;
  final bool isAdmin;
  final String myMemberId;
  final String mySignSeed;
  final String myX25519Priv;
  final int keyEpoch;
  final String? cryptoState;
  final String? pendingRotations;
  final DateTime? createdAt;
  const GroupChannelRow({
    required this.groupId,
    required this.label,
    required this.isAdmin,
    required this.myMemberId,
    required this.mySignSeed,
    required this.myX25519Priv,
    required this.keyEpoch,
    this.cryptoState,
    this.pendingRotations,
    this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['label'] = Variable<String>(label);
    map['is_admin'] = Variable<bool>(isAdmin);
    map['my_member_id'] = Variable<String>(myMemberId);
    map['my_sign_seed'] = Variable<String>(mySignSeed);
    map['my_x25519_priv'] = Variable<String>(myX25519Priv);
    map['key_epoch'] = Variable<int>(keyEpoch);
    if (!nullToAbsent || cryptoState != null) {
      map['crypto_state'] = Variable<String>(cryptoState);
    }
    if (!nullToAbsent || pendingRotations != null) {
      map['pending_rotations'] = Variable<String>(pendingRotations);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    return map;
  }

  GroupChannelsCompanion toCompanion(bool nullToAbsent) {
    return GroupChannelsCompanion(
      groupId: Value(groupId),
      label: Value(label),
      isAdmin: Value(isAdmin),
      myMemberId: Value(myMemberId),
      mySignSeed: Value(mySignSeed),
      myX25519Priv: Value(myX25519Priv),
      keyEpoch: Value(keyEpoch),
      cryptoState: cryptoState == null && nullToAbsent
          ? const Value.absent()
          : Value(cryptoState),
      pendingRotations: pendingRotations == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingRotations),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
    );
  }

  factory GroupChannelRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupChannelRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      label: serializer.fromJson<String>(json['label']),
      isAdmin: serializer.fromJson<bool>(json['isAdmin']),
      myMemberId: serializer.fromJson<String>(json['myMemberId']),
      mySignSeed: serializer.fromJson<String>(json['mySignSeed']),
      myX25519Priv: serializer.fromJson<String>(json['myX25519Priv']),
      keyEpoch: serializer.fromJson<int>(json['keyEpoch']),
      cryptoState: serializer.fromJson<String?>(json['cryptoState']),
      pendingRotations: serializer.fromJson<String?>(json['pendingRotations']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'label': serializer.toJson<String>(label),
      'isAdmin': serializer.toJson<bool>(isAdmin),
      'myMemberId': serializer.toJson<String>(myMemberId),
      'mySignSeed': serializer.toJson<String>(mySignSeed),
      'myX25519Priv': serializer.toJson<String>(myX25519Priv),
      'keyEpoch': serializer.toJson<int>(keyEpoch),
      'cryptoState': serializer.toJson<String?>(cryptoState),
      'pendingRotations': serializer.toJson<String?>(pendingRotations),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
    };
  }

  GroupChannelRow copyWith({
    String? groupId,
    String? label,
    bool? isAdmin,
    String? myMemberId,
    String? mySignSeed,
    String? myX25519Priv,
    int? keyEpoch,
    Value<String?> cryptoState = const Value.absent(),
    Value<String?> pendingRotations = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
  }) => GroupChannelRow(
    groupId: groupId ?? this.groupId,
    label: label ?? this.label,
    isAdmin: isAdmin ?? this.isAdmin,
    myMemberId: myMemberId ?? this.myMemberId,
    mySignSeed: mySignSeed ?? this.mySignSeed,
    myX25519Priv: myX25519Priv ?? this.myX25519Priv,
    keyEpoch: keyEpoch ?? this.keyEpoch,
    cryptoState: cryptoState.present ? cryptoState.value : this.cryptoState,
    pendingRotations: pendingRotations.present
        ? pendingRotations.value
        : this.pendingRotations,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
  );
  GroupChannelRow copyWithCompanion(GroupChannelsCompanion data) {
    return GroupChannelRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      label: data.label.present ? data.label.value : this.label,
      isAdmin: data.isAdmin.present ? data.isAdmin.value : this.isAdmin,
      myMemberId: data.myMemberId.present
          ? data.myMemberId.value
          : this.myMemberId,
      mySignSeed: data.mySignSeed.present
          ? data.mySignSeed.value
          : this.mySignSeed,
      myX25519Priv: data.myX25519Priv.present
          ? data.myX25519Priv.value
          : this.myX25519Priv,
      keyEpoch: data.keyEpoch.present ? data.keyEpoch.value : this.keyEpoch,
      cryptoState: data.cryptoState.present
          ? data.cryptoState.value
          : this.cryptoState,
      pendingRotations: data.pendingRotations.present
          ? data.pendingRotations.value
          : this.pendingRotations,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupChannelRow(')
          ..write('groupId: $groupId, ')
          ..write('label: $label, ')
          ..write('isAdmin: $isAdmin, ')
          ..write('myMemberId: $myMemberId, ')
          ..write('mySignSeed: $mySignSeed, ')
          ..write('myX25519Priv: $myX25519Priv, ')
          ..write('keyEpoch: $keyEpoch, ')
          ..write('cryptoState: $cryptoState, ')
          ..write('pendingRotations: $pendingRotations, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    label,
    isAdmin,
    myMemberId,
    mySignSeed,
    myX25519Priv,
    keyEpoch,
    cryptoState,
    pendingRotations,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupChannelRow &&
          other.groupId == this.groupId &&
          other.label == this.label &&
          other.isAdmin == this.isAdmin &&
          other.myMemberId == this.myMemberId &&
          other.mySignSeed == this.mySignSeed &&
          other.myX25519Priv == this.myX25519Priv &&
          other.keyEpoch == this.keyEpoch &&
          other.cryptoState == this.cryptoState &&
          other.pendingRotations == this.pendingRotations &&
          other.createdAt == this.createdAt);
}

class GroupChannelsCompanion extends UpdateCompanion<GroupChannelRow> {
  final Value<String> groupId;
  final Value<String> label;
  final Value<bool> isAdmin;
  final Value<String> myMemberId;
  final Value<String> mySignSeed;
  final Value<String> myX25519Priv;
  final Value<int> keyEpoch;
  final Value<String?> cryptoState;
  final Value<String?> pendingRotations;
  final Value<DateTime?> createdAt;
  final Value<int> rowid;
  const GroupChannelsCompanion({
    this.groupId = const Value.absent(),
    this.label = const Value.absent(),
    this.isAdmin = const Value.absent(),
    this.myMemberId = const Value.absent(),
    this.mySignSeed = const Value.absent(),
    this.myX25519Priv = const Value.absent(),
    this.keyEpoch = const Value.absent(),
    this.cryptoState = const Value.absent(),
    this.pendingRotations = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupChannelsCompanion.insert({
    required String groupId,
    required String label,
    this.isAdmin = const Value.absent(),
    required String myMemberId,
    required String mySignSeed,
    required String myX25519Priv,
    this.keyEpoch = const Value.absent(),
    this.cryptoState = const Value.absent(),
    this.pendingRotations = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       label = Value(label),
       myMemberId = Value(myMemberId),
       mySignSeed = Value(mySignSeed),
       myX25519Priv = Value(myX25519Priv);
  static Insertable<GroupChannelRow> custom({
    Expression<String>? groupId,
    Expression<String>? label,
    Expression<bool>? isAdmin,
    Expression<String>? myMemberId,
    Expression<String>? mySignSeed,
    Expression<String>? myX25519Priv,
    Expression<int>? keyEpoch,
    Expression<String>? cryptoState,
    Expression<String>? pendingRotations,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (label != null) 'label': label,
      if (isAdmin != null) 'is_admin': isAdmin,
      if (myMemberId != null) 'my_member_id': myMemberId,
      if (mySignSeed != null) 'my_sign_seed': mySignSeed,
      if (myX25519Priv != null) 'my_x25519_priv': myX25519Priv,
      if (keyEpoch != null) 'key_epoch': keyEpoch,
      if (cryptoState != null) 'crypto_state': cryptoState,
      if (pendingRotations != null) 'pending_rotations': pendingRotations,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupChannelsCompanion copyWith({
    Value<String>? groupId,
    Value<String>? label,
    Value<bool>? isAdmin,
    Value<String>? myMemberId,
    Value<String>? mySignSeed,
    Value<String>? myX25519Priv,
    Value<int>? keyEpoch,
    Value<String?>? cryptoState,
    Value<String?>? pendingRotations,
    Value<DateTime?>? createdAt,
    Value<int>? rowid,
  }) {
    return GroupChannelsCompanion(
      groupId: groupId ?? this.groupId,
      label: label ?? this.label,
      isAdmin: isAdmin ?? this.isAdmin,
      myMemberId: myMemberId ?? this.myMemberId,
      mySignSeed: mySignSeed ?? this.mySignSeed,
      myX25519Priv: myX25519Priv ?? this.myX25519Priv,
      keyEpoch: keyEpoch ?? this.keyEpoch,
      cryptoState: cryptoState ?? this.cryptoState,
      pendingRotations: pendingRotations ?? this.pendingRotations,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (isAdmin.present) {
      map['is_admin'] = Variable<bool>(isAdmin.value);
    }
    if (myMemberId.present) {
      map['my_member_id'] = Variable<String>(myMemberId.value);
    }
    if (mySignSeed.present) {
      map['my_sign_seed'] = Variable<String>(mySignSeed.value);
    }
    if (myX25519Priv.present) {
      map['my_x25519_priv'] = Variable<String>(myX25519Priv.value);
    }
    if (keyEpoch.present) {
      map['key_epoch'] = Variable<int>(keyEpoch.value);
    }
    if (cryptoState.present) {
      map['crypto_state'] = Variable<String>(cryptoState.value);
    }
    if (pendingRotations.present) {
      map['pending_rotations'] = Variable<String>(pendingRotations.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupChannelsCompanion(')
          ..write('groupId: $groupId, ')
          ..write('label: $label, ')
          ..write('isAdmin: $isAdmin, ')
          ..write('myMemberId: $myMemberId, ')
          ..write('mySignSeed: $mySignSeed, ')
          ..write('myX25519Priv: $myX25519Priv, ')
          ..write('keyEpoch: $keyEpoch, ')
          ..write('cryptoState: $cryptoState, ')
          ..write('pendingRotations: $pendingRotations, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupMembersTable extends GroupMembers
    with TableInfo<$GroupMembersTable, GroupMemberRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupMembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES group_channels (group_id)',
    ),
  );
  static const VerificationMeta _memberIdMeta = const VerificationMeta(
    'memberId',
  );
  @override
  late final GeneratedColumn<String> memberId = GeneratedColumn<String>(
    'member_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ohIdMeta = const VerificationMeta('ohId');
  @override
  late final GeneratedColumn<String> ohId = GeneratedColumn<String>(
    'oh_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ohEndpointMeta = const VerificationMeta(
    'ohEndpoint',
  );
  @override
  late final GeneratedColumn<String> ohEndpoint = GeneratedColumn<String>(
    'oh_endpoint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _x25519PubMeta = const VerificationMeta(
    'x25519Pub',
  );
  @override
  late final GeneratedColumn<String> x25519Pub = GeneratedColumn<String>(
    'x25519_pub',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<int> role = GeneratedColumn<int>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    memberId,
    displayName,
    ohId,
    ohEndpoint,
    x25519Pub,
    role,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_members';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupMemberRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('member_id')) {
      context.handle(
        _memberIdMeta,
        memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta),
      );
    } else if (isInserting) {
      context.missing(_memberIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('oh_id')) {
      context.handle(
        _ohIdMeta,
        ohId.isAcceptableOrUnknown(data['oh_id']!, _ohIdMeta),
      );
    }
    if (data.containsKey('oh_endpoint')) {
      context.handle(
        _ohEndpointMeta,
        ohEndpoint.isAcceptableOrUnknown(data['oh_endpoint']!, _ohEndpointMeta),
      );
    }
    if (data.containsKey('x25519_pub')) {
      context.handle(
        _x25519PubMeta,
        x25519Pub.isAcceptableOrUnknown(data['x25519_pub']!, _x25519PubMeta),
      );
    } else if (isInserting) {
      context.missing(_x25519PubMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, memberId};
  @override
  GroupMemberRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupMemberRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      memberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      ohId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}oh_id'],
      ),
      ohEndpoint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}oh_endpoint'],
      ),
      x25519Pub: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}x25519_pub'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}role'],
      )!,
    );
  }

  @override
  $GroupMembersTable createAlias(String alias) {
    return $GroupMembersTable(attachedDatabase, alias);
  }
}

class GroupMemberRow extends DataClass implements Insertable<GroupMemberRow> {
  final String groupId;
  final String memberId;
  final String displayName;
  final String? ohId;
  final String? ohEndpoint;
  final String x25519Pub;
  final int role;
  const GroupMemberRow({
    required this.groupId,
    required this.memberId,
    required this.displayName,
    this.ohId,
    this.ohEndpoint,
    required this.x25519Pub,
    required this.role,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['member_id'] = Variable<String>(memberId);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || ohId != null) {
      map['oh_id'] = Variable<String>(ohId);
    }
    if (!nullToAbsent || ohEndpoint != null) {
      map['oh_endpoint'] = Variable<String>(ohEndpoint);
    }
    map['x25519_pub'] = Variable<String>(x25519Pub);
    map['role'] = Variable<int>(role);
    return map;
  }

  GroupMembersCompanion toCompanion(bool nullToAbsent) {
    return GroupMembersCompanion(
      groupId: Value(groupId),
      memberId: Value(memberId),
      displayName: Value(displayName),
      ohId: ohId == null && nullToAbsent ? const Value.absent() : Value(ohId),
      ohEndpoint: ohEndpoint == null && nullToAbsent
          ? const Value.absent()
          : Value(ohEndpoint),
      x25519Pub: Value(x25519Pub),
      role: Value(role),
    );
  }

  factory GroupMemberRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupMemberRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      memberId: serializer.fromJson<String>(json['memberId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      ohId: serializer.fromJson<String?>(json['ohId']),
      ohEndpoint: serializer.fromJson<String?>(json['ohEndpoint']),
      x25519Pub: serializer.fromJson<String>(json['x25519Pub']),
      role: serializer.fromJson<int>(json['role']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'memberId': serializer.toJson<String>(memberId),
      'displayName': serializer.toJson<String>(displayName),
      'ohId': serializer.toJson<String?>(ohId),
      'ohEndpoint': serializer.toJson<String?>(ohEndpoint),
      'x25519Pub': serializer.toJson<String>(x25519Pub),
      'role': serializer.toJson<int>(role),
    };
  }

  GroupMemberRow copyWith({
    String? groupId,
    String? memberId,
    String? displayName,
    Value<String?> ohId = const Value.absent(),
    Value<String?> ohEndpoint = const Value.absent(),
    String? x25519Pub,
    int? role,
  }) => GroupMemberRow(
    groupId: groupId ?? this.groupId,
    memberId: memberId ?? this.memberId,
    displayName: displayName ?? this.displayName,
    ohId: ohId.present ? ohId.value : this.ohId,
    ohEndpoint: ohEndpoint.present ? ohEndpoint.value : this.ohEndpoint,
    x25519Pub: x25519Pub ?? this.x25519Pub,
    role: role ?? this.role,
  );
  GroupMemberRow copyWithCompanion(GroupMembersCompanion data) {
    return GroupMemberRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      ohId: data.ohId.present ? data.ohId.value : this.ohId,
      ohEndpoint: data.ohEndpoint.present
          ? data.ohEndpoint.value
          : this.ohEndpoint,
      x25519Pub: data.x25519Pub.present ? data.x25519Pub.value : this.x25519Pub,
      role: data.role.present ? data.role.value : this.role,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupMemberRow(')
          ..write('groupId: $groupId, ')
          ..write('memberId: $memberId, ')
          ..write('displayName: $displayName, ')
          ..write('ohId: $ohId, ')
          ..write('ohEndpoint: $ohEndpoint, ')
          ..write('x25519Pub: $x25519Pub, ')
          ..write('role: $role')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    memberId,
    displayName,
    ohId,
    ohEndpoint,
    x25519Pub,
    role,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupMemberRow &&
          other.groupId == this.groupId &&
          other.memberId == this.memberId &&
          other.displayName == this.displayName &&
          other.ohId == this.ohId &&
          other.ohEndpoint == this.ohEndpoint &&
          other.x25519Pub == this.x25519Pub &&
          other.role == this.role);
}

class GroupMembersCompanion extends UpdateCompanion<GroupMemberRow> {
  final Value<String> groupId;
  final Value<String> memberId;
  final Value<String> displayName;
  final Value<String?> ohId;
  final Value<String?> ohEndpoint;
  final Value<String> x25519Pub;
  final Value<int> role;
  final Value<int> rowid;
  const GroupMembersCompanion({
    this.groupId = const Value.absent(),
    this.memberId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.ohId = const Value.absent(),
    this.ohEndpoint = const Value.absent(),
    this.x25519Pub = const Value.absent(),
    this.role = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupMembersCompanion.insert({
    required String groupId,
    required String memberId,
    required String displayName,
    this.ohId = const Value.absent(),
    this.ohEndpoint = const Value.absent(),
    required String x25519Pub,
    required int role,
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       memberId = Value(memberId),
       displayName = Value(displayName),
       x25519Pub = Value(x25519Pub),
       role = Value(role);
  static Insertable<GroupMemberRow> custom({
    Expression<String>? groupId,
    Expression<String>? memberId,
    Expression<String>? displayName,
    Expression<String>? ohId,
    Expression<String>? ohEndpoint,
    Expression<String>? x25519Pub,
    Expression<int>? role,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (memberId != null) 'member_id': memberId,
      if (displayName != null) 'display_name': displayName,
      if (ohId != null) 'oh_id': ohId,
      if (ohEndpoint != null) 'oh_endpoint': ohEndpoint,
      if (x25519Pub != null) 'x25519_pub': x25519Pub,
      if (role != null) 'role': role,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupMembersCompanion copyWith({
    Value<String>? groupId,
    Value<String>? memberId,
    Value<String>? displayName,
    Value<String?>? ohId,
    Value<String?>? ohEndpoint,
    Value<String>? x25519Pub,
    Value<int>? role,
    Value<int>? rowid,
  }) {
    return GroupMembersCompanion(
      groupId: groupId ?? this.groupId,
      memberId: memberId ?? this.memberId,
      displayName: displayName ?? this.displayName,
      ohId: ohId ?? this.ohId,
      ohEndpoint: ohEndpoint ?? this.ohEndpoint,
      x25519Pub: x25519Pub ?? this.x25519Pub,
      role: role ?? this.role,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (memberId.present) {
      map['member_id'] = Variable<String>(memberId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (ohId.present) {
      map['oh_id'] = Variable<String>(ohId.value);
    }
    if (ohEndpoint.present) {
      map['oh_endpoint'] = Variable<String>(ohEndpoint.value);
    }
    if (x25519Pub.present) {
      map['x25519_pub'] = Variable<String>(x25519Pub.value);
    }
    if (role.present) {
      map['role'] = Variable<int>(role.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupMembersCompanion(')
          ..write('groupId: $groupId, ')
          ..write('memberId: $memberId, ')
          ..write('displayName: $displayName, ')
          ..write('ohId: $ohId, ')
          ..write('ohEndpoint: $ohEndpoint, ')
          ..write('x25519Pub: $x25519Pub, ')
          ..write('role: $role, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupPendingItemsTable extends GroupPendingItems
    with TableInfo<$GroupPendingItemsTable, GroupPendingItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupPendingItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES group_channels (group_id)',
    ),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta(
    'receivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> receivedAt = GeneratedColumn<DateTime>(
    'received_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, groupId, payload, receivedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_pending_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupPendingItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('received_at')) {
      context.handle(
        _receivedAtMeta,
        receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_receivedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GroupPendingItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupPendingItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}payload'],
      )!,
      receivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}received_at'],
      )!,
    );
  }

  @override
  $GroupPendingItemsTable createAlias(String alias) {
    return $GroupPendingItemsTable(attachedDatabase, alias);
  }
}

class GroupPendingItemRow extends DataClass
    implements Insertable<GroupPendingItemRow> {
  final int id;
  final String groupId;
  final Uint8List payload;
  final DateTime receivedAt;
  const GroupPendingItemRow({
    required this.id,
    required this.groupId,
    required this.payload,
    required this.receivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['group_id'] = Variable<String>(groupId);
    map['payload'] = Variable<Uint8List>(payload);
    map['received_at'] = Variable<DateTime>(receivedAt);
    return map;
  }

  GroupPendingItemsCompanion toCompanion(bool nullToAbsent) {
    return GroupPendingItemsCompanion(
      id: Value(id),
      groupId: Value(groupId),
      payload: Value(payload),
      receivedAt: Value(receivedAt),
    );
  }

  factory GroupPendingItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupPendingItemRow(
      id: serializer.fromJson<int>(json['id']),
      groupId: serializer.fromJson<String>(json['groupId']),
      payload: serializer.fromJson<Uint8List>(json['payload']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'groupId': serializer.toJson<String>(groupId),
      'payload': serializer.toJson<Uint8List>(payload),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
    };
  }

  GroupPendingItemRow copyWith({
    int? id,
    String? groupId,
    Uint8List? payload,
    DateTime? receivedAt,
  }) => GroupPendingItemRow(
    id: id ?? this.id,
    groupId: groupId ?? this.groupId,
    payload: payload ?? this.payload,
    receivedAt: receivedAt ?? this.receivedAt,
  );
  GroupPendingItemRow copyWithCompanion(GroupPendingItemsCompanion data) {
    return GroupPendingItemRow(
      id: data.id.present ? data.id.value : this.id,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      payload: data.payload.present ? data.payload.value : this.payload,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupPendingItemRow(')
          ..write('id: $id, ')
          ..write('groupId: $groupId, ')
          ..write('payload: $payload, ')
          ..write('receivedAt: $receivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, groupId, $driftBlobEquality.hash(payload), receivedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupPendingItemRow &&
          other.id == this.id &&
          other.groupId == this.groupId &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          other.receivedAt == this.receivedAt);
}

class GroupPendingItemsCompanion extends UpdateCompanion<GroupPendingItemRow> {
  final Value<int> id;
  final Value<String> groupId;
  final Value<Uint8List> payload;
  final Value<DateTime> receivedAt;
  const GroupPendingItemsCompanion({
    this.id = const Value.absent(),
    this.groupId = const Value.absent(),
    this.payload = const Value.absent(),
    this.receivedAt = const Value.absent(),
  });
  GroupPendingItemsCompanion.insert({
    this.id = const Value.absent(),
    required String groupId,
    required Uint8List payload,
    required DateTime receivedAt,
  }) : groupId = Value(groupId),
       payload = Value(payload),
       receivedAt = Value(receivedAt);
  static Insertable<GroupPendingItemRow> custom({
    Expression<int>? id,
    Expression<String>? groupId,
    Expression<Uint8List>? payload,
    Expression<DateTime>? receivedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (groupId != null) 'group_id': groupId,
      if (payload != null) 'payload': payload,
      if (receivedAt != null) 'received_at': receivedAt,
    });
  }

  GroupPendingItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? groupId,
    Value<Uint8List>? payload,
    Value<DateTime>? receivedAt,
  }) {
    return GroupPendingItemsCompanion(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      payload: payload ?? this.payload,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<DateTime>(receivedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupPendingItemsCompanion(')
          ..write('id: $id, ')
          ..write('groupId: $groupId, ')
          ..write('payload: $payload, ')
          ..write('receivedAt: $receivedAt')
          ..write(')'))
        .toString();
  }
}

class $GroupInvitesTable extends GroupInvites
    with TableInfo<$GroupInvitesTable, GroupInviteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupInvitesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupNameMeta = const VerificationMeta(
    'groupName',
  );
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
    'group_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _adminMemberIdMeta = const VerificationMeta(
    'adminMemberId',
  );
  @override
  late final GeneratedColumn<String> adminMemberId = GeneratedColumn<String>(
    'admin_member_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelIdMeta = const VerificationMeta(
    'channelId',
  );
  @override
  late final GeneratedColumn<String> channelId = GeneratedColumn<String>(
    'channel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta(
    'receivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> receivedAt = GeneratedColumn<DateTime>(
    'received_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    groupName,
    adminMemberId,
    channelId,
    receivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_invites';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupInviteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('group_name')) {
      context.handle(
        _groupNameMeta,
        groupName.isAcceptableOrUnknown(data['group_name']!, _groupNameMeta),
      );
    } else if (isInserting) {
      context.missing(_groupNameMeta);
    }
    if (data.containsKey('admin_member_id')) {
      context.handle(
        _adminMemberIdMeta,
        adminMemberId.isAcceptableOrUnknown(
          data['admin_member_id']!,
          _adminMemberIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_adminMemberIdMeta);
    }
    if (data.containsKey('channel_id')) {
      context.handle(
        _channelIdMeta,
        channelId.isAcceptableOrUnknown(data['channel_id']!, _channelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_channelIdMeta);
    }
    if (data.containsKey('received_at')) {
      context.handle(
        _receivedAtMeta,
        receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_receivedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId};
  @override
  GroupInviteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupInviteRow(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      groupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_name'],
      )!,
      adminMemberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}admin_member_id'],
      )!,
      channelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel_id'],
      )!,
      receivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}received_at'],
      )!,
    );
  }

  @override
  $GroupInvitesTable createAlias(String alias) {
    return $GroupInvitesTable(attachedDatabase, alias);
  }
}

class GroupInviteRow extends DataClass implements Insertable<GroupInviteRow> {
  final String groupId;
  final String groupName;
  final String adminMemberId;
  final String channelId;
  final DateTime receivedAt;
  const GroupInviteRow({
    required this.groupId,
    required this.groupName,
    required this.adminMemberId,
    required this.channelId,
    required this.receivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['group_name'] = Variable<String>(groupName);
    map['admin_member_id'] = Variable<String>(adminMemberId);
    map['channel_id'] = Variable<String>(channelId);
    map['received_at'] = Variable<DateTime>(receivedAt);
    return map;
  }

  GroupInvitesCompanion toCompanion(bool nullToAbsent) {
    return GroupInvitesCompanion(
      groupId: Value(groupId),
      groupName: Value(groupName),
      adminMemberId: Value(adminMemberId),
      channelId: Value(channelId),
      receivedAt: Value(receivedAt),
    );
  }

  factory GroupInviteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupInviteRow(
      groupId: serializer.fromJson<String>(json['groupId']),
      groupName: serializer.fromJson<String>(json['groupName']),
      adminMemberId: serializer.fromJson<String>(json['adminMemberId']),
      channelId: serializer.fromJson<String>(json['channelId']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'groupName': serializer.toJson<String>(groupName),
      'adminMemberId': serializer.toJson<String>(adminMemberId),
      'channelId': serializer.toJson<String>(channelId),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
    };
  }

  GroupInviteRow copyWith({
    String? groupId,
    String? groupName,
    String? adminMemberId,
    String? channelId,
    DateTime? receivedAt,
  }) => GroupInviteRow(
    groupId: groupId ?? this.groupId,
    groupName: groupName ?? this.groupName,
    adminMemberId: adminMemberId ?? this.adminMemberId,
    channelId: channelId ?? this.channelId,
    receivedAt: receivedAt ?? this.receivedAt,
  );
  GroupInviteRow copyWithCompanion(GroupInvitesCompanion data) {
    return GroupInviteRow(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      groupName: data.groupName.present ? data.groupName.value : this.groupName,
      adminMemberId: data.adminMemberId.present
          ? data.adminMemberId.value
          : this.adminMemberId,
      channelId: data.channelId.present ? data.channelId.value : this.channelId,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupInviteRow(')
          ..write('groupId: $groupId, ')
          ..write('groupName: $groupName, ')
          ..write('adminMemberId: $adminMemberId, ')
          ..write('channelId: $channelId, ')
          ..write('receivedAt: $receivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(groupId, groupName, adminMemberId, channelId, receivedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupInviteRow &&
          other.groupId == this.groupId &&
          other.groupName == this.groupName &&
          other.adminMemberId == this.adminMemberId &&
          other.channelId == this.channelId &&
          other.receivedAt == this.receivedAt);
}

class GroupInvitesCompanion extends UpdateCompanion<GroupInviteRow> {
  final Value<String> groupId;
  final Value<String> groupName;
  final Value<String> adminMemberId;
  final Value<String> channelId;
  final Value<DateTime> receivedAt;
  final Value<int> rowid;
  const GroupInvitesCompanion({
    this.groupId = const Value.absent(),
    this.groupName = const Value.absent(),
    this.adminMemberId = const Value.absent(),
    this.channelId = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupInvitesCompanion.insert({
    required String groupId,
    required String groupName,
    required String adminMemberId,
    required String channelId,
    required DateTime receivedAt,
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       groupName = Value(groupName),
       adminMemberId = Value(adminMemberId),
       channelId = Value(channelId),
       receivedAt = Value(receivedAt);
  static Insertable<GroupInviteRow> custom({
    Expression<String>? groupId,
    Expression<String>? groupName,
    Expression<String>? adminMemberId,
    Expression<String>? channelId,
    Expression<DateTime>? receivedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (groupName != null) 'group_name': groupName,
      if (adminMemberId != null) 'admin_member_id': adminMemberId,
      if (channelId != null) 'channel_id': channelId,
      if (receivedAt != null) 'received_at': receivedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupInvitesCompanion copyWith({
    Value<String>? groupId,
    Value<String>? groupName,
    Value<String>? adminMemberId,
    Value<String>? channelId,
    Value<DateTime>? receivedAt,
    Value<int>? rowid,
  }) {
    return GroupInvitesCompanion(
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      adminMemberId: adminMemberId ?? this.adminMemberId,
      channelId: channelId ?? this.channelId,
      receivedAt: receivedAt ?? this.receivedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (groupName.present) {
      map['group_name'] = Variable<String>(groupName.value);
    }
    if (adminMemberId.present) {
      map['admin_member_id'] = Variable<String>(adminMemberId.value);
    }
    if (channelId.present) {
      map['channel_id'] = Variable<String>(channelId.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<DateTime>(receivedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupInvitesCompanion(')
          ..write('groupId: $groupId, ')
          ..write('groupName: $groupName, ')
          ..write('adminMemberId: $adminMemberId, ')
          ..write('channelId: $channelId, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessageReceiptsTable extends MessageReceipts
    with TableInfo<$MessageReceiptsTable, MessageReceiptRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageReceiptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _memberIdMeta = const VerificationMeta(
    'memberId',
  );
  @override
  late final GeneratedColumn<String> memberId = GeneratedColumn<String>(
    'member_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _routedMeta = const VerificationMeta('routed');
  @override
  late final GeneratedColumn<bool> routed = GeneratedColumn<bool>(
    'routed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("routed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deliveredMeta = const VerificationMeta(
    'delivered',
  );
  @override
  late final GeneratedColumn<bool> delivered = GeneratedColumn<bool>(
    'delivered',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("delivered" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    conversationId,
    messageId,
    memberId,
    routed,
    delivered,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageReceiptRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('member_id')) {
      context.handle(
        _memberIdMeta,
        memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta),
      );
    } else if (isInserting) {
      context.missing(_memberIdMeta);
    }
    if (data.containsKey('routed')) {
      context.handle(
        _routedMeta,
        routed.isAcceptableOrUnknown(data['routed']!, _routedMeta),
      );
    }
    if (data.containsKey('delivered')) {
      context.handle(
        _deliveredMeta,
        delivered.isAcceptableOrUnknown(data['delivered']!, _deliveredMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conversationId, messageId, memberId};
  @override
  MessageReceiptRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageReceiptRow(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      memberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_id'],
      )!,
      routed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}routed'],
      )!,
      delivered: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}delivered'],
      )!,
    );
  }

  @override
  $MessageReceiptsTable createAlias(String alias) {
    return $MessageReceiptsTable(attachedDatabase, alias);
  }
}

class MessageReceiptRow extends DataClass
    implements Insertable<MessageReceiptRow> {
  final String conversationId;
  final String messageId;
  final String memberId;
  final bool routed;
  final bool delivered;
  const MessageReceiptRow({
    required this.conversationId,
    required this.messageId,
    required this.memberId,
    required this.routed,
    required this.delivered,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<String>(conversationId);
    map['message_id'] = Variable<String>(messageId);
    map['member_id'] = Variable<String>(memberId);
    map['routed'] = Variable<bool>(routed);
    map['delivered'] = Variable<bool>(delivered);
    return map;
  }

  MessageReceiptsCompanion toCompanion(bool nullToAbsent) {
    return MessageReceiptsCompanion(
      conversationId: Value(conversationId),
      messageId: Value(messageId),
      memberId: Value(memberId),
      routed: Value(routed),
      delivered: Value(delivered),
    );
  }

  factory MessageReceiptRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageReceiptRow(
      conversationId: serializer.fromJson<String>(json['conversationId']),
      messageId: serializer.fromJson<String>(json['messageId']),
      memberId: serializer.fromJson<String>(json['memberId']),
      routed: serializer.fromJson<bool>(json['routed']),
      delivered: serializer.fromJson<bool>(json['delivered']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<String>(conversationId),
      'messageId': serializer.toJson<String>(messageId),
      'memberId': serializer.toJson<String>(memberId),
      'routed': serializer.toJson<bool>(routed),
      'delivered': serializer.toJson<bool>(delivered),
    };
  }

  MessageReceiptRow copyWith({
    String? conversationId,
    String? messageId,
    String? memberId,
    bool? routed,
    bool? delivered,
  }) => MessageReceiptRow(
    conversationId: conversationId ?? this.conversationId,
    messageId: messageId ?? this.messageId,
    memberId: memberId ?? this.memberId,
    routed: routed ?? this.routed,
    delivered: delivered ?? this.delivered,
  );
  MessageReceiptRow copyWithCompanion(MessageReceiptsCompanion data) {
    return MessageReceiptRow(
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      routed: data.routed.present ? data.routed.value : this.routed,
      delivered: data.delivered.present ? data.delivered.value : this.delivered,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageReceiptRow(')
          ..write('conversationId: $conversationId, ')
          ..write('messageId: $messageId, ')
          ..write('memberId: $memberId, ')
          ..write('routed: $routed, ')
          ..write('delivered: $delivered')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(conversationId, messageId, memberId, routed, delivered);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageReceiptRow &&
          other.conversationId == this.conversationId &&
          other.messageId == this.messageId &&
          other.memberId == this.memberId &&
          other.routed == this.routed &&
          other.delivered == this.delivered);
}

class MessageReceiptsCompanion extends UpdateCompanion<MessageReceiptRow> {
  final Value<String> conversationId;
  final Value<String> messageId;
  final Value<String> memberId;
  final Value<bool> routed;
  final Value<bool> delivered;
  final Value<int> rowid;
  const MessageReceiptsCompanion({
    this.conversationId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.memberId = const Value.absent(),
    this.routed = const Value.absent(),
    this.delivered = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageReceiptsCompanion.insert({
    required String conversationId,
    required String messageId,
    required String memberId,
    this.routed = const Value.absent(),
    this.delivered = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : conversationId = Value(conversationId),
       messageId = Value(messageId),
       memberId = Value(memberId);
  static Insertable<MessageReceiptRow> custom({
    Expression<String>? conversationId,
    Expression<String>? messageId,
    Expression<String>? memberId,
    Expression<bool>? routed,
    Expression<bool>? delivered,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (messageId != null) 'message_id': messageId,
      if (memberId != null) 'member_id': memberId,
      if (routed != null) 'routed': routed,
      if (delivered != null) 'delivered': delivered,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageReceiptsCompanion copyWith({
    Value<String>? conversationId,
    Value<String>? messageId,
    Value<String>? memberId,
    Value<bool>? routed,
    Value<bool>? delivered,
    Value<int>? rowid,
  }) {
    return MessageReceiptsCompanion(
      conversationId: conversationId ?? this.conversationId,
      messageId: messageId ?? this.messageId,
      memberId: memberId ?? this.memberId,
      routed: routed ?? this.routed,
      delivered: delivered ?? this.delivered,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (memberId.present) {
      map['member_id'] = Variable<String>(memberId.value);
    }
    if (routed.present) {
      map['routed'] = Variable<bool>(routed.value);
    }
    if (delivered.present) {
      map['delivered'] = Variable<bool>(delivered.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageReceiptsCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('messageId: $messageId, ')
          ..write('memberId: $memberId, ')
          ..write('routed: $routed, ')
          ..write('delivered: $delivered, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UsersTable users = $UsersTable(this);
  late final $ChannelsTable channels = $ChannelsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $PeersTable peers = $PeersTable(this);
  late final $OutboundHandlesTable outboundHandles = $OutboundHandlesTable(
    this,
  );
  late final $SessionTagsTable sessionTags = $SessionTagsTable(this);
  late final $NodeScoresTable nodeScores = $NodeScoresTable(this);
  late final $GroupChannelsTable groupChannels = $GroupChannelsTable(this);
  late final $GroupMembersTable groupMembers = $GroupMembersTable(this);
  late final $GroupPendingItemsTable groupPendingItems =
      $GroupPendingItemsTable(this);
  late final $GroupInvitesTable groupInvites = $GroupInvitesTable(this);
  late final $MessageReceiptsTable messageReceipts = $MessageReceiptsTable(
    this,
  );
  late final Index idxMessagesConvMessageId = Index(
    'idx_messages_conv_message_id',
    'CREATE UNIQUE INDEX idx_messages_conv_message_id ON messages (conversation_id, message_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    users,
    channels,
    messages,
    peers,
    outboundHandles,
    sessionTags,
    nodeScores,
    groupChannels,
    groupMembers,
    groupPendingItems,
    groupInvites,
    messageReceipts,
    idxMessagesConvMessageId,
  ];
}

typedef $$UsersTableCreateCompanionBuilder =
    UsersCompanion Function({
      required String uuid,
      required String username,
      Value<String?> avatarUrl,
      Value<String?> publicKey,
      Value<int> rowid,
    });
typedef $$UsersTableUpdateCompanionBuilder =
    UsersCompanion Function({
      Value<String> uuid,
      Value<String> username,
      Value<String?> avatarUrl,
      Value<String?> publicKey,
      Value<int> rowid,
    });

class $$UsersTableFilterComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UsersTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsersTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);
}

class $$UsersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsersTable,
          User,
          $$UsersTableFilterComposer,
          $$UsersTableOrderingComposer,
          $$UsersTableAnnotationComposer,
          $$UsersTableCreateCompanionBuilder,
          $$UsersTableUpdateCompanionBuilder,
          (User, BaseReferences<_$AppDatabase, $UsersTable, User>),
          User,
          PrefetchHooks Function()
        > {
  $$UsersTableTableManager(_$AppDatabase db, $UsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> publicKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion(
                uuid: uuid,
                username: username,
                avatarUrl: avatarUrl,
                publicKey: publicKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String uuid,
                required String username,
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> publicKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion.insert(
                uuid: uuid,
                username: username,
                avatarUrl: avatarUrl,
                publicKey: publicKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UsersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsersTable,
      User,
      $$UsersTableFilterComposer,
      $$UsersTableOrderingComposer,
      $$UsersTableAnnotationComposer,
      $$UsersTableCreateCompanionBuilder,
      $$UsersTableUpdateCompanionBuilder,
      (User, BaseReferences<_$AppDatabase, $UsersTable, User>),
      User,
      PrefetchHooks Function()
    >;
typedef $$ChannelsTableCreateCompanionBuilder =
    ChannelsCompanion Function({
      required String uuid,
      required String label,
      required String encryptionKey,
      Value<String?> authPrivateKey,
      required String authPublicKey,
      Value<String?> peerOhEndpoint,
      Value<String?> peerOhId,
      Value<String?> peerOhPublicKey,
      Value<String?> peerOhSet,
      Value<DateTime?> lastSeen,
      Value<String?> ratchetState,
      Value<String?> pendingRgb,
      Value<int> rowid,
    });
typedef $$ChannelsTableUpdateCompanionBuilder =
    ChannelsCompanion Function({
      Value<String> uuid,
      Value<String> label,
      Value<String> encryptionKey,
      Value<String?> authPrivateKey,
      Value<String> authPublicKey,
      Value<String?> peerOhEndpoint,
      Value<String?> peerOhId,
      Value<String?> peerOhPublicKey,
      Value<String?> peerOhSet,
      Value<DateTime?> lastSeen,
      Value<String?> ratchetState,
      Value<String?> pendingRgb,
      Value<int> rowid,
    });

final class $$ChannelsTableReferences
    extends BaseReferences<_$AppDatabase, $ChannelsTable, Channel> {
  $$ChannelsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MessagesTable, List<Message>> _messagesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.messages,
    aliasName: $_aliasNameGenerator(
      db.channels.uuid,
      db.messages.conversationId,
    ),
  );

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager($_db, $_db.messages).filter(
      (f) => f.conversationId.uuid.sqlEquals($_itemColumn<String>('uuid')!),
    );

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SessionTagsTable, List<SessionTag>>
  _sessionTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.sessionTags,
    aliasName: $_aliasNameGenerator(db.channels.uuid, db.sessionTags.channelId),
  );

  $$SessionTagsTableProcessedTableManager get sessionTagsRefs {
    final manager = $$SessionTagsTableTableManager(
      $_db,
      $_db.sessionTags,
    ).filter((f) => f.channelId.uuid.sqlEquals($_itemColumn<String>('uuid')!));

    final cache = $_typedResult.readTableOrNull(_sessionTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ChannelsTableFilterComposer
    extends Composer<_$AppDatabase, $ChannelsTable> {
  $$ChannelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptionKey => $composableBuilder(
    column: $table.encryptionKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authPrivateKey => $composableBuilder(
    column: $table.authPrivateKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authPublicKey => $composableBuilder(
    column: $table.authPublicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerOhEndpoint => $composableBuilder(
    column: $table.peerOhEndpoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerOhId => $composableBuilder(
    column: $table.peerOhId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerOhPublicKey => $composableBuilder(
    column: $table.peerOhPublicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerOhSet => $composableBuilder(
    column: $table.peerOhSet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ratchetState => $composableBuilder(
    column: $table.ratchetState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pendingRgb => $composableBuilder(
    column: $table.pendingRgb,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> messagesRefs(
    Expression<bool> Function($$MessagesTableFilterComposer f) f,
  ) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.uuid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> sessionTagsRefs(
    Expression<bool> Function($$SessionTagsTableFilterComposer f) f,
  ) {
    final $$SessionTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.uuid,
      referencedTable: $db.sessionTags,
      getReferencedColumn: (t) => t.channelId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionTagsTableFilterComposer(
            $db: $db,
            $table: $db.sessionTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChannelsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChannelsTable> {
  $$ChannelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptionKey => $composableBuilder(
    column: $table.encryptionKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authPrivateKey => $composableBuilder(
    column: $table.authPrivateKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authPublicKey => $composableBuilder(
    column: $table.authPublicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerOhEndpoint => $composableBuilder(
    column: $table.peerOhEndpoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerOhId => $composableBuilder(
    column: $table.peerOhId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerOhPublicKey => $composableBuilder(
    column: $table.peerOhPublicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerOhSet => $composableBuilder(
    column: $table.peerOhSet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ratchetState => $composableBuilder(
    column: $table.ratchetState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingRgb => $composableBuilder(
    column: $table.pendingRgb,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChannelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChannelsTable> {
  $$ChannelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get encryptionKey => $composableBuilder(
    column: $table.encryptionKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authPrivateKey => $composableBuilder(
    column: $table.authPrivateKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authPublicKey => $composableBuilder(
    column: $table.authPublicKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerOhEndpoint => $composableBuilder(
    column: $table.peerOhEndpoint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerOhId =>
      $composableBuilder(column: $table.peerOhId, builder: (column) => column);

  GeneratedColumn<String> get peerOhPublicKey => $composableBuilder(
    column: $table.peerOhPublicKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get peerOhSet =>
      $composableBuilder(column: $table.peerOhSet, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  GeneratedColumn<String> get ratchetState => $composableBuilder(
    column: $table.ratchetState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pendingRgb => $composableBuilder(
    column: $table.pendingRgb,
    builder: (column) => column,
  );

  Expression<T> messagesRefs<T extends Object>(
    Expression<T> Function($$MessagesTableAnnotationComposer a) f,
  ) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.uuid,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> sessionTagsRefs<T extends Object>(
    Expression<T> Function($$SessionTagsTableAnnotationComposer a) f,
  ) {
    final $$SessionTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.uuid,
      referencedTable: $db.sessionTags,
      getReferencedColumn: (t) => t.channelId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessionTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ChannelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChannelsTable,
          Channel,
          $$ChannelsTableFilterComposer,
          $$ChannelsTableOrderingComposer,
          $$ChannelsTableAnnotationComposer,
          $$ChannelsTableCreateCompanionBuilder,
          $$ChannelsTableUpdateCompanionBuilder,
          (Channel, $$ChannelsTableReferences),
          Channel,
          PrefetchHooks Function({bool messagesRefs, bool sessionTagsRefs})
        > {
  $$ChannelsTableTableManager(_$AppDatabase db, $ChannelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChannelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChannelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChannelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> uuid = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> encryptionKey = const Value.absent(),
                Value<String?> authPrivateKey = const Value.absent(),
                Value<String> authPublicKey = const Value.absent(),
                Value<String?> peerOhEndpoint = const Value.absent(),
                Value<String?> peerOhId = const Value.absent(),
                Value<String?> peerOhPublicKey = const Value.absent(),
                Value<String?> peerOhSet = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<String?> ratchetState = const Value.absent(),
                Value<String?> pendingRgb = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelsCompanion(
                uuid: uuid,
                label: label,
                encryptionKey: encryptionKey,
                authPrivateKey: authPrivateKey,
                authPublicKey: authPublicKey,
                peerOhEndpoint: peerOhEndpoint,
                peerOhId: peerOhId,
                peerOhPublicKey: peerOhPublicKey,
                peerOhSet: peerOhSet,
                lastSeen: lastSeen,
                ratchetState: ratchetState,
                pendingRgb: pendingRgb,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String uuid,
                required String label,
                required String encryptionKey,
                Value<String?> authPrivateKey = const Value.absent(),
                required String authPublicKey,
                Value<String?> peerOhEndpoint = const Value.absent(),
                Value<String?> peerOhId = const Value.absent(),
                Value<String?> peerOhPublicKey = const Value.absent(),
                Value<String?> peerOhSet = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<String?> ratchetState = const Value.absent(),
                Value<String?> pendingRgb = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelsCompanion.insert(
                uuid: uuid,
                label: label,
                encryptionKey: encryptionKey,
                authPrivateKey: authPrivateKey,
                authPublicKey: authPublicKey,
                peerOhEndpoint: peerOhEndpoint,
                peerOhId: peerOhId,
                peerOhPublicKey: peerOhPublicKey,
                peerOhSet: peerOhSet,
                lastSeen: lastSeen,
                ratchetState: ratchetState,
                pendingRgb: pendingRgb,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ChannelsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({messagesRefs = false, sessionTagsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (messagesRefs) db.messages,
                    if (sessionTagsRefs) db.sessionTags,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (messagesRefs)
                        await $_getPrefetchedData<
                          Channel,
                          $ChannelsTable,
                          Message
                        >(
                          currentTable: table,
                          referencedTable: $$ChannelsTableReferences
                              ._messagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ChannelsTableReferences(
                                db,
                                table,
                                p0,
                              ).messagesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.conversationId == item.uuid,
                              ),
                          typedResults: items,
                        ),
                      if (sessionTagsRefs)
                        await $_getPrefetchedData<
                          Channel,
                          $ChannelsTable,
                          SessionTag
                        >(
                          currentTable: table,
                          referencedTable: $$ChannelsTableReferences
                              ._sessionTagsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ChannelsTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.channelId == item.uuid,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ChannelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChannelsTable,
      Channel,
      $$ChannelsTableFilterComposer,
      $$ChannelsTableOrderingComposer,
      $$ChannelsTableAnnotationComposer,
      $$ChannelsTableCreateCompanionBuilder,
      $$ChannelsTableUpdateCompanionBuilder,
      (Channel, $$ChannelsTableReferences),
      Channel,
      PrefetchHooks Function({bool messagesRefs, bool sessionTagsRefs})
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> id,
      required String conversationId,
      required String senderId,
      required String content,
      required DateTime timestamp,
      required int status,
      required int type,
      Value<String?> messageId,
      Value<int> retryCount,
      Value<DateTime?> lastRetryAt,
      Value<String?> senderMemberId,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> id,
      Value<String> conversationId,
      Value<String> senderId,
      Value<String> content,
      Value<DateTime> timestamp,
      Value<int> status,
      Value<int> type,
      Value<String?> messageId,
      Value<int> retryCount,
      Value<DateTime?> lastRetryAt,
      Value<String?> senderMemberId,
    });

final class $$MessagesTableReferences
    extends BaseReferences<_$AppDatabase, $MessagesTable, Message> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ChannelsTable _conversationIdTable(_$AppDatabase db) =>
      db.channels.createAlias(
        $_aliasNameGenerator(db.messages.conversationId, db.channels.uuid),
      );

  $$ChannelsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<String>('conversation_id')!;

    final manager = $$ChannelsTableTableManager(
      $_db,
      $_db.channels,
    ).filter((f) => f.uuid.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastRetryAt => $composableBuilder(
    column: $table.lastRetryAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderMemberId => $composableBuilder(
    column: $table.senderMemberId,
    builder: (column) => ColumnFilters(column),
  );

  $$ChannelsTableFilterComposer get conversationId {
    final $$ChannelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.uuid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableFilterComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastRetryAt => $composableBuilder(
    column: $table.lastRetryAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderMemberId => $composableBuilder(
    column: $table.senderMemberId,
    builder: (column) => ColumnOrderings(column),
  );

  $$ChannelsTableOrderingComposer get conversationId {
    final $$ChannelsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.uuid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableOrderingComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastRetryAt => $composableBuilder(
    column: $table.lastRetryAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get senderMemberId => $composableBuilder(
    column: $table.senderMemberId,
    builder: (column) => column,
  );

  $$ChannelsTableAnnotationComposer get conversationId {
    final $$ChannelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.uuid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableAnnotationComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, $$MessagesTableReferences),
          Message,
          PrefetchHooks Function({bool conversationId})
        > {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> senderId = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<String?> messageId = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime?> lastRetryAt = const Value.absent(),
                Value<String?> senderMemberId = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                content: content,
                timestamp: timestamp,
                status: status,
                type: type,
                messageId: messageId,
                retryCount: retryCount,
                lastRetryAt: lastRetryAt,
                senderMemberId: senderMemberId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String conversationId,
                required String senderId,
                required String content,
                required DateTime timestamp,
                required int status,
                required int type,
                Value<String?> messageId = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime?> lastRetryAt = const Value.absent(),
                Value<String?> senderMemberId = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                content: content,
                timestamp: timestamp,
                status: status,
                type: type,
                messageId: messageId,
                retryCount: retryCount,
                lastRetryAt: lastRetryAt,
                senderMemberId: senderMemberId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conversationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (conversationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.conversationId,
                                referencedTable: $$MessagesTableReferences
                                    ._conversationIdTable(db),
                                referencedColumn: $$MessagesTableReferences
                                    ._conversationIdTable(db)
                                    .uuid,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, $$MessagesTableReferences),
      Message,
      PrefetchHooks Function({bool conversationId})
    >;
typedef $$PeersTableCreateCompanionBuilder =
    PeersCompanion Function({
      required String address,
      Value<String?> nodeId,
      Value<String?> encryptionPublicKey,
      Value<int> averageLatencyMs,
      Value<int> successCount,
      Value<int> failureCount,
      Value<DateTime?> lastSeen,
      Value<int> rowid,
    });
typedef $$PeersTableUpdateCompanionBuilder =
    PeersCompanion Function({
      Value<String> address,
      Value<String?> nodeId,
      Value<String?> encryptionPublicKey,
      Value<int> averageLatencyMs,
      Value<int> successCount,
      Value<int> failureCount,
      Value<DateTime?> lastSeen,
      Value<int> rowid,
    });

class $$PeersTableFilterComposer extends Composer<_$AppDatabase, $PeersTable> {
  $$PeersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nodeId => $composableBuilder(
    column: $table.nodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptionPublicKey => $composableBuilder(
    column: $table.encryptionPublicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get averageLatencyMs => $composableBuilder(
    column: $table.averageLatencyMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failureCount => $composableBuilder(
    column: $table.failureCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PeersTableOrderingComposer
    extends Composer<_$AppDatabase, $PeersTable> {
  $$PeersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nodeId => $composableBuilder(
    column: $table.nodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptionPublicKey => $composableBuilder(
    column: $table.encryptionPublicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get averageLatencyMs => $composableBuilder(
    column: $table.averageLatencyMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failureCount => $composableBuilder(
    column: $table.failureCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeersTableAnnotationComposer
    extends Composer<_$AppDatabase, $PeersTable> {
  $$PeersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get nodeId =>
      $composableBuilder(column: $table.nodeId, builder: (column) => column);

  GeneratedColumn<String> get encryptionPublicKey => $composableBuilder(
    column: $table.encryptionPublicKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get averageLatencyMs => $composableBuilder(
    column: $table.averageLatencyMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get failureCount => $composableBuilder(
    column: $table.failureCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);
}

class $$PeersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PeersTable,
          Peer,
          $$PeersTableFilterComposer,
          $$PeersTableOrderingComposer,
          $$PeersTableAnnotationComposer,
          $$PeersTableCreateCompanionBuilder,
          $$PeersTableUpdateCompanionBuilder,
          (Peer, BaseReferences<_$AppDatabase, $PeersTable, Peer>),
          Peer,
          PrefetchHooks Function()
        > {
  $$PeersTableTableManager(_$AppDatabase db, $PeersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> address = const Value.absent(),
                Value<String?> nodeId = const Value.absent(),
                Value<String?> encryptionPublicKey = const Value.absent(),
                Value<int> averageLatencyMs = const Value.absent(),
                Value<int> successCount = const Value.absent(),
                Value<int> failureCount = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeersCompanion(
                address: address,
                nodeId: nodeId,
                encryptionPublicKey: encryptionPublicKey,
                averageLatencyMs: averageLatencyMs,
                successCount: successCount,
                failureCount: failureCount,
                lastSeen: lastSeen,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String address,
                Value<String?> nodeId = const Value.absent(),
                Value<String?> encryptionPublicKey = const Value.absent(),
                Value<int> averageLatencyMs = const Value.absent(),
                Value<int> successCount = const Value.absent(),
                Value<int> failureCount = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeersCompanion.insert(
                address: address,
                nodeId: nodeId,
                encryptionPublicKey: encryptionPublicKey,
                averageLatencyMs: averageLatencyMs,
                successCount: successCount,
                failureCount: failureCount,
                lastSeen: lastSeen,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PeersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PeersTable,
      Peer,
      $$PeersTableFilterComposer,
      $$PeersTableOrderingComposer,
      $$PeersTableAnnotationComposer,
      $$PeersTableCreateCompanionBuilder,
      $$PeersTableUpdateCompanionBuilder,
      (Peer, BaseReferences<_$AppDatabase, $PeersTable, Peer>),
      Peer,
      PrefetchHooks Function()
    >;
typedef $$OutboundHandlesTableCreateCompanionBuilder =
    OutboundHandlesCompanion Function({
      Value<int> id,
      required String ohId,
      required Uint8List keypairBytes,
      required String serverEndpoint,
      required DateTime expiresAt,
      Value<String?> channelId,
      Value<int> lastCursor,
      Value<DateTime?> failedOverAt,
    });
typedef $$OutboundHandlesTableUpdateCompanionBuilder =
    OutboundHandlesCompanion Function({
      Value<int> id,
      Value<String> ohId,
      Value<Uint8List> keypairBytes,
      Value<String> serverEndpoint,
      Value<DateTime> expiresAt,
      Value<String?> channelId,
      Value<int> lastCursor,
      Value<DateTime?> failedOverAt,
    });

class $$OutboundHandlesTableFilterComposer
    extends Composer<_$AppDatabase, $OutboundHandlesTable> {
  $$OutboundHandlesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ohId => $composableBuilder(
    column: $table.ohId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get keypairBytes => $composableBuilder(
    column: $table.keypairBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverEndpoint => $composableBuilder(
    column: $table.serverEndpoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channelId => $composableBuilder(
    column: $table.channelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastCursor => $composableBuilder(
    column: $table.lastCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get failedOverAt => $composableBuilder(
    column: $table.failedOverAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboundHandlesTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboundHandlesTable> {
  $$OutboundHandlesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ohId => $composableBuilder(
    column: $table.ohId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get keypairBytes => $composableBuilder(
    column: $table.keypairBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverEndpoint => $composableBuilder(
    column: $table.serverEndpoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channelId => $composableBuilder(
    column: $table.channelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastCursor => $composableBuilder(
    column: $table.lastCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get failedOverAt => $composableBuilder(
    column: $table.failedOverAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboundHandlesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboundHandlesTable> {
  $$OutboundHandlesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ohId =>
      $composableBuilder(column: $table.ohId, builder: (column) => column);

  GeneratedColumn<Uint8List> get keypairBytes => $composableBuilder(
    column: $table.keypairBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverEndpoint => $composableBuilder(
    column: $table.serverEndpoint,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<String> get channelId =>
      $composableBuilder(column: $table.channelId, builder: (column) => column);

  GeneratedColumn<int> get lastCursor => $composableBuilder(
    column: $table.lastCursor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get failedOverAt => $composableBuilder(
    column: $table.failedOverAt,
    builder: (column) => column,
  );
}

class $$OutboundHandlesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboundHandlesTable,
          OutboundHandle,
          $$OutboundHandlesTableFilterComposer,
          $$OutboundHandlesTableOrderingComposer,
          $$OutboundHandlesTableAnnotationComposer,
          $$OutboundHandlesTableCreateCompanionBuilder,
          $$OutboundHandlesTableUpdateCompanionBuilder,
          (
            OutboundHandle,
            BaseReferences<
              _$AppDatabase,
              $OutboundHandlesTable,
              OutboundHandle
            >,
          ),
          OutboundHandle,
          PrefetchHooks Function()
        > {
  $$OutboundHandlesTableTableManager(
    _$AppDatabase db,
    $OutboundHandlesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboundHandlesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboundHandlesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboundHandlesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> ohId = const Value.absent(),
                Value<Uint8List> keypairBytes = const Value.absent(),
                Value<String> serverEndpoint = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
                Value<String?> channelId = const Value.absent(),
                Value<int> lastCursor = const Value.absent(),
                Value<DateTime?> failedOverAt = const Value.absent(),
              }) => OutboundHandlesCompanion(
                id: id,
                ohId: ohId,
                keypairBytes: keypairBytes,
                serverEndpoint: serverEndpoint,
                expiresAt: expiresAt,
                channelId: channelId,
                lastCursor: lastCursor,
                failedOverAt: failedOverAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String ohId,
                required Uint8List keypairBytes,
                required String serverEndpoint,
                required DateTime expiresAt,
                Value<String?> channelId = const Value.absent(),
                Value<int> lastCursor = const Value.absent(),
                Value<DateTime?> failedOverAt = const Value.absent(),
              }) => OutboundHandlesCompanion.insert(
                id: id,
                ohId: ohId,
                keypairBytes: keypairBytes,
                serverEndpoint: serverEndpoint,
                expiresAt: expiresAt,
                channelId: channelId,
                lastCursor: lastCursor,
                failedOverAt: failedOverAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboundHandlesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboundHandlesTable,
      OutboundHandle,
      $$OutboundHandlesTableFilterComposer,
      $$OutboundHandlesTableOrderingComposer,
      $$OutboundHandlesTableAnnotationComposer,
      $$OutboundHandlesTableCreateCompanionBuilder,
      $$OutboundHandlesTableUpdateCompanionBuilder,
      (
        OutboundHandle,
        BaseReferences<_$AppDatabase, $OutboundHandlesTable, OutboundHandle>,
      ),
      OutboundHandle,
      PrefetchHooks Function()
    >;
typedef $$SessionTagsTableCreateCompanionBuilder =
    SessionTagsCompanion Function({
      required String tag,
      required String channelId,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$SessionTagsTableUpdateCompanionBuilder =
    SessionTagsCompanion Function({
      Value<String> tag,
      Value<String> channelId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$SessionTagsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionTagsTable, SessionTag> {
  $$SessionTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ChannelsTable _channelIdTable(_$AppDatabase db) =>
      db.channels.createAlias(
        $_aliasNameGenerator(db.sessionTags.channelId, db.channels.uuid),
      );

  $$ChannelsTableProcessedTableManager get channelId {
    final $_column = $_itemColumn<String>('channel_id')!;

    final manager = $$ChannelsTableTableManager(
      $_db,
      $_db.channels,
    ).filter((f) => f.uuid.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_channelIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SessionTagsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionTagsTable> {
  $$SessionTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ChannelsTableFilterComposer get channelId {
    final $$ChannelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.channelId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.uuid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableFilterComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionTagsTable> {
  $$SessionTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ChannelsTableOrderingComposer get channelId {
    final $$ChannelsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.channelId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.uuid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableOrderingComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionTagsTable> {
  $$SessionTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ChannelsTableAnnotationComposer get channelId {
    final $$ChannelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.channelId,
      referencedTable: $db.channels,
      getReferencedColumn: (t) => t.uuid,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ChannelsTableAnnotationComposer(
            $db: $db,
            $table: $db.channels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionTagsTable,
          SessionTag,
          $$SessionTagsTableFilterComposer,
          $$SessionTagsTableOrderingComposer,
          $$SessionTagsTableAnnotationComposer,
          $$SessionTagsTableCreateCompanionBuilder,
          $$SessionTagsTableUpdateCompanionBuilder,
          (SessionTag, $$SessionTagsTableReferences),
          SessionTag,
          PrefetchHooks Function({bool channelId})
        > {
  $$SessionTagsTableTableManager(_$AppDatabase db, $SessionTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tag = const Value.absent(),
                Value<String> channelId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionTagsCompanion(
                tag: tag,
                channelId: channelId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tag,
                required String channelId,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SessionTagsCompanion.insert(
                tag: tag,
                channelId: channelId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SessionTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({channelId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (channelId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.channelId,
                                referencedTable: $$SessionTagsTableReferences
                                    ._channelIdTable(db),
                                referencedColumn: $$SessionTagsTableReferences
                                    ._channelIdTable(db)
                                    .uuid,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SessionTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionTagsTable,
      SessionTag,
      $$SessionTagsTableFilterComposer,
      $$SessionTagsTableOrderingComposer,
      $$SessionTagsTableAnnotationComposer,
      $$SessionTagsTableCreateCompanionBuilder,
      $$SessionTagsTableUpdateCompanionBuilder,
      (SessionTag, $$SessionTagsTableReferences),
      SessionTag,
      PrefetchHooks Function({bool channelId})
    >;
typedef $$NodeScoresTableCreateCompanionBuilder =
    NodeScoresCompanion Function({
      required String nodeId,
      Value<int> successCount,
      Value<int> failureCount,
      Value<int> avgLatencyMs,
      Value<DateTime?> lastUpdated,
      Value<int> rowid,
    });
typedef $$NodeScoresTableUpdateCompanionBuilder =
    NodeScoresCompanion Function({
      Value<String> nodeId,
      Value<int> successCount,
      Value<int> failureCount,
      Value<int> avgLatencyMs,
      Value<DateTime?> lastUpdated,
      Value<int> rowid,
    });

class $$NodeScoresTableFilterComposer
    extends Composer<_$AppDatabase, $NodeScoresTable> {
  $$NodeScoresTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get nodeId => $composableBuilder(
    column: $table.nodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failureCount => $composableBuilder(
    column: $table.failureCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get avgLatencyMs => $composableBuilder(
    column: $table.avgLatencyMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NodeScoresTableOrderingComposer
    extends Composer<_$AppDatabase, $NodeScoresTable> {
  $$NodeScoresTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get nodeId => $composableBuilder(
    column: $table.nodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failureCount => $composableBuilder(
    column: $table.failureCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get avgLatencyMs => $composableBuilder(
    column: $table.avgLatencyMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NodeScoresTableAnnotationComposer
    extends Composer<_$AppDatabase, $NodeScoresTable> {
  $$NodeScoresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get nodeId =>
      $composableBuilder(column: $table.nodeId, builder: (column) => column);

  GeneratedColumn<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get failureCount => $composableBuilder(
    column: $table.failureCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get avgLatencyMs => $composableBuilder(
    column: $table.avgLatencyMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => column,
  );
}

class $$NodeScoresTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NodeScoresTable,
          NodeScoreRow,
          $$NodeScoresTableFilterComposer,
          $$NodeScoresTableOrderingComposer,
          $$NodeScoresTableAnnotationComposer,
          $$NodeScoresTableCreateCompanionBuilder,
          $$NodeScoresTableUpdateCompanionBuilder,
          (
            NodeScoreRow,
            BaseReferences<_$AppDatabase, $NodeScoresTable, NodeScoreRow>,
          ),
          NodeScoreRow,
          PrefetchHooks Function()
        > {
  $$NodeScoresTableTableManager(_$AppDatabase db, $NodeScoresTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NodeScoresTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NodeScoresTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NodeScoresTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> nodeId = const Value.absent(),
                Value<int> successCount = const Value.absent(),
                Value<int> failureCount = const Value.absent(),
                Value<int> avgLatencyMs = const Value.absent(),
                Value<DateTime?> lastUpdated = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NodeScoresCompanion(
                nodeId: nodeId,
                successCount: successCount,
                failureCount: failureCount,
                avgLatencyMs: avgLatencyMs,
                lastUpdated: lastUpdated,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String nodeId,
                Value<int> successCount = const Value.absent(),
                Value<int> failureCount = const Value.absent(),
                Value<int> avgLatencyMs = const Value.absent(),
                Value<DateTime?> lastUpdated = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NodeScoresCompanion.insert(
                nodeId: nodeId,
                successCount: successCount,
                failureCount: failureCount,
                avgLatencyMs: avgLatencyMs,
                lastUpdated: lastUpdated,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NodeScoresTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NodeScoresTable,
      NodeScoreRow,
      $$NodeScoresTableFilterComposer,
      $$NodeScoresTableOrderingComposer,
      $$NodeScoresTableAnnotationComposer,
      $$NodeScoresTableCreateCompanionBuilder,
      $$NodeScoresTableUpdateCompanionBuilder,
      (
        NodeScoreRow,
        BaseReferences<_$AppDatabase, $NodeScoresTable, NodeScoreRow>,
      ),
      NodeScoreRow,
      PrefetchHooks Function()
    >;
typedef $$GroupChannelsTableCreateCompanionBuilder =
    GroupChannelsCompanion Function({
      required String groupId,
      required String label,
      Value<bool> isAdmin,
      required String myMemberId,
      required String mySignSeed,
      required String myX25519Priv,
      Value<int> keyEpoch,
      Value<String?> cryptoState,
      Value<String?> pendingRotations,
      Value<DateTime?> createdAt,
      Value<int> rowid,
    });
typedef $$GroupChannelsTableUpdateCompanionBuilder =
    GroupChannelsCompanion Function({
      Value<String> groupId,
      Value<String> label,
      Value<bool> isAdmin,
      Value<String> myMemberId,
      Value<String> mySignSeed,
      Value<String> myX25519Priv,
      Value<int> keyEpoch,
      Value<String?> cryptoState,
      Value<String?> pendingRotations,
      Value<DateTime?> createdAt,
      Value<int> rowid,
    });

final class $$GroupChannelsTableReferences
    extends
        BaseReferences<_$AppDatabase, $GroupChannelsTable, GroupChannelRow> {
  $$GroupChannelsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$GroupMembersTable, List<GroupMemberRow>>
  _groupMembersRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.groupMembers,
    aliasName: $_aliasNameGenerator(
      db.groupChannels.groupId,
      db.groupMembers.groupId,
    ),
  );

  $$GroupMembersTableProcessedTableManager get groupMembersRefs {
    final manager = $$GroupMembersTableTableManager($_db, $_db.groupMembers)
        .filter(
          (f) => f.groupId.groupId.sqlEquals($_itemColumn<String>('group_id')!),
        );

    final cache = $_typedResult.readTableOrNull(_groupMembersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$GroupPendingItemsTable, List<GroupPendingItemRow>>
  _groupPendingItemsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.groupPendingItems,
        aliasName: $_aliasNameGenerator(
          db.groupChannels.groupId,
          db.groupPendingItems.groupId,
        ),
      );

  $$GroupPendingItemsTableProcessedTableManager get groupPendingItemsRefs {
    final manager =
        $$GroupPendingItemsTableTableManager(
          $_db,
          $_db.groupPendingItems,
        ).filter(
          (f) => f.groupId.groupId.sqlEquals($_itemColumn<String>('group_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _groupPendingItemsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GroupChannelsTableFilterComposer
    extends Composer<_$AppDatabase, $GroupChannelsTable> {
  $$GroupChannelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAdmin => $composableBuilder(
    column: $table.isAdmin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get myMemberId => $composableBuilder(
    column: $table.myMemberId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mySignSeed => $composableBuilder(
    column: $table.mySignSeed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get myX25519Priv => $composableBuilder(
    column: $table.myX25519Priv,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get keyEpoch => $composableBuilder(
    column: $table.keyEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cryptoState => $composableBuilder(
    column: $table.cryptoState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pendingRotations => $composableBuilder(
    column: $table.pendingRotations,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> groupMembersRefs(
    Expression<bool> Function($$GroupMembersTableFilterComposer f) f,
  ) {
    final $$GroupMembersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groupMembers,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupMembersTableFilterComposer(
            $db: $db,
            $table: $db.groupMembers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> groupPendingItemsRefs(
    Expression<bool> Function($$GroupPendingItemsTableFilterComposer f) f,
  ) {
    final $$GroupPendingItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groupPendingItems,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupPendingItemsTableFilterComposer(
            $db: $db,
            $table: $db.groupPendingItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GroupChannelsTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupChannelsTable> {
  $$GroupChannelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAdmin => $composableBuilder(
    column: $table.isAdmin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get myMemberId => $composableBuilder(
    column: $table.myMemberId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mySignSeed => $composableBuilder(
    column: $table.mySignSeed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get myX25519Priv => $composableBuilder(
    column: $table.myX25519Priv,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get keyEpoch => $composableBuilder(
    column: $table.keyEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cryptoState => $composableBuilder(
    column: $table.cryptoState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingRotations => $composableBuilder(
    column: $table.pendingRotations,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupChannelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupChannelsTable> {
  $$GroupChannelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<bool> get isAdmin =>
      $composableBuilder(column: $table.isAdmin, builder: (column) => column);

  GeneratedColumn<String> get myMemberId => $composableBuilder(
    column: $table.myMemberId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mySignSeed => $composableBuilder(
    column: $table.mySignSeed,
    builder: (column) => column,
  );

  GeneratedColumn<String> get myX25519Priv => $composableBuilder(
    column: $table.myX25519Priv,
    builder: (column) => column,
  );

  GeneratedColumn<int> get keyEpoch =>
      $composableBuilder(column: $table.keyEpoch, builder: (column) => column);

  GeneratedColumn<String> get cryptoState => $composableBuilder(
    column: $table.cryptoState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pendingRotations => $composableBuilder(
    column: $table.pendingRotations,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> groupMembersRefs<T extends Object>(
    Expression<T> Function($$GroupMembersTableAnnotationComposer a) f,
  ) {
    final $$GroupMembersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groupMembers,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupMembersTableAnnotationComposer(
            $db: $db,
            $table: $db.groupMembers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> groupPendingItemsRefs<T extends Object>(
    Expression<T> Function($$GroupPendingItemsTableAnnotationComposer a) f,
  ) {
    final $$GroupPendingItemsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.groupId,
          referencedTable: $db.groupPendingItems,
          getReferencedColumn: (t) => t.groupId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$GroupPendingItemsTableAnnotationComposer(
                $db: $db,
                $table: $db.groupPendingItems,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$GroupChannelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupChannelsTable,
          GroupChannelRow,
          $$GroupChannelsTableFilterComposer,
          $$GroupChannelsTableOrderingComposer,
          $$GroupChannelsTableAnnotationComposer,
          $$GroupChannelsTableCreateCompanionBuilder,
          $$GroupChannelsTableUpdateCompanionBuilder,
          (GroupChannelRow, $$GroupChannelsTableReferences),
          GroupChannelRow,
          PrefetchHooks Function({
            bool groupMembersRefs,
            bool groupPendingItemsRefs,
          })
        > {
  $$GroupChannelsTableTableManager(_$AppDatabase db, $GroupChannelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupChannelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupChannelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupChannelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<bool> isAdmin = const Value.absent(),
                Value<String> myMemberId = const Value.absent(),
                Value<String> mySignSeed = const Value.absent(),
                Value<String> myX25519Priv = const Value.absent(),
                Value<int> keyEpoch = const Value.absent(),
                Value<String?> cryptoState = const Value.absent(),
                Value<String?> pendingRotations = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupChannelsCompanion(
                groupId: groupId,
                label: label,
                isAdmin: isAdmin,
                myMemberId: myMemberId,
                mySignSeed: mySignSeed,
                myX25519Priv: myX25519Priv,
                keyEpoch: keyEpoch,
                cryptoState: cryptoState,
                pendingRotations: pendingRotations,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String label,
                Value<bool> isAdmin = const Value.absent(),
                required String myMemberId,
                required String mySignSeed,
                required String myX25519Priv,
                Value<int> keyEpoch = const Value.absent(),
                Value<String?> cryptoState = const Value.absent(),
                Value<String?> pendingRotations = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupChannelsCompanion.insert(
                groupId: groupId,
                label: label,
                isAdmin: isAdmin,
                myMemberId: myMemberId,
                mySignSeed: mySignSeed,
                myX25519Priv: myX25519Priv,
                keyEpoch: keyEpoch,
                cryptoState: cryptoState,
                pendingRotations: pendingRotations,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GroupChannelsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({groupMembersRefs = false, groupPendingItemsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (groupMembersRefs) db.groupMembers,
                    if (groupPendingItemsRefs) db.groupPendingItems,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (groupMembersRefs)
                        await $_getPrefetchedData<
                          GroupChannelRow,
                          $GroupChannelsTable,
                          GroupMemberRow
                        >(
                          currentTable: table,
                          referencedTable: $$GroupChannelsTableReferences
                              ._groupMembersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$GroupChannelsTableReferences(
                                db,
                                table,
                                p0,
                              ).groupMembersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.groupId == item.groupId,
                              ),
                          typedResults: items,
                        ),
                      if (groupPendingItemsRefs)
                        await $_getPrefetchedData<
                          GroupChannelRow,
                          $GroupChannelsTable,
                          GroupPendingItemRow
                        >(
                          currentTable: table,
                          referencedTable: $$GroupChannelsTableReferences
                              ._groupPendingItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$GroupChannelsTableReferences(
                                db,
                                table,
                                p0,
                              ).groupPendingItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.groupId == item.groupId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$GroupChannelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupChannelsTable,
      GroupChannelRow,
      $$GroupChannelsTableFilterComposer,
      $$GroupChannelsTableOrderingComposer,
      $$GroupChannelsTableAnnotationComposer,
      $$GroupChannelsTableCreateCompanionBuilder,
      $$GroupChannelsTableUpdateCompanionBuilder,
      (GroupChannelRow, $$GroupChannelsTableReferences),
      GroupChannelRow,
      PrefetchHooks Function({
        bool groupMembersRefs,
        bool groupPendingItemsRefs,
      })
    >;
typedef $$GroupMembersTableCreateCompanionBuilder =
    GroupMembersCompanion Function({
      required String groupId,
      required String memberId,
      required String displayName,
      Value<String?> ohId,
      Value<String?> ohEndpoint,
      required String x25519Pub,
      required int role,
      Value<int> rowid,
    });
typedef $$GroupMembersTableUpdateCompanionBuilder =
    GroupMembersCompanion Function({
      Value<String> groupId,
      Value<String> memberId,
      Value<String> displayName,
      Value<String?> ohId,
      Value<String?> ohEndpoint,
      Value<String> x25519Pub,
      Value<int> role,
      Value<int> rowid,
    });

final class $$GroupMembersTableReferences
    extends BaseReferences<_$AppDatabase, $GroupMembersTable, GroupMemberRow> {
  $$GroupMembersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $GroupChannelsTable _groupIdTable(_$AppDatabase db) =>
      db.groupChannels.createAlias(
        $_aliasNameGenerator(db.groupMembers.groupId, db.groupChannels.groupId),
      );

  $$GroupChannelsTableProcessedTableManager get groupId {
    final $_column = $_itemColumn<String>('group_id')!;

    final manager = $$GroupChannelsTableTableManager(
      $_db,
      $_db.groupChannels,
    ).filter((f) => f.groupId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GroupMembersTableFilterComposer
    extends Composer<_$AppDatabase, $GroupMembersTable> {
  $$GroupMembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ohId => $composableBuilder(
    column: $table.ohId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ohEndpoint => $composableBuilder(
    column: $table.ohEndpoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get x25519Pub => $composableBuilder(
    column: $table.x25519Pub,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  $$GroupChannelsTableFilterComposer get groupId {
    final $$GroupChannelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groupChannels,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupChannelsTableFilterComposer(
            $db: $db,
            $table: $db.groupChannels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupMembersTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupMembersTable> {
  $$GroupMembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ohId => $composableBuilder(
    column: $table.ohId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ohEndpoint => $composableBuilder(
    column: $table.ohEndpoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get x25519Pub => $composableBuilder(
    column: $table.x25519Pub,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  $$GroupChannelsTableOrderingComposer get groupId {
    final $$GroupChannelsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groupChannels,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupChannelsTableOrderingComposer(
            $db: $db,
            $table: $db.groupChannels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupMembersTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupMembersTable> {
  $$GroupMembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get memberId =>
      $composableBuilder(column: $table.memberId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ohId =>
      $composableBuilder(column: $table.ohId, builder: (column) => column);

  GeneratedColumn<String> get ohEndpoint => $composableBuilder(
    column: $table.ohEndpoint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get x25519Pub =>
      $composableBuilder(column: $table.x25519Pub, builder: (column) => column);

  GeneratedColumn<int> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  $$GroupChannelsTableAnnotationComposer get groupId {
    final $$GroupChannelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groupChannels,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupChannelsTableAnnotationComposer(
            $db: $db,
            $table: $db.groupChannels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupMembersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupMembersTable,
          GroupMemberRow,
          $$GroupMembersTableFilterComposer,
          $$GroupMembersTableOrderingComposer,
          $$GroupMembersTableAnnotationComposer,
          $$GroupMembersTableCreateCompanionBuilder,
          $$GroupMembersTableUpdateCompanionBuilder,
          (GroupMemberRow, $$GroupMembersTableReferences),
          GroupMemberRow,
          PrefetchHooks Function({bool groupId})
        > {
  $$GroupMembersTableTableManager(_$AppDatabase db, $GroupMembersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupMembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupMembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupMembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> memberId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> ohId = const Value.absent(),
                Value<String?> ohEndpoint = const Value.absent(),
                Value<String> x25519Pub = const Value.absent(),
                Value<int> role = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupMembersCompanion(
                groupId: groupId,
                memberId: memberId,
                displayName: displayName,
                ohId: ohId,
                ohEndpoint: ohEndpoint,
                x25519Pub: x25519Pub,
                role: role,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String memberId,
                required String displayName,
                Value<String?> ohId = const Value.absent(),
                Value<String?> ohEndpoint = const Value.absent(),
                required String x25519Pub,
                required int role,
                Value<int> rowid = const Value.absent(),
              }) => GroupMembersCompanion.insert(
                groupId: groupId,
                memberId: memberId,
                displayName: displayName,
                ohId: ohId,
                ohEndpoint: ohEndpoint,
                x25519Pub: x25519Pub,
                role: role,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GroupMembersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({groupId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (groupId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.groupId,
                                referencedTable: $$GroupMembersTableReferences
                                    ._groupIdTable(db),
                                referencedColumn: $$GroupMembersTableReferences
                                    ._groupIdTable(db)
                                    .groupId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GroupMembersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupMembersTable,
      GroupMemberRow,
      $$GroupMembersTableFilterComposer,
      $$GroupMembersTableOrderingComposer,
      $$GroupMembersTableAnnotationComposer,
      $$GroupMembersTableCreateCompanionBuilder,
      $$GroupMembersTableUpdateCompanionBuilder,
      (GroupMemberRow, $$GroupMembersTableReferences),
      GroupMemberRow,
      PrefetchHooks Function({bool groupId})
    >;
typedef $$GroupPendingItemsTableCreateCompanionBuilder =
    GroupPendingItemsCompanion Function({
      Value<int> id,
      required String groupId,
      required Uint8List payload,
      required DateTime receivedAt,
    });
typedef $$GroupPendingItemsTableUpdateCompanionBuilder =
    GroupPendingItemsCompanion Function({
      Value<int> id,
      Value<String> groupId,
      Value<Uint8List> payload,
      Value<DateTime> receivedAt,
    });

final class $$GroupPendingItemsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $GroupPendingItemsTable,
          GroupPendingItemRow
        > {
  $$GroupPendingItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $GroupChannelsTable _groupIdTable(_$AppDatabase db) =>
      db.groupChannels.createAlias(
        $_aliasNameGenerator(
          db.groupPendingItems.groupId,
          db.groupChannels.groupId,
        ),
      );

  $$GroupChannelsTableProcessedTableManager get groupId {
    final $_column = $_itemColumn<String>('group_id')!;

    final manager = $$GroupChannelsTableTableManager(
      $_db,
      $_db.groupChannels,
    ).filter((f) => f.groupId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GroupPendingItemsTableFilterComposer
    extends Composer<_$AppDatabase, $GroupPendingItemsTable> {
  $$GroupPendingItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$GroupChannelsTableFilterComposer get groupId {
    final $$GroupChannelsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groupChannels,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupChannelsTableFilterComposer(
            $db: $db,
            $table: $db.groupChannels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupPendingItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupPendingItemsTable> {
  $$GroupPendingItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$GroupChannelsTableOrderingComposer get groupId {
    final $$GroupChannelsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groupChannels,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupChannelsTableOrderingComposer(
            $db: $db,
            $table: $db.groupChannels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupPendingItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupPendingItemsTable> {
  $$GroupPendingItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => column,
  );

  $$GroupChannelsTableAnnotationComposer get groupId {
    final $$GroupChannelsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: $db.groupChannels,
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GroupChannelsTableAnnotationComposer(
            $db: $db,
            $table: $db.groupChannels,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GroupPendingItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupPendingItemsTable,
          GroupPendingItemRow,
          $$GroupPendingItemsTableFilterComposer,
          $$GroupPendingItemsTableOrderingComposer,
          $$GroupPendingItemsTableAnnotationComposer,
          $$GroupPendingItemsTableCreateCompanionBuilder,
          $$GroupPendingItemsTableUpdateCompanionBuilder,
          (GroupPendingItemRow, $$GroupPendingItemsTableReferences),
          GroupPendingItemRow,
          PrefetchHooks Function({bool groupId})
        > {
  $$GroupPendingItemsTableTableManager(
    _$AppDatabase db,
    $GroupPendingItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupPendingItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupPendingItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupPendingItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<Uint8List> payload = const Value.absent(),
                Value<DateTime> receivedAt = const Value.absent(),
              }) => GroupPendingItemsCompanion(
                id: id,
                groupId: groupId,
                payload: payload,
                receivedAt: receivedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String groupId,
                required Uint8List payload,
                required DateTime receivedAt,
              }) => GroupPendingItemsCompanion.insert(
                id: id,
                groupId: groupId,
                payload: payload,
                receivedAt: receivedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GroupPendingItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({groupId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (groupId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.groupId,
                                referencedTable:
                                    $$GroupPendingItemsTableReferences
                                        ._groupIdTable(db),
                                referencedColumn:
                                    $$GroupPendingItemsTableReferences
                                        ._groupIdTable(db)
                                        .groupId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GroupPendingItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupPendingItemsTable,
      GroupPendingItemRow,
      $$GroupPendingItemsTableFilterComposer,
      $$GroupPendingItemsTableOrderingComposer,
      $$GroupPendingItemsTableAnnotationComposer,
      $$GroupPendingItemsTableCreateCompanionBuilder,
      $$GroupPendingItemsTableUpdateCompanionBuilder,
      (GroupPendingItemRow, $$GroupPendingItemsTableReferences),
      GroupPendingItemRow,
      PrefetchHooks Function({bool groupId})
    >;
typedef $$GroupInvitesTableCreateCompanionBuilder =
    GroupInvitesCompanion Function({
      required String groupId,
      required String groupName,
      required String adminMemberId,
      required String channelId,
      required DateTime receivedAt,
      Value<int> rowid,
    });
typedef $$GroupInvitesTableUpdateCompanionBuilder =
    GroupInvitesCompanion Function({
      Value<String> groupId,
      Value<String> groupName,
      Value<String> adminMemberId,
      Value<String> channelId,
      Value<DateTime> receivedAt,
      Value<int> rowid,
    });

class $$GroupInvitesTableFilterComposer
    extends Composer<_$AppDatabase, $GroupInvitesTable> {
  $$GroupInvitesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get adminMemberId => $composableBuilder(
    column: $table.adminMemberId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channelId => $composableBuilder(
    column: $table.channelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GroupInvitesTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupInvitesTable> {
  $$GroupInvitesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get adminMemberId => $composableBuilder(
    column: $table.adminMemberId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channelId => $composableBuilder(
    column: $table.channelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupInvitesTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupInvitesTable> {
  $$GroupInvitesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get groupName =>
      $composableBuilder(column: $table.groupName, builder: (column) => column);

  GeneratedColumn<String> get adminMemberId => $composableBuilder(
    column: $table.adminMemberId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get channelId =>
      $composableBuilder(column: $table.channelId, builder: (column) => column);

  GeneratedColumn<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => column,
  );
}

class $$GroupInvitesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupInvitesTable,
          GroupInviteRow,
          $$GroupInvitesTableFilterComposer,
          $$GroupInvitesTableOrderingComposer,
          $$GroupInvitesTableAnnotationComposer,
          $$GroupInvitesTableCreateCompanionBuilder,
          $$GroupInvitesTableUpdateCompanionBuilder,
          (
            GroupInviteRow,
            BaseReferences<_$AppDatabase, $GroupInvitesTable, GroupInviteRow>,
          ),
          GroupInviteRow,
          PrefetchHooks Function()
        > {
  $$GroupInvitesTableTableManager(_$AppDatabase db, $GroupInvitesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupInvitesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupInvitesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupInvitesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> groupName = const Value.absent(),
                Value<String> adminMemberId = const Value.absent(),
                Value<String> channelId = const Value.absent(),
                Value<DateTime> receivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupInvitesCompanion(
                groupId: groupId,
                groupName: groupName,
                adminMemberId: adminMemberId,
                channelId: channelId,
                receivedAt: receivedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String groupName,
                required String adminMemberId,
                required String channelId,
                required DateTime receivedAt,
                Value<int> rowid = const Value.absent(),
              }) => GroupInvitesCompanion.insert(
                groupId: groupId,
                groupName: groupName,
                adminMemberId: adminMemberId,
                channelId: channelId,
                receivedAt: receivedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GroupInvitesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupInvitesTable,
      GroupInviteRow,
      $$GroupInvitesTableFilterComposer,
      $$GroupInvitesTableOrderingComposer,
      $$GroupInvitesTableAnnotationComposer,
      $$GroupInvitesTableCreateCompanionBuilder,
      $$GroupInvitesTableUpdateCompanionBuilder,
      (
        GroupInviteRow,
        BaseReferences<_$AppDatabase, $GroupInvitesTable, GroupInviteRow>,
      ),
      GroupInviteRow,
      PrefetchHooks Function()
    >;
typedef $$MessageReceiptsTableCreateCompanionBuilder =
    MessageReceiptsCompanion Function({
      required String conversationId,
      required String messageId,
      required String memberId,
      Value<bool> routed,
      Value<bool> delivered,
      Value<int> rowid,
    });
typedef $$MessageReceiptsTableUpdateCompanionBuilder =
    MessageReceiptsCompanion Function({
      Value<String> conversationId,
      Value<String> messageId,
      Value<String> memberId,
      Value<bool> routed,
      Value<bool> delivered,
      Value<int> rowid,
    });

class $$MessageReceiptsTableFilterComposer
    extends Composer<_$AppDatabase, $MessageReceiptsTable> {
  $$MessageReceiptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get routed => $composableBuilder(
    column: $table.routed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get delivered => $composableBuilder(
    column: $table.delivered,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessageReceiptsTableOrderingComposer
    extends Composer<_$AppDatabase, $MessageReceiptsTable> {
  $$MessageReceiptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get routed => $composableBuilder(
    column: $table.routed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get delivered => $composableBuilder(
    column: $table.delivered,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessageReceiptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessageReceiptsTable> {
  $$MessageReceiptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get memberId =>
      $composableBuilder(column: $table.memberId, builder: (column) => column);

  GeneratedColumn<bool> get routed =>
      $composableBuilder(column: $table.routed, builder: (column) => column);

  GeneratedColumn<bool> get delivered =>
      $composableBuilder(column: $table.delivered, builder: (column) => column);
}

class $$MessageReceiptsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessageReceiptsTable,
          MessageReceiptRow,
          $$MessageReceiptsTableFilterComposer,
          $$MessageReceiptsTableOrderingComposer,
          $$MessageReceiptsTableAnnotationComposer,
          $$MessageReceiptsTableCreateCompanionBuilder,
          $$MessageReceiptsTableUpdateCompanionBuilder,
          (
            MessageReceiptRow,
            BaseReferences<
              _$AppDatabase,
              $MessageReceiptsTable,
              MessageReceiptRow
            >,
          ),
          MessageReceiptRow,
          PrefetchHooks Function()
        > {
  $$MessageReceiptsTableTableManager(
    _$AppDatabase db,
    $MessageReceiptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageReceiptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageReceiptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageReceiptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> conversationId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> memberId = const Value.absent(),
                Value<bool> routed = const Value.absent(),
                Value<bool> delivered = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageReceiptsCompanion(
                conversationId: conversationId,
                messageId: messageId,
                memberId: memberId,
                routed: routed,
                delivered: delivered,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String conversationId,
                required String messageId,
                required String memberId,
                Value<bool> routed = const Value.absent(),
                Value<bool> delivered = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageReceiptsCompanion.insert(
                conversationId: conversationId,
                messageId: messageId,
                memberId: memberId,
                routed: routed,
                delivered: delivered,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessageReceiptsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessageReceiptsTable,
      MessageReceiptRow,
      $$MessageReceiptsTableFilterComposer,
      $$MessageReceiptsTableOrderingComposer,
      $$MessageReceiptsTableAnnotationComposer,
      $$MessageReceiptsTableCreateCompanionBuilder,
      $$MessageReceiptsTableUpdateCompanionBuilder,
      (
        MessageReceiptRow,
        BaseReferences<_$AppDatabase, $MessageReceiptsTable, MessageReceiptRow>,
      ),
      MessageReceiptRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$ChannelsTableTableManager get channels =>
      $$ChannelsTableTableManager(_db, _db.channels);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$PeersTableTableManager get peers =>
      $$PeersTableTableManager(_db, _db.peers);
  $$OutboundHandlesTableTableManager get outboundHandles =>
      $$OutboundHandlesTableTableManager(_db, _db.outboundHandles);
  $$SessionTagsTableTableManager get sessionTags =>
      $$SessionTagsTableTableManager(_db, _db.sessionTags);
  $$NodeScoresTableTableManager get nodeScores =>
      $$NodeScoresTableTableManager(_db, _db.nodeScores);
  $$GroupChannelsTableTableManager get groupChannels =>
      $$GroupChannelsTableTableManager(_db, _db.groupChannels);
  $$GroupMembersTableTableManager get groupMembers =>
      $$GroupMembersTableTableManager(_db, _db.groupMembers);
  $$GroupPendingItemsTableTableManager get groupPendingItems =>
      $$GroupPendingItemsTableTableManager(_db, _db.groupPendingItems);
  $$GroupInvitesTableTableManager get groupInvites =>
      $$GroupInvitesTableTableManager(_db, _db.groupInvites);
  $$MessageReceiptsTableTableManager get messageReceipts =>
      $$MessageReceiptsTableTableManager(_db, _db.messageReceipts);
}
