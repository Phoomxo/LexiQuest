import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'pair_matching_source_composer_test.dart' as f;

void main() {
  test(
    'operation IDs use structured owner binding without delimiter collisions',
    () {
      expect(pairSessionId('a:b', 'c'), isNot(pairSessionId('a', 'b:c')));
    },
  );
  test('plan deep freeze and exact round trip binds source/session/time', () {
    final p = (f.compose(List.generate(4, f.fixture)) as PairPlanReady).plan;
    expect(
      PairMatchingPlanV1.fromStableSerialization(
        p.stableSerialization,
      ).planFingerprint,
      p.planFingerprint,
    );
    expect(p.sourceSnapshotId, 'synthetic-snapshot');
    expect(p.learningSessionId, startsWith('pair:'));
    expect(() => p.sourceOrder.add('x'), throwsUnsupportedError);
    expect(
      () => p.orderedLexicalItems.first.sourceReasons.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => (p.toJson()['orderedLexicalItems'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(
      () => ((p.toJson()['orderedLexicalItems'] as List).first as Map).clear(),
      throwsUnsupportedError,
    );
  });
  test(
    'exact keys, versions and derived orders/fingerprint reject tampering',
    () {
      final p = (f.compose(List.generate(4, f.fixture)) as PairPlanReady).plan;
      for (final change in <String, Object?>{
        'unknown': true,
        'repairPolicyVersion': 2,
        'checkpointPolicyVersion': 7,
        'sourceOrder': ['forged'],
        'planFingerprint': 'bad',
      }.entries) {
        final json = jsonDecode(p.stableSerialization) as Map<String, dynamic>;
        json[change.key] = change.value;
        expect(
          () => PairMatchingPlanV1.fromStableSerialization(jsonEncode(json)),
          throwsFormatException,
        );
      }
    },
  );
}
