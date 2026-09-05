import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_checkpoint_budget.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'pair_matching_source_composer_test.dart' as f;

void main() {
  test(
    'review Unicode 29-attempt ledger fits compact codec and preserves start identity',
    () {
      final owner = 'o' * 256;
      final items = List.generate(
        6,
        (i) => PairLexicalItem(
          wordId: '${'ก' * 255}$i',
          contentRevision: 1,
          checksum: 'f' * 64,
          spelling: '${'e' * 255}$i',
          meaning: '${'ก' * 255}$i',
          sourceLocale: 'en',
          targetLocale: 'th',
          sourceReasons: PairSourceReason.values.where(
            (r) => r != PairSourceReason.reported,
          ),
        ),
      );
      final plan = PairMatchingPlanV1(
        ownerId: owner,
        orderedLexicalItems: items,
        direction: PairDirection.thToEn,
        density: PairDensity.standard6,
        shuffleSeed: 42,
        timerPreset: PairTimerPreset.seconds120,
        allowlistVersion: 'a' * 256,
        learningSessionId: pairSessionId(owner, 'l' * 256),
        entryKind: PairSourceSurface.learn,
        sourceSnapshotId: 's' * 256,
        createdAtUtc: DateTime.utc(2026, 9, 5),
      );
      final operation = PairMatchingStartOperation(
        plan: plan,
        launchOperationId: 'l' * 256,
        appVersion: 'v' * 256,
        buildId: 'b' * 256,
      );
      // Preserve the accepted PM2 codec regression as historical committed
      // data. New PM3 commands cannot generate unlimited immediate retries.
      final ledger = List.generate(29, (i) {
        final prefix = '${i * 2 + 1}:';
        final word = i < 23 ? 0 : i - 23;
        return PairAttemptRequested(
          operationId: '$prefix${'n' * (128 - prefix.length)}',
          fingerprint: 'f' * 64,
          promptWordId: items[word].wordId,
          targetWordId: items[i < 23 ? 1 : word].wordId,
          roundOrdinal: 0,
          role: i == 0 || i > 23
              ? PairAttemptRole.firstOpportunity
              : PairAttemptRole.independentRetry,
          responseTimeMs: 2147483647,
        );
      });
      final map = PairMatchingState.initial(plan).toJson();
      map['attempts'] = ledger.map((a) => a.toJson()).toList();
      map['matchedWordIds'] = items.map((i) => i.wordId).toList()..sort();
      map['operationRevision'] = 58;
      map['lastOperationId'] = ledger.last.operationId;
      map['lastFingerprint'] = ledger.last.fingerprint;
      final state = PairMatchingState.fromJson(plan, map);
      final snapshot = PairMatchingCheckpointSnapshot(
        engine: state,
        startOperation: operation.stableSerialization,
        evidenceIds: List.generate(
          29,
          (i) => 'attempt:${'e' * 186}${i.toString().padLeft(3, '0')}',
        ),
      );
      final encoded = snapshot.toJson();
      final bytes = utf8.encode(jsonEncode(encoded)).length;
      expect(bytes, lessThan(65536));
      expect(
        PairMatchingCheckpointCodec.decode(encoded).startOperation,
        operation.stableSerialization,
      );
      expect(
        PairMatchingCheckpointCodec.decode(encoded).engine.attempts,
        hasLength(29),
      );
    },
  );
  test('initial v6 preserves PM1 bytes and rejects forged progress', () {
    final plan = (f.compose(List.generate(4, f.fixture)) as PairPlanReady).plan;
    final op = PairMatchingStartOperation(
      plan: plan,
      launchOperationId: 'synthetic-operation',
      appVersion: 'synthetic',
      buildId: 'synthetic',
    );
    final decoded = PairMatchingCheckpointCodec.decode(
      op.initialCheckpoint.state,
    );
    expect(decoded.engine.plan.planFingerprint, plan.planFingerprint);
    final selected = PairMatchingEngine.reduce(
      decoded.engine,
      PairSelectTile(
        operationId: '0:tap',
        ownerId: plan.ownerId,
        sessionId: plan.learningSessionId,
        roundOrdinal: 0,
        expectedRevision: 0,
        tile: PairTile(
          PairTileSide.prompt,
          plan.orderedLexicalItems.first.wordId,
        ),
        responseTimeMs: 1,
      ),
    ).state;
    final malformed =
        jsonDecode(
              jsonEncode(
                PairMatchingCheckpointSnapshot(
                  engine: selected,
                  startOperation: op.stableSerialization,
                ).toJson(),
              ),
            )
            as Map<String, dynamic>;
    ((malformed['engine'] as Map)['selected'] as Map)['extra'] = true;
    expect(
      () => PairMatchingCheckpointCodec.decode(malformed),
      throwsFormatException,
    );
    expect(
      jsonEncode(
        PairMatchingCheckpointCodec.initialState(plan, op.stableSerialization),
      ),
      jsonEncode(op.initialCheckpoint.state),
    );
    expect(
      () => PairMatchingCheckpointCodec.decode({
        ...op.initialCheckpoint.state,
        'matchedPairIds': ['synthetic-0'],
      }),
      throwsFormatException,
    );
    expect(
      () => PairMatchingCheckpointCodec.decode({
        ...op.initialCheckpoint.state,
        'extra': true,
      }),
      throwsFormatException,
    );
    expect(
      utf8.encode(jsonEncode(decoded.toJson())).length,
      lessThan(PairMatchingCheckpointBudget.maximumBytes),
    );
  });
  test('answer admission preserves remaining answer and terminal capacity', () {
    expect(
      PairMatchingCheckpointBudget.canAnswer(
        revision: 46,
        attempts: 20,
        remainingPairs: 6,
      ),
      true,
    );
    expect(
      PairMatchingCheckpointBudget.canAnswer(
        revision: 47,
        attempts: 20,
        remainingPairs: 6,
      ),
      false,
    );
    expect(
      PairMatchingCheckpointBudget.canAnswer(
        revision: 1,
        attempts: 128,
        remainingPairs: 4,
      ),
      false,
    );
  });
}
