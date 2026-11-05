part of 'drift_learning_repository.dart';

final class DriftMatchingRepository implements MatchingRepository {
  DriftMatchingRepository(this.canonical);
  final DriftLearningRepository canonical;
  final Expando<_MatchingLease> _prepared = Expando<_MatchingLease>();

  db.AppDatabase get database => canonical.database;

  @override
  Future<MatchingPlan?> prepare({
    required LearningSessionDraft session,
    String? categoryId,
    Iterable<String>? wordIds,
    required int limit,
    required bool Function() stillCurrent,
  }) async {
    if (limit < 2 ||
        limit > 8 ||
        session.activityType != MatchingPlan.activityType) {
      throw ArgumentError('Matching requires 2..8 pairs');
    }
    final requested = wordIds?.toList(growable: false);
    if (requested != null &&
        (requested.length < 2 ||
            requested.length > limit ||
            requested.toSet().length != requested.length)) {
      throw ArgumentError('Invalid matching source selection');
    }
    final lease = _lease(stillCurrent);
    final plan = await _boundary<MatchingPlan?>(
      session.ownerId,
      () => lease.current,
      write: () async {
        if (await canonical._session(session.id) != null) {
          throw StateError('Matching preparation cannot adopt a saved session');
        }
        final candidates = await canonical.listQuizWords(
          ownerId: session.ownerId,
          categoryId: categoryId,
          wordIds: requested,
          limit: requested == null ? 100 : requested.length,
        );
        final spellings = <String>{};
        final meanings = <String>{};
        final words = <QuizWord>[];
        for (final word in candidates) {
          final spelling = word.spelling.trim().toLowerCase().replaceAll(
            RegExp(r'\s+'),
            ' ',
          );
          final meaning = word.meaning.trim().toLowerCase().replaceAll(
            RegExp(r'\s+'),
            ' ',
          );
          if (spelling.isEmpty ||
              meaning.isEmpty ||
              spellings.contains(spelling) ||
              meanings.contains(meaning)) {
            continue;
          }
          spellings.add(spelling);
          meanings.add(meaning);
          words.add(word);
          if (words.length == limit) break;
        }
        if (requested != null &&
            (words.length != requested.length ||
                words.any((word) => !requested.contains(word.id)))) {
          throw StateError('Matching source is missing or ambiguous');
        }
        if (words.length < 2) return null;
        return MatchingPlan(session: session, words: words);
      },
    );
    if (plan != null) _prepared[plan] = lease;
    return plan;
  }

  @override
  Future<MatchingState> start(
    MatchingPlan plan, {
    required bool Function() stillCurrent,
  }) async {
    final lease = _prepared[plan];
    if (lease == null) {
      throw StateError('Original matching preparation is required');
    }
    final state = await _boundary(
      plan.session.ownerId,
      () => lease.current && stillCurrent(),
      write: () async {
        final existing = await canonical._session(plan.session.id);
        if (existing != null) {
          if (!lease.startAttempted) {
            throw StateError('Matching session was not started by this handle');
          }
          final state = await _read(
            plan.session.id,
            plan.session.ownerId,
            lease,
          );
          if (state.plan.id != plan.id) {
            throw StateError('Original matching plan changed');
          }
          return state;
        }
        if (lease.started) {
          throw StateError('Acknowledged matching session is missing');
        }
        await _requireTargets(plan);
        lease.startAttempted = true;
        await canonical._startSession(
          plan.session,
          beforeObserved: () => _store(
            plan,
            1,
            MatchingCheckpoint(
              phase: MatchingPhase.selecting,
              attemptCount: 0,
              matched: const [],
            ),
          ),
        );
        await _requireTargets(plan);
        return _read(plan.session.id, plan.session.ownerId, lease);
      },
    );
    lease.started = true;
    return state;
  }

  @override
  Future<MatchingState> resume({
    required String sessionId,
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) {
    final lease = _lease(stillCurrent);
    return _boundary(
      expectedOwnerId,
      () => lease.current,
      write: () => _read(sessionId, expectedOwnerId, lease),
    );
  }

  @override
  Future<MatchingState> save(
    MatchingState state,
    MatchingCheckpoint next, {
    required bool Function() stillCurrent,
  }) async {
    final issued = _issued(state);
    next.validate(issued.plan);
    return _boundary(
      issued.plan.session.ownerId,
      () => issued.lease.current && stillCurrent(),
      write: () async {
        final current = await _read(
          issued.plan.session.id,
          issued.plan.session.ownerId,
          issued.lease,
        );
        if (current.checkpoint.stableSerialization ==
                next.stableSerialization &&
            current.revision == issued.revision + 1) {
          return current;
        }
        _sameSnapshot(issued, current);
        _transition(issued, next);
        if (next.phase == MatchingPhase.selecting ||
            next.phase == MatchingPhase.pending) {
          await _requireTargets(issued.plan);
        }
        if (next.phase == MatchingPhase.abandoned) {
          await database.customUpdate(
            "UPDATE learning_sessions SET state = 'abandoned', ended_at_utc_ms = ? WHERE id = ? AND owner_id = ? AND state = 'active'",
            variables: [
              Variable<int>(next.endedAtUtcMs!),
              Variable<String>(issued.plan.session.id),
              Variable<String>(issued.plan.session.ownerId),
            ],
            updates: {database.learningSessions},
          );
        }
        await _store(
          issued.plan,
          issued.revision + 1,
          next,
          expectedRevision: issued.revision,
        );
        if (next.phase == MatchingPhase.selecting ||
            next.phase == MatchingPhase.pending) {
          await _requireTargets(issued.plan);
        }
        return _read(
          issued.plan.session.id,
          issued.plan.session.ownerId,
          issued.lease,
        );
      },
    );
  }

  @override
  Future<MatchingState> commit(
    MatchingState state, {
    required bool Function() stillCurrent,
  }) async {
    final issued = _issued(state);
    final pending = issued.checkpoint;
    if (pending.phase != MatchingPhase.pending) {
      throw StateError('Original pending pair is required');
    }
    return _boundary(
      issued.plan.session.ownerId,
      () => issued.lease.current && stillCurrent(),
      write: () async {
        final current = await _read(
          issued.plan.session.id,
          issued.plan.session.ownerId,
          issued.lease,
        );
        final answer = pending.answer!;
        if (current.revision == issued.revision + 1 &&
            current.checkpoint.phase == MatchingPhase.answered &&
            jsonEncode(current.checkpoint.answer!.toJson()) ==
                jsonEncode(answer.toJson())) {
          return current;
        }
        _sameSnapshot(issued, current);
        await _requireTargets(issued.plan);
        await canonical._recordAnswer(issued.plan.command(answer));
        final matched = [
          ...pending.matched,
          if (answer.isCorrect) answer.wordIndex,
        ]..sort();
        final next = MatchingCheckpoint(
          phase: MatchingPhase.answered,
          attemptCount: pending.attemptCount + 1,
          matched: matched,
          answer: answer,
        );
        next.validate(issued.plan);
        await _store(
          issued.plan,
          issued.revision + 1,
          next,
          expectedRevision: issued.revision,
        );
        await _requireTargets(issued.plan);
        return _read(
          issued.plan.session.id,
          issued.plan.session.ownerId,
          issued.lease,
        );
      },
    );
  }

  @override
  Future<MatchingState> finish(
    MatchingState state, {
    required bool Function() stillCurrent,
  }) async {
    final issued = _issued(state);
    if (issued.checkpoint.phase != MatchingPhase.closing) {
      throw StateError('Original matching close is required');
    }
    return _boundary(
      issued.plan.session.ownerId,
      () => issued.lease.current && stillCurrent(),
      write: () async {
        final current = await _read(
          issued.plan.session.id,
          issued.plan.session.ownerId,
          issued.lease,
        );
        if (current.revision == issued.revision + 1 &&
            current.checkpoint.phase == MatchingPhase.completed &&
            current.checkpoint.endedAtUtcMs == issued.checkpoint.endedAtUtcMs) {
          return current;
        }
        _sameSnapshot(issued, current);
        await canonical._finishSession(
          ownerId: issued.plan.session.ownerId,
          sessionId: issued.plan.session.id,
          endedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            issued.checkpoint.endedAtUtcMs!,
            isUtc: true,
          ),
        );
        final next = MatchingCheckpoint(
          phase: MatchingPhase.completed,
          attemptCount: issued.checkpoint.attemptCount,
          matched: issued.checkpoint.matched,
          endedAtUtcMs: issued.checkpoint.endedAtUtcMs,
        );
        await _store(
          issued.plan,
          issued.revision + 1,
          next,
          expectedRevision: issued.revision,
        );
        return _read(
          issued.plan.session.id,
          issued.plan.session.ownerId,
          issued.lease,
        );
      },
    );
  }

  _MatchingLease _lease(bool Function() current) {
    canonical._trackConfiguredOwner();
    return _MatchingLease(canonical, canonical._configuredOwnerEpoch, current);
  }

  _DriftMatchingState _issued(MatchingState state) {
    if (state is! _DriftMatchingState ||
        !identical(state.issuer, this) ||
        !state.lease.current) {
      throw StateError('Original current matching read is required');
    }
    return state;
  }

  Future<T> _boundary<T>(
    String owner,
    bool Function() current, {
    required Future<T> Function() write,
  }) async {
    canonical._trackConfiguredOwner();
    final epoch = canonical._configuredOwnerEpoch;
    bool live() => current() && canonical._configuredOwnerEpoch == epoch;
    if (!live() ||
        await canonical._ownerWrites.hasAmbientTransaction() ||
        !live()) {
      throw StateError('Matching requires its own current transaction');
    }
    return canonical._ownerWrites.writeForActiveOwner(
      expectedOwnerId: owner,
      write: () async {
        await canonical._requireTimeReadOwner(owner, live);
        final result = await write();
        await canonical._requireTimeReadOwner(owner, live);
        return result;
      },
    );
  }

  Future<void> _requireTargets(MatchingPlan plan) async {
    final actual = await canonical.listQuizWords(
      ownerId: plan.session.ownerId,
      wordIds: plan.words.map((word) => word.id),
      limit: plan.words.length,
    );
    if (actual.length != plan.words.length) {
      throw StateError('Original matching vocabulary is unavailable');
    }
    for (final word in plan.words) {
      final fresh = actual.where((candidate) => candidate.id == word.id).single;
      if (fresh.categoryId != word.categoryId ||
          fresh.spelling != word.spelling ||
          fresh.meaning != word.meaning ||
          fresh.partOfSpeech != word.partOfSpeech ||
          fresh.contentRevision != word.contentRevision) {
        throw StateError('Original matching vocabulary changed');
      }
    }
  }

  Future<_DriftMatchingState> _read(
    String id,
    String owner,
    _MatchingLease lease,
  ) async {
    if (!lease.current) throw StateError('Matching owner changed');
    final row = await canonical._session(id);
    if (row == null ||
        row.ownerId != owner ||
        row.activityType != MatchingPlan.activityType ||
        row.acceptedPlanId == null ||
        row.acceptedPlanJson == null ||
        row.checkpointJson == null ||
        row.checkpointRevision < 1) {
      throw StateError('Matching session is unavailable');
    }
    final plan = MatchingPlan.parse(
      id: row.acceptedPlanId!,
      json: row.acceptedPlanJson!,
    );
    final session = plan.session;
    if (session.id != row.id ||
        session.ownerId != owner ||
        session.startedAtUtc!.millisecondsSinceEpoch != row.startedAtUtcMs ||
        session.appVersion != row.appVersion ||
        session.buildId != row.buildId) {
      throw StateError('Matching session identity changed');
    }
    await canonical._requireTimeOrdinarySession(id);
    final checkpoint = MatchingCheckpoint.parse(row.checkpointJson!, plan);
    final expectedState = switch (checkpoint.phase) {
      MatchingPhase.completed => 'completed',
      MatchingPhase.abandoned => 'abandoned',
      _ => 'active',
    };
    if (row.state != expectedState ||
        (row.state == 'active'
            ? row.endedAtUtcMs != null
            : row.endedAtUtcMs != checkpoint.endedAtUtcMs)) {
      throw StateError('Matching terminal state changed');
    }
    final attempts =
        await (database.select(database.answerAttempts)
              ..where((attempt) => attempt.sessionId.equals(id))
              ..orderBy([(attempt) => OrderingTerm.asc(attempt.attemptNumber)]))
            .get();
    if (attempts.length != checkpoint.attemptCount) {
      throw StateError('Matching attempt count changed');
    }
    final matched = <int>{};
    var lastTime = row.startedAtUtcMs;
    for (var index = 0; index < attempts.length; index++) {
      final attempt = attempts[index];
      if (!LearningEvidenceContract.validAttempt(
        id: attempt.id,
        ownerId: attempt.ownerId,
        sessionId: attempt.sessionId,
        wordId: attempt.wordId,
        promptMode: attempt.promptMode,
        responseTimeMs: attempt.responseTimeMs,
        attemptNumber: attempt.attemptNumber,
        occurredAtUtcMs: attempt.occurredAtUtcMs,
        providerProvenance: attempt.providerProvenance,
        evidenceClass: attempt.evidenceClass,
        evidenceContextJson: attempt.evidenceContextJson,
      )) {
        throw StateError('Matching attempt metadata changed');
      }
      final wordIndex = plan.words.indexWhere(
        (word) => word.id == attempt.wordId,
      );
      if (wordIndex < 0 ||
          matched.contains(wordIndex) ||
          attempt.ownerId != owner ||
          attempt.id != 'attempt:matching:$id:${index + 1}' ||
          attempt.attemptNumber != index + 1 ||
          attempt.promptMode != MatchingPlan.promptMode ||
          attempt.providerProvenance != null ||
          attempt.occurredAtUtcMs < lastTime ||
          attempt.evidenceClass != EvidenceClass.recognition.name ||
          attempt.evidenceContextJson != jsonEncode(plan.evidence.toJson())) {
        throw StateError('Matching canonical evidence changed');
      }
      if (attempt.isCorrect) matched.add(wordIndex);
      lastTime = attempt.occurredAtUtcMs;
    }
    final orderedMatched = matched.toList()..sort();
    final correct = attempts.where((attempt) => attempt.isCorrect).length;
    final score = attempts.isEmpty
        ? 0
        : ((correct * 100) / attempts.length).round();
    if (row.correctCount != correct ||
        row.wrongCount != attempts.length - correct ||
        (row.state == 'completed'
            ? row.score != score
            : row.score != null && row.score != score)) {
      throw StateError('Matching result differs from canonical answers');
    }
    if (jsonEncode(orderedMatched) != jsonEncode(checkpoint.matched)) {
      throw StateError('Matching board differs from canonical answers');
    }
    if (checkpoint.phase == MatchingPhase.answered &&
        (attempts.isEmpty ||
            !canonical._sameAttempt(
              attempts.last,
              plan.command(checkpoint.answer!),
            ))) {
      throw StateError(
        'Matching acknowledgement differs from its original pair',
      );
    }
    if (checkpoint.phase == MatchingPhase.pending &&
        checkpoint.answer!.occurredAtUtcMs < lastTime) {
      throw StateError('Matching answer precedes acknowledged evidence');
    }
    if (checkpoint.endedAtUtcMs != null &&
        checkpoint.endedAtUtcMs! < lastTime) {
      throw StateError('Matching close precedes acknowledged evidence');
    }
    if (row.state == 'active') await _requireTargets(plan);
    if (!lease.current) throw StateError('Matching owner changed during read');
    return _DriftMatchingState(
      issuer: this,
      lease: lease,
      plan: plan,
      checkpoint: checkpoint,
      revision: row.checkpointRevision,
      completedSummary: row.state == 'completed'
          ? canonical._nativeSummary(row)
          : null,
    );
  }

  void _sameSnapshot(_DriftMatchingState issued, _DriftMatchingState current) {
    if (issued.plan.id != current.plan.id ||
        issued.revision != current.revision ||
        issued.checkpoint.stableSerialization !=
            current.checkpoint.stableSerialization) {
      throw StateError('Matching checkpoint changed');
    }
  }

  void _transition(_DriftMatchingState state, MatchingCheckpoint next) {
    final old = state.checkpoint;
    if (old.phase == MatchingPhase.completed ||
        old.phase == MatchingPhase.abandoned ||
        old.attemptCount != next.attemptCount ||
        jsonEncode(old.matched) != jsonEncode(next.matched)) {
      throw StateError('Invalid matching transition');
    }
    if (next.phase == MatchingPhase.abandoned) return;
    final allowed = switch ((old.phase, next.phase)) {
      (MatchingPhase.selecting, MatchingPhase.selecting) => true,
      (MatchingPhase.selecting, MatchingPhase.pending) => true,
      (MatchingPhase.answered, MatchingPhase.selecting) =>
        old.matched.length < state.plan.words.length,
      (MatchingPhase.answered, MatchingPhase.closing) =>
        old.matched.length == state.plan.words.length,
      _ => false,
    };
    if (!allowed) throw StateError('Invalid matching transition');
    if (next.phase == MatchingPhase.pending &&
        (old.selectedWord != next.answer!.wordIndex ||
            old.selectedMeaning != next.answer!.meaningIndex)) {
      throw StateError('Matching pair differs from its saved selection');
    }
    if (next.endedAtUtcMs != null &&
        old.answer != null &&
        next.endedAtUtcMs! < old.answer!.occurredAtUtcMs) {
      throw StateError('Matching close precedes its final pair');
    }
  }

  Future<void> _store(
    MatchingPlan plan,
    int revision,
    MatchingCheckpoint checkpoint, {
    int? expectedRevision,
  }) async {
    checkpoint.validate(plan);
    final changed = await database.customUpdate(
      'UPDATE learning_sessions SET accepted_plan_id = ?, accepted_plan_json = ?, checkpoint_revision = ?, checkpoint_json = ? WHERE id = ? AND owner_id = ?${expectedRevision == null ? '' : ' AND checkpoint_revision = ?'}',
      variables: [
        Variable<String>(plan.id),
        Variable<String>(plan.stableSerialization),
        Variable<int>(revision),
        Variable<String>(checkpoint.stableSerialization),
        Variable<String>(plan.session.id),
        Variable<String>(plan.session.ownerId),
        if (expectedRevision != null) Variable<int>(expectedRevision),
      ],
      updates: {database.learningSessions},
    );
    if (changed != 1) throw StateError('Matching checkpoint changed');
  }
}

final class _MatchingLease {
  _MatchingLease(this.canonical, this.epoch, this.check);
  final DriftLearningRepository canonical;
  final int epoch;
  final bool Function() check;
  bool retired = false;
  bool startAttempted = false;
  bool started = false;
  bool get current {
    if (retired || canonical._configuredOwnerEpoch != epoch || !check()) {
      retired = true;
    }
    return !retired;
  }
}

final class _DriftMatchingState implements MatchingState {
  const _DriftMatchingState({
    required this.issuer,
    required this.lease,
    required this.plan,
    required this.checkpoint,
    required this.revision,
    required this.completedSummary,
  });
  final DriftMatchingRepository issuer;
  final _MatchingLease lease;
  @override
  final MatchingPlan plan;
  @override
  final MatchingCheckpoint checkpoint;
  @override
  final int revision;
  @override
  final LearningSessionSummary? completedSummary;
}
