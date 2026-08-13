import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/central_cost_policy.dart';

void main() {
  test('production baseline inventories remote defaults and stays unknown '
      'without billing evidence', () {
    const baseline = CentralCostBaseline.productionDefaults();

    final assessment = baseline.assess();

    expect(assessment.state, CentralCostPolicyState.unknown);
    expect(assessment.centralMonthlyThb, isNull);
    expect(assessment.minimumMonthlyThb, 0);
    expect(assessment.maximumMonthlyThb, 100);
    expect(baseline.components.map((component) => component.id).toSet(), const {
      'localCore',
      'participantByokAi',
      'firebaseAuthentication',
      'firebaseAppCheck',
      'firestoreCloudSync',
    });
    expect(
      baseline.components
          .where(
            (component) =>
                component.requiredByDefault &&
                component.responsibility == CostResponsibility.central,
          )
          .map((component) => component.id),
      containsAll(const {
        'firebaseAuthentication',
        'firebaseAppCheck',
        'firestoreCloudSync',
      }),
    );
    expect(productionCloudSyncEnabledByDefault, isTrue);
  });

  test(
    'unknown required central cost fails closed instead of claiming zero',
    () {
      const baseline = CentralCostBaseline(
        components: [
          CentralCostComponent(
            id: 'futureCentralService',
            requiredByDefault: true,
            responsibility: CostResponsibility.central,
            monthlyThb: null,
          ),
        ],
      );

      final assessment = baseline.assess();

      expect(assessment.state, CentralCostPolicyState.unknown);
      expect(assessment.centralMonthlyThb, isNull);
    },
  );

  test('known central cost above 100 THB is typed out of budget', () {
    const baseline = CentralCostBaseline(
      components: [
        CentralCostComponent(
          id: 'futureCentralService',
          requiredByDefault: true,
          responsibility: CostResponsibility.central,
          monthlyThb: 101,
        ),
      ],
    );

    final assessment = baseline.assess();

    expect(assessment.state, CentralCostPolicyState.outOfBudget);
    expect(assessment.centralMonthlyThb, 101);
  });
}
