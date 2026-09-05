import 'dart:convert';
import '../domain/pair_matching_engine.dart';
import '../domain/pair_active_clock.dart';
import '../domain/pair_matching_plan.dart';
import '../domain/pair_matching_launch.dart';
import '../domain/pair_matching_checkpoint_budget.dart';
import '../../domain/learning_evidence_contract.dart';

final class PairTerminalState {
  const PairTerminalState(
    this.atUtc, {
    this.acknowledged = false,
    this.presented = false,
  });
  final DateTime atUtc;
  final bool acknowledged, presented;
  Map<String, Object?> toJson() => {
    'atUtc': atUtc.toIso8601String(),
    'acknowledged': acknowledged,
    'presented': presented,
  };
  static PairTerminalState fromJson(Object? value) {
    final j = pairJson(value, {'atUtc', 'acknowledged', 'presented'});
    final t = PairTerminalState(
      DateTime.parse(j['atUtc'] as String),
      acknowledged: j['acknowledged'] as bool,
      presented: j['presented'] as bool,
    );
    if (!t.atUtc.isUtc || (t.presented && !t.acknowledged)) {
      throw const FormatException('Invalid Pair terminal');
    }
    return t;
  }
}

final class PairMatchingCheckpointSnapshot {
  PairMatchingCheckpointSnapshot({
    required this.engine,
    required this.startOperation,
    Iterable<String> evidenceIds = const [],
    Map<String, Object?>? frozenEvidence,
    this.timer,
    this.terminal,
  }) : evidenceIds = List.unmodifiable(evidenceIds),
       frozenEvidence = frozenEvidence == null
           ? null
           : _freeze(frozenEvidence) as Map<String, Object?>;
  final PairMatchingState engine;
  final String startOperation;
  final List<String> evidenceIds;
  final Map<String, Object?>? frozenEvidence;
  final PairTimerState? timer;
  final PairTerminalState? terminal;
  Map<String, Object?> toJson() =>
      _freeze({
            'schemaVersion': 6,
            'codecVersion': timer == null ? 2 : 3,
            'planFingerprint': engine.plan.planFingerprint,
            'plan': engine.plan.toJson(),
            'startOperation': _compactStart(startOperation),
            'engine': _compactEngine(engine),
            'evidenceIds': evidenceIds,
            'frozenEvidence': frozenEvidence,
            if (timer != null) ...{
              'timer': timer!.toJson(),
              'roundSeed': engine.roundSeed,
              'terminal': terminal?.toJson(),
            },
          })
          as Map<String, Object?>;
}

Object? _freeze(Object? value) => switch (value) {
  Map value => Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry(key as String, _freeze(value))),
  ),
  List value => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};

Map<String, Object?> _compactStart(String operation) {
  final j = jsonDecode(operation) as Map<String, dynamic>;
  return {
    'schemaVersion': j['schemaVersion'],
    'launchOperationId': j['launchOperationId'],
    'appVersion': j['appVersion'],
    'buildId': j['buildId'],
    if (j['schemaVersion'] == 2)
      'sessionConfiguration': j['sessionConfiguration'],
  };
}

// Repeated lexical IDs can each contain 256 characters. The immutable plan
// already authenticates their order, so durable attempt rows reference it by
// index; the pure reducer continues to expose canonical word IDs.
Map<String, Object?> _compactEngine(PairMatchingState engine) {
  final ids = engine.plan.orderedLexicalItems.map((i) => i.wordId).toList();
  Map<String, Object?> attempt(
    Object? value,
  ) => (value as Map<String, Object?>).map(
    (key, value) => switch (key) {
      'promptWordId' => MapEntry('promptIndex', ids.indexOf(value as String)),
      'targetWordId' => MapEntry('targetIndex', ids.indexOf(value as String)),
      _ => MapEntry(key, value),
    },
  );
  final j = engine.toJson();
  return {
    ...j,
    'attempts': (j['attempts'] as List).map(attempt).toList(),
    'pending': j['pending'] == null ? null : attempt(j['pending']),
    'selected': engine.selected == null
        ? null
        : {
            'side': engine.selected!.side.name,
            'wordId': ids.indexOf(engine.selected!.wordId),
          },
    'matchedWordIds': engine.matchedWordIds.map(ids.indexOf).toList()..sort(),
    'supportedWordIds': engine.supportedWordIds.map(ids.indexOf).toList()
      ..sort(),
    'supportAtRevision': {
      for (final id in engine.supportedWordIds.toList()..sort())
        '${ids.indexOf(id)}': engine.supportAtRevision[id],
    },
  };
}

Map<String, Object?> _expandEngine(
  PairMatchingPlanV1 plan,
  Object? value,
  int version,
) {
  final ids = plan.orderedLexicalItems.map((i) => i.wordId).toList();
  Map<String, Object?> attempt(Object? value) {
    final a = (value as Map).cast<String, Object?>();
    if (a.containsKey('promptWordId') ||
        a.containsKey('targetWordId') ||
        !a.containsKey('promptIndex') ||
        !a.containsKey('targetIndex')) {
      throw const FormatException('Invalid Pair compact identity');
    }
    return a.map(
      (key, value) => switch (key) {
        'promptIndex' => MapEntry('promptWordId', ids[value as int]),
        'targetIndex' => MapEntry('targetWordId', ids[value as int]),
        _ => MapEntry(key, value),
      },
    );
  }

  final j = Map<String, Object?>.of((value as Map).cast<String, Object?>());
  if (version >= 2) {
    j['selected'] = j['selected'] == null
        ? null
        : {
            'side': (j['selected'] as Map)['side'],
            'wordId': ids[(j['selected'] as Map)['wordId'] as int],
          };
    j['matchedWordIds'] =
        (j['matchedWordIds'] as List).map((i) => ids[i as int]).toList()
          ..sort();
    j['supportedWordIds'] =
        (j['supportedWordIds'] as List).map((i) => ids[i as int]).toList()
          ..sort();
    final support = (j['supportAtRevision'] as Map).map(
      (key, value) => MapEntry(ids[int.parse(key as String)], value),
    );
    j['supportAtRevision'] = {
      for (final key in support.keys.toList()..sort()) key: support[key],
    };
  }
  return {
    ...j,
    'attempts': (j['attempts'] as List).map(attempt).toList(),
    'pending': j['pending'] == null ? null : attempt(j['pending']),
  };
}

abstract final class PairMatchingCheckpointCodec {
  static void validateTransition(
    PairMatchingCheckpointSnapshot prior,
    PairMatchingCheckpointSnapshot next,
  ) {
    if (prior.timer != null && next.timer == null) {
      throw StateError('Pair timer writer cannot downgrade');
    }
    final a =
        prior.timer ?? PairTimerState.initial(prior.engine.plan.timerPreset);
    final b =
        next.timer ?? PairTimerState.initial(next.engine.plan.timerPreset);
    final delta = b.elapsedActiveMs - a.elapsedActiveMs;
    if (delta < 0 ||
        delta > a.remainingActiveMs ||
        (a.extensionUsed && !b.extensionUsed)) {
      throw StateError('Pair active time/entitlement regressed');
    }
    final newDecision = b.lastOperationId != a.lastOperationId;
    if (!newDecision) {
      if (a.lastFingerprint != b.lastFingerprint ||
          a.mode != b.mode ||
          a.extensionUsed != b.extensionUsed ||
          a.remainingActiveMs - b.remainingActiveMs != delta ||
          prior.engine.roundOrdinal != next.engine.roundOrdinal) {
        throw StateError('Pair timer changed without decision');
      }
    } else {
      final roundChanged =
          next.engine.roundOrdinal != prior.engine.roundOrdinal;
      final action = roundChanged
          ? PairTimerAction.restart
          : switch (b.mode) {
              PairTimerMode.timeoutDecision => PairTimerAction.expire,
              PairTimerMode.continuedUntimed => PairTimerAction.continueUntimed,
              PairTimerMode.extendedRunning => PairTimerAction.extend,
              _ => throw StateError('Invalid Pair timer decision mode'),
            };
      final command = PairTimerDecision(
        operationId: b.lastOperationId!,
        ownerId: prior.engine.plan.ownerId,
        sessionId: prior.engine.plan.learningSessionId,
        roundOrdinal: prior.engine.roundOrdinal,
        expectedRevision: next.engine.operationRevision - 1,
        action: action,
      );
      if (command.fingerprint != b.lastFingerprint ||
          next.engine.lastOperationId != command.operationId ||
          next.engine.lastFingerprint != command.fingerprint ||
          next.engine.attempts.length != prior.engine.attempts.length ||
          prior.engine.pending != null ||
          next.engine.pending != null ||
          next.engine.selected != null ||
          jsonEncode(prior.engine.supportAtRevision) !=
              jsonEncode(next.engine.supportAtRevision) ||
          (!roundChanged &&
              jsonEncode(prior.engine.matchedWordIds.toList()..sort()) !=
                  jsonEncode(next.engine.matchedWordIds.toList()..sort()))) {
        throw StateError('Pair decision identity changed');
      }
      switch (action) {
        case PairTimerAction.expire:
          if (!a.timed ||
              a.remainingActiveMs != delta ||
              b.remainingActiveMs != 0 ||
              b.extensionUsed != a.extensionUsed) {
            throw StateError('Invalid Pair expiry');
          }
        case PairTimerAction.extend:
          if (a.mode != PairTimerMode.timeoutDecision ||
              a.extensionUsed ||
              !b.extensionUsed ||
              b.remainingActiveMs != 30000 ||
              delta != 0) {
            throw StateError('Invalid Pair extension');
          }
        case PairTimerAction.continueUntimed:
          if ((!a.timed &&
                  a.mode != PairTimerMode.timeoutDecision &&
                  !a.reasons.contains(PairPauseReason.clockFault)) ||
              b.remainingActiveMs != 0 ||
              b.extensionUsed != a.extensionUsed) {
            throw StateError('Invalid Pair Continue');
          }
        case PairTimerAction.restart:
          if (a.mode != PairTimerMode.timeoutDecision ||
              next.engine.roundOrdinal != prior.engine.roundOrdinal + 1 ||
              b.mode != PairTimerMode.running ||
              b.remainingActiveMs !=
                  PairTimerState.initial(
                    next.engine.plan.timerPreset,
                  ).remainingActiveMs ||
              delta != 0 ||
              b.extensionUsed != a.extensionUsed ||
              next.engine.matchedWordIds.isNotEmpty) {
            throw StateError('Invalid Pair restart');
          }
      }
    }
    final old = prior.terminal, terminal = next.terminal;
    if (old != null &&
        (terminal == null ||
            old.atUtc != terminal.atUtc ||
            (old.acknowledged && !terminal.acknowledged) ||
            (old.presented && !terminal.presented) ||
            jsonEncode(prior.engine.toJson()) !=
                jsonEncode(next.engine.toJson()) ||
            delta != 0 ||
            newDecision)) {
      throw StateError('Pair terminal changed');
    }
    if (terminal != null &&
        ((old == null && terminal.acknowledged) ||
            (terminal.presented && old?.acknowledged != true))) {
      throw StateError('Pair terminal receipt skipped');
    }
  }

  static int encodedBytes(Object? value) =>
      utf8.encode(jsonEncode(value)).length;

  /// Size-only upper bound for captureMatching's full frozen schema: its ten
  /// research identifier occurrences (five in each context) may each contain
  /// 256 scalars, each requiring six JSON bytes. Owner/actor/session and the
  /// largest word are measured exactly. Source IDs use their canonical bound.
  /// 4096 covers fixed keys, declarations, hashes, timestamps, booleans and
  /// 64-bit numeric fields; matching capture emits no assessment or contrastive
  /// payload. The actual frozen envelope is checked against this bound before
  /// admission, so a future schema expansion cannot silently consume reserve.
  static int frozenOccurrenceByteBound(PairMatchingPlanV1 plan) =>
      4096 +
      10 * 6 * LearningEvidenceContract.maxIdentifierLength +
      6 * LearningEvidenceContract.maxSourceEvidenceIdLength +
      2 * encodedBytes(plan.ownerId) +
      encodedBytes(plan.learningSessionId) +
      plan.orderedLexicalItems
          .map((i) => encodedBytes(i.wordId))
          .reduce((a, b) => a > b ? a : b);

  /// A size projection, never an evidence/context writer. It retains every
  /// existing row and budgets maximum JSON encodings for each remaining
  /// mandatory correct answer. The final pending envelope and 1024 bytes for
  /// terminal receipt metadata remain available in addition to those rows.
  static int reservedCompletionBytes(PairMatchingCheckpointSnapshot snapshot) {
    final state = snapshot.engine;
    final map =
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>;
    final engine = map['engine'] as Map<String, dynamic>;
    final attempts = engine['attempts'] as List;
    final ids = map['evidenceIds'] as List;
    const maxInt = 9223372036854775807;
    final maxOperationId = '${'\u0000' * 127}x';
    final maxEvidenceId =
        '${'\u0000' * (LearningEvidenceContract.maxSourceEvidenceIdLength - 1)}x';
    final pending = state.pending;
    if (pending != null) {
      attempts.add(engine['pending']);
      ids.add(snapshot.frozenEvidence?['sourceEvidenceId'] ?? maxEvidenceId);
    }
    final remaining =
        state.plan.orderedLexicalItems.length -
        state.matchedWordIds.length -
        (pending?.isCorrect == true ? 1 : 0);
    final projected = pending == null
        ? state
        : PairMatchingEngine.acknowledge(state, pending.operationId);
    final futureAttempts = projected.remainingRepairAttemptBound;
    for (var i = 0; i < futureAttempts; i++) {
      attempts.add({
        'operationId': maxOperationId,
        'fingerprint': 'f' * 64,
        'promptIndex': 5,
        'targetIndex': 5,
        'roundOrdinal': maxInt,
        'role': 'independentRetry',
        'responseTimeMs': LearningEvidenceContract.maxResponseTimeMs,
        'resolutionFingerprint': 'f' * 64,
      });
      ids.add(maxEvidenceId);
    }
    engine['pending'] = null;
    engine['selected'] = {'side': 'prompt', 'wordId': 5};
    engine['operationRevision'] = maxInt;
    engine['roundOrdinal'] = maxInt;
    engine['lastOperationId'] = maxOperationId;
    engine['lastFingerprint'] = 'f' * 64;
    engine['matchedWordIds'] = List.generate(
      state.plan.orderedLexicalItems.length,
      (i) => i,
    );
    engine['supportedWordIds'] = List.generate(
      state.plan.orderedLexicalItems.length,
      (i) => i,
    );
    engine['supportAtRevision'] = {
      for (var i = 0; i < state.plan.orderedLexicalItems.length; i++)
        '$i': maxInt,
    };
    map['frozenEvidence'] = null;
    // Reserve the actual bounded timer schema even for immutable PM1 starts.
    map['timer'] = PairTimerState.initial(state.plan.timerPreset)
        .copy(
          mode: PairTimerMode.continuedUntimed,
          remainingActiveMs: maxInt,
          elapsedActiveMs: maxInt,
          reasons: PairPauseReason.values.toSet(),
          lastOperationId: maxOperationId,
          lastFingerprint: 'f' * 64,
        )
        .toJson();
    map['roundSeed'] = 2147483647;
    return encodedBytes(map) +
        ((remaining > 0 || pending != null)
            ? frozenOccurrenceByteBound(state.plan)
            : 0) +
        1024;
  }

  static void requireCompletionCapacity(
    PairMatchingCheckpointSnapshot snapshot,
  ) {
    if (reservedCompletionBytes(snapshot) >
        PairMatchingCheckpointBudget.maximumBytes) {
      throw StateError('Pair byte capacity reserved for remaining completion');
    }
    if (snapshot.frozenEvidence != null &&
        encodedBytes(snapshot.frozenEvidence) >
            frozenOccurrenceByteBound(snapshot.engine.plan)) {
      throw StateError(
        'Pair frozen occurrence exceeds supported schema budget',
      );
    }
  }

  /// These bytes intentionally remain exactly the accepted PM1 start shape.
  static Map<String, Object?> initialState(
    PairMatchingPlanV1 plan,
    String operation,
  ) =>
      _freeze({
            'schemaVersion': 6,
            'planFingerprint': plan.planFingerprint,
            'plan': plan.toJson(),
            'startOperation': operation,
            'roundOrdinal': 0,
            'operationRevision': 0,
            'selectedTileId': null,
            'matchedPairIds': <String>[],
            'firstOpportunityLedger': <Object?>[],
            'repairTickets': <Object?>[],
            'activeElapsedMs': 0,
            'extensionUsed': false,
            'pendingOperation': null,
          })
          as Map<String, Object?>;

  static PairMatchingCheckpointSnapshot decode(Map<String, Object?> source) {
    try {
      if (utf8.encode(jsonEncode(source)).length >
          PairMatchingCheckpointBudget.maximumBytes) {
        throw const FormatException('Pair checkpoint too large');
      }
      final plan = PairMatchingPlanV1.fromStableSerialization(
        jsonEncode(source['plan']),
      );
      final version = source['codecVersion'];
      final compactStart = version == 2 || version == 3
          ? pairJson(source['startOperation'], {
              'schemaVersion',
              'launchOperationId',
              'appVersion',
              'buildId',
              if ((source['startOperation'] as Map)['schemaVersion'] == 2)
                'sessionConfiguration',
            })
          : null;
      final operation = compactStart == null
          ? source['startOperation'] as String
          : jsonEncode({
              'schemaVersion': compactStart['schemaVersion'],
              'plan': plan.toJson(),
              'launchOperationId': compactStart['launchOperationId'],
              'appVersion': compactStart['appVersion'],
              'buildId': compactStart['buildId'],
              if (compactStart['schemaVersion'] == 2)
                'sessionConfiguration': compactStart['sessionConfiguration'],
            });
      final start = pairJson(jsonDecode(operation), {
        'schemaVersion',
        'plan',
        'launchOperationId',
        'appVersion',
        'buildId',
        if ((jsonDecode(operation) as Map)['schemaVersion'] == 2)
          'sessionConfiguration',
      });
      if (source['schemaVersion'] != 6 ||
          source['planFingerprint'] != plan.planFingerprint ||
          plan.sourceSessionId == plan.learningSessionId ||
          (start['schemaVersion'] != 1 && start['schemaVersion'] != 2) ||
          jsonEncode(start['plan']) != plan.stableSerialization ||
          pairSessionId(plan.ownerId, start['launchOperationId'] as String) !=
              plan.learningSessionId ||
          ['launchOperationId', 'appVersion', 'buildId'].any(
            (k) =>
                start[k] is! String ||
                (start[k] as String).isEmpty ||
                (start[k] as String).length > 256 ||
                start[k] != (start[k] as String).trim(),
          ) ||
          jsonEncode(start) != operation) {
        throw const FormatException('Invalid Pair checkpoint start binding');
      }
      if (!source.containsKey('codecVersion')) {
        if (jsonEncode(source) != jsonEncode(initialState(plan, operation))) {
          throw const FormatException('Invalid Pair initial checkpoint');
        }
        return PairMatchingCheckpointSnapshot(
          engine: PairMatchingState.initial(plan),
          startOperation: operation,
        );
      }
      final j = pairJson(source, {
        'schemaVersion',
        'codecVersion',
        'planFingerprint',
        'plan',
        'startOperation',
        'engine',
        'evidenceIds',
        'frozenEvidence',
        if (version == 3) ...{'timer', 'roundSeed', 'terminal'},
      });
      final engine = PairMatchingState.fromJson(
        plan,
        _expandEngine(plan, j['engine'], j['codecVersion'] as int),
      );
      if ((version == 2 || version == 3) &&
          jsonEncode(_compactEngine(engine)) != jsonEncode(j['engine'])) {
        throw const FormatException('Invalid Pair compact engine');
      }
      final ids = (j['evidenceIds'] as List).cast<String>();
      final frozen = j['frozenEvidence'] == null
          ? null
          : (j['frozenEvidence'] as Map).cast<String, Object?>();
      if ((j['codecVersion'] != 1 &&
              j['codecVersion'] != 2 &&
              j['codecVersion'] != 3) ||
          ids.length != engine.attempts.length ||
          ids.toSet().length != ids.length ||
          ids.any(
            (id) => !LearningEvidenceContract.validSourceEvidenceId(id),
          ) ||
          (frozen == null) != (engine.pending == null)) {
        throw const FormatException('Invalid Pair pending binding');
      }
      if (frozen != null) {
        final a = engine.pending!;
        if (frozen['ownerId'] != plan.ownerId ||
            frozen['actorIdentity'] != plan.ownerId ||
            frozen['sessionId'] != plan.learningSessionId ||
            frozen['wordId'] != a.promptWordId ||
            frozen['isCorrect'] != a.isCorrect ||
            frozen['responseTimeMs'] != a.responseTimeMs ||
            frozen['attemptNumber'] != ids.length + 1 ||
            ids.contains(frozen['sourceEvidenceId']) ||
            frozen['promptMode'] != 'matchingPair' ||
            frozen['providerProvenance'] != 'pinned-lexical-matching' ||
            frozen['input'] != 'matchingPair' ||
            frozen['hintLevel'] !=
                (plan.sessionPurpose == PairSessionPurpose.practiceReplay
                    ? 0
                    : engine.classificationFor(a).hintLevel)) {
          throw const FormatException('Invalid Pair frozen occurrence');
        }
      }
      final timer = version == 3 ? PairTimerState.fromJson(j['timer']) : null;
      final terminal = version == 3 && j['terminal'] != null
          ? PairTerminalState.fromJson(j['terminal'])
          : null;
      if (timer?.lastOperationId != null) {
        final id = timer!.lastOperationId!;
        final revision = int.parse(id.split(':').first);
        final action = switch (timer.mode) {
          PairTimerMode.timeoutDecision => PairTimerAction.expire,
          PairTimerMode.extendedRunning => PairTimerAction.extend,
          PairTimerMode.continuedUntimed => PairTimerAction.continueUntimed,
          PairTimerMode.running => PairTimerAction.restart,
          PairTimerMode.off => throw const FormatException(
            'OFF cannot have timer decision',
          ),
        };
        final command = PairTimerDecision(
          operationId: id,
          ownerId: plan.ownerId,
          sessionId: plan.learningSessionId,
          roundOrdinal:
              engine.roundOrdinal - (action == PairTimerAction.restart ? 1 : 0),
          expectedRevision: revision,
          action: action,
        );
        if (revision >= engine.operationRevision ||
            command.fingerprint != timer.lastFingerprint ||
            (revision == engine.operationRevision - 1 &&
                (engine.lastOperationId != id ||
                    engine.lastFingerprint != command.fingerprint))) {
          throw const FormatException('Pair timer decision binding changed');
        }
      } else if (timer != null &&
          (timer.extensionUsed ||
              engine.roundOrdinal != 0 ||
              (timer.mode != PairTimerMode.off &&
                  timer.mode != PairTimerMode.running))) {
        throw const FormatException('Pair timer decision missing');
      }
      if ((version != 3 && engine.roundOrdinal != 0) ||
          (version == 3 && j['roundSeed'] != engine.roundSeed) ||
          (terminal != null && (!engine.complete || engine.pending != null)) ||
          (timer != null &&
              plan.timerPreset == PairTimerPreset.off &&
              (timer.mode != PairTimerMode.off ||
                  timer.extensionUsed ||
                  timer.elapsedActiveMs != 0))) {
        throw const FormatException('Invalid Pair timer/terminal pins');
      }
      return PairMatchingCheckpointSnapshot(
        engine: engine,
        startOperation: operation,
        evidenceIds: ids,
        frozenEvidence: frozen,
        timer: timer,
        terminal: terminal,
      );
    } catch (_) {
      throw const FormatException('Invalid Pair checkpoint');
    }
  }
}
