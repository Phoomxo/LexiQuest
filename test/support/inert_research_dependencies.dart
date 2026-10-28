import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/research/application/assigned_learning_event_context_provider.dart';
import 'package:vocab_learning_app/features/research/application/experiment_assignment_use_cases.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/runtime/registries/consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';

/// Explicit inert research authorities for tests that construct the app shell.
///
/// The assignment use case retains its real repository boundary, while every
/// read/invocation authority remains unassigned, unknown-consent, and Legacy.
final class InertResearchDependencies {
  InertResearchDependencies(AppDatabase database)
    : experimentAssignments = ExperimentAssignmentUseCases(
        repository: DriftExperimentAssignmentRepository(database),
        consentRegistry: const NoOpConsentRegistry(),
      );

  final ExperimentRegistry experiments = const NoOpExperimentRegistry();
  final ConsentRegistry consents = const NoOpConsentRegistry();
  final ExperimentAssignmentUseCases experimentAssignments;
  final AssignedLearningEventContextProvider assignedLearningEventContext =
      const AssignedLearningEventContextProvider(
        experimentRegistry: NoOpExperimentRegistry(),
        consentRegistry: NoOpConsentRegistry(),
      );
  final EvidencePolicyRolloutModeProvider evidencePolicyRolloutModeProvider =
      const FixedEvidencePolicyRolloutModeProvider.legacy();
}
