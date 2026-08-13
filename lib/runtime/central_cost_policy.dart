enum CostResponsibility {
  central,
  localDevice,
  participantFunded,
  operatorConfigured,
}

enum CentralCostPolicyState { withinBudget, outOfBudget, unknown }

/// Shared by production bootstrap and the central-cost inventory so an
/// enabled remote surface cannot be silently classified as optional.
const productionCloudSyncEnabledByDefault = bool.fromEnvironment(
  'LEXIQUEST_CLOUD_SYNC_ENABLED',
  defaultValue: true,
);

final class CentralCostComponent {
  const CentralCostComponent({
    required this.id,
    required this.requiredByDefault,
    required this.responsibility,
    required this.monthlyThb,
  }) : assert(id != ''),
       assert(monthlyThb == null || monthlyThb >= 0);

  final String id;
  final bool requiredByDefault;
  final CostResponsibility responsibility;

  /// Fixed centrally-paid monthly amount, when this is a central component.
  /// Null never means free; for required central work it makes the assessment
  /// unknown and therefore fail closed.
  final int? monthlyThb;
}

final class CentralCostAssessment {
  const CentralCostAssessment({
    required this.state,
    required this.centralMonthlyThb,
    required this.minimumMonthlyThb,
    required this.maximumMonthlyThb,
  });

  final CentralCostPolicyState state;
  final int? centralMonthlyThb;
  final int minimumMonthlyThb;
  final int maximumMonthlyThb;
}

/// Closed baseline for costs paid centrally by LexiQuest production defaults.
///
/// Participant-funded BYOK and operator-configured optional integrations are
/// explicitly classified but are not silently assigned a price. This policy
/// makes no provider price, quota, or free-tier claim.
final class CentralCostBaseline {
  const CentralCostBaseline({required this.components});

  const CentralCostBaseline.productionDefaults()
    : components = const [
        CentralCostComponent(
          id: 'localCore',
          requiredByDefault: true,
          responsibility: CostResponsibility.localDevice,
          monthlyThb: null,
        ),
        CentralCostComponent(
          id: 'participantByokAi',
          requiredByDefault: false,
          responsibility: CostResponsibility.participantFunded,
          monthlyThb: null,
        ),
        CentralCostComponent(
          id: 'firebaseAuthentication',
          requiredByDefault: true,
          responsibility: CostResponsibility.central,
          monthlyThb: null,
        ),
        CentralCostComponent(
          id: 'firebaseAppCheck',
          requiredByDefault: true,
          responsibility: CostResponsibility.central,
          monthlyThb: null,
        ),
        CentralCostComponent(
          id: 'firestoreCloudSync',
          requiredByDefault: productionCloudSyncEnabledByDefault,
          responsibility: CostResponsibility.central,
          monthlyThb: null,
        ),
      ];

  static const minimumMonthlyThb = 0;
  static const maximumMonthlyThb = 100;

  final List<CentralCostComponent> components;

  CentralCostAssessment assess() {
    var total = 0;
    for (final component in components) {
      if (!component.requiredByDefault ||
          component.responsibility != CostResponsibility.central) {
        continue;
      }
      final cost = component.monthlyThb;
      if (cost == null) {
        return const CentralCostAssessment(
          state: CentralCostPolicyState.unknown,
          centralMonthlyThb: null,
          minimumMonthlyThb: minimumMonthlyThb,
          maximumMonthlyThb: maximumMonthlyThb,
        );
      }
      total += cost;
    }
    return CentralCostAssessment(
      state: total > maximumMonthlyThb
          ? CentralCostPolicyState.outOfBudget
          : CentralCostPolicyState.withinBudget,
      centralMonthlyThb: total,
      minimumMonthlyThb: minimumMonthlyThb,
      maximumMonthlyThb: maximumMonthlyThb,
    );
  }
}
