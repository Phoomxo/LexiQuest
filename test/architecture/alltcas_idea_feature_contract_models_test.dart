import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

void main() {
  test('runtime feature identities remain the exact persisted 15 names', () {
    expect(Feature.values.map((value) => value.name), const <String>[
      'vocabulary',
      'quiz',
      'srs',
      'reading',
      'mastery',
      'weakness',
      'ghostDuel',
      'achievements',
      'shop',
      'objectScanner',
      'speechPractice',
      'aiTutor',
      'export',
      'shadowRewardV2',
      'questV2',
    ]);
  });

  test('product contract identities are the exact f01 through f44 range', () {
    expect(FeatureContractId.values, hasLength(44));
    expect(FeatureContractId.values.first.name, 'f01');
    expect(FeatureContractId.values.last.name, 'f44');
    expect(
      FeatureContractId.values.map((value) => value.ordinal),
      List<int>.generate(44, (index) => index + 1),
    );
  });

  test('eight product domains map one-to-one to C1 through C8', () {
    expect(FeatureDomain.values, hasLength(8));
    expect(
      FeatureDomain.values.map((value) => value.completionContract),
      CompletionContractId.values,
    );
  });
}
