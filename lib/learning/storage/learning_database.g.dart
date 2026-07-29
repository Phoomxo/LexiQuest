// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'learning_database.dart';

// ignore_for_file: type=lint
class $LearningCommitsTable extends LearningCommits
    with TableInfo<$LearningCommitsTable, LearningCommitRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LearningCommitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(1),
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<int> createdAtUtc = GeneratedColumn<int>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtc = GeneratedColumn<int>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commitIdMeta = const VerificationMeta(
    'commitId',
  );
  @override
  late final GeneratedColumn<String> commitId = GeneratedColumn<String>(
    'commit_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordedAtUtcMeta = const VerificationMeta(
    'recordedAtUtc',
  );
  @override
  late final GeneratedColumn<int> recordedAtUtc = GeneratedColumn<int>(
    'recorded_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordCountMeta = const VerificationMeta(
    'recordCount',
  );
  @override
  late final GeneratedColumn<int> recordCount = GeneratedColumn<int>(
    'record_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentFingerprintMeta =
      const VerificationMeta('contentFingerprint');
  @override
  late final GeneratedColumn<String> contentFingerprint =
      GeneratedColumn<String>(
        'content_fingerprint',
        aliasedName,
        false,
        additionalChecks: GeneratedColumn.checkTextLength(
          minTextLength: 64,
          maxTextLength: 64,
        ),
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    commitId,
    recordedAtUtc,
    recordCount,
    contentFingerprint,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'learning_commits';
  @override
  VerificationContext validateIntegrity(
    Insertable<LearningCommitRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    if (data.containsKey('commit_id')) {
      context.handle(
        _commitIdMeta,
        commitId.isAcceptableOrUnknown(data['commit_id']!, _commitIdMeta),
      );
    } else if (isInserting) {
      context.missing(_commitIdMeta);
    }
    if (data.containsKey('recorded_at_utc')) {
      context.handle(
        _recordedAtUtcMeta,
        recordedAtUtc.isAcceptableOrUnknown(
          data['recorded_at_utc']!,
          _recordedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordedAtUtcMeta);
    }
    if (data.containsKey('record_count')) {
      context.handle(
        _recordCountMeta,
        recordCount.isAcceptableOrUnknown(
          data['record_count']!,
          _recordCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordCountMeta);
    }
    if (data.containsKey('content_fingerprint')) {
      context.handle(
        _contentFingerprintMeta,
        contentFingerprint.isAcceptableOrUnknown(
          data['content_fingerprint']!,
          _contentFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentFingerprintMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, commitId};
  @override
  LearningCommitRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LearningCommitRow(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc'],
      )!,
      commitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}commit_id'],
      )!,
      recordedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recorded_at_utc'],
      )!,
      recordCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}record_count'],
      )!,
      contentFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_fingerprint'],
      )!,
    );
  }

  @override
  $LearningCommitsTable createAlias(String alias) {
    return $LearningCommitsTable(attachedDatabase, alias);
  }
}

class LearningCommitRow extends DataClass
    implements Insertable<LearningCommitRow> {
  final String ownerId;
  final int schemaVersion;
  final int createdAtUtc;
  final int updatedAtUtc;
  final String commitId;
  final int recordedAtUtc;
  final int recordCount;
  final String contentFingerprint;
  const LearningCommitRow({
    required this.ownerId,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.commitId,
    required this.recordedAtUtc,
    required this.recordCount,
    required this.contentFingerprint,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['created_at_utc'] = Variable<int>(createdAtUtc);
    map['updated_at_utc'] = Variable<int>(updatedAtUtc);
    map['commit_id'] = Variable<String>(commitId);
    map['recorded_at_utc'] = Variable<int>(recordedAtUtc);
    map['record_count'] = Variable<int>(recordCount);
    map['content_fingerprint'] = Variable<String>(contentFingerprint);
    return map;
  }

  LearningCommitsCompanion toCompanion(bool nullToAbsent) {
    return LearningCommitsCompanion(
      ownerId: Value(ownerId),
      schemaVersion: Value(schemaVersion),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
      commitId: Value(commitId),
      recordedAtUtc: Value(recordedAtUtc),
      recordCount: Value(recordCount),
      contentFingerprint: Value(contentFingerprint),
    );
  }

  factory LearningCommitRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LearningCommitRow(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      createdAtUtc: serializer.fromJson<int>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<int>(json['updatedAtUtc']),
      commitId: serializer.fromJson<String>(json['commitId']),
      recordedAtUtc: serializer.fromJson<int>(json['recordedAtUtc']),
      recordCount: serializer.fromJson<int>(json['recordCount']),
      contentFingerprint: serializer.fromJson<String>(
        json['contentFingerprint'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'createdAtUtc': serializer.toJson<int>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<int>(updatedAtUtc),
      'commitId': serializer.toJson<String>(commitId),
      'recordedAtUtc': serializer.toJson<int>(recordedAtUtc),
      'recordCount': serializer.toJson<int>(recordCount),
      'contentFingerprint': serializer.toJson<String>(contentFingerprint),
    };
  }

  LearningCommitRow copyWith({
    String? ownerId,
    int? schemaVersion,
    int? createdAtUtc,
    int? updatedAtUtc,
    String? commitId,
    int? recordedAtUtc,
    int? recordCount,
    String? contentFingerprint,
  }) => LearningCommitRow(
    ownerId: ownerId ?? this.ownerId,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    commitId: commitId ?? this.commitId,
    recordedAtUtc: recordedAtUtc ?? this.recordedAtUtc,
    recordCount: recordCount ?? this.recordCount,
    contentFingerprint: contentFingerprint ?? this.contentFingerprint,
  );
  LearningCommitRow copyWithCompanion(LearningCommitsCompanion data) {
    return LearningCommitRow(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
      commitId: data.commitId.present ? data.commitId.value : this.commitId,
      recordedAtUtc: data.recordedAtUtc.present
          ? data.recordedAtUtc.value
          : this.recordedAtUtc,
      recordCount: data.recordCount.present
          ? data.recordCount.value
          : this.recordCount,
      contentFingerprint: data.contentFingerprint.present
          ? data.contentFingerprint.value
          : this.contentFingerprint,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LearningCommitRow(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('commitId: $commitId, ')
          ..write('recordedAtUtc: $recordedAtUtc, ')
          ..write('recordCount: $recordCount, ')
          ..write('contentFingerprint: $contentFingerprint')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    commitId,
    recordedAtUtc,
    recordCount,
    contentFingerprint,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LearningCommitRow &&
          other.ownerId == this.ownerId &&
          other.schemaVersion == this.schemaVersion &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc &&
          other.commitId == this.commitId &&
          other.recordedAtUtc == this.recordedAtUtc &&
          other.recordCount == this.recordCount &&
          other.contentFingerprint == this.contentFingerprint);
}

class LearningCommitsCompanion extends UpdateCompanion<LearningCommitRow> {
  final Value<String> ownerId;
  final Value<int> schemaVersion;
  final Value<int> createdAtUtc;
  final Value<int> updatedAtUtc;
  final Value<String> commitId;
  final Value<int> recordedAtUtc;
  final Value<int> recordCount;
  final Value<String> contentFingerprint;
  final Value<int> rowid;
  const LearningCommitsCompanion({
    this.ownerId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.commitId = const Value.absent(),
    this.recordedAtUtc = const Value.absent(),
    this.recordCount = const Value.absent(),
    this.contentFingerprint = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LearningCommitsCompanion.insert({
    required String ownerId,
    this.schemaVersion = const Value.absent(),
    required int createdAtUtc,
    required int updatedAtUtc,
    required String commitId,
    required int recordedAtUtc,
    required int recordCount,
    required String contentFingerprint,
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc),
       commitId = Value(commitId),
       recordedAtUtc = Value(recordedAtUtc),
       recordCount = Value(recordCount),
       contentFingerprint = Value(contentFingerprint);
  static Insertable<LearningCommitRow> custom({
    Expression<String>? ownerId,
    Expression<int>? schemaVersion,
    Expression<int>? createdAtUtc,
    Expression<int>? updatedAtUtc,
    Expression<String>? commitId,
    Expression<int>? recordedAtUtc,
    Expression<int>? recordCount,
    Expression<String>? contentFingerprint,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (commitId != null) 'commit_id': commitId,
      if (recordedAtUtc != null) 'recorded_at_utc': recordedAtUtc,
      if (recordCount != null) 'record_count': recordCount,
      if (contentFingerprint != null) 'content_fingerprint': contentFingerprint,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LearningCommitsCompanion copyWith({
    Value<String>? ownerId,
    Value<int>? schemaVersion,
    Value<int>? createdAtUtc,
    Value<int>? updatedAtUtc,
    Value<String>? commitId,
    Value<int>? recordedAtUtc,
    Value<int>? recordCount,
    Value<String>? contentFingerprint,
    Value<int>? rowid,
  }) {
    return LearningCommitsCompanion(
      ownerId: ownerId ?? this.ownerId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      commitId: commitId ?? this.commitId,
      recordedAtUtc: recordedAtUtc ?? this.recordedAtUtc,
      recordCount: recordCount ?? this.recordCount,
      contentFingerprint: contentFingerprint ?? this.contentFingerprint,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<int>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<int>(updatedAtUtc.value);
    }
    if (commitId.present) {
      map['commit_id'] = Variable<String>(commitId.value);
    }
    if (recordedAtUtc.present) {
      map['recorded_at_utc'] = Variable<int>(recordedAtUtc.value);
    }
    if (recordCount.present) {
      map['record_count'] = Variable<int>(recordCount.value);
    }
    if (contentFingerprint.present) {
      map['content_fingerprint'] = Variable<String>(contentFingerprint.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LearningCommitsCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('commitId: $commitId, ')
          ..write('recordedAtUtc: $recordedAtUtc, ')
          ..write('recordCount: $recordCount, ')
          ..write('contentFingerprint: $contentFingerprint, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssociationsTable extends Associations
    with TableInfo<$AssociationsTable, AssociationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssociationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(1),
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<int> createdAtUtc = GeneratedColumn<int>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtc = GeneratedColumn<int>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _associationIdMeta = const VerificationMeta(
    'associationId',
  );
  @override
  late final GeneratedColumn<String> associationId = GeneratedColumn<String>(
    'association_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wordKeyMeta = const VerificationMeta(
    'wordKey',
  );
  @override
  late final GeneratedColumn<String> wordKey = GeneratedColumn<String>(
    'word_key',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cueTypeMeta = const VerificationMeta(
    'cueType',
  );
  @override
  late final GeneratedColumn<String> cueType = GeneratedColumn<String>(
    'cue_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cueTextMeta = const VerificationMeta(
    'cueText',
  );
  @override
  late final GeneratedColumn<String> cueText = GeneratedColumn<String>(
    'cue_text',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 500,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _strengthMeta = const VerificationMeta(
    'strength',
  );
  @override
  late final GeneratedColumn<double> strength = GeneratedColumn<double>(
    'strength',
    aliasedName,
    false,
    type: DriftSqlType.double,
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
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    associationId,
    wordKey,
    cueType,
    cueText,
    origin,
    strength,
    successCount,
    failureCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'associations';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssociationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    if (data.containsKey('association_id')) {
      context.handle(
        _associationIdMeta,
        associationId.isAcceptableOrUnknown(
          data['association_id']!,
          _associationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_associationIdMeta);
    }
    if (data.containsKey('word_key')) {
      context.handle(
        _wordKeyMeta,
        wordKey.isAcceptableOrUnknown(data['word_key']!, _wordKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_wordKeyMeta);
    }
    if (data.containsKey('cue_type')) {
      context.handle(
        _cueTypeMeta,
        cueType.isAcceptableOrUnknown(data['cue_type']!, _cueTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_cueTypeMeta);
    }
    if (data.containsKey('cue_text')) {
      context.handle(
        _cueTextMeta,
        cueText.isAcceptableOrUnknown(data['cue_text']!, _cueTextMeta),
      );
    } else if (isInserting) {
      context.missing(_cueTextMeta);
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('strength')) {
      context.handle(
        _strengthMeta,
        strength.isAcceptableOrUnknown(data['strength']!, _strengthMeta),
      );
    } else if (isInserting) {
      context.missing(_strengthMeta);
    }
    if (data.containsKey('success_count')) {
      context.handle(
        _successCountMeta,
        successCount.isAcceptableOrUnknown(
          data['success_count']!,
          _successCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_successCountMeta);
    }
    if (data.containsKey('failure_count')) {
      context.handle(
        _failureCountMeta,
        failureCount.isAcceptableOrUnknown(
          data['failure_count']!,
          _failureCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_failureCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, associationId};
  @override
  AssociationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssociationRow(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc'],
      )!,
      associationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}association_id'],
      )!,
      wordKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}word_key'],
      )!,
      cueType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cue_type'],
      )!,
      cueText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cue_text'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      strength: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}strength'],
      )!,
      successCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}success_count'],
      )!,
      failureCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failure_count'],
      )!,
    );
  }

  @override
  $AssociationsTable createAlias(String alias) {
    return $AssociationsTable(attachedDatabase, alias);
  }
}

class AssociationRow extends DataClass implements Insertable<AssociationRow> {
  final String ownerId;
  final int schemaVersion;
  final int createdAtUtc;
  final int updatedAtUtc;
  final String associationId;
  final String wordKey;
  final String cueType;
  final String cueText;
  final String origin;
  final double strength;
  final int successCount;
  final int failureCount;
  const AssociationRow({
    required this.ownerId,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.associationId,
    required this.wordKey,
    required this.cueType,
    required this.cueText,
    required this.origin,
    required this.strength,
    required this.successCount,
    required this.failureCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['created_at_utc'] = Variable<int>(createdAtUtc);
    map['updated_at_utc'] = Variable<int>(updatedAtUtc);
    map['association_id'] = Variable<String>(associationId);
    map['word_key'] = Variable<String>(wordKey);
    map['cue_type'] = Variable<String>(cueType);
    map['cue_text'] = Variable<String>(cueText);
    map['origin'] = Variable<String>(origin);
    map['strength'] = Variable<double>(strength);
    map['success_count'] = Variable<int>(successCount);
    map['failure_count'] = Variable<int>(failureCount);
    return map;
  }

  AssociationsCompanion toCompanion(bool nullToAbsent) {
    return AssociationsCompanion(
      ownerId: Value(ownerId),
      schemaVersion: Value(schemaVersion),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
      associationId: Value(associationId),
      wordKey: Value(wordKey),
      cueType: Value(cueType),
      cueText: Value(cueText),
      origin: Value(origin),
      strength: Value(strength),
      successCount: Value(successCount),
      failureCount: Value(failureCount),
    );
  }

  factory AssociationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssociationRow(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      createdAtUtc: serializer.fromJson<int>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<int>(json['updatedAtUtc']),
      associationId: serializer.fromJson<String>(json['associationId']),
      wordKey: serializer.fromJson<String>(json['wordKey']),
      cueType: serializer.fromJson<String>(json['cueType']),
      cueText: serializer.fromJson<String>(json['cueText']),
      origin: serializer.fromJson<String>(json['origin']),
      strength: serializer.fromJson<double>(json['strength']),
      successCount: serializer.fromJson<int>(json['successCount']),
      failureCount: serializer.fromJson<int>(json['failureCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'createdAtUtc': serializer.toJson<int>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<int>(updatedAtUtc),
      'associationId': serializer.toJson<String>(associationId),
      'wordKey': serializer.toJson<String>(wordKey),
      'cueType': serializer.toJson<String>(cueType),
      'cueText': serializer.toJson<String>(cueText),
      'origin': serializer.toJson<String>(origin),
      'strength': serializer.toJson<double>(strength),
      'successCount': serializer.toJson<int>(successCount),
      'failureCount': serializer.toJson<int>(failureCount),
    };
  }

  AssociationRow copyWith({
    String? ownerId,
    int? schemaVersion,
    int? createdAtUtc,
    int? updatedAtUtc,
    String? associationId,
    String? wordKey,
    String? cueType,
    String? cueText,
    String? origin,
    double? strength,
    int? successCount,
    int? failureCount,
  }) => AssociationRow(
    ownerId: ownerId ?? this.ownerId,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    associationId: associationId ?? this.associationId,
    wordKey: wordKey ?? this.wordKey,
    cueType: cueType ?? this.cueType,
    cueText: cueText ?? this.cueText,
    origin: origin ?? this.origin,
    strength: strength ?? this.strength,
    successCount: successCount ?? this.successCount,
    failureCount: failureCount ?? this.failureCount,
  );
  AssociationRow copyWithCompanion(AssociationsCompanion data) {
    return AssociationRow(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
      associationId: data.associationId.present
          ? data.associationId.value
          : this.associationId,
      wordKey: data.wordKey.present ? data.wordKey.value : this.wordKey,
      cueType: data.cueType.present ? data.cueType.value : this.cueType,
      cueText: data.cueText.present ? data.cueText.value : this.cueText,
      origin: data.origin.present ? data.origin.value : this.origin,
      strength: data.strength.present ? data.strength.value : this.strength,
      successCount: data.successCount.present
          ? data.successCount.value
          : this.successCount,
      failureCount: data.failureCount.present
          ? data.failureCount.value
          : this.failureCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssociationRow(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('associationId: $associationId, ')
          ..write('wordKey: $wordKey, ')
          ..write('cueType: $cueType, ')
          ..write('cueText: $cueText, ')
          ..write('origin: $origin, ')
          ..write('strength: $strength, ')
          ..write('successCount: $successCount, ')
          ..write('failureCount: $failureCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    associationId,
    wordKey,
    cueType,
    cueText,
    origin,
    strength,
    successCount,
    failureCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssociationRow &&
          other.ownerId == this.ownerId &&
          other.schemaVersion == this.schemaVersion &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc &&
          other.associationId == this.associationId &&
          other.wordKey == this.wordKey &&
          other.cueType == this.cueType &&
          other.cueText == this.cueText &&
          other.origin == this.origin &&
          other.strength == this.strength &&
          other.successCount == this.successCount &&
          other.failureCount == this.failureCount);
}

class AssociationsCompanion extends UpdateCompanion<AssociationRow> {
  final Value<String> ownerId;
  final Value<int> schemaVersion;
  final Value<int> createdAtUtc;
  final Value<int> updatedAtUtc;
  final Value<String> associationId;
  final Value<String> wordKey;
  final Value<String> cueType;
  final Value<String> cueText;
  final Value<String> origin;
  final Value<double> strength;
  final Value<int> successCount;
  final Value<int> failureCount;
  final Value<int> rowid;
  const AssociationsCompanion({
    this.ownerId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.associationId = const Value.absent(),
    this.wordKey = const Value.absent(),
    this.cueType = const Value.absent(),
    this.cueText = const Value.absent(),
    this.origin = const Value.absent(),
    this.strength = const Value.absent(),
    this.successCount = const Value.absent(),
    this.failureCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssociationsCompanion.insert({
    required String ownerId,
    this.schemaVersion = const Value.absent(),
    required int createdAtUtc,
    required int updatedAtUtc,
    required String associationId,
    required String wordKey,
    required String cueType,
    required String cueText,
    required String origin,
    required double strength,
    required int successCount,
    required int failureCount,
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc),
       associationId = Value(associationId),
       wordKey = Value(wordKey),
       cueType = Value(cueType),
       cueText = Value(cueText),
       origin = Value(origin),
       strength = Value(strength),
       successCount = Value(successCount),
       failureCount = Value(failureCount);
  static Insertable<AssociationRow> custom({
    Expression<String>? ownerId,
    Expression<int>? schemaVersion,
    Expression<int>? createdAtUtc,
    Expression<int>? updatedAtUtc,
    Expression<String>? associationId,
    Expression<String>? wordKey,
    Expression<String>? cueType,
    Expression<String>? cueText,
    Expression<String>? origin,
    Expression<double>? strength,
    Expression<int>? successCount,
    Expression<int>? failureCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (associationId != null) 'association_id': associationId,
      if (wordKey != null) 'word_key': wordKey,
      if (cueType != null) 'cue_type': cueType,
      if (cueText != null) 'cue_text': cueText,
      if (origin != null) 'origin': origin,
      if (strength != null) 'strength': strength,
      if (successCount != null) 'success_count': successCount,
      if (failureCount != null) 'failure_count': failureCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssociationsCompanion copyWith({
    Value<String>? ownerId,
    Value<int>? schemaVersion,
    Value<int>? createdAtUtc,
    Value<int>? updatedAtUtc,
    Value<String>? associationId,
    Value<String>? wordKey,
    Value<String>? cueType,
    Value<String>? cueText,
    Value<String>? origin,
    Value<double>? strength,
    Value<int>? successCount,
    Value<int>? failureCount,
    Value<int>? rowid,
  }) {
    return AssociationsCompanion(
      ownerId: ownerId ?? this.ownerId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      associationId: associationId ?? this.associationId,
      wordKey: wordKey ?? this.wordKey,
      cueType: cueType ?? this.cueType,
      cueText: cueText ?? this.cueText,
      origin: origin ?? this.origin,
      strength: strength ?? this.strength,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<int>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<int>(updatedAtUtc.value);
    }
    if (associationId.present) {
      map['association_id'] = Variable<String>(associationId.value);
    }
    if (wordKey.present) {
      map['word_key'] = Variable<String>(wordKey.value);
    }
    if (cueType.present) {
      map['cue_type'] = Variable<String>(cueType.value);
    }
    if (cueText.present) {
      map['cue_text'] = Variable<String>(cueText.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (strength.present) {
      map['strength'] = Variable<double>(strength.value);
    }
    if (successCount.present) {
      map['success_count'] = Variable<int>(successCount.value);
    }
    if (failureCount.present) {
      map['failure_count'] = Variable<int>(failureCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssociationsCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('associationId: $associationId, ')
          ..write('wordKey: $wordKey, ')
          ..write('cueType: $cueType, ')
          ..write('cueText: $cueText, ')
          ..write('origin: $origin, ')
          ..write('strength: $strength, ')
          ..write('successCount: $successCount, ')
          ..write('failureCount: $failureCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadingSessionsTable extends ReadingSessions
    with TableInfo<$ReadingSessionsTable, ReadingSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(1),
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<int> createdAtUtc = GeneratedColumn<int>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtc = GeneratedColumn<int>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
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
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 2,
      maxTextLength: 2,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetWordKeysJsonMeta =
      const VerificationMeta('targetWordKeysJson');
  @override
  late final GeneratedColumn<String> targetWordKeysJson =
      GeneratedColumn<String>(
        'target_word_keys_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _mixPolicyVersionMeta = const VerificationMeta(
    'mixPolicyVersion',
  );
  @override
  late final GeneratedColumn<String> mixPolicyVersion = GeneratedColumn<String>(
    'mix_policy_version',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentIdMeta = const VerificationMeta(
    'contentId',
  );
  @override
  late final GeneratedColumn<String> contentId = GeneratedColumn<String>(
    'content_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentVersionMeta = const VerificationMeta(
    'contentVersion',
  );
  @override
  late final GeneratedColumn<String> contentVersion = GeneratedColumn<String>(
    'content_version',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentStageMeta = const VerificationMeta(
    'currentStage',
  );
  @override
  late final GeneratedColumn<String> currentStage = GeneratedColumn<String>(
    'current_stage',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtUtcMeta = const VerificationMeta(
    'startedAtUtc',
  );
  @override
  late final GeneratedColumn<int> startedAtUtc = GeneratedColumn<int>(
    'started_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtUtcMeta = const VerificationMeta(
    'completedAtUtc',
  );
  @override
  late final GeneratedColumn<int> completedAtUtc = GeneratedColumn<int>(
    'completed_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _abandonedAtUtcMeta = const VerificationMeta(
    'abandonedAtUtc',
  );
  @override
  late final GeneratedColumn<int> abandonedAtUtc = GeneratedColumn<int>(
    'abandoned_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    sessionId,
    cefrLevel,
    targetWordKeysJson,
    mixPolicyVersion,
    contentId,
    contentVersion,
    currentStage,
    startedAtUtc,
    completedAtUtc,
    abandonedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('cefr_level')) {
      context.handle(
        _cefrLevelMeta,
        cefrLevel.isAcceptableOrUnknown(data['cefr_level']!, _cefrLevelMeta),
      );
    } else if (isInserting) {
      context.missing(_cefrLevelMeta);
    }
    if (data.containsKey('target_word_keys_json')) {
      context.handle(
        _targetWordKeysJsonMeta,
        targetWordKeysJson.isAcceptableOrUnknown(
          data['target_word_keys_json']!,
          _targetWordKeysJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetWordKeysJsonMeta);
    }
    if (data.containsKey('mix_policy_version')) {
      context.handle(
        _mixPolicyVersionMeta,
        mixPolicyVersion.isAcceptableOrUnknown(
          data['mix_policy_version']!,
          _mixPolicyVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mixPolicyVersionMeta);
    }
    if (data.containsKey('content_id')) {
      context.handle(
        _contentIdMeta,
        contentId.isAcceptableOrUnknown(data['content_id']!, _contentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_contentIdMeta);
    }
    if (data.containsKey('content_version')) {
      context.handle(
        _contentVersionMeta,
        contentVersion.isAcceptableOrUnknown(
          data['content_version']!,
          _contentVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentVersionMeta);
    }
    if (data.containsKey('current_stage')) {
      context.handle(
        _currentStageMeta,
        currentStage.isAcceptableOrUnknown(
          data['current_stage']!,
          _currentStageMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentStageMeta);
    }
    if (data.containsKey('started_at_utc')) {
      context.handle(
        _startedAtUtcMeta,
        startedAtUtc.isAcceptableOrUnknown(
          data['started_at_utc']!,
          _startedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startedAtUtcMeta);
    }
    if (data.containsKey('completed_at_utc')) {
      context.handle(
        _completedAtUtcMeta,
        completedAtUtc.isAcceptableOrUnknown(
          data['completed_at_utc']!,
          _completedAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('abandoned_at_utc')) {
      context.handle(
        _abandonedAtUtcMeta,
        abandonedAtUtc.isAcceptableOrUnknown(
          data['abandoned_at_utc']!,
          _abandonedAtUtcMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, sessionId};
  @override
  ReadingSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingSessionRow(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      cefrLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cefr_level'],
      )!,
      targetWordKeysJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_word_keys_json'],
      )!,
      mixPolicyVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mix_policy_version'],
      )!,
      contentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_id'],
      )!,
      contentVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_version'],
      )!,
      currentStage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_stage'],
      )!,
      startedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at_utc'],
      )!,
      completedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at_utc'],
      ),
      abandonedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}abandoned_at_utc'],
      ),
    );
  }

  @override
  $ReadingSessionsTable createAlias(String alias) {
    return $ReadingSessionsTable(attachedDatabase, alias);
  }
}

class ReadingSessionRow extends DataClass
    implements Insertable<ReadingSessionRow> {
  final String ownerId;
  final int schemaVersion;
  final int createdAtUtc;
  final int updatedAtUtc;
  final String sessionId;
  final String cefrLevel;
  final String targetWordKeysJson;
  final String mixPolicyVersion;
  final String contentId;
  final String contentVersion;
  final String currentStage;
  final int startedAtUtc;
  final int? completedAtUtc;
  final int? abandonedAtUtc;
  const ReadingSessionRow({
    required this.ownerId,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.sessionId,
    required this.cefrLevel,
    required this.targetWordKeysJson,
    required this.mixPolicyVersion,
    required this.contentId,
    required this.contentVersion,
    required this.currentStage,
    required this.startedAtUtc,
    this.completedAtUtc,
    this.abandonedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['created_at_utc'] = Variable<int>(createdAtUtc);
    map['updated_at_utc'] = Variable<int>(updatedAtUtc);
    map['session_id'] = Variable<String>(sessionId);
    map['cefr_level'] = Variable<String>(cefrLevel);
    map['target_word_keys_json'] = Variable<String>(targetWordKeysJson);
    map['mix_policy_version'] = Variable<String>(mixPolicyVersion);
    map['content_id'] = Variable<String>(contentId);
    map['content_version'] = Variable<String>(contentVersion);
    map['current_stage'] = Variable<String>(currentStage);
    map['started_at_utc'] = Variable<int>(startedAtUtc);
    if (!nullToAbsent || completedAtUtc != null) {
      map['completed_at_utc'] = Variable<int>(completedAtUtc);
    }
    if (!nullToAbsent || abandonedAtUtc != null) {
      map['abandoned_at_utc'] = Variable<int>(abandonedAtUtc);
    }
    return map;
  }

  ReadingSessionsCompanion toCompanion(bool nullToAbsent) {
    return ReadingSessionsCompanion(
      ownerId: Value(ownerId),
      schemaVersion: Value(schemaVersion),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
      sessionId: Value(sessionId),
      cefrLevel: Value(cefrLevel),
      targetWordKeysJson: Value(targetWordKeysJson),
      mixPolicyVersion: Value(mixPolicyVersion),
      contentId: Value(contentId),
      contentVersion: Value(contentVersion),
      currentStage: Value(currentStage),
      startedAtUtc: Value(startedAtUtc),
      completedAtUtc: completedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtUtc),
      abandonedAtUtc: abandonedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(abandonedAtUtc),
    );
  }

  factory ReadingSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingSessionRow(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      createdAtUtc: serializer.fromJson<int>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<int>(json['updatedAtUtc']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      cefrLevel: serializer.fromJson<String>(json['cefrLevel']),
      targetWordKeysJson: serializer.fromJson<String>(
        json['targetWordKeysJson'],
      ),
      mixPolicyVersion: serializer.fromJson<String>(json['mixPolicyVersion']),
      contentId: serializer.fromJson<String>(json['contentId']),
      contentVersion: serializer.fromJson<String>(json['contentVersion']),
      currentStage: serializer.fromJson<String>(json['currentStage']),
      startedAtUtc: serializer.fromJson<int>(json['startedAtUtc']),
      completedAtUtc: serializer.fromJson<int?>(json['completedAtUtc']),
      abandonedAtUtc: serializer.fromJson<int?>(json['abandonedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'createdAtUtc': serializer.toJson<int>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<int>(updatedAtUtc),
      'sessionId': serializer.toJson<String>(sessionId),
      'cefrLevel': serializer.toJson<String>(cefrLevel),
      'targetWordKeysJson': serializer.toJson<String>(targetWordKeysJson),
      'mixPolicyVersion': serializer.toJson<String>(mixPolicyVersion),
      'contentId': serializer.toJson<String>(contentId),
      'contentVersion': serializer.toJson<String>(contentVersion),
      'currentStage': serializer.toJson<String>(currentStage),
      'startedAtUtc': serializer.toJson<int>(startedAtUtc),
      'completedAtUtc': serializer.toJson<int?>(completedAtUtc),
      'abandonedAtUtc': serializer.toJson<int?>(abandonedAtUtc),
    };
  }

  ReadingSessionRow copyWith({
    String? ownerId,
    int? schemaVersion,
    int? createdAtUtc,
    int? updatedAtUtc,
    String? sessionId,
    String? cefrLevel,
    String? targetWordKeysJson,
    String? mixPolicyVersion,
    String? contentId,
    String? contentVersion,
    String? currentStage,
    int? startedAtUtc,
    Value<int?> completedAtUtc = const Value.absent(),
    Value<int?> abandonedAtUtc = const Value.absent(),
  }) => ReadingSessionRow(
    ownerId: ownerId ?? this.ownerId,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    sessionId: sessionId ?? this.sessionId,
    cefrLevel: cefrLevel ?? this.cefrLevel,
    targetWordKeysJson: targetWordKeysJson ?? this.targetWordKeysJson,
    mixPolicyVersion: mixPolicyVersion ?? this.mixPolicyVersion,
    contentId: contentId ?? this.contentId,
    contentVersion: contentVersion ?? this.contentVersion,
    currentStage: currentStage ?? this.currentStage,
    startedAtUtc: startedAtUtc ?? this.startedAtUtc,
    completedAtUtc: completedAtUtc.present
        ? completedAtUtc.value
        : this.completedAtUtc,
    abandonedAtUtc: abandonedAtUtc.present
        ? abandonedAtUtc.value
        : this.abandonedAtUtc,
  );
  ReadingSessionRow copyWithCompanion(ReadingSessionsCompanion data) {
    return ReadingSessionRow(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      cefrLevel: data.cefrLevel.present ? data.cefrLevel.value : this.cefrLevel,
      targetWordKeysJson: data.targetWordKeysJson.present
          ? data.targetWordKeysJson.value
          : this.targetWordKeysJson,
      mixPolicyVersion: data.mixPolicyVersion.present
          ? data.mixPolicyVersion.value
          : this.mixPolicyVersion,
      contentId: data.contentId.present ? data.contentId.value : this.contentId,
      contentVersion: data.contentVersion.present
          ? data.contentVersion.value
          : this.contentVersion,
      currentStage: data.currentStage.present
          ? data.currentStage.value
          : this.currentStage,
      startedAtUtc: data.startedAtUtc.present
          ? data.startedAtUtc.value
          : this.startedAtUtc,
      completedAtUtc: data.completedAtUtc.present
          ? data.completedAtUtc.value
          : this.completedAtUtc,
      abandonedAtUtc: data.abandonedAtUtc.present
          ? data.abandonedAtUtc.value
          : this.abandonedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingSessionRow(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('sessionId: $sessionId, ')
          ..write('cefrLevel: $cefrLevel, ')
          ..write('targetWordKeysJson: $targetWordKeysJson, ')
          ..write('mixPolicyVersion: $mixPolicyVersion, ')
          ..write('contentId: $contentId, ')
          ..write('contentVersion: $contentVersion, ')
          ..write('currentStage: $currentStage, ')
          ..write('startedAtUtc: $startedAtUtc, ')
          ..write('completedAtUtc: $completedAtUtc, ')
          ..write('abandonedAtUtc: $abandonedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    sessionId,
    cefrLevel,
    targetWordKeysJson,
    mixPolicyVersion,
    contentId,
    contentVersion,
    currentStage,
    startedAtUtc,
    completedAtUtc,
    abandonedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingSessionRow &&
          other.ownerId == this.ownerId &&
          other.schemaVersion == this.schemaVersion &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc &&
          other.sessionId == this.sessionId &&
          other.cefrLevel == this.cefrLevel &&
          other.targetWordKeysJson == this.targetWordKeysJson &&
          other.mixPolicyVersion == this.mixPolicyVersion &&
          other.contentId == this.contentId &&
          other.contentVersion == this.contentVersion &&
          other.currentStage == this.currentStage &&
          other.startedAtUtc == this.startedAtUtc &&
          other.completedAtUtc == this.completedAtUtc &&
          other.abandonedAtUtc == this.abandonedAtUtc);
}

class ReadingSessionsCompanion extends UpdateCompanion<ReadingSessionRow> {
  final Value<String> ownerId;
  final Value<int> schemaVersion;
  final Value<int> createdAtUtc;
  final Value<int> updatedAtUtc;
  final Value<String> sessionId;
  final Value<String> cefrLevel;
  final Value<String> targetWordKeysJson;
  final Value<String> mixPolicyVersion;
  final Value<String> contentId;
  final Value<String> contentVersion;
  final Value<String> currentStage;
  final Value<int> startedAtUtc;
  final Value<int?> completedAtUtc;
  final Value<int?> abandonedAtUtc;
  final Value<int> rowid;
  const ReadingSessionsCompanion({
    this.ownerId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.cefrLevel = const Value.absent(),
    this.targetWordKeysJson = const Value.absent(),
    this.mixPolicyVersion = const Value.absent(),
    this.contentId = const Value.absent(),
    this.contentVersion = const Value.absent(),
    this.currentStage = const Value.absent(),
    this.startedAtUtc = const Value.absent(),
    this.completedAtUtc = const Value.absent(),
    this.abandonedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingSessionsCompanion.insert({
    required String ownerId,
    this.schemaVersion = const Value.absent(),
    required int createdAtUtc,
    required int updatedAtUtc,
    required String sessionId,
    required String cefrLevel,
    required String targetWordKeysJson,
    required String mixPolicyVersion,
    required String contentId,
    required String contentVersion,
    required String currentStage,
    required int startedAtUtc,
    this.completedAtUtc = const Value.absent(),
    this.abandonedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc),
       sessionId = Value(sessionId),
       cefrLevel = Value(cefrLevel),
       targetWordKeysJson = Value(targetWordKeysJson),
       mixPolicyVersion = Value(mixPolicyVersion),
       contentId = Value(contentId),
       contentVersion = Value(contentVersion),
       currentStage = Value(currentStage),
       startedAtUtc = Value(startedAtUtc);
  static Insertable<ReadingSessionRow> custom({
    Expression<String>? ownerId,
    Expression<int>? schemaVersion,
    Expression<int>? createdAtUtc,
    Expression<int>? updatedAtUtc,
    Expression<String>? sessionId,
    Expression<String>? cefrLevel,
    Expression<String>? targetWordKeysJson,
    Expression<String>? mixPolicyVersion,
    Expression<String>? contentId,
    Expression<String>? contentVersion,
    Expression<String>? currentStage,
    Expression<int>? startedAtUtc,
    Expression<int>? completedAtUtc,
    Expression<int>? abandonedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (sessionId != null) 'session_id': sessionId,
      if (cefrLevel != null) 'cefr_level': cefrLevel,
      if (targetWordKeysJson != null)
        'target_word_keys_json': targetWordKeysJson,
      if (mixPolicyVersion != null) 'mix_policy_version': mixPolicyVersion,
      if (contentId != null) 'content_id': contentId,
      if (contentVersion != null) 'content_version': contentVersion,
      if (currentStage != null) 'current_stage': currentStage,
      if (startedAtUtc != null) 'started_at_utc': startedAtUtc,
      if (completedAtUtc != null) 'completed_at_utc': completedAtUtc,
      if (abandonedAtUtc != null) 'abandoned_at_utc': abandonedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingSessionsCompanion copyWith({
    Value<String>? ownerId,
    Value<int>? schemaVersion,
    Value<int>? createdAtUtc,
    Value<int>? updatedAtUtc,
    Value<String>? sessionId,
    Value<String>? cefrLevel,
    Value<String>? targetWordKeysJson,
    Value<String>? mixPolicyVersion,
    Value<String>? contentId,
    Value<String>? contentVersion,
    Value<String>? currentStage,
    Value<int>? startedAtUtc,
    Value<int?>? completedAtUtc,
    Value<int?>? abandonedAtUtc,
    Value<int>? rowid,
  }) {
    return ReadingSessionsCompanion(
      ownerId: ownerId ?? this.ownerId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      sessionId: sessionId ?? this.sessionId,
      cefrLevel: cefrLevel ?? this.cefrLevel,
      targetWordKeysJson: targetWordKeysJson ?? this.targetWordKeysJson,
      mixPolicyVersion: mixPolicyVersion ?? this.mixPolicyVersion,
      contentId: contentId ?? this.contentId,
      contentVersion: contentVersion ?? this.contentVersion,
      currentStage: currentStage ?? this.currentStage,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      completedAtUtc: completedAtUtc ?? this.completedAtUtc,
      abandonedAtUtc: abandonedAtUtc ?? this.abandonedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<int>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<int>(updatedAtUtc.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (cefrLevel.present) {
      map['cefr_level'] = Variable<String>(cefrLevel.value);
    }
    if (targetWordKeysJson.present) {
      map['target_word_keys_json'] = Variable<String>(targetWordKeysJson.value);
    }
    if (mixPolicyVersion.present) {
      map['mix_policy_version'] = Variable<String>(mixPolicyVersion.value);
    }
    if (contentId.present) {
      map['content_id'] = Variable<String>(contentId.value);
    }
    if (contentVersion.present) {
      map['content_version'] = Variable<String>(contentVersion.value);
    }
    if (currentStage.present) {
      map['current_stage'] = Variable<String>(currentStage.value);
    }
    if (startedAtUtc.present) {
      map['started_at_utc'] = Variable<int>(startedAtUtc.value);
    }
    if (completedAtUtc.present) {
      map['completed_at_utc'] = Variable<int>(completedAtUtc.value);
    }
    if (abandonedAtUtc.present) {
      map['abandoned_at_utc'] = Variable<int>(abandonedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingSessionsCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('sessionId: $sessionId, ')
          ..write('cefrLevel: $cefrLevel, ')
          ..write('targetWordKeysJson: $targetWordKeysJson, ')
          ..write('mixPolicyVersion: $mixPolicyVersion, ')
          ..write('contentId: $contentId, ')
          ..write('contentVersion: $contentVersion, ')
          ..write('currentStage: $currentStage, ')
          ..write('startedAtUtc: $startedAtUtc, ')
          ..write('completedAtUtc: $completedAtUtc, ')
          ..write('abandonedAtUtc: $abandonedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecallAttemptsTable extends RecallAttempts
    with TableInfo<$RecallAttemptsTable, RecallAttemptRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecallAttemptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(1),
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<int> createdAtUtc = GeneratedColumn<int>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtc = GeneratedColumn<int>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptIdMeta = const VerificationMeta(
    'attemptId',
  );
  @override
  late final GeneratedColumn<String> attemptId = GeneratedColumn<String>(
    'attempt_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wordKeyMeta = const VerificationMeta(
    'wordKey',
  );
  @override
  late final GeneratedColumn<String> wordKey = GeneratedColumn<String>(
    'word_key',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recallModeMeta = const VerificationMeta(
    'recallMode',
  );
  @override
  late final GeneratedColumn<String> recallMode = GeneratedColumn<String>(
    'recall_mode',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cueLevelMeta = const VerificationMeta(
    'cueLevel',
  );
  @override
  late final GeneratedColumn<String> cueLevel = GeneratedColumn<String>(
    'cue_level',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _correctnessMeta = const VerificationMeta(
    'correctness',
  );
  @override
  late final GeneratedColumn<bool> correctness = GeneratedColumn<bool>(
    'correctness',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("correctness" IN (0, 1))',
    ),
  );
  static const VerificationMeta _responseTimeMsMeta = const VerificationMeta(
    'responseTimeMs',
  );
  @override
  late final GeneratedColumn<int> responseTimeMs = GeneratedColumn<int>(
    'response_time_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<int> confidence = GeneratedColumn<int>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contextIdMeta = const VerificationMeta(
    'contextId',
  );
  @override
  late final GeneratedColumn<String> contextId = GeneratedColumn<String>(
    'context_id',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _algorithmVersionMeta = const VerificationMeta(
    'algorithmVersion',
  );
  @override
  late final GeneratedColumn<String> algorithmVersion = GeneratedColumn<String>(
    'algorithm_version',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtUtcMeta = const VerificationMeta(
    'occurredAtUtc',
  );
  @override
  late final GeneratedColumn<int> occurredAtUtc = GeneratedColumn<int>(
    'occurred_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    attemptId,
    sessionId,
    wordKey,
    recallMode,
    cueLevel,
    correctness,
    responseTimeMs,
    confidence,
    contextId,
    algorithmVersion,
    occurredAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recall_attempts';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecallAttemptRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    if (data.containsKey('attempt_id')) {
      context.handle(
        _attemptIdMeta,
        attemptId.isAcceptableOrUnknown(data['attempt_id']!, _attemptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_attemptIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('word_key')) {
      context.handle(
        _wordKeyMeta,
        wordKey.isAcceptableOrUnknown(data['word_key']!, _wordKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_wordKeyMeta);
    }
    if (data.containsKey('recall_mode')) {
      context.handle(
        _recallModeMeta,
        recallMode.isAcceptableOrUnknown(data['recall_mode']!, _recallModeMeta),
      );
    } else if (isInserting) {
      context.missing(_recallModeMeta);
    }
    if (data.containsKey('cue_level')) {
      context.handle(
        _cueLevelMeta,
        cueLevel.isAcceptableOrUnknown(data['cue_level']!, _cueLevelMeta),
      );
    } else if (isInserting) {
      context.missing(_cueLevelMeta);
    }
    if (data.containsKey('correctness')) {
      context.handle(
        _correctnessMeta,
        correctness.isAcceptableOrUnknown(
          data['correctness']!,
          _correctnessMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_correctnessMeta);
    }
    if (data.containsKey('response_time_ms')) {
      context.handle(
        _responseTimeMsMeta,
        responseTimeMs.isAcceptableOrUnknown(
          data['response_time_ms']!,
          _responseTimeMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_responseTimeMsMeta);
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    } else if (isInserting) {
      context.missing(_confidenceMeta);
    }
    if (data.containsKey('context_id')) {
      context.handle(
        _contextIdMeta,
        contextId.isAcceptableOrUnknown(data['context_id']!, _contextIdMeta),
      );
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
    if (data.containsKey('occurred_at_utc')) {
      context.handle(
        _occurredAtUtcMeta,
        occurredAtUtc.isAcceptableOrUnknown(
          data['occurred_at_utc']!,
          _occurredAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, attemptId};
  @override
  RecallAttemptRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecallAttemptRow(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc'],
      )!,
      attemptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attempt_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      wordKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}word_key'],
      )!,
      recallMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recall_mode'],
      )!,
      cueLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cue_level'],
      )!,
      correctness: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}correctness'],
      )!,
      responseTimeMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}response_time_ms'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confidence'],
      )!,
      contextId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context_id'],
      ),
      algorithmVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}algorithm_version'],
      )!,
      occurredAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurred_at_utc'],
      )!,
    );
  }

  @override
  $RecallAttemptsTable createAlias(String alias) {
    return $RecallAttemptsTable(attachedDatabase, alias);
  }
}

class RecallAttemptRow extends DataClass
    implements Insertable<RecallAttemptRow> {
  final String ownerId;
  final int schemaVersion;
  final int createdAtUtc;
  final int updatedAtUtc;
  final String attemptId;
  final String sessionId;
  final String wordKey;
  final String recallMode;
  final String cueLevel;
  final bool correctness;
  final int responseTimeMs;
  final int confidence;
  final String? contextId;
  final String algorithmVersion;
  final int occurredAtUtc;
  const RecallAttemptRow({
    required this.ownerId,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.attemptId,
    required this.sessionId,
    required this.wordKey,
    required this.recallMode,
    required this.cueLevel,
    required this.correctness,
    required this.responseTimeMs,
    required this.confidence,
    this.contextId,
    required this.algorithmVersion,
    required this.occurredAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['created_at_utc'] = Variable<int>(createdAtUtc);
    map['updated_at_utc'] = Variable<int>(updatedAtUtc);
    map['attempt_id'] = Variable<String>(attemptId);
    map['session_id'] = Variable<String>(sessionId);
    map['word_key'] = Variable<String>(wordKey);
    map['recall_mode'] = Variable<String>(recallMode);
    map['cue_level'] = Variable<String>(cueLevel);
    map['correctness'] = Variable<bool>(correctness);
    map['response_time_ms'] = Variable<int>(responseTimeMs);
    map['confidence'] = Variable<int>(confidence);
    if (!nullToAbsent || contextId != null) {
      map['context_id'] = Variable<String>(contextId);
    }
    map['algorithm_version'] = Variable<String>(algorithmVersion);
    map['occurred_at_utc'] = Variable<int>(occurredAtUtc);
    return map;
  }

  RecallAttemptsCompanion toCompanion(bool nullToAbsent) {
    return RecallAttemptsCompanion(
      ownerId: Value(ownerId),
      schemaVersion: Value(schemaVersion),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
      attemptId: Value(attemptId),
      sessionId: Value(sessionId),
      wordKey: Value(wordKey),
      recallMode: Value(recallMode),
      cueLevel: Value(cueLevel),
      correctness: Value(correctness),
      responseTimeMs: Value(responseTimeMs),
      confidence: Value(confidence),
      contextId: contextId == null && nullToAbsent
          ? const Value.absent()
          : Value(contextId),
      algorithmVersion: Value(algorithmVersion),
      occurredAtUtc: Value(occurredAtUtc),
    );
  }

  factory RecallAttemptRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecallAttemptRow(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      createdAtUtc: serializer.fromJson<int>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<int>(json['updatedAtUtc']),
      attemptId: serializer.fromJson<String>(json['attemptId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      wordKey: serializer.fromJson<String>(json['wordKey']),
      recallMode: serializer.fromJson<String>(json['recallMode']),
      cueLevel: serializer.fromJson<String>(json['cueLevel']),
      correctness: serializer.fromJson<bool>(json['correctness']),
      responseTimeMs: serializer.fromJson<int>(json['responseTimeMs']),
      confidence: serializer.fromJson<int>(json['confidence']),
      contextId: serializer.fromJson<String?>(json['contextId']),
      algorithmVersion: serializer.fromJson<String>(json['algorithmVersion']),
      occurredAtUtc: serializer.fromJson<int>(json['occurredAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'createdAtUtc': serializer.toJson<int>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<int>(updatedAtUtc),
      'attemptId': serializer.toJson<String>(attemptId),
      'sessionId': serializer.toJson<String>(sessionId),
      'wordKey': serializer.toJson<String>(wordKey),
      'recallMode': serializer.toJson<String>(recallMode),
      'cueLevel': serializer.toJson<String>(cueLevel),
      'correctness': serializer.toJson<bool>(correctness),
      'responseTimeMs': serializer.toJson<int>(responseTimeMs),
      'confidence': serializer.toJson<int>(confidence),
      'contextId': serializer.toJson<String?>(contextId),
      'algorithmVersion': serializer.toJson<String>(algorithmVersion),
      'occurredAtUtc': serializer.toJson<int>(occurredAtUtc),
    };
  }

  RecallAttemptRow copyWith({
    String? ownerId,
    int? schemaVersion,
    int? createdAtUtc,
    int? updatedAtUtc,
    String? attemptId,
    String? sessionId,
    String? wordKey,
    String? recallMode,
    String? cueLevel,
    bool? correctness,
    int? responseTimeMs,
    int? confidence,
    Value<String?> contextId = const Value.absent(),
    String? algorithmVersion,
    int? occurredAtUtc,
  }) => RecallAttemptRow(
    ownerId: ownerId ?? this.ownerId,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    attemptId: attemptId ?? this.attemptId,
    sessionId: sessionId ?? this.sessionId,
    wordKey: wordKey ?? this.wordKey,
    recallMode: recallMode ?? this.recallMode,
    cueLevel: cueLevel ?? this.cueLevel,
    correctness: correctness ?? this.correctness,
    responseTimeMs: responseTimeMs ?? this.responseTimeMs,
    confidence: confidence ?? this.confidence,
    contextId: contextId.present ? contextId.value : this.contextId,
    algorithmVersion: algorithmVersion ?? this.algorithmVersion,
    occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
  );
  RecallAttemptRow copyWithCompanion(RecallAttemptsCompanion data) {
    return RecallAttemptRow(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
      attemptId: data.attemptId.present ? data.attemptId.value : this.attemptId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      wordKey: data.wordKey.present ? data.wordKey.value : this.wordKey,
      recallMode: data.recallMode.present
          ? data.recallMode.value
          : this.recallMode,
      cueLevel: data.cueLevel.present ? data.cueLevel.value : this.cueLevel,
      correctness: data.correctness.present
          ? data.correctness.value
          : this.correctness,
      responseTimeMs: data.responseTimeMs.present
          ? data.responseTimeMs.value
          : this.responseTimeMs,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      contextId: data.contextId.present ? data.contextId.value : this.contextId,
      algorithmVersion: data.algorithmVersion.present
          ? data.algorithmVersion.value
          : this.algorithmVersion,
      occurredAtUtc: data.occurredAtUtc.present
          ? data.occurredAtUtc.value
          : this.occurredAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecallAttemptRow(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('attemptId: $attemptId, ')
          ..write('sessionId: $sessionId, ')
          ..write('wordKey: $wordKey, ')
          ..write('recallMode: $recallMode, ')
          ..write('cueLevel: $cueLevel, ')
          ..write('correctness: $correctness, ')
          ..write('responseTimeMs: $responseTimeMs, ')
          ..write('confidence: $confidence, ')
          ..write('contextId: $contextId, ')
          ..write('algorithmVersion: $algorithmVersion, ')
          ..write('occurredAtUtc: $occurredAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    attemptId,
    sessionId,
    wordKey,
    recallMode,
    cueLevel,
    correctness,
    responseTimeMs,
    confidence,
    contextId,
    algorithmVersion,
    occurredAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecallAttemptRow &&
          other.ownerId == this.ownerId &&
          other.schemaVersion == this.schemaVersion &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc &&
          other.attemptId == this.attemptId &&
          other.sessionId == this.sessionId &&
          other.wordKey == this.wordKey &&
          other.recallMode == this.recallMode &&
          other.cueLevel == this.cueLevel &&
          other.correctness == this.correctness &&
          other.responseTimeMs == this.responseTimeMs &&
          other.confidence == this.confidence &&
          other.contextId == this.contextId &&
          other.algorithmVersion == this.algorithmVersion &&
          other.occurredAtUtc == this.occurredAtUtc);
}

class RecallAttemptsCompanion extends UpdateCompanion<RecallAttemptRow> {
  final Value<String> ownerId;
  final Value<int> schemaVersion;
  final Value<int> createdAtUtc;
  final Value<int> updatedAtUtc;
  final Value<String> attemptId;
  final Value<String> sessionId;
  final Value<String> wordKey;
  final Value<String> recallMode;
  final Value<String> cueLevel;
  final Value<bool> correctness;
  final Value<int> responseTimeMs;
  final Value<int> confidence;
  final Value<String?> contextId;
  final Value<String> algorithmVersion;
  final Value<int> occurredAtUtc;
  final Value<int> rowid;
  const RecallAttemptsCompanion({
    this.ownerId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.attemptId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.wordKey = const Value.absent(),
    this.recallMode = const Value.absent(),
    this.cueLevel = const Value.absent(),
    this.correctness = const Value.absent(),
    this.responseTimeMs = const Value.absent(),
    this.confidence = const Value.absent(),
    this.contextId = const Value.absent(),
    this.algorithmVersion = const Value.absent(),
    this.occurredAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecallAttemptsCompanion.insert({
    required String ownerId,
    this.schemaVersion = const Value.absent(),
    required int createdAtUtc,
    required int updatedAtUtc,
    required String attemptId,
    required String sessionId,
    required String wordKey,
    required String recallMode,
    required String cueLevel,
    required bool correctness,
    required int responseTimeMs,
    required int confidence,
    this.contextId = const Value.absent(),
    required String algorithmVersion,
    required int occurredAtUtc,
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc),
       attemptId = Value(attemptId),
       sessionId = Value(sessionId),
       wordKey = Value(wordKey),
       recallMode = Value(recallMode),
       cueLevel = Value(cueLevel),
       correctness = Value(correctness),
       responseTimeMs = Value(responseTimeMs),
       confidence = Value(confidence),
       algorithmVersion = Value(algorithmVersion),
       occurredAtUtc = Value(occurredAtUtc);
  static Insertable<RecallAttemptRow> custom({
    Expression<String>? ownerId,
    Expression<int>? schemaVersion,
    Expression<int>? createdAtUtc,
    Expression<int>? updatedAtUtc,
    Expression<String>? attemptId,
    Expression<String>? sessionId,
    Expression<String>? wordKey,
    Expression<String>? recallMode,
    Expression<String>? cueLevel,
    Expression<bool>? correctness,
    Expression<int>? responseTimeMs,
    Expression<int>? confidence,
    Expression<String>? contextId,
    Expression<String>? algorithmVersion,
    Expression<int>? occurredAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (attemptId != null) 'attempt_id': attemptId,
      if (sessionId != null) 'session_id': sessionId,
      if (wordKey != null) 'word_key': wordKey,
      if (recallMode != null) 'recall_mode': recallMode,
      if (cueLevel != null) 'cue_level': cueLevel,
      if (correctness != null) 'correctness': correctness,
      if (responseTimeMs != null) 'response_time_ms': responseTimeMs,
      if (confidence != null) 'confidence': confidence,
      if (contextId != null) 'context_id': contextId,
      if (algorithmVersion != null) 'algorithm_version': algorithmVersion,
      if (occurredAtUtc != null) 'occurred_at_utc': occurredAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecallAttemptsCompanion copyWith({
    Value<String>? ownerId,
    Value<int>? schemaVersion,
    Value<int>? createdAtUtc,
    Value<int>? updatedAtUtc,
    Value<String>? attemptId,
    Value<String>? sessionId,
    Value<String>? wordKey,
    Value<String>? recallMode,
    Value<String>? cueLevel,
    Value<bool>? correctness,
    Value<int>? responseTimeMs,
    Value<int>? confidence,
    Value<String?>? contextId,
    Value<String>? algorithmVersion,
    Value<int>? occurredAtUtc,
    Value<int>? rowid,
  }) {
    return RecallAttemptsCompanion(
      ownerId: ownerId ?? this.ownerId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      attemptId: attemptId ?? this.attemptId,
      sessionId: sessionId ?? this.sessionId,
      wordKey: wordKey ?? this.wordKey,
      recallMode: recallMode ?? this.recallMode,
      cueLevel: cueLevel ?? this.cueLevel,
      correctness: correctness ?? this.correctness,
      responseTimeMs: responseTimeMs ?? this.responseTimeMs,
      confidence: confidence ?? this.confidence,
      contextId: contextId ?? this.contextId,
      algorithmVersion: algorithmVersion ?? this.algorithmVersion,
      occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<int>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<int>(updatedAtUtc.value);
    }
    if (attemptId.present) {
      map['attempt_id'] = Variable<String>(attemptId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (wordKey.present) {
      map['word_key'] = Variable<String>(wordKey.value);
    }
    if (recallMode.present) {
      map['recall_mode'] = Variable<String>(recallMode.value);
    }
    if (cueLevel.present) {
      map['cue_level'] = Variable<String>(cueLevel.value);
    }
    if (correctness.present) {
      map['correctness'] = Variable<bool>(correctness.value);
    }
    if (responseTimeMs.present) {
      map['response_time_ms'] = Variable<int>(responseTimeMs.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<int>(confidence.value);
    }
    if (contextId.present) {
      map['context_id'] = Variable<String>(contextId.value);
    }
    if (algorithmVersion.present) {
      map['algorithm_version'] = Variable<String>(algorithmVersion.value);
    }
    if (occurredAtUtc.present) {
      map['occurred_at_utc'] = Variable<int>(occurredAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecallAttemptsCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('attemptId: $attemptId, ')
          ..write('sessionId: $sessionId, ')
          ..write('wordKey: $wordKey, ')
          ..write('recallMode: $recallMode, ')
          ..write('cueLevel: $cueLevel, ')
          ..write('correctness: $correctness, ')
          ..write('responseTimeMs: $responseTimeMs, ')
          ..write('confidence: $confidence, ')
          ..write('contextId: $contextId, ')
          ..write('algorithmVersion: $algorithmVersion, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MemoryStatesTable extends MemoryStates
    with TableInfo<$MemoryStatesTable, MemoryStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemoryStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(1),
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<int> createdAtUtc = GeneratedColumn<int>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtc = GeneratedColumn<int>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wordKeyMeta = const VerificationMeta(
    'wordKey',
  );
  @override
  late final GeneratedColumn<String> wordKey = GeneratedColumn<String>(
    'word_key',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _strengthMeta = const VerificationMeta(
    'strength',
  );
  @override
  late final GeneratedColumn<double> strength = GeneratedColumn<double>(
    'strength',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cueDependencyMeta = const VerificationMeta(
    'cueDependency',
  );
  @override
  late final GeneratedColumn<double> cueDependency = GeneratedColumn<double>(
    'cue_dependency',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lapseCountMeta = const VerificationMeta(
    'lapseCount',
  );
  @override
  late final GeneratedColumn<int> lapseCount = GeneratedColumn<int>(
    'lapse_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastReviewedAtUtcMeta = const VerificationMeta(
    'lastReviewedAtUtc',
  );
  @override
  late final GeneratedColumn<int> lastReviewedAtUtc = GeneratedColumn<int>(
    'last_reviewed_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextDueAtUtcMeta = const VerificationMeta(
    'nextDueAtUtc',
  );
  @override
  late final GeneratedColumn<int> nextDueAtUtc = GeneratedColumn<int>(
    'next_due_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastErrorTypeMeta = const VerificationMeta(
    'lastErrorType',
  );
  @override
  late final GeneratedColumn<String> lastErrorType = GeneratedColumn<String>(
    'last_error_type',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _algorithmVersionMeta = const VerificationMeta(
    'algorithmVersion',
  );
  @override
  late final GeneratedColumn<String> algorithmVersion = GeneratedColumn<String>(
    'algorithm_version',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    wordKey,
    strength,
    cueDependency,
    stability,
    difficulty,
    lapseCount,
    lastReviewedAtUtc,
    nextDueAtUtc,
    lastErrorType,
    algorithmVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memory_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<MemoryStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    if (data.containsKey('word_key')) {
      context.handle(
        _wordKeyMeta,
        wordKey.isAcceptableOrUnknown(data['word_key']!, _wordKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_wordKeyMeta);
    }
    if (data.containsKey('strength')) {
      context.handle(
        _strengthMeta,
        strength.isAcceptableOrUnknown(data['strength']!, _strengthMeta),
      );
    } else if (isInserting) {
      context.missing(_strengthMeta);
    }
    if (data.containsKey('cue_dependency')) {
      context.handle(
        _cueDependencyMeta,
        cueDependency.isAcceptableOrUnknown(
          data['cue_dependency']!,
          _cueDependencyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cueDependencyMeta);
    }
    if (data.containsKey('stability')) {
      context.handle(
        _stabilityMeta,
        stability.isAcceptableOrUnknown(data['stability']!, _stabilityMeta),
      );
    } else if (isInserting) {
      context.missing(_stabilityMeta);
    }
    if (data.containsKey('difficulty')) {
      context.handle(
        _difficultyMeta,
        difficulty.isAcceptableOrUnknown(data['difficulty']!, _difficultyMeta),
      );
    } else if (isInserting) {
      context.missing(_difficultyMeta);
    }
    if (data.containsKey('lapse_count')) {
      context.handle(
        _lapseCountMeta,
        lapseCount.isAcceptableOrUnknown(data['lapse_count']!, _lapseCountMeta),
      );
    } else if (isInserting) {
      context.missing(_lapseCountMeta);
    }
    if (data.containsKey('last_reviewed_at_utc')) {
      context.handle(
        _lastReviewedAtUtcMeta,
        lastReviewedAtUtc.isAcceptableOrUnknown(
          data['last_reviewed_at_utc']!,
          _lastReviewedAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('next_due_at_utc')) {
      context.handle(
        _nextDueAtUtcMeta,
        nextDueAtUtc.isAcceptableOrUnknown(
          data['next_due_at_utc']!,
          _nextDueAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextDueAtUtcMeta);
    }
    if (data.containsKey('last_error_type')) {
      context.handle(
        _lastErrorTypeMeta,
        lastErrorType.isAcceptableOrUnknown(
          data['last_error_type']!,
          _lastErrorTypeMeta,
        ),
      );
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
  Set<GeneratedColumn> get $primaryKey => {ownerId, wordKey};
  @override
  MemoryStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemoryStateRow(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc'],
      )!,
      wordKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}word_key'],
      )!,
      strength: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}strength'],
      )!,
      cueDependency: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cue_dependency'],
      )!,
      stability: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}stability'],
      )!,
      difficulty: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}difficulty'],
      )!,
      lapseCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lapse_count'],
      )!,
      lastReviewedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_reviewed_at_utc'],
      ),
      nextDueAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_due_at_utc'],
      )!,
      lastErrorType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_type'],
      ),
      algorithmVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}algorithm_version'],
      )!,
    );
  }

  @override
  $MemoryStatesTable createAlias(String alias) {
    return $MemoryStatesTable(attachedDatabase, alias);
  }
}

class MemoryStateRow extends DataClass implements Insertable<MemoryStateRow> {
  final String ownerId;
  final int schemaVersion;
  final int createdAtUtc;
  final int updatedAtUtc;
  final String wordKey;
  final double strength;
  final double cueDependency;
  final double stability;
  final double difficulty;
  final int lapseCount;
  final int? lastReviewedAtUtc;
  final int nextDueAtUtc;
  final String? lastErrorType;
  final String algorithmVersion;
  const MemoryStateRow({
    required this.ownerId,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.wordKey,
    required this.strength,
    required this.cueDependency,
    required this.stability,
    required this.difficulty,
    required this.lapseCount,
    this.lastReviewedAtUtc,
    required this.nextDueAtUtc,
    this.lastErrorType,
    required this.algorithmVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['created_at_utc'] = Variable<int>(createdAtUtc);
    map['updated_at_utc'] = Variable<int>(updatedAtUtc);
    map['word_key'] = Variable<String>(wordKey);
    map['strength'] = Variable<double>(strength);
    map['cue_dependency'] = Variable<double>(cueDependency);
    map['stability'] = Variable<double>(stability);
    map['difficulty'] = Variable<double>(difficulty);
    map['lapse_count'] = Variable<int>(lapseCount);
    if (!nullToAbsent || lastReviewedAtUtc != null) {
      map['last_reviewed_at_utc'] = Variable<int>(lastReviewedAtUtc);
    }
    map['next_due_at_utc'] = Variable<int>(nextDueAtUtc);
    if (!nullToAbsent || lastErrorType != null) {
      map['last_error_type'] = Variable<String>(lastErrorType);
    }
    map['algorithm_version'] = Variable<String>(algorithmVersion);
    return map;
  }

  MemoryStatesCompanion toCompanion(bool nullToAbsent) {
    return MemoryStatesCompanion(
      ownerId: Value(ownerId),
      schemaVersion: Value(schemaVersion),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
      wordKey: Value(wordKey),
      strength: Value(strength),
      cueDependency: Value(cueDependency),
      stability: Value(stability),
      difficulty: Value(difficulty),
      lapseCount: Value(lapseCount),
      lastReviewedAtUtc: lastReviewedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReviewedAtUtc),
      nextDueAtUtc: Value(nextDueAtUtc),
      lastErrorType: lastErrorType == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorType),
      algorithmVersion: Value(algorithmVersion),
    );
  }

  factory MemoryStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemoryStateRow(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      createdAtUtc: serializer.fromJson<int>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<int>(json['updatedAtUtc']),
      wordKey: serializer.fromJson<String>(json['wordKey']),
      strength: serializer.fromJson<double>(json['strength']),
      cueDependency: serializer.fromJson<double>(json['cueDependency']),
      stability: serializer.fromJson<double>(json['stability']),
      difficulty: serializer.fromJson<double>(json['difficulty']),
      lapseCount: serializer.fromJson<int>(json['lapseCount']),
      lastReviewedAtUtc: serializer.fromJson<int?>(json['lastReviewedAtUtc']),
      nextDueAtUtc: serializer.fromJson<int>(json['nextDueAtUtc']),
      lastErrorType: serializer.fromJson<String?>(json['lastErrorType']),
      algorithmVersion: serializer.fromJson<String>(json['algorithmVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'createdAtUtc': serializer.toJson<int>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<int>(updatedAtUtc),
      'wordKey': serializer.toJson<String>(wordKey),
      'strength': serializer.toJson<double>(strength),
      'cueDependency': serializer.toJson<double>(cueDependency),
      'stability': serializer.toJson<double>(stability),
      'difficulty': serializer.toJson<double>(difficulty),
      'lapseCount': serializer.toJson<int>(lapseCount),
      'lastReviewedAtUtc': serializer.toJson<int?>(lastReviewedAtUtc),
      'nextDueAtUtc': serializer.toJson<int>(nextDueAtUtc),
      'lastErrorType': serializer.toJson<String?>(lastErrorType),
      'algorithmVersion': serializer.toJson<String>(algorithmVersion),
    };
  }

  MemoryStateRow copyWith({
    String? ownerId,
    int? schemaVersion,
    int? createdAtUtc,
    int? updatedAtUtc,
    String? wordKey,
    double? strength,
    double? cueDependency,
    double? stability,
    double? difficulty,
    int? lapseCount,
    Value<int?> lastReviewedAtUtc = const Value.absent(),
    int? nextDueAtUtc,
    Value<String?> lastErrorType = const Value.absent(),
    String? algorithmVersion,
  }) => MemoryStateRow(
    ownerId: ownerId ?? this.ownerId,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    wordKey: wordKey ?? this.wordKey,
    strength: strength ?? this.strength,
    cueDependency: cueDependency ?? this.cueDependency,
    stability: stability ?? this.stability,
    difficulty: difficulty ?? this.difficulty,
    lapseCount: lapseCount ?? this.lapseCount,
    lastReviewedAtUtc: lastReviewedAtUtc.present
        ? lastReviewedAtUtc.value
        : this.lastReviewedAtUtc,
    nextDueAtUtc: nextDueAtUtc ?? this.nextDueAtUtc,
    lastErrorType: lastErrorType.present
        ? lastErrorType.value
        : this.lastErrorType,
    algorithmVersion: algorithmVersion ?? this.algorithmVersion,
  );
  MemoryStateRow copyWithCompanion(MemoryStatesCompanion data) {
    return MemoryStateRow(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
      wordKey: data.wordKey.present ? data.wordKey.value : this.wordKey,
      strength: data.strength.present ? data.strength.value : this.strength,
      cueDependency: data.cueDependency.present
          ? data.cueDependency.value
          : this.cueDependency,
      stability: data.stability.present ? data.stability.value : this.stability,
      difficulty: data.difficulty.present
          ? data.difficulty.value
          : this.difficulty,
      lapseCount: data.lapseCount.present
          ? data.lapseCount.value
          : this.lapseCount,
      lastReviewedAtUtc: data.lastReviewedAtUtc.present
          ? data.lastReviewedAtUtc.value
          : this.lastReviewedAtUtc,
      nextDueAtUtc: data.nextDueAtUtc.present
          ? data.nextDueAtUtc.value
          : this.nextDueAtUtc,
      lastErrorType: data.lastErrorType.present
          ? data.lastErrorType.value
          : this.lastErrorType,
      algorithmVersion: data.algorithmVersion.present
          ? data.algorithmVersion.value
          : this.algorithmVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemoryStateRow(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('wordKey: $wordKey, ')
          ..write('strength: $strength, ')
          ..write('cueDependency: $cueDependency, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('lapseCount: $lapseCount, ')
          ..write('lastReviewedAtUtc: $lastReviewedAtUtc, ')
          ..write('nextDueAtUtc: $nextDueAtUtc, ')
          ..write('lastErrorType: $lastErrorType, ')
          ..write('algorithmVersion: $algorithmVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    wordKey,
    strength,
    cueDependency,
    stability,
    difficulty,
    lapseCount,
    lastReviewedAtUtc,
    nextDueAtUtc,
    lastErrorType,
    algorithmVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoryStateRow &&
          other.ownerId == this.ownerId &&
          other.schemaVersion == this.schemaVersion &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc &&
          other.wordKey == this.wordKey &&
          other.strength == this.strength &&
          other.cueDependency == this.cueDependency &&
          other.stability == this.stability &&
          other.difficulty == this.difficulty &&
          other.lapseCount == this.lapseCount &&
          other.lastReviewedAtUtc == this.lastReviewedAtUtc &&
          other.nextDueAtUtc == this.nextDueAtUtc &&
          other.lastErrorType == this.lastErrorType &&
          other.algorithmVersion == this.algorithmVersion);
}

class MemoryStatesCompanion extends UpdateCompanion<MemoryStateRow> {
  final Value<String> ownerId;
  final Value<int> schemaVersion;
  final Value<int> createdAtUtc;
  final Value<int> updatedAtUtc;
  final Value<String> wordKey;
  final Value<double> strength;
  final Value<double> cueDependency;
  final Value<double> stability;
  final Value<double> difficulty;
  final Value<int> lapseCount;
  final Value<int?> lastReviewedAtUtc;
  final Value<int> nextDueAtUtc;
  final Value<String?> lastErrorType;
  final Value<String> algorithmVersion;
  final Value<int> rowid;
  const MemoryStatesCompanion({
    this.ownerId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.wordKey = const Value.absent(),
    this.strength = const Value.absent(),
    this.cueDependency = const Value.absent(),
    this.stability = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.lapseCount = const Value.absent(),
    this.lastReviewedAtUtc = const Value.absent(),
    this.nextDueAtUtc = const Value.absent(),
    this.lastErrorType = const Value.absent(),
    this.algorithmVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemoryStatesCompanion.insert({
    required String ownerId,
    this.schemaVersion = const Value.absent(),
    required int createdAtUtc,
    required int updatedAtUtc,
    required String wordKey,
    required double strength,
    required double cueDependency,
    required double stability,
    required double difficulty,
    required int lapseCount,
    this.lastReviewedAtUtc = const Value.absent(),
    required int nextDueAtUtc,
    this.lastErrorType = const Value.absent(),
    required String algorithmVersion,
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc),
       wordKey = Value(wordKey),
       strength = Value(strength),
       cueDependency = Value(cueDependency),
       stability = Value(stability),
       difficulty = Value(difficulty),
       lapseCount = Value(lapseCount),
       nextDueAtUtc = Value(nextDueAtUtc),
       algorithmVersion = Value(algorithmVersion);
  static Insertable<MemoryStateRow> custom({
    Expression<String>? ownerId,
    Expression<int>? schemaVersion,
    Expression<int>? createdAtUtc,
    Expression<int>? updatedAtUtc,
    Expression<String>? wordKey,
    Expression<double>? strength,
    Expression<double>? cueDependency,
    Expression<double>? stability,
    Expression<double>? difficulty,
    Expression<int>? lapseCount,
    Expression<int>? lastReviewedAtUtc,
    Expression<int>? nextDueAtUtc,
    Expression<String>? lastErrorType,
    Expression<String>? algorithmVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (wordKey != null) 'word_key': wordKey,
      if (strength != null) 'strength': strength,
      if (cueDependency != null) 'cue_dependency': cueDependency,
      if (stability != null) 'stability': stability,
      if (difficulty != null) 'difficulty': difficulty,
      if (lapseCount != null) 'lapse_count': lapseCount,
      if (lastReviewedAtUtc != null) 'last_reviewed_at_utc': lastReviewedAtUtc,
      if (nextDueAtUtc != null) 'next_due_at_utc': nextDueAtUtc,
      if (lastErrorType != null) 'last_error_type': lastErrorType,
      if (algorithmVersion != null) 'algorithm_version': algorithmVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemoryStatesCompanion copyWith({
    Value<String>? ownerId,
    Value<int>? schemaVersion,
    Value<int>? createdAtUtc,
    Value<int>? updatedAtUtc,
    Value<String>? wordKey,
    Value<double>? strength,
    Value<double>? cueDependency,
    Value<double>? stability,
    Value<double>? difficulty,
    Value<int>? lapseCount,
    Value<int?>? lastReviewedAtUtc,
    Value<int>? nextDueAtUtc,
    Value<String?>? lastErrorType,
    Value<String>? algorithmVersion,
    Value<int>? rowid,
  }) {
    return MemoryStatesCompanion(
      ownerId: ownerId ?? this.ownerId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      wordKey: wordKey ?? this.wordKey,
      strength: strength ?? this.strength,
      cueDependency: cueDependency ?? this.cueDependency,
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      lapseCount: lapseCount ?? this.lapseCount,
      lastReviewedAtUtc: lastReviewedAtUtc ?? this.lastReviewedAtUtc,
      nextDueAtUtc: nextDueAtUtc ?? this.nextDueAtUtc,
      lastErrorType: lastErrorType ?? this.lastErrorType,
      algorithmVersion: algorithmVersion ?? this.algorithmVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<int>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<int>(updatedAtUtc.value);
    }
    if (wordKey.present) {
      map['word_key'] = Variable<String>(wordKey.value);
    }
    if (strength.present) {
      map['strength'] = Variable<double>(strength.value);
    }
    if (cueDependency.present) {
      map['cue_dependency'] = Variable<double>(cueDependency.value);
    }
    if (stability.present) {
      map['stability'] = Variable<double>(stability.value);
    }
    if (difficulty.present) {
      map['difficulty'] = Variable<double>(difficulty.value);
    }
    if (lapseCount.present) {
      map['lapse_count'] = Variable<int>(lapseCount.value);
    }
    if (lastReviewedAtUtc.present) {
      map['last_reviewed_at_utc'] = Variable<int>(lastReviewedAtUtc.value);
    }
    if (nextDueAtUtc.present) {
      map['next_due_at_utc'] = Variable<int>(nextDueAtUtc.value);
    }
    if (lastErrorType.present) {
      map['last_error_type'] = Variable<String>(lastErrorType.value);
    }
    if (algorithmVersion.present) {
      map['algorithm_version'] = Variable<String>(algorithmVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoryStatesCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('wordKey: $wordKey, ')
          ..write('strength: $strength, ')
          ..write('cueDependency: $cueDependency, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('lapseCount: $lapseCount, ')
          ..write('lastReviewedAtUtc: $lastReviewedAtUtc, ')
          ..write('nextDueAtUtc: $nextDueAtUtc, ')
          ..write('lastErrorType: $lastErrorType, ')
          ..write('algorithmVersion: $algorithmVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LearningEventsTable extends LearningEvents
    with TableInfo<$LearningEventsTable, LearningEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LearningEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(1),
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<int> createdAtUtc = GeneratedColumn<int>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtc = GeneratedColumn<int>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtUtcMeta = const VerificationMeta(
    'occurredAtUtc',
  );
  @override
  late final GeneratedColumn<int> occurredAtUtc = GeneratedColumn<int>(
    'occurred_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activityMeta = const VerificationMeta(
    'activity',
  );
  @override
  late final GeneratedColumn<String> activity = GeneratedColumn<String>(
    'activity',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 80,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentIdMeta = const VerificationMeta(
    'contentId',
  );
  @override
  late final GeneratedColumn<String> contentId = GeneratedColumn<String>(
    'content_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cefrLevelMeta = const VerificationMeta(
    'cefrLevel',
  );
  @override
  late final GeneratedColumn<String> cefrLevel = GeneratedColumn<String>(
    'cefr_level',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 2,
      maxTextLength: 2,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _skillMeta = const VerificationMeta('skill');
  @override
  late final GeneratedColumn<String> skill = GeneratedColumn<String>(
    'skill',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 80,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _correctMeta = const VerificationMeta(
    'correct',
  );
  @override
  late final GeneratedColumn<bool> correct = GeneratedColumn<bool>(
    'correct',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("correct" IN (0, 1))',
    ),
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<int> score = GeneratedColumn<int>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
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
  static const VerificationMeta _appVersionMeta = const VerificationMeta(
    'appVersion',
  );
  @override
  late final GeneratedColumn<String> appVersion = GeneratedColumn<String>(
    'app_version',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
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
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    eventId,
    occurredAtUtc,
    activity,
    contentId,
    categoryId,
    cefrLevel,
    skill,
    correct,
    score,
    responseTimeMs,
    attemptNumber,
    appVersion,
    buildId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'learning_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<LearningEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('occurred_at_utc')) {
      context.handle(
        _occurredAtUtcMeta,
        occurredAtUtc.isAcceptableOrUnknown(
          data['occurred_at_utc']!,
          _occurredAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtUtcMeta);
    }
    if (data.containsKey('activity')) {
      context.handle(
        _activityMeta,
        activity.isAcceptableOrUnknown(data['activity']!, _activityMeta),
      );
    } else if (isInserting) {
      context.missing(_activityMeta);
    }
    if (data.containsKey('content_id')) {
      context.handle(
        _contentIdMeta,
        contentId.isAcceptableOrUnknown(data['content_id']!, _contentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_contentIdMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('cefr_level')) {
      context.handle(
        _cefrLevelMeta,
        cefrLevel.isAcceptableOrUnknown(data['cefr_level']!, _cefrLevelMeta),
      );
    }
    if (data.containsKey('skill')) {
      context.handle(
        _skillMeta,
        skill.isAcceptableOrUnknown(data['skill']!, _skillMeta),
      );
    } else if (isInserting) {
      context.missing(_skillMeta);
    }
    if (data.containsKey('correct')) {
      context.handle(
        _correctMeta,
        correct.isAcceptableOrUnknown(data['correct']!, _correctMeta),
      );
    } else if (isInserting) {
      context.missing(_correctMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreMeta);
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
  Set<GeneratedColumn> get $primaryKey => {ownerId, eventId};
  @override
  LearningEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LearningEventRow(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      occurredAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurred_at_utc'],
      )!,
      activity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activity'],
      )!,
      contentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      cefrLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cefr_level'],
      ),
      skill: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}skill'],
      )!,
      correct: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}correct'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}score'],
      )!,
      responseTimeMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}response_time_ms'],
      ),
      attemptNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_number'],
      )!,
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
  $LearningEventsTable createAlias(String alias) {
    return $LearningEventsTable(attachedDatabase, alias);
  }
}

class LearningEventRow extends DataClass
    implements Insertable<LearningEventRow> {
  final String ownerId;
  final int schemaVersion;
  final int createdAtUtc;
  final int updatedAtUtc;
  final String eventId;
  final int occurredAtUtc;
  final String activity;
  final String contentId;
  final String? categoryId;
  final String? cefrLevel;
  final String skill;
  final bool correct;
  final int score;
  final int? responseTimeMs;
  final int attemptNumber;
  final String appVersion;
  final String buildId;
  const LearningEventRow({
    required this.ownerId,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.eventId,
    required this.occurredAtUtc,
    required this.activity,
    required this.contentId,
    this.categoryId,
    this.cefrLevel,
    required this.skill,
    required this.correct,
    required this.score,
    this.responseTimeMs,
    required this.attemptNumber,
    required this.appVersion,
    required this.buildId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['created_at_utc'] = Variable<int>(createdAtUtc);
    map['updated_at_utc'] = Variable<int>(updatedAtUtc);
    map['event_id'] = Variable<String>(eventId);
    map['occurred_at_utc'] = Variable<int>(occurredAtUtc);
    map['activity'] = Variable<String>(activity);
    map['content_id'] = Variable<String>(contentId);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || cefrLevel != null) {
      map['cefr_level'] = Variable<String>(cefrLevel);
    }
    map['skill'] = Variable<String>(skill);
    map['correct'] = Variable<bool>(correct);
    map['score'] = Variable<int>(score);
    if (!nullToAbsent || responseTimeMs != null) {
      map['response_time_ms'] = Variable<int>(responseTimeMs);
    }
    map['attempt_number'] = Variable<int>(attemptNumber);
    map['app_version'] = Variable<String>(appVersion);
    map['build_id'] = Variable<String>(buildId);
    return map;
  }

  LearningEventsCompanion toCompanion(bool nullToAbsent) {
    return LearningEventsCompanion(
      ownerId: Value(ownerId),
      schemaVersion: Value(schemaVersion),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
      eventId: Value(eventId),
      occurredAtUtc: Value(occurredAtUtc),
      activity: Value(activity),
      contentId: Value(contentId),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      cefrLevel: cefrLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(cefrLevel),
      skill: Value(skill),
      correct: Value(correct),
      score: Value(score),
      responseTimeMs: responseTimeMs == null && nullToAbsent
          ? const Value.absent()
          : Value(responseTimeMs),
      attemptNumber: Value(attemptNumber),
      appVersion: Value(appVersion),
      buildId: Value(buildId),
    );
  }

  factory LearningEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LearningEventRow(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      createdAtUtc: serializer.fromJson<int>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<int>(json['updatedAtUtc']),
      eventId: serializer.fromJson<String>(json['eventId']),
      occurredAtUtc: serializer.fromJson<int>(json['occurredAtUtc']),
      activity: serializer.fromJson<String>(json['activity']),
      contentId: serializer.fromJson<String>(json['contentId']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      cefrLevel: serializer.fromJson<String?>(json['cefrLevel']),
      skill: serializer.fromJson<String>(json['skill']),
      correct: serializer.fromJson<bool>(json['correct']),
      score: serializer.fromJson<int>(json['score']),
      responseTimeMs: serializer.fromJson<int?>(json['responseTimeMs']),
      attemptNumber: serializer.fromJson<int>(json['attemptNumber']),
      appVersion: serializer.fromJson<String>(json['appVersion']),
      buildId: serializer.fromJson<String>(json['buildId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'createdAtUtc': serializer.toJson<int>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<int>(updatedAtUtc),
      'eventId': serializer.toJson<String>(eventId),
      'occurredAtUtc': serializer.toJson<int>(occurredAtUtc),
      'activity': serializer.toJson<String>(activity),
      'contentId': serializer.toJson<String>(contentId),
      'categoryId': serializer.toJson<String?>(categoryId),
      'cefrLevel': serializer.toJson<String?>(cefrLevel),
      'skill': serializer.toJson<String>(skill),
      'correct': serializer.toJson<bool>(correct),
      'score': serializer.toJson<int>(score),
      'responseTimeMs': serializer.toJson<int?>(responseTimeMs),
      'attemptNumber': serializer.toJson<int>(attemptNumber),
      'appVersion': serializer.toJson<String>(appVersion),
      'buildId': serializer.toJson<String>(buildId),
    };
  }

  LearningEventRow copyWith({
    String? ownerId,
    int? schemaVersion,
    int? createdAtUtc,
    int? updatedAtUtc,
    String? eventId,
    int? occurredAtUtc,
    String? activity,
    String? contentId,
    Value<String?> categoryId = const Value.absent(),
    Value<String?> cefrLevel = const Value.absent(),
    String? skill,
    bool? correct,
    int? score,
    Value<int?> responseTimeMs = const Value.absent(),
    int? attemptNumber,
    String? appVersion,
    String? buildId,
  }) => LearningEventRow(
    ownerId: ownerId ?? this.ownerId,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    eventId: eventId ?? this.eventId,
    occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
    activity: activity ?? this.activity,
    contentId: contentId ?? this.contentId,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    cefrLevel: cefrLevel.present ? cefrLevel.value : this.cefrLevel,
    skill: skill ?? this.skill,
    correct: correct ?? this.correct,
    score: score ?? this.score,
    responseTimeMs: responseTimeMs.present
        ? responseTimeMs.value
        : this.responseTimeMs,
    attemptNumber: attemptNumber ?? this.attemptNumber,
    appVersion: appVersion ?? this.appVersion,
    buildId: buildId ?? this.buildId,
  );
  LearningEventRow copyWithCompanion(LearningEventsCompanion data) {
    return LearningEventRow(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      occurredAtUtc: data.occurredAtUtc.present
          ? data.occurredAtUtc.value
          : this.occurredAtUtc,
      activity: data.activity.present ? data.activity.value : this.activity,
      contentId: data.contentId.present ? data.contentId.value : this.contentId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      cefrLevel: data.cefrLevel.present ? data.cefrLevel.value : this.cefrLevel,
      skill: data.skill.present ? data.skill.value : this.skill,
      correct: data.correct.present ? data.correct.value : this.correct,
      score: data.score.present ? data.score.value : this.score,
      responseTimeMs: data.responseTimeMs.present
          ? data.responseTimeMs.value
          : this.responseTimeMs,
      attemptNumber: data.attemptNumber.present
          ? data.attemptNumber.value
          : this.attemptNumber,
      appVersion: data.appVersion.present
          ? data.appVersion.value
          : this.appVersion,
      buildId: data.buildId.present ? data.buildId.value : this.buildId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LearningEventRow(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('eventId: $eventId, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('activity: $activity, ')
          ..write('contentId: $contentId, ')
          ..write('categoryId: $categoryId, ')
          ..write('cefrLevel: $cefrLevel, ')
          ..write('skill: $skill, ')
          ..write('correct: $correct, ')
          ..write('score: $score, ')
          ..write('responseTimeMs: $responseTimeMs, ')
          ..write('attemptNumber: $attemptNumber, ')
          ..write('appVersion: $appVersion, ')
          ..write('buildId: $buildId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    eventId,
    occurredAtUtc,
    activity,
    contentId,
    categoryId,
    cefrLevel,
    skill,
    correct,
    score,
    responseTimeMs,
    attemptNumber,
    appVersion,
    buildId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LearningEventRow &&
          other.ownerId == this.ownerId &&
          other.schemaVersion == this.schemaVersion &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc &&
          other.eventId == this.eventId &&
          other.occurredAtUtc == this.occurredAtUtc &&
          other.activity == this.activity &&
          other.contentId == this.contentId &&
          other.categoryId == this.categoryId &&
          other.cefrLevel == this.cefrLevel &&
          other.skill == this.skill &&
          other.correct == this.correct &&
          other.score == this.score &&
          other.responseTimeMs == this.responseTimeMs &&
          other.attemptNumber == this.attemptNumber &&
          other.appVersion == this.appVersion &&
          other.buildId == this.buildId);
}

class LearningEventsCompanion extends UpdateCompanion<LearningEventRow> {
  final Value<String> ownerId;
  final Value<int> schemaVersion;
  final Value<int> createdAtUtc;
  final Value<int> updatedAtUtc;
  final Value<String> eventId;
  final Value<int> occurredAtUtc;
  final Value<String> activity;
  final Value<String> contentId;
  final Value<String?> categoryId;
  final Value<String?> cefrLevel;
  final Value<String> skill;
  final Value<bool> correct;
  final Value<int> score;
  final Value<int?> responseTimeMs;
  final Value<int> attemptNumber;
  final Value<String> appVersion;
  final Value<String> buildId;
  final Value<int> rowid;
  const LearningEventsCompanion({
    this.ownerId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.eventId = const Value.absent(),
    this.occurredAtUtc = const Value.absent(),
    this.activity = const Value.absent(),
    this.contentId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.cefrLevel = const Value.absent(),
    this.skill = const Value.absent(),
    this.correct = const Value.absent(),
    this.score = const Value.absent(),
    this.responseTimeMs = const Value.absent(),
    this.attemptNumber = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.buildId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LearningEventsCompanion.insert({
    required String ownerId,
    this.schemaVersion = const Value.absent(),
    required int createdAtUtc,
    required int updatedAtUtc,
    required String eventId,
    required int occurredAtUtc,
    required String activity,
    required String contentId,
    this.categoryId = const Value.absent(),
    this.cefrLevel = const Value.absent(),
    required String skill,
    required bool correct,
    required int score,
    this.responseTimeMs = const Value.absent(),
    required int attemptNumber,
    required String appVersion,
    required String buildId,
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc),
       eventId = Value(eventId),
       occurredAtUtc = Value(occurredAtUtc),
       activity = Value(activity),
       contentId = Value(contentId),
       skill = Value(skill),
       correct = Value(correct),
       score = Value(score),
       attemptNumber = Value(attemptNumber),
       appVersion = Value(appVersion),
       buildId = Value(buildId);
  static Insertable<LearningEventRow> custom({
    Expression<String>? ownerId,
    Expression<int>? schemaVersion,
    Expression<int>? createdAtUtc,
    Expression<int>? updatedAtUtc,
    Expression<String>? eventId,
    Expression<int>? occurredAtUtc,
    Expression<String>? activity,
    Expression<String>? contentId,
    Expression<String>? categoryId,
    Expression<String>? cefrLevel,
    Expression<String>? skill,
    Expression<bool>? correct,
    Expression<int>? score,
    Expression<int>? responseTimeMs,
    Expression<int>? attemptNumber,
    Expression<String>? appVersion,
    Expression<String>? buildId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (eventId != null) 'event_id': eventId,
      if (occurredAtUtc != null) 'occurred_at_utc': occurredAtUtc,
      if (activity != null) 'activity': activity,
      if (contentId != null) 'content_id': contentId,
      if (categoryId != null) 'category_id': categoryId,
      if (cefrLevel != null) 'cefr_level': cefrLevel,
      if (skill != null) 'skill': skill,
      if (correct != null) 'correct': correct,
      if (score != null) 'score': score,
      if (responseTimeMs != null) 'response_time_ms': responseTimeMs,
      if (attemptNumber != null) 'attempt_number': attemptNumber,
      if (appVersion != null) 'app_version': appVersion,
      if (buildId != null) 'build_id': buildId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LearningEventsCompanion copyWith({
    Value<String>? ownerId,
    Value<int>? schemaVersion,
    Value<int>? createdAtUtc,
    Value<int>? updatedAtUtc,
    Value<String>? eventId,
    Value<int>? occurredAtUtc,
    Value<String>? activity,
    Value<String>? contentId,
    Value<String?>? categoryId,
    Value<String?>? cefrLevel,
    Value<String>? skill,
    Value<bool>? correct,
    Value<int>? score,
    Value<int?>? responseTimeMs,
    Value<int>? attemptNumber,
    Value<String>? appVersion,
    Value<String>? buildId,
    Value<int>? rowid,
  }) {
    return LearningEventsCompanion(
      ownerId: ownerId ?? this.ownerId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      eventId: eventId ?? this.eventId,
      occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
      activity: activity ?? this.activity,
      contentId: contentId ?? this.contentId,
      categoryId: categoryId ?? this.categoryId,
      cefrLevel: cefrLevel ?? this.cefrLevel,
      skill: skill ?? this.skill,
      correct: correct ?? this.correct,
      score: score ?? this.score,
      responseTimeMs: responseTimeMs ?? this.responseTimeMs,
      attemptNumber: attemptNumber ?? this.attemptNumber,
      appVersion: appVersion ?? this.appVersion,
      buildId: buildId ?? this.buildId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<int>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<int>(updatedAtUtc.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (occurredAtUtc.present) {
      map['occurred_at_utc'] = Variable<int>(occurredAtUtc.value);
    }
    if (activity.present) {
      map['activity'] = Variable<String>(activity.value);
    }
    if (contentId.present) {
      map['content_id'] = Variable<String>(contentId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (cefrLevel.present) {
      map['cefr_level'] = Variable<String>(cefrLevel.value);
    }
    if (skill.present) {
      map['skill'] = Variable<String>(skill.value);
    }
    if (correct.present) {
      map['correct'] = Variable<bool>(correct.value);
    }
    if (score.present) {
      map['score'] = Variable<int>(score.value);
    }
    if (responseTimeMs.present) {
      map['response_time_ms'] = Variable<int>(responseTimeMs.value);
    }
    if (attemptNumber.present) {
      map['attempt_number'] = Variable<int>(attemptNumber.value);
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
    return (StringBuffer('LearningEventsCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('eventId: $eventId, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('activity: $activity, ')
          ..write('contentId: $contentId, ')
          ..write('categoryId: $categoryId, ')
          ..write('cefrLevel: $cefrLevel, ')
          ..write('skill: $skill, ')
          ..write('correct: $correct, ')
          ..write('score: $score, ')
          ..write('responseTimeMs: $responseTimeMs, ')
          ..write('attemptNumber: $attemptNumber, ')
          ..write('appVersion: $appVersion, ')
          ..write('buildId: $buildId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, SyncOutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(1),
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<int> createdAtUtc = GeneratedColumn<int>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtc = GeneratedColumn<int>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outboxIdMeta = const VerificationMeta(
    'outboxId',
  );
  @override
  late final GeneratedColumn<String> outboxId = GeneratedColumn<String>(
    'outbox_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 80,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acknowledgedAtUtcMeta = const VerificationMeta(
    'acknowledgedAtUtc',
  );
  @override
  late final GeneratedColumn<int> acknowledgedAtUtc = GeneratedColumn<int>(
    'acknowledged_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    outboxId,
    eventId,
    operation,
    payloadJson,
    acknowledgedAtUtc,
    attemptCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    if (data.containsKey('outbox_id')) {
      context.handle(
        _outboxIdMeta,
        outboxId.isAcceptableOrUnknown(data['outbox_id']!, _outboxIdMeta),
      );
    } else if (isInserting) {
      context.missing(_outboxIdMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('acknowledged_at_utc')) {
      context.handle(
        _acknowledgedAtUtcMeta,
        acknowledgedAtUtc.isAcceptableOrUnknown(
          data['acknowledged_at_utc']!,
          _acknowledgedAtUtcMeta,
        ),
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
    } else if (isInserting) {
      context.missing(_attemptCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, outboxId};
  @override
  SyncOutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxRow(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc'],
      )!,
      outboxId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outbox_id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      acknowledgedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}acknowledged_at_utc'],
      ),
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class SyncOutboxRow extends DataClass implements Insertable<SyncOutboxRow> {
  final String ownerId;
  final int schemaVersion;
  final int createdAtUtc;
  final int updatedAtUtc;
  final String outboxId;
  final String eventId;
  final String operation;
  final String payloadJson;
  final int? acknowledgedAtUtc;
  final int attemptCount;
  const SyncOutboxRow({
    required this.ownerId,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.outboxId,
    required this.eventId,
    required this.operation,
    required this.payloadJson,
    this.acknowledgedAtUtc,
    required this.attemptCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['created_at_utc'] = Variable<int>(createdAtUtc);
    map['updated_at_utc'] = Variable<int>(updatedAtUtc);
    map['outbox_id'] = Variable<String>(outboxId);
    map['event_id'] = Variable<String>(eventId);
    map['operation'] = Variable<String>(operation);
    map['payload_json'] = Variable<String>(payloadJson);
    if (!nullToAbsent || acknowledgedAtUtc != null) {
      map['acknowledged_at_utc'] = Variable<int>(acknowledgedAtUtc);
    }
    map['attempt_count'] = Variable<int>(attemptCount);
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      ownerId: Value(ownerId),
      schemaVersion: Value(schemaVersion),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
      outboxId: Value(outboxId),
      eventId: Value(eventId),
      operation: Value(operation),
      payloadJson: Value(payloadJson),
      acknowledgedAtUtc: acknowledgedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(acknowledgedAtUtc),
      attemptCount: Value(attemptCount),
    );
  }

  factory SyncOutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxRow(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      createdAtUtc: serializer.fromJson<int>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<int>(json['updatedAtUtc']),
      outboxId: serializer.fromJson<String>(json['outboxId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      operation: serializer.fromJson<String>(json['operation']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      acknowledgedAtUtc: serializer.fromJson<int?>(json['acknowledgedAtUtc']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'createdAtUtc': serializer.toJson<int>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<int>(updatedAtUtc),
      'outboxId': serializer.toJson<String>(outboxId),
      'eventId': serializer.toJson<String>(eventId),
      'operation': serializer.toJson<String>(operation),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'acknowledgedAtUtc': serializer.toJson<int?>(acknowledgedAtUtc),
      'attemptCount': serializer.toJson<int>(attemptCount),
    };
  }

  SyncOutboxRow copyWith({
    String? ownerId,
    int? schemaVersion,
    int? createdAtUtc,
    int? updatedAtUtc,
    String? outboxId,
    String? eventId,
    String? operation,
    String? payloadJson,
    Value<int?> acknowledgedAtUtc = const Value.absent(),
    int? attemptCount,
  }) => SyncOutboxRow(
    ownerId: ownerId ?? this.ownerId,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    outboxId: outboxId ?? this.outboxId,
    eventId: eventId ?? this.eventId,
    operation: operation ?? this.operation,
    payloadJson: payloadJson ?? this.payloadJson,
    acknowledgedAtUtc: acknowledgedAtUtc.present
        ? acknowledgedAtUtc.value
        : this.acknowledgedAtUtc,
    attemptCount: attemptCount ?? this.attemptCount,
  );
  SyncOutboxRow copyWithCompanion(SyncOutboxCompanion data) {
    return SyncOutboxRow(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
      outboxId: data.outboxId.present ? data.outboxId.value : this.outboxId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      acknowledgedAtUtc: data.acknowledgedAtUtc.present
          ? data.acknowledgedAtUtc.value
          : this.acknowledgedAtUtc,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxRow(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('outboxId: $outboxId, ')
          ..write('eventId: $eventId, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('acknowledgedAtUtc: $acknowledgedAtUtc, ')
          ..write('attemptCount: $attemptCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    outboxId,
    eventId,
    operation,
    payloadJson,
    acknowledgedAtUtc,
    attemptCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxRow &&
          other.ownerId == this.ownerId &&
          other.schemaVersion == this.schemaVersion &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc &&
          other.outboxId == this.outboxId &&
          other.eventId == this.eventId &&
          other.operation == this.operation &&
          other.payloadJson == this.payloadJson &&
          other.acknowledgedAtUtc == this.acknowledgedAtUtc &&
          other.attemptCount == this.attemptCount);
}

class SyncOutboxCompanion extends UpdateCompanion<SyncOutboxRow> {
  final Value<String> ownerId;
  final Value<int> schemaVersion;
  final Value<int> createdAtUtc;
  final Value<int> updatedAtUtc;
  final Value<String> outboxId;
  final Value<String> eventId;
  final Value<String> operation;
  final Value<String> payloadJson;
  final Value<int?> acknowledgedAtUtc;
  final Value<int> attemptCount;
  final Value<int> rowid;
  const SyncOutboxCompanion({
    this.ownerId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.outboxId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.acknowledgedAtUtc = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    required String ownerId,
    this.schemaVersion = const Value.absent(),
    required int createdAtUtc,
    required int updatedAtUtc,
    required String outboxId,
    required String eventId,
    required String operation,
    required String payloadJson,
    this.acknowledgedAtUtc = const Value.absent(),
    required int attemptCount,
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc),
       outboxId = Value(outboxId),
       eventId = Value(eventId),
       operation = Value(operation),
       payloadJson = Value(payloadJson),
       attemptCount = Value(attemptCount);
  static Insertable<SyncOutboxRow> custom({
    Expression<String>? ownerId,
    Expression<int>? schemaVersion,
    Expression<int>? createdAtUtc,
    Expression<int>? updatedAtUtc,
    Expression<String>? outboxId,
    Expression<String>? eventId,
    Expression<String>? operation,
    Expression<String>? payloadJson,
    Expression<int>? acknowledgedAtUtc,
    Expression<int>? attemptCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (outboxId != null) 'outbox_id': outboxId,
      if (eventId != null) 'event_id': eventId,
      if (operation != null) 'operation': operation,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (acknowledgedAtUtc != null) 'acknowledged_at_utc': acknowledgedAtUtc,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<String>? ownerId,
    Value<int>? schemaVersion,
    Value<int>? createdAtUtc,
    Value<int>? updatedAtUtc,
    Value<String>? outboxId,
    Value<String>? eventId,
    Value<String>? operation,
    Value<String>? payloadJson,
    Value<int?>? acknowledgedAtUtc,
    Value<int>? attemptCount,
    Value<int>? rowid,
  }) {
    return SyncOutboxCompanion(
      ownerId: ownerId ?? this.ownerId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      outboxId: outboxId ?? this.outboxId,
      eventId: eventId ?? this.eventId,
      operation: operation ?? this.operation,
      payloadJson: payloadJson ?? this.payloadJson,
      acknowledgedAtUtc: acknowledgedAtUtc ?? this.acknowledgedAtUtc,
      attemptCount: attemptCount ?? this.attemptCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<int>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<int>(updatedAtUtc.value);
    }
    if (outboxId.present) {
      map['outbox_id'] = Variable<String>(outboxId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (acknowledgedAtUtc.present) {
      map['acknowledged_at_utc'] = Variable<int>(acknowledgedAtUtc.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('outboxId: $outboxId, ')
          ..write('eventId: $eventId, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('acknowledgedAtUtc: $acknowledgedAtUtc, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeletionTombstonesTable extends DeletionTombstones
    with TableInfo<$DeletionTombstonesTable, DeletionTombstoneRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeletionTombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(1),
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<int> createdAtUtc = GeneratedColumn<int>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtc = GeneratedColumn<int>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tombstoneIdMeta = const VerificationMeta(
    'tombstoneId',
  );
  @override
  late final GeneratedColumn<String> tombstoneId = GeneratedColumn<String>(
    'tombstone_id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
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
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtUtcMeta = const VerificationMeta(
    'deletedAtUtc',
  );
  @override
  late final GeneratedColumn<int> deletedAtUtc = GeneratedColumn<int>(
    'deleted_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    tombstoneId,
    entityType,
    entityId,
    deletedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'deletion_tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeletionTombstoneRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    if (data.containsKey('tombstone_id')) {
      context.handle(
        _tombstoneIdMeta,
        tombstoneId.isAcceptableOrUnknown(
          data['tombstone_id']!,
          _tombstoneIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tombstoneIdMeta);
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
    if (data.containsKey('deleted_at_utc')) {
      context.handle(
        _deletedAtUtcMeta,
        deletedAtUtc.isAcceptableOrUnknown(
          data['deleted_at_utc']!,
          _deletedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deletedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, tombstoneId};
  @override
  DeletionTombstoneRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeletionTombstoneRow(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc'],
      )!,
      tombstoneId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tombstone_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      deletedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at_utc'],
      )!,
    );
  }

  @override
  $DeletionTombstonesTable createAlias(String alias) {
    return $DeletionTombstonesTable(attachedDatabase, alias);
  }
}

class DeletionTombstoneRow extends DataClass
    implements Insertable<DeletionTombstoneRow> {
  final String ownerId;
  final int schemaVersion;
  final int createdAtUtc;
  final int updatedAtUtc;
  final String tombstoneId;
  final String entityType;
  final String entityId;
  final int deletedAtUtc;
  const DeletionTombstoneRow({
    required this.ownerId,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.tombstoneId,
    required this.entityType,
    required this.entityId,
    required this.deletedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['created_at_utc'] = Variable<int>(createdAtUtc);
    map['updated_at_utc'] = Variable<int>(updatedAtUtc);
    map['tombstone_id'] = Variable<String>(tombstoneId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['deleted_at_utc'] = Variable<int>(deletedAtUtc);
    return map;
  }

  DeletionTombstonesCompanion toCompanion(bool nullToAbsent) {
    return DeletionTombstonesCompanion(
      ownerId: Value(ownerId),
      schemaVersion: Value(schemaVersion),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
      tombstoneId: Value(tombstoneId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      deletedAtUtc: Value(deletedAtUtc),
    );
  }

  factory DeletionTombstoneRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeletionTombstoneRow(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      createdAtUtc: serializer.fromJson<int>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<int>(json['updatedAtUtc']),
      tombstoneId: serializer.fromJson<String>(json['tombstoneId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      deletedAtUtc: serializer.fromJson<int>(json['deletedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'createdAtUtc': serializer.toJson<int>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<int>(updatedAtUtc),
      'tombstoneId': serializer.toJson<String>(tombstoneId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'deletedAtUtc': serializer.toJson<int>(deletedAtUtc),
    };
  }

  DeletionTombstoneRow copyWith({
    String? ownerId,
    int? schemaVersion,
    int? createdAtUtc,
    int? updatedAtUtc,
    String? tombstoneId,
    String? entityType,
    String? entityId,
    int? deletedAtUtc,
  }) => DeletionTombstoneRow(
    ownerId: ownerId ?? this.ownerId,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    tombstoneId: tombstoneId ?? this.tombstoneId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    deletedAtUtc: deletedAtUtc ?? this.deletedAtUtc,
  );
  DeletionTombstoneRow copyWithCompanion(DeletionTombstonesCompanion data) {
    return DeletionTombstoneRow(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
      tombstoneId: data.tombstoneId.present
          ? data.tombstoneId.value
          : this.tombstoneId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      deletedAtUtc: data.deletedAtUtc.present
          ? data.deletedAtUtc.value
          : this.deletedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeletionTombstoneRow(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('tombstoneId: $tombstoneId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('deletedAtUtc: $deletedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    schemaVersion,
    createdAtUtc,
    updatedAtUtc,
    tombstoneId,
    entityType,
    entityId,
    deletedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeletionTombstoneRow &&
          other.ownerId == this.ownerId &&
          other.schemaVersion == this.schemaVersion &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc &&
          other.tombstoneId == this.tombstoneId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.deletedAtUtc == this.deletedAtUtc);
}

class DeletionTombstonesCompanion
    extends UpdateCompanion<DeletionTombstoneRow> {
  final Value<String> ownerId;
  final Value<int> schemaVersion;
  final Value<int> createdAtUtc;
  final Value<int> updatedAtUtc;
  final Value<String> tombstoneId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<int> deletedAtUtc;
  final Value<int> rowid;
  const DeletionTombstonesCompanion({
    this.ownerId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.tombstoneId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.deletedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeletionTombstonesCompanion.insert({
    required String ownerId,
    this.schemaVersion = const Value.absent(),
    required int createdAtUtc,
    required int updatedAtUtc,
    required String tombstoneId,
    required String entityType,
    required String entityId,
    required int deletedAtUtc,
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc),
       tombstoneId = Value(tombstoneId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       deletedAtUtc = Value(deletedAtUtc);
  static Insertable<DeletionTombstoneRow> custom({
    Expression<String>? ownerId,
    Expression<int>? schemaVersion,
    Expression<int>? createdAtUtc,
    Expression<int>? updatedAtUtc,
    Expression<String>? tombstoneId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<int>? deletedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (tombstoneId != null) 'tombstone_id': tombstoneId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (deletedAtUtc != null) 'deleted_at_utc': deletedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeletionTombstonesCompanion copyWith({
    Value<String>? ownerId,
    Value<int>? schemaVersion,
    Value<int>? createdAtUtc,
    Value<int>? updatedAtUtc,
    Value<String>? tombstoneId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<int>? deletedAtUtc,
    Value<int>? rowid,
  }) {
    return DeletionTombstonesCompanion(
      ownerId: ownerId ?? this.ownerId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      tombstoneId: tombstoneId ?? this.tombstoneId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      deletedAtUtc: deletedAtUtc ?? this.deletedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<int>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<int>(updatedAtUtc.value);
    }
    if (tombstoneId.present) {
      map['tombstone_id'] = Variable<String>(tombstoneId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (deletedAtUtc.present) {
      map['deleted_at_utc'] = Variable<int>(deletedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeletionTombstonesCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('tombstoneId: $tombstoneId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('deletedAtUtc: $deletedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LearningDatabase extends GeneratedDatabase {
  _$LearningDatabase(QueryExecutor e) : super(e);
  $LearningDatabaseManager get managers => $LearningDatabaseManager(this);
  late final $LearningCommitsTable learningCommits = $LearningCommitsTable(
    this,
  );
  late final $AssociationsTable associations = $AssociationsTable(this);
  late final $ReadingSessionsTable readingSessions = $ReadingSessionsTable(
    this,
  );
  late final $RecallAttemptsTable recallAttempts = $RecallAttemptsTable(this);
  late final $MemoryStatesTable memoryStates = $MemoryStatesTable(this);
  late final $LearningEventsTable learningEvents = $LearningEventsTable(this);
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  late final $DeletionTombstonesTable deletionTombstones =
      $DeletionTombstonesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    learningCommits,
    associations,
    readingSessions,
    recallAttempts,
    memoryStates,
    learningEvents,
    syncOutbox,
    deletionTombstones,
  ];
}

typedef $$LearningCommitsTableCreateCompanionBuilder =
    LearningCommitsCompanion Function({
      required String ownerId,
      Value<int> schemaVersion,
      required int createdAtUtc,
      required int updatedAtUtc,
      required String commitId,
      required int recordedAtUtc,
      required int recordCount,
      required String contentFingerprint,
      Value<int> rowid,
    });
typedef $$LearningCommitsTableUpdateCompanionBuilder =
    LearningCommitsCompanion Function({
      Value<String> ownerId,
      Value<int> schemaVersion,
      Value<int> createdAtUtc,
      Value<int> updatedAtUtc,
      Value<String> commitId,
      Value<int> recordedAtUtc,
      Value<int> recordCount,
      Value<String> contentFingerprint,
      Value<int> rowid,
    });

class $$LearningCommitsTableFilterComposer
    extends Composer<_$LearningDatabase, $LearningCommitsTable> {
  $$LearningCommitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get commitId => $composableBuilder(
    column: $table.commitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recordedAtUtc => $composableBuilder(
    column: $table.recordedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recordCount => $composableBuilder(
    column: $table.recordCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentFingerprint => $composableBuilder(
    column: $table.contentFingerprint,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LearningCommitsTableOrderingComposer
    extends Composer<_$LearningDatabase, $LearningCommitsTable> {
  $$LearningCommitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commitId => $composableBuilder(
    column: $table.commitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordedAtUtc => $composableBuilder(
    column: $table.recordedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordCount => $composableBuilder(
    column: $table.recordCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentFingerprint => $composableBuilder(
    column: $table.contentFingerprint,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LearningCommitsTableAnnotationComposer
    extends Composer<_$LearningDatabase, $LearningCommitsTable> {
  $$LearningCommitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get commitId =>
      $composableBuilder(column: $table.commitId, builder: (column) => column);

  GeneratedColumn<int> get recordedAtUtc => $composableBuilder(
    column: $table.recordedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recordCount => $composableBuilder(
    column: $table.recordCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentFingerprint => $composableBuilder(
    column: $table.contentFingerprint,
    builder: (column) => column,
  );
}

class $$LearningCommitsTableTableManager
    extends
        RootTableManager<
          _$LearningDatabase,
          $LearningCommitsTable,
          LearningCommitRow,
          $$LearningCommitsTableFilterComposer,
          $$LearningCommitsTableOrderingComposer,
          $$LearningCommitsTableAnnotationComposer,
          $$LearningCommitsTableCreateCompanionBuilder,
          $$LearningCommitsTableUpdateCompanionBuilder,
          (
            LearningCommitRow,
            BaseReferences<
              _$LearningDatabase,
              $LearningCommitsTable,
              LearningCommitRow
            >,
          ),
          LearningCommitRow,
          PrefetchHooks Function()
        > {
  $$LearningCommitsTableTableManager(
    _$LearningDatabase db,
    $LearningCommitsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LearningCommitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LearningCommitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LearningCommitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<int> createdAtUtc = const Value.absent(),
                Value<int> updatedAtUtc = const Value.absent(),
                Value<String> commitId = const Value.absent(),
                Value<int> recordedAtUtc = const Value.absent(),
                Value<int> recordCount = const Value.absent(),
                Value<String> contentFingerprint = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearningCommitsCompanion(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                commitId: commitId,
                recordedAtUtc: recordedAtUtc,
                recordCount: recordCount,
                contentFingerprint: contentFingerprint,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerId,
                Value<int> schemaVersion = const Value.absent(),
                required int createdAtUtc,
                required int updatedAtUtc,
                required String commitId,
                required int recordedAtUtc,
                required int recordCount,
                required String contentFingerprint,
                Value<int> rowid = const Value.absent(),
              }) => LearningCommitsCompanion.insert(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                commitId: commitId,
                recordedAtUtc: recordedAtUtc,
                recordCount: recordCount,
                contentFingerprint: contentFingerprint,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LearningCommitsTableProcessedTableManager =
    ProcessedTableManager<
      _$LearningDatabase,
      $LearningCommitsTable,
      LearningCommitRow,
      $$LearningCommitsTableFilterComposer,
      $$LearningCommitsTableOrderingComposer,
      $$LearningCommitsTableAnnotationComposer,
      $$LearningCommitsTableCreateCompanionBuilder,
      $$LearningCommitsTableUpdateCompanionBuilder,
      (
        LearningCommitRow,
        BaseReferences<
          _$LearningDatabase,
          $LearningCommitsTable,
          LearningCommitRow
        >,
      ),
      LearningCommitRow,
      PrefetchHooks Function()
    >;
typedef $$AssociationsTableCreateCompanionBuilder =
    AssociationsCompanion Function({
      required String ownerId,
      Value<int> schemaVersion,
      required int createdAtUtc,
      required int updatedAtUtc,
      required String associationId,
      required String wordKey,
      required String cueType,
      required String cueText,
      required String origin,
      required double strength,
      required int successCount,
      required int failureCount,
      Value<int> rowid,
    });
typedef $$AssociationsTableUpdateCompanionBuilder =
    AssociationsCompanion Function({
      Value<String> ownerId,
      Value<int> schemaVersion,
      Value<int> createdAtUtc,
      Value<int> updatedAtUtc,
      Value<String> associationId,
      Value<String> wordKey,
      Value<String> cueType,
      Value<String> cueText,
      Value<String> origin,
      Value<double> strength,
      Value<int> successCount,
      Value<int> failureCount,
      Value<int> rowid,
    });

class $$AssociationsTableFilterComposer
    extends Composer<_$LearningDatabase, $AssociationsTable> {
  $$AssociationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get associationId => $composableBuilder(
    column: $table.associationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wordKey => $composableBuilder(
    column: $table.wordKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cueType => $composableBuilder(
    column: $table.cueType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cueText => $composableBuilder(
    column: $table.cueText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get strength => $composableBuilder(
    column: $table.strength,
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
}

class $$AssociationsTableOrderingComposer
    extends Composer<_$LearningDatabase, $AssociationsTable> {
  $$AssociationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get associationId => $composableBuilder(
    column: $table.associationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wordKey => $composableBuilder(
    column: $table.wordKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cueType => $composableBuilder(
    column: $table.cueType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cueText => $composableBuilder(
    column: $table.cueText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get strength => $composableBuilder(
    column: $table.strength,
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
}

class $$AssociationsTableAnnotationComposer
    extends Composer<_$LearningDatabase, $AssociationsTable> {
  $$AssociationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get associationId => $composableBuilder(
    column: $table.associationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get wordKey =>
      $composableBuilder(column: $table.wordKey, builder: (column) => column);

  GeneratedColumn<String> get cueType =>
      $composableBuilder(column: $table.cueType, builder: (column) => column);

  GeneratedColumn<String> get cueText =>
      $composableBuilder(column: $table.cueText, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<double> get strength =>
      $composableBuilder(column: $table.strength, builder: (column) => column);

  GeneratedColumn<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get failureCount => $composableBuilder(
    column: $table.failureCount,
    builder: (column) => column,
  );
}

class $$AssociationsTableTableManager
    extends
        RootTableManager<
          _$LearningDatabase,
          $AssociationsTable,
          AssociationRow,
          $$AssociationsTableFilterComposer,
          $$AssociationsTableOrderingComposer,
          $$AssociationsTableAnnotationComposer,
          $$AssociationsTableCreateCompanionBuilder,
          $$AssociationsTableUpdateCompanionBuilder,
          (
            AssociationRow,
            BaseReferences<
              _$LearningDatabase,
              $AssociationsTable,
              AssociationRow
            >,
          ),
          AssociationRow,
          PrefetchHooks Function()
        > {
  $$AssociationsTableTableManager(
    _$LearningDatabase db,
    $AssociationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssociationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssociationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssociationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<int> createdAtUtc = const Value.absent(),
                Value<int> updatedAtUtc = const Value.absent(),
                Value<String> associationId = const Value.absent(),
                Value<String> wordKey = const Value.absent(),
                Value<String> cueType = const Value.absent(),
                Value<String> cueText = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<double> strength = const Value.absent(),
                Value<int> successCount = const Value.absent(),
                Value<int> failureCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssociationsCompanion(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                associationId: associationId,
                wordKey: wordKey,
                cueType: cueType,
                cueText: cueText,
                origin: origin,
                strength: strength,
                successCount: successCount,
                failureCount: failureCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerId,
                Value<int> schemaVersion = const Value.absent(),
                required int createdAtUtc,
                required int updatedAtUtc,
                required String associationId,
                required String wordKey,
                required String cueType,
                required String cueText,
                required String origin,
                required double strength,
                required int successCount,
                required int failureCount,
                Value<int> rowid = const Value.absent(),
              }) => AssociationsCompanion.insert(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                associationId: associationId,
                wordKey: wordKey,
                cueType: cueType,
                cueText: cueText,
                origin: origin,
                strength: strength,
                successCount: successCount,
                failureCount: failureCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AssociationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LearningDatabase,
      $AssociationsTable,
      AssociationRow,
      $$AssociationsTableFilterComposer,
      $$AssociationsTableOrderingComposer,
      $$AssociationsTableAnnotationComposer,
      $$AssociationsTableCreateCompanionBuilder,
      $$AssociationsTableUpdateCompanionBuilder,
      (
        AssociationRow,
        BaseReferences<_$LearningDatabase, $AssociationsTable, AssociationRow>,
      ),
      AssociationRow,
      PrefetchHooks Function()
    >;
typedef $$ReadingSessionsTableCreateCompanionBuilder =
    ReadingSessionsCompanion Function({
      required String ownerId,
      Value<int> schemaVersion,
      required int createdAtUtc,
      required int updatedAtUtc,
      required String sessionId,
      required String cefrLevel,
      required String targetWordKeysJson,
      required String mixPolicyVersion,
      required String contentId,
      required String contentVersion,
      required String currentStage,
      required int startedAtUtc,
      Value<int?> completedAtUtc,
      Value<int?> abandonedAtUtc,
      Value<int> rowid,
    });
typedef $$ReadingSessionsTableUpdateCompanionBuilder =
    ReadingSessionsCompanion Function({
      Value<String> ownerId,
      Value<int> schemaVersion,
      Value<int> createdAtUtc,
      Value<int> updatedAtUtc,
      Value<String> sessionId,
      Value<String> cefrLevel,
      Value<String> targetWordKeysJson,
      Value<String> mixPolicyVersion,
      Value<String> contentId,
      Value<String> contentVersion,
      Value<String> currentStage,
      Value<int> startedAtUtc,
      Value<int?> completedAtUtc,
      Value<int?> abandonedAtUtc,
      Value<int> rowid,
    });

class $$ReadingSessionsTableFilterComposer
    extends Composer<_$LearningDatabase, $ReadingSessionsTable> {
  $$ReadingSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cefrLevel => $composableBuilder(
    column: $table.cefrLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetWordKeysJson => $composableBuilder(
    column: $table.targetWordKeysJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mixPolicyVersion => $composableBuilder(
    column: $table.mixPolicyVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentId => $composableBuilder(
    column: $table.contentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentVersion => $composableBuilder(
    column: $table.contentVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentStage => $composableBuilder(
    column: $table.currentStage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAtUtc => $composableBuilder(
    column: $table.startedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get abandonedAtUtc => $composableBuilder(
    column: $table.abandonedAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReadingSessionsTableOrderingComposer
    extends Composer<_$LearningDatabase, $ReadingSessionsTable> {
  $$ReadingSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cefrLevel => $composableBuilder(
    column: $table.cefrLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetWordKeysJson => $composableBuilder(
    column: $table.targetWordKeysJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mixPolicyVersion => $composableBuilder(
    column: $table.mixPolicyVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentId => $composableBuilder(
    column: $table.contentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentVersion => $composableBuilder(
    column: $table.contentVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentStage => $composableBuilder(
    column: $table.currentStage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAtUtc => $composableBuilder(
    column: $table.startedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get abandonedAtUtc => $composableBuilder(
    column: $table.abandonedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReadingSessionsTableAnnotationComposer
    extends Composer<_$LearningDatabase, $ReadingSessionsTable> {
  $$ReadingSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get cefrLevel =>
      $composableBuilder(column: $table.cefrLevel, builder: (column) => column);

  GeneratedColumn<String> get targetWordKeysJson => $composableBuilder(
    column: $table.targetWordKeysJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mixPolicyVersion => $composableBuilder(
    column: $table.mixPolicyVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentId =>
      $composableBuilder(column: $table.contentId, builder: (column) => column);

  GeneratedColumn<String> get contentVersion => $composableBuilder(
    column: $table.contentVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentStage => $composableBuilder(
    column: $table.currentStage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startedAtUtc => $composableBuilder(
    column: $table.startedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get abandonedAtUtc => $composableBuilder(
    column: $table.abandonedAtUtc,
    builder: (column) => column,
  );
}

class $$ReadingSessionsTableTableManager
    extends
        RootTableManager<
          _$LearningDatabase,
          $ReadingSessionsTable,
          ReadingSessionRow,
          $$ReadingSessionsTableFilterComposer,
          $$ReadingSessionsTableOrderingComposer,
          $$ReadingSessionsTableAnnotationComposer,
          $$ReadingSessionsTableCreateCompanionBuilder,
          $$ReadingSessionsTableUpdateCompanionBuilder,
          (
            ReadingSessionRow,
            BaseReferences<
              _$LearningDatabase,
              $ReadingSessionsTable,
              ReadingSessionRow
            >,
          ),
          ReadingSessionRow,
          PrefetchHooks Function()
        > {
  $$ReadingSessionsTableTableManager(
    _$LearningDatabase db,
    $ReadingSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadingSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<int> createdAtUtc = const Value.absent(),
                Value<int> updatedAtUtc = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> cefrLevel = const Value.absent(),
                Value<String> targetWordKeysJson = const Value.absent(),
                Value<String> mixPolicyVersion = const Value.absent(),
                Value<String> contentId = const Value.absent(),
                Value<String> contentVersion = const Value.absent(),
                Value<String> currentStage = const Value.absent(),
                Value<int> startedAtUtc = const Value.absent(),
                Value<int?> completedAtUtc = const Value.absent(),
                Value<int?> abandonedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingSessionsCompanion(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                sessionId: sessionId,
                cefrLevel: cefrLevel,
                targetWordKeysJson: targetWordKeysJson,
                mixPolicyVersion: mixPolicyVersion,
                contentId: contentId,
                contentVersion: contentVersion,
                currentStage: currentStage,
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
                abandonedAtUtc: abandonedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerId,
                Value<int> schemaVersion = const Value.absent(),
                required int createdAtUtc,
                required int updatedAtUtc,
                required String sessionId,
                required String cefrLevel,
                required String targetWordKeysJson,
                required String mixPolicyVersion,
                required String contentId,
                required String contentVersion,
                required String currentStage,
                required int startedAtUtc,
                Value<int?> completedAtUtc = const Value.absent(),
                Value<int?> abandonedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingSessionsCompanion.insert(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                sessionId: sessionId,
                cefrLevel: cefrLevel,
                targetWordKeysJson: targetWordKeysJson,
                mixPolicyVersion: mixPolicyVersion,
                contentId: contentId,
                contentVersion: contentVersion,
                currentStage: currentStage,
                startedAtUtc: startedAtUtc,
                completedAtUtc: completedAtUtc,
                abandonedAtUtc: abandonedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReadingSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LearningDatabase,
      $ReadingSessionsTable,
      ReadingSessionRow,
      $$ReadingSessionsTableFilterComposer,
      $$ReadingSessionsTableOrderingComposer,
      $$ReadingSessionsTableAnnotationComposer,
      $$ReadingSessionsTableCreateCompanionBuilder,
      $$ReadingSessionsTableUpdateCompanionBuilder,
      (
        ReadingSessionRow,
        BaseReferences<
          _$LearningDatabase,
          $ReadingSessionsTable,
          ReadingSessionRow
        >,
      ),
      ReadingSessionRow,
      PrefetchHooks Function()
    >;
typedef $$RecallAttemptsTableCreateCompanionBuilder =
    RecallAttemptsCompanion Function({
      required String ownerId,
      Value<int> schemaVersion,
      required int createdAtUtc,
      required int updatedAtUtc,
      required String attemptId,
      required String sessionId,
      required String wordKey,
      required String recallMode,
      required String cueLevel,
      required bool correctness,
      required int responseTimeMs,
      required int confidence,
      Value<String?> contextId,
      required String algorithmVersion,
      required int occurredAtUtc,
      Value<int> rowid,
    });
typedef $$RecallAttemptsTableUpdateCompanionBuilder =
    RecallAttemptsCompanion Function({
      Value<String> ownerId,
      Value<int> schemaVersion,
      Value<int> createdAtUtc,
      Value<int> updatedAtUtc,
      Value<String> attemptId,
      Value<String> sessionId,
      Value<String> wordKey,
      Value<String> recallMode,
      Value<String> cueLevel,
      Value<bool> correctness,
      Value<int> responseTimeMs,
      Value<int> confidence,
      Value<String?> contextId,
      Value<String> algorithmVersion,
      Value<int> occurredAtUtc,
      Value<int> rowid,
    });

class $$RecallAttemptsTableFilterComposer
    extends Composer<_$LearningDatabase, $RecallAttemptsTable> {
  $$RecallAttemptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wordKey => $composableBuilder(
    column: $table.wordKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recallMode => $composableBuilder(
    column: $table.recallMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cueLevel => $composableBuilder(
    column: $table.cueLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get correctness => $composableBuilder(
    column: $table.correctness,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get responseTimeMs => $composableBuilder(
    column: $table.responseTimeMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contextId => $composableBuilder(
    column: $table.contextId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecallAttemptsTableOrderingComposer
    extends Composer<_$LearningDatabase, $RecallAttemptsTable> {
  $$RecallAttemptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wordKey => $composableBuilder(
    column: $table.wordKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recallMode => $composableBuilder(
    column: $table.recallMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cueLevel => $composableBuilder(
    column: $table.cueLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get correctness => $composableBuilder(
    column: $table.correctness,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get responseTimeMs => $composableBuilder(
    column: $table.responseTimeMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contextId => $composableBuilder(
    column: $table.contextId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecallAttemptsTableAnnotationComposer
    extends Composer<_$LearningDatabase, $RecallAttemptsTable> {
  $$RecallAttemptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attemptId =>
      $composableBuilder(column: $table.attemptId, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get wordKey =>
      $composableBuilder(column: $table.wordKey, builder: (column) => column);

  GeneratedColumn<String> get recallMode => $composableBuilder(
    column: $table.recallMode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cueLevel =>
      $composableBuilder(column: $table.cueLevel, builder: (column) => column);

  GeneratedColumn<bool> get correctness => $composableBuilder(
    column: $table.correctness,
    builder: (column) => column,
  );

  GeneratedColumn<int> get responseTimeMs => $composableBuilder(
    column: $table.responseTimeMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contextId =>
      $composableBuilder(column: $table.contextId, builder: (column) => column);

  GeneratedColumn<String> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => column,
  );
}

class $$RecallAttemptsTableTableManager
    extends
        RootTableManager<
          _$LearningDatabase,
          $RecallAttemptsTable,
          RecallAttemptRow,
          $$RecallAttemptsTableFilterComposer,
          $$RecallAttemptsTableOrderingComposer,
          $$RecallAttemptsTableAnnotationComposer,
          $$RecallAttemptsTableCreateCompanionBuilder,
          $$RecallAttemptsTableUpdateCompanionBuilder,
          (
            RecallAttemptRow,
            BaseReferences<
              _$LearningDatabase,
              $RecallAttemptsTable,
              RecallAttemptRow
            >,
          ),
          RecallAttemptRow,
          PrefetchHooks Function()
        > {
  $$RecallAttemptsTableTableManager(
    _$LearningDatabase db,
    $RecallAttemptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecallAttemptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecallAttemptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecallAttemptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<int> createdAtUtc = const Value.absent(),
                Value<int> updatedAtUtc = const Value.absent(),
                Value<String> attemptId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> wordKey = const Value.absent(),
                Value<String> recallMode = const Value.absent(),
                Value<String> cueLevel = const Value.absent(),
                Value<bool> correctness = const Value.absent(),
                Value<int> responseTimeMs = const Value.absent(),
                Value<int> confidence = const Value.absent(),
                Value<String?> contextId = const Value.absent(),
                Value<String> algorithmVersion = const Value.absent(),
                Value<int> occurredAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecallAttemptsCompanion(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                attemptId: attemptId,
                sessionId: sessionId,
                wordKey: wordKey,
                recallMode: recallMode,
                cueLevel: cueLevel,
                correctness: correctness,
                responseTimeMs: responseTimeMs,
                confidence: confidence,
                contextId: contextId,
                algorithmVersion: algorithmVersion,
                occurredAtUtc: occurredAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerId,
                Value<int> schemaVersion = const Value.absent(),
                required int createdAtUtc,
                required int updatedAtUtc,
                required String attemptId,
                required String sessionId,
                required String wordKey,
                required String recallMode,
                required String cueLevel,
                required bool correctness,
                required int responseTimeMs,
                required int confidence,
                Value<String?> contextId = const Value.absent(),
                required String algorithmVersion,
                required int occurredAtUtc,
                Value<int> rowid = const Value.absent(),
              }) => RecallAttemptsCompanion.insert(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                attemptId: attemptId,
                sessionId: sessionId,
                wordKey: wordKey,
                recallMode: recallMode,
                cueLevel: cueLevel,
                correctness: correctness,
                responseTimeMs: responseTimeMs,
                confidence: confidence,
                contextId: contextId,
                algorithmVersion: algorithmVersion,
                occurredAtUtc: occurredAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecallAttemptsTableProcessedTableManager =
    ProcessedTableManager<
      _$LearningDatabase,
      $RecallAttemptsTable,
      RecallAttemptRow,
      $$RecallAttemptsTableFilterComposer,
      $$RecallAttemptsTableOrderingComposer,
      $$RecallAttemptsTableAnnotationComposer,
      $$RecallAttemptsTableCreateCompanionBuilder,
      $$RecallAttemptsTableUpdateCompanionBuilder,
      (
        RecallAttemptRow,
        BaseReferences<
          _$LearningDatabase,
          $RecallAttemptsTable,
          RecallAttemptRow
        >,
      ),
      RecallAttemptRow,
      PrefetchHooks Function()
    >;
typedef $$MemoryStatesTableCreateCompanionBuilder =
    MemoryStatesCompanion Function({
      required String ownerId,
      Value<int> schemaVersion,
      required int createdAtUtc,
      required int updatedAtUtc,
      required String wordKey,
      required double strength,
      required double cueDependency,
      required double stability,
      required double difficulty,
      required int lapseCount,
      Value<int?> lastReviewedAtUtc,
      required int nextDueAtUtc,
      Value<String?> lastErrorType,
      required String algorithmVersion,
      Value<int> rowid,
    });
typedef $$MemoryStatesTableUpdateCompanionBuilder =
    MemoryStatesCompanion Function({
      Value<String> ownerId,
      Value<int> schemaVersion,
      Value<int> createdAtUtc,
      Value<int> updatedAtUtc,
      Value<String> wordKey,
      Value<double> strength,
      Value<double> cueDependency,
      Value<double> stability,
      Value<double> difficulty,
      Value<int> lapseCount,
      Value<int?> lastReviewedAtUtc,
      Value<int> nextDueAtUtc,
      Value<String?> lastErrorType,
      Value<String> algorithmVersion,
      Value<int> rowid,
    });

class $$MemoryStatesTableFilterComposer
    extends Composer<_$LearningDatabase, $MemoryStatesTable> {
  $$MemoryStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wordKey => $composableBuilder(
    column: $table.wordKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get strength => $composableBuilder(
    column: $table.strength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cueDependency => $composableBuilder(
    column: $table.cueDependency,
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

  ColumnFilters<int> get lapseCount => $composableBuilder(
    column: $table.lapseCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReviewedAtUtc => $composableBuilder(
    column: $table.lastReviewedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextDueAtUtc => $composableBuilder(
    column: $table.nextDueAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorType => $composableBuilder(
    column: $table.lastErrorType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MemoryStatesTableOrderingComposer
    extends Composer<_$LearningDatabase, $MemoryStatesTable> {
  $$MemoryStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wordKey => $composableBuilder(
    column: $table.wordKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get strength => $composableBuilder(
    column: $table.strength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cueDependency => $composableBuilder(
    column: $table.cueDependency,
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

  ColumnOrderings<int> get lapseCount => $composableBuilder(
    column: $table.lapseCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReviewedAtUtc => $composableBuilder(
    column: $table.lastReviewedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextDueAtUtc => $composableBuilder(
    column: $table.nextDueAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorType => $composableBuilder(
    column: $table.lastErrorType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MemoryStatesTableAnnotationComposer
    extends Composer<_$LearningDatabase, $MemoryStatesTable> {
  $$MemoryStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get wordKey =>
      $composableBuilder(column: $table.wordKey, builder: (column) => column);

  GeneratedColumn<double> get strength =>
      $composableBuilder(column: $table.strength, builder: (column) => column);

  GeneratedColumn<double> get cueDependency => $composableBuilder(
    column: $table.cueDependency,
    builder: (column) => column,
  );

  GeneratedColumn<double> get stability =>
      $composableBuilder(column: $table.stability, builder: (column) => column);

  GeneratedColumn<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lapseCount => $composableBuilder(
    column: $table.lapseCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReviewedAtUtc => $composableBuilder(
    column: $table.lastReviewedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get nextDueAtUtc => $composableBuilder(
    column: $table.nextDueAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorType => $composableBuilder(
    column: $table.lastErrorType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get algorithmVersion => $composableBuilder(
    column: $table.algorithmVersion,
    builder: (column) => column,
  );
}

class $$MemoryStatesTableTableManager
    extends
        RootTableManager<
          _$LearningDatabase,
          $MemoryStatesTable,
          MemoryStateRow,
          $$MemoryStatesTableFilterComposer,
          $$MemoryStatesTableOrderingComposer,
          $$MemoryStatesTableAnnotationComposer,
          $$MemoryStatesTableCreateCompanionBuilder,
          $$MemoryStatesTableUpdateCompanionBuilder,
          (
            MemoryStateRow,
            BaseReferences<
              _$LearningDatabase,
              $MemoryStatesTable,
              MemoryStateRow
            >,
          ),
          MemoryStateRow,
          PrefetchHooks Function()
        > {
  $$MemoryStatesTableTableManager(
    _$LearningDatabase db,
    $MemoryStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemoryStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemoryStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemoryStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<int> createdAtUtc = const Value.absent(),
                Value<int> updatedAtUtc = const Value.absent(),
                Value<String> wordKey = const Value.absent(),
                Value<double> strength = const Value.absent(),
                Value<double> cueDependency = const Value.absent(),
                Value<double> stability = const Value.absent(),
                Value<double> difficulty = const Value.absent(),
                Value<int> lapseCount = const Value.absent(),
                Value<int?> lastReviewedAtUtc = const Value.absent(),
                Value<int> nextDueAtUtc = const Value.absent(),
                Value<String?> lastErrorType = const Value.absent(),
                Value<String> algorithmVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoryStatesCompanion(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                wordKey: wordKey,
                strength: strength,
                cueDependency: cueDependency,
                stability: stability,
                difficulty: difficulty,
                lapseCount: lapseCount,
                lastReviewedAtUtc: lastReviewedAtUtc,
                nextDueAtUtc: nextDueAtUtc,
                lastErrorType: lastErrorType,
                algorithmVersion: algorithmVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerId,
                Value<int> schemaVersion = const Value.absent(),
                required int createdAtUtc,
                required int updatedAtUtc,
                required String wordKey,
                required double strength,
                required double cueDependency,
                required double stability,
                required double difficulty,
                required int lapseCount,
                Value<int?> lastReviewedAtUtc = const Value.absent(),
                required int nextDueAtUtc,
                Value<String?> lastErrorType = const Value.absent(),
                required String algorithmVersion,
                Value<int> rowid = const Value.absent(),
              }) => MemoryStatesCompanion.insert(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                wordKey: wordKey,
                strength: strength,
                cueDependency: cueDependency,
                stability: stability,
                difficulty: difficulty,
                lapseCount: lapseCount,
                lastReviewedAtUtc: lastReviewedAtUtc,
                nextDueAtUtc: nextDueAtUtc,
                lastErrorType: lastErrorType,
                algorithmVersion: algorithmVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MemoryStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$LearningDatabase,
      $MemoryStatesTable,
      MemoryStateRow,
      $$MemoryStatesTableFilterComposer,
      $$MemoryStatesTableOrderingComposer,
      $$MemoryStatesTableAnnotationComposer,
      $$MemoryStatesTableCreateCompanionBuilder,
      $$MemoryStatesTableUpdateCompanionBuilder,
      (
        MemoryStateRow,
        BaseReferences<_$LearningDatabase, $MemoryStatesTable, MemoryStateRow>,
      ),
      MemoryStateRow,
      PrefetchHooks Function()
    >;
typedef $$LearningEventsTableCreateCompanionBuilder =
    LearningEventsCompanion Function({
      required String ownerId,
      Value<int> schemaVersion,
      required int createdAtUtc,
      required int updatedAtUtc,
      required String eventId,
      required int occurredAtUtc,
      required String activity,
      required String contentId,
      Value<String?> categoryId,
      Value<String?> cefrLevel,
      required String skill,
      required bool correct,
      required int score,
      Value<int?> responseTimeMs,
      required int attemptNumber,
      required String appVersion,
      required String buildId,
      Value<int> rowid,
    });
typedef $$LearningEventsTableUpdateCompanionBuilder =
    LearningEventsCompanion Function({
      Value<String> ownerId,
      Value<int> schemaVersion,
      Value<int> createdAtUtc,
      Value<int> updatedAtUtc,
      Value<String> eventId,
      Value<int> occurredAtUtc,
      Value<String> activity,
      Value<String> contentId,
      Value<String?> categoryId,
      Value<String?> cefrLevel,
      Value<String> skill,
      Value<bool> correct,
      Value<int> score,
      Value<int?> responseTimeMs,
      Value<int> attemptNumber,
      Value<String> appVersion,
      Value<String> buildId,
      Value<int> rowid,
    });

class $$LearningEventsTableFilterComposer
    extends Composer<_$LearningDatabase, $LearningEventsTable> {
  $$LearningEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activity => $composableBuilder(
    column: $table.activity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentId => $composableBuilder(
    column: $table.contentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cefrLevel => $composableBuilder(
    column: $table.cefrLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get skill => $composableBuilder(
    column: $table.skill,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get correct => $composableBuilder(
    column: $table.correct,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get score => $composableBuilder(
    column: $table.score,
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

  ColumnFilters<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get buildId => $composableBuilder(
    column: $table.buildId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LearningEventsTableOrderingComposer
    extends Composer<_$LearningDatabase, $LearningEventsTable> {
  $$LearningEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activity => $composableBuilder(
    column: $table.activity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentId => $composableBuilder(
    column: $table.contentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cefrLevel => $composableBuilder(
    column: $table.cefrLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get skill => $composableBuilder(
    column: $table.skill,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get correct => $composableBuilder(
    column: $table.correct,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get score => $composableBuilder(
    column: $table.score,
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

  ColumnOrderings<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get buildId => $composableBuilder(
    column: $table.buildId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LearningEventsTableAnnotationComposer
    extends Composer<_$LearningDatabase, $LearningEventsTable> {
  $$LearningEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<int> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get activity =>
      $composableBuilder(column: $table.activity, builder: (column) => column);

  GeneratedColumn<String> get contentId =>
      $composableBuilder(column: $table.contentId, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cefrLevel =>
      $composableBuilder(column: $table.cefrLevel, builder: (column) => column);

  GeneratedColumn<String> get skill =>
      $composableBuilder(column: $table.skill, builder: (column) => column);

  GeneratedColumn<bool> get correct =>
      $composableBuilder(column: $table.correct, builder: (column) => column);

  GeneratedColumn<int> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<int> get responseTimeMs => $composableBuilder(
    column: $table.responseTimeMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptNumber => $composableBuilder(
    column: $table.attemptNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get buildId =>
      $composableBuilder(column: $table.buildId, builder: (column) => column);
}

class $$LearningEventsTableTableManager
    extends
        RootTableManager<
          _$LearningDatabase,
          $LearningEventsTable,
          LearningEventRow,
          $$LearningEventsTableFilterComposer,
          $$LearningEventsTableOrderingComposer,
          $$LearningEventsTableAnnotationComposer,
          $$LearningEventsTableCreateCompanionBuilder,
          $$LearningEventsTableUpdateCompanionBuilder,
          (
            LearningEventRow,
            BaseReferences<
              _$LearningDatabase,
              $LearningEventsTable,
              LearningEventRow
            >,
          ),
          LearningEventRow,
          PrefetchHooks Function()
        > {
  $$LearningEventsTableTableManager(
    _$LearningDatabase db,
    $LearningEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LearningEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LearningEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LearningEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<int> createdAtUtc = const Value.absent(),
                Value<int> updatedAtUtc = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<int> occurredAtUtc = const Value.absent(),
                Value<String> activity = const Value.absent(),
                Value<String> contentId = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> cefrLevel = const Value.absent(),
                Value<String> skill = const Value.absent(),
                Value<bool> correct = const Value.absent(),
                Value<int> score = const Value.absent(),
                Value<int?> responseTimeMs = const Value.absent(),
                Value<int> attemptNumber = const Value.absent(),
                Value<String> appVersion = const Value.absent(),
                Value<String> buildId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LearningEventsCompanion(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                eventId: eventId,
                occurredAtUtc: occurredAtUtc,
                activity: activity,
                contentId: contentId,
                categoryId: categoryId,
                cefrLevel: cefrLevel,
                skill: skill,
                correct: correct,
                score: score,
                responseTimeMs: responseTimeMs,
                attemptNumber: attemptNumber,
                appVersion: appVersion,
                buildId: buildId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerId,
                Value<int> schemaVersion = const Value.absent(),
                required int createdAtUtc,
                required int updatedAtUtc,
                required String eventId,
                required int occurredAtUtc,
                required String activity,
                required String contentId,
                Value<String?> categoryId = const Value.absent(),
                Value<String?> cefrLevel = const Value.absent(),
                required String skill,
                required bool correct,
                required int score,
                Value<int?> responseTimeMs = const Value.absent(),
                required int attemptNumber,
                required String appVersion,
                required String buildId,
                Value<int> rowid = const Value.absent(),
              }) => LearningEventsCompanion.insert(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                eventId: eventId,
                occurredAtUtc: occurredAtUtc,
                activity: activity,
                contentId: contentId,
                categoryId: categoryId,
                cefrLevel: cefrLevel,
                skill: skill,
                correct: correct,
                score: score,
                responseTimeMs: responseTimeMs,
                attemptNumber: attemptNumber,
                appVersion: appVersion,
                buildId: buildId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LearningEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$LearningDatabase,
      $LearningEventsTable,
      LearningEventRow,
      $$LearningEventsTableFilterComposer,
      $$LearningEventsTableOrderingComposer,
      $$LearningEventsTableAnnotationComposer,
      $$LearningEventsTableCreateCompanionBuilder,
      $$LearningEventsTableUpdateCompanionBuilder,
      (
        LearningEventRow,
        BaseReferences<
          _$LearningDatabase,
          $LearningEventsTable,
          LearningEventRow
        >,
      ),
      LearningEventRow,
      PrefetchHooks Function()
    >;
typedef $$SyncOutboxTableCreateCompanionBuilder =
    SyncOutboxCompanion Function({
      required String ownerId,
      Value<int> schemaVersion,
      required int createdAtUtc,
      required int updatedAtUtc,
      required String outboxId,
      required String eventId,
      required String operation,
      required String payloadJson,
      Value<int?> acknowledgedAtUtc,
      required int attemptCount,
      Value<int> rowid,
    });
typedef $$SyncOutboxTableUpdateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<String> ownerId,
      Value<int> schemaVersion,
      Value<int> createdAtUtc,
      Value<int> updatedAtUtc,
      Value<String> outboxId,
      Value<String> eventId,
      Value<String> operation,
      Value<String> payloadJson,
      Value<int?> acknowledgedAtUtc,
      Value<int> attemptCount,
      Value<int> rowid,
    });

class $$SyncOutboxTableFilterComposer
    extends Composer<_$LearningDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outboxId => $composableBuilder(
    column: $table.outboxId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acknowledgedAtUtc => $composableBuilder(
    column: $table.acknowledgedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends Composer<_$LearningDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outboxId => $composableBuilder(
    column: $table.outboxId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acknowledgedAtUtc => $composableBuilder(
    column: $table.acknowledgedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends Composer<_$LearningDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get outboxId =>
      $composableBuilder(column: $table.outboxId, builder: (column) => column);

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get acknowledgedAtUtc => $composableBuilder(
    column: $table.acknowledgedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );
}

class $$SyncOutboxTableTableManager
    extends
        RootTableManager<
          _$LearningDatabase,
          $SyncOutboxTable,
          SyncOutboxRow,
          $$SyncOutboxTableFilterComposer,
          $$SyncOutboxTableOrderingComposer,
          $$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (
            SyncOutboxRow,
            BaseReferences<_$LearningDatabase, $SyncOutboxTable, SyncOutboxRow>,
          ),
          SyncOutboxRow,
          PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(_$LearningDatabase db, $SyncOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<int> createdAtUtc = const Value.absent(),
                Value<int> updatedAtUtc = const Value.absent(),
                Value<String> outboxId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int?> acknowledgedAtUtc = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                outboxId: outboxId,
                eventId: eventId,
                operation: operation,
                payloadJson: payloadJson,
                acknowledgedAtUtc: acknowledgedAtUtc,
                attemptCount: attemptCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerId,
                Value<int> schemaVersion = const Value.absent(),
                required int createdAtUtc,
                required int updatedAtUtc,
                required String outboxId,
                required String eventId,
                required String operation,
                required String payloadJson,
                Value<int?> acknowledgedAtUtc = const Value.absent(),
                required int attemptCount,
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion.insert(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                outboxId: outboxId,
                eventId: eventId,
                operation: operation,
                payloadJson: payloadJson,
                acknowledgedAtUtc: acknowledgedAtUtc,
                attemptCount: attemptCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$LearningDatabase,
      $SyncOutboxTable,
      SyncOutboxRow,
      $$SyncOutboxTableFilterComposer,
      $$SyncOutboxTableOrderingComposer,
      $$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (
        SyncOutboxRow,
        BaseReferences<_$LearningDatabase, $SyncOutboxTable, SyncOutboxRow>,
      ),
      SyncOutboxRow,
      PrefetchHooks Function()
    >;
typedef $$DeletionTombstonesTableCreateCompanionBuilder =
    DeletionTombstonesCompanion Function({
      required String ownerId,
      Value<int> schemaVersion,
      required int createdAtUtc,
      required int updatedAtUtc,
      required String tombstoneId,
      required String entityType,
      required String entityId,
      required int deletedAtUtc,
      Value<int> rowid,
    });
typedef $$DeletionTombstonesTableUpdateCompanionBuilder =
    DeletionTombstonesCompanion Function({
      Value<String> ownerId,
      Value<int> schemaVersion,
      Value<int> createdAtUtc,
      Value<int> updatedAtUtc,
      Value<String> tombstoneId,
      Value<String> entityType,
      Value<String> entityId,
      Value<int> deletedAtUtc,
      Value<int> rowid,
    });

class $$DeletionTombstonesTableFilterComposer
    extends Composer<_$LearningDatabase, $DeletionTombstonesTable> {
  $$DeletionTombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tombstoneId => $composableBuilder(
    column: $table.tombstoneId,
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

  ColumnFilters<int> get deletedAtUtc => $composableBuilder(
    column: $table.deletedAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DeletionTombstonesTableOrderingComposer
    extends Composer<_$LearningDatabase, $DeletionTombstonesTable> {
  $$DeletionTombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tombstoneId => $composableBuilder(
    column: $table.tombstoneId,
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

  ColumnOrderings<int> get deletedAtUtc => $composableBuilder(
    column: $table.deletedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeletionTombstonesTableAnnotationComposer
    extends Composer<_$LearningDatabase, $DeletionTombstonesTable> {
  $$DeletionTombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tombstoneId => $composableBuilder(
    column: $table.tombstoneId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<int> get deletedAtUtc => $composableBuilder(
    column: $table.deletedAtUtc,
    builder: (column) => column,
  );
}

class $$DeletionTombstonesTableTableManager
    extends
        RootTableManager<
          _$LearningDatabase,
          $DeletionTombstonesTable,
          DeletionTombstoneRow,
          $$DeletionTombstonesTableFilterComposer,
          $$DeletionTombstonesTableOrderingComposer,
          $$DeletionTombstonesTableAnnotationComposer,
          $$DeletionTombstonesTableCreateCompanionBuilder,
          $$DeletionTombstonesTableUpdateCompanionBuilder,
          (
            DeletionTombstoneRow,
            BaseReferences<
              _$LearningDatabase,
              $DeletionTombstonesTable,
              DeletionTombstoneRow
            >,
          ),
          DeletionTombstoneRow,
          PrefetchHooks Function()
        > {
  $$DeletionTombstonesTableTableManager(
    _$LearningDatabase db,
    $DeletionTombstonesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeletionTombstonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeletionTombstonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeletionTombstonesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<int> createdAtUtc = const Value.absent(),
                Value<int> updatedAtUtc = const Value.absent(),
                Value<String> tombstoneId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<int> deletedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeletionTombstonesCompanion(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                tombstoneId: tombstoneId,
                entityType: entityType,
                entityId: entityId,
                deletedAtUtc: deletedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerId,
                Value<int> schemaVersion = const Value.absent(),
                required int createdAtUtc,
                required int updatedAtUtc,
                required String tombstoneId,
                required String entityType,
                required String entityId,
                required int deletedAtUtc,
                Value<int> rowid = const Value.absent(),
              }) => DeletionTombstonesCompanion.insert(
                ownerId: ownerId,
                schemaVersion: schemaVersion,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                tombstoneId: tombstoneId,
                entityType: entityType,
                entityId: entityId,
                deletedAtUtc: deletedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeletionTombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$LearningDatabase,
      $DeletionTombstonesTable,
      DeletionTombstoneRow,
      $$DeletionTombstonesTableFilterComposer,
      $$DeletionTombstonesTableOrderingComposer,
      $$DeletionTombstonesTableAnnotationComposer,
      $$DeletionTombstonesTableCreateCompanionBuilder,
      $$DeletionTombstonesTableUpdateCompanionBuilder,
      (
        DeletionTombstoneRow,
        BaseReferences<
          _$LearningDatabase,
          $DeletionTombstonesTable,
          DeletionTombstoneRow
        >,
      ),
      DeletionTombstoneRow,
      PrefetchHooks Function()
    >;

class $LearningDatabaseManager {
  final _$LearningDatabase _db;
  $LearningDatabaseManager(this._db);
  $$LearningCommitsTableTableManager get learningCommits =>
      $$LearningCommitsTableTableManager(_db, _db.learningCommits);
  $$AssociationsTableTableManager get associations =>
      $$AssociationsTableTableManager(_db, _db.associations);
  $$ReadingSessionsTableTableManager get readingSessions =>
      $$ReadingSessionsTableTableManager(_db, _db.readingSessions);
  $$RecallAttemptsTableTableManager get recallAttempts =>
      $$RecallAttemptsTableTableManager(_db, _db.recallAttempts);
  $$MemoryStatesTableTableManager get memoryStates =>
      $$MemoryStatesTableTableManager(_db, _db.memoryStates);
  $$LearningEventsTableTableManager get learningEvents =>
      $$LearningEventsTableTableManager(_db, _db.learningEvents);
  $$SyncOutboxTableTableManager get syncOutbox =>
      $$SyncOutboxTableTableManager(_db, _db.syncOutbox);
  $$DeletionTombstonesTableTableManager get deletionTombstones =>
      $$DeletionTombstonesTableTableManager(_db, _db.deletionTombstones);
}
