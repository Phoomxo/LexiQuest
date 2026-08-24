import '../../learning_packs/domain/content_manifest.dart';
import '../domain/learner_intent.dart';
import '../domain/learner_intent_repository.dart';

typedef LearnerIntentIdGenerator = String Function();
typedef LearnerIntentClock = DateTime Function();

/// Composes learner-intent writes without exposing owner, id, or clock
/// authority to presentation code.
final class LearnerIntentUseCases {
  const LearnerIntentUseCases({
    required this.repository,
    required this.generateId,
    required this.nowUtc,
  });

  final LearnerIntentRepository repository;
  final LearnerIntentIdGenerator generateId;
  final LearnerIntentClock nowUtc;

  Future<void> bookmark(ContentIdentity identity) {
    return repository.save(
      SaveLearningItemCommand(
        id: generateId(),
        contentIdentity: identity,
        savedAtUtc: nowUtc(),
      ),
    );
  }
}
