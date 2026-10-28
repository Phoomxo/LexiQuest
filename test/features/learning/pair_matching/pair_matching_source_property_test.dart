import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'pair_matching_source_composer_test.dart' as f;

void main() {
  test(
    '100 synthetic permutations preserve exact pinned plan and all overlap reasons',
    () {
      final source = List.generate(12, f.fixture)
        ..add(f.fixture(10, reasons: {PairSourceReason.dueSrs}));
      final expected = (f.compose(source) as PairPlanReady).plan;
      for (var seed = 0; seed < 100; seed++) {
        final shuffled = [...source]..shuffle(Random(seed));
        final plan = (f.compose(shuffled) as PairPlanReady).plan;
        expect(plan.stableSerialization, expected.stableSerialization);
        expect(plan.sourceOrder.toSet().length, 4);
        expect(plan.targetOrder.toSet(), plan.sourceOrder.toSet());
      }
    },
  );
}
