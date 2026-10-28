import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/lexical_prompt_artifact_identity.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_active_clock.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_session_purpose.dart';
import 'package:vocab_learning_app/features/research/domain/research_session_proof.dart';

const _owner = 'owner:a';
const _start = 1785808800000;

Map<String, Object?> _plain({int phase = 1}) {
  final payload = <String, Object?>{
    'schema': 'lexiquest.research-session-proof.v1',
    'ownerId': _owner,
    'measurementRunId': 'run:a',
    'learningSessionId': 'session:a',
    'proofRevision': phase,
    'activityType': 'quiz',
    'sessionState': phase == 1 ? 'active' : 'completed',
    'startedAtUtcMs': _start,
    'endedAtUtcMs': phase == 1 ? null : _start + 1000,
    'appVersion': '1',
    'buildId': 'synthetic',
    'sessionConfigurationIdentity': null,
    'sessionConfigurationJson': null,
    'pairStartOperation': null,
    'pairCheckpointEventVersion': null,
    'pairOwnerLineage': null,
    'permitId': 'permit:a',
    'permitPayloadSha256': 'a' * 64,
    'permitRevision': 1,
  };
  payload['id'] = _id(payload);
  return payload;
}

String _id(Map<String, Object?> p) =>
    'research-session-proof:${sha256.convert(utf8.encode(jsonEncode([p['ownerId'], p['permitId'], p['measurementRunId'], p['learningSessionId'], p['proofRevision']])))}';

Map<String, Object?> _copy(Map<String, Object?> p) =>
    (jsonDecode(jsonEncode(p)) as Map).cast<String, Object?>();

void main() {
  _extendedProofTests();
  test(
    'phase identity uses the exact owner permit run session phase array',
    () {
      final payload = _plain();
      expect(
        ResearchSessionProof.identityFor(
          ownerId: _owner,
          permitId: 'permit:a',
          measurementRunId: 'run:a',
          learningSessionId: 'session:a',
          proofRevision: 1,
        ),
        payload['id'],
      );
      final proof = ResearchSessionProof.decode(payload);
      expect(proof.toJson(), payload);
      payload['appVersion'] = 'changed-after-decode';
      expect(proof.toJson()['appVersion'], '1');
    },
  );

  test(
    'completed-first and later started facts have one immutable start core',
    () {
      final completed = ResearchSessionProof.decode(_plain(phase: 2));
      final started = ResearchSessionProof.decode(_plain());
      expect(completed.hasSameStartCore(started), isTrue);
      expect(started.hasSameStartCore(completed), isTrue);
      expect(completed.toSessionProjection()['state'], 'completed');
      expect(completed.toSessionProjection()['ended_at_utc_ms'], _start + 1000);
      expect(started.toSessionProjection()['ended_at_utc_ms'], isNull);
    },
  );

  for (final field in [
    'ownerId',
    'permitId',
    'measurementRunId',
    'learningSessionId',
    'appVersion',
    'buildId',
    'permitPayloadSha256',
    'permitRevision',
    'startedAtUtcMs',
  ]) {
    test('sibling start core detects changed $field', () {
      final altered = _plain(phase: 2);
      altered[field] = switch (field) {
        'permitRevision' => 2,
        'startedAtUtcMs' => _start + 1,
        'permitPayloadSha256' => 'b' * 64,
        _ => '${altered[field]}:other',
      };
      altered['id'] = _id(altered);
      expect(
        ResearchSessionProof.decode(
          _plain(),
        ).hasSameStartCore(ResearchSessionProof.decode(altered)),
        isFalse,
      );
    });
  }

  for (final mutation in [
    'unknown-key',
    'string-phase',
    'bad-id',
    'active-end',
    'completed-no-end',
    'end-before-start',
    'one-null-config',
    'bad-config',
    'utf8-overflow',
  ]) {
    test('strict proof rejects $mutation without exposing input', () {
      final p = _plain();
      switch (mutation) {
        case 'unknown-key':
          p['fullCheckpointHistory'] = [];
        case 'string-phase':
          p['proofRevision'] = '1';
        case 'bad-id':
          p['id'] = 'research-session-proof:wrong';
        case 'active-end':
          p['endedAtUtcMs'] = _start;
        case 'completed-no-end':
          p['proofRevision'] = 2;
          p['sessionState'] = 'completed';
          p['id'] = _id(p);
        case 'end-before-start':
          p['proofRevision'] = 2;
          p['sessionState'] = 'completed';
          p['endedAtUtcMs'] = _start - 1;
          p['id'] = _id(p);
        case 'one-null-config':
          p['sessionConfigurationIdentity'] = 'synthetic-canary';
        case 'bad-config':
          p['sessionConfigurationIdentity'] = 'synthetic-canary';
          p['sessionConfigurationJson'] = '{"canary":"synthetic-canary"}';
        case 'utf8-overflow':
          p['buildId'] = 'ก' * 44000;
          expect(jsonEncode(p).length, lessThan(131072));
          expect(utf8.encode(jsonEncode(p)).length, greaterThan(131072));
      }
      expect(
        () => ResearchSessionProof.decode(p),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'bounded message',
            isNot(contains('synthetic-canary')),
          ),
        ),
      );
    });
  }

  for (final phase in [1, 2]) {
    for (final eventVersion in [1, 2]) {
      test(
        'Pair initial v$eventVersion reconstructs phase$phase without invented terminal history',
        () {
          final f = _PairRows(phase: phase, eventVersion: eventVersion);
          // Verify the existing pure decoder itself supports this projection.
          expect(
            PairMatchingSessionPurpose.decode(
              ownerId: _owner,
              session: f.session,
              checkpoints: [f.checkpoint],
              historicalOwners: f.owners,
            ).allowsLearningAuthority,
            isTrue,
          );
          final proof = f.proof();
          expect(
            ResearchSessionProof.decode(proof.toJson()).toJson(),
            proof.toJson(),
          );
          expect(
            proof.toSessionProjection()['state'],
            phase == 1 ? 'active' : 'completed',
          );
          expect(proof.toJson()['pairCheckpointEventVersion'], eventVersion);
          expect((proof.toJson()['pairOwnerLineage'] as List), hasLength(1));
          final frozenPayload = _copy(proof.toJson());
          f.owners.single['created_at_utc_ms'] = _start + 9999;
          expect(
            proof.toJson(),
            frozenPayload,
            reason: 'Nested source maps cannot mutate an admitted proof.',
          );
          final leaked = jsonEncode(proof.toJson());
          expect(leaked, isNot(contains('payload_json')));
          expect(leaked, isNot(contains('firebase_uid')));
        },
      );
    }
  }

  test(
    'source validates full Pair prefix instead of silently taking initial only',
    () {
      final f = _PairRows();
      final corruptLater = Map<String, Object?>.from(f.checkpoint)
        ..['payload_json'] = '{"schemaVersion":1,"revision":2,"state":{}}';
      expect(
        () => f.proof(checkpoints: [f.checkpoint, corruptLater]),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('practice replay cannot become a learning session proof', () {
    final f = _PairRows(replay: true);
    expect(
      PairMatchingSessionPurpose.decode(
        ownerId: _owner,
        session: f.session,
        checkpoints: [f.checkpoint],
        historicalOwners: f.owners,
      ).isReplay,
      isTrue,
    );
    expect(() => f.proof(), throwsA(isA<FormatException>()));
  });

  for (final field in [
    'pairOwnerLineage',
    'pairStartOperation',
    'sessionConfigurationIdentity',
    'startedAtUtcMs',
    'appVersion',
  ]) {
    test('Pair proof rejects tampered $field', () {
      final p = _copy(_PairRows().proof().toJson());
      switch (field) {
        case 'pairOwnerLineage':
          (p[field] as List).single['mergedIntoOwnerId'] = 'foreign-owner';
        case 'pairStartOperation':
          p[field] = 'synthetic-invalid-start';
        case 'startedAtUtcMs':
          p[field] = _start + 1;
        default:
          p[field] = 'synthetic-other';
      }
      expect(
        () => ResearchSessionProof.decode(p),
        throwsA(isA<FormatException>()),
      );
    });
  }
}

void _extendedProofTests() {
  test(
    'completed full Pair prefix is validated before deriving started facts',
    () {
      final fixture = _PairRows(phase: 2);
      final prefix = _completedPrefix(fixture);
      _expectPurpose(fixture, prefix);
      expect(
        PairMatchingSessionPurpose.decode(
          ownerId: _owner,
          session: fixture.session,
          checkpoints: prefix,
          historicalOwners: fixture.owners,
        ).snapshot!.terminal!.acknowledged,
        isTrue,
      );
      final completed = fixture.proof(checkpoints: prefix);
      final started = fixture.proof(checkpoints: prefix, phase: 1);
      expect(started.toSessionProjection()['state'], 'active');
      expect(started.toSessionProjection()['ended_at_utc_ms'], isNull);
      expect(completed.toSessionProjection()['ended_at_utc_ms'], _start + 1000);
      expect(started.hasSameStartCore(completed), isTrue);
      expect(completed.hasSameStartCore(started), isTrue);
      expect(
        started.toJson()['pairStartOperation'],
        fixture.operation.stableSerialization,
      );
      expect(
        ResearchSessionProof.decode(completed.toJson()).toJson(),
        completed.toJson(),
      );
      expect(fixture.session['state'], 'completed');
    },
  );

  test('valid measured revision2 retains only the immutable initial proof', () {
    final fixture = _PairRows();
    final prefix = [
      fixture.checkpoint,
      _checkpointRow(fixture, 2, _measured(fixture)),
    ];
    _expectPurpose(fixture, prefix);
    expect(
      fixture.proof(checkpoints: prefix).toJson(),
      fixture.proof().toJson(),
    );
  });

  test('valid later envelope rejects measured admission at the wrong time', () {
    final fixture = _PairRows();
    final measured = _measured(fixture);
    expect(
      PairMatchingCheckpointCodec.decode(measured.toJson()).toJson(),
      measured.toJson(),
    );
    final later = _checkpointRow(fixture, 2, measured, atMs: _start + 1000);
    final prefix = [fixture.checkpoint, later];
    expect(
      () => PairMatchingSessionPurpose.decode(
        ownerId: _owner,
        session: fixture.session,
        checkpoints: prefix,
        historicalOwners: fixture.owners,
      ),
      throwsStateError,
    );
    expect(
      () => fixture.proof(checkpoints: prefix),
      throwsA(isA<FormatException>()),
    );
  });

  test('active canonical Pair cannot supply a completed phase', () {
    final fixture = _PairRows();
    _expectPurpose(fixture, [fixture.checkpoint]);
    expect(() => fixture.proof(phase: 2), throwsA(isA<FormatException>()));
  });

  test('abandoned canonical Pair preserves its original started facts', () {
    final fixture = _PairRows();
    fixture.session['state'] = 'abandoned';
    final prefix = [
      fixture.checkpoint,
      _checkpointRow(fixture, 2, _measured(fixture)),
    ];
    _expectPurpose(fixture, prefix);
    final proof = fixture.proof(checkpoints: prefix);
    expect(proof.toSessionProjection()['state'], 'active');
    expect(proof.toSessionProjection()['ended_at_utc_ms'], isNull);
    expect(proof.toJson()['startedAtUtcMs'], _start);
    expect(
      ResearchSessionProof.decode(proof.toJson()).toJson(),
      proof.toJson(),
    );
    expect(fixture.session['state'], 'abandoned');
  });

  test('abandoned canonical Pair cannot supply a completed phase', () {
    final fixture = _PairRows();
    fixture.session['state'] = 'abandoned';
    _expectPurpose(fixture, [fixture.checkpoint]);
    expect(() => fixture.proof(phase: 2), throwsA(isA<FormatException>()));
  });

  test(
    'merged Pair keeps P start and projects R configuration with compact lineage',
    () {
      final fixture = _mergedRows();
      _expectPurpose(fixture, [fixture.checkpoint]);
      final proof = fixture.proof();
      final payload = proof.toJson();
      expect(payload['ownerId'], 'owner:z');
      expect(
        payload['pairStartOperation'],
        fixture.operation.stableSerialization,
      );
      expect(
        payload['sessionConfigurationIdentity'],
        fixture.session['session_configuration_identity'],
      );
      expect(
        payload['sessionConfigurationJson'],
        fixture.session['session_configuration_json'],
      );
      expect(proof.toSessionProjection()['owner_id'], 'owner:z');
      expect(payload['pairOwnerLineage'], [
        {
          'ownerId': _owner,
          'createdAtUtcMs': _start - 1000,
          'upgradedAtUtcMs': _start + 500,
          'mergedIntoOwnerId': 'owner:z',
        },
        {
          'ownerId': 'owner:z',
          'createdAtUtcMs': _start - 500,
          'upgradedAtUtcMs': _start + 500,
          'mergedIntoOwnerId': null,
        },
      ]);
      expect(ResearchSessionProof.decode(payload).toJson(), payload);
      for (final secret in [
        'unrelated-owner',
        'firebase_uid',
        'synthetic-uid-private',
        'display_name',
        'synthetic-private-name',
      ]) {
        expect(jsonEncode(payload), isNot(contains(secret)));
      }
    },
  );

  for (final phase in [1, 2]) {
    test(
      'unconfigured Pair schema1 roundtrips phase$phase without invented config',
      () {
        final fixture = _PairRows(phase: phase, configured: false);
        expect(
          (jsonDecode(fixture.operation.stableSerialization)
              as Map)['schemaVersion'],
          1,
        );
        _expectPurpose(fixture, [fixture.checkpoint]);
        final proof = fixture.proof();
        expect(
          proof.toJson(),
          containsPair('sessionConfigurationIdentity', null),
        );
        expect(proof.toJson(), containsPair('sessionConfigurationJson', null));
        expect(
          ResearchSessionProof.decode(proof.toJson()).toJson(),
          proof.toJson(),
        );
      },
    );
  }

  for (final field in [
    'endedAtUtcMs',
    'sessionConfigurationIdentity',
    'sessionConfigurationJson',
    'pairStartOperation',
    'pairCheckpointEventVersion',
    'pairOwnerLineage',
  ]) {
    test('required nullable proof key cannot be omitted $field', () {
      final payload = _plain()..remove(field);
      expect(
        () => ResearchSessionProof.decode(payload),
        throwsA(isA<FormatException>()),
      );
    });
  }

  for (final mutation in [
    'schema',
    'phase0',
    'phase3',
    'bool-phase',
    'double-start',
    'string-start',
    'negative-start',
    'bool-permit-revision',
    'zero-permit-revision',
    'invalid-digest',
    'wrong-state',
    'opposite-null-config',
    'nonmatching-pair-fields',
  ]) {
    test('strict proof scalar contract rejects $mutation', () {
      final payload = _plain();
      switch (mutation) {
        case 'schema':
          payload['schema'] = 'lexiquest.research-session-proof.v2';
        case 'phase0':
          payload['proofRevision'] = 0;
          payload['id'] = _id(payload);
        case 'phase3':
          payload['proofRevision'] = 3;
          payload['id'] = _id(payload);
        case 'bool-phase':
          payload['proofRevision'] = true;
          payload['id'] = _id(payload);
        case 'double-start':
          payload['startedAtUtcMs'] = _start.toDouble();
        case 'string-start':
          payload['startedAtUtcMs'] = '$_start';
        case 'negative-start':
          payload['startedAtUtcMs'] = -1;
        case 'bool-permit-revision':
          payload['permitRevision'] = true;
        case 'zero-permit-revision':
          payload['permitRevision'] = 0;
        case 'invalid-digest':
          payload['permitPayloadSha256'] = 'g' * 64;
        case 'wrong-state':
          payload['sessionState'] = 'completed';
          payload['endedAtUtcMs'] = _start;
        case 'opposite-null-config':
          payload['sessionConfigurationJson'] =
              _PairRows().operation.configuration!.stableSerialization;
        case 'nonmatching-pair-fields':
          final pair = _PairRows().proof().toJson();
          for (final key in [
            'pairStartOperation',
            'pairCheckpointEventVersion',
            'pairOwnerLineage',
          ]) {
            payload[key] = pair[key];
          }
      }
      expect(
        () => ResearchSessionProof.decode(payload),
        throwsA(isA<FormatException>()),
      );
    });
  }

  for (final field in [
    'pairStartOperation',
    'pairCheckpointEventVersion',
    'pairOwnerLineage',
  ]) {
    test('matching proof requires every Pair field $field', () {
      final payload = _copy(_PairRows().proof().toJson())..[field] = null;
      expect(
        () => ResearchSessionProof.decode(payload),
        throwsA(isA<FormatException>()),
      );
    });
  }

  for (final mutation in [
    'duplicate',
    'third-owner',
    'private-key',
    'wrong-target',
    'missing-actor',
    'created-after-start',
    'string-time',
  ]) {
    test('strict compact Pair lineage rejects $mutation', () {
      final payload = _copy(_mergedRows().proof().toJson());
      final lineage = payload['pairOwnerLineage'] as List;
      switch (mutation) {
        case 'duplicate':
          lineage.add(Map<String, Object?>.from(lineage.first as Map));
        case 'third-owner':
          lineage.add({
            'ownerId': 'owner:third',
            'createdAtUtcMs': 0,
            'upgradedAtUtcMs': _start + 500,
            'mergedIntoOwnerId': 'owner:z',
          });
        case 'private-key':
          (lineage.first as Map)['firebaseUid'] = 'synthetic-private';
        case 'wrong-target':
          (lineage.first as Map)['mergedIntoOwnerId'] = 'owner:foreign';
        case 'missing-actor':
          lineage.removeAt(0);
        case 'created-after-start':
          (lineage.first as Map)['createdAtUtcMs'] = _start + 1;
        case 'string-time':
          (lineage.first as Map)['createdAtUtcMs'] = '$_start';
      }
      expect(
        () => ResearchSessionProof.decode(payload),
        throwsA(isA<FormatException>()),
      );
    });
  }

  for (final field in [
    'configuration',
    'startOperation',
    'eventVersion',
    'lineage',
  ]) {
    test('valid Pair siblings compare immutable $field in both directions', () {
      final original = _PairRows().proof();
      final other = switch (field) {
        'configuration' => _PairRows(phase: 2, hintBudget: 1),
        'startOperation' => _PairRows(phase: 2, shuffleSeed: 53),
        'eventVersion' => _PairRows(phase: 2, eventVersion: 2),
        _ => _PairRows(phase: 2),
      };
      if (field == 'lineage')
        other.owners.single['created_at_utc_ms'] = _start - 2000;
      _expectPurpose(other, [other.checkpoint]);
      final changed = ResearchSessionProof.decode(other.proof().toJson());
      expect(original.hasSameStartCore(changed), isFalse);
      expect(changed.hasSameStartCore(original), isFalse);
    });
  }

  test(
    'returned nested proof values and session projection cannot mutate admitted facts',
    () {
      final proof = _mergedRows().proof();
      final frozen = _copy(proof.toJson());
      final projection = Map<String, Object?>.from(proof.toSessionProjection());
      final exposed = proof.toJson();
      try {
        ((exposed['pairOwnerLineage'] as List).first as Map)['ownerId'] =
            'changed';
      } on UnsupportedError {
        /* Immutable containers are also acceptable. */
      }
      try {
        (exposed['pairOwnerLineage'] as List).clear();
      } on UnsupportedError {
        /* A fresh defensive copy may instead be mutable. */
      }
      final session = proof.toSessionProjection();
      try {
        session['owner_id'] = 'changed';
      } on UnsupportedError {
        /* Either approach must preserve proof internals. */
      }
      expect(proof.toJson(), frozen);
      expect(proof.toSessionProjection(), projection);
      expect(
        proof.hasSameStartCore(ResearchSessionProof.decode(frozen)),
        isTrue,
      );
    },
  );
}

Map<String, Object?> _checkpointRow(
  _PairRows fixture,
  int revision,
  PairMatchingCheckpointSnapshot snapshot, {
  int atMs = _start,
}) {
  final actor = fixture.operation.plan.ownerId;
  final sessionId = fixture.session['id'] as String;
  final key = PairMatchingSessionPurpose.checkpointKey(
    actor,
    sessionId,
    revision,
  );
  return {
    ...fixture.checkpoint,
    'event_id': key,
    'idempotency_key': key,
    'event_version': 2,
    'occurred_at_utc': atMs ~/ 1000,
    'recorded_at_utc': atMs ~/ 1000,
    'payload_json': jsonEncode({
      'schemaVersion': 2,
      'activityType': 'matching',
      'sessionId': sessionId,
      'revision': revision,
      'state': snapshot.toJson(),
      'terminalAtUtc': snapshot.terminal?.atUtc.toIso8601String(),
      'terminalAcknowledged': snapshot.terminal?.acknowledged ?? false,
    }),
  };
}

PairMatchingCheckpointSnapshot _measured(_PairRows fixture) =>
    PairMatchingCheckpointSnapshot(
      engine: PairMatchingState.initial(fixture.operation.plan),
      startOperation: fixture.operation.stableSerialization,
      timer: PairTimerState.initial(
        fixture.operation.plan.timerPreset,
      ).copy(interactiveElapsedMs: 0),
    );

void _expectPurpose(_PairRows fixture, List<Map<String, Object?>> prefix) {
  expect(
    PairMatchingSessionPurpose.decode(
      ownerId: fixture.session['owner_id'] as String,
      session: fixture.session,
      checkpoints: prefix,
      historicalOwners: fixture.owners,
    ).allowsLearningAuthority,
    isTrue,
  );
}

// A complete pure prefix, including each pending reservation before its
// acknowledgement. It exercises existing engine/context serializers only.
List<Map<String, Object?>> _completedPrefix(_PairRows fixture) {
  final operation = fixture.operation;
  var engine = PairMatchingState.initial(operation.plan);
  final timer = _measured(fixture).timer!;
  final ids = <String>[];
  final prefix = [
    fixture.checkpoint,
    _checkpointRow(fixture, 2, _measured(fixture)),
  ];
  void append({Map<String, Object?>? frozen, PairTerminalState? terminal}) {
    prefix.add(
      _checkpointRow(
        fixture,
        prefix.length + 1,
        PairMatchingCheckpointSnapshot(
          engine: engine,
          startOperation: operation.stableSerialization,
          timer: timer,
          evidenceIds: ids,
          frozenEvidence: frozen,
          terminal: terminal,
        ),
        atMs: terminal?.atUtc.millisecondsSinceEpoch ?? _start,
      ),
    );
  }

  for (final item in operation.plan.orderedLexicalItems) {
    for (final side in PairTileSide.values) {
      final revision = engine.operationRevision;
      engine = PairMatchingEngine.reduce(
        engine,
        PairSelectTile(
          operationId: '$revision:proof-select',
          ownerId: operation.plan.ownerId,
          sessionId: operation.plan.learningSessionId,
          roundOrdinal: 0,
          expectedRevision: revision,
          tile: PairTile(side, item.wordId),
          responseTimeMs: 0,
        ),
      ).state;
      if (engine.pending == null) append();
    }
    final pending = engine.pending!;
    final classification = engine.classificationFor(pending);
    final content = LexicalPromptArtifactResolver.resolveForAdapter(
      promptMode: 'matchingPair',
      wordId: item.wordId,
      coreRevision: item.contentRevision,
      coreChecksumSha256: item.checksum,
    )!;
    final context = EvidenceContext.legacyCompatibility(
      evidenceClass: classification.evidenceClass,
      skillId: 'matching-recognition',
      hintLevel: classification.hintLevel,
      contentRevision: content.evidenceContentRevision,
      engagementAllowed: true,
    );
    final evidenceId = 'evidence:proof:${ids.length}';
    final frozen = FrozenPendingCurrentActivityEvidence.fromJson({
      'schemaVersion':
          FrozenPendingCurrentActivityEvidence.currentSchemaVersion,
      'ownerId': operation.plan.ownerId,
      'actorIdentity': operation.plan.ownerId,
      'sourceEvidenceId': evidenceId,
      'occurredAtUtc': operation.plan.createdAtUtc.toIso8601String(),
      'sessionId': operation.plan.learningSessionId,
      'wordId': item.wordId,
      'promptMode': 'matchingPair',
      'isCorrect': true,
      'responseTimeMs': 0,
      'attemptNumber': ids.length + 1,
      'providerProvenance': 'pinned-lexical-matching',
      'input': 'matchingPair',
      'hintLevel': classification.hintLevel,
      'declaration': {
        'evidenceClass': classification.evidenceClass.name,
        'skillId': 'matching-recognition',
        'promptMode': 'matchingPair',
        'contentRevision': content.evidenceContentRevision,
      },
      'contrastiveFeedback': null,
      'evidenceContext': context.toJson(),
      'eventContext': LearningEventContext.noResearch(context).toJson(),
    }).toJson();
    append(frozen: frozen);
    ids.add(evidenceId);
    engine = PairMatchingEngine.acknowledge(engine, pending.operationId);
    append();
  }
  expect(engine.complete, isTrue);
  final end = DateTime.fromMillisecondsSinceEpoch(_start + 1000, isUtc: true);
  append(terminal: PairTerminalState(end));
  append(terminal: PairTerminalState(end, acknowledged: true));
  return prefix;
}

_PairRows _mergedRows() {
  final fixture = _PairRows();
  const current = 'owner:z';
  final projected = PairMatchingSessionPurpose.projectConfigurationOwner(
    fixture.operation.configuration,
    current,
  )!;
  fixture.session.addAll({
    'owner_id': current,
    'session_configuration_identity': projected.contentIdentity,
    'session_configuration_json': projected.stableSerialization,
  });
  fixture.checkpoint['owner_id'] = current;
  fixture.owners.single.addAll({
    'is_active': 0,
    'account_state': 'mergedInto:$current',
    'upgraded_at_utc_ms': _start + 500,
  });
  fixture.owners.addAll([
    {
      'id': current,
      'created_at_utc_ms': _start - 500,
      'upgraded_at_utc_ms': _start + 500,
      'is_active': 1,
      'account_state': 'firebaseBound',
      'firebase_uid': 'synthetic-uid-private',
    },
    {
      'id': 'unrelated-owner',
      'created_at_utc_ms': 0,
      'upgraded_at_utc_ms': null,
      'is_active': 0,
      'account_state': 'localGuest',
      'display_name': 'synthetic-private-name',
    },
  ]);
  return fixture;
}

// Uses the same real plan/configuration/start serializers and row shape as
// test/support/pair_purpose_fixture.dart; no database or codec stand-in.
final class _PairRows {
  _PairRows({
    int phase = 1,
    int eventVersion = 1,
    bool replay = false,
    bool configured = true,
    int shuffleSeed = 52,
    int hintBudget = 0,
  }) {
    proofPhase = phase;
    final at = DateTime.fromMillisecondsSinceEpoch(_start, isUtc: true);
    final sessionId = pairSessionId(_owner, 'synthetic-proof-start');
    final plan = PairMatchingPlanV1(
      ownerId: _owner,
      orderedLexicalItems: [
        for (var i = 0; i < 4; i++)
          PairLexicalItem(
            wordId: 'synthetic-$i',
            contentRevision: 1,
            checksum: 'a' * 64,
            spelling: 'word$i',
            meaning: 'คำ$i',
            sourceLocale: 'en',
            targetLocale: 'th',
            sourceReasons: {PairSourceReason.dueSrs},
          ),
      ],
      direction: PairDirection.enToTh,
      density: PairDensity.compact4,
      shuffleSeed: shuffleSeed,
      timerPreset: PairTimerPreset.off,
      allowlistVersion: 'synthetic',
      learningSessionId: sessionId,
      entryKind: PairSourceSurface.learn,
      sourceSnapshotId: 'synthetic',
      createdAtUtc: at,
      sessionPurpose: replay
          ? PairSessionPurpose.practiceReplay
          : PairSessionPurpose.learning,
      sourceSessionId: replay ? 'synthetic-terminal-source' : null,
    );
    final config = configured
        ? SessionConfiguration.validated(
            schemaVersion: 1,
            policyVersion: sessionConfigurationPolicyVersion,
            ownerId: _owner,
            mode: LessonMode.matching,
            itemCount: 4,
            direction: SessionDirection.forward,
            difficulty: SessionDifficulty.standard,
            hintBudget: hintBudget,
            timing: const SessionTiming.timed(Duration(minutes: 2)),
            packIdentity: null,
            protocolId: 'standard',
            protocolVersion: '1',
            protocolLimitsIdentity: 'standard',
          )
        : null;
    operation = PairMatchingStartOperation(
      plan: plan,
      launchOperationId: 'synthetic-proof-start',
      appVersion: '1',
      buildId: 'synthetic',
      configuration: config,
    );
    session = {
      'id': sessionId,
      'owner_id': _owner,
      'activity_type': 'matching',
      'state': phase == 1 ? 'active' : 'completed',
      'started_at_utc_ms': _start,
      'ended_at_utc_ms': phase == 1 ? null : _start + 1000,
      'app_version': '1',
      'build_id': 'synthetic',
      'session_configuration_identity': config?.contentIdentity,
      'session_configuration_json': config?.stableSerialization,
    };
    final key = PairMatchingSessionPurpose.checkpointKey(_owner, sessionId, 1);
    checkpoint = {
      'event_id': key,
      'idempotency_key': key,
      'owner_id': _owner,
      'actor_identity': _owner,
      'aggregate_id': sessionId,
      'aggregate_type': 'LearningSession',
      'event_type': 'LearningActivityCheckpoint',
      'event_version': eventVersion,
      'occurred_at_utc': _start ~/ 1000,
      'recorded_at_utc': _start ~/ 1000,
      'app_version': '1',
      'build_id': 'synthetic',
      'privacy_classification': 'ownerOnly',
      'consent_context_json': jsonEncode({
        'researchConsentVersion': 0,
        'aiConsentGranted': false,
        'voiceConsentGranted': false,
        'socialConsentGranted': false,
      }),
      'payload_json': jsonEncode({
        'schemaVersion': eventVersion,
        'activityType': 'matching',
        'sessionId': sessionId,
        'revision': 1,
        'state': operation.initialCheckpoint.state,
        if (eventVersion == 2) ...{
          'terminalAtUtc': null,
          'terminalAcknowledged': false,
        },
      }),
    };
  }
  late final int proofPhase;
  late final PairMatchingStartOperation operation;
  late final Map<String, Object?> session, checkpoint;
  final owners = <Map<String, Object?>>[
    {
      'id': _owner,
      'created_at_utc_ms': _start - 1000,
      'upgraded_at_utc_ms': null,
      'is_active': 1,
      'account_state': 'localGuest',
    },
  ];
  ResearchSessionProof proof({
    List<Map<String, Object?>>? checkpoints,
    int? phase,
  }) => ResearchSessionProof.fromCanonicalSnapshot(
    ownerId: session['owner_id'] as String,
    permitId: 'permit:a',
    permitPayloadSha256: 'a' * 64,
    permitRevision: 1,
    measurementRunId: 'run:a',
    proofRevision: phase ?? proofPhase,
    session: session,
    checkpoints: checkpoints ?? [checkpoint],
    historicalOwners: owners,
  );
}
