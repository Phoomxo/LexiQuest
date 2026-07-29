import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:sqlite3/common.dart';

import '../association_record.dart';
import '../deletion_tombstone.dart';
import '../learning_commit.dart';
import '../learning_event.dart';
import '../learning_repository.dart';
import '../memory_state.dart';
import '../reading_session.dart';
import '../recall_attempt.dart';
import '../sync_outbox_entry.dart';
import 'learning_database.dart';

final class DriftLearningRepository
    implements LearningRepository, LearningReader {
  DriftLearningRepository(this._database);

  final LearningDatabase _database;

  @override
  Future<CommitResult> commit(LearningCommit commit) async {
    final fingerprint = _fingerprint(commit);
    try {
      return await _database.transaction(() async {
        final existing =
            await (_database.select(_database.learningCommits)..where(
                  (row) =>
                      row.ownerId.equals(commit.ownerId) &
                      row.commitId.equals(commit.commitId),
                ))
                .getSingleOrNull();
        if (existing != null) {
          if (existing.contentFingerprint != fingerprint) {
            throw const LearningRepositoryException(
              LearningRepositoryErrorCode.idempotencyConflict,
              'A commit identifier was reused with different content.',
            );
          }
          return CommitResult(
            commitId: commit.commitId,
            disposition: CommitDisposition.alreadyApplied,
            writtenRecords: 0,
          );
        }

        await _writeAssociations(commit.associations);
        await _writeSessions(commit.sessions);
        await _writeRecallAttempts(commit.recallAttempts);
        await _writeMemoryStates(commit.memoryStates);
        await _writeLearningEvents(commit.learningEvents);
        await _writeOutbox(commit.outboxEntries);
        await _writeTombstones(commit.tombstones);

        final recordedAt = _epoch(commit.recordedAtUtc);
        await _database
            .into(_database.learningCommits)
            .insert(
              LearningCommitsCompanion.insert(
                ownerId: commit.ownerId,
                schemaVersion: const Value(1),
                createdAtUtc: recordedAt,
                updatedAtUtc: recordedAt,
                commitId: commit.commitId,
                recordedAtUtc: recordedAt,
                recordCount: commit.recordCount,
                contentFingerprint: fingerprint,
              ),
            );

        return CommitResult(
          commitId: commit.commitId,
          disposition: CommitDisposition.applied,
          writtenRecords: commit.recordCount,
        );
      });
    } on LearningRepositoryException {
      rethrow;
    } on SqliteException catch (error) {
      throw LearningRepositoryException(
        LearningRepositoryErrorCode.writeConflict,
        'The local transaction was rejected (${error.resultCode}).',
      );
    } on Object {
      throw const LearningRepositoryException(
        LearningRepositoryErrorCode.unavailable,
        'The local learning store is unavailable.',
      );
    }
  }

  @override
  Future<List<AssociationRecord>> readAssociations({
    required String ownerId,
    required String wordKey,
  }) async {
    try {
      final rows =
          await (_database.select(_database.associations)
                ..where(
                  (row) =>
                      row.ownerId.equals(ownerId) & row.wordKey.equals(wordKey),
                )
                ..orderBy([
                  (row) => OrderingTerm.desc(row.updatedAtUtc),
                  (row) => OrderingTerm.asc(row.associationId),
                ]))
              .get();
      return rows.map(_associationFromRow).toList(growable: false);
    } on LearningRepositoryException {
      rethrow;
    } on Object {
      throw const LearningRepositoryException(
        LearningRepositoryErrorCode.invalidStoredData,
        'Stored associations could not be read.',
      );
    }
  }

  @override
  Future<ReadingSession?> readSession({
    required String ownerId,
    required String sessionId,
  }) async {
    try {
      final row =
          await (_database.select(_database.readingSessions)..where(
                (candidate) =>
                    candidate.ownerId.equals(ownerId) &
                    candidate.sessionId.equals(sessionId),
              ))
              .getSingleOrNull();
      return row == null ? null : _sessionFromRow(row);
    } on Object {
      throw const LearningRepositoryException(
        LearningRepositoryErrorCode.invalidStoredData,
        'The stored reading session could not be read.',
      );
    }
  }

  @override
  Future<MemoryState?> readMemoryState({
    required String ownerId,
    required String wordKey,
  }) async {
    try {
      final row =
          await (_database.select(_database.memoryStates)..where(
                (candidate) =>
                    candidate.ownerId.equals(ownerId) &
                    candidate.wordKey.equals(wordKey),
              ))
              .getSingleOrNull();
      return row == null ? null : _memoryFromRow(row);
    } on Object {
      throw const LearningRepositoryException(
        LearningRepositoryErrorCode.invalidStoredData,
        'The stored memory state could not be read.',
      );
    }
  }

  @override
  Future<List<SyncOutboxEntry>> readPendingOutbox({
    required String ownerId,
  }) async {
    try {
      final rows =
          await (_database.select(_database.syncOutbox)
                ..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.acknowledgedAtUtc.isNull(),
                )
                ..orderBy([
                  (row) => OrderingTerm.asc(row.createdAtUtc),
                  (row) => OrderingTerm.asc(row.outboxId),
                ]))
              .get();
      return rows.map(_outboxFromRow).toList(growable: false);
    } on Object {
      throw const LearningRepositoryException(
        LearningRepositoryErrorCode.invalidStoredData,
        'The stored outbox could not be read.',
      );
    }
  }

  Future<void> _writeAssociations(List<AssociationRecord> records) async {
    for (final record in records) {
      await _database
          .into(_database.associations)
          .insertOnConflictUpdate(
            AssociationsCompanion.insert(
              ownerId: record.ownerId,
              schemaVersion: Value(record.schemaVersion),
              createdAtUtc: _epoch(record.createdAtUtc),
              updatedAtUtc: _epoch(record.updatedAtUtc),
              associationId: record.associationId,
              wordKey: record.wordKey,
              cueType: record.cueType.name,
              cueText: record.cueText,
              origin: record.origin.name,
              strength: record.strength,
              successCount: record.successCount,
              failureCount: record.failureCount,
            ),
          );
    }
  }

  Future<void> _writeSessions(List<ReadingSession> records) async {
    for (final record in records) {
      await _database
          .into(_database.readingSessions)
          .insertOnConflictUpdate(
            ReadingSessionsCompanion.insert(
              ownerId: record.ownerId,
              schemaVersion: Value(record.schemaVersion),
              createdAtUtc: _epoch(record.startedAtUtc),
              updatedAtUtc: _epoch(record.updatedAtUtc),
              sessionId: record.sessionId,
              cefrLevel: record.cefrLevel,
              targetWordKeysJson: jsonEncode(record.targetWordKeys),
              mixPolicyVersion: record.mixPolicyVersion,
              contentId: record.contentId,
              contentVersion: record.contentVersion,
              currentStage: record.currentStage.name,
              startedAtUtc: _epoch(record.startedAtUtc),
              completedAtUtc: Value(_optionalEpoch(record.completedAtUtc)),
              abandonedAtUtc: Value(_optionalEpoch(record.abandonedAtUtc)),
            ),
          );
    }
  }

  Future<void> _writeRecallAttempts(List<RecallAttempt> records) async {
    for (final record in records) {
      final occurredAt = _epoch(record.occurredAtUtc);
      await _database
          .into(_database.recallAttempts)
          .insert(
            RecallAttemptsCompanion.insert(
              ownerId: record.ownerId,
              schemaVersion: Value(record.schemaVersion),
              createdAtUtc: occurredAt,
              updatedAtUtc: occurredAt,
              attemptId: record.attemptId,
              sessionId: record.sessionId,
              wordKey: record.wordKey,
              recallMode: record.recallMode.name,
              cueLevel: record.cueLevel.name,
              correctness: record.correctness,
              responseTimeMs: record.responseTimeMs,
              confidence: record.confidence,
              contextId: Value(record.contextId),
              algorithmVersion: record.algorithmVersion,
              occurredAtUtc: occurredAt,
            ),
          );
    }
  }

  Future<void> _writeMemoryStates(List<MemoryState> records) async {
    for (final record in records) {
      final existing =
          await (_database.select(_database.memoryStates)..where(
                (row) =>
                    row.ownerId.equals(record.ownerId) &
                    row.wordKey.equals(record.wordKey),
              ))
              .getSingleOrNull();
      await _database
          .into(_database.memoryStates)
          .insertOnConflictUpdate(
            MemoryStatesCompanion.insert(
              ownerId: record.ownerId,
              schemaVersion: Value(record.schemaVersion),
              createdAtUtc:
                  existing?.createdAtUtc ?? _epoch(record.updatedAtUtc),
              updatedAtUtc: _epoch(record.updatedAtUtc),
              wordKey: record.wordKey,
              strength: record.strength,
              cueDependency: record.cueDependency,
              stability: record.stability,
              difficulty: record.difficulty,
              lapseCount: record.lapseCount,
              lastReviewedAtUtc: Value(
                _optionalEpoch(record.lastReviewedAtUtc),
              ),
              nextDueAtUtc: _epoch(record.nextDueAtUtc),
              lastErrorType: Value(record.lastErrorType),
              algorithmVersion: record.algorithmVersion,
            ),
          );
    }
  }

  Future<void> _writeLearningEvents(List<LearningEvent> records) async {
    for (final record in records) {
      final occurredAt = _epoch(record.occurredAtUtc);
      await _database
          .into(_database.learningEvents)
          .insert(
            LearningEventsCompanion.insert(
              ownerId: record.pseudonymousUserId,
              schemaVersion: Value(record.schemaVersion),
              createdAtUtc: occurredAt,
              updatedAtUtc: occurredAt,
              eventId: record.eventId,
              occurredAtUtc: occurredAt,
              activity: record.activity.wireName,
              contentId: record.contentId,
              categoryId: Value(record.categoryId),
              cefrLevel: Value(record.cefrLevel),
              skill: record.skill.wireName,
              correct: record.correct,
              score: record.score,
              responseTimeMs: Value(record.responseTimeMs),
              attemptNumber: record.attemptNumber,
              appVersion: record.appVersion,
              buildId: record.buildId,
            ),
          );
    }
  }

  Future<void> _writeOutbox(List<SyncOutboxEntry> records) async {
    for (final record in records) {
      await _database
          .into(_database.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              ownerId: record.ownerId,
              schemaVersion: Value(record.schemaVersion),
              createdAtUtc: _epoch(record.createdAtUtc),
              updatedAtUtc: _epoch(record.createdAtUtc),
              outboxId: record.outboxId,
              eventId: record.eventId,
              operation: record.operation.name,
              payloadJson: record.payloadJson,
              acknowledgedAtUtc: Value(
                _optionalEpoch(record.acknowledgedAtUtc),
              ),
              attemptCount: record.attemptCount,
            ),
          );
    }
  }

  Future<void> _writeTombstones(List<DeletionTombstone> records) async {
    for (final record in records) {
      final deletedAt = _epoch(record.deletedAtUtc);
      if (record.entityType == TombstoneEntityType.association) {
        await (_database.delete(_database.associations)..where(
              (row) =>
                  row.ownerId.equals(record.ownerId) &
                  row.associationId.equals(record.entityId),
            ))
            .go();
      }
      await _database
          .into(_database.deletionTombstones)
          .insert(
            DeletionTombstonesCompanion.insert(
              ownerId: record.ownerId,
              schemaVersion: Value(record.schemaVersion),
              createdAtUtc: deletedAt,
              updatedAtUtc: deletedAt,
              tombstoneId: record.tombstoneId,
              entityType: record.entityType.name,
              entityId: record.entityId,
              deletedAtUtc: deletedAt,
            ),
          );
    }
  }
}

AssociationRecord _associationFromRow(AssociationRow row) {
  return AssociationRecord(
    associationId: row.associationId,
    ownerId: row.ownerId,
    wordKey: row.wordKey,
    cueType: AssociationCueType.values.byName(row.cueType),
    cueText: row.cueText,
    origin: AssociationOrigin.values.byName(row.origin),
    strength: row.strength,
    successCount: row.successCount,
    failureCount: row.failureCount,
    createdAtUtc: _dateTime(row.createdAtUtc),
    updatedAtUtc: _dateTime(row.updatedAtUtc),
    schemaVersion: row.schemaVersion,
  );
}

ReadingSession _sessionFromRow(ReadingSessionRow row) {
  final decodedTargets = jsonDecode(row.targetWordKeysJson);
  if (decodedTargets is! List<dynamic> ||
      decodedTargets.any((value) => value is! String)) {
    throw const FormatException('targetWordKeysJson must be a string list');
  }
  return ReadingSession(
    sessionId: row.sessionId,
    ownerId: row.ownerId,
    cefrLevel: row.cefrLevel,
    targetWordKeys: decodedTargets.cast<String>(),
    mixPolicyVersion: row.mixPolicyVersion,
    contentId: row.contentId,
    contentVersion: row.contentVersion,
    currentStage: ReadingSessionStage.values.byName(row.currentStage),
    startedAtUtc: _dateTime(row.startedAtUtc),
    updatedAtUtc: _dateTime(row.updatedAtUtc),
    completedAtUtc: _optionalDateTime(row.completedAtUtc),
    abandonedAtUtc: _optionalDateTime(row.abandonedAtUtc),
    schemaVersion: row.schemaVersion,
  );
}

MemoryState _memoryFromRow(MemoryStateRow row) {
  return MemoryState(
    ownerId: row.ownerId,
    wordKey: row.wordKey,
    strength: row.strength,
    cueDependency: row.cueDependency,
    stability: row.stability,
    difficulty: row.difficulty,
    lapseCount: row.lapseCount,
    lastReviewedAtUtc: _optionalDateTime(row.lastReviewedAtUtc),
    nextDueAtUtc: _dateTime(row.nextDueAtUtc),
    lastErrorType: row.lastErrorType,
    algorithmVersion: row.algorithmVersion,
    updatedAtUtc: _dateTime(row.updatedAtUtc),
    schemaVersion: row.schemaVersion,
  );
}

SyncOutboxEntry _outboxFromRow(SyncOutboxRow row) {
  return SyncOutboxEntry(
    outboxId: row.outboxId,
    ownerId: row.ownerId,
    eventId: row.eventId,
    operation: OutboxOperation.values.byName(row.operation),
    payloadJson: row.payloadJson,
    createdAtUtc: _dateTime(row.createdAtUtc),
    acknowledgedAtUtc: _optionalDateTime(row.acknowledgedAtUtc),
    attemptCount: row.attemptCount,
    schemaVersion: row.schemaVersion,
  );
}

String _fingerprint(LearningCommit commit) {
  final canonical = <String, Object?>{
    'commitId': commit.commitId,
    'ownerId': commit.ownerId,
    'recordedAtUtc': commit.recordedAtUtc.toIso8601String(),
    'associations': commit.associations.map((record) {
      return <String, Object?>{
        'id': record.associationId,
        'word': record.wordKey,
        'type': record.cueType.name,
        'text': record.cueText,
        'origin': record.origin.name,
        'strength': record.strength,
        'success': record.successCount,
        'failure': record.failureCount,
        'created': record.createdAtUtc.toIso8601String(),
        'updated': record.updatedAtUtc.toIso8601String(),
        'schema': record.schemaVersion,
      };
    }).toList(),
    'sessions': commit.sessions.map((record) {
      return <String, Object?>{
        'id': record.sessionId,
        'cefr': record.cefrLevel,
        'words': record.targetWordKeys,
        'mix': record.mixPolicyVersion,
        'content': record.contentId,
        'contentVersion': record.contentVersion,
        'stage': record.currentStage.name,
        'started': record.startedAtUtc.toIso8601String(),
        'updated': record.updatedAtUtc.toIso8601String(),
        'completed': record.completedAtUtc?.toIso8601String(),
        'abandoned': record.abandonedAtUtc?.toIso8601String(),
        'schema': record.schemaVersion,
      };
    }).toList(),
    'attempts': commit.recallAttempts.map((record) {
      return <String, Object?>{
        'id': record.attemptId,
        'session': record.sessionId,
        'word': record.wordKey,
        'mode': record.recallMode.name,
        'cue': record.cueLevel.name,
        'correct': record.correctness,
        'latency': record.responseTimeMs,
        'confidence': record.confidence,
        'context': record.contextId,
        'algorithm': record.algorithmVersion,
        'occurred': record.occurredAtUtc.toIso8601String(),
        'schema': record.schemaVersion,
      };
    }).toList(),
    'memory': commit.memoryStates.map((record) {
      return <String, Object?>{
        'word': record.wordKey,
        'strength': record.strength,
        'cueDependency': record.cueDependency,
        'stability': record.stability,
        'difficulty': record.difficulty,
        'lapses': record.lapseCount,
        'reviewed': record.lastReviewedAtUtc?.toIso8601String(),
        'due': record.nextDueAtUtc.toIso8601String(),
        'error': record.lastErrorType,
        'algorithm': record.algorithmVersion,
        'updated': record.updatedAtUtc.toIso8601String(),
        'schema': record.schemaVersion,
      };
    }).toList(),
    'events': commit.learningEvents.map((record) => record.toMap()).toList(),
    'outbox': commit.outboxEntries.map((record) {
      return <String, Object?>{
        'id': record.outboxId,
        'event': record.eventId,
        'operation': record.operation.name,
        'payload': record.payloadJson,
        'created': record.createdAtUtc.toIso8601String(),
        'acknowledged': record.acknowledgedAtUtc?.toIso8601String(),
        'attempts': record.attemptCount,
        'schema': record.schemaVersion,
      };
    }).toList(),
    'tombstones': commit.tombstones.map((record) {
      return <String, Object?>{
        'id': record.tombstoneId,
        'type': record.entityType.name,
        'entity': record.entityId,
        'deleted': record.deletedAtUtc.toIso8601String(),
        'schema': record.schemaVersion,
      };
    }).toList(),
  };
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

int _epoch(DateTime value) => value.toUtc().millisecondsSinceEpoch;

int? _optionalEpoch(DateTime? value) => value == null ? null : _epoch(value);

DateTime _dateTime(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

DateTime? _optionalDateTime(int? value) =>
    value == null ? null : _dateTime(value);
