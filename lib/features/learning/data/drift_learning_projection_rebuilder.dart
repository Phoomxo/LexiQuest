import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import 'drift_learning_event_store.dart'
    hide
        ContextEvidencePolicyRolloutModeProvider,
        EvidencePolicyRolloutModeProvider,
        FixedEvidencePolicyRolloutModeProvider;
import '../domain/evidence_eligibility_policy.dart';
import '../domain/evidence_policy_rollout.dart';
import '../domain/learning_models.dart';
import '../domain/srs_policy.dart';

final class _WordProjectionScope {
  const _WordProjectionScope({
    required this.canonicalWordId,
    required this.wordIds,
  });

  final String canonicalWordId;
  final List<String> wordIds;
}

final class _WordProjectionAlias {
  const _WordProjectionAlias({
    required this.sourceWordId,
    required this.sourceOwnerId,
    required this.targetWordId,
    required this.conflictEntityId,
    required this.localSnapshot,
    required this.targetSnapshot,
  });

  final String sourceWordId;
  final String sourceOwnerId;
  final String targetWordId;
  final String conflictEntityId;
  final Map<String, Object?> localSnapshot;
  final Map<String, Object?> targetSnapshot;
}

final class DriftLearningProjectionRebuilder {
  static const int _maximumProjectionAliases = 64;

  DriftLearningProjectionRebuilder(
    this.database, {
    this.srsPolicy = const BinarySm2SrsPolicy(),
    EvidenceEligibilityPolicy evidencePolicy =
        const EvidenceEligibilityPolicySet(),
    EvidencePolicyRolloutModeProvider rolloutModeProvider =
        const FixedEvidencePolicyRolloutModeProvider.legacy(),
  }) : evidenceDecisions = DriftLearningEventStore(
         database,
         evidencePolicy: evidencePolicy,
         rolloutModeProvider: rolloutModeProvider,
       );

  final db.AppDatabase database;
  final SrsPolicy srsPolicy;
  final DriftLearningEventStore evidenceDecisions;

  /// Whether [wordId] is the live canonical target of immutable historical
  /// word aliases for [ownerId]. This validates the full contributing alias
  /// component before allowing an owner upgrade to extend that chain.
  Future<bool> hasIncomingProjectionAlias({
    required String ownerId,
    required String wordId,
  }) async {
    final scope = await _projectionScope(ownerId: ownerId, wordId: wordId);
    return scope.canonicalWordId == wordId &&
        scope.wordIds.any((candidate) => candidate != wordId);
  }

  Future<SrsSnapshot?> rebuildWord({
    required String ownerId,
    required String wordId,
  }) async {
    final scope = await _projectionScope(ownerId: ownerId, wordId: wordId);
    final attempts =
        await (database.select(database.answerAttempts)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.wordId.isIn(scope.wordIds),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    if (attempts.isEmpty) {
      throw StateError('cannot rebuild SRS without answer evidence');
    }

    final decisions = <String, LearningEvidenceDecisionSet>{};
    for (final attempt in attempts) {
      decisions[attempt.id] = await evidenceDecisions
          .ensureDecisionSetForAttempt(attempt: attempt);
    }
    final masteryAttempts = attempts
        .where(
          (attempt) =>
              decisions[attempt.id]!.allows(LearningProjection.masterySrs),
        )
        .toList(growable: false);
    final xpAttempts = attempts
        .where(
          (attempt) => decisions[attempt.id]!.allows(LearningProjection.xp),
        )
        .toList(growable: false);

    final attemptIds = attempts.map((attempt) => attempt.id).toList();
    await (database.delete(database.pointsLedgerEntries)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.entryType.equals('quizCorrect') &
              row.sourceEventId.isIn(attemptIds),
        ))
        .go();
    for (final attempt in xpAttempts.where((attempt) => attempt.isCorrect)) {
      await database
          .into(database.pointsLedgerEntries)
          .insert(
            db.PointsLedgerEntriesCompanion.insert(
              id: 'points:${attempt.id}',
              ownerId: ownerId,
              idempotencyKey: 'correct-answer:${attempt.id}',
              entryType: 'quizCorrect',
              amount: 1,
              sourceEventId: Value(attempt.id),
              occurredAtUtcMs: attempt.occurredAtUtcMs,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }

    if (masteryAttempts.isEmpty) {
      await (database.delete(database.srsStates)..where(
            (row) =>
                row.ownerId.equals(ownerId) & row.wordId.isIn(scope.wordIds),
          ))
          .go();
      return null;
    }

    SrsSnapshot? state;
    for (final attempt in masteryAttempts) {
      state = srsPolicy.review(
        previous: state,
        isCorrect: attempt.isCorrect,
        nowUtc: _utc(attempt.occurredAtUtcMs),
      );
    }

    final next = state!;
    await (database.delete(database.srsStates)..where(
          (row) => row.ownerId.equals(ownerId) & row.wordId.isIn(scope.wordIds),
        ))
        .go();
    await database
        .into(database.srsStates)
        .insert(
          db.SrsStatesCompanion.insert(
            id: 'srs:$ownerId:${scope.canonicalWordId}',
            ownerId: ownerId,
            wordId: scope.canonicalWordId,
            stability: Value(next.stability),
            difficulty: Value(next.difficulty),
            intervalDays: Value(next.intervalDays),
            repetitions: Value(next.repetitions),
            lapses: Value(next.lapses),
            lastReviewAtUtcMs: Value(
              next.lastReviewAtUtc?.millisecondsSinceEpoch,
            ),
            dueAtUtcMs: next.dueAtUtc!.millisecondsSinceEpoch,
            algorithmVersion: next.algorithmVersion,
          ),
        );
    return next;
  }

  Future<_WordProjectionScope> _projectionScope({
    required String ownerId,
    required String wordId,
  }) async {
    final conflicts =
        await (database.select(database.syncConflicts)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.entityType.equals('word') &
                    row.resolutionPolicy.equals('guestUpgradeCanonicalTarget') &
                    row.outcome.equals('targetRetained') &
                    row.localSnapshotJson.like('%projectionAlias%'),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.id)])
              ..limit(_maximumProjectionAliases + 1))
            .get();
    if (conflicts.length > _maximumProjectionAliases) {
      throw StateError('word projection alias bound exceeded');
    }
    final aliases = <String, _WordProjectionAlias>{};
    for (final conflict in conflicts) {
      final alias = _decodeProjectionAlias(conflict);
      if (alias == null) continue;
      final existing = aliases[alias.sourceWordId];
      if (existing != null &&
          (existing.targetWordId != alias.targetWordId ||
              existing.conflictEntityId != alias.conflictEntityId ||
              jsonEncode(existing.localSnapshot) !=
                  jsonEncode(alias.localSnapshot) ||
              jsonEncode(existing.targetSnapshot) !=
                  jsonEncode(alias.targetSnapshot))) {
        throw StateError('word projection alias is ambiguous');
      }
      aliases.putIfAbsent(alias.sourceWordId, () => alias);
    }
    String resolve(String candidate) {
      final visited = <String>{};
      var resolved = candidate;
      while (true) {
        final alias = aliases[resolved];
        if (alias == null) break;
        if (!visited.add(resolved)) {
          throw StateError('word projection alias cycle is invalid');
        }
        resolved = alias.targetWordId;
      }
      return resolved;
    }

    for (final alias in aliases.values) {
      if (alias.conflictEntityId != resolve(alias.targetWordId)) {
        throw StateError('word projection alias target is invalid');
      }
    }
    final canonicalWordId = resolve(wordId);
    // Live word rows are mutable application state. Validate only the alias
    // component that can contribute evidence to this canonical projection so
    // a retired component cannot roll back unrelated answers.
    final relevantAliases = aliases.values
        .where((alias) => resolve(alias.sourceWordId) == canonicalWordId)
        .toList(growable: false);
    for (final alias in relevantAliases) {
      await _validateProjectionAlias(
        ownerId: ownerId,
        alias: alias,
        aliases: aliases,
      );
    }
    final wordIds = <String>{canonicalWordId};
    for (final alias in relevantAliases) {
      wordIds.add(alias.sourceWordId);
    }
    return _WordProjectionScope(
      canonicalWordId: canonicalWordId,
      wordIds: List<String>.unmodifiable(wordIds.toList()..sort()),
    );
  }

  _WordProjectionAlias? _decodeProjectionAlias(db.SyncConflict conflict) {
    final localJson = conflict.localSnapshotJson;
    final targetJson = conflict.cloudSnapshotJson;
    if (localJson == null || targetJson == null) return null;
    late final Map<String, Object?> local;
    late final Map<String, Object?> target;
    try {
      local = (jsonDecode(localJson) as Map).cast<String, Object?>();
      target = (jsonDecode(targetJson) as Map).cast<String, Object?>();
    } on Object {
      throw StateError('word projection alias snapshot is corrupt');
    }
    const aliasKeys = <String>{
      'projectionAliasVersion',
      'projectionAliasSourceOwnerId',
      'projectionAliasTargetWordId',
    };
    final presentAliasKeys = local.keys.where(aliasKeys.contains).length;
    if (presentAliasKeys == 0) return null;
    const localKeys = <String>{
      'id',
      'spelling',
      'meaning',
      'normalizedSpelling',
      'normalizedMeaning',
      'contentRevision',
      'contentChecksumSha256',
      'contentProvenance',
      'contentReviewState',
      'contentPublicationState',
      ...aliasKeys,
    };
    const targetKeys = <String>{
      'id',
      'spelling',
      'meaning',
      'normalizedSpelling',
      'normalizedMeaning',
      'contentRevision',
      'contentChecksumSha256',
      'contentProvenance',
      'contentReviewState',
      'contentPublicationState',
    };
    final sourceWordId = local['id'];
    final sourceOwnerId = local['projectionAliasSourceOwnerId'];
    final targetWordId = local['projectionAliasTargetWordId'];
    if (presentAliasKeys != aliasKeys.length ||
        local.length != localKeys.length ||
        !local.keys.every(localKeys.contains) ||
        target.length != targetKeys.length ||
        !target.keys.every(targetKeys.contains) ||
        local['projectionAliasVersion'] != 1 ||
        sourceWordId is! String ||
        sourceOwnerId is! String ||
        targetWordId is! String ||
        target['id'] != targetWordId ||
        local['normalizedSpelling'] != target['normalizedSpelling'] ||
        local['normalizedMeaning'] != target['normalizedMeaning']) {
      throw StateError('word projection alias snapshot is invalid');
    }
    return _WordProjectionAlias(
      sourceWordId: sourceWordId,
      sourceOwnerId: sourceOwnerId,
      targetWordId: targetWordId,
      conflictEntityId: conflict.entityId,
      localSnapshot: Map<String, Object?>.unmodifiable(local),
      targetSnapshot: Map<String, Object?>.unmodifiable(target),
    );
  }

  Future<void> _validateProjectionAlias({
    required String ownerId,
    required _WordProjectionAlias alias,
    required Map<String, _WordProjectionAlias> aliases,
  }) async {
    final sourceWordId = alias.sourceWordId;
    final sourceOwnerId = alias.sourceOwnerId;
    final targetWordId = alias.targetWordId;
    final local = alias.localSnapshot;
    final words =
        await (database.select(database.vocabularyWords)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.id.isIn(<String>[sourceWordId, targetWordId]),
            ))
            .get();
    if (words.length != 2) {
      throw StateError('word projection alias identity is unavailable');
    }
    final source = words.singleWhere((row) => row.id == sourceWordId);
    final targetWord = words.singleWhere((row) => row.id == targetWordId);
    final ownerLineageValid = await _isMergedOwnerAncestor(
      historicalOwnerId: sourceOwnerId,
      currentOwnerId: ownerId,
    );
    final tombstoneHash = sha256
        .convert(utf8.encode('$sourceOwnerId|$sourceWordId|$targetWordId'))
        .toString();
    final targetIsIntermediateAlias = aliases.containsKey(targetWordId);
    if (targetWord.isDeleted && !targetIsIntermediateAlias) {
      throw StateError('word projection alias canonical target is deleted');
    }
    // The target snapshot proves the natural-key collision at upgrade time;
    // its live lexical bytes may evolve afterward. The source tombstone and
    // owner lineage remain immutable provenance and are checked below.
    if (sourceOwnerId == ownerId ||
        !ownerLineageValid ||
        !source.isDeleted ||
        source.spelling != local['spelling'] ||
        source.meaning != local['meaning'] ||
        source.contentRevision != local['contentRevision'] ||
        source.contentChecksumSha256 != local['contentChecksumSha256'] ||
        source.contentProvenance != local['contentProvenance'] ||
        source.contentReviewState != local['contentReviewState'] ||
        source.contentPublicationState != local['contentPublicationState'] ||
        source.normalizedSpelling !=
            'merged-collision-$tombstoneHash-spelling' ||
        source.normalizedMeaning != 'merged-collision-$tombstoneHash-meaning') {
      throw StateError('word projection alias binding is invalid');
    }
  }

  Future<bool> _isMergedOwnerAncestor({
    required String historicalOwnerId,
    required String currentOwnerId,
  }) async {
    final visited = <String>{};
    var candidate = historicalOwnerId;
    for (var depth = 0; depth <= _maximumProjectionAliases; depth += 1) {
      if (candidate == currentOwnerId) return depth > 0;
      if (!visited.add(candidate)) return false;
      final owner = await (database.select(
        database.localOwners,
      )..where((row) => row.id.equals(candidate))).getSingleOrNull();
      if (owner == null || owner.isActive) return false;
      const prefix = 'mergedInto:';
      if (!owner.accountState.startsWith(prefix)) return false;
      candidate = owner.accountState.substring(prefix.length);
    }
    return false;
  }

  Future<void> rebuildSession({
    required String ownerId,
    required String sessionId,
  }) async {
    final session =
        await (database.select(database.learningSessions)..where(
              (row) => row.id.equals(sessionId) & row.ownerId.equals(ownerId),
            ))
            .getSingleOrNull();
    if (session == null) {
      throw StateError('owner-scoped learning session not found');
    }
    final attempts =
        await (database.select(database.answerAttempts)..where(
              (row) =>
                  row.ownerId.equals(ownerId) & row.sessionId.equals(sessionId),
            ))
            .get();
    final eligible = <db.AnswerAttempt>[];
    for (final attempt in attempts) {
      final decisionSet = await evidenceDecisions.ensureDecisionSetForAttempt(
        attempt: attempt,
      );
      if (decisionSet.allows(LearningProjection.sessionOutcome)) {
        eligible.add(attempt);
      }
    }
    final correct = eligible.where((attempt) => attempt.isCorrect).length;
    final wrong = eligible.length - correct;
    final score = eligible.isEmpty
        ? 0
        : ((correct * 100) / eligible.length).round();
    await (database.update(database.learningSessions)..where(
          (row) => row.id.equals(sessionId) & row.ownerId.equals(ownerId),
        ))
        .write(
          db.LearningSessionsCompanion(
            correctCount: Value(correct),
            wrongCount: Value(wrong),
            score: session.state == 'completed'
                ? Value(score)
                : const Value.absent(),
          ),
        );
  }

  Future<void> rebuildAchievements(String ownerId) async {
    final attempts =
        await (database.select(database.answerAttempts)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final eligible = <db.AnswerAttempt>[];
    for (final attempt in attempts) {
      final decisionSet = await evidenceDecisions.ensureDecisionSetForAttempt(
        attempt: attempt,
      );
      if (decisionSet.allows(LearningProjection.achievement)) {
        eligible.add(attempt);
      }
    }
    final desired = <String, db.AnswerAttempt>{};
    if (eligible.isNotEmpty) desired['first_answer'] = eligible.first;
    final correct = eligible
        .where((attempt) => attempt.isCorrect)
        .toList(growable: false);
    if (correct.isNotEmpty) {
      desired['first_correct'] = correct.first;
    }
    if (correct.length >= 10) {
      desired['ten_correct'] = correct[9];
    }
    const managedAchievementIds = <String>{
      'first_answer',
      'first_correct',
      'ten_correct',
    };
    final obsolete = managedAchievementIds.difference(desired.keys.toSet());
    if (obsolete.isNotEmpty) {
      await (database.delete(database.achievementUnlocks)..where(
            (row) =>
                row.ownerId.equals(ownerId) &
                row.definitionVersion.equals(1) &
                row.achievementId.isIn(obsolete),
          ))
          .go();
    }
    for (final entry in desired.entries) {
      await _insertAchievement(
        ownerId: ownerId,
        achievementId: entry.key,
        source: entry.value,
      );
    }
  }

  Future<LearningEvidenceDecisionSet> decisionSetForAttempt(
    db.AnswerAttempt attempt,
  ) => evidenceDecisions.ensureDecisionSetForAttempt(attempt: attempt);

  Future<ReadingProgressSnapshot> rebuildReading({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async {
    final events =
        await (database.select(database.readingEvents)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.documentId.equals(documentId) &
                    row.documentRevision.equals(documentRevision),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    if (events.isEmpty) {
      throw StateError('cannot rebuild reading progress without evidence');
    }
    var position = 0;
    var completed = false;
    var updatedAtUtcMs = 0;
    for (final event in events) {
      final eventPosition = event.position ?? 0;
      if (eventPosition > position) position = eventPosition;
      if (event.eventType == 'completed') completed = true;
      if (event.occurredAtUtcMs > updatedAtUtcMs) {
        updatedAtUtcMs = event.occurredAtUtcMs;
      }
    }
    await (database.delete(database.readingProgressEntries)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.documentId.equals(documentId) &
              row.documentRevision.equals(documentRevision),
        ))
        .go();
    await database
        .into(database.readingProgressEntries)
        .insert(
          db.ReadingProgressEntriesCompanion.insert(
            id: 'reading:$ownerId:$documentId:$documentRevision',
            ownerId: ownerId,
            documentId: documentId,
            documentRevision: Value(documentRevision),
            lastPosition: Value(position),
            isCompleted: Value(completed),
            updatedAtUtcMs: updatedAtUtcMs,
          ),
        );
    return ReadingProgressSnapshot(
      documentId: documentId,
      documentRevision: documentRevision,
      lastPosition: position,
      isCompleted: completed,
      updatedAtUtc: _utc(updatedAtUtcMs),
    );
  }

  Future<void> _insertAchievement({
    required String ownerId,
    required String achievementId,
    required db.AnswerAttempt source,
  }) async {
    const definitionVersion = 1;
    final existing =
        await (database.select(database.achievementUnlocks)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.achievementId.equals(achievementId) &
                  row.definitionVersion.equals(definitionVersion),
            ))
            .getSingleOrNull();
    if (existing != null) {
      if (source.id == existing.sourceEventId &&
          source.occurredAtUtcMs == existing.unlockedAtUtcMs) {
        return;
      }

      // Preserve the unlock identity while rebuilding canonical provenance
      // exclusively from eligible evidence.
      await (database.update(
        database.achievementUnlocks,
      )..where((row) => row.id.equals(existing.id))).write(
        db.AchievementUnlocksCompanion(
          sourceEventId: Value(source.id),
          unlockedAtUtcMs: Value(source.occurredAtUtcMs),
        ),
      );
      return;
    }
    await database
        .into(database.achievementUnlocks)
        .insert(
          db.AchievementUnlocksCompanion.insert(
            id: 'achievement:$ownerId:$achievementId:$definitionVersion',
            ownerId: ownerId,
            achievementId: achievementId,
            definitionVersion: definitionVersion,
            sourceEventId: source.id,
            unlockedAtUtcMs: source.occurredAtUtcMs,
          ),
        );
  }
}

DateTime _utc(int millisecondsSinceEpoch) =>
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true);
