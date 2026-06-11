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
  static const VerificationMeta _authenticationKeyMeta = const VerificationMeta(
    'authenticationKey',
  );
  @override
  late final GeneratedColumn<String> authenticationKey =
      GeneratedColumn<String>(
        'authentication_key',
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
    uuid,
    label,
    encryptionKey,
    authenticationKey,
    peerOhEndpoint,
    peerOhId,
    peerOhPublicKey,
    lastSeen,
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
    if (data.containsKey('authentication_key')) {
      context.handle(
        _authenticationKeyMeta,
        authenticationKey.isAcceptableOrUnknown(
          data['authentication_key']!,
          _authenticationKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authenticationKeyMeta);
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
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
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
      authenticationKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}authentication_key'],
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
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen'],
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
  final String authenticationKey;
  final String? peerOhEndpoint;
  final String? peerOhId;
  final String? peerOhPublicKey;
  final DateTime? lastSeen;
  const Channel({
    required this.uuid,
    required this.label,
    required this.encryptionKey,
    required this.authenticationKey,
    this.peerOhEndpoint,
    this.peerOhId,
    this.peerOhPublicKey,
    this.lastSeen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uuid'] = Variable<String>(uuid);
    map['label'] = Variable<String>(label);
    map['encryption_key'] = Variable<String>(encryptionKey);
    map['authentication_key'] = Variable<String>(authenticationKey);
    if (!nullToAbsent || peerOhEndpoint != null) {
      map['peer_oh_endpoint'] = Variable<String>(peerOhEndpoint);
    }
    if (!nullToAbsent || peerOhId != null) {
      map['peer_oh_id'] = Variable<String>(peerOhId);
    }
    if (!nullToAbsent || peerOhPublicKey != null) {
      map['peer_oh_public_key'] = Variable<String>(peerOhPublicKey);
    }
    if (!nullToAbsent || lastSeen != null) {
      map['last_seen'] = Variable<DateTime>(lastSeen);
    }
    return map;
  }

  ChannelsCompanion toCompanion(bool nullToAbsent) {
    return ChannelsCompanion(
      uuid: Value(uuid),
      label: Value(label),
      encryptionKey: Value(encryptionKey),
      authenticationKey: Value(authenticationKey),
      peerOhEndpoint: peerOhEndpoint == null && nullToAbsent
          ? const Value.absent()
          : Value(peerOhEndpoint),
      peerOhId: peerOhId == null && nullToAbsent
          ? const Value.absent()
          : Value(peerOhId),
      peerOhPublicKey: peerOhPublicKey == null && nullToAbsent
          ? const Value.absent()
          : Value(peerOhPublicKey),
      lastSeen: lastSeen == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeen),
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
      authenticationKey: serializer.fromJson<String>(json['authenticationKey']),
      peerOhEndpoint: serializer.fromJson<String?>(json['peerOhEndpoint']),
      peerOhId: serializer.fromJson<String?>(json['peerOhId']),
      peerOhPublicKey: serializer.fromJson<String?>(json['peerOhPublicKey']),
      lastSeen: serializer.fromJson<DateTime?>(json['lastSeen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uuid': serializer.toJson<String>(uuid),
      'label': serializer.toJson<String>(label),
      'encryptionKey': serializer.toJson<String>(encryptionKey),
      'authenticationKey': serializer.toJson<String>(authenticationKey),
      'peerOhEndpoint': serializer.toJson<String?>(peerOhEndpoint),
      'peerOhId': serializer.toJson<String?>(peerOhId),
      'peerOhPublicKey': serializer.toJson<String?>(peerOhPublicKey),
      'lastSeen': serializer.toJson<DateTime?>(lastSeen),
    };
  }

  Channel copyWith({
    String? uuid,
    String? label,
    String? encryptionKey,
    String? authenticationKey,
    Value<String?> peerOhEndpoint = const Value.absent(),
    Value<String?> peerOhId = const Value.absent(),
    Value<String?> peerOhPublicKey = const Value.absent(),
    Value<DateTime?> lastSeen = const Value.absent(),
  }) => Channel(
    uuid: uuid ?? this.uuid,
    label: label ?? this.label,
    encryptionKey: encryptionKey ?? this.encryptionKey,
    authenticationKey: authenticationKey ?? this.authenticationKey,
    peerOhEndpoint: peerOhEndpoint.present
        ? peerOhEndpoint.value
        : this.peerOhEndpoint,
    peerOhId: peerOhId.present ? peerOhId.value : this.peerOhId,
    peerOhPublicKey: peerOhPublicKey.present
        ? peerOhPublicKey.value
        : this.peerOhPublicKey,
    lastSeen: lastSeen.present ? lastSeen.value : this.lastSeen,
  );
  Channel copyWithCompanion(ChannelsCompanion data) {
    return Channel(
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      label: data.label.present ? data.label.value : this.label,
      encryptionKey: data.encryptionKey.present
          ? data.encryptionKey.value
          : this.encryptionKey,
      authenticationKey: data.authenticationKey.present
          ? data.authenticationKey.value
          : this.authenticationKey,
      peerOhEndpoint: data.peerOhEndpoint.present
          ? data.peerOhEndpoint.value
          : this.peerOhEndpoint,
      peerOhId: data.peerOhId.present ? data.peerOhId.value : this.peerOhId,
      peerOhPublicKey: data.peerOhPublicKey.present
          ? data.peerOhPublicKey.value
          : this.peerOhPublicKey,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Channel(')
          ..write('uuid: $uuid, ')
          ..write('label: $label, ')
          ..write('encryptionKey: $encryptionKey, ')
          ..write('authenticationKey: $authenticationKey, ')
          ..write('peerOhEndpoint: $peerOhEndpoint, ')
          ..write('peerOhId: $peerOhId, ')
          ..write('peerOhPublicKey: $peerOhPublicKey, ')
          ..write('lastSeen: $lastSeen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    uuid,
    label,
    encryptionKey,
    authenticationKey,
    peerOhEndpoint,
    peerOhId,
    peerOhPublicKey,
    lastSeen,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Channel &&
          other.uuid == this.uuid &&
          other.label == this.label &&
          other.encryptionKey == this.encryptionKey &&
          other.authenticationKey == this.authenticationKey &&
          other.peerOhEndpoint == this.peerOhEndpoint &&
          other.peerOhId == this.peerOhId &&
          other.peerOhPublicKey == this.peerOhPublicKey &&
          other.lastSeen == this.lastSeen);
}

class ChannelsCompanion extends UpdateCompanion<Channel> {
  final Value<String> uuid;
  final Value<String> label;
  final Value<String> encryptionKey;
  final Value<String> authenticationKey;
  final Value<String?> peerOhEndpoint;
  final Value<String?> peerOhId;
  final Value<String?> peerOhPublicKey;
  final Value<DateTime?> lastSeen;
  final Value<int> rowid;
  const ChannelsCompanion({
    this.uuid = const Value.absent(),
    this.label = const Value.absent(),
    this.encryptionKey = const Value.absent(),
    this.authenticationKey = const Value.absent(),
    this.peerOhEndpoint = const Value.absent(),
    this.peerOhId = const Value.absent(),
    this.peerOhPublicKey = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChannelsCompanion.insert({
    required String uuid,
    required String label,
    required String encryptionKey,
    required String authenticationKey,
    this.peerOhEndpoint = const Value.absent(),
    this.peerOhId = const Value.absent(),
    this.peerOhPublicKey = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : uuid = Value(uuid),
       label = Value(label),
       encryptionKey = Value(encryptionKey),
       authenticationKey = Value(authenticationKey);
  static Insertable<Channel> custom({
    Expression<String>? uuid,
    Expression<String>? label,
    Expression<String>? encryptionKey,
    Expression<String>? authenticationKey,
    Expression<String>? peerOhEndpoint,
    Expression<String>? peerOhId,
    Expression<String>? peerOhPublicKey,
    Expression<DateTime>? lastSeen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (uuid != null) 'uuid': uuid,
      if (label != null) 'label': label,
      if (encryptionKey != null) 'encryption_key': encryptionKey,
      if (authenticationKey != null) 'authentication_key': authenticationKey,
      if (peerOhEndpoint != null) 'peer_oh_endpoint': peerOhEndpoint,
      if (peerOhId != null) 'peer_oh_id': peerOhId,
      if (peerOhPublicKey != null) 'peer_oh_public_key': peerOhPublicKey,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChannelsCompanion copyWith({
    Value<String>? uuid,
    Value<String>? label,
    Value<String>? encryptionKey,
    Value<String>? authenticationKey,
    Value<String?>? peerOhEndpoint,
    Value<String?>? peerOhId,
    Value<String?>? peerOhPublicKey,
    Value<DateTime?>? lastSeen,
    Value<int>? rowid,
  }) {
    return ChannelsCompanion(
      uuid: uuid ?? this.uuid,
      label: label ?? this.label,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      authenticationKey: authenticationKey ?? this.authenticationKey,
      peerOhEndpoint: peerOhEndpoint ?? this.peerOhEndpoint,
      peerOhId: peerOhId ?? this.peerOhId,
      peerOhPublicKey: peerOhPublicKey ?? this.peerOhPublicKey,
      lastSeen: lastSeen ?? this.lastSeen,
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
    if (authenticationKey.present) {
      map['authentication_key'] = Variable<String>(authenticationKey.value);
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
    return (StringBuffer('ChannelsCompanion(')
          ..write('uuid: $uuid, ')
          ..write('label: $label, ')
          ..write('encryptionKey: $encryptionKey, ')
          ..write('authenticationKey: $authenticationKey, ')
          ..write('peerOhEndpoint: $peerOhEndpoint, ')
          ..write('peerOhId: $peerOhId, ')
          ..write('peerOhPublicKey: $peerOhPublicKey, ')
          ..write('lastSeen: $lastSeen, ')
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
          ..write('lastRetryAt: $lastRetryAt')
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
          other.lastRetryAt == this.lastRetryAt);
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
          ..write('lastRetryAt: $lastRetryAt')
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
  final int averageLatencyMs;
  final int successCount;
  final int failureCount;
  final DateTime? lastSeen;
  const Peer({
    required this.address,
    this.nodeId,
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
      'averageLatencyMs': serializer.toJson<int>(averageLatencyMs),
      'successCount': serializer.toJson<int>(successCount),
      'failureCount': serializer.toJson<int>(failureCount),
      'lastSeen': serializer.toJson<DateTime?>(lastSeen),
    };
  }

  Peer copyWith({
    String? address,
    Value<String?> nodeId = const Value.absent(),
    int? averageLatencyMs,
    int? successCount,
    int? failureCount,
    Value<DateTime?> lastSeen = const Value.absent(),
  }) => Peer(
    address: address ?? this.address,
    nodeId: nodeId.present ? nodeId.value : this.nodeId,
    averageLatencyMs: averageLatencyMs ?? this.averageLatencyMs,
    successCount: successCount ?? this.successCount,
    failureCount: failureCount ?? this.failureCount,
    lastSeen: lastSeen.present ? lastSeen.value : this.lastSeen,
  );
  Peer copyWithCompanion(PeersCompanion data) {
    return Peer(
      address: data.address.present ? data.address.value : this.address,
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
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
          other.averageLatencyMs == this.averageLatencyMs &&
          other.successCount == this.successCount &&
          other.failureCount == this.failureCount &&
          other.lastSeen == this.lastSeen);
}

class PeersCompanion extends UpdateCompanion<Peer> {
  final Value<String> address;
  final Value<String?> nodeId;
  final Value<int> averageLatencyMs;
  final Value<int> successCount;
  final Value<int> failureCount;
  final Value<DateTime?> lastSeen;
  final Value<int> rowid;
  const PeersCompanion({
    this.address = const Value.absent(),
    this.nodeId = const Value.absent(),
    this.averageLatencyMs = const Value.absent(),
    this.successCount = const Value.absent(),
    this.failureCount = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeersCompanion.insert({
    required String address,
    this.nodeId = const Value.absent(),
    this.averageLatencyMs = const Value.absent(),
    this.successCount = const Value.absent(),
    this.failureCount = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : address = Value(address);
  static Insertable<Peer> custom({
    Expression<String>? address,
    Expression<String>? nodeId,
    Expression<int>? averageLatencyMs,
    Expression<int>? successCount,
    Expression<int>? failureCount,
    Expression<DateTime>? lastSeen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (address != null) 'address': address,
      if (nodeId != null) 'node_id': nodeId,
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
    Value<int>? averageLatencyMs,
    Value<int>? successCount,
    Value<int>? failureCount,
    Value<DateTime?>? lastSeen,
    Value<int>? rowid,
  }) {
    return PeersCompanion(
      address: address ?? this.address,
      nodeId: nodeId ?? this.nodeId,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ohId,
    keypairBytes,
    serverEndpoint,
    expiresAt,
    channelId,
    lastCursor,
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
  const OutboundHandle({
    required this.id,
    required this.ohId,
    required this.keypairBytes,
    required this.serverEndpoint,
    required this.expiresAt,
    this.channelId,
    required this.lastCursor,
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
  }) => OutboundHandle(
    id: id ?? this.id,
    ohId: ohId ?? this.ohId,
    keypairBytes: keypairBytes ?? this.keypairBytes,
    serverEndpoint: serverEndpoint ?? this.serverEndpoint,
    expiresAt: expiresAt ?? this.expiresAt,
    channelId: channelId.present ? channelId.value : this.channelId,
    lastCursor: lastCursor ?? this.lastCursor,
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
          ..write('lastCursor: $lastCursor')
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
          other.lastCursor == this.lastCursor);
}

class OutboundHandlesCompanion extends UpdateCompanion<OutboundHandle> {
  final Value<int> id;
  final Value<String> ohId;
  final Value<Uint8List> keypairBytes;
  final Value<String> serverEndpoint;
  final Value<DateTime> expiresAt;
  final Value<String?> channelId;
  final Value<int> lastCursor;
  const OutboundHandlesCompanion({
    this.id = const Value.absent(),
    this.ohId = const Value.absent(),
    this.keypairBytes = const Value.absent(),
    this.serverEndpoint = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.channelId = const Value.absent(),
    this.lastCursor = const Value.absent(),
  });
  OutboundHandlesCompanion.insert({
    this.id = const Value.absent(),
    required String ohId,
    required Uint8List keypairBytes,
    required String serverEndpoint,
    required DateTime expiresAt,
    this.channelId = const Value.absent(),
    this.lastCursor = const Value.absent(),
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
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ohId != null) 'oh_id': ohId,
      if (keypairBytes != null) 'keypair_bytes': keypairBytes,
      if (serverEndpoint != null) 'server_endpoint': serverEndpoint,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (channelId != null) 'channel_id': channelId,
      if (lastCursor != null) 'last_cursor': lastCursor,
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
  }) {
    return OutboundHandlesCompanion(
      id: id ?? this.id,
      ohId: ohId ?? this.ohId,
      keypairBytes: keypairBytes ?? this.keypairBytes,
      serverEndpoint: serverEndpoint ?? this.serverEndpoint,
      expiresAt: expiresAt ?? this.expiresAt,
      channelId: channelId ?? this.channelId,
      lastCursor: lastCursor ?? this.lastCursor,
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
          ..write('lastCursor: $lastCursor')
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
  late final Index idxMessagesMessageId = Index(
    'idx_messages_message_id',
    'CREATE UNIQUE INDEX idx_messages_message_id ON messages (message_id)',
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
    idxMessagesMessageId,
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
      required String authenticationKey,
      Value<String?> peerOhEndpoint,
      Value<String?> peerOhId,
      Value<String?> peerOhPublicKey,
      Value<DateTime?> lastSeen,
      Value<int> rowid,
    });
typedef $$ChannelsTableUpdateCompanionBuilder =
    ChannelsCompanion Function({
      Value<String> uuid,
      Value<String> label,
      Value<String> encryptionKey,
      Value<String> authenticationKey,
      Value<String?> peerOhEndpoint,
      Value<String?> peerOhId,
      Value<String?> peerOhPublicKey,
      Value<DateTime?> lastSeen,
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

  ColumnFilters<String> get authenticationKey => $composableBuilder(
    column: $table.authenticationKey,
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

  ColumnFilters<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
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

  ColumnOrderings<String> get authenticationKey => $composableBuilder(
    column: $table.authenticationKey,
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

  ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
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

  GeneratedColumn<String> get authenticationKey => $composableBuilder(
    column: $table.authenticationKey,
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

  GeneratedColumn<DateTime> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

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
          PrefetchHooks Function({bool messagesRefs})
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
                Value<String> authenticationKey = const Value.absent(),
                Value<String?> peerOhEndpoint = const Value.absent(),
                Value<String?> peerOhId = const Value.absent(),
                Value<String?> peerOhPublicKey = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelsCompanion(
                uuid: uuid,
                label: label,
                encryptionKey: encryptionKey,
                authenticationKey: authenticationKey,
                peerOhEndpoint: peerOhEndpoint,
                peerOhId: peerOhId,
                peerOhPublicKey: peerOhPublicKey,
                lastSeen: lastSeen,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String uuid,
                required String label,
                required String encryptionKey,
                required String authenticationKey,
                Value<String?> peerOhEndpoint = const Value.absent(),
                Value<String?> peerOhId = const Value.absent(),
                Value<String?> peerOhPublicKey = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelsCompanion.insert(
                uuid: uuid,
                label: label,
                encryptionKey: encryptionKey,
                authenticationKey: authenticationKey,
                peerOhEndpoint: peerOhEndpoint,
                peerOhId: peerOhId,
                peerOhPublicKey: peerOhPublicKey,
                lastSeen: lastSeen,
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
          prefetchHooksCallback: ({messagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (messagesRefs) db.messages],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (messagesRefs)
                    await $_getPrefetchedData<Channel, $ChannelsTable, Message>(
                      currentTable: table,
                      referencedTable: $$ChannelsTableReferences
                          ._messagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ChannelsTableReferences(db, table, p0).messagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.conversationId == item.uuid,
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
      PrefetchHooks Function({bool messagesRefs})
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
                Value<int> averageLatencyMs = const Value.absent(),
                Value<int> successCount = const Value.absent(),
                Value<int> failureCount = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeersCompanion(
                address: address,
                nodeId: nodeId,
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
                Value<int> averageLatencyMs = const Value.absent(),
                Value<int> successCount = const Value.absent(),
                Value<int> failureCount = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeersCompanion.insert(
                address: address,
                nodeId: nodeId,
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
              }) => OutboundHandlesCompanion(
                id: id,
                ohId: ohId,
                keypairBytes: keypairBytes,
                serverEndpoint: serverEndpoint,
                expiresAt: expiresAt,
                channelId: channelId,
                lastCursor: lastCursor,
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
              }) => OutboundHandlesCompanion.insert(
                id: id,
                ohId: ohId,
                keypairBytes: keypairBytes,
                serverEndpoint: serverEndpoint,
                expiresAt: expiresAt,
                channelId: channelId,
                lastCursor: lastCursor,
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
}
