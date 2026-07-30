// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LocalOwnersTable extends LocalOwners
    with TableInfo<$LocalOwnersTable, LocalOwner> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalOwnersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firebaseUidMeta = const VerificationMeta(
    'firebaseUid',
  );
  @override
  late final GeneratedColumn<String> firebaseUid = GeneratedColumn<String>(
    'firebase_uid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _accountStateMeta = const VerificationMeta(
    'accountState',
  );
  @override
  late final GeneratedColumn<String> accountState = GeneratedColumn<String>(
    'account_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('localGuest'),
  );
  static const VerificationMeta _createdAtUtcMsMeta = const VerificationMeta(
    'createdAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> createdAtUtcMs = GeneratedColumn<int>(
    'created_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (created_at_utc_ms >= 0)',
  );
  static const VerificationMeta _upgradedAtUtcMsMeta = const VerificationMeta(
    'upgradedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> upgradedAtUtcMs = GeneratedColumn<int>(
    'upgraded_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    firebaseUid,
    accountState,
    createdAtUtcMs,
    upgradedAtUtcMs,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_owners';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalOwner> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('firebase_uid')) {
      context.handle(
        _firebaseUidMeta,
        firebaseUid.isAcceptableOrUnknown(
          data['firebase_uid']!,
          _firebaseUidMeta,
        ),
      );
    }
    if (data.containsKey('account_state')) {
      context.handle(
        _accountStateMeta,
        accountState.isAcceptableOrUnknown(
          data['account_state']!,
          _accountStateMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc_ms')) {
      context.handle(
        _createdAtUtcMsMeta,
        createdAtUtcMs.isAcceptableOrUnknown(
          data['created_at_utc_ms']!,
          _createdAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMsMeta);
    }
    if (data.containsKey('upgraded_at_utc_ms')) {
      context.handle(
        _upgradedAtUtcMsMeta,
        upgradedAtUtcMs.isAcceptableOrUnknown(
          data['upgraded_at_utc_ms']!,
          _upgradedAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalOwner map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalOwner(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      firebaseUid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}firebase_uid'],
      ),
      accountState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_state'],
      )!,
      createdAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc_ms'],
      )!,
      upgradedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}upgraded_at_utc_ms'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $LocalOwnersTable createAlias(String alias) {
    return $LocalOwnersTable(attachedDatabase, alias);
  }
}

class LocalOwner extends DataClass implements Insertable<LocalOwner> {
  final String id;
  final String? firebaseUid;
  final String accountState;
  final int createdAtUtcMs;
  final int? upgradedAtUtcMs;
  final bool isActive;
  const LocalOwner({
    required this.id,
    this.firebaseUid,
    required this.accountState,
    required this.createdAtUtcMs,
    this.upgradedAtUtcMs,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || firebaseUid != null) {
      map['firebase_uid'] = Variable<String>(firebaseUid);
    }
    map['account_state'] = Variable<String>(accountState);
    map['created_at_utc_ms'] = Variable<int>(createdAtUtcMs);
    if (!nullToAbsent || upgradedAtUtcMs != null) {
      map['upgraded_at_utc_ms'] = Variable<int>(upgradedAtUtcMs);
    }
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  LocalOwnersCompanion toCompanion(bool nullToAbsent) {
    return LocalOwnersCompanion(
      id: Value(id),
      firebaseUid: firebaseUid == null && nullToAbsent
          ? const Value.absent()
          : Value(firebaseUid),
      accountState: Value(accountState),
      createdAtUtcMs: Value(createdAtUtcMs),
      upgradedAtUtcMs: upgradedAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(upgradedAtUtcMs),
      isActive: Value(isActive),
    );
  }

  factory LocalOwner.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalOwner(
      id: serializer.fromJson<String>(json['id']),
      firebaseUid: serializer.fromJson<String?>(json['firebaseUid']),
      accountState: serializer.fromJson<String>(json['accountState']),
      createdAtUtcMs: serializer.fromJson<int>(json['createdAtUtcMs']),
      upgradedAtUtcMs: serializer.fromJson<int?>(json['upgradedAtUtcMs']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'firebaseUid': serializer.toJson<String?>(firebaseUid),
      'accountState': serializer.toJson<String>(accountState),
      'createdAtUtcMs': serializer.toJson<int>(createdAtUtcMs),
      'upgradedAtUtcMs': serializer.toJson<int?>(upgradedAtUtcMs),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  LocalOwner copyWith({
    String? id,
    Value<String?> firebaseUid = const Value.absent(),
    String? accountState,
    int? createdAtUtcMs,
    Value<int?> upgradedAtUtcMs = const Value.absent(),
    bool? isActive,
  }) => LocalOwner(
    id: id ?? this.id,
    firebaseUid: firebaseUid.present ? firebaseUid.value : this.firebaseUid,
    accountState: accountState ?? this.accountState,
    createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
    upgradedAtUtcMs: upgradedAtUtcMs.present
        ? upgradedAtUtcMs.value
        : this.upgradedAtUtcMs,
    isActive: isActive ?? this.isActive,
  );
  LocalOwner copyWithCompanion(LocalOwnersCompanion data) {
    return LocalOwner(
      id: data.id.present ? data.id.value : this.id,
      firebaseUid: data.firebaseUid.present
          ? data.firebaseUid.value
          : this.firebaseUid,
      accountState: data.accountState.present
          ? data.accountState.value
          : this.accountState,
      createdAtUtcMs: data.createdAtUtcMs.present
          ? data.createdAtUtcMs.value
          : this.createdAtUtcMs,
      upgradedAtUtcMs: data.upgradedAtUtcMs.present
          ? data.upgradedAtUtcMs.value
          : this.upgradedAtUtcMs,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalOwner(')
          ..write('id: $id, ')
          ..write('firebaseUid: $firebaseUid, ')
          ..write('accountState: $accountState, ')
          ..write('createdAtUtcMs: $createdAtUtcMs, ')
          ..write('upgradedAtUtcMs: $upgradedAtUtcMs, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    firebaseUid,
    accountState,
    createdAtUtcMs,
    upgradedAtUtcMs,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalOwner &&
          other.id == this.id &&
          other.firebaseUid == this.firebaseUid &&
          other.accountState == this.accountState &&
          other.createdAtUtcMs == this.createdAtUtcMs &&
          other.upgradedAtUtcMs == this.upgradedAtUtcMs &&
          other.isActive == this.isActive);
}

class LocalOwnersCompanion extends UpdateCompanion<LocalOwner> {
  final Value<String> id;
  final Value<String?> firebaseUid;
  final Value<String> accountState;
  final Value<int> createdAtUtcMs;
  final Value<int?> upgradedAtUtcMs;
  final Value<bool> isActive;
  final Value<int> rowid;
  const LocalOwnersCompanion({
    this.id = const Value.absent(),
    this.firebaseUid = const Value.absent(),
    this.accountState = const Value.absent(),
    this.createdAtUtcMs = const Value.absent(),
    this.upgradedAtUtcMs = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalOwnersCompanion.insert({
    required String id,
    this.firebaseUid = const Value.absent(),
    this.accountState = const Value.absent(),
    required int createdAtUtcMs,
    this.upgradedAtUtcMs = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAtUtcMs = Value(createdAtUtcMs);
  static Insertable<LocalOwner> custom({
    Expression<String>? id,
    Expression<String>? firebaseUid,
    Expression<String>? accountState,
    Expression<int>? createdAtUtcMs,
    Expression<int>? upgradedAtUtcMs,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (firebaseUid != null) 'firebase_uid': firebaseUid,
      if (accountState != null) 'account_state': accountState,
      if (createdAtUtcMs != null) 'created_at_utc_ms': createdAtUtcMs,
      if (upgradedAtUtcMs != null) 'upgraded_at_utc_ms': upgradedAtUtcMs,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalOwnersCompanion copyWith({
    Value<String>? id,
    Value<String?>? firebaseUid,
    Value<String>? accountState,
    Value<int>? createdAtUtcMs,
    Value<int?>? upgradedAtUtcMs,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return LocalOwnersCompanion(
      id: id ?? this.id,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      accountState: accountState ?? this.accountState,
      createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
      upgradedAtUtcMs: upgradedAtUtcMs ?? this.upgradedAtUtcMs,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (firebaseUid.present) {
      map['firebase_uid'] = Variable<String>(firebaseUid.value);
    }
    if (accountState.present) {
      map['account_state'] = Variable<String>(accountState.value);
    }
    if (createdAtUtcMs.present) {
      map['created_at_utc_ms'] = Variable<int>(createdAtUtcMs.value);
    }
    if (upgradedAtUtcMs.present) {
      map['upgraded_at_utc_ms'] = Variable<int>(upgradedAtUtcMs.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalOwnersCompanion(')
          ..write('id: $id, ')
          ..write('firebaseUid: $firebaseUid, ')
          ..write('accountState: $accountState, ')
          ..write('createdAtUtcMs: $createdAtUtcMs, ')
          ..write('upgradedAtUtcMs: $upgradedAtUtcMs, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ResearchConsentsTable extends ResearchConsents
    with TableInfo<$ResearchConsentsTable, ResearchConsent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ResearchConsentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _consentVersionMeta = const VerificationMeta(
    'consentVersion',
  );
  @override
  late final GeneratedColumn<int> consentVersion = GeneratedColumn<int>(
    'consent_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _consentStateMeta = const VerificationMeta(
    'consentState',
  );
  @override
  late final GeneratedColumn<String> consentState = GeneratedColumn<String>(
    'consent_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _decidedAtUtcMsMeta = const VerificationMeta(
    'decidedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> decidedAtUtcMs = GeneratedColumn<int>(
    'decided_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _withdrawnAtUtcMsMeta = const VerificationMeta(
    'withdrawnAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> withdrawnAtUtcMs = GeneratedColumn<int>(
    'withdrawn_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    consentVersion,
    consentState,
    decidedAtUtcMs,
    withdrawnAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'research_consents';
  @override
  VerificationContext validateIntegrity(
    Insertable<ResearchConsent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('consent_version')) {
      context.handle(
        _consentVersionMeta,
        consentVersion.isAcceptableOrUnknown(
          data['consent_version']!,
          _consentVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_consentVersionMeta);
    }
    if (data.containsKey('consent_state')) {
      context.handle(
        _consentStateMeta,
        consentState.isAcceptableOrUnknown(
          data['consent_state']!,
          _consentStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_consentStateMeta);
    }
    if (data.containsKey('decided_at_utc_ms')) {
      context.handle(
        _decidedAtUtcMsMeta,
        decidedAtUtcMs.isAcceptableOrUnknown(
          data['decided_at_utc_ms']!,
          _decidedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_decidedAtUtcMsMeta);
    }
    if (data.containsKey('withdrawn_at_utc_ms')) {
      context.handle(
        _withdrawnAtUtcMsMeta,
        withdrawnAtUtcMs.isAcceptableOrUnknown(
          data['withdrawn_at_utc_ms']!,
          _withdrawnAtUtcMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerId, consentVersion},
  ];
  @override
  ResearchConsent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ResearchConsent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      consentVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}consent_version'],
      )!,
      consentState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}consent_state'],
      )!,
      decidedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}decided_at_utc_ms'],
      )!,
      withdrawnAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}withdrawn_at_utc_ms'],
      ),
    );
  }

  @override
  $ResearchConsentsTable createAlias(String alias) {
    return $ResearchConsentsTable(attachedDatabase, alias);
  }
}

class ResearchConsent extends DataClass implements Insertable<ResearchConsent> {
  final String id;
  final String ownerId;
  final int consentVersion;
  final String consentState;
  final int decidedAtUtcMs;
  final int? withdrawnAtUtcMs;
  const ResearchConsent({
    required this.id,
    required this.ownerId,
    required this.consentVersion,
    required this.consentState,
    required this.decidedAtUtcMs,
    this.withdrawnAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['consent_version'] = Variable<int>(consentVersion);
    map['consent_state'] = Variable<String>(consentState);
    map['decided_at_utc_ms'] = Variable<int>(decidedAtUtcMs);
    if (!nullToAbsent || withdrawnAtUtcMs != null) {
      map['withdrawn_at_utc_ms'] = Variable<int>(withdrawnAtUtcMs);
    }
    return map;
  }

  ResearchConsentsCompanion toCompanion(bool nullToAbsent) {
    return ResearchConsentsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      consentVersion: Value(consentVersion),
      consentState: Value(consentState),
      decidedAtUtcMs: Value(decidedAtUtcMs),
      withdrawnAtUtcMs: withdrawnAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(withdrawnAtUtcMs),
    );
  }

  factory ResearchConsent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ResearchConsent(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      consentVersion: serializer.fromJson<int>(json['consentVersion']),
      consentState: serializer.fromJson<String>(json['consentState']),
      decidedAtUtcMs: serializer.fromJson<int>(json['decidedAtUtcMs']),
      withdrawnAtUtcMs: serializer.fromJson<int?>(json['withdrawnAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'consentVersion': serializer.toJson<int>(consentVersion),
      'consentState': serializer.toJson<String>(consentState),
      'decidedAtUtcMs': serializer.toJson<int>(decidedAtUtcMs),
      'withdrawnAtUtcMs': serializer.toJson<int?>(withdrawnAtUtcMs),
    };
  }

  ResearchConsent copyWith({
    String? id,
    String? ownerId,
    int? consentVersion,
    String? consentState,
    int? decidedAtUtcMs,
    Value<int?> withdrawnAtUtcMs = const Value.absent(),
  }) => ResearchConsent(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    consentVersion: consentVersion ?? this.consentVersion,
    consentState: consentState ?? this.consentState,
    decidedAtUtcMs: decidedAtUtcMs ?? this.decidedAtUtcMs,
    withdrawnAtUtcMs: withdrawnAtUtcMs.present
        ? withdrawnAtUtcMs.value
        : this.withdrawnAtUtcMs,
  );
  ResearchConsent copyWithCompanion(ResearchConsentsCompanion data) {
    return ResearchConsent(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      consentVersion: data.consentVersion.present
          ? data.consentVersion.value
          : this.consentVersion,
      consentState: data.consentState.present
          ? data.consentState.value
          : this.consentState,
      decidedAtUtcMs: data.decidedAtUtcMs.present
          ? data.decidedAtUtcMs.value
          : this.decidedAtUtcMs,
      withdrawnAtUtcMs: data.withdrawnAtUtcMs.present
          ? data.withdrawnAtUtcMs.value
          : this.withdrawnAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ResearchConsent(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('consentVersion: $consentVersion, ')
          ..write('consentState: $consentState, ')
          ..write('decidedAtUtcMs: $decidedAtUtcMs, ')
          ..write('withdrawnAtUtcMs: $withdrawnAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    consentVersion,
    consentState,
    decidedAtUtcMs,
    withdrawnAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ResearchConsent &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.consentVersion == this.consentVersion &&
          other.consentState == this.consentState &&
          other.decidedAtUtcMs == this.decidedAtUtcMs &&
          other.withdrawnAtUtcMs == this.withdrawnAtUtcMs);
}

class ResearchConsentsCompanion extends UpdateCompanion<ResearchConsent> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<int> consentVersion;
  final Value<String> consentState;
  final Value<int> decidedAtUtcMs;
  final Value<int?> withdrawnAtUtcMs;
  final Value<int> rowid;
  const ResearchConsentsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.consentVersion = const Value.absent(),
    this.consentState = const Value.absent(),
    this.decidedAtUtcMs = const Value.absent(),
    this.withdrawnAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ResearchConsentsCompanion.insert({
    required String id,
    required String ownerId,
    required int consentVersion,
    required String consentState,
    required int decidedAtUtcMs,
    this.withdrawnAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       consentVersion = Value(consentVersion),
       consentState = Value(consentState),
       decidedAtUtcMs = Value(decidedAtUtcMs);
  static Insertable<ResearchConsent> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<int>? consentVersion,
    Expression<String>? consentState,
    Expression<int>? decidedAtUtcMs,
    Expression<int>? withdrawnAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (consentVersion != null) 'consent_version': consentVersion,
      if (consentState != null) 'consent_state': consentState,
      if (decidedAtUtcMs != null) 'decided_at_utc_ms': decidedAtUtcMs,
      if (withdrawnAtUtcMs != null) 'withdrawn_at_utc_ms': withdrawnAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ResearchConsentsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<int>? consentVersion,
    Value<String>? consentState,
    Value<int>? decidedAtUtcMs,
    Value<int?>? withdrawnAtUtcMs,
    Value<int>? rowid,
  }) {
    return ResearchConsentsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      consentVersion: consentVersion ?? this.consentVersion,
      consentState: consentState ?? this.consentState,
      decidedAtUtcMs: decidedAtUtcMs ?? this.decidedAtUtcMs,
      withdrawnAtUtcMs: withdrawnAtUtcMs ?? this.withdrawnAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (consentVersion.present) {
      map['consent_version'] = Variable<int>(consentVersion.value);
    }
    if (consentState.present) {
      map['consent_state'] = Variable<String>(consentState.value);
    }
    if (decidedAtUtcMs.present) {
      map['decided_at_utc_ms'] = Variable<int>(decidedAtUtcMs.value);
    }
    if (withdrawnAtUtcMs.present) {
      map['withdrawn_at_utc_ms'] = Variable<int>(withdrawnAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ResearchConsentsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('consentVersion: $consentVersion, ')
          ..write('consentState: $consentState, ')
          ..write('decidedAtUtcMs: $decidedAtUtcMs, ')
          ..write('withdrawnAtUtcMs: $withdrawnAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VocabularyCategoriesTable extends VocabularyCategories
    with TableInfo<$VocabularyCategoriesTable, VocabularyCategory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VocabularyCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedNameMeta = const VerificationMeta(
    'normalizedName',
  );
  @override
  late final GeneratedColumn<String> normalizedName = GeneratedColumn<String>(
    'normalized_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _localRevisionMeta = const VerificationMeta(
    'localRevision',
  );
  @override
  late final GeneratedColumn<int> localRevision = GeneratedColumn<int>(
    'local_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _cloudRevisionMeta = const VerificationMeta(
    'cloudRevision',
  );
  @override
  late final GeneratedColumn<int> cloudRevision = GeneratedColumn<int>(
    'cloud_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastAcknowledgedAtUtcMsMeta =
      const VerificationMeta('lastAcknowledgedAtUtcMs');
  @override
  late final GeneratedColumn<int> lastAcknowledgedAtUtcMs =
      GeneratedColumn<int>(
        'last_acknowledged_at_utc_ms',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _serverUpdatedAtUtcMsMeta =
      const VerificationMeta('serverUpdatedAtUtcMs');
  @override
  late final GeneratedColumn<int> serverUpdatedAtUtcMs = GeneratedColumn<int>(
    'server_updated_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtUtcMsMeta = const VerificationMeta(
    'createdAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> createdAtUtcMs = GeneratedColumn<int>(
    'created_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMsMeta = const VerificationMeta(
    'updatedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtcMs = GeneratedColumn<int>(
    'updated_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    name,
    normalizedName,
    sortOrder,
    localRevision,
    cloudRevision,
    lastAcknowledgedAtUtcMs,
    serverUpdatedAtUtcMs,
    isDeleted,
    createdAtUtcMs,
    updatedAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vocabulary_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<VocabularyCategory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('normalized_name')) {
      context.handle(
        _normalizedNameMeta,
        normalizedName.isAcceptableOrUnknown(
          data['normalized_name']!,
          _normalizedNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedNameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('local_revision')) {
      context.handle(
        _localRevisionMeta,
        localRevision.isAcceptableOrUnknown(
          data['local_revision']!,
          _localRevisionMeta,
        ),
      );
    }
    if (data.containsKey('cloud_revision')) {
      context.handle(
        _cloudRevisionMeta,
        cloudRevision.isAcceptableOrUnknown(
          data['cloud_revision']!,
          _cloudRevisionMeta,
        ),
      );
    }
    if (data.containsKey('last_acknowledged_at_utc_ms')) {
      context.handle(
        _lastAcknowledgedAtUtcMsMeta,
        lastAcknowledgedAtUtcMs.isAcceptableOrUnknown(
          data['last_acknowledged_at_utc_ms']!,
          _lastAcknowledgedAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at_utc_ms')) {
      context.handle(
        _serverUpdatedAtUtcMsMeta,
        serverUpdatedAtUtcMs.isAcceptableOrUnknown(
          data['server_updated_at_utc_ms']!,
          _serverUpdatedAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('created_at_utc_ms')) {
      context.handle(
        _createdAtUtcMsMeta,
        createdAtUtcMs.isAcceptableOrUnknown(
          data['created_at_utc_ms']!,
          _createdAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMsMeta);
    }
    if (data.containsKey('updated_at_utc_ms')) {
      context.handle(
        _updatedAtUtcMsMeta,
        updatedAtUtcMs.isAcceptableOrUnknown(
          data['updated_at_utc_ms']!,
          _updatedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerId, normalizedName},
  ];
  @override
  VocabularyCategory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VocabularyCategory(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      normalizedName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      localRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_revision'],
      )!,
      cloudRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cloud_revision'],
      )!,
      lastAcknowledgedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_acknowledged_at_utc_ms'],
      ),
      serverUpdatedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_updated_at_utc_ms'],
      ),
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      createdAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc_ms'],
      )!,
      updatedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc_ms'],
      )!,
    );
  }

  @override
  $VocabularyCategoriesTable createAlias(String alias) {
    return $VocabularyCategoriesTable(attachedDatabase, alias);
  }
}

class VocabularyCategory extends DataClass
    implements Insertable<VocabularyCategory> {
  final String id;
  final String ownerId;
  final String name;
  final String normalizedName;
  final int sortOrder;
  final int localRevision;
  final int cloudRevision;
  final int? lastAcknowledgedAtUtcMs;
  final int? serverUpdatedAtUtcMs;
  final bool isDeleted;
  final int createdAtUtcMs;
  final int updatedAtUtcMs;
  const VocabularyCategory({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.normalizedName,
    required this.sortOrder,
    required this.localRevision,
    required this.cloudRevision,
    this.lastAcknowledgedAtUtcMs,
    this.serverUpdatedAtUtcMs,
    required this.isDeleted,
    required this.createdAtUtcMs,
    required this.updatedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['name'] = Variable<String>(name);
    map['normalized_name'] = Variable<String>(normalizedName);
    map['sort_order'] = Variable<int>(sortOrder);
    map['local_revision'] = Variable<int>(localRevision);
    map['cloud_revision'] = Variable<int>(cloudRevision);
    if (!nullToAbsent || lastAcknowledgedAtUtcMs != null) {
      map['last_acknowledged_at_utc_ms'] = Variable<int>(
        lastAcknowledgedAtUtcMs,
      );
    }
    if (!nullToAbsent || serverUpdatedAtUtcMs != null) {
      map['server_updated_at_utc_ms'] = Variable<int>(serverUpdatedAtUtcMs);
    }
    map['is_deleted'] = Variable<bool>(isDeleted);
    map['created_at_utc_ms'] = Variable<int>(createdAtUtcMs);
    map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs);
    return map;
  }

  VocabularyCategoriesCompanion toCompanion(bool nullToAbsent) {
    return VocabularyCategoriesCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      name: Value(name),
      normalizedName: Value(normalizedName),
      sortOrder: Value(sortOrder),
      localRevision: Value(localRevision),
      cloudRevision: Value(cloudRevision),
      lastAcknowledgedAtUtcMs: lastAcknowledgedAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAcknowledgedAtUtcMs),
      serverUpdatedAtUtcMs: serverUpdatedAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAtUtcMs),
      isDeleted: Value(isDeleted),
      createdAtUtcMs: Value(createdAtUtcMs),
      updatedAtUtcMs: Value(updatedAtUtcMs),
    );
  }

  factory VocabularyCategory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VocabularyCategory(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      name: serializer.fromJson<String>(json['name']),
      normalizedName: serializer.fromJson<String>(json['normalizedName']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      localRevision: serializer.fromJson<int>(json['localRevision']),
      cloudRevision: serializer.fromJson<int>(json['cloudRevision']),
      lastAcknowledgedAtUtcMs: serializer.fromJson<int?>(
        json['lastAcknowledgedAtUtcMs'],
      ),
      serverUpdatedAtUtcMs: serializer.fromJson<int?>(
        json['serverUpdatedAtUtcMs'],
      ),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      createdAtUtcMs: serializer.fromJson<int>(json['createdAtUtcMs']),
      updatedAtUtcMs: serializer.fromJson<int>(json['updatedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'name': serializer.toJson<String>(name),
      'normalizedName': serializer.toJson<String>(normalizedName),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'localRevision': serializer.toJson<int>(localRevision),
      'cloudRevision': serializer.toJson<int>(cloudRevision),
      'lastAcknowledgedAtUtcMs': serializer.toJson<int?>(
        lastAcknowledgedAtUtcMs,
      ),
      'serverUpdatedAtUtcMs': serializer.toJson<int?>(serverUpdatedAtUtcMs),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'createdAtUtcMs': serializer.toJson<int>(createdAtUtcMs),
      'updatedAtUtcMs': serializer.toJson<int>(updatedAtUtcMs),
    };
  }

  VocabularyCategory copyWith({
    String? id,
    String? ownerId,
    String? name,
    String? normalizedName,
    int? sortOrder,
    int? localRevision,
    int? cloudRevision,
    Value<int?> lastAcknowledgedAtUtcMs = const Value.absent(),
    Value<int?> serverUpdatedAtUtcMs = const Value.absent(),
    bool? isDeleted,
    int? createdAtUtcMs,
    int? updatedAtUtcMs,
  }) => VocabularyCategory(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    name: name ?? this.name,
    normalizedName: normalizedName ?? this.normalizedName,
    sortOrder: sortOrder ?? this.sortOrder,
    localRevision: localRevision ?? this.localRevision,
    cloudRevision: cloudRevision ?? this.cloudRevision,
    lastAcknowledgedAtUtcMs: lastAcknowledgedAtUtcMs.present
        ? lastAcknowledgedAtUtcMs.value
        : this.lastAcknowledgedAtUtcMs,
    serverUpdatedAtUtcMs: serverUpdatedAtUtcMs.present
        ? serverUpdatedAtUtcMs.value
        : this.serverUpdatedAtUtcMs,
    isDeleted: isDeleted ?? this.isDeleted,
    createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
    updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
  );
  VocabularyCategory copyWithCompanion(VocabularyCategoriesCompanion data) {
    return VocabularyCategory(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      name: data.name.present ? data.name.value : this.name,
      normalizedName: data.normalizedName.present
          ? data.normalizedName.value
          : this.normalizedName,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      localRevision: data.localRevision.present
          ? data.localRevision.value
          : this.localRevision,
      cloudRevision: data.cloudRevision.present
          ? data.cloudRevision.value
          : this.cloudRevision,
      lastAcknowledgedAtUtcMs: data.lastAcknowledgedAtUtcMs.present
          ? data.lastAcknowledgedAtUtcMs.value
          : this.lastAcknowledgedAtUtcMs,
      serverUpdatedAtUtcMs: data.serverUpdatedAtUtcMs.present
          ? data.serverUpdatedAtUtcMs.value
          : this.serverUpdatedAtUtcMs,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      createdAtUtcMs: data.createdAtUtcMs.present
          ? data.createdAtUtcMs.value
          : this.createdAtUtcMs,
      updatedAtUtcMs: data.updatedAtUtcMs.present
          ? data.updatedAtUtcMs.value
          : this.updatedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VocabularyCategory(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('name: $name, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('localRevision: $localRevision, ')
          ..write('cloudRevision: $cloudRevision, ')
          ..write('lastAcknowledgedAtUtcMs: $lastAcknowledgedAtUtcMs, ')
          ..write('serverUpdatedAtUtcMs: $serverUpdatedAtUtcMs, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAtUtcMs: $createdAtUtcMs, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    name,
    normalizedName,
    sortOrder,
    localRevision,
    cloudRevision,
    lastAcknowledgedAtUtcMs,
    serverUpdatedAtUtcMs,
    isDeleted,
    createdAtUtcMs,
    updatedAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VocabularyCategory &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.name == this.name &&
          other.normalizedName == this.normalizedName &&
          other.sortOrder == this.sortOrder &&
          other.localRevision == this.localRevision &&
          other.cloudRevision == this.cloudRevision &&
          other.lastAcknowledgedAtUtcMs == this.lastAcknowledgedAtUtcMs &&
          other.serverUpdatedAtUtcMs == this.serverUpdatedAtUtcMs &&
          other.isDeleted == this.isDeleted &&
          other.createdAtUtcMs == this.createdAtUtcMs &&
          other.updatedAtUtcMs == this.updatedAtUtcMs);
}

class VocabularyCategoriesCompanion
    extends UpdateCompanion<VocabularyCategory> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> name;
  final Value<String> normalizedName;
  final Value<int> sortOrder;
  final Value<int> localRevision;
  final Value<int> cloudRevision;
  final Value<int?> lastAcknowledgedAtUtcMs;
  final Value<int?> serverUpdatedAtUtcMs;
  final Value<bool> isDeleted;
  final Value<int> createdAtUtcMs;
  final Value<int> updatedAtUtcMs;
  final Value<int> rowid;
  const VocabularyCategoriesCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.name = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.cloudRevision = const Value.absent(),
    this.lastAcknowledgedAtUtcMs = const Value.absent(),
    this.serverUpdatedAtUtcMs = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.createdAtUtcMs = const Value.absent(),
    this.updatedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VocabularyCategoriesCompanion.insert({
    required String id,
    required String ownerId,
    required String name,
    required String normalizedName,
    this.sortOrder = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.cloudRevision = const Value.absent(),
    this.lastAcknowledgedAtUtcMs = const Value.absent(),
    this.serverUpdatedAtUtcMs = const Value.absent(),
    this.isDeleted = const Value.absent(),
    required int createdAtUtcMs,
    required int updatedAtUtcMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       name = Value(name),
       normalizedName = Value(normalizedName),
       createdAtUtcMs = Value(createdAtUtcMs),
       updatedAtUtcMs = Value(updatedAtUtcMs);
  static Insertable<VocabularyCategory> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? name,
    Expression<String>? normalizedName,
    Expression<int>? sortOrder,
    Expression<int>? localRevision,
    Expression<int>? cloudRevision,
    Expression<int>? lastAcknowledgedAtUtcMs,
    Expression<int>? serverUpdatedAtUtcMs,
    Expression<bool>? isDeleted,
    Expression<int>? createdAtUtcMs,
    Expression<int>? updatedAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (name != null) 'name': name,
      if (normalizedName != null) 'normalized_name': normalizedName,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (localRevision != null) 'local_revision': localRevision,
      if (cloudRevision != null) 'cloud_revision': cloudRevision,
      if (lastAcknowledgedAtUtcMs != null)
        'last_acknowledged_at_utc_ms': lastAcknowledgedAtUtcMs,
      if (serverUpdatedAtUtcMs != null)
        'server_updated_at_utc_ms': serverUpdatedAtUtcMs,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (createdAtUtcMs != null) 'created_at_utc_ms': createdAtUtcMs,
      if (updatedAtUtcMs != null) 'updated_at_utc_ms': updatedAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VocabularyCategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? name,
    Value<String>? normalizedName,
    Value<int>? sortOrder,
    Value<int>? localRevision,
    Value<int>? cloudRevision,
    Value<int?>? lastAcknowledgedAtUtcMs,
    Value<int?>? serverUpdatedAtUtcMs,
    Value<bool>? isDeleted,
    Value<int>? createdAtUtcMs,
    Value<int>? updatedAtUtcMs,
    Value<int>? rowid,
  }) {
    return VocabularyCategoriesCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      sortOrder: sortOrder ?? this.sortOrder,
      localRevision: localRevision ?? this.localRevision,
      cloudRevision: cloudRevision ?? this.cloudRevision,
      lastAcknowledgedAtUtcMs:
          lastAcknowledgedAtUtcMs ?? this.lastAcknowledgedAtUtcMs,
      serverUpdatedAtUtcMs: serverUpdatedAtUtcMs ?? this.serverUpdatedAtUtcMs,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
      updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (normalizedName.present) {
      map['normalized_name'] = Variable<String>(normalizedName.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (localRevision.present) {
      map['local_revision'] = Variable<int>(localRevision.value);
    }
    if (cloudRevision.present) {
      map['cloud_revision'] = Variable<int>(cloudRevision.value);
    }
    if (lastAcknowledgedAtUtcMs.present) {
      map['last_acknowledged_at_utc_ms'] = Variable<int>(
        lastAcknowledgedAtUtcMs.value,
      );
    }
    if (serverUpdatedAtUtcMs.present) {
      map['server_updated_at_utc_ms'] = Variable<int>(
        serverUpdatedAtUtcMs.value,
      );
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (createdAtUtcMs.present) {
      map['created_at_utc_ms'] = Variable<int>(createdAtUtcMs.value);
    }
    if (updatedAtUtcMs.present) {
      map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VocabularyCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('name: $name, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('localRevision: $localRevision, ')
          ..write('cloudRevision: $cloudRevision, ')
          ..write('lastAcknowledgedAtUtcMs: $lastAcknowledgedAtUtcMs, ')
          ..write('serverUpdatedAtUtcMs: $serverUpdatedAtUtcMs, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAtUtcMs: $createdAtUtcMs, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VocabularyWordsTable extends VocabularyWords
    with TableInfo<$VocabularyWordsTable, VocabularyWord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VocabularyWordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES vocabulary_categories (id)',
    ),
  );
  static const VerificationMeta _spellingMeta = const VerificationMeta(
    'spelling',
  );
  @override
  late final GeneratedColumn<String> spelling = GeneratedColumn<String>(
    'spelling',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedSpellingMeta =
      const VerificationMeta('normalizedSpelling');
  @override
  late final GeneratedColumn<String> normalizedSpelling =
      GeneratedColumn<String>(
        'normalized_spelling',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _meaningMeta = const VerificationMeta(
    'meaning',
  );
  @override
  late final GeneratedColumn<String> meaning = GeneratedColumn<String>(
    'meaning',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedMeaningMeta = const VerificationMeta(
    'normalizedMeaning',
  );
  @override
  late final GeneratedColumn<String> normalizedMeaning =
      GeneratedColumn<String>(
        'normalized_meaning',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _partOfSpeechMeta = const VerificationMeta(
    'partOfSpeech',
  );
  @override
  late final GeneratedColumn<String> partOfSpeech = GeneratedColumn<String>(
    'part_of_speech',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cefrLevelMeta = const VerificationMeta(
    'cefrLevel',
  );
  @override
  late final GeneratedColumn<String> cefrLevel = GeneratedColumn<String>(
    'cefr_level',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _isGlobalMeta = const VerificationMeta(
    'isGlobal',
  );
  @override
  late final GeneratedColumn<bool> isGlobal = GeneratedColumn<bool>(
    'is_global',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_global" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _localRevisionMeta = const VerificationMeta(
    'localRevision',
  );
  @override
  late final GeneratedColumn<int> localRevision = GeneratedColumn<int>(
    'local_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _cloudRevisionMeta = const VerificationMeta(
    'cloudRevision',
  );
  @override
  late final GeneratedColumn<int> cloudRevision = GeneratedColumn<int>(
    'cloud_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastAcknowledgedAtUtcMsMeta =
      const VerificationMeta('lastAcknowledgedAtUtcMs');
  @override
  late final GeneratedColumn<int> lastAcknowledgedAtUtcMs =
      GeneratedColumn<int>(
        'last_acknowledged_at_utc_ms',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _serverUpdatedAtUtcMsMeta =
      const VerificationMeta('serverUpdatedAtUtcMs');
  @override
  late final GeneratedColumn<int> serverUpdatedAtUtcMs = GeneratedColumn<int>(
    'server_updated_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtUtcMsMeta = const VerificationMeta(
    'createdAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> createdAtUtcMs = GeneratedColumn<int>(
    'created_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMsMeta = const VerificationMeta(
    'updatedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtcMs = GeneratedColumn<int>(
    'updated_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    categoryId,
    spelling,
    normalizedSpelling,
    meaning,
    normalizedMeaning,
    partOfSpeech,
    cefrLevel,
    source,
    isGlobal,
    localRevision,
    cloudRevision,
    lastAcknowledgedAtUtcMs,
    serverUpdatedAtUtcMs,
    isDeleted,
    createdAtUtcMs,
    updatedAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vocabulary_words';
  @override
  VerificationContext validateIntegrity(
    Insertable<VocabularyWord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('spelling')) {
      context.handle(
        _spellingMeta,
        spelling.isAcceptableOrUnknown(data['spelling']!, _spellingMeta),
      );
    } else if (isInserting) {
      context.missing(_spellingMeta);
    }
    if (data.containsKey('normalized_spelling')) {
      context.handle(
        _normalizedSpellingMeta,
        normalizedSpelling.isAcceptableOrUnknown(
          data['normalized_spelling']!,
          _normalizedSpellingMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedSpellingMeta);
    }
    if (data.containsKey('meaning')) {
      context.handle(
        _meaningMeta,
        meaning.isAcceptableOrUnknown(data['meaning']!, _meaningMeta),
      );
    } else if (isInserting) {
      context.missing(_meaningMeta);
    }
    if (data.containsKey('normalized_meaning')) {
      context.handle(
        _normalizedMeaningMeta,
        normalizedMeaning.isAcceptableOrUnknown(
          data['normalized_meaning']!,
          _normalizedMeaningMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedMeaningMeta);
    }
    if (data.containsKey('part_of_speech')) {
      context.handle(
        _partOfSpeechMeta,
        partOfSpeech.isAcceptableOrUnknown(
          data['part_of_speech']!,
          _partOfSpeechMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_partOfSpeechMeta);
    }
    if (data.containsKey('cefr_level')) {
      context.handle(
        _cefrLevelMeta,
        cefrLevel.isAcceptableOrUnknown(data['cefr_level']!, _cefrLevelMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('is_global')) {
      context.handle(
        _isGlobalMeta,
        isGlobal.isAcceptableOrUnknown(data['is_global']!, _isGlobalMeta),
      );
    }
    if (data.containsKey('local_revision')) {
      context.handle(
        _localRevisionMeta,
        localRevision.isAcceptableOrUnknown(
          data['local_revision']!,
          _localRevisionMeta,
        ),
      );
    }
    if (data.containsKey('cloud_revision')) {
      context.handle(
        _cloudRevisionMeta,
        cloudRevision.isAcceptableOrUnknown(
          data['cloud_revision']!,
          _cloudRevisionMeta,
        ),
      );
    }
    if (data.containsKey('last_acknowledged_at_utc_ms')) {
      context.handle(
        _lastAcknowledgedAtUtcMsMeta,
        lastAcknowledgedAtUtcMs.isAcceptableOrUnknown(
          data['last_acknowledged_at_utc_ms']!,
          _lastAcknowledgedAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('server_updated_at_utc_ms')) {
      context.handle(
        _serverUpdatedAtUtcMsMeta,
        serverUpdatedAtUtcMs.isAcceptableOrUnknown(
          data['server_updated_at_utc_ms']!,
          _serverUpdatedAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('created_at_utc_ms')) {
      context.handle(
        _createdAtUtcMsMeta,
        createdAtUtcMs.isAcceptableOrUnknown(
          data['created_at_utc_ms']!,
          _createdAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMsMeta);
    }
    if (data.containsKey('updated_at_utc_ms')) {
      context.handle(
        _updatedAtUtcMsMeta,
        updatedAtUtcMs.isAcceptableOrUnknown(
          data['updated_at_utc_ms']!,
          _updatedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerId, categoryId, normalizedSpelling, normalizedMeaning},
  ];
  @override
  VocabularyWord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VocabularyWord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      spelling: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}spelling'],
      )!,
      normalizedSpelling: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_spelling'],
      )!,
      meaning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meaning'],
      )!,
      normalizedMeaning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_meaning'],
      )!,
      partOfSpeech: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}part_of_speech'],
      )!,
      cefrLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cefr_level'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      isGlobal: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_global'],
      )!,
      localRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_revision'],
      )!,
      cloudRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cloud_revision'],
      )!,
      lastAcknowledgedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_acknowledged_at_utc_ms'],
      ),
      serverUpdatedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_updated_at_utc_ms'],
      ),
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      createdAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc_ms'],
      )!,
      updatedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc_ms'],
      )!,
    );
  }

  @override
  $VocabularyWordsTable createAlias(String alias) {
    return $VocabularyWordsTable(attachedDatabase, alias);
  }
}

class VocabularyWord extends DataClass implements Insertable<VocabularyWord> {
  final String id;
  final String ownerId;
  final String categoryId;
  final String spelling;
  final String normalizedSpelling;
  final String meaning;
  final String normalizedMeaning;
  final String partOfSpeech;
  final String? cefrLevel;
  final String source;
  final bool isGlobal;
  final int localRevision;
  final int cloudRevision;
  final int? lastAcknowledgedAtUtcMs;
  final int? serverUpdatedAtUtcMs;
  final bool isDeleted;
  final int createdAtUtcMs;
  final int updatedAtUtcMs;
  const VocabularyWord({
    required this.id,
    required this.ownerId,
    required this.categoryId,
    required this.spelling,
    required this.normalizedSpelling,
    required this.meaning,
    required this.normalizedMeaning,
    required this.partOfSpeech,
    this.cefrLevel,
    required this.source,
    required this.isGlobal,
    required this.localRevision,
    required this.cloudRevision,
    this.lastAcknowledgedAtUtcMs,
    this.serverUpdatedAtUtcMs,
    required this.isDeleted,
    required this.createdAtUtcMs,
    required this.updatedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['category_id'] = Variable<String>(categoryId);
    map['spelling'] = Variable<String>(spelling);
    map['normalized_spelling'] = Variable<String>(normalizedSpelling);
    map['meaning'] = Variable<String>(meaning);
    map['normalized_meaning'] = Variable<String>(normalizedMeaning);
    map['part_of_speech'] = Variable<String>(partOfSpeech);
    if (!nullToAbsent || cefrLevel != null) {
      map['cefr_level'] = Variable<String>(cefrLevel);
    }
    map['source'] = Variable<String>(source);
    map['is_global'] = Variable<bool>(isGlobal);
    map['local_revision'] = Variable<int>(localRevision);
    map['cloud_revision'] = Variable<int>(cloudRevision);
    if (!nullToAbsent || lastAcknowledgedAtUtcMs != null) {
      map['last_acknowledged_at_utc_ms'] = Variable<int>(
        lastAcknowledgedAtUtcMs,
      );
    }
    if (!nullToAbsent || serverUpdatedAtUtcMs != null) {
      map['server_updated_at_utc_ms'] = Variable<int>(serverUpdatedAtUtcMs);
    }
    map['is_deleted'] = Variable<bool>(isDeleted);
    map['created_at_utc_ms'] = Variable<int>(createdAtUtcMs);
    map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs);
    return map;
  }

  VocabularyWordsCompanion toCompanion(bool nullToAbsent) {
    return VocabularyWordsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      categoryId: Value(categoryId),
      spelling: Value(spelling),
      normalizedSpelling: Value(normalizedSpelling),
      meaning: Value(meaning),
      normalizedMeaning: Value(normalizedMeaning),
      partOfSpeech: Value(partOfSpeech),
      cefrLevel: cefrLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(cefrLevel),
      source: Value(source),
      isGlobal: Value(isGlobal),
      localRevision: Value(localRevision),
      cloudRevision: Value(cloudRevision),
      lastAcknowledgedAtUtcMs: lastAcknowledgedAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAcknowledgedAtUtcMs),
      serverUpdatedAtUtcMs: serverUpdatedAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAtUtcMs),
      isDeleted: Value(isDeleted),
      createdAtUtcMs: Value(createdAtUtcMs),
      updatedAtUtcMs: Value(updatedAtUtcMs),
    );
  }

  factory VocabularyWord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VocabularyWord(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      spelling: serializer.fromJson<String>(json['spelling']),
      normalizedSpelling: serializer.fromJson<String>(
        json['normalizedSpelling'],
      ),
      meaning: serializer.fromJson<String>(json['meaning']),
      normalizedMeaning: serializer.fromJson<String>(json['normalizedMeaning']),
      partOfSpeech: serializer.fromJson<String>(json['partOfSpeech']),
      cefrLevel: serializer.fromJson<String?>(json['cefrLevel']),
      source: serializer.fromJson<String>(json['source']),
      isGlobal: serializer.fromJson<bool>(json['isGlobal']),
      localRevision: serializer.fromJson<int>(json['localRevision']),
      cloudRevision: serializer.fromJson<int>(json['cloudRevision']),
      lastAcknowledgedAtUtcMs: serializer.fromJson<int?>(
        json['lastAcknowledgedAtUtcMs'],
      ),
      serverUpdatedAtUtcMs: serializer.fromJson<int?>(
        json['serverUpdatedAtUtcMs'],
      ),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      createdAtUtcMs: serializer.fromJson<int>(json['createdAtUtcMs']),
      updatedAtUtcMs: serializer.fromJson<int>(json['updatedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'categoryId': serializer.toJson<String>(categoryId),
      'spelling': serializer.toJson<String>(spelling),
      'normalizedSpelling': serializer.toJson<String>(normalizedSpelling),
      'meaning': serializer.toJson<String>(meaning),
      'normalizedMeaning': serializer.toJson<String>(normalizedMeaning),
      'partOfSpeech': serializer.toJson<String>(partOfSpeech),
      'cefrLevel': serializer.toJson<String?>(cefrLevel),
      'source': serializer.toJson<String>(source),
      'isGlobal': serializer.toJson<bool>(isGlobal),
      'localRevision': serializer.toJson<int>(localRevision),
      'cloudRevision': serializer.toJson<int>(cloudRevision),
      'lastAcknowledgedAtUtcMs': serializer.toJson<int?>(
        lastAcknowledgedAtUtcMs,
      ),
      'serverUpdatedAtUtcMs': serializer.toJson<int?>(serverUpdatedAtUtcMs),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'createdAtUtcMs': serializer.toJson<int>(createdAtUtcMs),
      'updatedAtUtcMs': serializer.toJson<int>(updatedAtUtcMs),
    };
  }

  VocabularyWord copyWith({
    String? id,
    String? ownerId,
    String? categoryId,
    String? spelling,
    String? normalizedSpelling,
    String? meaning,
    String? normalizedMeaning,
    String? partOfSpeech,
    Value<String?> cefrLevel = const Value.absent(),
    String? source,
    bool? isGlobal,
    int? localRevision,
    int? cloudRevision,
    Value<int?> lastAcknowledgedAtUtcMs = const Value.absent(),
    Value<int?> serverUpdatedAtUtcMs = const Value.absent(),
    bool? isDeleted,
    int? createdAtUtcMs,
    int? updatedAtUtcMs,
  }) => VocabularyWord(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    categoryId: categoryId ?? this.categoryId,
    spelling: spelling ?? this.spelling,
    normalizedSpelling: normalizedSpelling ?? this.normalizedSpelling,
    meaning: meaning ?? this.meaning,
    normalizedMeaning: normalizedMeaning ?? this.normalizedMeaning,
    partOfSpeech: partOfSpeech ?? this.partOfSpeech,
    cefrLevel: cefrLevel.present ? cefrLevel.value : this.cefrLevel,
    source: source ?? this.source,
    isGlobal: isGlobal ?? this.isGlobal,
    localRevision: localRevision ?? this.localRevision,
    cloudRevision: cloudRevision ?? this.cloudRevision,
    lastAcknowledgedAtUtcMs: lastAcknowledgedAtUtcMs.present
        ? lastAcknowledgedAtUtcMs.value
        : this.lastAcknowledgedAtUtcMs,
    serverUpdatedAtUtcMs: serverUpdatedAtUtcMs.present
        ? serverUpdatedAtUtcMs.value
        : this.serverUpdatedAtUtcMs,
    isDeleted: isDeleted ?? this.isDeleted,
    createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
    updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
  );
  VocabularyWord copyWithCompanion(VocabularyWordsCompanion data) {
    return VocabularyWord(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      spelling: data.spelling.present ? data.spelling.value : this.spelling,
      normalizedSpelling: data.normalizedSpelling.present
          ? data.normalizedSpelling.value
          : this.normalizedSpelling,
      meaning: data.meaning.present ? data.meaning.value : this.meaning,
      normalizedMeaning: data.normalizedMeaning.present
          ? data.normalizedMeaning.value
          : this.normalizedMeaning,
      partOfSpeech: data.partOfSpeech.present
          ? data.partOfSpeech.value
          : this.partOfSpeech,
      cefrLevel: data.cefrLevel.present ? data.cefrLevel.value : this.cefrLevel,
      source: data.source.present ? data.source.value : this.source,
      isGlobal: data.isGlobal.present ? data.isGlobal.value : this.isGlobal,
      localRevision: data.localRevision.present
          ? data.localRevision.value
          : this.localRevision,
      cloudRevision: data.cloudRevision.present
          ? data.cloudRevision.value
          : this.cloudRevision,
      lastAcknowledgedAtUtcMs: data.lastAcknowledgedAtUtcMs.present
          ? data.lastAcknowledgedAtUtcMs.value
          : this.lastAcknowledgedAtUtcMs,
      serverUpdatedAtUtcMs: data.serverUpdatedAtUtcMs.present
          ? data.serverUpdatedAtUtcMs.value
          : this.serverUpdatedAtUtcMs,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      createdAtUtcMs: data.createdAtUtcMs.present
          ? data.createdAtUtcMs.value
          : this.createdAtUtcMs,
      updatedAtUtcMs: data.updatedAtUtcMs.present
          ? data.updatedAtUtcMs.value
          : this.updatedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VocabularyWord(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('categoryId: $categoryId, ')
          ..write('spelling: $spelling, ')
          ..write('normalizedSpelling: $normalizedSpelling, ')
          ..write('meaning: $meaning, ')
          ..write('normalizedMeaning: $normalizedMeaning, ')
          ..write('partOfSpeech: $partOfSpeech, ')
          ..write('cefrLevel: $cefrLevel, ')
          ..write('source: $source, ')
          ..write('isGlobal: $isGlobal, ')
          ..write('localRevision: $localRevision, ')
          ..write('cloudRevision: $cloudRevision, ')
          ..write('lastAcknowledgedAtUtcMs: $lastAcknowledgedAtUtcMs, ')
          ..write('serverUpdatedAtUtcMs: $serverUpdatedAtUtcMs, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAtUtcMs: $createdAtUtcMs, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    categoryId,
    spelling,
    normalizedSpelling,
    meaning,
    normalizedMeaning,
    partOfSpeech,
    cefrLevel,
    source,
    isGlobal,
    localRevision,
    cloudRevision,
    lastAcknowledgedAtUtcMs,
    serverUpdatedAtUtcMs,
    isDeleted,
    createdAtUtcMs,
    updatedAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VocabularyWord &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.categoryId == this.categoryId &&
          other.spelling == this.spelling &&
          other.normalizedSpelling == this.normalizedSpelling &&
          other.meaning == this.meaning &&
          other.normalizedMeaning == this.normalizedMeaning &&
          other.partOfSpeech == this.partOfSpeech &&
          other.cefrLevel == this.cefrLevel &&
          other.source == this.source &&
          other.isGlobal == this.isGlobal &&
          other.localRevision == this.localRevision &&
          other.cloudRevision == this.cloudRevision &&
          other.lastAcknowledgedAtUtcMs == this.lastAcknowledgedAtUtcMs &&
          other.serverUpdatedAtUtcMs == this.serverUpdatedAtUtcMs &&
          other.isDeleted == this.isDeleted &&
          other.createdAtUtcMs == this.createdAtUtcMs &&
          other.updatedAtUtcMs == this.updatedAtUtcMs);
}

class VocabularyWordsCompanion extends UpdateCompanion<VocabularyWord> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> categoryId;
  final Value<String> spelling;
  final Value<String> normalizedSpelling;
  final Value<String> meaning;
  final Value<String> normalizedMeaning;
  final Value<String> partOfSpeech;
  final Value<String?> cefrLevel;
  final Value<String> source;
  final Value<bool> isGlobal;
  final Value<int> localRevision;
  final Value<int> cloudRevision;
  final Value<int?> lastAcknowledgedAtUtcMs;
  final Value<int?> serverUpdatedAtUtcMs;
  final Value<bool> isDeleted;
  final Value<int> createdAtUtcMs;
  final Value<int> updatedAtUtcMs;
  final Value<int> rowid;
  const VocabularyWordsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.spelling = const Value.absent(),
    this.normalizedSpelling = const Value.absent(),
    this.meaning = const Value.absent(),
    this.normalizedMeaning = const Value.absent(),
    this.partOfSpeech = const Value.absent(),
    this.cefrLevel = const Value.absent(),
    this.source = const Value.absent(),
    this.isGlobal = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.cloudRevision = const Value.absent(),
    this.lastAcknowledgedAtUtcMs = const Value.absent(),
    this.serverUpdatedAtUtcMs = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.createdAtUtcMs = const Value.absent(),
    this.updatedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VocabularyWordsCompanion.insert({
    required String id,
    required String ownerId,
    required String categoryId,
    required String spelling,
    required String normalizedSpelling,
    required String meaning,
    required String normalizedMeaning,
    required String partOfSpeech,
    this.cefrLevel = const Value.absent(),
    this.source = const Value.absent(),
    this.isGlobal = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.cloudRevision = const Value.absent(),
    this.lastAcknowledgedAtUtcMs = const Value.absent(),
    this.serverUpdatedAtUtcMs = const Value.absent(),
    this.isDeleted = const Value.absent(),
    required int createdAtUtcMs,
    required int updatedAtUtcMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       categoryId = Value(categoryId),
       spelling = Value(spelling),
       normalizedSpelling = Value(normalizedSpelling),
       meaning = Value(meaning),
       normalizedMeaning = Value(normalizedMeaning),
       partOfSpeech = Value(partOfSpeech),
       createdAtUtcMs = Value(createdAtUtcMs),
       updatedAtUtcMs = Value(updatedAtUtcMs);
  static Insertable<VocabularyWord> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? categoryId,
    Expression<String>? spelling,
    Expression<String>? normalizedSpelling,
    Expression<String>? meaning,
    Expression<String>? normalizedMeaning,
    Expression<String>? partOfSpeech,
    Expression<String>? cefrLevel,
    Expression<String>? source,
    Expression<bool>? isGlobal,
    Expression<int>? localRevision,
    Expression<int>? cloudRevision,
    Expression<int>? lastAcknowledgedAtUtcMs,
    Expression<int>? serverUpdatedAtUtcMs,
    Expression<bool>? isDeleted,
    Expression<int>? createdAtUtcMs,
    Expression<int>? updatedAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (categoryId != null) 'category_id': categoryId,
      if (spelling != null) 'spelling': spelling,
      if (normalizedSpelling != null) 'normalized_spelling': normalizedSpelling,
      if (meaning != null) 'meaning': meaning,
      if (normalizedMeaning != null) 'normalized_meaning': normalizedMeaning,
      if (partOfSpeech != null) 'part_of_speech': partOfSpeech,
      if (cefrLevel != null) 'cefr_level': cefrLevel,
      if (source != null) 'source': source,
      if (isGlobal != null) 'is_global': isGlobal,
      if (localRevision != null) 'local_revision': localRevision,
      if (cloudRevision != null) 'cloud_revision': cloudRevision,
      if (lastAcknowledgedAtUtcMs != null)
        'last_acknowledged_at_utc_ms': lastAcknowledgedAtUtcMs,
      if (serverUpdatedAtUtcMs != null)
        'server_updated_at_utc_ms': serverUpdatedAtUtcMs,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (createdAtUtcMs != null) 'created_at_utc_ms': createdAtUtcMs,
      if (updatedAtUtcMs != null) 'updated_at_utc_ms': updatedAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VocabularyWordsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? categoryId,
    Value<String>? spelling,
    Value<String>? normalizedSpelling,
    Value<String>? meaning,
    Value<String>? normalizedMeaning,
    Value<String>? partOfSpeech,
    Value<String?>? cefrLevel,
    Value<String>? source,
    Value<bool>? isGlobal,
    Value<int>? localRevision,
    Value<int>? cloudRevision,
    Value<int?>? lastAcknowledgedAtUtcMs,
    Value<int?>? serverUpdatedAtUtcMs,
    Value<bool>? isDeleted,
    Value<int>? createdAtUtcMs,
    Value<int>? updatedAtUtcMs,
    Value<int>? rowid,
  }) {
    return VocabularyWordsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      categoryId: categoryId ?? this.categoryId,
      spelling: spelling ?? this.spelling,
      normalizedSpelling: normalizedSpelling ?? this.normalizedSpelling,
      meaning: meaning ?? this.meaning,
      normalizedMeaning: normalizedMeaning ?? this.normalizedMeaning,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      cefrLevel: cefrLevel ?? this.cefrLevel,
      source: source ?? this.source,
      isGlobal: isGlobal ?? this.isGlobal,
      localRevision: localRevision ?? this.localRevision,
      cloudRevision: cloudRevision ?? this.cloudRevision,
      lastAcknowledgedAtUtcMs:
          lastAcknowledgedAtUtcMs ?? this.lastAcknowledgedAtUtcMs,
      serverUpdatedAtUtcMs: serverUpdatedAtUtcMs ?? this.serverUpdatedAtUtcMs,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
      updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (spelling.present) {
      map['spelling'] = Variable<String>(spelling.value);
    }
    if (normalizedSpelling.present) {
      map['normalized_spelling'] = Variable<String>(normalizedSpelling.value);
    }
    if (meaning.present) {
      map['meaning'] = Variable<String>(meaning.value);
    }
    if (normalizedMeaning.present) {
      map['normalized_meaning'] = Variable<String>(normalizedMeaning.value);
    }
    if (partOfSpeech.present) {
      map['part_of_speech'] = Variable<String>(partOfSpeech.value);
    }
    if (cefrLevel.present) {
      map['cefr_level'] = Variable<String>(cefrLevel.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (isGlobal.present) {
      map['is_global'] = Variable<bool>(isGlobal.value);
    }
    if (localRevision.present) {
      map['local_revision'] = Variable<int>(localRevision.value);
    }
    if (cloudRevision.present) {
      map['cloud_revision'] = Variable<int>(cloudRevision.value);
    }
    if (lastAcknowledgedAtUtcMs.present) {
      map['last_acknowledged_at_utc_ms'] = Variable<int>(
        lastAcknowledgedAtUtcMs.value,
      );
    }
    if (serverUpdatedAtUtcMs.present) {
      map['server_updated_at_utc_ms'] = Variable<int>(
        serverUpdatedAtUtcMs.value,
      );
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (createdAtUtcMs.present) {
      map['created_at_utc_ms'] = Variable<int>(createdAtUtcMs.value);
    }
    if (updatedAtUtcMs.present) {
      map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VocabularyWordsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('categoryId: $categoryId, ')
          ..write('spelling: $spelling, ')
          ..write('normalizedSpelling: $normalizedSpelling, ')
          ..write('meaning: $meaning, ')
          ..write('normalizedMeaning: $normalizedMeaning, ')
          ..write('partOfSpeech: $partOfSpeech, ')
          ..write('cefrLevel: $cefrLevel, ')
          ..write('source: $source, ')
          ..write('isGlobal: $isGlobal, ')
          ..write('localRevision: $localRevision, ')
          ..write('cloudRevision: $cloudRevision, ')
          ..write('lastAcknowledgedAtUtcMs: $lastAcknowledgedAtUtcMs, ')
          ..write('serverUpdatedAtUtcMs: $serverUpdatedAtUtcMs, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAtUtcMs: $createdAtUtcMs, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VocabularyImportsTable extends VocabularyImports
    with TableInfo<$VocabularyImportsTable, VocabularyImport> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VocabularyImportsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES vocabulary_categories (id)',
    ),
  );
  static const VerificationMeta _sourceTypeMeta = const VerificationMeta(
    'sourceType',
  );
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
    'source_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceNameMeta = const VerificationMeta(
    'sourceName',
  );
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
    'source_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceHashMeta = const VerificationMeta(
    'sourceHash',
  );
  @override
  late final GeneratedColumn<String> sourceHash = GeneratedColumn<String>(
    'source_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acceptedCountMeta = const VerificationMeta(
    'acceptedCount',
  );
  @override
  late final GeneratedColumn<int> acceptedCount = GeneratedColumn<int>(
    'accepted_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _duplicateCountMeta = const VerificationMeta(
    'duplicateCount',
  );
  @override
  late final GeneratedColumn<int> duplicateCount = GeneratedColumn<int>(
    'duplicate_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _rejectedCountMeta = const VerificationMeta(
    'rejectedCount',
  );
  @override
  late final GeneratedColumn<int> rejectedCount = GeneratedColumn<int>(
    'rejected_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtUtcMsMeta = const VerificationMeta(
    'createdAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> createdAtUtcMs = GeneratedColumn<int>(
    'created_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtUtcMsMeta = const VerificationMeta(
    'completedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> completedAtUtcMs = GeneratedColumn<int>(
    'completed_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    categoryId,
    sourceType,
    sourceName,
    sourceHash,
    status,
    acceptedCount,
    duplicateCount,
    rejectedCount,
    createdAtUtcMs,
    completedAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vocabulary_imports';
  @override
  VerificationContext validateIntegrity(
    Insertable<VocabularyImport> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('source_type')) {
      context.handle(
        _sourceTypeMeta,
        sourceType.isAcceptableOrUnknown(data['source_type']!, _sourceTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceTypeMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
        _sourceNameMeta,
        sourceName.isAcceptableOrUnknown(data['source_name']!, _sourceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceNameMeta);
    }
    if (data.containsKey('source_hash')) {
      context.handle(
        _sourceHashMeta,
        sourceHash.isAcceptableOrUnknown(data['source_hash']!, _sourceHashMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceHashMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('accepted_count')) {
      context.handle(
        _acceptedCountMeta,
        acceptedCount.isAcceptableOrUnknown(
          data['accepted_count']!,
          _acceptedCountMeta,
        ),
      );
    }
    if (data.containsKey('duplicate_count')) {
      context.handle(
        _duplicateCountMeta,
        duplicateCount.isAcceptableOrUnknown(
          data['duplicate_count']!,
          _duplicateCountMeta,
        ),
      );
    }
    if (data.containsKey('rejected_count')) {
      context.handle(
        _rejectedCountMeta,
        rejectedCount.isAcceptableOrUnknown(
          data['rejected_count']!,
          _rejectedCountMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc_ms')) {
      context.handle(
        _createdAtUtcMsMeta,
        createdAtUtcMs.isAcceptableOrUnknown(
          data['created_at_utc_ms']!,
          _createdAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMsMeta);
    }
    if (data.containsKey('completed_at_utc_ms')) {
      context.handle(
        _completedAtUtcMsMeta,
        completedAtUtcMs.isAcceptableOrUnknown(
          data['completed_at_utc_ms']!,
          _completedAtUtcMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerId, categoryId, sourceHash},
  ];
  @override
  VocabularyImport map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VocabularyImport(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      sourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_type'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      )!,
      sourceHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_hash'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      acceptedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accepted_count'],
      )!,
      duplicateCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duplicate_count'],
      )!,
      rejectedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rejected_count'],
      )!,
      createdAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc_ms'],
      )!,
      completedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at_utc_ms'],
      ),
    );
  }

  @override
  $VocabularyImportsTable createAlias(String alias) {
    return $VocabularyImportsTable(attachedDatabase, alias);
  }
}

class VocabularyImport extends DataClass
    implements Insertable<VocabularyImport> {
  final String id;
  final String ownerId;
  final String categoryId;
  final String sourceType;
  final String sourceName;
  final String sourceHash;
  final String status;
  final int acceptedCount;
  final int duplicateCount;
  final int rejectedCount;
  final int createdAtUtcMs;
  final int? completedAtUtcMs;
  const VocabularyImport({
    required this.id,
    required this.ownerId,
    required this.categoryId,
    required this.sourceType,
    required this.sourceName,
    required this.sourceHash,
    required this.status,
    required this.acceptedCount,
    required this.duplicateCount,
    required this.rejectedCount,
    required this.createdAtUtcMs,
    this.completedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['category_id'] = Variable<String>(categoryId);
    map['source_type'] = Variable<String>(sourceType);
    map['source_name'] = Variable<String>(sourceName);
    map['source_hash'] = Variable<String>(sourceHash);
    map['status'] = Variable<String>(status);
    map['accepted_count'] = Variable<int>(acceptedCount);
    map['duplicate_count'] = Variable<int>(duplicateCount);
    map['rejected_count'] = Variable<int>(rejectedCount);
    map['created_at_utc_ms'] = Variable<int>(createdAtUtcMs);
    if (!nullToAbsent || completedAtUtcMs != null) {
      map['completed_at_utc_ms'] = Variable<int>(completedAtUtcMs);
    }
    return map;
  }

  VocabularyImportsCompanion toCompanion(bool nullToAbsent) {
    return VocabularyImportsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      categoryId: Value(categoryId),
      sourceType: Value(sourceType),
      sourceName: Value(sourceName),
      sourceHash: Value(sourceHash),
      status: Value(status),
      acceptedCount: Value(acceptedCount),
      duplicateCount: Value(duplicateCount),
      rejectedCount: Value(rejectedCount),
      createdAtUtcMs: Value(createdAtUtcMs),
      completedAtUtcMs: completedAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtUtcMs),
    );
  }

  factory VocabularyImport.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VocabularyImport(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      sourceType: serializer.fromJson<String>(json['sourceType']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      sourceHash: serializer.fromJson<String>(json['sourceHash']),
      status: serializer.fromJson<String>(json['status']),
      acceptedCount: serializer.fromJson<int>(json['acceptedCount']),
      duplicateCount: serializer.fromJson<int>(json['duplicateCount']),
      rejectedCount: serializer.fromJson<int>(json['rejectedCount']),
      createdAtUtcMs: serializer.fromJson<int>(json['createdAtUtcMs']),
      completedAtUtcMs: serializer.fromJson<int?>(json['completedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'categoryId': serializer.toJson<String>(categoryId),
      'sourceType': serializer.toJson<String>(sourceType),
      'sourceName': serializer.toJson<String>(sourceName),
      'sourceHash': serializer.toJson<String>(sourceHash),
      'status': serializer.toJson<String>(status),
      'acceptedCount': serializer.toJson<int>(acceptedCount),
      'duplicateCount': serializer.toJson<int>(duplicateCount),
      'rejectedCount': serializer.toJson<int>(rejectedCount),
      'createdAtUtcMs': serializer.toJson<int>(createdAtUtcMs),
      'completedAtUtcMs': serializer.toJson<int?>(completedAtUtcMs),
    };
  }

  VocabularyImport copyWith({
    String? id,
    String? ownerId,
    String? categoryId,
    String? sourceType,
    String? sourceName,
    String? sourceHash,
    String? status,
    int? acceptedCount,
    int? duplicateCount,
    int? rejectedCount,
    int? createdAtUtcMs,
    Value<int?> completedAtUtcMs = const Value.absent(),
  }) => VocabularyImport(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    categoryId: categoryId ?? this.categoryId,
    sourceType: sourceType ?? this.sourceType,
    sourceName: sourceName ?? this.sourceName,
    sourceHash: sourceHash ?? this.sourceHash,
    status: status ?? this.status,
    acceptedCount: acceptedCount ?? this.acceptedCount,
    duplicateCount: duplicateCount ?? this.duplicateCount,
    rejectedCount: rejectedCount ?? this.rejectedCount,
    createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
    completedAtUtcMs: completedAtUtcMs.present
        ? completedAtUtcMs.value
        : this.completedAtUtcMs,
  );
  VocabularyImport copyWithCompanion(VocabularyImportsCompanion data) {
    return VocabularyImport(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      sourceType: data.sourceType.present
          ? data.sourceType.value
          : this.sourceType,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      sourceHash: data.sourceHash.present
          ? data.sourceHash.value
          : this.sourceHash,
      status: data.status.present ? data.status.value : this.status,
      acceptedCount: data.acceptedCount.present
          ? data.acceptedCount.value
          : this.acceptedCount,
      duplicateCount: data.duplicateCount.present
          ? data.duplicateCount.value
          : this.duplicateCount,
      rejectedCount: data.rejectedCount.present
          ? data.rejectedCount.value
          : this.rejectedCount,
      createdAtUtcMs: data.createdAtUtcMs.present
          ? data.createdAtUtcMs.value
          : this.createdAtUtcMs,
      completedAtUtcMs: data.completedAtUtcMs.present
          ? data.completedAtUtcMs.value
          : this.completedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VocabularyImport(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('categoryId: $categoryId, ')
          ..write('sourceType: $sourceType, ')
          ..write('sourceName: $sourceName, ')
          ..write('sourceHash: $sourceHash, ')
          ..write('status: $status, ')
          ..write('acceptedCount: $acceptedCount, ')
          ..write('duplicateCount: $duplicateCount, ')
          ..write('rejectedCount: $rejectedCount, ')
          ..write('createdAtUtcMs: $createdAtUtcMs, ')
          ..write('completedAtUtcMs: $completedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    categoryId,
    sourceType,
    sourceName,
    sourceHash,
    status,
    acceptedCount,
    duplicateCount,
    rejectedCount,
    createdAtUtcMs,
    completedAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VocabularyImport &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.categoryId == this.categoryId &&
          other.sourceType == this.sourceType &&
          other.sourceName == this.sourceName &&
          other.sourceHash == this.sourceHash &&
          other.status == this.status &&
          other.acceptedCount == this.acceptedCount &&
          other.duplicateCount == this.duplicateCount &&
          other.rejectedCount == this.rejectedCount &&
          other.createdAtUtcMs == this.createdAtUtcMs &&
          other.completedAtUtcMs == this.completedAtUtcMs);
}

class VocabularyImportsCompanion extends UpdateCompanion<VocabularyImport> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> categoryId;
  final Value<String> sourceType;
  final Value<String> sourceName;
  final Value<String> sourceHash;
  final Value<String> status;
  final Value<int> acceptedCount;
  final Value<int> duplicateCount;
  final Value<int> rejectedCount;
  final Value<int> createdAtUtcMs;
  final Value<int?> completedAtUtcMs;
  final Value<int> rowid;
  const VocabularyImportsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.sourceHash = const Value.absent(),
    this.status = const Value.absent(),
    this.acceptedCount = const Value.absent(),
    this.duplicateCount = const Value.absent(),
    this.rejectedCount = const Value.absent(),
    this.createdAtUtcMs = const Value.absent(),
    this.completedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VocabularyImportsCompanion.insert({
    required String id,
    required String ownerId,
    required String categoryId,
    required String sourceType,
    required String sourceName,
    required String sourceHash,
    required String status,
    this.acceptedCount = const Value.absent(),
    this.duplicateCount = const Value.absent(),
    this.rejectedCount = const Value.absent(),
    required int createdAtUtcMs,
    this.completedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       categoryId = Value(categoryId),
       sourceType = Value(sourceType),
       sourceName = Value(sourceName),
       sourceHash = Value(sourceHash),
       status = Value(status),
       createdAtUtcMs = Value(createdAtUtcMs);
  static Insertable<VocabularyImport> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? categoryId,
    Expression<String>? sourceType,
    Expression<String>? sourceName,
    Expression<String>? sourceHash,
    Expression<String>? status,
    Expression<int>? acceptedCount,
    Expression<int>? duplicateCount,
    Expression<int>? rejectedCount,
    Expression<int>? createdAtUtcMs,
    Expression<int>? completedAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (categoryId != null) 'category_id': categoryId,
      if (sourceType != null) 'source_type': sourceType,
      if (sourceName != null) 'source_name': sourceName,
      if (sourceHash != null) 'source_hash': sourceHash,
      if (status != null) 'status': status,
      if (acceptedCount != null) 'accepted_count': acceptedCount,
      if (duplicateCount != null) 'duplicate_count': duplicateCount,
      if (rejectedCount != null) 'rejected_count': rejectedCount,
      if (createdAtUtcMs != null) 'created_at_utc_ms': createdAtUtcMs,
      if (completedAtUtcMs != null) 'completed_at_utc_ms': completedAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VocabularyImportsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? categoryId,
    Value<String>? sourceType,
    Value<String>? sourceName,
    Value<String>? sourceHash,
    Value<String>? status,
    Value<int>? acceptedCount,
    Value<int>? duplicateCount,
    Value<int>? rejectedCount,
    Value<int>? createdAtUtcMs,
    Value<int?>? completedAtUtcMs,
    Value<int>? rowid,
  }) {
    return VocabularyImportsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      categoryId: categoryId ?? this.categoryId,
      sourceType: sourceType ?? this.sourceType,
      sourceName: sourceName ?? this.sourceName,
      sourceHash: sourceHash ?? this.sourceHash,
      status: status ?? this.status,
      acceptedCount: acceptedCount ?? this.acceptedCount,
      duplicateCount: duplicateCount ?? this.duplicateCount,
      rejectedCount: rejectedCount ?? this.rejectedCount,
      createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
      completedAtUtcMs: completedAtUtcMs ?? this.completedAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (sourceHash.present) {
      map['source_hash'] = Variable<String>(sourceHash.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (acceptedCount.present) {
      map['accepted_count'] = Variable<int>(acceptedCount.value);
    }
    if (duplicateCount.present) {
      map['duplicate_count'] = Variable<int>(duplicateCount.value);
    }
    if (rejectedCount.present) {
      map['rejected_count'] = Variable<int>(rejectedCount.value);
    }
    if (createdAtUtcMs.present) {
      map['created_at_utc_ms'] = Variable<int>(createdAtUtcMs.value);
    }
    if (completedAtUtcMs.present) {
      map['completed_at_utc_ms'] = Variable<int>(completedAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VocabularyImportsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('categoryId: $categoryId, ')
          ..write('sourceType: $sourceType, ')
          ..write('sourceName: $sourceName, ')
          ..write('sourceHash: $sourceHash, ')
          ..write('status: $status, ')
          ..write('acceptedCount: $acceptedCount, ')
          ..write('duplicateCount: $duplicateCount, ')
          ..write('rejectedCount: $rejectedCount, ')
          ..write('createdAtUtcMs: $createdAtUtcMs, ')
          ..write('completedAtUtcMs: $completedAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VocabularyImportRowsTable extends VocabularyImportRows
    with TableInfo<$VocabularyImportRowsTable, VocabularyImportRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VocabularyImportRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importIdMeta = const VerificationMeta(
    'importId',
  );
  @override
  late final GeneratedColumn<String> importId = GeneratedColumn<String>(
    'import_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES vocabulary_imports (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _rowNumberMeta = const VerificationMeta(
    'rowNumber',
  );
  @override
  late final GeneratedColumn<int> rowNumber = GeneratedColumn<int>(
    'row_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadHashMeta = const VerificationMeta(
    'payloadHash',
  );
  @override
  late final GeneratedColumn<String> payloadHash = GeneratedColumn<String>(
    'payload_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _failureCodeMeta = const VerificationMeta(
    'failureCode',
  );
  @override
  late final GeneratedColumn<String> failureCode = GeneratedColumn<String>(
    'failure_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<String> wordId = GeneratedColumn<String>(
    'word_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    importId,
    rowNumber,
    payloadHash,
    status,
    failureCode,
    wordId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vocabulary_import_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<VocabularyImportRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('import_id')) {
      context.handle(
        _importIdMeta,
        importId.isAcceptableOrUnknown(data['import_id']!, _importIdMeta),
      );
    } else if (isInserting) {
      context.missing(_importIdMeta);
    }
    if (data.containsKey('row_number')) {
      context.handle(
        _rowNumberMeta,
        rowNumber.isAcceptableOrUnknown(data['row_number']!, _rowNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_rowNumberMeta);
    }
    if (data.containsKey('payload_hash')) {
      context.handle(
        _payloadHashMeta,
        payloadHash.isAcceptableOrUnknown(
          data['payload_hash']!,
          _payloadHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadHashMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('failure_code')) {
      context.handle(
        _failureCodeMeta,
        failureCode.isAcceptableOrUnknown(
          data['failure_code']!,
          _failureCodeMeta,
        ),
      );
    }
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {importId, rowNumber},
  ];
  @override
  VocabularyImportRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VocabularyImportRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      importId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}import_id'],
      )!,
      rowNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_number'],
      )!,
      payloadHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_hash'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      failureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_code'],
      ),
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}word_id'],
      ),
    );
  }

  @override
  $VocabularyImportRowsTable createAlias(String alias) {
    return $VocabularyImportRowsTable(attachedDatabase, alias);
  }
}

class VocabularyImportRow extends DataClass
    implements Insertable<VocabularyImportRow> {
  final String id;
  final String importId;
  final int rowNumber;
  final String payloadHash;
  final String status;
  final String? failureCode;
  final String? wordId;
  const VocabularyImportRow({
    required this.id,
    required this.importId,
    required this.rowNumber,
    required this.payloadHash,
    required this.status,
    this.failureCode,
    this.wordId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['import_id'] = Variable<String>(importId);
    map['row_number'] = Variable<int>(rowNumber);
    map['payload_hash'] = Variable<String>(payloadHash);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || failureCode != null) {
      map['failure_code'] = Variable<String>(failureCode);
    }
    if (!nullToAbsent || wordId != null) {
      map['word_id'] = Variable<String>(wordId);
    }
    return map;
  }

  VocabularyImportRowsCompanion toCompanion(bool nullToAbsent) {
    return VocabularyImportRowsCompanion(
      id: Value(id),
      importId: Value(importId),
      rowNumber: Value(rowNumber),
      payloadHash: Value(payloadHash),
      status: Value(status),
      failureCode: failureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(failureCode),
      wordId: wordId == null && nullToAbsent
          ? const Value.absent()
          : Value(wordId),
    );
  }

  factory VocabularyImportRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VocabularyImportRow(
      id: serializer.fromJson<String>(json['id']),
      importId: serializer.fromJson<String>(json['importId']),
      rowNumber: serializer.fromJson<int>(json['rowNumber']),
      payloadHash: serializer.fromJson<String>(json['payloadHash']),
      status: serializer.fromJson<String>(json['status']),
      failureCode: serializer.fromJson<String?>(json['failureCode']),
      wordId: serializer.fromJson<String?>(json['wordId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'importId': serializer.toJson<String>(importId),
      'rowNumber': serializer.toJson<int>(rowNumber),
      'payloadHash': serializer.toJson<String>(payloadHash),
      'status': serializer.toJson<String>(status),
      'failureCode': serializer.toJson<String?>(failureCode),
      'wordId': serializer.toJson<String?>(wordId),
    };
  }

  VocabularyImportRow copyWith({
    String? id,
    String? importId,
    int? rowNumber,
    String? payloadHash,
    String? status,
    Value<String?> failureCode = const Value.absent(),
    Value<String?> wordId = const Value.absent(),
  }) => VocabularyImportRow(
    id: id ?? this.id,
    importId: importId ?? this.importId,
    rowNumber: rowNumber ?? this.rowNumber,
    payloadHash: payloadHash ?? this.payloadHash,
    status: status ?? this.status,
    failureCode: failureCode.present ? failureCode.value : this.failureCode,
    wordId: wordId.present ? wordId.value : this.wordId,
  );
  VocabularyImportRow copyWithCompanion(VocabularyImportRowsCompanion data) {
    return VocabularyImportRow(
      id: data.id.present ? data.id.value : this.id,
      importId: data.importId.present ? data.importId.value : this.importId,
      rowNumber: data.rowNumber.present ? data.rowNumber.value : this.rowNumber,
      payloadHash: data.payloadHash.present
          ? data.payloadHash.value
          : this.payloadHash,
      status: data.status.present ? data.status.value : this.status,
      failureCode: data.failureCode.present
          ? data.failureCode.value
          : this.failureCode,
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VocabularyImportRow(')
          ..write('id: $id, ')
          ..write('importId: $importId, ')
          ..write('rowNumber: $rowNumber, ')
          ..write('payloadHash: $payloadHash, ')
          ..write('status: $status, ')
          ..write('failureCode: $failureCode, ')
          ..write('wordId: $wordId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    importId,
    rowNumber,
    payloadHash,
    status,
    failureCode,
    wordId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VocabularyImportRow &&
          other.id == this.id &&
          other.importId == this.importId &&
          other.rowNumber == this.rowNumber &&
          other.payloadHash == this.payloadHash &&
          other.status == this.status &&
          other.failureCode == this.failureCode &&
          other.wordId == this.wordId);
}

class VocabularyImportRowsCompanion
    extends UpdateCompanion<VocabularyImportRow> {
  final Value<String> id;
  final Value<String> importId;
  final Value<int> rowNumber;
  final Value<String> payloadHash;
  final Value<String> status;
  final Value<String?> failureCode;
  final Value<String?> wordId;
  final Value<int> rowid;
  const VocabularyImportRowsCompanion({
    this.id = const Value.absent(),
    this.importId = const Value.absent(),
    this.rowNumber = const Value.absent(),
    this.payloadHash = const Value.absent(),
    this.status = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.wordId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VocabularyImportRowsCompanion.insert({
    required String id,
    required String importId,
    required int rowNumber,
    required String payloadHash,
    required String status,
    this.failureCode = const Value.absent(),
    this.wordId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       importId = Value(importId),
       rowNumber = Value(rowNumber),
       payloadHash = Value(payloadHash),
       status = Value(status);
  static Insertable<VocabularyImportRow> custom({
    Expression<String>? id,
    Expression<String>? importId,
    Expression<int>? rowNumber,
    Expression<String>? payloadHash,
    Expression<String>? status,
    Expression<String>? failureCode,
    Expression<String>? wordId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (importId != null) 'import_id': importId,
      if (rowNumber != null) 'row_number': rowNumber,
      if (payloadHash != null) 'payload_hash': payloadHash,
      if (status != null) 'status': status,
      if (failureCode != null) 'failure_code': failureCode,
      if (wordId != null) 'word_id': wordId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VocabularyImportRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? importId,
    Value<int>? rowNumber,
    Value<String>? payloadHash,
    Value<String>? status,
    Value<String?>? failureCode,
    Value<String?>? wordId,
    Value<int>? rowid,
  }) {
    return VocabularyImportRowsCompanion(
      id: id ?? this.id,
      importId: importId ?? this.importId,
      rowNumber: rowNumber ?? this.rowNumber,
      payloadHash: payloadHash ?? this.payloadHash,
      status: status ?? this.status,
      failureCode: failureCode ?? this.failureCode,
      wordId: wordId ?? this.wordId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (importId.present) {
      map['import_id'] = Variable<String>(importId.value);
    }
    if (rowNumber.present) {
      map['row_number'] = Variable<int>(rowNumber.value);
    }
    if (payloadHash.present) {
      map['payload_hash'] = Variable<String>(payloadHash.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (failureCode.present) {
      map['failure_code'] = Variable<String>(failureCode.value);
    }
    if (wordId.present) {
      map['word_id'] = Variable<String>(wordId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VocabularyImportRowsCompanion(')
          ..write('id: $id, ')
          ..write('importId: $importId, ')
          ..write('rowNumber: $rowNumber, ')
          ..write('payloadHash: $payloadHash, ')
          ..write('status: $status, ')
          ..write('failureCode: $failureCode, ')
          ..write('wordId: $wordId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LearningSessionsTable extends LearningSessions
    with TableInfo<$LearningSessionsTable, LearningSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LearningSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _activityTypeMeta = const VerificationMeta(
    'activityType',
  );
  @override
  late final GeneratedColumn<String> activityType = GeneratedColumn<String>(
    'activity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtUtcMsMeta = const VerificationMeta(
    'startedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> startedAtUtcMs = GeneratedColumn<int>(
    'started_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtUtcMsMeta = const VerificationMeta(
    'endedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> endedAtUtcMs = GeneratedColumn<int>(
    'ended_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _correctCountMeta = const VerificationMeta(
    'correctCount',
  );
  @override
  late final GeneratedColumn<int> correctCount = GeneratedColumn<int>(
    'correct_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _wrongCountMeta = const VerificationMeta(
    'wrongCount',
  );
  @override
  late final GeneratedColumn<int> wrongCount = GeneratedColumn<int>(
    'wrong_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<int> score = GeneratedColumn<int>(
    'score',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _appVersionMeta = const VerificationMeta(
    'appVersion',
  );
  @override
  late final GeneratedColumn<String> appVersion = GeneratedColumn<String>(
    'app_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _buildIdMeta = const VerificationMeta(
    'buildId',
  );
  @override
  late final GeneratedColumn<String> buildId = GeneratedColumn<String>(
    'build_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    activityType,
    state,
    startedAtUtcMs,
    endedAtUtcMs,
    correctCount,
    wrongCount,
    score,
    appVersion,
    buildId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'learning_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<LearningSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('activity_type')) {
      context.handle(
        _activityTypeMeta,
        activityType.isAcceptableOrUnknown(
          data['activity_type']!,
          _activityTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activityTypeMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('started_at_utc_ms')) {
      context.handle(
        _startedAtUtcMsMeta,
        startedAtUtcMs.isAcceptableOrUnknown(
          data['started_at_utc_ms']!,
          _startedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startedAtUtcMsMeta);
    }
    if (data.containsKey('ended_at_utc_ms')) {
      context.handle(
        _endedAtUtcMsMeta,
        endedAtUtcMs.isAcceptableOrUnknown(
          data['ended_at_utc_ms']!,
          _endedAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('correct_count')) {
      context.handle(
        _correctCountMeta,
        correctCount.isAcceptableOrUnknown(
          data['correct_count']!,
          _correctCountMeta,
        ),
      );
    }
    if (data.containsKey('wrong_count')) {
      context.handle(
        _wrongCountMeta,
        wrongCount.isAcceptableOrUnknown(data['wrong_count']!, _wrongCountMeta),
      );
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    }
    if (data.containsKey('app_version')) {
      context.handle(
        _appVersionMeta,
        appVersion.isAcceptableOrUnknown(data['app_version']!, _appVersionMeta),
      );
    } else if (isInserting) {
      context.missing(_appVersionMeta);
    }
    if (data.containsKey('build_id')) {
      context.handle(
        _buildIdMeta,
        buildId.isAcceptableOrUnknown(data['build_id']!, _buildIdMeta),
      );
    } else if (isInserting) {
      context.missing(_buildIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LearningSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LearningSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      activityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity_type'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      startedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at_utc_ms'],
      )!,
      endedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at_utc_ms'],
      ),
      correctCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}correct_count'],
      )!,
      wrongCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wrong_count'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}score'],
      ),
      appVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_version'],
      )!,
      buildId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}build_id'],
      )!,
    );
  }

  @override
  $LearningSessionsTable createAlias(String alias) {
    return $LearningSessionsTable(attachedDatabase, alias);
  }
}

class LearningSession extends DataClass implements Insertable<LearningSession> {
  final String id;
  final String ownerId;
  final String activityType;
  final String state;
  final int startedAtUtcMs;
  final int? endedAtUtcMs;
  final int correctCount;
  final int wrongCount;
  final int? score;
  final String appVersion;
  final String buildId;
  const LearningSession({
    required this.id,
    required this.ownerId,
    required this.activityType,
    required this.state,
    required this.startedAtUtcMs,
    this.endedAtUtcMs,
    required this.correctCount,
    required this.wrongCount,
    this.score,
    required this.appVersion,
    required this.buildId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['activity_type'] = Variable<String>(activityType);
    map['state'] = Variable<String>(state);
    map['started_at_utc_ms'] = Variable<int>(startedAtUtcMs);
    if (!nullToAbsent || endedAtUtcMs != null) {
      map['ended_at_utc_ms'] = Variable<int>(endedAtUtcMs);
    }
    map['correct_count'] = Variable<int>(correctCount);
    map['wrong_count'] = Variable<int>(wrongCount);
    if (!nullToAbsent || score != null) {
      map['score'] = Variable<int>(score);
    }
    map['app_version'] = Variable<String>(appVersion);
    map['build_id'] = Variable<String>(buildId);
    return map;
  }

  LearningSessionsCompanion toCompanion(bool nullToAbsent) {
    return LearningSessionsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      activityType: Value(activityType),
      state: Value(state),
      startedAtUtcMs: Value(startedAtUtcMs),
      endedAtUtcMs: endedAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAtUtcMs),
      correctCount: Value(correctCount),
      wrongCount: Value(wrongCount),
      score: score == null && nullToAbsent
          ? const Value.absent()
          : Value(score),
      appVersion: Value(appVersion),
      buildId: Value(buildId),
    );
  }

  factory LearningSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LearningSession(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      activityType: serializer.fromJson<String>(json['activityType']),
      state: serializer.fromJson<String>(json['state']),
      startedAtUtcMs: serializer.fromJson<int>(json['startedAtUtcMs']),
      endedAtUtcMs: serializer.fromJson<int?>(json['endedAtUtcMs']),
      correctCount: serializer.fromJson<int>(json['correctCount']),
      wrongCount: serializer.fromJson<int>(json['wrongCount']),
      score: serializer.fromJson<int?>(json['score']),
      appVersion: serializer.fromJson<String>(json['appVersion']),
      buildId: serializer.fromJson<String>(json['buildId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'activityType': serializer.toJson<String>(activityType),
      'state': serializer.toJson<String>(state),
      'startedAtUtcMs': serializer.toJson<int>(startedAtUtcMs),
      'endedAtUtcMs': serializer.toJson<int?>(endedAtUtcMs),
      'correctCount': serializer.toJson<int>(correctCount),
      'wrongCount': serializer.toJson<int>(wrongCount),
      'score': serializer.toJson<int?>(score),
      'appVersion': serializer.toJson<String>(appVersion),
      'buildId': serializer.toJson<String>(buildId),
    };
  }

  LearningSession copyWith({
    String? id,
    String? ownerId,
    String? activityType,
    String? state,
    int? startedAtUtcMs,
    Value<int?> endedAtUtcMs = const Value.absent(),
    int? correctCount,
    int? wrongCount,
    Value<int?> score = const Value.absent(),
    String? appVersion,
    String? buildId,
  }) => LearningSession(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    activityType: activityType ?? this.activityType,
    state: state ?? this.state,
    startedAtUtcMs: startedAtUtcMs ?? this.startedAtUtcMs,
    endedAtUtcMs: endedAtUtcMs.present ? endedAtUtcMs.value : this.endedAtUtcMs,
    correctCount: correctCount ?? this.correctCount,
    wrongCount: wrongCount ?? this.wrongCount,
    score: score.present ? score.value : this.score,
    appVersion: appVersion ?? this.appVersion,
    buildId: buildId ?? this.buildId,
  );
  LearningSession copyWithCompanion(LearningSessionsCompanion data) {
    return LearningSession(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      activityType: data.activityType.present
          ? data.activityType.value
          : this.activityType,
      state: data.state.present ? data.state.value : this.state,
      startedAtUtcMs: data.startedAtUtcMs.present
          ? data.startedAtUtcMs.value
          : this.startedAtUtcMs,
      endedAtUtcMs: data.endedAtUtcMs.present
          ? data.endedAtUtcMs.value
          : this.endedAtUtcMs,
      correctCount: data.correctCount.present
          ? data.correctCount.value
          : this.correctCount,
      wrongCount: data.wrongCount.present
          ? data.wrongCount.value
          : this.wrongCount,
      score: data.score.present ? data.score.value : this.score,
      appVersion: data.appVersion.present
          ? data.appVersion.value
          : this.appVersion,
      buildId: data.buildId.present ? data.buildId.value : this.buildId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LearningSession(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('activityType: $activityType, ')
          ..write('state: $state, ')
          ..write('startedAtUtcMs: $startedAtUtcMs, ')
          ..write('endedAtUtcMs: $endedAtUtcMs, ')
          ..write('correctCount: $correctCount, ')
          ..write('wrongCount: $wrongCount, ')
          ..write('score: $score, ')
          ..write('appVersion: $appVersion, ')
          ..write('buildId: $buildId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    activityType,
    state,
    startedAtUtcMs,
    endedAtUtcMs,
    correctCount,
    wrongCount,
    score,
    appVersion,
    buildId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LearningSession &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.activityType == this.activityType &&
          other.state == this.state &&
          other.startedAtUtcMs == this.startedAtUtcMs &&
          other.endedAtUtcMs == this.endedAtUtcMs &&
          other.correctCount == this.correctCount &&
          other.wrongCount == this.wrongCount &&
          other.score == this.score &&
          other.appVersion == this.appVersion &&
          other.buildId == this.buildId);
}

class LearningSessionsCompanion extends UpdateCompanion<LearningSession> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> activityType;
  final Value<String> state;
  final Value<int> startedAtUtcMs;
  final Value<int?> endedAtUtcMs;
  final Value<int> correctCount;
  final Value<int> wrongCount;
  final Value<int?> score;
  final Value<String> appVersion;
  final Value<String> buildId;
  final Value<int> rowid;
  const LearningSessionsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.activityType = const Value.absent(),
    this.state = const Value.absent(),
    this.startedAtUtcMs = const Value.absent(),
    this.endedAtUtcMs = const Value.absent(),
    this.correctCount = const Value.absent(),
    this.wrongCount = const Value.absent(),
    this.score = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.buildId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LearningSessionsCompanion.insert({
    required String id,
    required String ownerId,
    required String activityType,
    required String state,
    required int startedAtUtcMs,
    this.endedAtUtcMs = const Value.absent(),
    this.correctCount = const Value.absent(),
    this.wrongCount = const Value.absent(),
    this.score = const Value.absent(),
    required String appVersion,
    required String buildId,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       activityType = Value(activityType),
       state = Value(state),
       startedAtUtcMs = Value(startedAtUtcMs),
       appVersion = Value(appVersion),
       buildId = Value(buildId);
  static Insertable<LearningSession> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? activityType,
    Expression<String>? state,
    Expression<int>? startedAtUtcMs,
    Expression<int>? endedAtUtcMs,
    Expression<int>? correctCount,
    Expression<int>? wrongCount,
    Expression<int>? score,
    Expression<String>? appVersion,
    Expression<String>? buildId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (activityType != null) 'activity_type': activityType,
      if (state != null) 'state': state,
      if (startedAtUtcMs != null) 'started_at_utc_ms': startedAtUtcMs,
      if (endedAtUtcMs != null) 'ended_at_utc_ms': endedAtUtcMs,
      if (correctCount != null) 'correct_count': correctCount,
      if (wrongCount != null) 'wrong_count': wrongCount,
      if (score != null) 'score': score,
      if (appVersion != null) 'app_version': appVersion,
      if (buildId != null) 'build_id': buildId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LearningSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? activityType,
    Value<String>? state,
    Value<int>? startedAtUtcMs,
    Value<int?>? endedAtUtcMs,
    Value<int>? correctCount,
    Value<int>? wrongCount,
    Value<int?>? score,
    Value<String>? appVersion,
    Value<String>? buildId,
    Value<int>? rowid,
  }) {
    return LearningSessionsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      activityType: activityType ?? this.activityType,
      state: state ?? this.state,
      startedAtUtcMs: startedAtUtcMs ?? this.startedAtUtcMs,
      endedAtUtcMs: endedAtUtcMs ?? this.endedAtUtcMs,
      correctCount: correctCount ?? this.correctCount,
      wrongCount: wrongCount ?? this.wrongCount,
      score: score ?? this.score,
      appVersion: appVersion ?? this.appVersion,
      buildId: buildId ?? this.buildId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (activityType.present) {
      map['activity_type'] = Variable<String>(activityType.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (startedAtUtcMs.present) {
      map['started_at_utc_ms'] = Variable<int>(startedAtUtcMs.value);
    }
    if (endedAtUtcMs.present) {
      map['ended_at_utc_ms'] = Variable<int>(endedAtUtcMs.value);
    }
    if (correctCount.present) {
      map['correct_count'] = Variable<int>(correctCount.value);
    }
    if (wrongCount.present) {
      map['wrong_count'] = Variable<int>(wrongCount.value);
    }
    if (score.present) {
      map['score'] = Variable<int>(score.value);
    }
    if (appVersion.present) {
      map['app_version'] = Variable<String>(appVersion.value);
    }
    if (buildId.present) {
      map['build_id'] = Variable<String>(buildId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LearningSessionsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('activityType: $activityType, ')
          ..write('state: $state, ')
          ..write('startedAtUtcMs: $startedAtUtcMs, ')
          ..write('endedAtUtcMs: $endedAtUtcMs, ')
          ..write('correctCount: $correctCount, ')
          ..write('wrongCount: $wrongCount, ')
          ..write('score: $score, ')
          ..write('appVersion: $appVersion, ')
          ..write('buildId: $buildId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AnswerAttemptsTable extends AnswerAttempts
    with TableInfo<$AnswerAttemptsTable, AnswerAttempt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnswerAttemptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES learning_sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<String> wordId = GeneratedColumn<String>(
    'word_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES vocabulary_words (id)',
    ),
  );
  static const VerificationMeta _promptModeMeta = const VerificationMeta(
    'promptMode',
  );
  @override
  late final GeneratedColumn<String> promptMode = GeneratedColumn<String>(
    'prompt_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isCorrectMeta = const VerificationMeta(
    'isCorrect',
  );
  @override
  late final GeneratedColumn<bool> isCorrect = GeneratedColumn<bool>(
    'is_correct',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_correct" IN (0, 1))',
    ),
  );
  static const VerificationMeta _responseTimeMsMeta = const VerificationMeta(
    'responseTimeMs',
  );
  @override
  late final GeneratedColumn<int> responseTimeMs = GeneratedColumn<int>(
    'response_time_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptNumberMeta = const VerificationMeta(
    'attemptNumber',
  );
  @override
  late final GeneratedColumn<int> attemptNumber = GeneratedColumn<int>(
    'attempt_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtUtcMsMeta = const VerificationMeta(
    'occurredAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> occurredAtUtcMs = GeneratedColumn<int>(
    'occurred_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerProvenanceMeta =
      const VerificationMeta('providerProvenance');
  @override
  late final GeneratedColumn<String> providerProvenance =
      GeneratedColumn<String>(
        'provider_provenance',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    sessionId,
    wordId,
    promptMode,
    isCorrect,
    responseTimeMs,
    attemptNumber,
    occurredAtUtcMs,
    providerProvenance,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'answer_attempts';
  @override
  VerificationContext validateIntegrity(
    Insertable<AnswerAttempt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_wordIdMeta);
    }
    if (data.containsKey('prompt_mode')) {
      context.handle(
        _promptModeMeta,
        promptMode.isAcceptableOrUnknown(data['prompt_mode']!, _promptModeMeta),
      );
    } else if (isInserting) {
      context.missing(_promptModeMeta);
    }
    if (data.containsKey('is_correct')) {
      context.handle(
        _isCorrectMeta,
        isCorrect.isAcceptableOrUnknown(data['is_correct']!, _isCorrectMeta),
      );
    } else if (isInserting) {
      context.missing(_isCorrectMeta);
    }
    if (data.containsKey('response_time_ms')) {
      context.handle(
        _responseTimeMsMeta,
        responseTimeMs.isAcceptableOrUnknown(
          data['response_time_ms']!,
          _responseTimeMsMeta,
        ),
      );
    }
    if (data.containsKey('attempt_number')) {
      context.handle(
        _attemptNumberMeta,
        attemptNumber.isAcceptableOrUnknown(
          data['attempt_number']!,
          _attemptNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attemptNumberMeta);
    }
    if (data.containsKey('occurred_at_utc_ms')) {
      context.handle(
        _occurredAtUtcMsMeta,
        occurredAtUtcMs.isAcceptableOrUnknown(
          data['occurred_at_utc_ms']!,
          _occurredAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtUtcMsMeta);
    }
    if (data.containsKey('provider_provenance')) {
      context.handle(
        _providerProvenanceMeta,
        providerProvenance.isAcceptableOrUnknown(
          data['provider_provenance']!,
          _providerProvenanceMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AnswerAttempt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnswerAttempt(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}word_id'],
      )!,
      promptMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt_mode'],
      )!,
      isCorrect: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_correct'],
      )!,
      responseTimeMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}response_time_ms'],
      ),
      attemptNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_number'],
      )!,
      occurredAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurred_at_utc_ms'],
      )!,
      providerProvenance: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_provenance'],
      ),
    );
  }

  @override
  $AnswerAttemptsTable createAlias(String alias) {
    return $AnswerAttemptsTable(attachedDatabase, alias);
  }
}

class AnswerAttempt extends DataClass implements Insertable<AnswerAttempt> {
  final String id;
  final String ownerId;
  final String sessionId;
  final String wordId;
  final String promptMode;
  final bool isCorrect;
  final int? responseTimeMs;
  final int attemptNumber;
  final int occurredAtUtcMs;
  final String? providerProvenance;
  const AnswerAttempt({
    required this.id,
    required this.ownerId,
    required this.sessionId,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    this.responseTimeMs,
    required this.attemptNumber,
    required this.occurredAtUtcMs,
    this.providerProvenance,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['session_id'] = Variable<String>(sessionId);
    map['word_id'] = Variable<String>(wordId);
    map['prompt_mode'] = Variable<String>(promptMode);
    map['is_correct'] = Variable<bool>(isCorrect);
    if (!nullToAbsent || responseTimeMs != null) {
      map['response_time_ms'] = Variable<int>(responseTimeMs);
    }
    map['attempt_number'] = Variable<int>(attemptNumber);
    map['occurred_at_utc_ms'] = Variable<int>(occurredAtUtcMs);
    if (!nullToAbsent || providerProvenance != null) {
      map['provider_provenance'] = Variable<String>(providerProvenance);
    }
    return map;
  }

  AnswerAttemptsCompanion toCompanion(bool nullToAbsent) {
    return AnswerAttemptsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      sessionId: Value(sessionId),
      wordId: Value(wordId),
      promptMode: Value(promptMode),
      isCorrect: Value(isCorrect),
      responseTimeMs: responseTimeMs == null && nullToAbsent
          ? const Value.absent()
          : Value(responseTimeMs),
      attemptNumber: Value(attemptNumber),
      occurredAtUtcMs: Value(occurredAtUtcMs),
      providerProvenance: providerProvenance == null && nullToAbsent
          ? const Value.absent()
          : Value(providerProvenance),
    );
  }

  factory AnswerAttempt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnswerAttempt(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      wordId: serializer.fromJson<String>(json['wordId']),
      promptMode: serializer.fromJson<String>(json['promptMode']),
      isCorrect: serializer.fromJson<bool>(json['isCorrect']),
      responseTimeMs: serializer.fromJson<int?>(json['responseTimeMs']),
      attemptNumber: serializer.fromJson<int>(json['attemptNumber']),
      occurredAtUtcMs: serializer.fromJson<int>(json['occurredAtUtcMs']),
      providerProvenance: serializer.fromJson<String?>(
        json['providerProvenance'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'sessionId': serializer.toJson<String>(sessionId),
      'wordId': serializer.toJson<String>(wordId),
      'promptMode': serializer.toJson<String>(promptMode),
      'isCorrect': serializer.toJson<bool>(isCorrect),
      'responseTimeMs': serializer.toJson<int?>(responseTimeMs),
      'attemptNumber': serializer.toJson<int>(attemptNumber),
      'occurredAtUtcMs': serializer.toJson<int>(occurredAtUtcMs),
      'providerProvenance': serializer.toJson<String?>(providerProvenance),
    };
  }

  AnswerAttempt copyWith({
    String? id,
    String? ownerId,
    String? sessionId,
    String? wordId,
    String? promptMode,
    bool? isCorrect,
    Value<int?> responseTimeMs = const Value.absent(),
    int? attemptNumber,
    int? occurredAtUtcMs,
    Value<String?> providerProvenance = const Value.absent(),
  }) => AnswerAttempt(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    sessionId: sessionId ?? this.sessionId,
    wordId: wordId ?? this.wordId,
    promptMode: promptMode ?? this.promptMode,
    isCorrect: isCorrect ?? this.isCorrect,
    responseTimeMs: responseTimeMs.present
        ? responseTimeMs.value
        : this.responseTimeMs,
    attemptNumber: attemptNumber ?? this.attemptNumber,
    occurredAtUtcMs: occurredAtUtcMs ?? this.occurredAtUtcMs,
    providerProvenance: providerProvenance.present
        ? providerProvenance.value
        : this.providerProvenance,
  );
  AnswerAttempt copyWithCompanion(AnswerAttemptsCompanion data) {
    return AnswerAttempt(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      promptMode: data.promptMode.present
          ? data.promptMode.value
          : this.promptMode,
      isCorrect: data.isCorrect.present ? data.isCorrect.value : this.isCorrect,
      responseTimeMs: data.responseTimeMs.present
          ? data.responseTimeMs.value
          : this.responseTimeMs,
      attemptNumber: data.attemptNumber.present
          ? data.attemptNumber.value
          : this.attemptNumber,
      occurredAtUtcMs: data.occurredAtUtcMs.present
          ? data.occurredAtUtcMs.value
          : this.occurredAtUtcMs,
      providerProvenance: data.providerProvenance.present
          ? data.providerProvenance.value
          : this.providerProvenance,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnswerAttempt(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('sessionId: $sessionId, ')
          ..write('wordId: $wordId, ')
          ..write('promptMode: $promptMode, ')
          ..write('isCorrect: $isCorrect, ')
          ..write('responseTimeMs: $responseTimeMs, ')
          ..write('attemptNumber: $attemptNumber, ')
          ..write('occurredAtUtcMs: $occurredAtUtcMs, ')
          ..write('providerProvenance: $providerProvenance')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    sessionId,
    wordId,
    promptMode,
    isCorrect,
    responseTimeMs,
    attemptNumber,
    occurredAtUtcMs,
    providerProvenance,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnswerAttempt &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.sessionId == this.sessionId &&
          other.wordId == this.wordId &&
          other.promptMode == this.promptMode &&
          other.isCorrect == this.isCorrect &&
          other.responseTimeMs == this.responseTimeMs &&
          other.attemptNumber == this.attemptNumber &&
          other.occurredAtUtcMs == this.occurredAtUtcMs &&
          other.providerProvenance == this.providerProvenance);
}

class AnswerAttemptsCompanion extends UpdateCompanion<AnswerAttempt> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> sessionId;
  final Value<String> wordId;
  final Value<String> promptMode;
  final Value<bool> isCorrect;
  final Value<int?> responseTimeMs;
  final Value<int> attemptNumber;
  final Value<int> occurredAtUtcMs;
  final Value<String?> providerProvenance;
  final Value<int> rowid;
  const AnswerAttemptsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.wordId = const Value.absent(),
    this.promptMode = const Value.absent(),
    this.isCorrect = const Value.absent(),
    this.responseTimeMs = const Value.absent(),
    this.attemptNumber = const Value.absent(),
    this.occurredAtUtcMs = const Value.absent(),
    this.providerProvenance = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnswerAttemptsCompanion.insert({
    required String id,
    required String ownerId,
    required String sessionId,
    required String wordId,
    required String promptMode,
    required bool isCorrect,
    this.responseTimeMs = const Value.absent(),
    required int attemptNumber,
    required int occurredAtUtcMs,
    this.providerProvenance = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       sessionId = Value(sessionId),
       wordId = Value(wordId),
       promptMode = Value(promptMode),
       isCorrect = Value(isCorrect),
       attemptNumber = Value(attemptNumber),
       occurredAtUtcMs = Value(occurredAtUtcMs);
  static Insertable<AnswerAttempt> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? sessionId,
    Expression<String>? wordId,
    Expression<String>? promptMode,
    Expression<bool>? isCorrect,
    Expression<int>? responseTimeMs,
    Expression<int>? attemptNumber,
    Expression<int>? occurredAtUtcMs,
    Expression<String>? providerProvenance,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (sessionId != null) 'session_id': sessionId,
      if (wordId != null) 'word_id': wordId,
      if (promptMode != null) 'prompt_mode': promptMode,
      if (isCorrect != null) 'is_correct': isCorrect,
      if (responseTimeMs != null) 'response_time_ms': responseTimeMs,
      if (attemptNumber != null) 'attempt_number': attemptNumber,
      if (occurredAtUtcMs != null) 'occurred_at_utc_ms': occurredAtUtcMs,
      if (providerProvenance != null) 'provider_provenance': providerProvenance,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnswerAttemptsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? sessionId,
    Value<String>? wordId,
    Value<String>? promptMode,
    Value<bool>? isCorrect,
    Value<int?>? responseTimeMs,
    Value<int>? attemptNumber,
    Value<int>? occurredAtUtcMs,
    Value<String?>? providerProvenance,
    Value<int>? rowid,
  }) {
    return AnswerAttemptsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      sessionId: sessionId ?? this.sessionId,
      wordId: wordId ?? this.wordId,
      promptMode: promptMode ?? this.promptMode,
      isCorrect: isCorrect ?? this.isCorrect,
      responseTimeMs: responseTimeMs ?? this.responseTimeMs,
      attemptNumber: attemptNumber ?? this.attemptNumber,
      occurredAtUtcMs: occurredAtUtcMs ?? this.occurredAtUtcMs,
      providerProvenance: providerProvenance ?? this.providerProvenance,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (wordId.present) {
      map['word_id'] = Variable<String>(wordId.value);
    }
    if (promptMode.present) {
      map['prompt_mode'] = Variable<String>(promptMode.value);
    }
    if (isCorrect.present) {
      map['is_correct'] = Variable<bool>(isCorrect.value);
    }
    if (responseTimeMs.present) {
      map['response_time_ms'] = Variable<int>(responseTimeMs.value);
    }
    if (attemptNumber.present) {
      map['attempt_number'] = Variable<int>(attemptNumber.value);
    }
    if (occurredAtUtcMs.present) {
      map['occurred_at_utc_ms'] = Variable<int>(occurredAtUtcMs.value);
    }
    if (providerProvenance.present) {
      map['provider_provenance'] = Variable<String>(providerProvenance.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnswerAttemptsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('sessionId: $sessionId, ')
          ..write('wordId: $wordId, ')
          ..write('promptMode: $promptMode, ')
          ..write('isCorrect: $isCorrect, ')
          ..write('responseTimeMs: $responseTimeMs, ')
          ..write('attemptNumber: $attemptNumber, ')
          ..write('occurredAtUtcMs: $occurredAtUtcMs, ')
          ..write('providerProvenance: $providerProvenance, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SrsStatesTable extends SrsStates
    with TableInfo<$SrsStatesTable, SrsState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SrsStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<String> wordId = GeneratedColumn<String>(
    'word_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES vocabulary_words (id)',
    ),
  );
  static const VerificationMeta _stabilityMeta = const VerificationMeta(
    'stability',
  );
  @override
  late final GeneratedColumn<double> stability = GeneratedColumn<double>(
    'stability',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _difficultyMeta = const VerificationMeta(
    'difficulty',
  );
  @override
  late final GeneratedColumn<double> difficulty = GeneratedColumn<double>(
    'difficulty',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _intervalDaysMeta = const VerificationMeta(
    'intervalDays',
  );
  @override
  late final GeneratedColumn<int> intervalDays = GeneratedColumn<int>(
    'interval_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _repetitionsMeta = const VerificationMeta(
    'repetitions',
  );
  @override
  late final GeneratedColumn<int> repetitions = GeneratedColumn<int>(
    'repetitions',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lapsesMeta = const VerificationMeta('lapses');
  @override
  late final GeneratedColumn<int> lapses = GeneratedColumn<int>(
    'lapses',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastReviewAtUtcMsMeta = const VerificationMeta(
    'lastReviewAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> lastReviewAtUtcMs = GeneratedColumn<int>(
    'last_review_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueAtUtcMsMeta = const VerificationMeta(
    'dueAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> dueAtUtcMs = GeneratedColumn<int>(
    'due_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _algorithmVersionMeta = const VerificationMeta(
    'algorithmVersion',
  );
  @override
  late final GeneratedColumn<int> algorithmVersion = GeneratedColumn<int>(
    'algorithm_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    wordId,
    stability,
    difficulty,
    intervalDays,
    repetitions,
    lapses,
    lastReviewAtUtcMs,
    dueAtUtcMs,
    algorithmVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'srs_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<SrsState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_wordIdMeta);
    }
    if (data.containsKey('stability')) {
      context.handle(
        _stabilityMeta,
        stability.isAcceptableOrUnknown(data['stability']!, _stabilityMeta),
      );
    }
    if (data.containsKey('difficulty')) {
      context.handle(
        _difficultyMeta,
        difficulty.isAcceptableOrUnknown(data['difficulty']!, _difficultyMeta),
      );
    }
    if (data.containsKey('interval_days')) {
      context.handle(
        _intervalDaysMeta,
        intervalDays.isAcceptableOrUnknown(
          data['interval_days']!,
          _intervalDaysMeta,
        ),
      );
    }
    if (data.containsKey('repetitions')) {
      context.handle(
        _repetitionsMeta,
        repetitions.isAcceptableOrUnknown(
          data['repetitions']!,
          _repetitionsMeta,
        ),
      );
    }
    if (data.containsKey('lapses')) {
      context.handle(
        _lapsesMeta,
        lapses.isAcceptableOrUnknown(data['lapses']!, _lapsesMeta),
      );
    }
    if (data.containsKey('last_review_at_utc_ms')) {
      context.handle(
        _lastReviewAtUtcMsMeta,
        lastReviewAtUtcMs.isAcceptableOrUnknown(
          data['last_review_at_utc_ms']!,
          _lastReviewAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('due_at_utc_ms')) {
      context.handle(
        _dueAtUtcMsMeta,
        dueAtUtcMs.isAcceptableOrUnknown(
          data['due_at_utc_ms']!,
          _dueAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dueAtUtcMsMeta);
    }
    if (data.containsKey('algorithm_version')) {
      context.handle(
        _algorithmVersionMeta,
        algorithmVersion.isAcceptableOrUnknown(
          data['algorithm_version']!,
          _algorithmVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_algorithmVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerId, wordId},
  ];
  @override
  SrsState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SrsState(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}word_id'],
      )!,
      stability: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}stability'],
      )!,
      difficulty: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}difficulty'],
      )!,
      intervalDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interval_days'],
      )!,
      repetitions: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repetitions'],
      )!,
      lapses: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lapses'],
      )!,
      lastReviewAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_review_at_utc_ms'],
      ),
      dueAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due_at_utc_ms'],
      )!,
      algorithmVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}algorithm_version'],
      )!,
    );
  }

  @override
  $SrsStatesTable createAlias(String alias) {
    return $SrsStatesTable(attachedDatabase, alias);
  }
}

class SrsState extends DataClass implements Insertable<SrsState> {
  final String id;
  final String ownerId;
  final String wordId;
  final double stability;
  final double difficulty;
  final int intervalDays;
  final int repetitions;
  final int lapses;
  final int? lastReviewAtUtcMs;
  final int dueAtUtcMs;
  final int algorithmVersion;
  const SrsState({
    required this.id,
    required this.ownerId,
    required this.wordId,
    required this.stability,
    required this.difficulty,
    required this.intervalDays,
    required this.repetitions,
    required this.lapses,
    this.lastReviewAtUtcMs,
    required this.dueAtUtcMs,
    required this.algorithmVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['word_id'] = Variable<String>(wordId);
    map['stability'] = Variable<double>(stability);
    map['difficulty'] = Variable<double>(difficulty);
    map['interval_days'] = Variable<int>(intervalDays);
    map['repetitions'] = Variable<int>(repetitions);
    map['lapses'] = Variable<int>(lapses);
    if (!nullToAbsent || lastReviewAtUtcMs != null) {
      map['last_review_at_utc_ms'] = Variable<int>(lastReviewAtUtcMs);
    }
    map['due_at_utc_ms'] = Variable<int>(dueAtUtcMs);
    map['algorithm_version'] = Variable<int>(algorithmVersion);
    return map;
  }

  SrsStatesCompanion toCompanion(bool nullToAbsent) {
    return SrsStatesCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      wordId: Value(wordId),
      stability: Value(stability),
      difficulty: Value(difficulty),
      intervalDays: Value(intervalDays),
      repetitions: Value(repetitions),
      lapses: Value(lapses),
      lastReviewAtUtcMs: lastReviewAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReviewAtUtcMs),
      dueAtUtcMs: Value(dueAtUtcMs),
      algorithmVersion: Value(algorithmVersion),
    );
  }

  factory SrsState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SrsState(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      wordId: serializer.fromJson<String>(json['wordId']),
      stability: serializer.fromJson<double>(json['stability']),
      difficulty: serializer.fromJson<double>(json['difficulty']),
      intervalDays: serializer.fromJson<int>(json['intervalDays']),
      repetitions: serializer.fromJson<int>(json['repetitions']),
      lapses: serializer.fromJson<int>(json['lapses']),
      lastReviewAtUtcMs: serializer.fromJson<int?>(json['lastReviewAtUtcMs']),
      dueAtUtcMs: serializer.fromJson<int>(json['dueAtUtcMs']),
      algorithmVersion: serializer.fromJson<int>(json['algorithmVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'wordId': serializer.toJson<String>(wordId),
      'stability': serializer.toJson<double>(stability),
      'difficulty': serializer.toJson<double>(difficulty),
      'intervalDays': serializer.toJson<int>(intervalDays),
      'repetitions': serializer.toJson<int>(repetitions),
      'lapses': serializer.toJson<int>(lapses),
      'lastReviewAtUtcMs': serializer.toJson<int?>(lastReviewAtUtcMs),
      'dueAtUtcMs': serializer.toJson<int>(dueAtUtcMs),
      'algorithmVersion': serializer.toJson<int>(algorithmVersion),
    };
  }

  SrsState copyWith({
    String? id,
    String? ownerId,
    String? wordId,
    double? stability,
    double? difficulty,
    int? intervalDays,
    int? repetitions,
    int? lapses,
    Value<int?> lastReviewAtUtcMs = const Value.absent(),
    int? dueAtUtcMs,
    int? algorithmVersion,
  }) => SrsState(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    wordId: wordId ?? this.wordId,
    stability: stability ?? this.stability,
    difficulty: difficulty ?? this.difficulty,
    intervalDays: intervalDays ?? this.intervalDays,
    repetitions: repetitions ?? this.repetitions,
    lapses: lapses ?? this.lapses,
    lastReviewAtUtcMs: lastReviewAtUtcMs.present
        ? lastReviewAtUtcMs.value
        : this.lastReviewAtUtcMs,
    dueAtUtcMs: dueAtUtcMs ?? this.dueAtUtcMs,
    algorithmVersion: algorithmVersion ?? this.algorithmVersion,
  );
  SrsState copyWithCompanion(SrsStatesCompanion data) {
    return SrsState(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      stability: data.stability.present ? data.stability.value : this.stability,
      difficulty: data.difficulty.present
          ? data.difficulty.value
          : this.difficulty,
      intervalDays: data.intervalDays.present
          ? data.intervalDays.value
          : this.intervalDays,
      repetitions: data.repetitions.present
          ? data.repetitions.value
          : this.repetitions,
      lapses: data.lapses.present ? data.lapses.value : this.lapses,
      lastReviewAtUtcMs: data.lastReviewAtUtcMs.present
          ? data.lastReviewAtUtcMs.value
          : this.lastReviewAtUtcMs,
      dueAtUtcMs: data.dueAtUtcMs.present
          ? data.dueAtUtcMs.value
          : this.dueAtUtcMs,
      algorithmVersion: data.algorithmVersion.present
          ? data.algorithmVersion.value
          : this.algorithmVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SrsState(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('wordId: $wordId, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('intervalDays: $intervalDays, ')
          ..write('repetitions: $repetitions, ')
          ..write('lapses: $lapses, ')
          ..write('lastReviewAtUtcMs: $lastReviewAtUtcMs, ')
          ..write('dueAtUtcMs: $dueAtUtcMs, ')
          ..write('algorithmVersion: $algorithmVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    wordId,
    stability,
    difficulty,
    intervalDays,
    repetitions,
    lapses,
    lastReviewAtUtcMs,
    dueAtUtcMs,
    algorithmVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SrsState &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.wordId == this.wordId &&
          other.stability == this.stability &&
          other.difficulty == this.difficulty &&
          other.intervalDays == this.intervalDays &&
          other.repetitions == this.repetitions &&
          other.lapses == this.lapses &&
          other.lastReviewAtUtcMs == this.lastReviewAtUtcMs &&
          other.dueAtUtcMs == this.dueAtUtcMs &&
          other.algorithmVersion == this.algorithmVersion);
}

class SrsStatesCompanion extends UpdateCompanion<SrsState> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> wordId;
  final Value<double> stability;
  final Value<double> difficulty;
  final Value<int> intervalDays;
  final Value<int> repetitions;
  final Value<int> lapses;
  final Value<int?> lastReviewAtUtcMs;
  final Value<int> dueAtUtcMs;
  final Value<int> algorithmVersion;
  final Value<int> rowid;
  const SrsStatesCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.wordId = const Value.absent(),
    this.stability = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.intervalDays = const Value.absent(),
    this.repetitions = const Value.absent(),
    this.lapses = const Value.absent(),
    this.lastReviewAtUtcMs = const Value.absent(),
    this.dueAtUtcMs = const Value.absent(),
    this.algorithmVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SrsStatesCompanion.insert({
    required String id,
    required String ownerId,
    required String wordId,
    this.stability = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.intervalDays = const Value.absent(),
    this.repetitions = const Value.absent(),
    this.lapses = const Value.absent(),
    this.lastReviewAtUtcMs = const Value.absent(),
    required int dueAtUtcMs,
    required int algorithmVersion,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       wordId = Value(wordId),
       dueAtUtcMs = Value(dueAtUtcMs),
       algorithmVersion = Value(algorithmVersion);
  static Insertable<SrsState> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? wordId,
    Expression<double>? stability,
    Expression<double>? difficulty,
    Expression<int>? intervalDays,
    Expression<int>? repetitions,
    Expression<int>? lapses,
    Expression<int>? lastReviewAtUtcMs,
    Expression<int>? dueAtUtcMs,
    Expression<int>? algorithmVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (wordId != null) 'word_id': wordId,
      if (stability != null) 'stability': stability,
      if (difficulty != null) 'difficulty': difficulty,
      if (intervalDays != null) 'interval_days': intervalDays,
      if (repetitions != null) 'repetitions': repetitions,
      if (lapses != null) 'lapses': lapses,
      if (lastReviewAtUtcMs != null) 'last_review_at_utc_ms': lastReviewAtUtcMs,
      if (dueAtUtcMs != null) 'due_at_utc_ms': dueAtUtcMs,
      if (algorithmVersion != null) 'algorithm_version': algorithmVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SrsStatesCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? wordId,
    Value<double>? stability,
    Value<double>? difficulty,
    Value<int>? intervalDays,
    Value<int>? repetitions,
    Value<int>? lapses,
    Value<int?>? lastReviewAtUtcMs,
    Value<int>? dueAtUtcMs,
    Value<int>? algorithmVersion,
    Value<int>? rowid,
  }) {
    return SrsStatesCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      wordId: wordId ?? this.wordId,
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      intervalDays: intervalDays ?? this.intervalDays,
      repetitions: repetitions ?? this.repetitions,
      lapses: lapses ?? this.lapses,
      lastReviewAtUtcMs: lastReviewAtUtcMs ?? this.lastReviewAtUtcMs,
      dueAtUtcMs: dueAtUtcMs ?? this.dueAtUtcMs,
      algorithmVersion: algorithmVersion ?? this.algorithmVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (wordId.present) {
      map['word_id'] = Variable<String>(wordId.value);
    }
    if (stability.present) {
      map['stability'] = Variable<double>(stability.value);
    }
    if (difficulty.present) {
      map['difficulty'] = Variable<double>(difficulty.value);
    }
    if (intervalDays.present) {
      map['interval_days'] = Variable<int>(intervalDays.value);
    }
    if (repetitions.present) {
      map['repetitions'] = Variable<int>(repetitions.value);
    }
    if (lapses.present) {
      map['lapses'] = Variable<int>(lapses.value);
    }
    if (lastReviewAtUtcMs.present) {
      map['last_review_at_utc_ms'] = Variable<int>(lastReviewAtUtcMs.value);
    }
    if (dueAtUtcMs.present) {
      map['due_at_utc_ms'] = Variable<int>(dueAtUtcMs.value);
    }
    if (algorithmVersion.present) {
      map['algorithm_version'] = Variable<int>(algorithmVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SrsStatesCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('wordId: $wordId, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('intervalDays: $intervalDays, ')
          ..write('repetitions: $repetitions, ')
          ..write('lapses: $lapses, ')
          ..write('lastReviewAtUtcMs: $lastReviewAtUtcMs, ')
          ..write('dueAtUtcMs: $dueAtUtcMs, ')
          ..write('algorithmVersion: $algorithmVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadingProgressEntriesTable extends ReadingProgressEntries
    with TableInfo<$ReadingProgressEntriesTable, ReadingProgressEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingProgressEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentRevisionMeta = const VerificationMeta(
    'documentRevision',
  );
  @override
  late final GeneratedColumn<int> documentRevision = GeneratedColumn<int>(
    'document_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _lastPositionMeta = const VerificationMeta(
    'lastPosition',
  );
  @override
  late final GeneratedColumn<int> lastPosition = GeneratedColumn<int>(
    'last_position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isCompletedMeta = const VerificationMeta(
    'isCompleted',
  );
  @override
  late final GeneratedColumn<bool> isCompleted = GeneratedColumn<bool>(
    'is_completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtUtcMsMeta = const VerificationMeta(
    'updatedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtcMs = GeneratedColumn<int>(
    'updated_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    documentId,
    documentRevision,
    lastPosition,
    isCompleted,
    updatedAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_progress_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingProgressEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('document_revision')) {
      context.handle(
        _documentRevisionMeta,
        documentRevision.isAcceptableOrUnknown(
          data['document_revision']!,
          _documentRevisionMeta,
        ),
      );
    }
    if (data.containsKey('last_position')) {
      context.handle(
        _lastPositionMeta,
        lastPosition.isAcceptableOrUnknown(
          data['last_position']!,
          _lastPositionMeta,
        ),
      );
    }
    if (data.containsKey('is_completed')) {
      context.handle(
        _isCompletedMeta,
        isCompleted.isAcceptableOrUnknown(
          data['is_completed']!,
          _isCompletedMeta,
        ),
      );
    }
    if (data.containsKey('updated_at_utc_ms')) {
      context.handle(
        _updatedAtUtcMsMeta,
        updatedAtUtcMs.isAcceptableOrUnknown(
          data['updated_at_utc_ms']!,
          _updatedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerId, documentId, documentRevision},
  ];
  @override
  ReadingProgressEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingProgressEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      )!,
      documentRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}document_revision'],
      )!,
      lastPosition: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_position'],
      )!,
      isCompleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_completed'],
      )!,
      updatedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc_ms'],
      )!,
    );
  }

  @override
  $ReadingProgressEntriesTable createAlias(String alias) {
    return $ReadingProgressEntriesTable(attachedDatabase, alias);
  }
}

class ReadingProgressEntry extends DataClass
    implements Insertable<ReadingProgressEntry> {
  final String id;
  final String ownerId;
  final String documentId;
  final int documentRevision;
  final int lastPosition;
  final bool isCompleted;
  final int updatedAtUtcMs;
  const ReadingProgressEntry({
    required this.id,
    required this.ownerId,
    required this.documentId,
    required this.documentRevision,
    required this.lastPosition,
    required this.isCompleted,
    required this.updatedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['document_id'] = Variable<String>(documentId);
    map['document_revision'] = Variable<int>(documentRevision);
    map['last_position'] = Variable<int>(lastPosition);
    map['is_completed'] = Variable<bool>(isCompleted);
    map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs);
    return map;
  }

  ReadingProgressEntriesCompanion toCompanion(bool nullToAbsent) {
    return ReadingProgressEntriesCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      documentId: Value(documentId),
      documentRevision: Value(documentRevision),
      lastPosition: Value(lastPosition),
      isCompleted: Value(isCompleted),
      updatedAtUtcMs: Value(updatedAtUtcMs),
    );
  }

  factory ReadingProgressEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingProgressEntry(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      documentId: serializer.fromJson<String>(json['documentId']),
      documentRevision: serializer.fromJson<int>(json['documentRevision']),
      lastPosition: serializer.fromJson<int>(json['lastPosition']),
      isCompleted: serializer.fromJson<bool>(json['isCompleted']),
      updatedAtUtcMs: serializer.fromJson<int>(json['updatedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'documentId': serializer.toJson<String>(documentId),
      'documentRevision': serializer.toJson<int>(documentRevision),
      'lastPosition': serializer.toJson<int>(lastPosition),
      'isCompleted': serializer.toJson<bool>(isCompleted),
      'updatedAtUtcMs': serializer.toJson<int>(updatedAtUtcMs),
    };
  }

  ReadingProgressEntry copyWith({
    String? id,
    String? ownerId,
    String? documentId,
    int? documentRevision,
    int? lastPosition,
    bool? isCompleted,
    int? updatedAtUtcMs,
  }) => ReadingProgressEntry(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    documentId: documentId ?? this.documentId,
    documentRevision: documentRevision ?? this.documentRevision,
    lastPosition: lastPosition ?? this.lastPosition,
    isCompleted: isCompleted ?? this.isCompleted,
    updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
  );
  ReadingProgressEntry copyWithCompanion(ReadingProgressEntriesCompanion data) {
    return ReadingProgressEntry(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      documentRevision: data.documentRevision.present
          ? data.documentRevision.value
          : this.documentRevision,
      lastPosition: data.lastPosition.present
          ? data.lastPosition.value
          : this.lastPosition,
      isCompleted: data.isCompleted.present
          ? data.isCompleted.value
          : this.isCompleted,
      updatedAtUtcMs: data.updatedAtUtcMs.present
          ? data.updatedAtUtcMs.value
          : this.updatedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressEntry(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('documentId: $documentId, ')
          ..write('documentRevision: $documentRevision, ')
          ..write('lastPosition: $lastPosition, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    documentId,
    documentRevision,
    lastPosition,
    isCompleted,
    updatedAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingProgressEntry &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.documentId == this.documentId &&
          other.documentRevision == this.documentRevision &&
          other.lastPosition == this.lastPosition &&
          other.isCompleted == this.isCompleted &&
          other.updatedAtUtcMs == this.updatedAtUtcMs);
}

class ReadingProgressEntriesCompanion
    extends UpdateCompanion<ReadingProgressEntry> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> documentId;
  final Value<int> documentRevision;
  final Value<int> lastPosition;
  final Value<bool> isCompleted;
  final Value<int> updatedAtUtcMs;
  final Value<int> rowid;
  const ReadingProgressEntriesCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.documentId = const Value.absent(),
    this.documentRevision = const Value.absent(),
    this.lastPosition = const Value.absent(),
    this.isCompleted = const Value.absent(),
    this.updatedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingProgressEntriesCompanion.insert({
    required String id,
    required String ownerId,
    required String documentId,
    this.documentRevision = const Value.absent(),
    this.lastPosition = const Value.absent(),
    this.isCompleted = const Value.absent(),
    required int updatedAtUtcMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       documentId = Value(documentId),
       updatedAtUtcMs = Value(updatedAtUtcMs);
  static Insertable<ReadingProgressEntry> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? documentId,
    Expression<int>? documentRevision,
    Expression<int>? lastPosition,
    Expression<bool>? isCompleted,
    Expression<int>? updatedAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (documentId != null) 'document_id': documentId,
      if (documentRevision != null) 'document_revision': documentRevision,
      if (lastPosition != null) 'last_position': lastPosition,
      if (isCompleted != null) 'is_completed': isCompleted,
      if (updatedAtUtcMs != null) 'updated_at_utc_ms': updatedAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingProgressEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? documentId,
    Value<int>? documentRevision,
    Value<int>? lastPosition,
    Value<bool>? isCompleted,
    Value<int>? updatedAtUtcMs,
    Value<int>? rowid,
  }) {
    return ReadingProgressEntriesCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      documentId: documentId ?? this.documentId,
      documentRevision: documentRevision ?? this.documentRevision,
      lastPosition: lastPosition ?? this.lastPosition,
      isCompleted: isCompleted ?? this.isCompleted,
      updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (documentRevision.present) {
      map['document_revision'] = Variable<int>(documentRevision.value);
    }
    if (lastPosition.present) {
      map['last_position'] = Variable<int>(lastPosition.value);
    }
    if (isCompleted.present) {
      map['is_completed'] = Variable<bool>(isCompleted.value);
    }
    if (updatedAtUtcMs.present) {
      map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressEntriesCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('documentId: $documentId, ')
          ..write('documentRevision: $documentRevision, ')
          ..write('lastPosition: $lastPosition, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadingEventsTable extends ReadingEvents
    with TableInfo<$ReadingEventsTable, ReadingEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentRevisionMeta = const VerificationMeta(
    'documentRevision',
  );
  @override
  late final GeneratedColumn<int> documentRevision = GeneratedColumn<int>(
    'document_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurredAtUtcMsMeta = const VerificationMeta(
    'occurredAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> occurredAtUtcMs = GeneratedColumn<int>(
    'occurred_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    documentId,
    documentRevision,
    eventType,
    position,
    occurredAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('document_revision')) {
      context.handle(
        _documentRevisionMeta,
        documentRevision.isAcceptableOrUnknown(
          data['document_revision']!,
          _documentRevisionMeta,
        ),
      );
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('occurred_at_utc_ms')) {
      context.handle(
        _occurredAtUtcMsMeta,
        occurredAtUtcMs.isAcceptableOrUnknown(
          data['occurred_at_utc_ms']!,
          _occurredAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReadingEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      )!,
      documentRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}document_revision'],
      )!,
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      ),
      occurredAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurred_at_utc_ms'],
      )!,
    );
  }

  @override
  $ReadingEventsTable createAlias(String alias) {
    return $ReadingEventsTable(attachedDatabase, alias);
  }
}

class ReadingEvent extends DataClass implements Insertable<ReadingEvent> {
  final String id;
  final String ownerId;
  final String documentId;
  final int documentRevision;
  final String eventType;
  final int? position;
  final int occurredAtUtcMs;
  const ReadingEvent({
    required this.id,
    required this.ownerId,
    required this.documentId,
    required this.documentRevision,
    required this.eventType,
    this.position,
    required this.occurredAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['document_id'] = Variable<String>(documentId);
    map['document_revision'] = Variable<int>(documentRevision);
    map['event_type'] = Variable<String>(eventType);
    if (!nullToAbsent || position != null) {
      map['position'] = Variable<int>(position);
    }
    map['occurred_at_utc_ms'] = Variable<int>(occurredAtUtcMs);
    return map;
  }

  ReadingEventsCompanion toCompanion(bool nullToAbsent) {
    return ReadingEventsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      documentId: Value(documentId),
      documentRevision: Value(documentRevision),
      eventType: Value(eventType),
      position: position == null && nullToAbsent
          ? const Value.absent()
          : Value(position),
      occurredAtUtcMs: Value(occurredAtUtcMs),
    );
  }

  factory ReadingEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingEvent(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      documentId: serializer.fromJson<String>(json['documentId']),
      documentRevision: serializer.fromJson<int>(json['documentRevision']),
      eventType: serializer.fromJson<String>(json['eventType']),
      position: serializer.fromJson<int?>(json['position']),
      occurredAtUtcMs: serializer.fromJson<int>(json['occurredAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'documentId': serializer.toJson<String>(documentId),
      'documentRevision': serializer.toJson<int>(documentRevision),
      'eventType': serializer.toJson<String>(eventType),
      'position': serializer.toJson<int?>(position),
      'occurredAtUtcMs': serializer.toJson<int>(occurredAtUtcMs),
    };
  }

  ReadingEvent copyWith({
    String? id,
    String? ownerId,
    String? documentId,
    int? documentRevision,
    String? eventType,
    Value<int?> position = const Value.absent(),
    int? occurredAtUtcMs,
  }) => ReadingEvent(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    documentId: documentId ?? this.documentId,
    documentRevision: documentRevision ?? this.documentRevision,
    eventType: eventType ?? this.eventType,
    position: position.present ? position.value : this.position,
    occurredAtUtcMs: occurredAtUtcMs ?? this.occurredAtUtcMs,
  );
  ReadingEvent copyWithCompanion(ReadingEventsCompanion data) {
    return ReadingEvent(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      documentRevision: data.documentRevision.present
          ? data.documentRevision.value
          : this.documentRevision,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      position: data.position.present ? data.position.value : this.position,
      occurredAtUtcMs: data.occurredAtUtcMs.present
          ? data.occurredAtUtcMs.value
          : this.occurredAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingEvent(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('documentId: $documentId, ')
          ..write('documentRevision: $documentRevision, ')
          ..write('eventType: $eventType, ')
          ..write('position: $position, ')
          ..write('occurredAtUtcMs: $occurredAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    documentId,
    documentRevision,
    eventType,
    position,
    occurredAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingEvent &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.documentId == this.documentId &&
          other.documentRevision == this.documentRevision &&
          other.eventType == this.eventType &&
          other.position == this.position &&
          other.occurredAtUtcMs == this.occurredAtUtcMs);
}

class ReadingEventsCompanion extends UpdateCompanion<ReadingEvent> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> documentId;
  final Value<int> documentRevision;
  final Value<String> eventType;
  final Value<int?> position;
  final Value<int> occurredAtUtcMs;
  final Value<int> rowid;
  const ReadingEventsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.documentId = const Value.absent(),
    this.documentRevision = const Value.absent(),
    this.eventType = const Value.absent(),
    this.position = const Value.absent(),
    this.occurredAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingEventsCompanion.insert({
    required String id,
    required String ownerId,
    required String documentId,
    this.documentRevision = const Value.absent(),
    required String eventType,
    this.position = const Value.absent(),
    required int occurredAtUtcMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       documentId = Value(documentId),
       eventType = Value(eventType),
       occurredAtUtcMs = Value(occurredAtUtcMs);
  static Insertable<ReadingEvent> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? documentId,
    Expression<int>? documentRevision,
    Expression<String>? eventType,
    Expression<int>? position,
    Expression<int>? occurredAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (documentId != null) 'document_id': documentId,
      if (documentRevision != null) 'document_revision': documentRevision,
      if (eventType != null) 'event_type': eventType,
      if (position != null) 'position': position,
      if (occurredAtUtcMs != null) 'occurred_at_utc_ms': occurredAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? documentId,
    Value<int>? documentRevision,
    Value<String>? eventType,
    Value<int?>? position,
    Value<int>? occurredAtUtcMs,
    Value<int>? rowid,
  }) {
    return ReadingEventsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      documentId: documentId ?? this.documentId,
      documentRevision: documentRevision ?? this.documentRevision,
      eventType: eventType ?? this.eventType,
      position: position ?? this.position,
      occurredAtUtcMs: occurredAtUtcMs ?? this.occurredAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (documentRevision.present) {
      map['document_revision'] = Variable<int>(documentRevision.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (occurredAtUtcMs.present) {
      map['occurred_at_utc_ms'] = Variable<int>(occurredAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingEventsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('documentId: $documentId, ')
          ..write('documentRevision: $documentRevision, ')
          ..write('eventType: $eventType, ')
          ..write('position: $position, ')
          ..write('occurredAtUtcMs: $occurredAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PointsLedgerEntriesTable extends PointsLedgerEntries
    with TableInfo<$PointsLedgerEntriesTable, PointsLedgerEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PointsLedgerEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryTypeMeta = const VerificationMeta(
    'entryType',
  );
  @override
  late final GeneratedColumn<String> entryType = GeneratedColumn<String>(
    'entry_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceEventIdMeta = const VerificationMeta(
    'sourceEventId',
  );
  @override
  late final GeneratedColumn<String> sourceEventId = GeneratedColumn<String>(
    'source_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurredAtUtcMsMeta = const VerificationMeta(
    'occurredAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> occurredAtUtcMs = GeneratedColumn<int>(
    'occurred_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    idempotencyKey,
    entryType,
    amount,
    sourceEventId,
    occurredAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'points_ledger_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<PointsLedgerEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('entry_type')) {
      context.handle(
        _entryTypeMeta,
        entryType.isAcceptableOrUnknown(data['entry_type']!, _entryTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entryTypeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('source_event_id')) {
      context.handle(
        _sourceEventIdMeta,
        sourceEventId.isAcceptableOrUnknown(
          data['source_event_id']!,
          _sourceEventIdMeta,
        ),
      );
    }
    if (data.containsKey('occurred_at_utc_ms')) {
      context.handle(
        _occurredAtUtcMsMeta,
        occurredAtUtcMs.isAcceptableOrUnknown(
          data['occurred_at_utc_ms']!,
          _occurredAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerId, idempotencyKey},
  ];
  @override
  PointsLedgerEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PointsLedgerEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      entryType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_type'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      sourceEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_event_id'],
      ),
      occurredAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurred_at_utc_ms'],
      )!,
    );
  }

  @override
  $PointsLedgerEntriesTable createAlias(String alias) {
    return $PointsLedgerEntriesTable(attachedDatabase, alias);
  }
}

class PointsLedgerEntry extends DataClass
    implements Insertable<PointsLedgerEntry> {
  final String id;
  final String ownerId;
  final String idempotencyKey;
  final String entryType;
  final int amount;
  final String? sourceEventId;
  final int occurredAtUtcMs;
  const PointsLedgerEntry({
    required this.id,
    required this.ownerId,
    required this.idempotencyKey,
    required this.entryType,
    required this.amount,
    this.sourceEventId,
    required this.occurredAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['entry_type'] = Variable<String>(entryType);
    map['amount'] = Variable<int>(amount);
    if (!nullToAbsent || sourceEventId != null) {
      map['source_event_id'] = Variable<String>(sourceEventId);
    }
    map['occurred_at_utc_ms'] = Variable<int>(occurredAtUtcMs);
    return map;
  }

  PointsLedgerEntriesCompanion toCompanion(bool nullToAbsent) {
    return PointsLedgerEntriesCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      idempotencyKey: Value(idempotencyKey),
      entryType: Value(entryType),
      amount: Value(amount),
      sourceEventId: sourceEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceEventId),
      occurredAtUtcMs: Value(occurredAtUtcMs),
    );
  }

  factory PointsLedgerEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PointsLedgerEntry(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      entryType: serializer.fromJson<String>(json['entryType']),
      amount: serializer.fromJson<int>(json['amount']),
      sourceEventId: serializer.fromJson<String?>(json['sourceEventId']),
      occurredAtUtcMs: serializer.fromJson<int>(json['occurredAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'entryType': serializer.toJson<String>(entryType),
      'amount': serializer.toJson<int>(amount),
      'sourceEventId': serializer.toJson<String?>(sourceEventId),
      'occurredAtUtcMs': serializer.toJson<int>(occurredAtUtcMs),
    };
  }

  PointsLedgerEntry copyWith({
    String? id,
    String? ownerId,
    String? idempotencyKey,
    String? entryType,
    int? amount,
    Value<String?> sourceEventId = const Value.absent(),
    int? occurredAtUtcMs,
  }) => PointsLedgerEntry(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    entryType: entryType ?? this.entryType,
    amount: amount ?? this.amount,
    sourceEventId: sourceEventId.present
        ? sourceEventId.value
        : this.sourceEventId,
    occurredAtUtcMs: occurredAtUtcMs ?? this.occurredAtUtcMs,
  );
  PointsLedgerEntry copyWithCompanion(PointsLedgerEntriesCompanion data) {
    return PointsLedgerEntry(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      entryType: data.entryType.present ? data.entryType.value : this.entryType,
      amount: data.amount.present ? data.amount.value : this.amount,
      sourceEventId: data.sourceEventId.present
          ? data.sourceEventId.value
          : this.sourceEventId,
      occurredAtUtcMs: data.occurredAtUtcMs.present
          ? data.occurredAtUtcMs.value
          : this.occurredAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PointsLedgerEntry(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('entryType: $entryType, ')
          ..write('amount: $amount, ')
          ..write('sourceEventId: $sourceEventId, ')
          ..write('occurredAtUtcMs: $occurredAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    idempotencyKey,
    entryType,
    amount,
    sourceEventId,
    occurredAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PointsLedgerEntry &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.idempotencyKey == this.idempotencyKey &&
          other.entryType == this.entryType &&
          other.amount == this.amount &&
          other.sourceEventId == this.sourceEventId &&
          other.occurredAtUtcMs == this.occurredAtUtcMs);
}

class PointsLedgerEntriesCompanion extends UpdateCompanion<PointsLedgerEntry> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> idempotencyKey;
  final Value<String> entryType;
  final Value<int> amount;
  final Value<String?> sourceEventId;
  final Value<int> occurredAtUtcMs;
  final Value<int> rowid;
  const PointsLedgerEntriesCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.entryType = const Value.absent(),
    this.amount = const Value.absent(),
    this.sourceEventId = const Value.absent(),
    this.occurredAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PointsLedgerEntriesCompanion.insert({
    required String id,
    required String ownerId,
    required String idempotencyKey,
    required String entryType,
    required int amount,
    this.sourceEventId = const Value.absent(),
    required int occurredAtUtcMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       idempotencyKey = Value(idempotencyKey),
       entryType = Value(entryType),
       amount = Value(amount),
       occurredAtUtcMs = Value(occurredAtUtcMs);
  static Insertable<PointsLedgerEntry> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? idempotencyKey,
    Expression<String>? entryType,
    Expression<int>? amount,
    Expression<String>? sourceEventId,
    Expression<int>? occurredAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (entryType != null) 'entry_type': entryType,
      if (amount != null) 'amount': amount,
      if (sourceEventId != null) 'source_event_id': sourceEventId,
      if (occurredAtUtcMs != null) 'occurred_at_utc_ms': occurredAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PointsLedgerEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? idempotencyKey,
    Value<String>? entryType,
    Value<int>? amount,
    Value<String?>? sourceEventId,
    Value<int>? occurredAtUtcMs,
    Value<int>? rowid,
  }) {
    return PointsLedgerEntriesCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      entryType: entryType ?? this.entryType,
      amount: amount ?? this.amount,
      sourceEventId: sourceEventId ?? this.sourceEventId,
      occurredAtUtcMs: occurredAtUtcMs ?? this.occurredAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (entryType.present) {
      map['entry_type'] = Variable<String>(entryType.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (sourceEventId.present) {
      map['source_event_id'] = Variable<String>(sourceEventId.value);
    }
    if (occurredAtUtcMs.present) {
      map['occurred_at_utc_ms'] = Variable<int>(occurredAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PointsLedgerEntriesCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('entryType: $entryType, ')
          ..write('amount: $amount, ')
          ..write('sourceEventId: $sourceEventId, ')
          ..write('occurredAtUtcMs: $occurredAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AchievementUnlocksTable extends AchievementUnlocks
    with TableInfo<$AchievementUnlocksTable, AchievementUnlock> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AchievementUnlocksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _achievementIdMeta = const VerificationMeta(
    'achievementId',
  );
  @override
  late final GeneratedColumn<String> achievementId = GeneratedColumn<String>(
    'achievement_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _definitionVersionMeta = const VerificationMeta(
    'definitionVersion',
  );
  @override
  late final GeneratedColumn<int> definitionVersion = GeneratedColumn<int>(
    'definition_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceEventIdMeta = const VerificationMeta(
    'sourceEventId',
  );
  @override
  late final GeneratedColumn<String> sourceEventId = GeneratedColumn<String>(
    'source_event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unlockedAtUtcMsMeta = const VerificationMeta(
    'unlockedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> unlockedAtUtcMs = GeneratedColumn<int>(
    'unlocked_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    achievementId,
    definitionVersion,
    sourceEventId,
    unlockedAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'achievement_unlocks';
  @override
  VerificationContext validateIntegrity(
    Insertable<AchievementUnlock> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('achievement_id')) {
      context.handle(
        _achievementIdMeta,
        achievementId.isAcceptableOrUnknown(
          data['achievement_id']!,
          _achievementIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_achievementIdMeta);
    }
    if (data.containsKey('definition_version')) {
      context.handle(
        _definitionVersionMeta,
        definitionVersion.isAcceptableOrUnknown(
          data['definition_version']!,
          _definitionVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_definitionVersionMeta);
    }
    if (data.containsKey('source_event_id')) {
      context.handle(
        _sourceEventIdMeta,
        sourceEventId.isAcceptableOrUnknown(
          data['source_event_id']!,
          _sourceEventIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceEventIdMeta);
    }
    if (data.containsKey('unlocked_at_utc_ms')) {
      context.handle(
        _unlockedAtUtcMsMeta,
        unlockedAtUtcMs.isAcceptableOrUnknown(
          data['unlocked_at_utc_ms']!,
          _unlockedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_unlockedAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerId, achievementId, definitionVersion},
  ];
  @override
  AchievementUnlock map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AchievementUnlock(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      achievementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}achievement_id'],
      )!,
      definitionVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}definition_version'],
      )!,
      sourceEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_event_id'],
      )!,
      unlockedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unlocked_at_utc_ms'],
      )!,
    );
  }

  @override
  $AchievementUnlocksTable createAlias(String alias) {
    return $AchievementUnlocksTable(attachedDatabase, alias);
  }
}

class AchievementUnlock extends DataClass
    implements Insertable<AchievementUnlock> {
  final String id;
  final String ownerId;
  final String achievementId;
  final int definitionVersion;
  final String sourceEventId;
  final int unlockedAtUtcMs;
  const AchievementUnlock({
    required this.id,
    required this.ownerId,
    required this.achievementId,
    required this.definitionVersion,
    required this.sourceEventId,
    required this.unlockedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['achievement_id'] = Variable<String>(achievementId);
    map['definition_version'] = Variable<int>(definitionVersion);
    map['source_event_id'] = Variable<String>(sourceEventId);
    map['unlocked_at_utc_ms'] = Variable<int>(unlockedAtUtcMs);
    return map;
  }

  AchievementUnlocksCompanion toCompanion(bool nullToAbsent) {
    return AchievementUnlocksCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      achievementId: Value(achievementId),
      definitionVersion: Value(definitionVersion),
      sourceEventId: Value(sourceEventId),
      unlockedAtUtcMs: Value(unlockedAtUtcMs),
    );
  }

  factory AchievementUnlock.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AchievementUnlock(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      achievementId: serializer.fromJson<String>(json['achievementId']),
      definitionVersion: serializer.fromJson<int>(json['definitionVersion']),
      sourceEventId: serializer.fromJson<String>(json['sourceEventId']),
      unlockedAtUtcMs: serializer.fromJson<int>(json['unlockedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'achievementId': serializer.toJson<String>(achievementId),
      'definitionVersion': serializer.toJson<int>(definitionVersion),
      'sourceEventId': serializer.toJson<String>(sourceEventId),
      'unlockedAtUtcMs': serializer.toJson<int>(unlockedAtUtcMs),
    };
  }

  AchievementUnlock copyWith({
    String? id,
    String? ownerId,
    String? achievementId,
    int? definitionVersion,
    String? sourceEventId,
    int? unlockedAtUtcMs,
  }) => AchievementUnlock(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    achievementId: achievementId ?? this.achievementId,
    definitionVersion: definitionVersion ?? this.definitionVersion,
    sourceEventId: sourceEventId ?? this.sourceEventId,
    unlockedAtUtcMs: unlockedAtUtcMs ?? this.unlockedAtUtcMs,
  );
  AchievementUnlock copyWithCompanion(AchievementUnlocksCompanion data) {
    return AchievementUnlock(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      achievementId: data.achievementId.present
          ? data.achievementId.value
          : this.achievementId,
      definitionVersion: data.definitionVersion.present
          ? data.definitionVersion.value
          : this.definitionVersion,
      sourceEventId: data.sourceEventId.present
          ? data.sourceEventId.value
          : this.sourceEventId,
      unlockedAtUtcMs: data.unlockedAtUtcMs.present
          ? data.unlockedAtUtcMs.value
          : this.unlockedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AchievementUnlock(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('achievementId: $achievementId, ')
          ..write('definitionVersion: $definitionVersion, ')
          ..write('sourceEventId: $sourceEventId, ')
          ..write('unlockedAtUtcMs: $unlockedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    achievementId,
    definitionVersion,
    sourceEventId,
    unlockedAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AchievementUnlock &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.achievementId == this.achievementId &&
          other.definitionVersion == this.definitionVersion &&
          other.sourceEventId == this.sourceEventId &&
          other.unlockedAtUtcMs == this.unlockedAtUtcMs);
}

class AchievementUnlocksCompanion extends UpdateCompanion<AchievementUnlock> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> achievementId;
  final Value<int> definitionVersion;
  final Value<String> sourceEventId;
  final Value<int> unlockedAtUtcMs;
  final Value<int> rowid;
  const AchievementUnlocksCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.achievementId = const Value.absent(),
    this.definitionVersion = const Value.absent(),
    this.sourceEventId = const Value.absent(),
    this.unlockedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AchievementUnlocksCompanion.insert({
    required String id,
    required String ownerId,
    required String achievementId,
    required int definitionVersion,
    required String sourceEventId,
    required int unlockedAtUtcMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       achievementId = Value(achievementId),
       definitionVersion = Value(definitionVersion),
       sourceEventId = Value(sourceEventId),
       unlockedAtUtcMs = Value(unlockedAtUtcMs);
  static Insertable<AchievementUnlock> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? achievementId,
    Expression<int>? definitionVersion,
    Expression<String>? sourceEventId,
    Expression<int>? unlockedAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (achievementId != null) 'achievement_id': achievementId,
      if (definitionVersion != null) 'definition_version': definitionVersion,
      if (sourceEventId != null) 'source_event_id': sourceEventId,
      if (unlockedAtUtcMs != null) 'unlocked_at_utc_ms': unlockedAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AchievementUnlocksCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? achievementId,
    Value<int>? definitionVersion,
    Value<String>? sourceEventId,
    Value<int>? unlockedAtUtcMs,
    Value<int>? rowid,
  }) {
    return AchievementUnlocksCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      achievementId: achievementId ?? this.achievementId,
      definitionVersion: definitionVersion ?? this.definitionVersion,
      sourceEventId: sourceEventId ?? this.sourceEventId,
      unlockedAtUtcMs: unlockedAtUtcMs ?? this.unlockedAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (achievementId.present) {
      map['achievement_id'] = Variable<String>(achievementId.value);
    }
    if (definitionVersion.present) {
      map['definition_version'] = Variable<int>(definitionVersion.value);
    }
    if (sourceEventId.present) {
      map['source_event_id'] = Variable<String>(sourceEventId.value);
    }
    if (unlockedAtUtcMs.present) {
      map['unlocked_at_utc_ms'] = Variable<int>(unlockedAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AchievementUnlocksCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('achievementId: $achievementId, ')
          ..write('definitionVersion: $definitionVersion, ')
          ..write('sourceEventId: $sourceEventId, ')
          ..write('unlockedAtUtcMs: $unlockedAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RewardTransactionsTable extends RewardTransactions
    with TableInfo<$RewardTransactionsTable, RewardTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RewardTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transactionTypeMeta = const VerificationMeta(
    'transactionType',
  );
  @override
  late final GeneratedColumn<String> transactionType = GeneratedColumn<String>(
    'transaction_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _catalogVersionMeta = const VerificationMeta(
    'catalogVersion',
  );
  @override
  late final GeneratedColumn<int> catalogVersion = GeneratedColumn<int>(
    'catalog_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceEventIdMeta = const VerificationMeta(
    'sourceEventId',
  );
  @override
  late final GeneratedColumn<String> sourceEventId = GeneratedColumn<String>(
    'source_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurredAtUtcMsMeta = const VerificationMeta(
    'occurredAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> occurredAtUtcMs = GeneratedColumn<int>(
    'occurred_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    idempotencyKey,
    transactionType,
    amount,
    itemId,
    catalogVersion,
    sourceEventId,
    occurredAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reward_transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<RewardTransaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('transaction_type')) {
      context.handle(
        _transactionTypeMeta,
        transactionType.isAcceptableOrUnknown(
          data['transaction_type']!,
          _transactionTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transactionTypeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    }
    if (data.containsKey('catalog_version')) {
      context.handle(
        _catalogVersionMeta,
        catalogVersion.isAcceptableOrUnknown(
          data['catalog_version']!,
          _catalogVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_catalogVersionMeta);
    }
    if (data.containsKey('source_event_id')) {
      context.handle(
        _sourceEventIdMeta,
        sourceEventId.isAcceptableOrUnknown(
          data['source_event_id']!,
          _sourceEventIdMeta,
        ),
      );
    }
    if (data.containsKey('occurred_at_utc_ms')) {
      context.handle(
        _occurredAtUtcMsMeta,
        occurredAtUtcMs.isAcceptableOrUnknown(
          data['occurred_at_utc_ms']!,
          _occurredAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerId, idempotencyKey},
  ];
  @override
  RewardTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RewardTransaction(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      transactionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transaction_type'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      ),
      catalogVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}catalog_version'],
      )!,
      sourceEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_event_id'],
      ),
      occurredAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurred_at_utc_ms'],
      )!,
    );
  }

  @override
  $RewardTransactionsTable createAlias(String alias) {
    return $RewardTransactionsTable(attachedDatabase, alias);
  }
}

class RewardTransaction extends DataClass
    implements Insertable<RewardTransaction> {
  final String id;
  final String ownerId;
  final String idempotencyKey;
  final String transactionType;
  final int amount;
  final String? itemId;
  final int catalogVersion;
  final String? sourceEventId;
  final int occurredAtUtcMs;
  const RewardTransaction({
    required this.id,
    required this.ownerId,
    required this.idempotencyKey,
    required this.transactionType,
    required this.amount,
    this.itemId,
    required this.catalogVersion,
    this.sourceEventId,
    required this.occurredAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['transaction_type'] = Variable<String>(transactionType);
    map['amount'] = Variable<int>(amount);
    if (!nullToAbsent || itemId != null) {
      map['item_id'] = Variable<String>(itemId);
    }
    map['catalog_version'] = Variable<int>(catalogVersion);
    if (!nullToAbsent || sourceEventId != null) {
      map['source_event_id'] = Variable<String>(sourceEventId);
    }
    map['occurred_at_utc_ms'] = Variable<int>(occurredAtUtcMs);
    return map;
  }

  RewardTransactionsCompanion toCompanion(bool nullToAbsent) {
    return RewardTransactionsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      idempotencyKey: Value(idempotencyKey),
      transactionType: Value(transactionType),
      amount: Value(amount),
      itemId: itemId == null && nullToAbsent
          ? const Value.absent()
          : Value(itemId),
      catalogVersion: Value(catalogVersion),
      sourceEventId: sourceEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceEventId),
      occurredAtUtcMs: Value(occurredAtUtcMs),
    );
  }

  factory RewardTransaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RewardTransaction(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      transactionType: serializer.fromJson<String>(json['transactionType']),
      amount: serializer.fromJson<int>(json['amount']),
      itemId: serializer.fromJson<String?>(json['itemId']),
      catalogVersion: serializer.fromJson<int>(json['catalogVersion']),
      sourceEventId: serializer.fromJson<String?>(json['sourceEventId']),
      occurredAtUtcMs: serializer.fromJson<int>(json['occurredAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'transactionType': serializer.toJson<String>(transactionType),
      'amount': serializer.toJson<int>(amount),
      'itemId': serializer.toJson<String?>(itemId),
      'catalogVersion': serializer.toJson<int>(catalogVersion),
      'sourceEventId': serializer.toJson<String?>(sourceEventId),
      'occurredAtUtcMs': serializer.toJson<int>(occurredAtUtcMs),
    };
  }

  RewardTransaction copyWith({
    String? id,
    String? ownerId,
    String? idempotencyKey,
    String? transactionType,
    int? amount,
    Value<String?> itemId = const Value.absent(),
    int? catalogVersion,
    Value<String?> sourceEventId = const Value.absent(),
    int? occurredAtUtcMs,
  }) => RewardTransaction(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    transactionType: transactionType ?? this.transactionType,
    amount: amount ?? this.amount,
    itemId: itemId.present ? itemId.value : this.itemId,
    catalogVersion: catalogVersion ?? this.catalogVersion,
    sourceEventId: sourceEventId.present
        ? sourceEventId.value
        : this.sourceEventId,
    occurredAtUtcMs: occurredAtUtcMs ?? this.occurredAtUtcMs,
  );
  RewardTransaction copyWithCompanion(RewardTransactionsCompanion data) {
    return RewardTransaction(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      transactionType: data.transactionType.present
          ? data.transactionType.value
          : this.transactionType,
      amount: data.amount.present ? data.amount.value : this.amount,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      catalogVersion: data.catalogVersion.present
          ? data.catalogVersion.value
          : this.catalogVersion,
      sourceEventId: data.sourceEventId.present
          ? data.sourceEventId.value
          : this.sourceEventId,
      occurredAtUtcMs: data.occurredAtUtcMs.present
          ? data.occurredAtUtcMs.value
          : this.occurredAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RewardTransaction(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('transactionType: $transactionType, ')
          ..write('amount: $amount, ')
          ..write('itemId: $itemId, ')
          ..write('catalogVersion: $catalogVersion, ')
          ..write('sourceEventId: $sourceEventId, ')
          ..write('occurredAtUtcMs: $occurredAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    idempotencyKey,
    transactionType,
    amount,
    itemId,
    catalogVersion,
    sourceEventId,
    occurredAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RewardTransaction &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.idempotencyKey == this.idempotencyKey &&
          other.transactionType == this.transactionType &&
          other.amount == this.amount &&
          other.itemId == this.itemId &&
          other.catalogVersion == this.catalogVersion &&
          other.sourceEventId == this.sourceEventId &&
          other.occurredAtUtcMs == this.occurredAtUtcMs);
}

class RewardTransactionsCompanion extends UpdateCompanion<RewardTransaction> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> idempotencyKey;
  final Value<String> transactionType;
  final Value<int> amount;
  final Value<String?> itemId;
  final Value<int> catalogVersion;
  final Value<String?> sourceEventId;
  final Value<int> occurredAtUtcMs;
  final Value<int> rowid;
  const RewardTransactionsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.transactionType = const Value.absent(),
    this.amount = const Value.absent(),
    this.itemId = const Value.absent(),
    this.catalogVersion = const Value.absent(),
    this.sourceEventId = const Value.absent(),
    this.occurredAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RewardTransactionsCompanion.insert({
    required String id,
    required String ownerId,
    required String idempotencyKey,
    required String transactionType,
    required int amount,
    this.itemId = const Value.absent(),
    required int catalogVersion,
    this.sourceEventId = const Value.absent(),
    required int occurredAtUtcMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       idempotencyKey = Value(idempotencyKey),
       transactionType = Value(transactionType),
       amount = Value(amount),
       catalogVersion = Value(catalogVersion),
       occurredAtUtcMs = Value(occurredAtUtcMs);
  static Insertable<RewardTransaction> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? idempotencyKey,
    Expression<String>? transactionType,
    Expression<int>? amount,
    Expression<String>? itemId,
    Expression<int>? catalogVersion,
    Expression<String>? sourceEventId,
    Expression<int>? occurredAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (transactionType != null) 'transaction_type': transactionType,
      if (amount != null) 'amount': amount,
      if (itemId != null) 'item_id': itemId,
      if (catalogVersion != null) 'catalog_version': catalogVersion,
      if (sourceEventId != null) 'source_event_id': sourceEventId,
      if (occurredAtUtcMs != null) 'occurred_at_utc_ms': occurredAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RewardTransactionsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? idempotencyKey,
    Value<String>? transactionType,
    Value<int>? amount,
    Value<String?>? itemId,
    Value<int>? catalogVersion,
    Value<String?>? sourceEventId,
    Value<int>? occurredAtUtcMs,
    Value<int>? rowid,
  }) {
    return RewardTransactionsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      transactionType: transactionType ?? this.transactionType,
      amount: amount ?? this.amount,
      itemId: itemId ?? this.itemId,
      catalogVersion: catalogVersion ?? this.catalogVersion,
      sourceEventId: sourceEventId ?? this.sourceEventId,
      occurredAtUtcMs: occurredAtUtcMs ?? this.occurredAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (transactionType.present) {
      map['transaction_type'] = Variable<String>(transactionType.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (catalogVersion.present) {
      map['catalog_version'] = Variable<int>(catalogVersion.value);
    }
    if (sourceEventId.present) {
      map['source_event_id'] = Variable<String>(sourceEventId.value);
    }
    if (occurredAtUtcMs.present) {
      map['occurred_at_utc_ms'] = Variable<int>(occurredAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RewardTransactionsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('transactionType: $transactionType, ')
          ..write('amount: $amount, ')
          ..write('itemId: $itemId, ')
          ..write('catalogVersion: $catalogVersion, ')
          ..write('sourceEventId: $sourceEventId, ')
          ..write('occurredAtUtcMs: $occurredAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OwnedRewardItemsTable extends OwnedRewardItems
    with TableInfo<$OwnedRewardItemsTable, OwnedRewardItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OwnedRewardItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _catalogVersionMeta = const VerificationMeta(
    'catalogVersion',
  );
  @override
  late final GeneratedColumn<int> catalogVersion = GeneratedColumn<int>(
    'catalog_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acquiredByTransactionIdMeta =
      const VerificationMeta('acquiredByTransactionId');
  @override
  late final GeneratedColumn<String> acquiredByTransactionId =
      GeneratedColumn<String>(
        'acquired_by_transaction_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES reward_transactions (id)',
        ),
      );
  static const VerificationMeta _acquiredAtUtcMsMeta = const VerificationMeta(
    'acquiredAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> acquiredAtUtcMs = GeneratedColumn<int>(
    'acquired_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    itemId,
    catalogVersion,
    acquiredByTransactionId,
    acquiredAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'owned_reward_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<OwnedRewardItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('catalog_version')) {
      context.handle(
        _catalogVersionMeta,
        catalogVersion.isAcceptableOrUnknown(
          data['catalog_version']!,
          _catalogVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_catalogVersionMeta);
    }
    if (data.containsKey('acquired_by_transaction_id')) {
      context.handle(
        _acquiredByTransactionIdMeta,
        acquiredByTransactionId.isAcceptableOrUnknown(
          data['acquired_by_transaction_id']!,
          _acquiredByTransactionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_acquiredByTransactionIdMeta);
    }
    if (data.containsKey('acquired_at_utc_ms')) {
      context.handle(
        _acquiredAtUtcMsMeta,
        acquiredAtUtcMs.isAcceptableOrUnknown(
          data['acquired_at_utc_ms']!,
          _acquiredAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_acquiredAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerId, itemId},
  ];
  @override
  OwnedRewardItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OwnedRewardItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      catalogVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}catalog_version'],
      )!,
      acquiredByTransactionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}acquired_by_transaction_id'],
      )!,
      acquiredAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}acquired_at_utc_ms'],
      )!,
    );
  }

  @override
  $OwnedRewardItemsTable createAlias(String alias) {
    return $OwnedRewardItemsTable(attachedDatabase, alias);
  }
}

class OwnedRewardItem extends DataClass implements Insertable<OwnedRewardItem> {
  final String id;
  final String ownerId;
  final String itemId;
  final int catalogVersion;
  final String acquiredByTransactionId;
  final int acquiredAtUtcMs;
  const OwnedRewardItem({
    required this.id,
    required this.ownerId,
    required this.itemId,
    required this.catalogVersion,
    required this.acquiredByTransactionId,
    required this.acquiredAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['item_id'] = Variable<String>(itemId);
    map['catalog_version'] = Variable<int>(catalogVersion);
    map['acquired_by_transaction_id'] = Variable<String>(
      acquiredByTransactionId,
    );
    map['acquired_at_utc_ms'] = Variable<int>(acquiredAtUtcMs);
    return map;
  }

  OwnedRewardItemsCompanion toCompanion(bool nullToAbsent) {
    return OwnedRewardItemsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      itemId: Value(itemId),
      catalogVersion: Value(catalogVersion),
      acquiredByTransactionId: Value(acquiredByTransactionId),
      acquiredAtUtcMs: Value(acquiredAtUtcMs),
    );
  }

  factory OwnedRewardItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OwnedRewardItem(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      catalogVersion: serializer.fromJson<int>(json['catalogVersion']),
      acquiredByTransactionId: serializer.fromJson<String>(
        json['acquiredByTransactionId'],
      ),
      acquiredAtUtcMs: serializer.fromJson<int>(json['acquiredAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'itemId': serializer.toJson<String>(itemId),
      'catalogVersion': serializer.toJson<int>(catalogVersion),
      'acquiredByTransactionId': serializer.toJson<String>(
        acquiredByTransactionId,
      ),
      'acquiredAtUtcMs': serializer.toJson<int>(acquiredAtUtcMs),
    };
  }

  OwnedRewardItem copyWith({
    String? id,
    String? ownerId,
    String? itemId,
    int? catalogVersion,
    String? acquiredByTransactionId,
    int? acquiredAtUtcMs,
  }) => OwnedRewardItem(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    itemId: itemId ?? this.itemId,
    catalogVersion: catalogVersion ?? this.catalogVersion,
    acquiredByTransactionId:
        acquiredByTransactionId ?? this.acquiredByTransactionId,
    acquiredAtUtcMs: acquiredAtUtcMs ?? this.acquiredAtUtcMs,
  );
  OwnedRewardItem copyWithCompanion(OwnedRewardItemsCompanion data) {
    return OwnedRewardItem(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      catalogVersion: data.catalogVersion.present
          ? data.catalogVersion.value
          : this.catalogVersion,
      acquiredByTransactionId: data.acquiredByTransactionId.present
          ? data.acquiredByTransactionId.value
          : this.acquiredByTransactionId,
      acquiredAtUtcMs: data.acquiredAtUtcMs.present
          ? data.acquiredAtUtcMs.value
          : this.acquiredAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OwnedRewardItem(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('itemId: $itemId, ')
          ..write('catalogVersion: $catalogVersion, ')
          ..write('acquiredByTransactionId: $acquiredByTransactionId, ')
          ..write('acquiredAtUtcMs: $acquiredAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    itemId,
    catalogVersion,
    acquiredByTransactionId,
    acquiredAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OwnedRewardItem &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.itemId == this.itemId &&
          other.catalogVersion == this.catalogVersion &&
          other.acquiredByTransactionId == this.acquiredByTransactionId &&
          other.acquiredAtUtcMs == this.acquiredAtUtcMs);
}

class OwnedRewardItemsCompanion extends UpdateCompanion<OwnedRewardItem> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> itemId;
  final Value<int> catalogVersion;
  final Value<String> acquiredByTransactionId;
  final Value<int> acquiredAtUtcMs;
  final Value<int> rowid;
  const OwnedRewardItemsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.catalogVersion = const Value.absent(),
    this.acquiredByTransactionId = const Value.absent(),
    this.acquiredAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OwnedRewardItemsCompanion.insert({
    required String id,
    required String ownerId,
    required String itemId,
    required int catalogVersion,
    required String acquiredByTransactionId,
    required int acquiredAtUtcMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       itemId = Value(itemId),
       catalogVersion = Value(catalogVersion),
       acquiredByTransactionId = Value(acquiredByTransactionId),
       acquiredAtUtcMs = Value(acquiredAtUtcMs);
  static Insertable<OwnedRewardItem> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? itemId,
    Expression<int>? catalogVersion,
    Expression<String>? acquiredByTransactionId,
    Expression<int>? acquiredAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (itemId != null) 'item_id': itemId,
      if (catalogVersion != null) 'catalog_version': catalogVersion,
      if (acquiredByTransactionId != null)
        'acquired_by_transaction_id': acquiredByTransactionId,
      if (acquiredAtUtcMs != null) 'acquired_at_utc_ms': acquiredAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OwnedRewardItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? itemId,
    Value<int>? catalogVersion,
    Value<String>? acquiredByTransactionId,
    Value<int>? acquiredAtUtcMs,
    Value<int>? rowid,
  }) {
    return OwnedRewardItemsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      itemId: itemId ?? this.itemId,
      catalogVersion: catalogVersion ?? this.catalogVersion,
      acquiredByTransactionId:
          acquiredByTransactionId ?? this.acquiredByTransactionId,
      acquiredAtUtcMs: acquiredAtUtcMs ?? this.acquiredAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (catalogVersion.present) {
      map['catalog_version'] = Variable<int>(catalogVersion.value);
    }
    if (acquiredByTransactionId.present) {
      map['acquired_by_transaction_id'] = Variable<String>(
        acquiredByTransactionId.value,
      );
    }
    if (acquiredAtUtcMs.present) {
      map['acquired_at_utc_ms'] = Variable<int>(acquiredAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OwnedRewardItemsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('itemId: $itemId, ')
          ..write('catalogVersion: $catalogVersion, ')
          ..write('acquiredByTransactionId: $acquiredByTransactionId, ')
          ..write('acquiredAtUtcMs: $acquiredAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EquippedRewardItemsTable extends EquippedRewardItems
    with TableInfo<$EquippedRewardItemsTable, EquippedRewardItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EquippedRewardItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<String> slot = GeneratedColumn<String>(
    'slot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _equippedAtUtcMsMeta = const VerificationMeta(
    'equippedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> equippedAtUtcMs = GeneratedColumn<int>(
    'equipped_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    slot,
    itemId,
    equippedAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'equipped_reward_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<EquippedRewardItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    } else if (isInserting) {
      context.missing(_slotMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('equipped_at_utc_ms')) {
      context.handle(
        _equippedAtUtcMsMeta,
        equippedAtUtcMs.isAcceptableOrUnknown(
          data['equipped_at_utc_ms']!,
          _equippedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_equippedAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerId, slot},
  ];
  @override
  EquippedRewardItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EquippedRewardItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slot'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      equippedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}equipped_at_utc_ms'],
      )!,
    );
  }

  @override
  $EquippedRewardItemsTable createAlias(String alias) {
    return $EquippedRewardItemsTable(attachedDatabase, alias);
  }
}

class EquippedRewardItem extends DataClass
    implements Insertable<EquippedRewardItem> {
  final String id;
  final String ownerId;
  final String slot;
  final String itemId;
  final int equippedAtUtcMs;
  const EquippedRewardItem({
    required this.id,
    required this.ownerId,
    required this.slot,
    required this.itemId,
    required this.equippedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['slot'] = Variable<String>(slot);
    map['item_id'] = Variable<String>(itemId);
    map['equipped_at_utc_ms'] = Variable<int>(equippedAtUtcMs);
    return map;
  }

  EquippedRewardItemsCompanion toCompanion(bool nullToAbsent) {
    return EquippedRewardItemsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      slot: Value(slot),
      itemId: Value(itemId),
      equippedAtUtcMs: Value(equippedAtUtcMs),
    );
  }

  factory EquippedRewardItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EquippedRewardItem(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      slot: serializer.fromJson<String>(json['slot']),
      itemId: serializer.fromJson<String>(json['itemId']),
      equippedAtUtcMs: serializer.fromJson<int>(json['equippedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'slot': serializer.toJson<String>(slot),
      'itemId': serializer.toJson<String>(itemId),
      'equippedAtUtcMs': serializer.toJson<int>(equippedAtUtcMs),
    };
  }

  EquippedRewardItem copyWith({
    String? id,
    String? ownerId,
    String? slot,
    String? itemId,
    int? equippedAtUtcMs,
  }) => EquippedRewardItem(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    slot: slot ?? this.slot,
    itemId: itemId ?? this.itemId,
    equippedAtUtcMs: equippedAtUtcMs ?? this.equippedAtUtcMs,
  );
  EquippedRewardItem copyWithCompanion(EquippedRewardItemsCompanion data) {
    return EquippedRewardItem(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      slot: data.slot.present ? data.slot.value : this.slot,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      equippedAtUtcMs: data.equippedAtUtcMs.present
          ? data.equippedAtUtcMs.value
          : this.equippedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EquippedRewardItem(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('slot: $slot, ')
          ..write('itemId: $itemId, ')
          ..write('equippedAtUtcMs: $equippedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, ownerId, slot, itemId, equippedAtUtcMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EquippedRewardItem &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.slot == this.slot &&
          other.itemId == this.itemId &&
          other.equippedAtUtcMs == this.equippedAtUtcMs);
}

class EquippedRewardItemsCompanion extends UpdateCompanion<EquippedRewardItem> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> slot;
  final Value<String> itemId;
  final Value<int> equippedAtUtcMs;
  final Value<int> rowid;
  const EquippedRewardItemsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.slot = const Value.absent(),
    this.itemId = const Value.absent(),
    this.equippedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EquippedRewardItemsCompanion.insert({
    required String id,
    required String ownerId,
    required String slot,
    required String itemId,
    required int equippedAtUtcMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       slot = Value(slot),
       itemId = Value(itemId),
       equippedAtUtcMs = Value(equippedAtUtcMs);
  static Insertable<EquippedRewardItem> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? slot,
    Expression<String>? itemId,
    Expression<int>? equippedAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (slot != null) 'slot': slot,
      if (itemId != null) 'item_id': itemId,
      if (equippedAtUtcMs != null) 'equipped_at_utc_ms': equippedAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EquippedRewardItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? slot,
    Value<String>? itemId,
    Value<int>? equippedAtUtcMs,
    Value<int>? rowid,
  }) {
    return EquippedRewardItemsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      slot: slot ?? this.slot,
      itemId: itemId ?? this.itemId,
      equippedAtUtcMs: equippedAtUtcMs ?? this.equippedAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (slot.present) {
      map['slot'] = Variable<String>(slot.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (equippedAtUtcMs.present) {
      map['equipped_at_utc_ms'] = Variable<int>(equippedAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EquippedRewardItemsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('slot: $slot, ')
          ..write('itemId: $itemId, ')
          ..write('equippedAtUtcMs: $equippedAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxOperationsTable extends OutboxOperations
    with TableInfo<$OutboxOperationsTable, OutboxOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationKindMeta = const VerificationMeta(
    'operationKind',
  );
  @override
  late final GeneratedColumn<String> operationKind = GeneratedColumn<String>(
    'operation_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadVersionMeta = const VerificationMeta(
    'payloadVersion',
  );
  @override
  late final GeneratedColumn<int> payloadVersion = GeneratedColumn<int>(
    'payload_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _baseRevisionMeta = const VerificationMeta(
    'baseRevision',
  );
  @override
  late final GeneratedColumn<int> baseRevision = GeneratedColumn<int>(
    'base_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtUtcMsMeta =
      const VerificationMeta('nextAttemptAtUtcMs');
  @override
  late final GeneratedColumn<int> nextAttemptAtUtcMs = GeneratedColumn<int>(
    'next_attempt_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _leaseTokenMeta = const VerificationMeta(
    'leaseToken',
  );
  @override
  late final GeneratedColumn<String> leaseToken = GeneratedColumn<String>(
    'lease_token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _leaseExpiresAtUtcMsMeta =
      const VerificationMeta('leaseExpiresAtUtcMs');
  @override
  late final GeneratedColumn<int> leaseExpiresAtUtcMs = GeneratedColumn<int>(
    'lease_expires_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastAttemptAtUtcMsMeta =
      const VerificationMeta('lastAttemptAtUtcMs');
  @override
  late final GeneratedColumn<int> lastAttemptAtUtcMs = GeneratedColumn<int>(
    'last_attempt_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtUtcMsMeta = const VerificationMeta(
    'createdAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> createdAtUtcMs = GeneratedColumn<int>(
    'created_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acknowledgedAtUtcMsMeta =
      const VerificationMeta('acknowledgedAtUtcMs');
  @override
  late final GeneratedColumn<int> acknowledgedAtUtcMs = GeneratedColumn<int>(
    'acknowledged_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureCodeMeta = const VerificationMeta(
    'failureCode',
  );
  @override
  late final GeneratedColumn<String> failureCode = GeneratedColumn<String>(
    'failure_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    ownerId,
    entityType,
    entityId,
    operationKind,
    payloadVersion,
    baseRevision,
    state,
    attemptCount,
    nextAttemptAtUtcMs,
    leaseToken,
    leaseExpiresAtUtcMs,
    lastAttemptAtUtcMs,
    createdAtUtcMs,
    acknowledgedAtUtcMs,
    failureCode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation_kind')) {
      context.handle(
        _operationKindMeta,
        operationKind.isAcceptableOrUnknown(
          data['operation_kind']!,
          _operationKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationKindMeta);
    }
    if (data.containsKey('payload_version')) {
      context.handle(
        _payloadVersionMeta,
        payloadVersion.isAcceptableOrUnknown(
          data['payload_version']!,
          _payloadVersionMeta,
        ),
      );
    }
    if (data.containsKey('base_revision')) {
      context.handle(
        _baseRevisionMeta,
        baseRevision.isAcceptableOrUnknown(
          data['base_revision']!,
          _baseRevisionMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at_utc_ms')) {
      context.handle(
        _nextAttemptAtUtcMsMeta,
        nextAttemptAtUtcMs.isAcceptableOrUnknown(
          data['next_attempt_at_utc_ms']!,
          _nextAttemptAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('lease_token')) {
      context.handle(
        _leaseTokenMeta,
        leaseToken.isAcceptableOrUnknown(data['lease_token']!, _leaseTokenMeta),
      );
    }
    if (data.containsKey('lease_expires_at_utc_ms')) {
      context.handle(
        _leaseExpiresAtUtcMsMeta,
        leaseExpiresAtUtcMs.isAcceptableOrUnknown(
          data['lease_expires_at_utc_ms']!,
          _leaseExpiresAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('last_attempt_at_utc_ms')) {
      context.handle(
        _lastAttemptAtUtcMsMeta,
        lastAttemptAtUtcMs.isAcceptableOrUnknown(
          data['last_attempt_at_utc_ms']!,
          _lastAttemptAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc_ms')) {
      context.handle(
        _createdAtUtcMsMeta,
        createdAtUtcMs.isAcceptableOrUnknown(
          data['created_at_utc_ms']!,
          _createdAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMsMeta);
    }
    if (data.containsKey('acknowledged_at_utc_ms')) {
      context.handle(
        _acknowledgedAtUtcMsMeta,
        acknowledgedAtUtcMs.isAcceptableOrUnknown(
          data['acknowledged_at_utc_ms']!,
          _acknowledgedAtUtcMsMeta,
        ),
      );
    }
    if (data.containsKey('failure_code')) {
      context.handle(
        _failureCodeMeta,
        failureCode.isAcceptableOrUnknown(
          data['failure_code']!,
          _failureCodeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  OutboxOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxOperation(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operationKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_kind'],
      )!,
      payloadVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payload_version'],
      )!,
      baseRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_revision'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at_utc_ms'],
      ),
      leaseToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lease_token'],
      ),
      leaseExpiresAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lease_expires_at_utc_ms'],
      ),
      lastAttemptAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_attempt_at_utc_ms'],
      ),
      createdAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc_ms'],
      )!,
      acknowledgedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}acknowledged_at_utc_ms'],
      ),
      failureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_code'],
      ),
    );
  }

  @override
  $OutboxOperationsTable createAlias(String alias) {
    return $OutboxOperationsTable(attachedDatabase, alias);
  }
}

class OutboxOperation extends DataClass implements Insertable<OutboxOperation> {
  final String operationId;
  final String ownerId;
  final String entityType;
  final String entityId;
  final String operationKind;
  final int payloadVersion;
  final int baseRevision;
  final String state;
  final int attemptCount;
  final int? nextAttemptAtUtcMs;
  final String? leaseToken;
  final int? leaseExpiresAtUtcMs;
  final int? lastAttemptAtUtcMs;
  final int createdAtUtcMs;
  final int? acknowledgedAtUtcMs;
  final String? failureCode;
  const OutboxOperation({
    required this.operationId,
    required this.ownerId,
    required this.entityType,
    required this.entityId,
    required this.operationKind,
    required this.payloadVersion,
    required this.baseRevision,
    required this.state,
    required this.attemptCount,
    this.nextAttemptAtUtcMs,
    this.leaseToken,
    this.leaseExpiresAtUtcMs,
    this.lastAttemptAtUtcMs,
    required this.createdAtUtcMs,
    this.acknowledgedAtUtcMs,
    this.failureCode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['owner_id'] = Variable<String>(ownerId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation_kind'] = Variable<String>(operationKind);
    map['payload_version'] = Variable<int>(payloadVersion);
    map['base_revision'] = Variable<int>(baseRevision);
    map['state'] = Variable<String>(state);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAtUtcMs != null) {
      map['next_attempt_at_utc_ms'] = Variable<int>(nextAttemptAtUtcMs);
    }
    if (!nullToAbsent || leaseToken != null) {
      map['lease_token'] = Variable<String>(leaseToken);
    }
    if (!nullToAbsent || leaseExpiresAtUtcMs != null) {
      map['lease_expires_at_utc_ms'] = Variable<int>(leaseExpiresAtUtcMs);
    }
    if (!nullToAbsent || lastAttemptAtUtcMs != null) {
      map['last_attempt_at_utc_ms'] = Variable<int>(lastAttemptAtUtcMs);
    }
    map['created_at_utc_ms'] = Variable<int>(createdAtUtcMs);
    if (!nullToAbsent || acknowledgedAtUtcMs != null) {
      map['acknowledged_at_utc_ms'] = Variable<int>(acknowledgedAtUtcMs);
    }
    if (!nullToAbsent || failureCode != null) {
      map['failure_code'] = Variable<String>(failureCode);
    }
    return map;
  }

  OutboxOperationsCompanion toCompanion(bool nullToAbsent) {
    return OutboxOperationsCompanion(
      operationId: Value(operationId),
      ownerId: Value(ownerId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operationKind: Value(operationKind),
      payloadVersion: Value(payloadVersion),
      baseRevision: Value(baseRevision),
      state: Value(state),
      attemptCount: Value(attemptCount),
      nextAttemptAtUtcMs: nextAttemptAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAtUtcMs),
      leaseToken: leaseToken == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseToken),
      leaseExpiresAtUtcMs: leaseExpiresAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseExpiresAtUtcMs),
      lastAttemptAtUtcMs: lastAttemptAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAtUtcMs),
      createdAtUtcMs: Value(createdAtUtcMs),
      acknowledgedAtUtcMs: acknowledgedAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(acknowledgedAtUtcMs),
      failureCode: failureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(failureCode),
    );
  }

  factory OutboxOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxOperation(
      operationId: serializer.fromJson<String>(json['operationId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operationKind: serializer.fromJson<String>(json['operationKind']),
      payloadVersion: serializer.fromJson<int>(json['payloadVersion']),
      baseRevision: serializer.fromJson<int>(json['baseRevision']),
      state: serializer.fromJson<String>(json['state']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAtUtcMs: serializer.fromJson<int?>(json['nextAttemptAtUtcMs']),
      leaseToken: serializer.fromJson<String?>(json['leaseToken']),
      leaseExpiresAtUtcMs: serializer.fromJson<int?>(
        json['leaseExpiresAtUtcMs'],
      ),
      lastAttemptAtUtcMs: serializer.fromJson<int?>(json['lastAttemptAtUtcMs']),
      createdAtUtcMs: serializer.fromJson<int>(json['createdAtUtcMs']),
      acknowledgedAtUtcMs: serializer.fromJson<int?>(
        json['acknowledgedAtUtcMs'],
      ),
      failureCode: serializer.fromJson<String?>(json['failureCode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'ownerId': serializer.toJson<String>(ownerId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operationKind': serializer.toJson<String>(operationKind),
      'payloadVersion': serializer.toJson<int>(payloadVersion),
      'baseRevision': serializer.toJson<int>(baseRevision),
      'state': serializer.toJson<String>(state),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAtUtcMs': serializer.toJson<int?>(nextAttemptAtUtcMs),
      'leaseToken': serializer.toJson<String?>(leaseToken),
      'leaseExpiresAtUtcMs': serializer.toJson<int?>(leaseExpiresAtUtcMs),
      'lastAttemptAtUtcMs': serializer.toJson<int?>(lastAttemptAtUtcMs),
      'createdAtUtcMs': serializer.toJson<int>(createdAtUtcMs),
      'acknowledgedAtUtcMs': serializer.toJson<int?>(acknowledgedAtUtcMs),
      'failureCode': serializer.toJson<String?>(failureCode),
    };
  }

  OutboxOperation copyWith({
    String? operationId,
    String? ownerId,
    String? entityType,
    String? entityId,
    String? operationKind,
    int? payloadVersion,
    int? baseRevision,
    String? state,
    int? attemptCount,
    Value<int?> nextAttemptAtUtcMs = const Value.absent(),
    Value<String?> leaseToken = const Value.absent(),
    Value<int?> leaseExpiresAtUtcMs = const Value.absent(),
    Value<int?> lastAttemptAtUtcMs = const Value.absent(),
    int? createdAtUtcMs,
    Value<int?> acknowledgedAtUtcMs = const Value.absent(),
    Value<String?> failureCode = const Value.absent(),
  }) => OutboxOperation(
    operationId: operationId ?? this.operationId,
    ownerId: ownerId ?? this.ownerId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operationKind: operationKind ?? this.operationKind,
    payloadVersion: payloadVersion ?? this.payloadVersion,
    baseRevision: baseRevision ?? this.baseRevision,
    state: state ?? this.state,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAtUtcMs: nextAttemptAtUtcMs.present
        ? nextAttemptAtUtcMs.value
        : this.nextAttemptAtUtcMs,
    leaseToken: leaseToken.present ? leaseToken.value : this.leaseToken,
    leaseExpiresAtUtcMs: leaseExpiresAtUtcMs.present
        ? leaseExpiresAtUtcMs.value
        : this.leaseExpiresAtUtcMs,
    lastAttemptAtUtcMs: lastAttemptAtUtcMs.present
        ? lastAttemptAtUtcMs.value
        : this.lastAttemptAtUtcMs,
    createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
    acknowledgedAtUtcMs: acknowledgedAtUtcMs.present
        ? acknowledgedAtUtcMs.value
        : this.acknowledgedAtUtcMs,
    failureCode: failureCode.present ? failureCode.value : this.failureCode,
  );
  OutboxOperation copyWithCompanion(OutboxOperationsCompanion data) {
    return OutboxOperation(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operationKind: data.operationKind.present
          ? data.operationKind.value
          : this.operationKind,
      payloadVersion: data.payloadVersion.present
          ? data.payloadVersion.value
          : this.payloadVersion,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
      state: data.state.present ? data.state.value : this.state,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAtUtcMs: data.nextAttemptAtUtcMs.present
          ? data.nextAttemptAtUtcMs.value
          : this.nextAttemptAtUtcMs,
      leaseToken: data.leaseToken.present
          ? data.leaseToken.value
          : this.leaseToken,
      leaseExpiresAtUtcMs: data.leaseExpiresAtUtcMs.present
          ? data.leaseExpiresAtUtcMs.value
          : this.leaseExpiresAtUtcMs,
      lastAttemptAtUtcMs: data.lastAttemptAtUtcMs.present
          ? data.lastAttemptAtUtcMs.value
          : this.lastAttemptAtUtcMs,
      createdAtUtcMs: data.createdAtUtcMs.present
          ? data.createdAtUtcMs.value
          : this.createdAtUtcMs,
      acknowledgedAtUtcMs: data.acknowledgedAtUtcMs.present
          ? data.acknowledgedAtUtcMs.value
          : this.acknowledgedAtUtcMs,
      failureCode: data.failureCode.present
          ? data.failureCode.value
          : this.failureCode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxOperation(')
          ..write('operationId: $operationId, ')
          ..write('ownerId: $ownerId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operationKind: $operationKind, ')
          ..write('payloadVersion: $payloadVersion, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('state: $state, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAtUtcMs: $nextAttemptAtUtcMs, ')
          ..write('leaseToken: $leaseToken, ')
          ..write('leaseExpiresAtUtcMs: $leaseExpiresAtUtcMs, ')
          ..write('lastAttemptAtUtcMs: $lastAttemptAtUtcMs, ')
          ..write('createdAtUtcMs: $createdAtUtcMs, ')
          ..write('acknowledgedAtUtcMs: $acknowledgedAtUtcMs, ')
          ..write('failureCode: $failureCode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    ownerId,
    entityType,
    entityId,
    operationKind,
    payloadVersion,
    baseRevision,
    state,
    attemptCount,
    nextAttemptAtUtcMs,
    leaseToken,
    leaseExpiresAtUtcMs,
    lastAttemptAtUtcMs,
    createdAtUtcMs,
    acknowledgedAtUtcMs,
    failureCode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxOperation &&
          other.operationId == this.operationId &&
          other.ownerId == this.ownerId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operationKind == this.operationKind &&
          other.payloadVersion == this.payloadVersion &&
          other.baseRevision == this.baseRevision &&
          other.state == this.state &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAtUtcMs == this.nextAttemptAtUtcMs &&
          other.leaseToken == this.leaseToken &&
          other.leaseExpiresAtUtcMs == this.leaseExpiresAtUtcMs &&
          other.lastAttemptAtUtcMs == this.lastAttemptAtUtcMs &&
          other.createdAtUtcMs == this.createdAtUtcMs &&
          other.acknowledgedAtUtcMs == this.acknowledgedAtUtcMs &&
          other.failureCode == this.failureCode);
}

class OutboxOperationsCompanion extends UpdateCompanion<OutboxOperation> {
  final Value<String> operationId;
  final Value<String> ownerId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operationKind;
  final Value<int> payloadVersion;
  final Value<int> baseRevision;
  final Value<String> state;
  final Value<int> attemptCount;
  final Value<int?> nextAttemptAtUtcMs;
  final Value<String?> leaseToken;
  final Value<int?> leaseExpiresAtUtcMs;
  final Value<int?> lastAttemptAtUtcMs;
  final Value<int> createdAtUtcMs;
  final Value<int?> acknowledgedAtUtcMs;
  final Value<String?> failureCode;
  final Value<int> rowid;
  const OutboxOperationsCompanion({
    this.operationId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operationKind = const Value.absent(),
    this.payloadVersion = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.state = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAtUtcMs = const Value.absent(),
    this.leaseToken = const Value.absent(),
    this.leaseExpiresAtUtcMs = const Value.absent(),
    this.lastAttemptAtUtcMs = const Value.absent(),
    this.createdAtUtcMs = const Value.absent(),
    this.acknowledgedAtUtcMs = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxOperationsCompanion.insert({
    required String operationId,
    required String ownerId,
    required String entityType,
    required String entityId,
    required String operationKind,
    this.payloadVersion = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.state = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAtUtcMs = const Value.absent(),
    this.leaseToken = const Value.absent(),
    this.leaseExpiresAtUtcMs = const Value.absent(),
    this.lastAttemptAtUtcMs = const Value.absent(),
    required int createdAtUtcMs,
    this.acknowledgedAtUtcMs = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       ownerId = Value(ownerId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       operationKind = Value(operationKind),
       createdAtUtcMs = Value(createdAtUtcMs);
  static Insertable<OutboxOperation> custom({
    Expression<String>? operationId,
    Expression<String>? ownerId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operationKind,
    Expression<int>? payloadVersion,
    Expression<int>? baseRevision,
    Expression<String>? state,
    Expression<int>? attemptCount,
    Expression<int>? nextAttemptAtUtcMs,
    Expression<String>? leaseToken,
    Expression<int>? leaseExpiresAtUtcMs,
    Expression<int>? lastAttemptAtUtcMs,
    Expression<int>? createdAtUtcMs,
    Expression<int>? acknowledgedAtUtcMs,
    Expression<String>? failureCode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (ownerId != null) 'owner_id': ownerId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operationKind != null) 'operation_kind': operationKind,
      if (payloadVersion != null) 'payload_version': payloadVersion,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (state != null) 'state': state,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAtUtcMs != null)
        'next_attempt_at_utc_ms': nextAttemptAtUtcMs,
      if (leaseToken != null) 'lease_token': leaseToken,
      if (leaseExpiresAtUtcMs != null)
        'lease_expires_at_utc_ms': leaseExpiresAtUtcMs,
      if (lastAttemptAtUtcMs != null)
        'last_attempt_at_utc_ms': lastAttemptAtUtcMs,
      if (createdAtUtcMs != null) 'created_at_utc_ms': createdAtUtcMs,
      if (acknowledgedAtUtcMs != null)
        'acknowledged_at_utc_ms': acknowledgedAtUtcMs,
      if (failureCode != null) 'failure_code': failureCode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxOperationsCompanion copyWith({
    Value<String>? operationId,
    Value<String>? ownerId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operationKind,
    Value<int>? payloadVersion,
    Value<int>? baseRevision,
    Value<String>? state,
    Value<int>? attemptCount,
    Value<int?>? nextAttemptAtUtcMs,
    Value<String?>? leaseToken,
    Value<int?>? leaseExpiresAtUtcMs,
    Value<int?>? lastAttemptAtUtcMs,
    Value<int>? createdAtUtcMs,
    Value<int?>? acknowledgedAtUtcMs,
    Value<String?>? failureCode,
    Value<int>? rowid,
  }) {
    return OutboxOperationsCompanion(
      operationId: operationId ?? this.operationId,
      ownerId: ownerId ?? this.ownerId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operationKind: operationKind ?? this.operationKind,
      payloadVersion: payloadVersion ?? this.payloadVersion,
      baseRevision: baseRevision ?? this.baseRevision,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAtUtcMs: nextAttemptAtUtcMs ?? this.nextAttemptAtUtcMs,
      leaseToken: leaseToken ?? this.leaseToken,
      leaseExpiresAtUtcMs: leaseExpiresAtUtcMs ?? this.leaseExpiresAtUtcMs,
      lastAttemptAtUtcMs: lastAttemptAtUtcMs ?? this.lastAttemptAtUtcMs,
      createdAtUtcMs: createdAtUtcMs ?? this.createdAtUtcMs,
      acknowledgedAtUtcMs: acknowledgedAtUtcMs ?? this.acknowledgedAtUtcMs,
      failureCode: failureCode ?? this.failureCode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operationKind.present) {
      map['operation_kind'] = Variable<String>(operationKind.value);
    }
    if (payloadVersion.present) {
      map['payload_version'] = Variable<int>(payloadVersion.value);
    }
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAtUtcMs.present) {
      map['next_attempt_at_utc_ms'] = Variable<int>(nextAttemptAtUtcMs.value);
    }
    if (leaseToken.present) {
      map['lease_token'] = Variable<String>(leaseToken.value);
    }
    if (leaseExpiresAtUtcMs.present) {
      map['lease_expires_at_utc_ms'] = Variable<int>(leaseExpiresAtUtcMs.value);
    }
    if (lastAttemptAtUtcMs.present) {
      map['last_attempt_at_utc_ms'] = Variable<int>(lastAttemptAtUtcMs.value);
    }
    if (createdAtUtcMs.present) {
      map['created_at_utc_ms'] = Variable<int>(createdAtUtcMs.value);
    }
    if (acknowledgedAtUtcMs.present) {
      map['acknowledged_at_utc_ms'] = Variable<int>(acknowledgedAtUtcMs.value);
    }
    if (failureCode.present) {
      map['failure_code'] = Variable<String>(failureCode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxOperationsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('ownerId: $ownerId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operationKind: $operationKind, ')
          ..write('payloadVersion: $payloadVersion, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('state: $state, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAtUtcMs: $nextAttemptAtUtcMs, ')
          ..write('leaseToken: $leaseToken, ')
          ..write('leaseExpiresAtUtcMs: $leaseExpiresAtUtcMs, ')
          ..write('lastAttemptAtUtcMs: $lastAttemptAtUtcMs, ')
          ..write('createdAtUtcMs: $createdAtUtcMs, ')
          ..write('acknowledgedAtUtcMs: $acknowledgedAtUtcMs, ')
          ..write('failureCode: $failureCode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCheckpointsTable extends SyncCheckpoints
    with TableInfo<$SyncCheckpointsTable, SyncCheckpoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCheckpointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _collectionNameMeta = const VerificationMeta(
    'collectionName',
  );
  @override
  late final GeneratedColumn<String> collectionName = GeneratedColumn<String>(
    'collection_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverCursorMeta = const VerificationMeta(
    'serverCursor',
  );
  @override
  late final GeneratedColumn<String> serverCursor = GeneratedColumn<String>(
    'server_cursor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSuccessAtUtcMsMeta =
      const VerificationMeta('lastSuccessAtUtcMs');
  @override
  late final GeneratedColumn<int> lastSuccessAtUtcMs = GeneratedColumn<int>(
    'last_success_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    collectionName,
    serverCursor,
    lastSuccessAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_checkpoints';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCheckpoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('collection_name')) {
      context.handle(
        _collectionNameMeta,
        collectionName.isAcceptableOrUnknown(
          data['collection_name']!,
          _collectionNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectionNameMeta);
    }
    if (data.containsKey('server_cursor')) {
      context.handle(
        _serverCursorMeta,
        serverCursor.isAcceptableOrUnknown(
          data['server_cursor']!,
          _serverCursorMeta,
        ),
      );
    }
    if (data.containsKey('last_success_at_utc_ms')) {
      context.handle(
        _lastSuccessAtUtcMsMeta,
        lastSuccessAtUtcMs.isAcceptableOrUnknown(
          data['last_success_at_utc_ms']!,
          _lastSuccessAtUtcMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {ownerId, collectionName},
  ];
  @override
  SyncCheckpoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCheckpoint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      collectionName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_name'],
      )!,
      serverCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_cursor'],
      ),
      lastSuccessAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_success_at_utc_ms'],
      ),
    );
  }

  @override
  $SyncCheckpointsTable createAlias(String alias) {
    return $SyncCheckpointsTable(attachedDatabase, alias);
  }
}

class SyncCheckpoint extends DataClass implements Insertable<SyncCheckpoint> {
  final String id;
  final String ownerId;
  final String collectionName;
  final String? serverCursor;
  final int? lastSuccessAtUtcMs;
  const SyncCheckpoint({
    required this.id,
    required this.ownerId,
    required this.collectionName,
    this.serverCursor,
    this.lastSuccessAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['collection_name'] = Variable<String>(collectionName);
    if (!nullToAbsent || serverCursor != null) {
      map['server_cursor'] = Variable<String>(serverCursor);
    }
    if (!nullToAbsent || lastSuccessAtUtcMs != null) {
      map['last_success_at_utc_ms'] = Variable<int>(lastSuccessAtUtcMs);
    }
    return map;
  }

  SyncCheckpointsCompanion toCompanion(bool nullToAbsent) {
    return SyncCheckpointsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      collectionName: Value(collectionName),
      serverCursor: serverCursor == null && nullToAbsent
          ? const Value.absent()
          : Value(serverCursor),
      lastSuccessAtUtcMs: lastSuccessAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSuccessAtUtcMs),
    );
  }

  factory SyncCheckpoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCheckpoint(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      collectionName: serializer.fromJson<String>(json['collectionName']),
      serverCursor: serializer.fromJson<String?>(json['serverCursor']),
      lastSuccessAtUtcMs: serializer.fromJson<int?>(json['lastSuccessAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'collectionName': serializer.toJson<String>(collectionName),
      'serverCursor': serializer.toJson<String?>(serverCursor),
      'lastSuccessAtUtcMs': serializer.toJson<int?>(lastSuccessAtUtcMs),
    };
  }

  SyncCheckpoint copyWith({
    String? id,
    String? ownerId,
    String? collectionName,
    Value<String?> serverCursor = const Value.absent(),
    Value<int?> lastSuccessAtUtcMs = const Value.absent(),
  }) => SyncCheckpoint(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    collectionName: collectionName ?? this.collectionName,
    serverCursor: serverCursor.present ? serverCursor.value : this.serverCursor,
    lastSuccessAtUtcMs: lastSuccessAtUtcMs.present
        ? lastSuccessAtUtcMs.value
        : this.lastSuccessAtUtcMs,
  );
  SyncCheckpoint copyWithCompanion(SyncCheckpointsCompanion data) {
    return SyncCheckpoint(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      collectionName: data.collectionName.present
          ? data.collectionName.value
          : this.collectionName,
      serverCursor: data.serverCursor.present
          ? data.serverCursor.value
          : this.serverCursor,
      lastSuccessAtUtcMs: data.lastSuccessAtUtcMs.present
          ? data.lastSuccessAtUtcMs.value
          : this.lastSuccessAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCheckpoint(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('collectionName: $collectionName, ')
          ..write('serverCursor: $serverCursor, ')
          ..write('lastSuccessAtUtcMs: $lastSuccessAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    collectionName,
    serverCursor,
    lastSuccessAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCheckpoint &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.collectionName == this.collectionName &&
          other.serverCursor == this.serverCursor &&
          other.lastSuccessAtUtcMs == this.lastSuccessAtUtcMs);
}

class SyncCheckpointsCompanion extends UpdateCompanion<SyncCheckpoint> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> collectionName;
  final Value<String?> serverCursor;
  final Value<int?> lastSuccessAtUtcMs;
  final Value<int> rowid;
  const SyncCheckpointsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.collectionName = const Value.absent(),
    this.serverCursor = const Value.absent(),
    this.lastSuccessAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCheckpointsCompanion.insert({
    required String id,
    required String ownerId,
    required String collectionName,
    this.serverCursor = const Value.absent(),
    this.lastSuccessAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       collectionName = Value(collectionName);
  static Insertable<SyncCheckpoint> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? collectionName,
    Expression<String>? serverCursor,
    Expression<int>? lastSuccessAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (collectionName != null) 'collection_name': collectionName,
      if (serverCursor != null) 'server_cursor': serverCursor,
      if (lastSuccessAtUtcMs != null)
        'last_success_at_utc_ms': lastSuccessAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCheckpointsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? collectionName,
    Value<String?>? serverCursor,
    Value<int?>? lastSuccessAtUtcMs,
    Value<int>? rowid,
  }) {
    return SyncCheckpointsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      collectionName: collectionName ?? this.collectionName,
      serverCursor: serverCursor ?? this.serverCursor,
      lastSuccessAtUtcMs: lastSuccessAtUtcMs ?? this.lastSuccessAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (collectionName.present) {
      map['collection_name'] = Variable<String>(collectionName.value);
    }
    if (serverCursor.present) {
      map['server_cursor'] = Variable<String>(serverCursor.value);
    }
    if (lastSuccessAtUtcMs.present) {
      map['last_success_at_utc_ms'] = Variable<int>(lastSuccessAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCheckpointsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('collectionName: $collectionName, ')
          ..write('serverCursor: $serverCursor, ')
          ..write('lastSuccessAtUtcMs: $lastSuccessAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncConflictsTable extends SyncConflicts
    with TableInfo<$SyncConflictsTable, SyncConflict> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncConflictsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_owners (id)',
    ),
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localRevisionMeta = const VerificationMeta(
    'localRevision',
  );
  @override
  late final GeneratedColumn<int> localRevision = GeneratedColumn<int>(
    'local_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cloudRevisionMeta = const VerificationMeta(
    'cloudRevision',
  );
  @override
  late final GeneratedColumn<int> cloudRevision = GeneratedColumn<int>(
    'cloud_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resolutionPolicyMeta = const VerificationMeta(
    'resolutionPolicy',
  );
  @override
  late final GeneratedColumn<String> resolutionPolicy = GeneratedColumn<String>(
    'resolution_policy',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localSnapshotJsonMeta = const VerificationMeta(
    'localSnapshotJson',
  );
  @override
  late final GeneratedColumn<String> localSnapshotJson =
      GeneratedColumn<String>(
        'local_snapshot_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _cloudSnapshotJsonMeta = const VerificationMeta(
    'cloudSnapshotJson',
  );
  @override
  late final GeneratedColumn<String> cloudSnapshotJson =
      GeneratedColumn<String>(
        'cloud_snapshot_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _resolvedAtUtcMsMeta = const VerificationMeta(
    'resolvedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> resolvedAtUtcMs = GeneratedColumn<int>(
    'resolved_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    entityType,
    entityId,
    localRevision,
    cloudRevision,
    resolutionPolicy,
    outcome,
    localSnapshotJson,
    cloudSnapshotJson,
    resolvedAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_conflicts';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncConflict> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('local_revision')) {
      context.handle(
        _localRevisionMeta,
        localRevision.isAcceptableOrUnknown(
          data['local_revision']!,
          _localRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localRevisionMeta);
    }
    if (data.containsKey('cloud_revision')) {
      context.handle(
        _cloudRevisionMeta,
        cloudRevision.isAcceptableOrUnknown(
          data['cloud_revision']!,
          _cloudRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cloudRevisionMeta);
    }
    if (data.containsKey('resolution_policy')) {
      context.handle(
        _resolutionPolicyMeta,
        resolutionPolicy.isAcceptableOrUnknown(
          data['resolution_policy']!,
          _resolutionPolicyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_resolutionPolicyMeta);
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    } else if (isInserting) {
      context.missing(_outcomeMeta);
    }
    if (data.containsKey('local_snapshot_json')) {
      context.handle(
        _localSnapshotJsonMeta,
        localSnapshotJson.isAcceptableOrUnknown(
          data['local_snapshot_json']!,
          _localSnapshotJsonMeta,
        ),
      );
    }
    if (data.containsKey('cloud_snapshot_json')) {
      context.handle(
        _cloudSnapshotJsonMeta,
        cloudSnapshotJson.isAcceptableOrUnknown(
          data['cloud_snapshot_json']!,
          _cloudSnapshotJsonMeta,
        ),
      );
    }
    if (data.containsKey('resolved_at_utc_ms')) {
      context.handle(
        _resolvedAtUtcMsMeta,
        resolvedAtUtcMs.isAcceptableOrUnknown(
          data['resolved_at_utc_ms']!,
          _resolvedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_resolvedAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncConflict map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncConflict(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      localRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_revision'],
      )!,
      cloudRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cloud_revision'],
      )!,
      resolutionPolicy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolution_policy'],
      )!,
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      )!,
      localSnapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_snapshot_json'],
      ),
      cloudSnapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_snapshot_json'],
      ),
      resolvedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolved_at_utc_ms'],
      )!,
    );
  }

  @override
  $SyncConflictsTable createAlias(String alias) {
    return $SyncConflictsTable(attachedDatabase, alias);
  }
}

class SyncConflict extends DataClass implements Insertable<SyncConflict> {
  final String id;
  final String ownerId;
  final String entityType;
  final String entityId;
  final int localRevision;
  final int cloudRevision;
  final String resolutionPolicy;
  final String outcome;
  final String? localSnapshotJson;
  final String? cloudSnapshotJson;
  final int resolvedAtUtcMs;
  const SyncConflict({
    required this.id,
    required this.ownerId,
    required this.entityType,
    required this.entityId,
    required this.localRevision,
    required this.cloudRevision,
    required this.resolutionPolicy,
    required this.outcome,
    this.localSnapshotJson,
    this.cloudSnapshotJson,
    required this.resolvedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['local_revision'] = Variable<int>(localRevision);
    map['cloud_revision'] = Variable<int>(cloudRevision);
    map['resolution_policy'] = Variable<String>(resolutionPolicy);
    map['outcome'] = Variable<String>(outcome);
    if (!nullToAbsent || localSnapshotJson != null) {
      map['local_snapshot_json'] = Variable<String>(localSnapshotJson);
    }
    if (!nullToAbsent || cloudSnapshotJson != null) {
      map['cloud_snapshot_json'] = Variable<String>(cloudSnapshotJson);
    }
    map['resolved_at_utc_ms'] = Variable<int>(resolvedAtUtcMs);
    return map;
  }

  SyncConflictsCompanion toCompanion(bool nullToAbsent) {
    return SyncConflictsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      localRevision: Value(localRevision),
      cloudRevision: Value(cloudRevision),
      resolutionPolicy: Value(resolutionPolicy),
      outcome: Value(outcome),
      localSnapshotJson: localSnapshotJson == null && nullToAbsent
          ? const Value.absent()
          : Value(localSnapshotJson),
      cloudSnapshotJson: cloudSnapshotJson == null && nullToAbsent
          ? const Value.absent()
          : Value(cloudSnapshotJson),
      resolvedAtUtcMs: Value(resolvedAtUtcMs),
    );
  }

  factory SyncConflict.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncConflict(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      localRevision: serializer.fromJson<int>(json['localRevision']),
      cloudRevision: serializer.fromJson<int>(json['cloudRevision']),
      resolutionPolicy: serializer.fromJson<String>(json['resolutionPolicy']),
      outcome: serializer.fromJson<String>(json['outcome']),
      localSnapshotJson: serializer.fromJson<String?>(
        json['localSnapshotJson'],
      ),
      cloudSnapshotJson: serializer.fromJson<String?>(
        json['cloudSnapshotJson'],
      ),
      resolvedAtUtcMs: serializer.fromJson<int>(json['resolvedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'localRevision': serializer.toJson<int>(localRevision),
      'cloudRevision': serializer.toJson<int>(cloudRevision),
      'resolutionPolicy': serializer.toJson<String>(resolutionPolicy),
      'outcome': serializer.toJson<String>(outcome),
      'localSnapshotJson': serializer.toJson<String?>(localSnapshotJson),
      'cloudSnapshotJson': serializer.toJson<String?>(cloudSnapshotJson),
      'resolvedAtUtcMs': serializer.toJson<int>(resolvedAtUtcMs),
    };
  }

  SyncConflict copyWith({
    String? id,
    String? ownerId,
    String? entityType,
    String? entityId,
    int? localRevision,
    int? cloudRevision,
    String? resolutionPolicy,
    String? outcome,
    Value<String?> localSnapshotJson = const Value.absent(),
    Value<String?> cloudSnapshotJson = const Value.absent(),
    int? resolvedAtUtcMs,
  }) => SyncConflict(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    localRevision: localRevision ?? this.localRevision,
    cloudRevision: cloudRevision ?? this.cloudRevision,
    resolutionPolicy: resolutionPolicy ?? this.resolutionPolicy,
    outcome: outcome ?? this.outcome,
    localSnapshotJson: localSnapshotJson.present
        ? localSnapshotJson.value
        : this.localSnapshotJson,
    cloudSnapshotJson: cloudSnapshotJson.present
        ? cloudSnapshotJson.value
        : this.cloudSnapshotJson,
    resolvedAtUtcMs: resolvedAtUtcMs ?? this.resolvedAtUtcMs,
  );
  SyncConflict copyWithCompanion(SyncConflictsCompanion data) {
    return SyncConflict(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      localRevision: data.localRevision.present
          ? data.localRevision.value
          : this.localRevision,
      cloudRevision: data.cloudRevision.present
          ? data.cloudRevision.value
          : this.cloudRevision,
      resolutionPolicy: data.resolutionPolicy.present
          ? data.resolutionPolicy.value
          : this.resolutionPolicy,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      localSnapshotJson: data.localSnapshotJson.present
          ? data.localSnapshotJson.value
          : this.localSnapshotJson,
      cloudSnapshotJson: data.cloudSnapshotJson.present
          ? data.cloudSnapshotJson.value
          : this.cloudSnapshotJson,
      resolvedAtUtcMs: data.resolvedAtUtcMs.present
          ? data.resolvedAtUtcMs.value
          : this.resolvedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflict(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('localRevision: $localRevision, ')
          ..write('cloudRevision: $cloudRevision, ')
          ..write('resolutionPolicy: $resolutionPolicy, ')
          ..write('outcome: $outcome, ')
          ..write('localSnapshotJson: $localSnapshotJson, ')
          ..write('cloudSnapshotJson: $cloudSnapshotJson, ')
          ..write('resolvedAtUtcMs: $resolvedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    entityType,
    entityId,
    localRevision,
    cloudRevision,
    resolutionPolicy,
    outcome,
    localSnapshotJson,
    cloudSnapshotJson,
    resolvedAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncConflict &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.localRevision == this.localRevision &&
          other.cloudRevision == this.cloudRevision &&
          other.resolutionPolicy == this.resolutionPolicy &&
          other.outcome == this.outcome &&
          other.localSnapshotJson == this.localSnapshotJson &&
          other.cloudSnapshotJson == this.cloudSnapshotJson &&
          other.resolvedAtUtcMs == this.resolvedAtUtcMs);
}

class SyncConflictsCompanion extends UpdateCompanion<SyncConflict> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<int> localRevision;
  final Value<int> cloudRevision;
  final Value<String> resolutionPolicy;
  final Value<String> outcome;
  final Value<String?> localSnapshotJson;
  final Value<String?> cloudSnapshotJson;
  final Value<int> resolvedAtUtcMs;
  final Value<int> rowid;
  const SyncConflictsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.cloudRevision = const Value.absent(),
    this.resolutionPolicy = const Value.absent(),
    this.outcome = const Value.absent(),
    this.localSnapshotJson = const Value.absent(),
    this.cloudSnapshotJson = const Value.absent(),
    this.resolvedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncConflictsCompanion.insert({
    required String id,
    required String ownerId,
    required String entityType,
    required String entityId,
    required int localRevision,
    required int cloudRevision,
    required String resolutionPolicy,
    required String outcome,
    this.localSnapshotJson = const Value.absent(),
    this.cloudSnapshotJson = const Value.absent(),
    required int resolvedAtUtcMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       localRevision = Value(localRevision),
       cloudRevision = Value(cloudRevision),
       resolutionPolicy = Value(resolutionPolicy),
       outcome = Value(outcome),
       resolvedAtUtcMs = Value(resolvedAtUtcMs);
  static Insertable<SyncConflict> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<int>? localRevision,
    Expression<int>? cloudRevision,
    Expression<String>? resolutionPolicy,
    Expression<String>? outcome,
    Expression<String>? localSnapshotJson,
    Expression<String>? cloudSnapshotJson,
    Expression<int>? resolvedAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (localRevision != null) 'local_revision': localRevision,
      if (cloudRevision != null) 'cloud_revision': cloudRevision,
      if (resolutionPolicy != null) 'resolution_policy': resolutionPolicy,
      if (outcome != null) 'outcome': outcome,
      if (localSnapshotJson != null) 'local_snapshot_json': localSnapshotJson,
      if (cloudSnapshotJson != null) 'cloud_snapshot_json': cloudSnapshotJson,
      if (resolvedAtUtcMs != null) 'resolved_at_utc_ms': resolvedAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncConflictsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<int>? localRevision,
    Value<int>? cloudRevision,
    Value<String>? resolutionPolicy,
    Value<String>? outcome,
    Value<String?>? localSnapshotJson,
    Value<String?>? cloudSnapshotJson,
    Value<int>? resolvedAtUtcMs,
    Value<int>? rowid,
  }) {
    return SyncConflictsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      localRevision: localRevision ?? this.localRevision,
      cloudRevision: cloudRevision ?? this.cloudRevision,
      resolutionPolicy: resolutionPolicy ?? this.resolutionPolicy,
      outcome: outcome ?? this.outcome,
      localSnapshotJson: localSnapshotJson ?? this.localSnapshotJson,
      cloudSnapshotJson: cloudSnapshotJson ?? this.cloudSnapshotJson,
      resolvedAtUtcMs: resolvedAtUtcMs ?? this.resolvedAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (localRevision.present) {
      map['local_revision'] = Variable<int>(localRevision.value);
    }
    if (cloudRevision.present) {
      map['cloud_revision'] = Variable<int>(cloudRevision.value);
    }
    if (resolutionPolicy.present) {
      map['resolution_policy'] = Variable<String>(resolutionPolicy.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (localSnapshotJson.present) {
      map['local_snapshot_json'] = Variable<String>(localSnapshotJson.value);
    }
    if (cloudSnapshotJson.present) {
      map['cloud_snapshot_json'] = Variable<String>(cloudSnapshotJson.value);
    }
    if (resolvedAtUtcMs.present) {
      map['resolved_at_utc_ms'] = Variable<int>(resolvedAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('localRevision: $localRevision, ')
          ..write('cloudRevision: $cloudRevision, ')
          ..write('resolutionPolicy: $resolutionPolicy, ')
          ..write('outcome: $outcome, ')
          ..write('localSnapshotJson: $localSnapshotJson, ')
          ..write('cloudSnapshotJson: $cloudSnapshotJson, ')
          ..write('resolvedAtUtcMs: $resolvedAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RuntimeFlagsTable extends RuntimeFlags
    with TableInfo<$RuntimeFlagsTable, RuntimeFlag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RuntimeFlagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _boolValueMeta = const VerificationMeta(
    'boolValue',
  );
  @override
  late final GeneratedColumn<bool> boolValue = GeneratedColumn<bool>(
    'bool_value',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("bool_value" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  );
  static const VerificationMeta _updatedAtUtcMsMeta = const VerificationMeta(
    'updatedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtcMs = GeneratedColumn<int>(
    'updated_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtUtcMsMeta = const VerificationMeta(
    'expiresAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> expiresAtUtcMs = GeneratedColumn<int>(
    'expires_at_utc_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    key,
    boolValue,
    source,
    updatedAtUtcMs,
    expiresAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'runtime_flags';
  @override
  VerificationContext validateIntegrity(
    Insertable<RuntimeFlag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('bool_value')) {
      context.handle(
        _boolValueMeta,
        boolValue.isAcceptableOrUnknown(data['bool_value']!, _boolValueMeta),
      );
    } else if (isInserting) {
      context.missing(_boolValueMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('updated_at_utc_ms')) {
      context.handle(
        _updatedAtUtcMsMeta,
        updatedAtUtcMs.isAcceptableOrUnknown(
          data['updated_at_utc_ms']!,
          _updatedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMsMeta);
    }
    if (data.containsKey('expires_at_utc_ms')) {
      context.handle(
        _expiresAtUtcMsMeta,
        expiresAtUtcMs.isAcceptableOrUnknown(
          data['expires_at_utc_ms']!,
          _expiresAtUtcMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  RuntimeFlag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RuntimeFlag(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      boolValue: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}bool_value'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      updatedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc_ms'],
      )!,
      expiresAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at_utc_ms'],
      ),
    );
  }

  @override
  $RuntimeFlagsTable createAlias(String alias) {
    return $RuntimeFlagsTable(attachedDatabase, alias);
  }
}

class RuntimeFlag extends DataClass implements Insertable<RuntimeFlag> {
  final String key;
  final bool boolValue;
  final String source;
  final int updatedAtUtcMs;
  final int? expiresAtUtcMs;
  const RuntimeFlag({
    required this.key,
    required this.boolValue,
    required this.source,
    required this.updatedAtUtcMs,
    this.expiresAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['bool_value'] = Variable<bool>(boolValue);
    map['source'] = Variable<String>(source);
    map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs);
    if (!nullToAbsent || expiresAtUtcMs != null) {
      map['expires_at_utc_ms'] = Variable<int>(expiresAtUtcMs);
    }
    return map;
  }

  RuntimeFlagsCompanion toCompanion(bool nullToAbsent) {
    return RuntimeFlagsCompanion(
      key: Value(key),
      boolValue: Value(boolValue),
      source: Value(source),
      updatedAtUtcMs: Value(updatedAtUtcMs),
      expiresAtUtcMs: expiresAtUtcMs == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAtUtcMs),
    );
  }

  factory RuntimeFlag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RuntimeFlag(
      key: serializer.fromJson<String>(json['key']),
      boolValue: serializer.fromJson<bool>(json['boolValue']),
      source: serializer.fromJson<String>(json['source']),
      updatedAtUtcMs: serializer.fromJson<int>(json['updatedAtUtcMs']),
      expiresAtUtcMs: serializer.fromJson<int?>(json['expiresAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'boolValue': serializer.toJson<bool>(boolValue),
      'source': serializer.toJson<String>(source),
      'updatedAtUtcMs': serializer.toJson<int>(updatedAtUtcMs),
      'expiresAtUtcMs': serializer.toJson<int?>(expiresAtUtcMs),
    };
  }

  RuntimeFlag copyWith({
    String? key,
    bool? boolValue,
    String? source,
    int? updatedAtUtcMs,
    Value<int?> expiresAtUtcMs = const Value.absent(),
  }) => RuntimeFlag(
    key: key ?? this.key,
    boolValue: boolValue ?? this.boolValue,
    source: source ?? this.source,
    updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
    expiresAtUtcMs: expiresAtUtcMs.present
        ? expiresAtUtcMs.value
        : this.expiresAtUtcMs,
  );
  RuntimeFlag copyWithCompanion(RuntimeFlagsCompanion data) {
    return RuntimeFlag(
      key: data.key.present ? data.key.value : this.key,
      boolValue: data.boolValue.present ? data.boolValue.value : this.boolValue,
      source: data.source.present ? data.source.value : this.source,
      updatedAtUtcMs: data.updatedAtUtcMs.present
          ? data.updatedAtUtcMs.value
          : this.updatedAtUtcMs,
      expiresAtUtcMs: data.expiresAtUtcMs.present
          ? data.expiresAtUtcMs.value
          : this.expiresAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RuntimeFlag(')
          ..write('key: $key, ')
          ..write('boolValue: $boolValue, ')
          ..write('source: $source, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs, ')
          ..write('expiresAtUtcMs: $expiresAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(key, boolValue, source, updatedAtUtcMs, expiresAtUtcMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RuntimeFlag &&
          other.key == this.key &&
          other.boolValue == this.boolValue &&
          other.source == this.source &&
          other.updatedAtUtcMs == this.updatedAtUtcMs &&
          other.expiresAtUtcMs == this.expiresAtUtcMs);
}

class RuntimeFlagsCompanion extends UpdateCompanion<RuntimeFlag> {
  final Value<String> key;
  final Value<bool> boolValue;
  final Value<String> source;
  final Value<int> updatedAtUtcMs;
  final Value<int?> expiresAtUtcMs;
  final Value<int> rowid;
  const RuntimeFlagsCompanion({
    this.key = const Value.absent(),
    this.boolValue = const Value.absent(),
    this.source = const Value.absent(),
    this.updatedAtUtcMs = const Value.absent(),
    this.expiresAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RuntimeFlagsCompanion.insert({
    required String key,
    required bool boolValue,
    this.source = const Value.absent(),
    required int updatedAtUtcMs,
    this.expiresAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       boolValue = Value(boolValue),
       updatedAtUtcMs = Value(updatedAtUtcMs);
  static Insertable<RuntimeFlag> custom({
    Expression<String>? key,
    Expression<bool>? boolValue,
    Expression<String>? source,
    Expression<int>? updatedAtUtcMs,
    Expression<int>? expiresAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (boolValue != null) 'bool_value': boolValue,
      if (source != null) 'source': source,
      if (updatedAtUtcMs != null) 'updated_at_utc_ms': updatedAtUtcMs,
      if (expiresAtUtcMs != null) 'expires_at_utc_ms': expiresAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RuntimeFlagsCompanion copyWith({
    Value<String>? key,
    Value<bool>? boolValue,
    Value<String>? source,
    Value<int>? updatedAtUtcMs,
    Value<int?>? expiresAtUtcMs,
    Value<int>? rowid,
  }) {
    return RuntimeFlagsCompanion(
      key: key ?? this.key,
      boolValue: boolValue ?? this.boolValue,
      source: source ?? this.source,
      updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
      expiresAtUtcMs: expiresAtUtcMs ?? this.expiresAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (boolValue.present) {
      map['bool_value'] = Variable<bool>(boolValue.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (updatedAtUtcMs.present) {
      map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs.value);
    }
    if (expiresAtUtcMs.present) {
      map['expires_at_utc_ms'] = Variable<int>(expiresAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RuntimeFlagsCompanion(')
          ..write('key: $key, ')
          ..write('boolValue: $boolValue, ')
          ..write('source: $source, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs, ')
          ..write('expiresAtUtcMs: $expiresAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ModelDownloadsTable extends ModelDownloads
    with TableInfo<$ModelDownloadsTable, ModelDownload> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModelDownloadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelVersionMeta = const VerificationMeta(
    'modelVersion',
  );
  @override
  late final GeneratedColumn<String> modelVersion = GeneratedColumn<String>(
    'model_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceUrlMeta = const VerificationMeta(
    'sourceUrl',
  );
  @override
  late final GeneratedColumn<String> sourceUrl = GeneratedColumn<String>(
    'source_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedChecksumMeta = const VerificationMeta(
    'expectedChecksum',
  );
  @override
  late final GeneratedColumn<String> expectedChecksum = GeneratedColumn<String>(
    'expected_checksum',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedBytesMeta = const VerificationMeta(
    'expectedBytes',
  );
  @override
  late final GeneratedColumn<int> expectedBytes = GeneratedColumn<int>(
    'expected_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _downloadedBytesMeta = const VerificationMeta(
    'downloadedBytes',
  );
  @override
  late final GeneratedColumn<int> downloadedBytes = GeneratedColumn<int>(
    'downloaded_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('notStarted'),
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureCodeMeta = const VerificationMeta(
    'failureCode',
  );
  @override
  late final GeneratedColumn<String> failureCode = GeneratedColumn<String>(
    'failure_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtUtcMsMeta = const VerificationMeta(
    'updatedAtUtcMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtcMs = GeneratedColumn<int>(
    'updated_at_utc_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    modelVersion,
    sourceUrl,
    expectedChecksum,
    expectedBytes,
    downloadedBytes,
    retryCount,
    state,
    localPath,
    failureCode,
    updatedAtUtcMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'model_downloads';
  @override
  VerificationContext validateIntegrity(
    Insertable<ModelDownload> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('model_version')) {
      context.handle(
        _modelVersionMeta,
        modelVersion.isAcceptableOrUnknown(
          data['model_version']!,
          _modelVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_modelVersionMeta);
    }
    if (data.containsKey('source_url')) {
      context.handle(
        _sourceUrlMeta,
        sourceUrl.isAcceptableOrUnknown(data['source_url']!, _sourceUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceUrlMeta);
    }
    if (data.containsKey('expected_checksum')) {
      context.handle(
        _expectedChecksumMeta,
        expectedChecksum.isAcceptableOrUnknown(
          data['expected_checksum']!,
          _expectedChecksumMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expectedChecksumMeta);
    }
    if (data.containsKey('expected_bytes')) {
      context.handle(
        _expectedBytesMeta,
        expectedBytes.isAcceptableOrUnknown(
          data['expected_bytes']!,
          _expectedBytesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expectedBytesMeta);
    }
    if (data.containsKey('downloaded_bytes')) {
      context.handle(
        _downloadedBytesMeta,
        downloadedBytes.isAcceptableOrUnknown(
          data['downloaded_bytes']!,
          _downloadedBytesMeta,
        ),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('failure_code')) {
      context.handle(
        _failureCodeMeta,
        failureCode.isAcceptableOrUnknown(
          data['failure_code']!,
          _failureCodeMeta,
        ),
      );
    }
    if (data.containsKey('updated_at_utc_ms')) {
      context.handle(
        _updatedAtUtcMsMeta,
        updatedAtUtcMs.isAcceptableOrUnknown(
          data['updated_at_utc_ms']!,
          _updatedAtUtcMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {modelVersion},
  ];
  @override
  ModelDownload map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ModelDownload(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      modelVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_version'],
      )!,
      sourceUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_url'],
      )!,
      expectedChecksum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expected_checksum'],
      )!,
      expectedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_bytes'],
      )!,
      downloadedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}downloaded_bytes'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      failureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_code'],
      ),
      updatedAtUtcMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc_ms'],
      )!,
    );
  }

  @override
  $ModelDownloadsTable createAlias(String alias) {
    return $ModelDownloadsTable(attachedDatabase, alias);
  }
}

class ModelDownload extends DataClass implements Insertable<ModelDownload> {
  final String id;
  final String modelVersion;
  final String sourceUrl;
  final String expectedChecksum;
  final int expectedBytes;
  final int downloadedBytes;
  final int retryCount;
  final String state;
  final String? localPath;
  final String? failureCode;
  final int updatedAtUtcMs;
  const ModelDownload({
    required this.id,
    required this.modelVersion,
    required this.sourceUrl,
    required this.expectedChecksum,
    required this.expectedBytes,
    required this.downloadedBytes,
    required this.retryCount,
    required this.state,
    this.localPath,
    this.failureCode,
    required this.updatedAtUtcMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['model_version'] = Variable<String>(modelVersion);
    map['source_url'] = Variable<String>(sourceUrl);
    map['expected_checksum'] = Variable<String>(expectedChecksum);
    map['expected_bytes'] = Variable<int>(expectedBytes);
    map['downloaded_bytes'] = Variable<int>(downloadedBytes);
    map['retry_count'] = Variable<int>(retryCount);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    if (!nullToAbsent || failureCode != null) {
      map['failure_code'] = Variable<String>(failureCode);
    }
    map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs);
    return map;
  }

  ModelDownloadsCompanion toCompanion(bool nullToAbsent) {
    return ModelDownloadsCompanion(
      id: Value(id),
      modelVersion: Value(modelVersion),
      sourceUrl: Value(sourceUrl),
      expectedChecksum: Value(expectedChecksum),
      expectedBytes: Value(expectedBytes),
      downloadedBytes: Value(downloadedBytes),
      retryCount: Value(retryCount),
      state: Value(state),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      failureCode: failureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(failureCode),
      updatedAtUtcMs: Value(updatedAtUtcMs),
    );
  }

  factory ModelDownload.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ModelDownload(
      id: serializer.fromJson<String>(json['id']),
      modelVersion: serializer.fromJson<String>(json['modelVersion']),
      sourceUrl: serializer.fromJson<String>(json['sourceUrl']),
      expectedChecksum: serializer.fromJson<String>(json['expectedChecksum']),
      expectedBytes: serializer.fromJson<int>(json['expectedBytes']),
      downloadedBytes: serializer.fromJson<int>(json['downloadedBytes']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      state: serializer.fromJson<String>(json['state']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      failureCode: serializer.fromJson<String?>(json['failureCode']),
      updatedAtUtcMs: serializer.fromJson<int>(json['updatedAtUtcMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'modelVersion': serializer.toJson<String>(modelVersion),
      'sourceUrl': serializer.toJson<String>(sourceUrl),
      'expectedChecksum': serializer.toJson<String>(expectedChecksum),
      'expectedBytes': serializer.toJson<int>(expectedBytes),
      'downloadedBytes': serializer.toJson<int>(downloadedBytes),
      'retryCount': serializer.toJson<int>(retryCount),
      'state': serializer.toJson<String>(state),
      'localPath': serializer.toJson<String?>(localPath),
      'failureCode': serializer.toJson<String?>(failureCode),
      'updatedAtUtcMs': serializer.toJson<int>(updatedAtUtcMs),
    };
  }

  ModelDownload copyWith({
    String? id,
    String? modelVersion,
    String? sourceUrl,
    String? expectedChecksum,
    int? expectedBytes,
    int? downloadedBytes,
    int? retryCount,
    String? state,
    Value<String?> localPath = const Value.absent(),
    Value<String?> failureCode = const Value.absent(),
    int? updatedAtUtcMs,
  }) => ModelDownload(
    id: id ?? this.id,
    modelVersion: modelVersion ?? this.modelVersion,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    expectedChecksum: expectedChecksum ?? this.expectedChecksum,
    expectedBytes: expectedBytes ?? this.expectedBytes,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    retryCount: retryCount ?? this.retryCount,
    state: state ?? this.state,
    localPath: localPath.present ? localPath.value : this.localPath,
    failureCode: failureCode.present ? failureCode.value : this.failureCode,
    updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
  );
  ModelDownload copyWithCompanion(ModelDownloadsCompanion data) {
    return ModelDownload(
      id: data.id.present ? data.id.value : this.id,
      modelVersion: data.modelVersion.present
          ? data.modelVersion.value
          : this.modelVersion,
      sourceUrl: data.sourceUrl.present ? data.sourceUrl.value : this.sourceUrl,
      expectedChecksum: data.expectedChecksum.present
          ? data.expectedChecksum.value
          : this.expectedChecksum,
      expectedBytes: data.expectedBytes.present
          ? data.expectedBytes.value
          : this.expectedBytes,
      downloadedBytes: data.downloadedBytes.present
          ? data.downloadedBytes.value
          : this.downloadedBytes,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      state: data.state.present ? data.state.value : this.state,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      failureCode: data.failureCode.present
          ? data.failureCode.value
          : this.failureCode,
      updatedAtUtcMs: data.updatedAtUtcMs.present
          ? data.updatedAtUtcMs.value
          : this.updatedAtUtcMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ModelDownload(')
          ..write('id: $id, ')
          ..write('modelVersion: $modelVersion, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('expectedChecksum: $expectedChecksum, ')
          ..write('expectedBytes: $expectedBytes, ')
          ..write('downloadedBytes: $downloadedBytes, ')
          ..write('retryCount: $retryCount, ')
          ..write('state: $state, ')
          ..write('localPath: $localPath, ')
          ..write('failureCode: $failureCode, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    modelVersion,
    sourceUrl,
    expectedChecksum,
    expectedBytes,
    downloadedBytes,
    retryCount,
    state,
    localPath,
    failureCode,
    updatedAtUtcMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ModelDownload &&
          other.id == this.id &&
          other.modelVersion == this.modelVersion &&
          other.sourceUrl == this.sourceUrl &&
          other.expectedChecksum == this.expectedChecksum &&
          other.expectedBytes == this.expectedBytes &&
          other.downloadedBytes == this.downloadedBytes &&
          other.retryCount == this.retryCount &&
          other.state == this.state &&
          other.localPath == this.localPath &&
          other.failureCode == this.failureCode &&
          other.updatedAtUtcMs == this.updatedAtUtcMs);
}

class ModelDownloadsCompanion extends UpdateCompanion<ModelDownload> {
  final Value<String> id;
  final Value<String> modelVersion;
  final Value<String> sourceUrl;
  final Value<String> expectedChecksum;
  final Value<int> expectedBytes;
  final Value<int> downloadedBytes;
  final Value<int> retryCount;
  final Value<String> state;
  final Value<String?> localPath;
  final Value<String?> failureCode;
  final Value<int> updatedAtUtcMs;
  final Value<int> rowid;
  const ModelDownloadsCompanion({
    this.id = const Value.absent(),
    this.modelVersion = const Value.absent(),
    this.sourceUrl = const Value.absent(),
    this.expectedChecksum = const Value.absent(),
    this.expectedBytes = const Value.absent(),
    this.downloadedBytes = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.state = const Value.absent(),
    this.localPath = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.updatedAtUtcMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModelDownloadsCompanion.insert({
    required String id,
    required String modelVersion,
    required String sourceUrl,
    required String expectedChecksum,
    required int expectedBytes,
    this.downloadedBytes = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.state = const Value.absent(),
    this.localPath = const Value.absent(),
    this.failureCode = const Value.absent(),
    required int updatedAtUtcMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       modelVersion = Value(modelVersion),
       sourceUrl = Value(sourceUrl),
       expectedChecksum = Value(expectedChecksum),
       expectedBytes = Value(expectedBytes),
       updatedAtUtcMs = Value(updatedAtUtcMs);
  static Insertable<ModelDownload> custom({
    Expression<String>? id,
    Expression<String>? modelVersion,
    Expression<String>? sourceUrl,
    Expression<String>? expectedChecksum,
    Expression<int>? expectedBytes,
    Expression<int>? downloadedBytes,
    Expression<int>? retryCount,
    Expression<String>? state,
    Expression<String>? localPath,
    Expression<String>? failureCode,
    Expression<int>? updatedAtUtcMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (modelVersion != null) 'model_version': modelVersion,
      if (sourceUrl != null) 'source_url': sourceUrl,
      if (expectedChecksum != null) 'expected_checksum': expectedChecksum,
      if (expectedBytes != null) 'expected_bytes': expectedBytes,
      if (downloadedBytes != null) 'downloaded_bytes': downloadedBytes,
      if (retryCount != null) 'retry_count': retryCount,
      if (state != null) 'state': state,
      if (localPath != null) 'local_path': localPath,
      if (failureCode != null) 'failure_code': failureCode,
      if (updatedAtUtcMs != null) 'updated_at_utc_ms': updatedAtUtcMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModelDownloadsCompanion copyWith({
    Value<String>? id,
    Value<String>? modelVersion,
    Value<String>? sourceUrl,
    Value<String>? expectedChecksum,
    Value<int>? expectedBytes,
    Value<int>? downloadedBytes,
    Value<int>? retryCount,
    Value<String>? state,
    Value<String?>? localPath,
    Value<String?>? failureCode,
    Value<int>? updatedAtUtcMs,
    Value<int>? rowid,
  }) {
    return ModelDownloadsCompanion(
      id: id ?? this.id,
      modelVersion: modelVersion ?? this.modelVersion,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      expectedChecksum: expectedChecksum ?? this.expectedChecksum,
      expectedBytes: expectedBytes ?? this.expectedBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      retryCount: retryCount ?? this.retryCount,
      state: state ?? this.state,
      localPath: localPath ?? this.localPath,
      failureCode: failureCode ?? this.failureCode,
      updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (modelVersion.present) {
      map['model_version'] = Variable<String>(modelVersion.value);
    }
    if (sourceUrl.present) {
      map['source_url'] = Variable<String>(sourceUrl.value);
    }
    if (expectedChecksum.present) {
      map['expected_checksum'] = Variable<String>(expectedChecksum.value);
    }
    if (expectedBytes.present) {
      map['expected_bytes'] = Variable<int>(expectedBytes.value);
    }
    if (downloadedBytes.present) {
      map['downloaded_bytes'] = Variable<int>(downloadedBytes.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (failureCode.present) {
      map['failure_code'] = Variable<String>(failureCode.value);
    }
    if (updatedAtUtcMs.present) {
      map['updated_at_utc_ms'] = Variable<int>(updatedAtUtcMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModelDownloadsCompanion(')
          ..write('id: $id, ')
          ..write('modelVersion: $modelVersion, ')
          ..write('sourceUrl: $sourceUrl, ')
          ..write('expectedChecksum: $expectedChecksum, ')
          ..write('expectedBytes: $expectedBytes, ')
          ..write('downloadedBytes: $downloadedBytes, ')
          ..write('retryCount: $retryCount, ')
          ..write('state: $state, ')
          ..write('localPath: $localPath, ')
          ..write('failureCode: $failureCode, ')
          ..write('updatedAtUtcMs: $updatedAtUtcMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalOwnersTable localOwners = $LocalOwnersTable(this);
  late final $ResearchConsentsTable researchConsents = $ResearchConsentsTable(
    this,
  );
  late final $VocabularyCategoriesTable vocabularyCategories =
      $VocabularyCategoriesTable(this);
  late final $VocabularyWordsTable vocabularyWords = $VocabularyWordsTable(
    this,
  );
  late final $VocabularyImportsTable vocabularyImports =
      $VocabularyImportsTable(this);
  late final $VocabularyImportRowsTable vocabularyImportRows =
      $VocabularyImportRowsTable(this);
  late final $LearningSessionsTable learningSessions = $LearningSessionsTable(
    this,
  );
  late final $AnswerAttemptsTable answerAttempts = $AnswerAttemptsTable(this);
  late final $SrsStatesTable srsStates = $SrsStatesTable(this);
  late final $ReadingProgressEntriesTable readingProgressEntries =
      $ReadingProgressEntriesTable(this);
  late final $ReadingEventsTable readingEvents = $ReadingEventsTable(this);
  late final $PointsLedgerEntriesTable pointsLedgerEntries =
      $PointsLedgerEntriesTable(this);
  late final $AchievementUnlocksTable achievementUnlocks =
      $AchievementUnlocksTable(this);
  late final $RewardTransactionsTable rewardTransactions =
      $RewardTransactionsTable(this);
  late final $OwnedRewardItemsTable ownedRewardItems = $OwnedRewardItemsTable(
    this,
  );
  late final $EquippedRewardItemsTable equippedRewardItems =
      $EquippedRewardItemsTable(this);
  late final $OutboxOperationsTable outboxOperations = $OutboxOperationsTable(
    this,
  );
  late final $SyncCheckpointsTable syncCheckpoints = $SyncCheckpointsTable(
    this,
  );
  late final $SyncConflictsTable syncConflicts = $SyncConflictsTable(this);
  late final $RuntimeFlagsTable runtimeFlags = $RuntimeFlagsTable(this);
  late final $ModelDownloadsTable modelDownloads = $ModelDownloadsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localOwners,
    researchConsents,
    vocabularyCategories,
    vocabularyWords,
    vocabularyImports,
    vocabularyImportRows,
    learningSessions,
    answerAttempts,
    srsStates,
    readingProgressEntries,
    readingEvents,
    pointsLedgerEntries,
    achievementUnlocks,
    rewardTransactions,
    ownedRewardItems,
    equippedRewardItems,
    outboxOperations,
    syncCheckpoints,
    syncConflicts,
    runtimeFlags,
    modelDownloads,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'vocabulary_imports',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('vocabulary_import_rows', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'learning_sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('answer_attempts', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$LocalOwnersTableCreateCompanionBuilder =
    LocalOwnersCompanion Function({
      required String id,
      Value<String?> firebaseUid,
      Value<String> accountState,
      required int createdAtUtcMs,
      Value<int?> upgradedAtUtcMs,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$LocalOwnersTableUpdateCompanionBuilder =
    LocalOwnersCompanion Function({
      Value<String> id,
      Value<String?> firebaseUid,
      Value<String> accountState,
      Value<int> createdAtUtcMs,
      Value<int?> upgradedAtUtcMs,
      Value<bool> isActive,
      Value<int> rowid,
    });

final class $$LocalOwnersTableReferences
    extends BaseReferences<_$AppDatabase, $LocalOwnersTable, LocalOwner> {
  $$LocalOwnersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ResearchConsentsTable, List<ResearchConsent>>
  _researchConsentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.researchConsents,
    aliasName: 'local_owners__id__research_consents__owner_id',
  );

  $$ResearchConsentsTableProcessedTableManager get researchConsentsRefs {
    final manager = $$ResearchConsentsTableTableManager(
      $_db,
      $_db.researchConsents,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _researchConsentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $VocabularyCategoriesTable,
    List<VocabularyCategory>
  >
  _vocabularyCategoriesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.vocabularyCategories,
        aliasName: 'local_owners__id__vocabulary_categories__owner_id',
      );

  $$VocabularyCategoriesTableProcessedTableManager
  get vocabularyCategoriesRefs {
    final manager = $$VocabularyCategoriesTableTableManager(
      $_db,
      $_db.vocabularyCategories,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _vocabularyCategoriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$VocabularyWordsTable, List<VocabularyWord>>
  _vocabularyWordsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.vocabularyWords,
    aliasName: 'local_owners__id__vocabulary_words__owner_id',
  );

  $$VocabularyWordsTableProcessedTableManager get vocabularyWordsRefs {
    final manager = $$VocabularyWordsTableTableManager(
      $_db,
      $_db.vocabularyWords,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _vocabularyWordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$VocabularyImportsTable, List<VocabularyImport>>
  _vocabularyImportsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.vocabularyImports,
        aliasName: 'local_owners__id__vocabulary_imports__owner_id',
      );

  $$VocabularyImportsTableProcessedTableManager get vocabularyImportsRefs {
    final manager = $$VocabularyImportsTableTableManager(
      $_db,
      $_db.vocabularyImports,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _vocabularyImportsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$LearningSessionsTable, List<LearningSession>>
  _learningSessionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.learningSessions,
    aliasName: 'local_owners__id__learning_sessions__owner_id',
  );

  $$LearningSessionsTableProcessedTableManager get learningSessionsRefs {
    final manager = $$LearningSessionsTableTableManager(
      $_db,
      $_db.learningSessions,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _learningSessionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AnswerAttemptsTable, List<AnswerAttempt>>
  _answerAttemptsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.answerAttempts,
    aliasName: 'local_owners__id__answer_attempts__owner_id',
  );

  $$AnswerAttemptsTableProcessedTableManager get answerAttemptsRefs {
    final manager = $$AnswerAttemptsTableTableManager(
      $_db,
      $_db.answerAttempts,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_answerAttemptsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SrsStatesTable, List<SrsState>>
  _srsStatesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.srsStates,
    aliasName: 'local_owners__id__srs_states__owner_id',
  );

  $$SrsStatesTableProcessedTableManager get srsStatesRefs {
    final manager = $$SrsStatesTableTableManager(
      $_db,
      $_db.srsStates,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_srsStatesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ReadingProgressEntriesTable,
    List<ReadingProgressEntry>
  >
  _readingProgressEntriesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.readingProgressEntries,
        aliasName: 'local_owners__id__reading_progress_entries__owner_id',
      );

  $$ReadingProgressEntriesTableProcessedTableManager
  get readingProgressEntriesRefs {
    final manager = $$ReadingProgressEntriesTableTableManager(
      $_db,
      $_db.readingProgressEntries,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _readingProgressEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReadingEventsTable, List<ReadingEvent>>
  _readingEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.readingEvents,
    aliasName: 'local_owners__id__reading_events__owner_id',
  );

  $$ReadingEventsTableProcessedTableManager get readingEventsRefs {
    final manager = $$ReadingEventsTableTableManager(
      $_db,
      $_db.readingEvents,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_readingEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PointsLedgerEntriesTable, List<PointsLedgerEntry>>
  _pointsLedgerEntriesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.pointsLedgerEntries,
        aliasName: 'local_owners__id__points_ledger_entries__owner_id',
      );

  $$PointsLedgerEntriesTableProcessedTableManager get pointsLedgerEntriesRefs {
    final manager = $$PointsLedgerEntriesTableTableManager(
      $_db,
      $_db.pointsLedgerEntries,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _pointsLedgerEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AchievementUnlocksTable, List<AchievementUnlock>>
  _achievementUnlocksRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.achievementUnlocks,
        aliasName: 'local_owners__id__achievement_unlocks__owner_id',
      );

  $$AchievementUnlocksTableProcessedTableManager get achievementUnlocksRefs {
    final manager = $$AchievementUnlocksTableTableManager(
      $_db,
      $_db.achievementUnlocks,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _achievementUnlocksRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RewardTransactionsTable, List<RewardTransaction>>
  _rewardTransactionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.rewardTransactions,
        aliasName: 'local_owners__id__reward_transactions__owner_id',
      );

  $$RewardTransactionsTableProcessedTableManager get rewardTransactionsRefs {
    final manager = $$RewardTransactionsTableTableManager(
      $_db,
      $_db.rewardTransactions,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _rewardTransactionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OwnedRewardItemsTable, List<OwnedRewardItem>>
  _ownedRewardItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.ownedRewardItems,
    aliasName: 'local_owners__id__owned_reward_items__owner_id',
  );

  $$OwnedRewardItemsTableProcessedTableManager get ownedRewardItemsRefs {
    final manager = $$OwnedRewardItemsTableTableManager(
      $_db,
      $_db.ownedRewardItems,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _ownedRewardItemsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $EquippedRewardItemsTable,
    List<EquippedRewardItem>
  >
  _equippedRewardItemsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.equippedRewardItems,
        aliasName: 'local_owners__id__equipped_reward_items__owner_id',
      );

  $$EquippedRewardItemsTableProcessedTableManager get equippedRewardItemsRefs {
    final manager = $$EquippedRewardItemsTableTableManager(
      $_db,
      $_db.equippedRewardItems,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _equippedRewardItemsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OutboxOperationsTable, List<OutboxOperation>>
  _outboxOperationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.outboxOperations,
    aliasName: 'local_owners__id__outbox_operations__owner_id',
  );

  $$OutboxOperationsTableProcessedTableManager get outboxOperationsRefs {
    final manager = $$OutboxOperationsTableTableManager(
      $_db,
      $_db.outboxOperations,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _outboxOperationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SyncCheckpointsTable, List<SyncCheckpoint>>
  _syncCheckpointsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.syncCheckpoints,
    aliasName: 'local_owners__id__sync_checkpoints__owner_id',
  );

  $$SyncCheckpointsTableProcessedTableManager get syncCheckpointsRefs {
    final manager = $$SyncCheckpointsTableTableManager(
      $_db,
      $_db.syncCheckpoints,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _syncCheckpointsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SyncConflictsTable, List<SyncConflict>>
  _syncConflictsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.syncConflicts,
    aliasName: 'local_owners__id__sync_conflicts__owner_id',
  );

  $$SyncConflictsTableProcessedTableManager get syncConflictsRefs {
    final manager = $$SyncConflictsTableTableManager(
      $_db,
      $_db.syncConflicts,
    ).filter((f) => f.ownerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_syncConflictsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LocalOwnersTableFilterComposer
    extends Composer<_$AppDatabase, $LocalOwnersTable> {
  $$LocalOwnersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firebaseUid => $composableBuilder(
    column: $table.firebaseUid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountState => $composableBuilder(
    column: $table.accountState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get upgradedAtUtcMs => $composableBuilder(
    column: $table.upgradedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> researchConsentsRefs(
    Expression<bool> Function($$ResearchConsentsTableFilterComposer f) f,
  ) {
    final $$ResearchConsentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.researchConsents,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ResearchConsentsTableFilterComposer(
            $db: $db,
            $table: $db.researchConsents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> vocabularyCategoriesRefs(
    Expression<bool> Function($$VocabularyCategoriesTableFilterComposer f) f,
  ) {
    final $$VocabularyCategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.vocabularyCategories,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyCategoriesTableFilterComposer(
            $db: $db,
            $table: $db.vocabularyCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> vocabularyWordsRefs(
    Expression<bool> Function($$VocabularyWordsTableFilterComposer f) f,
  ) {
    final $$VocabularyWordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.vocabularyWords,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyWordsTableFilterComposer(
            $db: $db,
            $table: $db.vocabularyWords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> vocabularyImportsRefs(
    Expression<bool> Function($$VocabularyImportsTableFilterComposer f) f,
  ) {
    final $$VocabularyImportsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.vocabularyImports,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyImportsTableFilterComposer(
            $db: $db,
            $table: $db.vocabularyImports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> learningSessionsRefs(
    Expression<bool> Function($$LearningSessionsTableFilterComposer f) f,
  ) {
    final $$LearningSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableFilterComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> answerAttemptsRefs(
    Expression<bool> Function($$AnswerAttemptsTableFilterComposer f) f,
  ) {
    final $$AnswerAttemptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.answerAttempts,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnswerAttemptsTableFilterComposer(
            $db: $db,
            $table: $db.answerAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> srsStatesRefs(
    Expression<bool> Function($$SrsStatesTableFilterComposer f) f,
  ) {
    final $$SrsStatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.srsStates,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SrsStatesTableFilterComposer(
            $db: $db,
            $table: $db.srsStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> readingProgressEntriesRefs(
    Expression<bool> Function($$ReadingProgressEntriesTableFilterComposer f) f,
  ) {
    final $$ReadingProgressEntriesTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.readingProgressEntries,
          getReferencedColumn: (t) => t.ownerId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReadingProgressEntriesTableFilterComposer(
                $db: $db,
                $table: $db.readingProgressEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> readingEventsRefs(
    Expression<bool> Function($$ReadingEventsTableFilterComposer f) f,
  ) {
    final $$ReadingEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingEvents,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingEventsTableFilterComposer(
            $db: $db,
            $table: $db.readingEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> pointsLedgerEntriesRefs(
    Expression<bool> Function($$PointsLedgerEntriesTableFilterComposer f) f,
  ) {
    final $$PointsLedgerEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pointsLedgerEntries,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PointsLedgerEntriesTableFilterComposer(
            $db: $db,
            $table: $db.pointsLedgerEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> achievementUnlocksRefs(
    Expression<bool> Function($$AchievementUnlocksTableFilterComposer f) f,
  ) {
    final $$AchievementUnlocksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.achievementUnlocks,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AchievementUnlocksTableFilterComposer(
            $db: $db,
            $table: $db.achievementUnlocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> rewardTransactionsRefs(
    Expression<bool> Function($$RewardTransactionsTableFilterComposer f) f,
  ) {
    final $$RewardTransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rewardTransactions,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RewardTransactionsTableFilterComposer(
            $db: $db,
            $table: $db.rewardTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> ownedRewardItemsRefs(
    Expression<bool> Function($$OwnedRewardItemsTableFilterComposer f) f,
  ) {
    final $$OwnedRewardItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ownedRewardItems,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OwnedRewardItemsTableFilterComposer(
            $db: $db,
            $table: $db.ownedRewardItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> equippedRewardItemsRefs(
    Expression<bool> Function($$EquippedRewardItemsTableFilterComposer f) f,
  ) {
    final $$EquippedRewardItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.equippedRewardItems,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EquippedRewardItemsTableFilterComposer(
            $db: $db,
            $table: $db.equippedRewardItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> outboxOperationsRefs(
    Expression<bool> Function($$OutboxOperationsTableFilterComposer f) f,
  ) {
    final $$OutboxOperationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outboxOperations,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxOperationsTableFilterComposer(
            $db: $db,
            $table: $db.outboxOperations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> syncCheckpointsRefs(
    Expression<bool> Function($$SyncCheckpointsTableFilterComposer f) f,
  ) {
    final $$SyncCheckpointsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.syncCheckpoints,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncCheckpointsTableFilterComposer(
            $db: $db,
            $table: $db.syncCheckpoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> syncConflictsRefs(
    Expression<bool> Function($$SyncConflictsTableFilterComposer f) f,
  ) {
    final $$SyncConflictsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.syncConflicts,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncConflictsTableFilterComposer(
            $db: $db,
            $table: $db.syncConflicts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalOwnersTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalOwnersTable> {
  $$LocalOwnersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firebaseUid => $composableBuilder(
    column: $table.firebaseUid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountState => $composableBuilder(
    column: $table.accountState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get upgradedAtUtcMs => $composableBuilder(
    column: $table.upgradedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalOwnersTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalOwnersTable> {
  $$LocalOwnersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get firebaseUid => $composableBuilder(
    column: $table.firebaseUid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountState => $composableBuilder(
    column: $table.accountState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get upgradedAtUtcMs => $composableBuilder(
    column: $table.upgradedAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  Expression<T> researchConsentsRefs<T extends Object>(
    Expression<T> Function($$ResearchConsentsTableAnnotationComposer a) f,
  ) {
    final $$ResearchConsentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.researchConsents,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ResearchConsentsTableAnnotationComposer(
            $db: $db,
            $table: $db.researchConsents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> vocabularyCategoriesRefs<T extends Object>(
    Expression<T> Function($$VocabularyCategoriesTableAnnotationComposer a) f,
  ) {
    final $$VocabularyCategoriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.vocabularyCategories,
          getReferencedColumn: (t) => t.ownerId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$VocabularyCategoriesTableAnnotationComposer(
                $db: $db,
                $table: $db.vocabularyCategories,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> vocabularyWordsRefs<T extends Object>(
    Expression<T> Function($$VocabularyWordsTableAnnotationComposer a) f,
  ) {
    final $$VocabularyWordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.vocabularyWords,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyWordsTableAnnotationComposer(
            $db: $db,
            $table: $db.vocabularyWords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> vocabularyImportsRefs<T extends Object>(
    Expression<T> Function($$VocabularyImportsTableAnnotationComposer a) f,
  ) {
    final $$VocabularyImportsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.vocabularyImports,
          getReferencedColumn: (t) => t.ownerId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$VocabularyImportsTableAnnotationComposer(
                $db: $db,
                $table: $db.vocabularyImports,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> learningSessionsRefs<T extends Object>(
    Expression<T> Function($$LearningSessionsTableAnnotationComposer a) f,
  ) {
    final $$LearningSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> answerAttemptsRefs<T extends Object>(
    Expression<T> Function($$AnswerAttemptsTableAnnotationComposer a) f,
  ) {
    final $$AnswerAttemptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.answerAttempts,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnswerAttemptsTableAnnotationComposer(
            $db: $db,
            $table: $db.answerAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> srsStatesRefs<T extends Object>(
    Expression<T> Function($$SrsStatesTableAnnotationComposer a) f,
  ) {
    final $$SrsStatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.srsStates,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SrsStatesTableAnnotationComposer(
            $db: $db,
            $table: $db.srsStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> readingProgressEntriesRefs<T extends Object>(
    Expression<T> Function($$ReadingProgressEntriesTableAnnotationComposer a) f,
  ) {
    final $$ReadingProgressEntriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.readingProgressEntries,
          getReferencedColumn: (t) => t.ownerId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReadingProgressEntriesTableAnnotationComposer(
                $db: $db,
                $table: $db.readingProgressEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> readingEventsRefs<T extends Object>(
    Expression<T> Function($$ReadingEventsTableAnnotationComposer a) f,
  ) {
    final $$ReadingEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingEvents,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.readingEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> pointsLedgerEntriesRefs<T extends Object>(
    Expression<T> Function($$PointsLedgerEntriesTableAnnotationComposer a) f,
  ) {
    final $$PointsLedgerEntriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.pointsLedgerEntries,
          getReferencedColumn: (t) => t.ownerId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PointsLedgerEntriesTableAnnotationComposer(
                $db: $db,
                $table: $db.pointsLedgerEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> achievementUnlocksRefs<T extends Object>(
    Expression<T> Function($$AchievementUnlocksTableAnnotationComposer a) f,
  ) {
    final $$AchievementUnlocksTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.achievementUnlocks,
          getReferencedColumn: (t) => t.ownerId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AchievementUnlocksTableAnnotationComposer(
                $db: $db,
                $table: $db.achievementUnlocks,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> rewardTransactionsRefs<T extends Object>(
    Expression<T> Function($$RewardTransactionsTableAnnotationComposer a) f,
  ) {
    final $$RewardTransactionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.rewardTransactions,
          getReferencedColumn: (t) => t.ownerId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RewardTransactionsTableAnnotationComposer(
                $db: $db,
                $table: $db.rewardTransactions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> ownedRewardItemsRefs<T extends Object>(
    Expression<T> Function($$OwnedRewardItemsTableAnnotationComposer a) f,
  ) {
    final $$OwnedRewardItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ownedRewardItems,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OwnedRewardItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.ownedRewardItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> equippedRewardItemsRefs<T extends Object>(
    Expression<T> Function($$EquippedRewardItemsTableAnnotationComposer a) f,
  ) {
    final $$EquippedRewardItemsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.equippedRewardItems,
          getReferencedColumn: (t) => t.ownerId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$EquippedRewardItemsTableAnnotationComposer(
                $db: $db,
                $table: $db.equippedRewardItems,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> outboxOperationsRefs<T extends Object>(
    Expression<T> Function($$OutboxOperationsTableAnnotationComposer a) f,
  ) {
    final $$OutboxOperationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outboxOperations,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxOperationsTableAnnotationComposer(
            $db: $db,
            $table: $db.outboxOperations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> syncCheckpointsRefs<T extends Object>(
    Expression<T> Function($$SyncCheckpointsTableAnnotationComposer a) f,
  ) {
    final $$SyncCheckpointsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.syncCheckpoints,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncCheckpointsTableAnnotationComposer(
            $db: $db,
            $table: $db.syncCheckpoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> syncConflictsRefs<T extends Object>(
    Expression<T> Function($$SyncConflictsTableAnnotationComposer a) f,
  ) {
    final $$SyncConflictsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.syncConflicts,
      getReferencedColumn: (t) => t.ownerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncConflictsTableAnnotationComposer(
            $db: $db,
            $table: $db.syncConflicts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalOwnersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalOwnersTable,
          LocalOwner,
          $$LocalOwnersTableFilterComposer,
          $$LocalOwnersTableOrderingComposer,
          $$LocalOwnersTableAnnotationComposer,
          $$LocalOwnersTableCreateCompanionBuilder,
          $$LocalOwnersTableUpdateCompanionBuilder,
          (LocalOwner, $$LocalOwnersTableReferences),
          LocalOwner,
          PrefetchHooks Function({
            bool researchConsentsRefs,
            bool vocabularyCategoriesRefs,
            bool vocabularyWordsRefs,
            bool vocabularyImportsRefs,
            bool learningSessionsRefs,
            bool answerAttemptsRefs,
            bool srsStatesRefs,
            bool readingProgressEntriesRefs,
            bool readingEventsRefs,
            bool pointsLedgerEntriesRefs,
            bool achievementUnlocksRefs,
            bool rewardTransactionsRefs,
            bool ownedRewardItemsRefs,
            bool equippedRewardItemsRefs,
            bool outboxOperationsRefs,
            bool syncCheckpointsRefs,
            bool syncConflictsRefs,
          })
        > {
  $$LocalOwnersTableTableManager(_$AppDatabase db, $LocalOwnersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalOwnersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalOwnersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalOwnersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> firebaseUid = const Value.absent(),
                Value<String> accountState = const Value.absent(),
                Value<int> createdAtUtcMs = const Value.absent(),
                Value<int?> upgradedAtUtcMs = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalOwnersCompanion(
                id: id,
                firebaseUid: firebaseUid,
                accountState: accountState,
                createdAtUtcMs: createdAtUtcMs,
                upgradedAtUtcMs: upgradedAtUtcMs,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> firebaseUid = const Value.absent(),
                Value<String> accountState = const Value.absent(),
                required int createdAtUtcMs,
                Value<int?> upgradedAtUtcMs = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalOwnersCompanion.insert(
                id: id,
                firebaseUid: firebaseUid,
                accountState: accountState,
                createdAtUtcMs: createdAtUtcMs,
                upgradedAtUtcMs: upgradedAtUtcMs,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalOwnersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                researchConsentsRefs = false,
                vocabularyCategoriesRefs = false,
                vocabularyWordsRefs = false,
                vocabularyImportsRefs = false,
                learningSessionsRefs = false,
                answerAttemptsRefs = false,
                srsStatesRefs = false,
                readingProgressEntriesRefs = false,
                readingEventsRefs = false,
                pointsLedgerEntriesRefs = false,
                achievementUnlocksRefs = false,
                rewardTransactionsRefs = false,
                ownedRewardItemsRefs = false,
                equippedRewardItemsRefs = false,
                outboxOperationsRefs = false,
                syncCheckpointsRefs = false,
                syncConflictsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (researchConsentsRefs) db.researchConsents,
                    if (vocabularyCategoriesRefs) db.vocabularyCategories,
                    if (vocabularyWordsRefs) db.vocabularyWords,
                    if (vocabularyImportsRefs) db.vocabularyImports,
                    if (learningSessionsRefs) db.learningSessions,
                    if (answerAttemptsRefs) db.answerAttempts,
                    if (srsStatesRefs) db.srsStates,
                    if (readingProgressEntriesRefs) db.readingProgressEntries,
                    if (readingEventsRefs) db.readingEvents,
                    if (pointsLedgerEntriesRefs) db.pointsLedgerEntries,
                    if (achievementUnlocksRefs) db.achievementUnlocks,
                    if (rewardTransactionsRefs) db.rewardTransactions,
                    if (ownedRewardItemsRefs) db.ownedRewardItems,
                    if (equippedRewardItemsRefs) db.equippedRewardItems,
                    if (outboxOperationsRefs) db.outboxOperations,
                    if (syncCheckpointsRefs) db.syncCheckpoints,
                    if (syncConflictsRefs) db.syncConflicts,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (researchConsentsRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          ResearchConsent
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._researchConsentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).researchConsentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (vocabularyCategoriesRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          VocabularyCategory
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._vocabularyCategoriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).vocabularyCategoriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (vocabularyWordsRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          VocabularyWord
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._vocabularyWordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).vocabularyWordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (vocabularyImportsRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          VocabularyImport
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._vocabularyImportsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).vocabularyImportsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (learningSessionsRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          LearningSession
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._learningSessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).learningSessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (answerAttemptsRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          AnswerAttempt
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._answerAttemptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).answerAttemptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (srsStatesRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          SrsState
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._srsStatesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).srsStatesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (readingProgressEntriesRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          ReadingProgressEntry
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._readingProgressEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).readingProgressEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (readingEventsRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          ReadingEvent
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._readingEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).readingEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (pointsLedgerEntriesRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          PointsLedgerEntry
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._pointsLedgerEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).pointsLedgerEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (achievementUnlocksRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          AchievementUnlock
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._achievementUnlocksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).achievementUnlocksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (rewardTransactionsRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          RewardTransaction
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._rewardTransactionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).rewardTransactionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (ownedRewardItemsRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          OwnedRewardItem
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._ownedRewardItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).ownedRewardItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (equippedRewardItemsRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          EquippedRewardItem
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._equippedRewardItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).equippedRewardItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (outboxOperationsRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          OutboxOperation
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._outboxOperationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).outboxOperationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (syncCheckpointsRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          SyncCheckpoint
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._syncCheckpointsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).syncCheckpointsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (syncConflictsRefs)
                        await $_getPrefetchedData<
                          LocalOwner,
                          $LocalOwnersTable,
                          SyncConflict
                        >(
                          currentTable: table,
                          referencedTable: $$LocalOwnersTableReferences
                              ._syncConflictsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LocalOwnersTableReferences(
                                db,
                                table,
                                p0,
                              ).syncConflictsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerId == item.id,
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

typedef $$LocalOwnersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalOwnersTable,
      LocalOwner,
      $$LocalOwnersTableFilterComposer,
      $$LocalOwnersTableOrderingComposer,
      $$LocalOwnersTableAnnotationComposer,
      $$LocalOwnersTableCreateCompanionBuilder,
      $$LocalOwnersTableUpdateCompanionBuilder,
      (LocalOwner, $$LocalOwnersTableReferences),
      LocalOwner,
      PrefetchHooks Function({
        bool researchConsentsRefs,
        bool vocabularyCategoriesRefs,
        bool vocabularyWordsRefs,
        bool vocabularyImportsRefs,
        bool learningSessionsRefs,
        bool answerAttemptsRefs,
        bool srsStatesRefs,
        bool readingProgressEntriesRefs,
        bool readingEventsRefs,
        bool pointsLedgerEntriesRefs,
        bool achievementUnlocksRefs,
        bool rewardTransactionsRefs,
        bool ownedRewardItemsRefs,
        bool equippedRewardItemsRefs,
        bool outboxOperationsRefs,
        bool syncCheckpointsRefs,
        bool syncConflictsRefs,
      })
    >;
typedef $$ResearchConsentsTableCreateCompanionBuilder =
    ResearchConsentsCompanion Function({
      required String id,
      required String ownerId,
      required int consentVersion,
      required String consentState,
      required int decidedAtUtcMs,
      Value<int?> withdrawnAtUtcMs,
      Value<int> rowid,
    });
typedef $$ResearchConsentsTableUpdateCompanionBuilder =
    ResearchConsentsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<int> consentVersion,
      Value<String> consentState,
      Value<int> decidedAtUtcMs,
      Value<int?> withdrawnAtUtcMs,
      Value<int> rowid,
    });

final class $$ResearchConsentsTableReferences
    extends
        BaseReferences<_$AppDatabase, $ResearchConsentsTable, ResearchConsent> {
  $$ResearchConsentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('research_consents__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ResearchConsentsTableFilterComposer
    extends Composer<_$AppDatabase, $ResearchConsentsTable> {
  $$ResearchConsentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get consentVersion => $composableBuilder(
    column: $table.consentVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get consentState => $composableBuilder(
    column: $table.consentState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get decidedAtUtcMs => $composableBuilder(
    column: $table.decidedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get withdrawnAtUtcMs => $composableBuilder(
    column: $table.withdrawnAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ResearchConsentsTableOrderingComposer
    extends Composer<_$AppDatabase, $ResearchConsentsTable> {
  $$ResearchConsentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get consentVersion => $composableBuilder(
    column: $table.consentVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get consentState => $composableBuilder(
    column: $table.consentState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get decidedAtUtcMs => $composableBuilder(
    column: $table.decidedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get withdrawnAtUtcMs => $composableBuilder(
    column: $table.withdrawnAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ResearchConsentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ResearchConsentsTable> {
  $$ResearchConsentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get consentVersion => $composableBuilder(
    column: $table.consentVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get consentState => $composableBuilder(
    column: $table.consentState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get decidedAtUtcMs => $composableBuilder(
    column: $table.decidedAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get withdrawnAtUtcMs => $composableBuilder(
    column: $table.withdrawnAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ResearchConsentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ResearchConsentsTable,
          ResearchConsent,
          $$ResearchConsentsTableFilterComposer,
          $$ResearchConsentsTableOrderingComposer,
          $$ResearchConsentsTableAnnotationComposer,
          $$ResearchConsentsTableCreateCompanionBuilder,
          $$ResearchConsentsTableUpdateCompanionBuilder,
          (ResearchConsent, $$ResearchConsentsTableReferences),
          ResearchConsent,
          PrefetchHooks Function({bool ownerId})
        > {
  $$ResearchConsentsTableTableManager(
    _$AppDatabase db,
    $ResearchConsentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ResearchConsentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ResearchConsentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ResearchConsentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<int> consentVersion = const Value.absent(),
                Value<String> consentState = const Value.absent(),
                Value<int> decidedAtUtcMs = const Value.absent(),
                Value<int?> withdrawnAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResearchConsentsCompanion(
                id: id,
                ownerId: ownerId,
                consentVersion: consentVersion,
                consentState: consentState,
                decidedAtUtcMs: decidedAtUtcMs,
                withdrawnAtUtcMs: withdrawnAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required int consentVersion,
                required String consentState,
                required int decidedAtUtcMs,
                Value<int?> withdrawnAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResearchConsentsCompanion.insert(
                id: id,
                ownerId: ownerId,
                consentVersion: consentVersion,
                consentState: consentState,
                decidedAtUtcMs: decidedAtUtcMs,
                withdrawnAtUtcMs: withdrawnAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ResearchConsentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({ownerId = false}) {
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
                    if (ownerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.ownerId,
                                referencedTable:
                                    $$ResearchConsentsTableReferences
                                        ._ownerIdTable(db),
                                referencedColumn:
                                    $$ResearchConsentsTableReferences
                                        ._ownerIdTable(db)
                                        .id,
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

typedef $$ResearchConsentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ResearchConsentsTable,
      ResearchConsent,
      $$ResearchConsentsTableFilterComposer,
      $$ResearchConsentsTableOrderingComposer,
      $$ResearchConsentsTableAnnotationComposer,
      $$ResearchConsentsTableCreateCompanionBuilder,
      $$ResearchConsentsTableUpdateCompanionBuilder,
      (ResearchConsent, $$ResearchConsentsTableReferences),
      ResearchConsent,
      PrefetchHooks Function({bool ownerId})
    >;
typedef $$VocabularyCategoriesTableCreateCompanionBuilder =
    VocabularyCategoriesCompanion Function({
      required String id,
      required String ownerId,
      required String name,
      required String normalizedName,
      Value<int> sortOrder,
      Value<int> localRevision,
      Value<int> cloudRevision,
      Value<int?> lastAcknowledgedAtUtcMs,
      Value<int?> serverUpdatedAtUtcMs,
      Value<bool> isDeleted,
      required int createdAtUtcMs,
      required int updatedAtUtcMs,
      Value<int> rowid,
    });
typedef $$VocabularyCategoriesTableUpdateCompanionBuilder =
    VocabularyCategoriesCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> name,
      Value<String> normalizedName,
      Value<int> sortOrder,
      Value<int> localRevision,
      Value<int> cloudRevision,
      Value<int?> lastAcknowledgedAtUtcMs,
      Value<int?> serverUpdatedAtUtcMs,
      Value<bool> isDeleted,
      Value<int> createdAtUtcMs,
      Value<int> updatedAtUtcMs,
      Value<int> rowid,
    });

final class $$VocabularyCategoriesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $VocabularyCategoriesTable,
          VocabularyCategory
        > {
  $$VocabularyCategoriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('vocabulary_categories__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$VocabularyWordsTable, List<VocabularyWord>>
  _vocabularyWordsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.vocabularyWords,
    aliasName: 'vocabulary_categories__id__vocabulary_words__category_id',
  );

  $$VocabularyWordsTableProcessedTableManager get vocabularyWordsRefs {
    final manager = $$VocabularyWordsTableTableManager(
      $_db,
      $_db.vocabularyWords,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _vocabularyWordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$VocabularyImportsTable, List<VocabularyImport>>
  _vocabularyImportsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.vocabularyImports,
        aliasName: 'vocabulary_categories__id__vocabulary_imports__category_id',
      );

  $$VocabularyImportsTableProcessedTableManager get vocabularyImportsRefs {
    final manager = $$VocabularyImportsTableTableManager(
      $_db,
      $_db.vocabularyImports,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _vocabularyImportsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$VocabularyCategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $VocabularyCategoriesTable> {
  $$VocabularyCategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cloudRevision => $composableBuilder(
    column: $table.cloudRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAcknowledgedAtUtcMs => $composableBuilder(
    column: $table.lastAcknowledgedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverUpdatedAtUtcMs => $composableBuilder(
    column: $table.serverUpdatedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> vocabularyWordsRefs(
    Expression<bool> Function($$VocabularyWordsTableFilterComposer f) f,
  ) {
    final $$VocabularyWordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.vocabularyWords,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyWordsTableFilterComposer(
            $db: $db,
            $table: $db.vocabularyWords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> vocabularyImportsRefs(
    Expression<bool> Function($$VocabularyImportsTableFilterComposer f) f,
  ) {
    final $$VocabularyImportsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.vocabularyImports,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyImportsTableFilterComposer(
            $db: $db,
            $table: $db.vocabularyImports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$VocabularyCategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $VocabularyCategoriesTable> {
  $$VocabularyCategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cloudRevision => $composableBuilder(
    column: $table.cloudRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAcknowledgedAtUtcMs => $composableBuilder(
    column: $table.lastAcknowledgedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverUpdatedAtUtcMs => $composableBuilder(
    column: $table.serverUpdatedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VocabularyCategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $VocabularyCategoriesTable> {
  $$VocabularyCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cloudRevision => $composableBuilder(
    column: $table.cloudRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastAcknowledgedAtUtcMs => $composableBuilder(
    column: $table.lastAcknowledgedAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverUpdatedAtUtcMs => $composableBuilder(
    column: $table.serverUpdatedAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> vocabularyWordsRefs<T extends Object>(
    Expression<T> Function($$VocabularyWordsTableAnnotationComposer a) f,
  ) {
    final $$VocabularyWordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.vocabularyWords,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyWordsTableAnnotationComposer(
            $db: $db,
            $table: $db.vocabularyWords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> vocabularyImportsRefs<T extends Object>(
    Expression<T> Function($$VocabularyImportsTableAnnotationComposer a) f,
  ) {
    final $$VocabularyImportsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.vocabularyImports,
          getReferencedColumn: (t) => t.categoryId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$VocabularyImportsTableAnnotationComposer(
                $db: $db,
                $table: $db.vocabularyImports,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$VocabularyCategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VocabularyCategoriesTable,
          VocabularyCategory,
          $$VocabularyCategoriesTableFilterComposer,
          $$VocabularyCategoriesTableOrderingComposer,
          $$VocabularyCategoriesTableAnnotationComposer,
          $$VocabularyCategoriesTableCreateCompanionBuilder,
          $$VocabularyCategoriesTableUpdateCompanionBuilder,
          (VocabularyCategory, $$VocabularyCategoriesTableReferences),
          VocabularyCategory,
          PrefetchHooks Function({
            bool ownerId,
            bool vocabularyWordsRefs,
            bool vocabularyImportsRefs,
          })
        > {
  $$VocabularyCategoriesTableTableManager(
    _$AppDatabase db,
    $VocabularyCategoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VocabularyCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VocabularyCategoriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$VocabularyCategoriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> normalizedName = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<int> cloudRevision = const Value.absent(),
                Value<int?> lastAcknowledgedAtUtcMs = const Value.absent(),
                Value<int?> serverUpdatedAtUtcMs = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<int> createdAtUtcMs = const Value.absent(),
                Value<int> updatedAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VocabularyCategoriesCompanion(
                id: id,
                ownerId: ownerId,
                name: name,
                normalizedName: normalizedName,
                sortOrder: sortOrder,
                localRevision: localRevision,
                cloudRevision: cloudRevision,
                lastAcknowledgedAtUtcMs: lastAcknowledgedAtUtcMs,
                serverUpdatedAtUtcMs: serverUpdatedAtUtcMs,
                isDeleted: isDeleted,
                createdAtUtcMs: createdAtUtcMs,
                updatedAtUtcMs: updatedAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String name,
                required String normalizedName,
                Value<int> sortOrder = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<int> cloudRevision = const Value.absent(),
                Value<int?> lastAcknowledgedAtUtcMs = const Value.absent(),
                Value<int?> serverUpdatedAtUtcMs = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                required int createdAtUtcMs,
                required int updatedAtUtcMs,
                Value<int> rowid = const Value.absent(),
              }) => VocabularyCategoriesCompanion.insert(
                id: id,
                ownerId: ownerId,
                name: name,
                normalizedName: normalizedName,
                sortOrder: sortOrder,
                localRevision: localRevision,
                cloudRevision: cloudRevision,
                lastAcknowledgedAtUtcMs: lastAcknowledgedAtUtcMs,
                serverUpdatedAtUtcMs: serverUpdatedAtUtcMs,
                isDeleted: isDeleted,
                createdAtUtcMs: createdAtUtcMs,
                updatedAtUtcMs: updatedAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$VocabularyCategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                ownerId = false,
                vocabularyWordsRefs = false,
                vocabularyImportsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (vocabularyWordsRefs) db.vocabularyWords,
                    if (vocabularyImportsRefs) db.vocabularyImports,
                  ],
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
                        if (ownerId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.ownerId,
                                    referencedTable:
                                        $$VocabularyCategoriesTableReferences
                                            ._ownerIdTable(db),
                                    referencedColumn:
                                        $$VocabularyCategoriesTableReferences
                                            ._ownerIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (vocabularyWordsRefs)
                        await $_getPrefetchedData<
                          VocabularyCategory,
                          $VocabularyCategoriesTable,
                          VocabularyWord
                        >(
                          currentTable: table,
                          referencedTable: $$VocabularyCategoriesTableReferences
                              ._vocabularyWordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VocabularyCategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).vocabularyWordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (vocabularyImportsRefs)
                        await $_getPrefetchedData<
                          VocabularyCategory,
                          $VocabularyCategoriesTable,
                          VocabularyImport
                        >(
                          currentTable: table,
                          referencedTable: $$VocabularyCategoriesTableReferences
                              ._vocabularyImportsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VocabularyCategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).vocabularyImportsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
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

typedef $$VocabularyCategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VocabularyCategoriesTable,
      VocabularyCategory,
      $$VocabularyCategoriesTableFilterComposer,
      $$VocabularyCategoriesTableOrderingComposer,
      $$VocabularyCategoriesTableAnnotationComposer,
      $$VocabularyCategoriesTableCreateCompanionBuilder,
      $$VocabularyCategoriesTableUpdateCompanionBuilder,
      (VocabularyCategory, $$VocabularyCategoriesTableReferences),
      VocabularyCategory,
      PrefetchHooks Function({
        bool ownerId,
        bool vocabularyWordsRefs,
        bool vocabularyImportsRefs,
      })
    >;
typedef $$VocabularyWordsTableCreateCompanionBuilder =
    VocabularyWordsCompanion Function({
      required String id,
      required String ownerId,
      required String categoryId,
      required String spelling,
      required String normalizedSpelling,
      required String meaning,
      required String normalizedMeaning,
      required String partOfSpeech,
      Value<String?> cefrLevel,
      Value<String> source,
      Value<bool> isGlobal,
      Value<int> localRevision,
      Value<int> cloudRevision,
      Value<int?> lastAcknowledgedAtUtcMs,
      Value<int?> serverUpdatedAtUtcMs,
      Value<bool> isDeleted,
      required int createdAtUtcMs,
      required int updatedAtUtcMs,
      Value<int> rowid,
    });
typedef $$VocabularyWordsTableUpdateCompanionBuilder =
    VocabularyWordsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> categoryId,
      Value<String> spelling,
      Value<String> normalizedSpelling,
      Value<String> meaning,
      Value<String> normalizedMeaning,
      Value<String> partOfSpeech,
      Value<String?> cefrLevel,
      Value<String> source,
      Value<bool> isGlobal,
      Value<int> localRevision,
      Value<int> cloudRevision,
      Value<int?> lastAcknowledgedAtUtcMs,
      Value<int?> serverUpdatedAtUtcMs,
      Value<bool> isDeleted,
      Value<int> createdAtUtcMs,
      Value<int> updatedAtUtcMs,
      Value<int> rowid,
    });

final class $$VocabularyWordsTableReferences
    extends
        BaseReferences<_$AppDatabase, $VocabularyWordsTable, VocabularyWord> {
  $$VocabularyWordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('vocabulary_words__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $VocabularyCategoriesTable _categoryIdTable(_$AppDatabase db) => db
      .vocabularyCategories
      .createAlias('vocabulary_words__category_id__vocabulary_categories__id');

  $$VocabularyCategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<String>('category_id')!;

    final manager = $$VocabularyCategoriesTableTableManager(
      $_db,
      $_db.vocabularyCategories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$AnswerAttemptsTable, List<AnswerAttempt>>
  _answerAttemptsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.answerAttempts,
    aliasName: 'vocabulary_words__id__answer_attempts__word_id',
  );

  $$AnswerAttemptsTableProcessedTableManager get answerAttemptsRefs {
    final manager = $$AnswerAttemptsTableTableManager(
      $_db,
      $_db.answerAttempts,
    ).filter((f) => f.wordId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_answerAttemptsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SrsStatesTable, List<SrsState>>
  _srsStatesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.srsStates,
    aliasName: 'vocabulary_words__id__srs_states__word_id',
  );

  $$SrsStatesTableProcessedTableManager get srsStatesRefs {
    final manager = $$SrsStatesTableTableManager(
      $_db,
      $_db.srsStates,
    ).filter((f) => f.wordId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_srsStatesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$VocabularyWordsTableFilterComposer
    extends Composer<_$AppDatabase, $VocabularyWordsTable> {
  $$VocabularyWordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get spelling => $composableBuilder(
    column: $table.spelling,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedSpelling => $composableBuilder(
    column: $table.normalizedSpelling,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meaning => $composableBuilder(
    column: $table.meaning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedMeaning => $composableBuilder(
    column: $table.normalizedMeaning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get partOfSpeech => $composableBuilder(
    column: $table.partOfSpeech,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cefrLevel => $composableBuilder(
    column: $table.cefrLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isGlobal => $composableBuilder(
    column: $table.isGlobal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cloudRevision => $composableBuilder(
    column: $table.cloudRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAcknowledgedAtUtcMs => $composableBuilder(
    column: $table.lastAcknowledgedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverUpdatedAtUtcMs => $composableBuilder(
    column: $table.serverUpdatedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VocabularyCategoriesTableFilterComposer get categoryId {
    final $$VocabularyCategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.vocabularyCategories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyCategoriesTableFilterComposer(
            $db: $db,
            $table: $db.vocabularyCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> answerAttemptsRefs(
    Expression<bool> Function($$AnswerAttemptsTableFilterComposer f) f,
  ) {
    final $$AnswerAttemptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.answerAttempts,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnswerAttemptsTableFilterComposer(
            $db: $db,
            $table: $db.answerAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> srsStatesRefs(
    Expression<bool> Function($$SrsStatesTableFilterComposer f) f,
  ) {
    final $$SrsStatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.srsStates,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SrsStatesTableFilterComposer(
            $db: $db,
            $table: $db.srsStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$VocabularyWordsTableOrderingComposer
    extends Composer<_$AppDatabase, $VocabularyWordsTable> {
  $$VocabularyWordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get spelling => $composableBuilder(
    column: $table.spelling,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedSpelling => $composableBuilder(
    column: $table.normalizedSpelling,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meaning => $composableBuilder(
    column: $table.meaning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedMeaning => $composableBuilder(
    column: $table.normalizedMeaning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get partOfSpeech => $composableBuilder(
    column: $table.partOfSpeech,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cefrLevel => $composableBuilder(
    column: $table.cefrLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isGlobal => $composableBuilder(
    column: $table.isGlobal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cloudRevision => $composableBuilder(
    column: $table.cloudRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAcknowledgedAtUtcMs => $composableBuilder(
    column: $table.lastAcknowledgedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverUpdatedAtUtcMs => $composableBuilder(
    column: $table.serverUpdatedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VocabularyCategoriesTableOrderingComposer get categoryId {
    final $$VocabularyCategoriesTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.categoryId,
          referencedTable: $db.vocabularyCategories,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$VocabularyCategoriesTableOrderingComposer(
                $db: $db,
                $table: $db.vocabularyCategories,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$VocabularyWordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VocabularyWordsTable> {
  $$VocabularyWordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get spelling =>
      $composableBuilder(column: $table.spelling, builder: (column) => column);

  GeneratedColumn<String> get normalizedSpelling => $composableBuilder(
    column: $table.normalizedSpelling,
    builder: (column) => column,
  );

  GeneratedColumn<String> get meaning =>
      $composableBuilder(column: $table.meaning, builder: (column) => column);

  GeneratedColumn<String> get normalizedMeaning => $composableBuilder(
    column: $table.normalizedMeaning,
    builder: (column) => column,
  );

  GeneratedColumn<String> get partOfSpeech => $composableBuilder(
    column: $table.partOfSpeech,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cefrLevel =>
      $composableBuilder(column: $table.cefrLevel, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get isGlobal =>
      $composableBuilder(column: $table.isGlobal, builder: (column) => column);

  GeneratedColumn<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cloudRevision => $composableBuilder(
    column: $table.cloudRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastAcknowledgedAtUtcMs => $composableBuilder(
    column: $table.lastAcknowledgedAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverUpdatedAtUtcMs => $composableBuilder(
    column: $table.serverUpdatedAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VocabularyCategoriesTableAnnotationComposer get categoryId {
    final $$VocabularyCategoriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.categoryId,
          referencedTable: $db.vocabularyCategories,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$VocabularyCategoriesTableAnnotationComposer(
                $db: $db,
                $table: $db.vocabularyCategories,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  Expression<T> answerAttemptsRefs<T extends Object>(
    Expression<T> Function($$AnswerAttemptsTableAnnotationComposer a) f,
  ) {
    final $$AnswerAttemptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.answerAttempts,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnswerAttemptsTableAnnotationComposer(
            $db: $db,
            $table: $db.answerAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> srsStatesRefs<T extends Object>(
    Expression<T> Function($$SrsStatesTableAnnotationComposer a) f,
  ) {
    final $$SrsStatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.srsStates,
      getReferencedColumn: (t) => t.wordId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SrsStatesTableAnnotationComposer(
            $db: $db,
            $table: $db.srsStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$VocabularyWordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VocabularyWordsTable,
          VocabularyWord,
          $$VocabularyWordsTableFilterComposer,
          $$VocabularyWordsTableOrderingComposer,
          $$VocabularyWordsTableAnnotationComposer,
          $$VocabularyWordsTableCreateCompanionBuilder,
          $$VocabularyWordsTableUpdateCompanionBuilder,
          (VocabularyWord, $$VocabularyWordsTableReferences),
          VocabularyWord,
          PrefetchHooks Function({
            bool ownerId,
            bool categoryId,
            bool answerAttemptsRefs,
            bool srsStatesRefs,
          })
        > {
  $$VocabularyWordsTableTableManager(
    _$AppDatabase db,
    $VocabularyWordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VocabularyWordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VocabularyWordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VocabularyWordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<String> spelling = const Value.absent(),
                Value<String> normalizedSpelling = const Value.absent(),
                Value<String> meaning = const Value.absent(),
                Value<String> normalizedMeaning = const Value.absent(),
                Value<String> partOfSpeech = const Value.absent(),
                Value<String?> cefrLevel = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> isGlobal = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<int> cloudRevision = const Value.absent(),
                Value<int?> lastAcknowledgedAtUtcMs = const Value.absent(),
                Value<int?> serverUpdatedAtUtcMs = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<int> createdAtUtcMs = const Value.absent(),
                Value<int> updatedAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VocabularyWordsCompanion(
                id: id,
                ownerId: ownerId,
                categoryId: categoryId,
                spelling: spelling,
                normalizedSpelling: normalizedSpelling,
                meaning: meaning,
                normalizedMeaning: normalizedMeaning,
                partOfSpeech: partOfSpeech,
                cefrLevel: cefrLevel,
                source: source,
                isGlobal: isGlobal,
                localRevision: localRevision,
                cloudRevision: cloudRevision,
                lastAcknowledgedAtUtcMs: lastAcknowledgedAtUtcMs,
                serverUpdatedAtUtcMs: serverUpdatedAtUtcMs,
                isDeleted: isDeleted,
                createdAtUtcMs: createdAtUtcMs,
                updatedAtUtcMs: updatedAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String categoryId,
                required String spelling,
                required String normalizedSpelling,
                required String meaning,
                required String normalizedMeaning,
                required String partOfSpeech,
                Value<String?> cefrLevel = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> isGlobal = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<int> cloudRevision = const Value.absent(),
                Value<int?> lastAcknowledgedAtUtcMs = const Value.absent(),
                Value<int?> serverUpdatedAtUtcMs = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                required int createdAtUtcMs,
                required int updatedAtUtcMs,
                Value<int> rowid = const Value.absent(),
              }) => VocabularyWordsCompanion.insert(
                id: id,
                ownerId: ownerId,
                categoryId: categoryId,
                spelling: spelling,
                normalizedSpelling: normalizedSpelling,
                meaning: meaning,
                normalizedMeaning: normalizedMeaning,
                partOfSpeech: partOfSpeech,
                cefrLevel: cefrLevel,
                source: source,
                isGlobal: isGlobal,
                localRevision: localRevision,
                cloudRevision: cloudRevision,
                lastAcknowledgedAtUtcMs: lastAcknowledgedAtUtcMs,
                serverUpdatedAtUtcMs: serverUpdatedAtUtcMs,
                isDeleted: isDeleted,
                createdAtUtcMs: createdAtUtcMs,
                updatedAtUtcMs: updatedAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$VocabularyWordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                ownerId = false,
                categoryId = false,
                answerAttemptsRefs = false,
                srsStatesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (answerAttemptsRefs) db.answerAttempts,
                    if (srsStatesRefs) db.srsStates,
                  ],
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
                        if (ownerId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.ownerId,
                                    referencedTable:
                                        $$VocabularyWordsTableReferences
                                            ._ownerIdTable(db),
                                    referencedColumn:
                                        $$VocabularyWordsTableReferences
                                            ._ownerIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (categoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.categoryId,
                                    referencedTable:
                                        $$VocabularyWordsTableReferences
                                            ._categoryIdTable(db),
                                    referencedColumn:
                                        $$VocabularyWordsTableReferences
                                            ._categoryIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (answerAttemptsRefs)
                        await $_getPrefetchedData<
                          VocabularyWord,
                          $VocabularyWordsTable,
                          AnswerAttempt
                        >(
                          currentTable: table,
                          referencedTable: $$VocabularyWordsTableReferences
                              ._answerAttemptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VocabularyWordsTableReferences(
                                db,
                                table,
                                p0,
                              ).answerAttemptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.wordId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (srsStatesRefs)
                        await $_getPrefetchedData<
                          VocabularyWord,
                          $VocabularyWordsTable,
                          SrsState
                        >(
                          currentTable: table,
                          referencedTable: $$VocabularyWordsTableReferences
                              ._srsStatesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VocabularyWordsTableReferences(
                                db,
                                table,
                                p0,
                              ).srsStatesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.wordId == item.id,
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

typedef $$VocabularyWordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VocabularyWordsTable,
      VocabularyWord,
      $$VocabularyWordsTableFilterComposer,
      $$VocabularyWordsTableOrderingComposer,
      $$VocabularyWordsTableAnnotationComposer,
      $$VocabularyWordsTableCreateCompanionBuilder,
      $$VocabularyWordsTableUpdateCompanionBuilder,
      (VocabularyWord, $$VocabularyWordsTableReferences),
      VocabularyWord,
      PrefetchHooks Function({
        bool ownerId,
        bool categoryId,
        bool answerAttemptsRefs,
        bool srsStatesRefs,
      })
    >;
typedef $$VocabularyImportsTableCreateCompanionBuilder =
    VocabularyImportsCompanion Function({
      required String id,
      required String ownerId,
      required String categoryId,
      required String sourceType,
      required String sourceName,
      required String sourceHash,
      required String status,
      Value<int> acceptedCount,
      Value<int> duplicateCount,
      Value<int> rejectedCount,
      required int createdAtUtcMs,
      Value<int?> completedAtUtcMs,
      Value<int> rowid,
    });
typedef $$VocabularyImportsTableUpdateCompanionBuilder =
    VocabularyImportsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> categoryId,
      Value<String> sourceType,
      Value<String> sourceName,
      Value<String> sourceHash,
      Value<String> status,
      Value<int> acceptedCount,
      Value<int> duplicateCount,
      Value<int> rejectedCount,
      Value<int> createdAtUtcMs,
      Value<int?> completedAtUtcMs,
      Value<int> rowid,
    });

final class $$VocabularyImportsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $VocabularyImportsTable,
          VocabularyImport
        > {
  $$VocabularyImportsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('vocabulary_imports__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $VocabularyCategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.vocabularyCategories.createAlias(
        'vocabulary_imports__category_id__vocabulary_categories__id',
      );

  $$VocabularyCategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<String>('category_id')!;

    final manager = $$VocabularyCategoriesTableTableManager(
      $_db,
      $_db.vocabularyCategories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $VocabularyImportRowsTable,
    List<VocabularyImportRow>
  >
  _vocabularyImportRowsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.vocabularyImportRows,
        aliasName: 'vocabulary_imports__id__vocabulary_import_rows__import_id',
      );

  $$VocabularyImportRowsTableProcessedTableManager
  get vocabularyImportRowsRefs {
    final manager = $$VocabularyImportRowsTableTableManager(
      $_db,
      $_db.vocabularyImportRows,
    ).filter((f) => f.importId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _vocabularyImportRowsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$VocabularyImportsTableFilterComposer
    extends Composer<_$AppDatabase, $VocabularyImportsTable> {
  $$VocabularyImportsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acceptedCount => $composableBuilder(
    column: $table.acceptedCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get duplicateCount => $composableBuilder(
    column: $table.duplicateCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rejectedCount => $composableBuilder(
    column: $table.rejectedCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAtUtcMs => $composableBuilder(
    column: $table.completedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VocabularyCategoriesTableFilterComposer get categoryId {
    final $$VocabularyCategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.vocabularyCategories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyCategoriesTableFilterComposer(
            $db: $db,
            $table: $db.vocabularyCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> vocabularyImportRowsRefs(
    Expression<bool> Function($$VocabularyImportRowsTableFilterComposer f) f,
  ) {
    final $$VocabularyImportRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.vocabularyImportRows,
      getReferencedColumn: (t) => t.importId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyImportRowsTableFilterComposer(
            $db: $db,
            $table: $db.vocabularyImportRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$VocabularyImportsTableOrderingComposer
    extends Composer<_$AppDatabase, $VocabularyImportsTable> {
  $$VocabularyImportsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acceptedCount => $composableBuilder(
    column: $table.acceptedCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get duplicateCount => $composableBuilder(
    column: $table.duplicateCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rejectedCount => $composableBuilder(
    column: $table.rejectedCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAtUtcMs => $composableBuilder(
    column: $table.completedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VocabularyCategoriesTableOrderingComposer get categoryId {
    final $$VocabularyCategoriesTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.categoryId,
          referencedTable: $db.vocabularyCategories,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$VocabularyCategoriesTableOrderingComposer(
                $db: $db,
                $table: $db.vocabularyCategories,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$VocabularyImportsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VocabularyImportsTable> {
  $$VocabularyImportsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get acceptedCount => $composableBuilder(
    column: $table.acceptedCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get duplicateCount => $composableBuilder(
    column: $table.duplicateCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rejectedCount => $composableBuilder(
    column: $table.rejectedCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedAtUtcMs => $composableBuilder(
    column: $table.completedAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VocabularyCategoriesTableAnnotationComposer get categoryId {
    final $$VocabularyCategoriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.categoryId,
          referencedTable: $db.vocabularyCategories,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$VocabularyCategoriesTableAnnotationComposer(
                $db: $db,
                $table: $db.vocabularyCategories,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  Expression<T> vocabularyImportRowsRefs<T extends Object>(
    Expression<T> Function($$VocabularyImportRowsTableAnnotationComposer a) f,
  ) {
    final $$VocabularyImportRowsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.vocabularyImportRows,
          getReferencedColumn: (t) => t.importId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$VocabularyImportRowsTableAnnotationComposer(
                $db: $db,
                $table: $db.vocabularyImportRows,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$VocabularyImportsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VocabularyImportsTable,
          VocabularyImport,
          $$VocabularyImportsTableFilterComposer,
          $$VocabularyImportsTableOrderingComposer,
          $$VocabularyImportsTableAnnotationComposer,
          $$VocabularyImportsTableCreateCompanionBuilder,
          $$VocabularyImportsTableUpdateCompanionBuilder,
          (VocabularyImport, $$VocabularyImportsTableReferences),
          VocabularyImport,
          PrefetchHooks Function({
            bool ownerId,
            bool categoryId,
            bool vocabularyImportRowsRefs,
          })
        > {
  $$VocabularyImportsTableTableManager(
    _$AppDatabase db,
    $VocabularyImportsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VocabularyImportsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VocabularyImportsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VocabularyImportsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<String> sourceType = const Value.absent(),
                Value<String> sourceName = const Value.absent(),
                Value<String> sourceHash = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> acceptedCount = const Value.absent(),
                Value<int> duplicateCount = const Value.absent(),
                Value<int> rejectedCount = const Value.absent(),
                Value<int> createdAtUtcMs = const Value.absent(),
                Value<int?> completedAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VocabularyImportsCompanion(
                id: id,
                ownerId: ownerId,
                categoryId: categoryId,
                sourceType: sourceType,
                sourceName: sourceName,
                sourceHash: sourceHash,
                status: status,
                acceptedCount: acceptedCount,
                duplicateCount: duplicateCount,
                rejectedCount: rejectedCount,
                createdAtUtcMs: createdAtUtcMs,
                completedAtUtcMs: completedAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String categoryId,
                required String sourceType,
                required String sourceName,
                required String sourceHash,
                required String status,
                Value<int> acceptedCount = const Value.absent(),
                Value<int> duplicateCount = const Value.absent(),
                Value<int> rejectedCount = const Value.absent(),
                required int createdAtUtcMs,
                Value<int?> completedAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VocabularyImportsCompanion.insert(
                id: id,
                ownerId: ownerId,
                categoryId: categoryId,
                sourceType: sourceType,
                sourceName: sourceName,
                sourceHash: sourceHash,
                status: status,
                acceptedCount: acceptedCount,
                duplicateCount: duplicateCount,
                rejectedCount: rejectedCount,
                createdAtUtcMs: createdAtUtcMs,
                completedAtUtcMs: completedAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$VocabularyImportsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                ownerId = false,
                categoryId = false,
                vocabularyImportRowsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (vocabularyImportRowsRefs) db.vocabularyImportRows,
                  ],
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
                        if (ownerId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.ownerId,
                                    referencedTable:
                                        $$VocabularyImportsTableReferences
                                            ._ownerIdTable(db),
                                    referencedColumn:
                                        $$VocabularyImportsTableReferences
                                            ._ownerIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (categoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.categoryId,
                                    referencedTable:
                                        $$VocabularyImportsTableReferences
                                            ._categoryIdTable(db),
                                    referencedColumn:
                                        $$VocabularyImportsTableReferences
                                            ._categoryIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (vocabularyImportRowsRefs)
                        await $_getPrefetchedData<
                          VocabularyImport,
                          $VocabularyImportsTable,
                          VocabularyImportRow
                        >(
                          currentTable: table,
                          referencedTable: $$VocabularyImportsTableReferences
                              ._vocabularyImportRowsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$VocabularyImportsTableReferences(
                                db,
                                table,
                                p0,
                              ).vocabularyImportRowsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.importId == item.id,
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

typedef $$VocabularyImportsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VocabularyImportsTable,
      VocabularyImport,
      $$VocabularyImportsTableFilterComposer,
      $$VocabularyImportsTableOrderingComposer,
      $$VocabularyImportsTableAnnotationComposer,
      $$VocabularyImportsTableCreateCompanionBuilder,
      $$VocabularyImportsTableUpdateCompanionBuilder,
      (VocabularyImport, $$VocabularyImportsTableReferences),
      VocabularyImport,
      PrefetchHooks Function({
        bool ownerId,
        bool categoryId,
        bool vocabularyImportRowsRefs,
      })
    >;
typedef $$VocabularyImportRowsTableCreateCompanionBuilder =
    VocabularyImportRowsCompanion Function({
      required String id,
      required String importId,
      required int rowNumber,
      required String payloadHash,
      required String status,
      Value<String?> failureCode,
      Value<String?> wordId,
      Value<int> rowid,
    });
typedef $$VocabularyImportRowsTableUpdateCompanionBuilder =
    VocabularyImportRowsCompanion Function({
      Value<String> id,
      Value<String> importId,
      Value<int> rowNumber,
      Value<String> payloadHash,
      Value<String> status,
      Value<String?> failureCode,
      Value<String?> wordId,
      Value<int> rowid,
    });

final class $$VocabularyImportRowsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $VocabularyImportRowsTable,
          VocabularyImportRow
        > {
  $$VocabularyImportRowsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $VocabularyImportsTable _importIdTable(_$AppDatabase db) => db
      .vocabularyImports
      .createAlias('vocabulary_import_rows__import_id__vocabulary_imports__id');

  $$VocabularyImportsTableProcessedTableManager get importId {
    final $_column = $_itemColumn<String>('import_id')!;

    final manager = $$VocabularyImportsTableTableManager(
      $_db,
      $_db.vocabularyImports,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_importIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$VocabularyImportRowsTableFilterComposer
    extends Composer<_$AppDatabase, $VocabularyImportRowsTable> {
  $$VocabularyImportRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowNumber => $composableBuilder(
    column: $table.rowNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadHash => $composableBuilder(
    column: $table.payloadHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wordId => $composableBuilder(
    column: $table.wordId,
    builder: (column) => ColumnFilters(column),
  );

  $$VocabularyImportsTableFilterComposer get importId {
    final $$VocabularyImportsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importId,
      referencedTable: $db.vocabularyImports,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyImportsTableFilterComposer(
            $db: $db,
            $table: $db.vocabularyImports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VocabularyImportRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $VocabularyImportRowsTable> {
  $$VocabularyImportRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowNumber => $composableBuilder(
    column: $table.rowNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadHash => $composableBuilder(
    column: $table.payloadHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wordId => $composableBuilder(
    column: $table.wordId,
    builder: (column) => ColumnOrderings(column),
  );

  $$VocabularyImportsTableOrderingComposer get importId {
    final $$VocabularyImportsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.importId,
      referencedTable: $db.vocabularyImports,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyImportsTableOrderingComposer(
            $db: $db,
            $table: $db.vocabularyImports,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VocabularyImportRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VocabularyImportRowsTable> {
  $$VocabularyImportRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get rowNumber =>
      $composableBuilder(column: $table.rowNumber, builder: (column) => column);

  GeneratedColumn<String> get payloadHash => $composableBuilder(
    column: $table.payloadHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get wordId =>
      $composableBuilder(column: $table.wordId, builder: (column) => column);

  $$VocabularyImportsTableAnnotationComposer get importId {
    final $$VocabularyImportsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.importId,
          referencedTable: $db.vocabularyImports,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$VocabularyImportsTableAnnotationComposer(
                $db: $db,
                $table: $db.vocabularyImports,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$VocabularyImportRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VocabularyImportRowsTable,
          VocabularyImportRow,
          $$VocabularyImportRowsTableFilterComposer,
          $$VocabularyImportRowsTableOrderingComposer,
          $$VocabularyImportRowsTableAnnotationComposer,
          $$VocabularyImportRowsTableCreateCompanionBuilder,
          $$VocabularyImportRowsTableUpdateCompanionBuilder,
          (VocabularyImportRow, $$VocabularyImportRowsTableReferences),
          VocabularyImportRow,
          PrefetchHooks Function({bool importId})
        > {
  $$VocabularyImportRowsTableTableManager(
    _$AppDatabase db,
    $VocabularyImportRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VocabularyImportRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VocabularyImportRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$VocabularyImportRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> importId = const Value.absent(),
                Value<int> rowNumber = const Value.absent(),
                Value<String> payloadHash = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<String?> wordId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VocabularyImportRowsCompanion(
                id: id,
                importId: importId,
                rowNumber: rowNumber,
                payloadHash: payloadHash,
                status: status,
                failureCode: failureCode,
                wordId: wordId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String importId,
                required int rowNumber,
                required String payloadHash,
                required String status,
                Value<String?> failureCode = const Value.absent(),
                Value<String?> wordId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VocabularyImportRowsCompanion.insert(
                id: id,
                importId: importId,
                rowNumber: rowNumber,
                payloadHash: payloadHash,
                status: status,
                failureCode: failureCode,
                wordId: wordId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$VocabularyImportRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({importId = false}) {
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
                    if (importId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.importId,
                                referencedTable:
                                    $$VocabularyImportRowsTableReferences
                                        ._importIdTable(db),
                                referencedColumn:
                                    $$VocabularyImportRowsTableReferences
                                        ._importIdTable(db)
                                        .id,
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

typedef $$VocabularyImportRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VocabularyImportRowsTable,
      VocabularyImportRow,
      $$VocabularyImportRowsTableFilterComposer,
      $$VocabularyImportRowsTableOrderingComposer,
      $$VocabularyImportRowsTableAnnotationComposer,
      $$VocabularyImportRowsTableCreateCompanionBuilder,
      $$VocabularyImportRowsTableUpdateCompanionBuilder,
      (VocabularyImportRow, $$VocabularyImportRowsTableReferences),
      VocabularyImportRow,
      PrefetchHooks Function({bool importId})
    >;
typedef $$LearningSessionsTableCreateCompanionBuilder =
    LearningSessionsCompanion Function({
      required String id,
      required String ownerId,
      required String activityType,
      required String state,
      required int startedAtUtcMs,
      Value<int?> endedAtUtcMs,
      Value<int> correctCount,
      Value<int> wrongCount,
      Value<int?> score,
      required String appVersion,
      required String buildId,
      Value<int> rowid,
    });
typedef $$LearningSessionsTableUpdateCompanionBuilder =
    LearningSessionsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> activityType,
      Value<String> state,
      Value<int> startedAtUtcMs,
      Value<int?> endedAtUtcMs,
      Value<int> correctCount,
      Value<int> wrongCount,
      Value<int?> score,
      Value<String> appVersion,
      Value<String> buildId,
      Value<int> rowid,
    });

final class $$LearningSessionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $LearningSessionsTable, LearningSession> {
  $$LearningSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('learning_sessions__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$AnswerAttemptsTable, List<AnswerAttempt>>
  _answerAttemptsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.answerAttempts,
    aliasName: 'learning_sessions__id__answer_attempts__session_id',
  );

  $$AnswerAttemptsTableProcessedTableManager get answerAttemptsRefs {
    final manager = $$AnswerAttemptsTableTableManager(
      $_db,
      $_db.answerAttempts,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_answerAttemptsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LearningSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $LearningSessionsTable> {
  $$LearningSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activityType => $composableBuilder(
    column: $table.activityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAtUtcMs => $composableBuilder(
    column: $table.startedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAtUtcMs => $composableBuilder(
    column: $table.endedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get correctCount => $composableBuilder(
    column: $table.correctCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wrongCount => $composableBuilder(
    column: $table.wrongCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get buildId => $composableBuilder(
    column: $table.buildId,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> answerAttemptsRefs(
    Expression<bool> Function($$AnswerAttemptsTableFilterComposer f) f,
  ) {
    final $$AnswerAttemptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.answerAttempts,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnswerAttemptsTableFilterComposer(
            $db: $db,
            $table: $db.answerAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LearningSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $LearningSessionsTable> {
  $$LearningSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activityType => $composableBuilder(
    column: $table.activityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAtUtcMs => $composableBuilder(
    column: $table.startedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAtUtcMs => $composableBuilder(
    column: $table.endedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get correctCount => $composableBuilder(
    column: $table.correctCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wrongCount => $composableBuilder(
    column: $table.wrongCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get buildId => $composableBuilder(
    column: $table.buildId,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LearningSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LearningSessionsTable> {
  $$LearningSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get activityType => $composableBuilder(
    column: $table.activityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get startedAtUtcMs => $composableBuilder(
    column: $table.startedAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endedAtUtcMs => $composableBuilder(
    column: $table.endedAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get correctCount => $composableBuilder(
    column: $table.correctCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wrongCount => $composableBuilder(
    column: $table.wrongCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get buildId =>
      $composableBuilder(column: $table.buildId, builder: (column) => column);

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> answerAttemptsRefs<T extends Object>(
    Expression<T> Function($$AnswerAttemptsTableAnnotationComposer a) f,
  ) {
    final $$AnswerAttemptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.answerAttempts,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnswerAttemptsTableAnnotationComposer(
            $db: $db,
            $table: $db.answerAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LearningSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LearningSessionsTable,
          LearningSession,
          $$LearningSessionsTableFilterComposer,
          $$LearningSessionsTableOrderingComposer,
          $$LearningSessionsTableAnnotationComposer,
          $$LearningSessionsTableCreateCompanionBuilder,
          $$LearningSessionsTableUpdateCompanionBuilder,
          (LearningSession, $$LearningSessionsTableReferences),
          LearningSession,
          PrefetchHooks Function({bool ownerId, bool answerAttemptsRefs})
        > {
  $$LearningSessionsTableTableManager(
    _$AppDatabase db,
    $LearningSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LearningSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LearningSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LearningSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> activityType = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> startedAtUtcMs = const Value.absent(),
                Value<int?> endedAtUtcMs = const Value.absent(),
                Value<int> correctCount = const Value.absent(),
                Value<int> wrongCount = const Value.absent(),
                Value<int?> score = const Value.absent(),
                Value<String> appVersion = const Value.absent(),
                Value<String> buildId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearningSessionsCompanion(
                id: id,
                ownerId: ownerId,
                activityType: activityType,
                state: state,
                startedAtUtcMs: startedAtUtcMs,
                endedAtUtcMs: endedAtUtcMs,
                correctCount: correctCount,
                wrongCount: wrongCount,
                score: score,
                appVersion: appVersion,
                buildId: buildId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String activityType,
                required String state,
                required int startedAtUtcMs,
                Value<int?> endedAtUtcMs = const Value.absent(),
                Value<int> correctCount = const Value.absent(),
                Value<int> wrongCount = const Value.absent(),
                Value<int?> score = const Value.absent(),
                required String appVersion,
                required String buildId,
                Value<int> rowid = const Value.absent(),
              }) => LearningSessionsCompanion.insert(
                id: id,
                ownerId: ownerId,
                activityType: activityType,
                state: state,
                startedAtUtcMs: startedAtUtcMs,
                endedAtUtcMs: endedAtUtcMs,
                correctCount: correctCount,
                wrongCount: wrongCount,
                score: score,
                appVersion: appVersion,
                buildId: buildId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LearningSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({ownerId = false, answerAttemptsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (answerAttemptsRefs) db.answerAttempts,
                  ],
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
                        if (ownerId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.ownerId,
                                    referencedTable:
                                        $$LearningSessionsTableReferences
                                            ._ownerIdTable(db),
                                    referencedColumn:
                                        $$LearningSessionsTableReferences
                                            ._ownerIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (answerAttemptsRefs)
                        await $_getPrefetchedData<
                          LearningSession,
                          $LearningSessionsTable,
                          AnswerAttempt
                        >(
                          currentTable: table,
                          referencedTable: $$LearningSessionsTableReferences
                              ._answerAttemptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$LearningSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).answerAttemptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
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

typedef $$LearningSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LearningSessionsTable,
      LearningSession,
      $$LearningSessionsTableFilterComposer,
      $$LearningSessionsTableOrderingComposer,
      $$LearningSessionsTableAnnotationComposer,
      $$LearningSessionsTableCreateCompanionBuilder,
      $$LearningSessionsTableUpdateCompanionBuilder,
      (LearningSession, $$LearningSessionsTableReferences),
      LearningSession,
      PrefetchHooks Function({bool ownerId, bool answerAttemptsRefs})
    >;
typedef $$AnswerAttemptsTableCreateCompanionBuilder =
    AnswerAttemptsCompanion Function({
      required String id,
      required String ownerId,
      required String sessionId,
      required String wordId,
      required String promptMode,
      required bool isCorrect,
      Value<int?> responseTimeMs,
      required int attemptNumber,
      required int occurredAtUtcMs,
      Value<String?> providerProvenance,
      Value<int> rowid,
    });
typedef $$AnswerAttemptsTableUpdateCompanionBuilder =
    AnswerAttemptsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> sessionId,
      Value<String> wordId,
      Value<String> promptMode,
      Value<bool> isCorrect,
      Value<int?> responseTimeMs,
      Value<int> attemptNumber,
      Value<int> occurredAtUtcMs,
      Value<String?> providerProvenance,
      Value<int> rowid,
    });

final class $$AnswerAttemptsTableReferences
    extends BaseReferences<_$AppDatabase, $AnswerAttemptsTable, AnswerAttempt> {
  $$AnswerAttemptsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) =>
      db.localOwners.createAlias('answer_attempts__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $LearningSessionsTable _sessionIdTable(_$AppDatabase db) => db
      .learningSessions
      .createAlias('answer_attempts__session_id__learning_sessions__id');

  $$LearningSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$LearningSessionsTableTableManager(
      $_db,
      $_db.learningSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $VocabularyWordsTable _wordIdTable(_$AppDatabase db) => db
      .vocabularyWords
      .createAlias('answer_attempts__word_id__vocabulary_words__id');

  $$VocabularyWordsTableProcessedTableManager get wordId {
    final $_column = $_itemColumn<String>('word_id')!;

    final manager = $$VocabularyWordsTableTableManager(
      $_db,
      $_db.vocabularyWords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AnswerAttemptsTableFilterComposer
    extends Composer<_$AppDatabase, $AnswerAttemptsTable> {
  $$AnswerAttemptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get promptMode => $composableBuilder(
    column: $table.promptMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCorrect => $composableBuilder(
    column: $table.isCorrect,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get responseTimeMs => $composableBuilder(
    column: $table.responseTimeMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptNumber => $composableBuilder(
    column: $table.attemptNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurredAtUtcMs => $composableBuilder(
    column: $table.occurredAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerProvenance => $composableBuilder(
    column: $table.providerProvenance,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LearningSessionsTableFilterComposer get sessionId {
    final $$LearningSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableFilterComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VocabularyWordsTableFilterComposer get wordId {
    final $$VocabularyWordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.vocabularyWords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyWordsTableFilterComposer(
            $db: $db,
            $table: $db.vocabularyWords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnswerAttemptsTableOrderingComposer
    extends Composer<_$AppDatabase, $AnswerAttemptsTable> {
  $$AnswerAttemptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get promptMode => $composableBuilder(
    column: $table.promptMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCorrect => $composableBuilder(
    column: $table.isCorrect,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get responseTimeMs => $composableBuilder(
    column: $table.responseTimeMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptNumber => $composableBuilder(
    column: $table.attemptNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurredAtUtcMs => $composableBuilder(
    column: $table.occurredAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerProvenance => $composableBuilder(
    column: $table.providerProvenance,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LearningSessionsTableOrderingComposer get sessionId {
    final $$LearningSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VocabularyWordsTableOrderingComposer get wordId {
    final $$VocabularyWordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.vocabularyWords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyWordsTableOrderingComposer(
            $db: $db,
            $table: $db.vocabularyWords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnswerAttemptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AnswerAttemptsTable> {
  $$AnswerAttemptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get promptMode => $composableBuilder(
    column: $table.promptMode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCorrect =>
      $composableBuilder(column: $table.isCorrect, builder: (column) => column);

  GeneratedColumn<int> get responseTimeMs => $composableBuilder(
    column: $table.responseTimeMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptNumber => $composableBuilder(
    column: $table.attemptNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get occurredAtUtcMs => $composableBuilder(
    column: $table.occurredAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get providerProvenance => $composableBuilder(
    column: $table.providerProvenance,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$LearningSessionsTableAnnotationComposer get sessionId {
    final $$LearningSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.learningSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LearningSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.learningSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VocabularyWordsTableAnnotationComposer get wordId {
    final $$VocabularyWordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.vocabularyWords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyWordsTableAnnotationComposer(
            $db: $db,
            $table: $db.vocabularyWords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnswerAttemptsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AnswerAttemptsTable,
          AnswerAttempt,
          $$AnswerAttemptsTableFilterComposer,
          $$AnswerAttemptsTableOrderingComposer,
          $$AnswerAttemptsTableAnnotationComposer,
          $$AnswerAttemptsTableCreateCompanionBuilder,
          $$AnswerAttemptsTableUpdateCompanionBuilder,
          (AnswerAttempt, $$AnswerAttemptsTableReferences),
          AnswerAttempt,
          PrefetchHooks Function({bool ownerId, bool sessionId, bool wordId})
        > {
  $$AnswerAttemptsTableTableManager(
    _$AppDatabase db,
    $AnswerAttemptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnswerAttemptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnswerAttemptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnswerAttemptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> wordId = const Value.absent(),
                Value<String> promptMode = const Value.absent(),
                Value<bool> isCorrect = const Value.absent(),
                Value<int?> responseTimeMs = const Value.absent(),
                Value<int> attemptNumber = const Value.absent(),
                Value<int> occurredAtUtcMs = const Value.absent(),
                Value<String?> providerProvenance = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnswerAttemptsCompanion(
                id: id,
                ownerId: ownerId,
                sessionId: sessionId,
                wordId: wordId,
                promptMode: promptMode,
                isCorrect: isCorrect,
                responseTimeMs: responseTimeMs,
                attemptNumber: attemptNumber,
                occurredAtUtcMs: occurredAtUtcMs,
                providerProvenance: providerProvenance,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String sessionId,
                required String wordId,
                required String promptMode,
                required bool isCorrect,
                Value<int?> responseTimeMs = const Value.absent(),
                required int attemptNumber,
                required int occurredAtUtcMs,
                Value<String?> providerProvenance = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnswerAttemptsCompanion.insert(
                id: id,
                ownerId: ownerId,
                sessionId: sessionId,
                wordId: wordId,
                promptMode: promptMode,
                isCorrect: isCorrect,
                responseTimeMs: responseTimeMs,
                attemptNumber: attemptNumber,
                occurredAtUtcMs: occurredAtUtcMs,
                providerProvenance: providerProvenance,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AnswerAttemptsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({ownerId = false, sessionId = false, wordId = false}) {
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
                        if (ownerId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.ownerId,
                                    referencedTable:
                                        $$AnswerAttemptsTableReferences
                                            ._ownerIdTable(db),
                                    referencedColumn:
                                        $$AnswerAttemptsTableReferences
                                            ._ownerIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (sessionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.sessionId,
                                    referencedTable:
                                        $$AnswerAttemptsTableReferences
                                            ._sessionIdTable(db),
                                    referencedColumn:
                                        $$AnswerAttemptsTableReferences
                                            ._sessionIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (wordId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.wordId,
                                    referencedTable:
                                        $$AnswerAttemptsTableReferences
                                            ._wordIdTable(db),
                                    referencedColumn:
                                        $$AnswerAttemptsTableReferences
                                            ._wordIdTable(db)
                                            .id,
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

typedef $$AnswerAttemptsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AnswerAttemptsTable,
      AnswerAttempt,
      $$AnswerAttemptsTableFilterComposer,
      $$AnswerAttemptsTableOrderingComposer,
      $$AnswerAttemptsTableAnnotationComposer,
      $$AnswerAttemptsTableCreateCompanionBuilder,
      $$AnswerAttemptsTableUpdateCompanionBuilder,
      (AnswerAttempt, $$AnswerAttemptsTableReferences),
      AnswerAttempt,
      PrefetchHooks Function({bool ownerId, bool sessionId, bool wordId})
    >;
typedef $$SrsStatesTableCreateCompanionBuilder =
    SrsStatesCompanion Function({
      required String id,
      required String ownerId,
      required String wordId,
      Value<double> stability,
      Value<double> difficulty,
      Value<int> intervalDays,
      Value<int> repetitions,
      Value<int> lapses,
      Value<int?> lastReviewAtUtcMs,
      required int dueAtUtcMs,
      required int algorithmVersion,
      Value<int> rowid,
    });
typedef $$SrsStatesTableUpdateCompanionBuilder =
    SrsStatesCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> wordId,
      Value<double> stability,
      Value<double> difficulty,
      Value<int> intervalDays,
      Value<int> repetitions,
      Value<int> lapses,
      Value<int?> lastReviewAtUtcMs,
      Value<int> dueAtUtcMs,
      Value<int> algorithmVersion,
      Value<int> rowid,
    });

final class $$SrsStatesTableReferences
    extends BaseReferences<_$AppDatabase, $SrsStatesTable, SrsState> {
  $$SrsStatesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) =>
      db.localOwners.createAlias('srs_states__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $VocabularyWordsTable _wordIdTable(_$AppDatabase db) => db
      .vocabularyWords
      .createAlias('srs_states__word_id__vocabulary_words__id');

  $$VocabularyWordsTableProcessedTableManager get wordId {
    final $_column = $_itemColumn<String>('word_id')!;

    final manager = $$VocabularyWordsTableTableManager(
      $_db,
      $_db.vocabularyWords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wordIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SrsStatesTableFilterComposer
    extends Composer<_$AppDatabase, $SrsStatesTable> {
  $$SrsStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get stability => $composableBuilder(
    column: $table.stability,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intervalDays => $composableBuilder(
    column: $table.intervalDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get repetitions => $composableBuilder(
    column: $table.repetitions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lapses => $composableBuilder(
    column: $table.lapses,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReviewAtUtcMs => $composableBuilder(
    column: $table.lastReviewAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dueAtUtcMs => $composableBuilder(
    column: $table.dueAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VocabularyWordsTableFilterComposer get wordId {
    final $$VocabularyWordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.vocabularyWords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyWordsTableFilterComposer(
            $db: $db,
            $table: $db.vocabularyWords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SrsStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $SrsStatesTable> {
  $$SrsStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get stability => $composableBuilder(
    column: $table.stability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intervalDays => $composableBuilder(
    column: $table.intervalDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repetitions => $composableBuilder(
    column: $table.repetitions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lapses => $composableBuilder(
    column: $table.lapses,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReviewAtUtcMs => $composableBuilder(
    column: $table.lastReviewAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dueAtUtcMs => $composableBuilder(
    column: $table.dueAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VocabularyWordsTableOrderingComposer get wordId {
    final $$VocabularyWordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.vocabularyWords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyWordsTableOrderingComposer(
            $db: $db,
            $table: $db.vocabularyWords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SrsStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SrsStatesTable> {
  $$SrsStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get stability =>
      $composableBuilder(column: $table.stability, builder: (column) => column);

  GeneratedColumn<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => column,
  );

  GeneratedColumn<int> get intervalDays => $composableBuilder(
    column: $table.intervalDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get repetitions => $composableBuilder(
    column: $table.repetitions,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lapses =>
      $composableBuilder(column: $table.lapses, builder: (column) => column);

  GeneratedColumn<int> get lastReviewAtUtcMs => $composableBuilder(
    column: $table.lastReviewAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dueAtUtcMs => $composableBuilder(
    column: $table.dueAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$VocabularyWordsTableAnnotationComposer get wordId {
    final $$VocabularyWordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wordId,
      referencedTable: $db.vocabularyWords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VocabularyWordsTableAnnotationComposer(
            $db: $db,
            $table: $db.vocabularyWords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SrsStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SrsStatesTable,
          SrsState,
          $$SrsStatesTableFilterComposer,
          $$SrsStatesTableOrderingComposer,
          $$SrsStatesTableAnnotationComposer,
          $$SrsStatesTableCreateCompanionBuilder,
          $$SrsStatesTableUpdateCompanionBuilder,
          (SrsState, $$SrsStatesTableReferences),
          SrsState,
          PrefetchHooks Function({bool ownerId, bool wordId})
        > {
  $$SrsStatesTableTableManager(_$AppDatabase db, $SrsStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SrsStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SrsStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SrsStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> wordId = const Value.absent(),
                Value<double> stability = const Value.absent(),
                Value<double> difficulty = const Value.absent(),
                Value<int> intervalDays = const Value.absent(),
                Value<int> repetitions = const Value.absent(),
                Value<int> lapses = const Value.absent(),
                Value<int?> lastReviewAtUtcMs = const Value.absent(),
                Value<int> dueAtUtcMs = const Value.absent(),
                Value<int> algorithmVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SrsStatesCompanion(
                id: id,
                ownerId: ownerId,
                wordId: wordId,
                stability: stability,
                difficulty: difficulty,
                intervalDays: intervalDays,
                repetitions: repetitions,
                lapses: lapses,
                lastReviewAtUtcMs: lastReviewAtUtcMs,
                dueAtUtcMs: dueAtUtcMs,
                algorithmVersion: algorithmVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String wordId,
                Value<double> stability = const Value.absent(),
                Value<double> difficulty = const Value.absent(),
                Value<int> intervalDays = const Value.absent(),
                Value<int> repetitions = const Value.absent(),
                Value<int> lapses = const Value.absent(),
                Value<int?> lastReviewAtUtcMs = const Value.absent(),
                required int dueAtUtcMs,
                required int algorithmVersion,
                Value<int> rowid = const Value.absent(),
              }) => SrsStatesCompanion.insert(
                id: id,
                ownerId: ownerId,
                wordId: wordId,
                stability: stability,
                difficulty: difficulty,
                intervalDays: intervalDays,
                repetitions: repetitions,
                lapses: lapses,
                lastReviewAtUtcMs: lastReviewAtUtcMs,
                dueAtUtcMs: dueAtUtcMs,
                algorithmVersion: algorithmVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SrsStatesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({ownerId = false, wordId = false}) {
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
                    if (ownerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.ownerId,
                                referencedTable: $$SrsStatesTableReferences
                                    ._ownerIdTable(db),
                                referencedColumn: $$SrsStatesTableReferences
                                    ._ownerIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (wordId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.wordId,
                                referencedTable: $$SrsStatesTableReferences
                                    ._wordIdTable(db),
                                referencedColumn: $$SrsStatesTableReferences
                                    ._wordIdTable(db)
                                    .id,
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

typedef $$SrsStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SrsStatesTable,
      SrsState,
      $$SrsStatesTableFilterComposer,
      $$SrsStatesTableOrderingComposer,
      $$SrsStatesTableAnnotationComposer,
      $$SrsStatesTableCreateCompanionBuilder,
      $$SrsStatesTableUpdateCompanionBuilder,
      (SrsState, $$SrsStatesTableReferences),
      SrsState,
      PrefetchHooks Function({bool ownerId, bool wordId})
    >;
typedef $$ReadingProgressEntriesTableCreateCompanionBuilder =
    ReadingProgressEntriesCompanion Function({
      required String id,
      required String ownerId,
      required String documentId,
      Value<int> documentRevision,
      Value<int> lastPosition,
      Value<bool> isCompleted,
      required int updatedAtUtcMs,
      Value<int> rowid,
    });
typedef $$ReadingProgressEntriesTableUpdateCompanionBuilder =
    ReadingProgressEntriesCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> documentId,
      Value<int> documentRevision,
      Value<int> lastPosition,
      Value<bool> isCompleted,
      Value<int> updatedAtUtcMs,
      Value<int> rowid,
    });

final class $$ReadingProgressEntriesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ReadingProgressEntriesTable,
          ReadingProgressEntry
        > {
  $$ReadingProgressEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('reading_progress_entries__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReadingProgressEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingProgressEntriesTable> {
  $$ReadingProgressEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get documentRevision => $composableBuilder(
    column: $table.documentRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPosition => $composableBuilder(
    column: $table.lastPosition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingProgressEntriesTable> {
  $$ReadingProgressEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get documentRevision => $composableBuilder(
    column: $table.documentRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPosition => $composableBuilder(
    column: $table.lastPosition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingProgressEntriesTable> {
  $$ReadingProgressEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get documentRevision => $composableBuilder(
    column: $table.documentRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastPosition => $composableBuilder(
    column: $table.lastPosition,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCompleted => $composableBuilder(
    column: $table.isCompleted,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingProgressEntriesTable,
          ReadingProgressEntry,
          $$ReadingProgressEntriesTableFilterComposer,
          $$ReadingProgressEntriesTableOrderingComposer,
          $$ReadingProgressEntriesTableAnnotationComposer,
          $$ReadingProgressEntriesTableCreateCompanionBuilder,
          $$ReadingProgressEntriesTableUpdateCompanionBuilder,
          (ReadingProgressEntry, $$ReadingProgressEntriesTableReferences),
          ReadingProgressEntry,
          PrefetchHooks Function({bool ownerId})
        > {
  $$ReadingProgressEntriesTableTableManager(
    _$AppDatabase db,
    $ReadingProgressEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingProgressEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ReadingProgressEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReadingProgressEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> documentId = const Value.absent(),
                Value<int> documentRevision = const Value.absent(),
                Value<int> lastPosition = const Value.absent(),
                Value<bool> isCompleted = const Value.absent(),
                Value<int> updatedAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressEntriesCompanion(
                id: id,
                ownerId: ownerId,
                documentId: documentId,
                documentRevision: documentRevision,
                lastPosition: lastPosition,
                isCompleted: isCompleted,
                updatedAtUtcMs: updatedAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String documentId,
                Value<int> documentRevision = const Value.absent(),
                Value<int> lastPosition = const Value.absent(),
                Value<bool> isCompleted = const Value.absent(),
                required int updatedAtUtcMs,
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressEntriesCompanion.insert(
                id: id,
                ownerId: ownerId,
                documentId: documentId,
                documentRevision: documentRevision,
                lastPosition: lastPosition,
                isCompleted: isCompleted,
                updatedAtUtcMs: updatedAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReadingProgressEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({ownerId = false}) {
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
                    if (ownerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.ownerId,
                                referencedTable:
                                    $$ReadingProgressEntriesTableReferences
                                        ._ownerIdTable(db),
                                referencedColumn:
                                    $$ReadingProgressEntriesTableReferences
                                        ._ownerIdTable(db)
                                        .id,
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

typedef $$ReadingProgressEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingProgressEntriesTable,
      ReadingProgressEntry,
      $$ReadingProgressEntriesTableFilterComposer,
      $$ReadingProgressEntriesTableOrderingComposer,
      $$ReadingProgressEntriesTableAnnotationComposer,
      $$ReadingProgressEntriesTableCreateCompanionBuilder,
      $$ReadingProgressEntriesTableUpdateCompanionBuilder,
      (ReadingProgressEntry, $$ReadingProgressEntriesTableReferences),
      ReadingProgressEntry,
      PrefetchHooks Function({bool ownerId})
    >;
typedef $$ReadingEventsTableCreateCompanionBuilder =
    ReadingEventsCompanion Function({
      required String id,
      required String ownerId,
      required String documentId,
      Value<int> documentRevision,
      required String eventType,
      Value<int?> position,
      required int occurredAtUtcMs,
      Value<int> rowid,
    });
typedef $$ReadingEventsTableUpdateCompanionBuilder =
    ReadingEventsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> documentId,
      Value<int> documentRevision,
      Value<String> eventType,
      Value<int?> position,
      Value<int> occurredAtUtcMs,
      Value<int> rowid,
    });

final class $$ReadingEventsTableReferences
    extends BaseReferences<_$AppDatabase, $ReadingEventsTable, ReadingEvent> {
  $$ReadingEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) =>
      db.localOwners.createAlias('reading_events__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReadingEventsTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingEventsTable> {
  $$ReadingEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get documentRevision => $composableBuilder(
    column: $table.documentRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurredAtUtcMs => $composableBuilder(
    column: $table.occurredAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingEventsTable> {
  $$ReadingEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get documentRevision => $composableBuilder(
    column: $table.documentRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurredAtUtcMs => $composableBuilder(
    column: $table.occurredAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingEventsTable> {
  $$ReadingEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get documentRevision => $composableBuilder(
    column: $table.documentRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get occurredAtUtcMs => $composableBuilder(
    column: $table.occurredAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingEventsTable,
          ReadingEvent,
          $$ReadingEventsTableFilterComposer,
          $$ReadingEventsTableOrderingComposer,
          $$ReadingEventsTableAnnotationComposer,
          $$ReadingEventsTableCreateCompanionBuilder,
          $$ReadingEventsTableUpdateCompanionBuilder,
          (ReadingEvent, $$ReadingEventsTableReferences),
          ReadingEvent,
          PrefetchHooks Function({bool ownerId})
        > {
  $$ReadingEventsTableTableManager(_$AppDatabase db, $ReadingEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadingEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> documentId = const Value.absent(),
                Value<int> documentRevision = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<int?> position = const Value.absent(),
                Value<int> occurredAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingEventsCompanion(
                id: id,
                ownerId: ownerId,
                documentId: documentId,
                documentRevision: documentRevision,
                eventType: eventType,
                position: position,
                occurredAtUtcMs: occurredAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String documentId,
                Value<int> documentRevision = const Value.absent(),
                required String eventType,
                Value<int?> position = const Value.absent(),
                required int occurredAtUtcMs,
                Value<int> rowid = const Value.absent(),
              }) => ReadingEventsCompanion.insert(
                id: id,
                ownerId: ownerId,
                documentId: documentId,
                documentRevision: documentRevision,
                eventType: eventType,
                position: position,
                occurredAtUtcMs: occurredAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReadingEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({ownerId = false}) {
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
                    if (ownerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.ownerId,
                                referencedTable: $$ReadingEventsTableReferences
                                    ._ownerIdTable(db),
                                referencedColumn: $$ReadingEventsTableReferences
                                    ._ownerIdTable(db)
                                    .id,
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

typedef $$ReadingEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingEventsTable,
      ReadingEvent,
      $$ReadingEventsTableFilterComposer,
      $$ReadingEventsTableOrderingComposer,
      $$ReadingEventsTableAnnotationComposer,
      $$ReadingEventsTableCreateCompanionBuilder,
      $$ReadingEventsTableUpdateCompanionBuilder,
      (ReadingEvent, $$ReadingEventsTableReferences),
      ReadingEvent,
      PrefetchHooks Function({bool ownerId})
    >;
typedef $$PointsLedgerEntriesTableCreateCompanionBuilder =
    PointsLedgerEntriesCompanion Function({
      required String id,
      required String ownerId,
      required String idempotencyKey,
      required String entryType,
      required int amount,
      Value<String?> sourceEventId,
      required int occurredAtUtcMs,
      Value<int> rowid,
    });
typedef $$PointsLedgerEntriesTableUpdateCompanionBuilder =
    PointsLedgerEntriesCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> idempotencyKey,
      Value<String> entryType,
      Value<int> amount,
      Value<String?> sourceEventId,
      Value<int> occurredAtUtcMs,
      Value<int> rowid,
    });

final class $$PointsLedgerEntriesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $PointsLedgerEntriesTable,
          PointsLedgerEntry
        > {
  $$PointsLedgerEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('points_ledger_entries__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PointsLedgerEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $PointsLedgerEntriesTable> {
  $$PointsLedgerEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryType => $composableBuilder(
    column: $table.entryType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurredAtUtcMs => $composableBuilder(
    column: $table.occurredAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PointsLedgerEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $PointsLedgerEntriesTable> {
  $$PointsLedgerEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryType => $composableBuilder(
    column: $table.entryType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurredAtUtcMs => $composableBuilder(
    column: $table.occurredAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PointsLedgerEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PointsLedgerEntriesTable> {
  $$PointsLedgerEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entryType =>
      $composableBuilder(column: $table.entryType, builder: (column) => column);

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get occurredAtUtcMs => $composableBuilder(
    column: $table.occurredAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PointsLedgerEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PointsLedgerEntriesTable,
          PointsLedgerEntry,
          $$PointsLedgerEntriesTableFilterComposer,
          $$PointsLedgerEntriesTableOrderingComposer,
          $$PointsLedgerEntriesTableAnnotationComposer,
          $$PointsLedgerEntriesTableCreateCompanionBuilder,
          $$PointsLedgerEntriesTableUpdateCompanionBuilder,
          (PointsLedgerEntry, $$PointsLedgerEntriesTableReferences),
          PointsLedgerEntry,
          PrefetchHooks Function({bool ownerId})
        > {
  $$PointsLedgerEntriesTableTableManager(
    _$AppDatabase db,
    $PointsLedgerEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PointsLedgerEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PointsLedgerEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PointsLedgerEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> idempotencyKey = const Value.absent(),
                Value<String> entryType = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<String?> sourceEventId = const Value.absent(),
                Value<int> occurredAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PointsLedgerEntriesCompanion(
                id: id,
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
                entryType: entryType,
                amount: amount,
                sourceEventId: sourceEventId,
                occurredAtUtcMs: occurredAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String idempotencyKey,
                required String entryType,
                required int amount,
                Value<String?> sourceEventId = const Value.absent(),
                required int occurredAtUtcMs,
                Value<int> rowid = const Value.absent(),
              }) => PointsLedgerEntriesCompanion.insert(
                id: id,
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
                entryType: entryType,
                amount: amount,
                sourceEventId: sourceEventId,
                occurredAtUtcMs: occurredAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PointsLedgerEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({ownerId = false}) {
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
                    if (ownerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.ownerId,
                                referencedTable:
                                    $$PointsLedgerEntriesTableReferences
                                        ._ownerIdTable(db),
                                referencedColumn:
                                    $$PointsLedgerEntriesTableReferences
                                        ._ownerIdTable(db)
                                        .id,
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

typedef $$PointsLedgerEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PointsLedgerEntriesTable,
      PointsLedgerEntry,
      $$PointsLedgerEntriesTableFilterComposer,
      $$PointsLedgerEntriesTableOrderingComposer,
      $$PointsLedgerEntriesTableAnnotationComposer,
      $$PointsLedgerEntriesTableCreateCompanionBuilder,
      $$PointsLedgerEntriesTableUpdateCompanionBuilder,
      (PointsLedgerEntry, $$PointsLedgerEntriesTableReferences),
      PointsLedgerEntry,
      PrefetchHooks Function({bool ownerId})
    >;
typedef $$AchievementUnlocksTableCreateCompanionBuilder =
    AchievementUnlocksCompanion Function({
      required String id,
      required String ownerId,
      required String achievementId,
      required int definitionVersion,
      required String sourceEventId,
      required int unlockedAtUtcMs,
      Value<int> rowid,
    });
typedef $$AchievementUnlocksTableUpdateCompanionBuilder =
    AchievementUnlocksCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> achievementId,
      Value<int> definitionVersion,
      Value<String> sourceEventId,
      Value<int> unlockedAtUtcMs,
      Value<int> rowid,
    });

final class $$AchievementUnlocksTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $AchievementUnlocksTable,
          AchievementUnlock
        > {
  $$AchievementUnlocksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('achievement_unlocks__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AchievementUnlocksTableFilterComposer
    extends Composer<_$AppDatabase, $AchievementUnlocksTable> {
  $$AchievementUnlocksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get achievementId => $composableBuilder(
    column: $table.achievementId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get definitionVersion => $composableBuilder(
    column: $table.definitionVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unlockedAtUtcMs => $composableBuilder(
    column: $table.unlockedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AchievementUnlocksTableOrderingComposer
    extends Composer<_$AppDatabase, $AchievementUnlocksTable> {
  $$AchievementUnlocksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get achievementId => $composableBuilder(
    column: $table.achievementId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get definitionVersion => $composableBuilder(
    column: $table.definitionVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unlockedAtUtcMs => $composableBuilder(
    column: $table.unlockedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AchievementUnlocksTableAnnotationComposer
    extends Composer<_$AppDatabase, $AchievementUnlocksTable> {
  $$AchievementUnlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get achievementId => $composableBuilder(
    column: $table.achievementId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get definitionVersion => $composableBuilder(
    column: $table.definitionVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unlockedAtUtcMs => $composableBuilder(
    column: $table.unlockedAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AchievementUnlocksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AchievementUnlocksTable,
          AchievementUnlock,
          $$AchievementUnlocksTableFilterComposer,
          $$AchievementUnlocksTableOrderingComposer,
          $$AchievementUnlocksTableAnnotationComposer,
          $$AchievementUnlocksTableCreateCompanionBuilder,
          $$AchievementUnlocksTableUpdateCompanionBuilder,
          (AchievementUnlock, $$AchievementUnlocksTableReferences),
          AchievementUnlock,
          PrefetchHooks Function({bool ownerId})
        > {
  $$AchievementUnlocksTableTableManager(
    _$AppDatabase db,
    $AchievementUnlocksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AchievementUnlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AchievementUnlocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AchievementUnlocksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> achievementId = const Value.absent(),
                Value<int> definitionVersion = const Value.absent(),
                Value<String> sourceEventId = const Value.absent(),
                Value<int> unlockedAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AchievementUnlocksCompanion(
                id: id,
                ownerId: ownerId,
                achievementId: achievementId,
                definitionVersion: definitionVersion,
                sourceEventId: sourceEventId,
                unlockedAtUtcMs: unlockedAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String achievementId,
                required int definitionVersion,
                required String sourceEventId,
                required int unlockedAtUtcMs,
                Value<int> rowid = const Value.absent(),
              }) => AchievementUnlocksCompanion.insert(
                id: id,
                ownerId: ownerId,
                achievementId: achievementId,
                definitionVersion: definitionVersion,
                sourceEventId: sourceEventId,
                unlockedAtUtcMs: unlockedAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AchievementUnlocksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({ownerId = false}) {
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
                    if (ownerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.ownerId,
                                referencedTable:
                                    $$AchievementUnlocksTableReferences
                                        ._ownerIdTable(db),
                                referencedColumn:
                                    $$AchievementUnlocksTableReferences
                                        ._ownerIdTable(db)
                                        .id,
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

typedef $$AchievementUnlocksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AchievementUnlocksTable,
      AchievementUnlock,
      $$AchievementUnlocksTableFilterComposer,
      $$AchievementUnlocksTableOrderingComposer,
      $$AchievementUnlocksTableAnnotationComposer,
      $$AchievementUnlocksTableCreateCompanionBuilder,
      $$AchievementUnlocksTableUpdateCompanionBuilder,
      (AchievementUnlock, $$AchievementUnlocksTableReferences),
      AchievementUnlock,
      PrefetchHooks Function({bool ownerId})
    >;
typedef $$RewardTransactionsTableCreateCompanionBuilder =
    RewardTransactionsCompanion Function({
      required String id,
      required String ownerId,
      required String idempotencyKey,
      required String transactionType,
      required int amount,
      Value<String?> itemId,
      required int catalogVersion,
      Value<String?> sourceEventId,
      required int occurredAtUtcMs,
      Value<int> rowid,
    });
typedef $$RewardTransactionsTableUpdateCompanionBuilder =
    RewardTransactionsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> idempotencyKey,
      Value<String> transactionType,
      Value<int> amount,
      Value<String?> itemId,
      Value<int> catalogVersion,
      Value<String?> sourceEventId,
      Value<int> occurredAtUtcMs,
      Value<int> rowid,
    });

final class $$RewardTransactionsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $RewardTransactionsTable,
          RewardTransaction
        > {
  $$RewardTransactionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('reward_transactions__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$OwnedRewardItemsTable, List<OwnedRewardItem>>
  _ownedRewardItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.ownedRewardItems,
    aliasName:
        'reward_transactions__id__owned_reward_items__acquired_by_transaction_id',
  );

  $$OwnedRewardItemsTableProcessedTableManager get ownedRewardItemsRefs {
    final manager =
        $$OwnedRewardItemsTableTableManager($_db, $_db.ownedRewardItems).filter(
          (f) => f.acquiredByTransactionId.id.sqlEquals(
            $_itemColumn<String>('id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _ownedRewardItemsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RewardTransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $RewardTransactionsTable> {
  $$RewardTransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transactionType => $composableBuilder(
    column: $table.transactionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get catalogVersion => $composableBuilder(
    column: $table.catalogVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurredAtUtcMs => $composableBuilder(
    column: $table.occurredAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> ownedRewardItemsRefs(
    Expression<bool> Function($$OwnedRewardItemsTableFilterComposer f) f,
  ) {
    final $$OwnedRewardItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ownedRewardItems,
      getReferencedColumn: (t) => t.acquiredByTransactionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OwnedRewardItemsTableFilterComposer(
            $db: $db,
            $table: $db.ownedRewardItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RewardTransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $RewardTransactionsTable> {
  $$RewardTransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transactionType => $composableBuilder(
    column: $table.transactionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get catalogVersion => $composableBuilder(
    column: $table.catalogVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurredAtUtcMs => $composableBuilder(
    column: $table.occurredAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RewardTransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RewardTransactionsTable> {
  $$RewardTransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transactionType => $composableBuilder(
    column: $table.transactionType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<int> get catalogVersion => $composableBuilder(
    column: $table.catalogVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceEventId => $composableBuilder(
    column: $table.sourceEventId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get occurredAtUtcMs => $composableBuilder(
    column: $table.occurredAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> ownedRewardItemsRefs<T extends Object>(
    Expression<T> Function($$OwnedRewardItemsTableAnnotationComposer a) f,
  ) {
    final $$OwnedRewardItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ownedRewardItems,
      getReferencedColumn: (t) => t.acquiredByTransactionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OwnedRewardItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.ownedRewardItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RewardTransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RewardTransactionsTable,
          RewardTransaction,
          $$RewardTransactionsTableFilterComposer,
          $$RewardTransactionsTableOrderingComposer,
          $$RewardTransactionsTableAnnotationComposer,
          $$RewardTransactionsTableCreateCompanionBuilder,
          $$RewardTransactionsTableUpdateCompanionBuilder,
          (RewardTransaction, $$RewardTransactionsTableReferences),
          RewardTransaction,
          PrefetchHooks Function({bool ownerId, bool ownedRewardItemsRefs})
        > {
  $$RewardTransactionsTableTableManager(
    _$AppDatabase db,
    $RewardTransactionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RewardTransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RewardTransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RewardTransactionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> idempotencyKey = const Value.absent(),
                Value<String> transactionType = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<String?> itemId = const Value.absent(),
                Value<int> catalogVersion = const Value.absent(),
                Value<String?> sourceEventId = const Value.absent(),
                Value<int> occurredAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RewardTransactionsCompanion(
                id: id,
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
                transactionType: transactionType,
                amount: amount,
                itemId: itemId,
                catalogVersion: catalogVersion,
                sourceEventId: sourceEventId,
                occurredAtUtcMs: occurredAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String idempotencyKey,
                required String transactionType,
                required int amount,
                Value<String?> itemId = const Value.absent(),
                required int catalogVersion,
                Value<String?> sourceEventId = const Value.absent(),
                required int occurredAtUtcMs,
                Value<int> rowid = const Value.absent(),
              }) => RewardTransactionsCompanion.insert(
                id: id,
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
                transactionType: transactionType,
                amount: amount,
                itemId: itemId,
                catalogVersion: catalogVersion,
                sourceEventId: sourceEventId,
                occurredAtUtcMs: occurredAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RewardTransactionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({ownerId = false, ownedRewardItemsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (ownedRewardItemsRefs) db.ownedRewardItems,
                  ],
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
                        if (ownerId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.ownerId,
                                    referencedTable:
                                        $$RewardTransactionsTableReferences
                                            ._ownerIdTable(db),
                                    referencedColumn:
                                        $$RewardTransactionsTableReferences
                                            ._ownerIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (ownedRewardItemsRefs)
                        await $_getPrefetchedData<
                          RewardTransaction,
                          $RewardTransactionsTable,
                          OwnedRewardItem
                        >(
                          currentTable: table,
                          referencedTable: $$RewardTransactionsTableReferences
                              ._ownedRewardItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RewardTransactionsTableReferences(
                                db,
                                table,
                                p0,
                              ).ownedRewardItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.acquiredByTransactionId == item.id,
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

typedef $$RewardTransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RewardTransactionsTable,
      RewardTransaction,
      $$RewardTransactionsTableFilterComposer,
      $$RewardTransactionsTableOrderingComposer,
      $$RewardTransactionsTableAnnotationComposer,
      $$RewardTransactionsTableCreateCompanionBuilder,
      $$RewardTransactionsTableUpdateCompanionBuilder,
      (RewardTransaction, $$RewardTransactionsTableReferences),
      RewardTransaction,
      PrefetchHooks Function({bool ownerId, bool ownedRewardItemsRefs})
    >;
typedef $$OwnedRewardItemsTableCreateCompanionBuilder =
    OwnedRewardItemsCompanion Function({
      required String id,
      required String ownerId,
      required String itemId,
      required int catalogVersion,
      required String acquiredByTransactionId,
      required int acquiredAtUtcMs,
      Value<int> rowid,
    });
typedef $$OwnedRewardItemsTableUpdateCompanionBuilder =
    OwnedRewardItemsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> itemId,
      Value<int> catalogVersion,
      Value<String> acquiredByTransactionId,
      Value<int> acquiredAtUtcMs,
      Value<int> rowid,
    });

final class $$OwnedRewardItemsTableReferences
    extends
        BaseReferences<_$AppDatabase, $OwnedRewardItemsTable, OwnedRewardItem> {
  $$OwnedRewardItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('owned_reward_items__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $RewardTransactionsTable _acquiredByTransactionIdTable(
    _$AppDatabase db,
  ) => db.rewardTransactions.createAlias(
    'owned_reward_items__acquired_by_transaction_id__reward_transactions__id',
  );

  $$RewardTransactionsTableProcessedTableManager get acquiredByTransactionId {
    final $_column = $_itemColumn<String>('acquired_by_transaction_id')!;

    final manager = $$RewardTransactionsTableTableManager(
      $_db,
      $_db.rewardTransactions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(
      _acquiredByTransactionIdTable($_db),
    );
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OwnedRewardItemsTableFilterComposer
    extends Composer<_$AppDatabase, $OwnedRewardItemsTable> {
  $$OwnedRewardItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get catalogVersion => $composableBuilder(
    column: $table.catalogVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acquiredAtUtcMs => $composableBuilder(
    column: $table.acquiredAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RewardTransactionsTableFilterComposer get acquiredByTransactionId {
    final $$RewardTransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.acquiredByTransactionId,
      referencedTable: $db.rewardTransactions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RewardTransactionsTableFilterComposer(
            $db: $db,
            $table: $db.rewardTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OwnedRewardItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $OwnedRewardItemsTable> {
  $$OwnedRewardItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get catalogVersion => $composableBuilder(
    column: $table.catalogVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acquiredAtUtcMs => $composableBuilder(
    column: $table.acquiredAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RewardTransactionsTableOrderingComposer get acquiredByTransactionId {
    final $$RewardTransactionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.acquiredByTransactionId,
      referencedTable: $db.rewardTransactions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RewardTransactionsTableOrderingComposer(
            $db: $db,
            $table: $db.rewardTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OwnedRewardItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OwnedRewardItemsTable> {
  $$OwnedRewardItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<int> get catalogVersion => $composableBuilder(
    column: $table.catalogVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get acquiredAtUtcMs => $composableBuilder(
    column: $table.acquiredAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$RewardTransactionsTableAnnotationComposer get acquiredByTransactionId {
    final $$RewardTransactionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.acquiredByTransactionId,
          referencedTable: $db.rewardTransactions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RewardTransactionsTableAnnotationComposer(
                $db: $db,
                $table: $db.rewardTransactions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$OwnedRewardItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OwnedRewardItemsTable,
          OwnedRewardItem,
          $$OwnedRewardItemsTableFilterComposer,
          $$OwnedRewardItemsTableOrderingComposer,
          $$OwnedRewardItemsTableAnnotationComposer,
          $$OwnedRewardItemsTableCreateCompanionBuilder,
          $$OwnedRewardItemsTableUpdateCompanionBuilder,
          (OwnedRewardItem, $$OwnedRewardItemsTableReferences),
          OwnedRewardItem,
          PrefetchHooks Function({bool ownerId, bool acquiredByTransactionId})
        > {
  $$OwnedRewardItemsTableTableManager(
    _$AppDatabase db,
    $OwnedRewardItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OwnedRewardItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OwnedRewardItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OwnedRewardItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<int> catalogVersion = const Value.absent(),
                Value<String> acquiredByTransactionId = const Value.absent(),
                Value<int> acquiredAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OwnedRewardItemsCompanion(
                id: id,
                ownerId: ownerId,
                itemId: itemId,
                catalogVersion: catalogVersion,
                acquiredByTransactionId: acquiredByTransactionId,
                acquiredAtUtcMs: acquiredAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String itemId,
                required int catalogVersion,
                required String acquiredByTransactionId,
                required int acquiredAtUtcMs,
                Value<int> rowid = const Value.absent(),
              }) => OwnedRewardItemsCompanion.insert(
                id: id,
                ownerId: ownerId,
                itemId: itemId,
                catalogVersion: catalogVersion,
                acquiredByTransactionId: acquiredByTransactionId,
                acquiredAtUtcMs: acquiredAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OwnedRewardItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({ownerId = false, acquiredByTransactionId = false}) {
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
                        if (ownerId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.ownerId,
                                    referencedTable:
                                        $$OwnedRewardItemsTableReferences
                                            ._ownerIdTable(db),
                                    referencedColumn:
                                        $$OwnedRewardItemsTableReferences
                                            ._ownerIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (acquiredByTransactionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn:
                                        table.acquiredByTransactionId,
                                    referencedTable:
                                        $$OwnedRewardItemsTableReferences
                                            ._acquiredByTransactionIdTable(db),
                                    referencedColumn:
                                        $$OwnedRewardItemsTableReferences
                                            ._acquiredByTransactionIdTable(db)
                                            .id,
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

typedef $$OwnedRewardItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OwnedRewardItemsTable,
      OwnedRewardItem,
      $$OwnedRewardItemsTableFilterComposer,
      $$OwnedRewardItemsTableOrderingComposer,
      $$OwnedRewardItemsTableAnnotationComposer,
      $$OwnedRewardItemsTableCreateCompanionBuilder,
      $$OwnedRewardItemsTableUpdateCompanionBuilder,
      (OwnedRewardItem, $$OwnedRewardItemsTableReferences),
      OwnedRewardItem,
      PrefetchHooks Function({bool ownerId, bool acquiredByTransactionId})
    >;
typedef $$EquippedRewardItemsTableCreateCompanionBuilder =
    EquippedRewardItemsCompanion Function({
      required String id,
      required String ownerId,
      required String slot,
      required String itemId,
      required int equippedAtUtcMs,
      Value<int> rowid,
    });
typedef $$EquippedRewardItemsTableUpdateCompanionBuilder =
    EquippedRewardItemsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> slot,
      Value<String> itemId,
      Value<int> equippedAtUtcMs,
      Value<int> rowid,
    });

final class $$EquippedRewardItemsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $EquippedRewardItemsTable,
          EquippedRewardItem
        > {
  $$EquippedRewardItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('equipped_reward_items__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EquippedRewardItemsTableFilterComposer
    extends Composer<_$AppDatabase, $EquippedRewardItemsTable> {
  $$EquippedRewardItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get equippedAtUtcMs => $composableBuilder(
    column: $table.equippedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EquippedRewardItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $EquippedRewardItemsTable> {
  $$EquippedRewardItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get equippedAtUtcMs => $composableBuilder(
    column: $table.equippedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EquippedRewardItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EquippedRewardItemsTable> {
  $$EquippedRewardItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<int> get equippedAtUtcMs => $composableBuilder(
    column: $table.equippedAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EquippedRewardItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EquippedRewardItemsTable,
          EquippedRewardItem,
          $$EquippedRewardItemsTableFilterComposer,
          $$EquippedRewardItemsTableOrderingComposer,
          $$EquippedRewardItemsTableAnnotationComposer,
          $$EquippedRewardItemsTableCreateCompanionBuilder,
          $$EquippedRewardItemsTableUpdateCompanionBuilder,
          (EquippedRewardItem, $$EquippedRewardItemsTableReferences),
          EquippedRewardItem,
          PrefetchHooks Function({bool ownerId})
        > {
  $$EquippedRewardItemsTableTableManager(
    _$AppDatabase db,
    $EquippedRewardItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EquippedRewardItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EquippedRewardItemsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$EquippedRewardItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> slot = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<int> equippedAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EquippedRewardItemsCompanion(
                id: id,
                ownerId: ownerId,
                slot: slot,
                itemId: itemId,
                equippedAtUtcMs: equippedAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String slot,
                required String itemId,
                required int equippedAtUtcMs,
                Value<int> rowid = const Value.absent(),
              }) => EquippedRewardItemsCompanion.insert(
                id: id,
                ownerId: ownerId,
                slot: slot,
                itemId: itemId,
                equippedAtUtcMs: equippedAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EquippedRewardItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({ownerId = false}) {
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
                    if (ownerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.ownerId,
                                referencedTable:
                                    $$EquippedRewardItemsTableReferences
                                        ._ownerIdTable(db),
                                referencedColumn:
                                    $$EquippedRewardItemsTableReferences
                                        ._ownerIdTable(db)
                                        .id,
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

typedef $$EquippedRewardItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EquippedRewardItemsTable,
      EquippedRewardItem,
      $$EquippedRewardItemsTableFilterComposer,
      $$EquippedRewardItemsTableOrderingComposer,
      $$EquippedRewardItemsTableAnnotationComposer,
      $$EquippedRewardItemsTableCreateCompanionBuilder,
      $$EquippedRewardItemsTableUpdateCompanionBuilder,
      (EquippedRewardItem, $$EquippedRewardItemsTableReferences),
      EquippedRewardItem,
      PrefetchHooks Function({bool ownerId})
    >;
typedef $$OutboxOperationsTableCreateCompanionBuilder =
    OutboxOperationsCompanion Function({
      required String operationId,
      required String ownerId,
      required String entityType,
      required String entityId,
      required String operationKind,
      Value<int> payloadVersion,
      Value<int> baseRevision,
      Value<String> state,
      Value<int> attemptCount,
      Value<int?> nextAttemptAtUtcMs,
      Value<String?> leaseToken,
      Value<int?> leaseExpiresAtUtcMs,
      Value<int?> lastAttemptAtUtcMs,
      required int createdAtUtcMs,
      Value<int?> acknowledgedAtUtcMs,
      Value<String?> failureCode,
      Value<int> rowid,
    });
typedef $$OutboxOperationsTableUpdateCompanionBuilder =
    OutboxOperationsCompanion Function({
      Value<String> operationId,
      Value<String> ownerId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operationKind,
      Value<int> payloadVersion,
      Value<int> baseRevision,
      Value<String> state,
      Value<int> attemptCount,
      Value<int?> nextAttemptAtUtcMs,
      Value<String?> leaseToken,
      Value<int?> leaseExpiresAtUtcMs,
      Value<int?> lastAttemptAtUtcMs,
      Value<int> createdAtUtcMs,
      Value<int?> acknowledgedAtUtcMs,
      Value<String?> failureCode,
      Value<int> rowid,
    });

final class $$OutboxOperationsTableReferences
    extends
        BaseReferences<_$AppDatabase, $OutboxOperationsTable, OutboxOperation> {
  $$OutboxOperationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('outbox_operations__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OutboxOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxOperationsTable> {
  $$OutboxOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationKind => $composableBuilder(
    column: $table.operationKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get payloadVersion => $composableBuilder(
    column: $table.payloadVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextAttemptAtUtcMs => $composableBuilder(
    column: $table.nextAttemptAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get leaseToken => $composableBuilder(
    column: $table.leaseToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get leaseExpiresAtUtcMs => $composableBuilder(
    column: $table.leaseExpiresAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAttemptAtUtcMs => $composableBuilder(
    column: $table.lastAttemptAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acknowledgedAtUtcMs => $composableBuilder(
    column: $table.acknowledgedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxOperationsTable> {
  $$OutboxOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationKind => $composableBuilder(
    column: $table.operationKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get payloadVersion => $composableBuilder(
    column: $table.payloadVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAtUtcMs => $composableBuilder(
    column: $table.nextAttemptAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get leaseToken => $composableBuilder(
    column: $table.leaseToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get leaseExpiresAtUtcMs => $composableBuilder(
    column: $table.leaseExpiresAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAttemptAtUtcMs => $composableBuilder(
    column: $table.lastAttemptAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acknowledgedAtUtcMs => $composableBuilder(
    column: $table.acknowledgedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxOperationsTable> {
  $$OutboxOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operationKind => $composableBuilder(
    column: $table.operationKind,
    builder: (column) => column,
  );

  GeneratedColumn<int> get payloadVersion => $composableBuilder(
    column: $table.payloadVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get nextAttemptAtUtcMs => $composableBuilder(
    column: $table.nextAttemptAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get leaseToken => $composableBuilder(
    column: $table.leaseToken,
    builder: (column) => column,
  );

  GeneratedColumn<int> get leaseExpiresAtUtcMs => $composableBuilder(
    column: $table.leaseExpiresAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastAttemptAtUtcMs => $composableBuilder(
    column: $table.lastAttemptAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtcMs => $composableBuilder(
    column: $table.createdAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get acknowledgedAtUtcMs => $composableBuilder(
    column: $table.acknowledgedAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxOperationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxOperationsTable,
          OutboxOperation,
          $$OutboxOperationsTableFilterComposer,
          $$OutboxOperationsTableOrderingComposer,
          $$OutboxOperationsTableAnnotationComposer,
          $$OutboxOperationsTableCreateCompanionBuilder,
          $$OutboxOperationsTableUpdateCompanionBuilder,
          (OutboxOperation, $$OutboxOperationsTableReferences),
          OutboxOperation,
          PrefetchHooks Function({bool ownerId})
        > {
  $$OutboxOperationsTableTableManager(
    _$AppDatabase db,
    $OutboxOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operationKind = const Value.absent(),
                Value<int> payloadVersion = const Value.absent(),
                Value<int> baseRevision = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int?> nextAttemptAtUtcMs = const Value.absent(),
                Value<String?> leaseToken = const Value.absent(),
                Value<int?> leaseExpiresAtUtcMs = const Value.absent(),
                Value<int?> lastAttemptAtUtcMs = const Value.absent(),
                Value<int> createdAtUtcMs = const Value.absent(),
                Value<int?> acknowledgedAtUtcMs = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxOperationsCompanion(
                operationId: operationId,
                ownerId: ownerId,
                entityType: entityType,
                entityId: entityId,
                operationKind: operationKind,
                payloadVersion: payloadVersion,
                baseRevision: baseRevision,
                state: state,
                attemptCount: attemptCount,
                nextAttemptAtUtcMs: nextAttemptAtUtcMs,
                leaseToken: leaseToken,
                leaseExpiresAtUtcMs: leaseExpiresAtUtcMs,
                lastAttemptAtUtcMs: lastAttemptAtUtcMs,
                createdAtUtcMs: createdAtUtcMs,
                acknowledgedAtUtcMs: acknowledgedAtUtcMs,
                failureCode: failureCode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String ownerId,
                required String entityType,
                required String entityId,
                required String operationKind,
                Value<int> payloadVersion = const Value.absent(),
                Value<int> baseRevision = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int?> nextAttemptAtUtcMs = const Value.absent(),
                Value<String?> leaseToken = const Value.absent(),
                Value<int?> leaseExpiresAtUtcMs = const Value.absent(),
                Value<int?> lastAttemptAtUtcMs = const Value.absent(),
                required int createdAtUtcMs,
                Value<int?> acknowledgedAtUtcMs = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxOperationsCompanion.insert(
                operationId: operationId,
                ownerId: ownerId,
                entityType: entityType,
                entityId: entityId,
                operationKind: operationKind,
                payloadVersion: payloadVersion,
                baseRevision: baseRevision,
                state: state,
                attemptCount: attemptCount,
                nextAttemptAtUtcMs: nextAttemptAtUtcMs,
                leaseToken: leaseToken,
                leaseExpiresAtUtcMs: leaseExpiresAtUtcMs,
                lastAttemptAtUtcMs: lastAttemptAtUtcMs,
                createdAtUtcMs: createdAtUtcMs,
                acknowledgedAtUtcMs: acknowledgedAtUtcMs,
                failureCode: failureCode,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OutboxOperationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({ownerId = false}) {
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
                    if (ownerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.ownerId,
                                referencedTable:
                                    $$OutboxOperationsTableReferences
                                        ._ownerIdTable(db),
                                referencedColumn:
                                    $$OutboxOperationsTableReferences
                                        ._ownerIdTable(db)
                                        .id,
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

typedef $$OutboxOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxOperationsTable,
      OutboxOperation,
      $$OutboxOperationsTableFilterComposer,
      $$OutboxOperationsTableOrderingComposer,
      $$OutboxOperationsTableAnnotationComposer,
      $$OutboxOperationsTableCreateCompanionBuilder,
      $$OutboxOperationsTableUpdateCompanionBuilder,
      (OutboxOperation, $$OutboxOperationsTableReferences),
      OutboxOperation,
      PrefetchHooks Function({bool ownerId})
    >;
typedef $$SyncCheckpointsTableCreateCompanionBuilder =
    SyncCheckpointsCompanion Function({
      required String id,
      required String ownerId,
      required String collectionName,
      Value<String?> serverCursor,
      Value<int?> lastSuccessAtUtcMs,
      Value<int> rowid,
    });
typedef $$SyncCheckpointsTableUpdateCompanionBuilder =
    SyncCheckpointsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> collectionName,
      Value<String?> serverCursor,
      Value<int?> lastSuccessAtUtcMs,
      Value<int> rowid,
    });

final class $$SyncCheckpointsTableReferences
    extends
        BaseReferences<_$AppDatabase, $SyncCheckpointsTable, SyncCheckpoint> {
  $$SyncCheckpointsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) => db.localOwners
      .createAlias('sync_checkpoints__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SyncCheckpointsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncCheckpointsTable> {
  $$SyncCheckpointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectionName => $composableBuilder(
    column: $table.collectionName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverCursor => $composableBuilder(
    column: $table.serverCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSuccessAtUtcMs => $composableBuilder(
    column: $table.lastSuccessAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SyncCheckpointsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncCheckpointsTable> {
  $$SyncCheckpointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectionName => $composableBuilder(
    column: $table.collectionName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverCursor => $composableBuilder(
    column: $table.serverCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSuccessAtUtcMs => $composableBuilder(
    column: $table.lastSuccessAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SyncCheckpointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncCheckpointsTable> {
  $$SyncCheckpointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get collectionName => $composableBuilder(
    column: $table.collectionName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverCursor => $composableBuilder(
    column: $table.serverCursor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSuccessAtUtcMs => $composableBuilder(
    column: $table.lastSuccessAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SyncCheckpointsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncCheckpointsTable,
          SyncCheckpoint,
          $$SyncCheckpointsTableFilterComposer,
          $$SyncCheckpointsTableOrderingComposer,
          $$SyncCheckpointsTableAnnotationComposer,
          $$SyncCheckpointsTableCreateCompanionBuilder,
          $$SyncCheckpointsTableUpdateCompanionBuilder,
          (SyncCheckpoint, $$SyncCheckpointsTableReferences),
          SyncCheckpoint,
          PrefetchHooks Function({bool ownerId})
        > {
  $$SyncCheckpointsTableTableManager(
    _$AppDatabase db,
    $SyncCheckpointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCheckpointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCheckpointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCheckpointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> collectionName = const Value.absent(),
                Value<String?> serverCursor = const Value.absent(),
                Value<int?> lastSuccessAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCheckpointsCompanion(
                id: id,
                ownerId: ownerId,
                collectionName: collectionName,
                serverCursor: serverCursor,
                lastSuccessAtUtcMs: lastSuccessAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String collectionName,
                Value<String?> serverCursor = const Value.absent(),
                Value<int?> lastSuccessAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCheckpointsCompanion.insert(
                id: id,
                ownerId: ownerId,
                collectionName: collectionName,
                serverCursor: serverCursor,
                lastSuccessAtUtcMs: lastSuccessAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SyncCheckpointsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({ownerId = false}) {
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
                    if (ownerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.ownerId,
                                referencedTable:
                                    $$SyncCheckpointsTableReferences
                                        ._ownerIdTable(db),
                                referencedColumn:
                                    $$SyncCheckpointsTableReferences
                                        ._ownerIdTable(db)
                                        .id,
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

typedef $$SyncCheckpointsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncCheckpointsTable,
      SyncCheckpoint,
      $$SyncCheckpointsTableFilterComposer,
      $$SyncCheckpointsTableOrderingComposer,
      $$SyncCheckpointsTableAnnotationComposer,
      $$SyncCheckpointsTableCreateCompanionBuilder,
      $$SyncCheckpointsTableUpdateCompanionBuilder,
      (SyncCheckpoint, $$SyncCheckpointsTableReferences),
      SyncCheckpoint,
      PrefetchHooks Function({bool ownerId})
    >;
typedef $$SyncConflictsTableCreateCompanionBuilder =
    SyncConflictsCompanion Function({
      required String id,
      required String ownerId,
      required String entityType,
      required String entityId,
      required int localRevision,
      required int cloudRevision,
      required String resolutionPolicy,
      required String outcome,
      Value<String?> localSnapshotJson,
      Value<String?> cloudSnapshotJson,
      required int resolvedAtUtcMs,
      Value<int> rowid,
    });
typedef $$SyncConflictsTableUpdateCompanionBuilder =
    SyncConflictsCompanion Function({
      Value<String> id,
      Value<String> ownerId,
      Value<String> entityType,
      Value<String> entityId,
      Value<int> localRevision,
      Value<int> cloudRevision,
      Value<String> resolutionPolicy,
      Value<String> outcome,
      Value<String?> localSnapshotJson,
      Value<String?> cloudSnapshotJson,
      Value<int> resolvedAtUtcMs,
      Value<int> rowid,
    });

final class $$SyncConflictsTableReferences
    extends BaseReferences<_$AppDatabase, $SyncConflictsTable, SyncConflict> {
  $$SyncConflictsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalOwnersTable _ownerIdTable(_$AppDatabase db) =>
      db.localOwners.createAlias('sync_conflicts__owner_id__local_owners__id');

  $$LocalOwnersTableProcessedTableManager get ownerId {
    final $_column = $_itemColumn<String>('owner_id')!;

    final manager = $$LocalOwnersTableTableManager(
      $_db,
      $_db.localOwners,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SyncConflictsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncConflictsTable> {
  $$SyncConflictsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cloudRevision => $composableBuilder(
    column: $table.cloudRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolutionPolicy => $composableBuilder(
    column: $table.resolutionPolicy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localSnapshotJson => $composableBuilder(
    column: $table.localSnapshotJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudSnapshotJson => $composableBuilder(
    column: $table.cloudSnapshotJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolvedAtUtcMs => $composableBuilder(
    column: $table.resolvedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalOwnersTableFilterComposer get ownerId {
    final $$LocalOwnersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableFilterComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SyncConflictsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncConflictsTable> {
  $$SyncConflictsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cloudRevision => $composableBuilder(
    column: $table.cloudRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolutionPolicy => $composableBuilder(
    column: $table.resolutionPolicy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localSnapshotJson => $composableBuilder(
    column: $table.localSnapshotJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudSnapshotJson => $composableBuilder(
    column: $table.cloudSnapshotJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolvedAtUtcMs => $composableBuilder(
    column: $table.resolvedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalOwnersTableOrderingComposer get ownerId {
    final $$LocalOwnersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableOrderingComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SyncConflictsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncConflictsTable> {
  $$SyncConflictsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cloudRevision => $composableBuilder(
    column: $table.cloudRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resolutionPolicy => $composableBuilder(
    column: $table.resolutionPolicy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumn<String> get localSnapshotJson => $composableBuilder(
    column: $table.localSnapshotJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudSnapshotJson => $composableBuilder(
    column: $table.cloudSnapshotJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get resolvedAtUtcMs => $composableBuilder(
    column: $table.resolvedAtUtcMs,
    builder: (column) => column,
  );

  $$LocalOwnersTableAnnotationComposer get ownerId {
    final $$LocalOwnersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerId,
      referencedTable: $db.localOwners,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalOwnersTableAnnotationComposer(
            $db: $db,
            $table: $db.localOwners,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SyncConflictsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncConflictsTable,
          SyncConflict,
          $$SyncConflictsTableFilterComposer,
          $$SyncConflictsTableOrderingComposer,
          $$SyncConflictsTableAnnotationComposer,
          $$SyncConflictsTableCreateCompanionBuilder,
          $$SyncConflictsTableUpdateCompanionBuilder,
          (SyncConflict, $$SyncConflictsTableReferences),
          SyncConflict,
          PrefetchHooks Function({bool ownerId})
        > {
  $$SyncConflictsTableTableManager(_$AppDatabase db, $SyncConflictsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncConflictsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncConflictsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncConflictsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<int> cloudRevision = const Value.absent(),
                Value<String> resolutionPolicy = const Value.absent(),
                Value<String> outcome = const Value.absent(),
                Value<String?> localSnapshotJson = const Value.absent(),
                Value<String?> cloudSnapshotJson = const Value.absent(),
                Value<int> resolvedAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncConflictsCompanion(
                id: id,
                ownerId: ownerId,
                entityType: entityType,
                entityId: entityId,
                localRevision: localRevision,
                cloudRevision: cloudRevision,
                resolutionPolicy: resolutionPolicy,
                outcome: outcome,
                localSnapshotJson: localSnapshotJson,
                cloudSnapshotJson: cloudSnapshotJson,
                resolvedAtUtcMs: resolvedAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String entityType,
                required String entityId,
                required int localRevision,
                required int cloudRevision,
                required String resolutionPolicy,
                required String outcome,
                Value<String?> localSnapshotJson = const Value.absent(),
                Value<String?> cloudSnapshotJson = const Value.absent(),
                required int resolvedAtUtcMs,
                Value<int> rowid = const Value.absent(),
              }) => SyncConflictsCompanion.insert(
                id: id,
                ownerId: ownerId,
                entityType: entityType,
                entityId: entityId,
                localRevision: localRevision,
                cloudRevision: cloudRevision,
                resolutionPolicy: resolutionPolicy,
                outcome: outcome,
                localSnapshotJson: localSnapshotJson,
                cloudSnapshotJson: cloudSnapshotJson,
                resolvedAtUtcMs: resolvedAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SyncConflictsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({ownerId = false}) {
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
                    if (ownerId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.ownerId,
                                referencedTable: $$SyncConflictsTableReferences
                                    ._ownerIdTable(db),
                                referencedColumn: $$SyncConflictsTableReferences
                                    ._ownerIdTable(db)
                                    .id,
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

typedef $$SyncConflictsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncConflictsTable,
      SyncConflict,
      $$SyncConflictsTableFilterComposer,
      $$SyncConflictsTableOrderingComposer,
      $$SyncConflictsTableAnnotationComposer,
      $$SyncConflictsTableCreateCompanionBuilder,
      $$SyncConflictsTableUpdateCompanionBuilder,
      (SyncConflict, $$SyncConflictsTableReferences),
      SyncConflict,
      PrefetchHooks Function({bool ownerId})
    >;
typedef $$RuntimeFlagsTableCreateCompanionBuilder =
    RuntimeFlagsCompanion Function({
      required String key,
      required bool boolValue,
      Value<String> source,
      required int updatedAtUtcMs,
      Value<int?> expiresAtUtcMs,
      Value<int> rowid,
    });
typedef $$RuntimeFlagsTableUpdateCompanionBuilder =
    RuntimeFlagsCompanion Function({
      Value<String> key,
      Value<bool> boolValue,
      Value<String> source,
      Value<int> updatedAtUtcMs,
      Value<int?> expiresAtUtcMs,
      Value<int> rowid,
    });

class $$RuntimeFlagsTableFilterComposer
    extends Composer<_$AppDatabase, $RuntimeFlagsTable> {
  $$RuntimeFlagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get boolValue => $composableBuilder(
    column: $table.boolValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAtUtcMs => $composableBuilder(
    column: $table.expiresAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RuntimeFlagsTableOrderingComposer
    extends Composer<_$AppDatabase, $RuntimeFlagsTable> {
  $$RuntimeFlagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get boolValue => $composableBuilder(
    column: $table.boolValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAtUtcMs => $composableBuilder(
    column: $table.expiresAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RuntimeFlagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RuntimeFlagsTable> {
  $$RuntimeFlagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<bool> get boolValue =>
      $composableBuilder(column: $table.boolValue, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expiresAtUtcMs => $composableBuilder(
    column: $table.expiresAtUtcMs,
    builder: (column) => column,
  );
}

class $$RuntimeFlagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RuntimeFlagsTable,
          RuntimeFlag,
          $$RuntimeFlagsTableFilterComposer,
          $$RuntimeFlagsTableOrderingComposer,
          $$RuntimeFlagsTableAnnotationComposer,
          $$RuntimeFlagsTableCreateCompanionBuilder,
          $$RuntimeFlagsTableUpdateCompanionBuilder,
          (
            RuntimeFlag,
            BaseReferences<_$AppDatabase, $RuntimeFlagsTable, RuntimeFlag>,
          ),
          RuntimeFlag,
          PrefetchHooks Function()
        > {
  $$RuntimeFlagsTableTableManager(_$AppDatabase db, $RuntimeFlagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RuntimeFlagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RuntimeFlagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RuntimeFlagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<bool> boolValue = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int> updatedAtUtcMs = const Value.absent(),
                Value<int?> expiresAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RuntimeFlagsCompanion(
                key: key,
                boolValue: boolValue,
                source: source,
                updatedAtUtcMs: updatedAtUtcMs,
                expiresAtUtcMs: expiresAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required bool boolValue,
                Value<String> source = const Value.absent(),
                required int updatedAtUtcMs,
                Value<int?> expiresAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RuntimeFlagsCompanion.insert(
                key: key,
                boolValue: boolValue,
                source: source,
                updatedAtUtcMs: updatedAtUtcMs,
                expiresAtUtcMs: expiresAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RuntimeFlagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RuntimeFlagsTable,
      RuntimeFlag,
      $$RuntimeFlagsTableFilterComposer,
      $$RuntimeFlagsTableOrderingComposer,
      $$RuntimeFlagsTableAnnotationComposer,
      $$RuntimeFlagsTableCreateCompanionBuilder,
      $$RuntimeFlagsTableUpdateCompanionBuilder,
      (
        RuntimeFlag,
        BaseReferences<_$AppDatabase, $RuntimeFlagsTable, RuntimeFlag>,
      ),
      RuntimeFlag,
      PrefetchHooks Function()
    >;
typedef $$ModelDownloadsTableCreateCompanionBuilder =
    ModelDownloadsCompanion Function({
      required String id,
      required String modelVersion,
      required String sourceUrl,
      required String expectedChecksum,
      required int expectedBytes,
      Value<int> downloadedBytes,
      Value<int> retryCount,
      Value<String> state,
      Value<String?> localPath,
      Value<String?> failureCode,
      required int updatedAtUtcMs,
      Value<int> rowid,
    });
typedef $$ModelDownloadsTableUpdateCompanionBuilder =
    ModelDownloadsCompanion Function({
      Value<String> id,
      Value<String> modelVersion,
      Value<String> sourceUrl,
      Value<String> expectedChecksum,
      Value<int> expectedBytes,
      Value<int> downloadedBytes,
      Value<int> retryCount,
      Value<String> state,
      Value<String?> localPath,
      Value<String?> failureCode,
      Value<int> updatedAtUtcMs,
      Value<int> rowid,
    });

class $$ModelDownloadsTableFilterComposer
    extends Composer<_$AppDatabase, $ModelDownloadsTable> {
  $$ModelDownloadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expectedChecksum => $composableBuilder(
    column: $table.expectedChecksum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedBytes => $composableBuilder(
    column: $table.expectedBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get downloadedBytes => $composableBuilder(
    column: $table.downloadedBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ModelDownloadsTableOrderingComposer
    extends Composer<_$AppDatabase, $ModelDownloadsTable> {
  $$ModelDownloadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceUrl => $composableBuilder(
    column: $table.sourceUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expectedChecksum => $composableBuilder(
    column: $table.expectedChecksum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedBytes => $composableBuilder(
    column: $table.expectedBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get downloadedBytes => $composableBuilder(
    column: $table.downloadedBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ModelDownloadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ModelDownloadsTable> {
  $$ModelDownloadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceUrl =>
      $composableBuilder(column: $table.sourceUrl, builder: (column) => column);

  GeneratedColumn<String> get expectedChecksum => $composableBuilder(
    column: $table.expectedChecksum,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expectedBytes => $composableBuilder(
    column: $table.expectedBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get downloadedBytes => $composableBuilder(
    column: $table.downloadedBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtcMs => $composableBuilder(
    column: $table.updatedAtUtcMs,
    builder: (column) => column,
  );
}

class $$ModelDownloadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ModelDownloadsTable,
          ModelDownload,
          $$ModelDownloadsTableFilterComposer,
          $$ModelDownloadsTableOrderingComposer,
          $$ModelDownloadsTableAnnotationComposer,
          $$ModelDownloadsTableCreateCompanionBuilder,
          $$ModelDownloadsTableUpdateCompanionBuilder,
          (
            ModelDownload,
            BaseReferences<_$AppDatabase, $ModelDownloadsTable, ModelDownload>,
          ),
          ModelDownload,
          PrefetchHooks Function()
        > {
  $$ModelDownloadsTableTableManager(
    _$AppDatabase db,
    $ModelDownloadsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ModelDownloadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ModelDownloadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ModelDownloadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> modelVersion = const Value.absent(),
                Value<String> sourceUrl = const Value.absent(),
                Value<String> expectedChecksum = const Value.absent(),
                Value<int> expectedBytes = const Value.absent(),
                Value<int> downloadedBytes = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<int> updatedAtUtcMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModelDownloadsCompanion(
                id: id,
                modelVersion: modelVersion,
                sourceUrl: sourceUrl,
                expectedChecksum: expectedChecksum,
                expectedBytes: expectedBytes,
                downloadedBytes: downloadedBytes,
                retryCount: retryCount,
                state: state,
                localPath: localPath,
                failureCode: failureCode,
                updatedAtUtcMs: updatedAtUtcMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String modelVersion,
                required String sourceUrl,
                required String expectedChecksum,
                required int expectedBytes,
                Value<int> downloadedBytes = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                required int updatedAtUtcMs,
                Value<int> rowid = const Value.absent(),
              }) => ModelDownloadsCompanion.insert(
                id: id,
                modelVersion: modelVersion,
                sourceUrl: sourceUrl,
                expectedChecksum: expectedChecksum,
                expectedBytes: expectedBytes,
                downloadedBytes: downloadedBytes,
                retryCount: retryCount,
                state: state,
                localPath: localPath,
                failureCode: failureCode,
                updatedAtUtcMs: updatedAtUtcMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ModelDownloadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ModelDownloadsTable,
      ModelDownload,
      $$ModelDownloadsTableFilterComposer,
      $$ModelDownloadsTableOrderingComposer,
      $$ModelDownloadsTableAnnotationComposer,
      $$ModelDownloadsTableCreateCompanionBuilder,
      $$ModelDownloadsTableUpdateCompanionBuilder,
      (
        ModelDownload,
        BaseReferences<_$AppDatabase, $ModelDownloadsTable, ModelDownload>,
      ),
      ModelDownload,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalOwnersTableTableManager get localOwners =>
      $$LocalOwnersTableTableManager(_db, _db.localOwners);
  $$ResearchConsentsTableTableManager get researchConsents =>
      $$ResearchConsentsTableTableManager(_db, _db.researchConsents);
  $$VocabularyCategoriesTableTableManager get vocabularyCategories =>
      $$VocabularyCategoriesTableTableManager(_db, _db.vocabularyCategories);
  $$VocabularyWordsTableTableManager get vocabularyWords =>
      $$VocabularyWordsTableTableManager(_db, _db.vocabularyWords);
  $$VocabularyImportsTableTableManager get vocabularyImports =>
      $$VocabularyImportsTableTableManager(_db, _db.vocabularyImports);
  $$VocabularyImportRowsTableTableManager get vocabularyImportRows =>
      $$VocabularyImportRowsTableTableManager(_db, _db.vocabularyImportRows);
  $$LearningSessionsTableTableManager get learningSessions =>
      $$LearningSessionsTableTableManager(_db, _db.learningSessions);
  $$AnswerAttemptsTableTableManager get answerAttempts =>
      $$AnswerAttemptsTableTableManager(_db, _db.answerAttempts);
  $$SrsStatesTableTableManager get srsStates =>
      $$SrsStatesTableTableManager(_db, _db.srsStates);
  $$ReadingProgressEntriesTableTableManager get readingProgressEntries =>
      $$ReadingProgressEntriesTableTableManager(
        _db,
        _db.readingProgressEntries,
      );
  $$ReadingEventsTableTableManager get readingEvents =>
      $$ReadingEventsTableTableManager(_db, _db.readingEvents);
  $$PointsLedgerEntriesTableTableManager get pointsLedgerEntries =>
      $$PointsLedgerEntriesTableTableManager(_db, _db.pointsLedgerEntries);
  $$AchievementUnlocksTableTableManager get achievementUnlocks =>
      $$AchievementUnlocksTableTableManager(_db, _db.achievementUnlocks);
  $$RewardTransactionsTableTableManager get rewardTransactions =>
      $$RewardTransactionsTableTableManager(_db, _db.rewardTransactions);
  $$OwnedRewardItemsTableTableManager get ownedRewardItems =>
      $$OwnedRewardItemsTableTableManager(_db, _db.ownedRewardItems);
  $$EquippedRewardItemsTableTableManager get equippedRewardItems =>
      $$EquippedRewardItemsTableTableManager(_db, _db.equippedRewardItems);
  $$OutboxOperationsTableTableManager get outboxOperations =>
      $$OutboxOperationsTableTableManager(_db, _db.outboxOperations);
  $$SyncCheckpointsTableTableManager get syncCheckpoints =>
      $$SyncCheckpointsTableTableManager(_db, _db.syncCheckpoints);
  $$SyncConflictsTableTableManager get syncConflicts =>
      $$SyncConflictsTableTableManager(_db, _db.syncConflicts);
  $$RuntimeFlagsTableTableManager get runtimeFlags =>
      $$RuntimeFlagsTableTableManager(_db, _db.runtimeFlags);
  $$ModelDownloadsTableTableManager get modelDownloads =>
      $$ModelDownloadsTableTableManager(_db, _db.modelDownloads);
}
