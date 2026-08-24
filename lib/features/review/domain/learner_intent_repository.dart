import '../../learning_packs/domain/content_manifest.dart';
import 'learner_intent.dart';

abstract interface class LearnerIntentRepository {
  Future<void> save(SaveLearningItemCommand command);

  Future<void> unsave(ContentIdentity identity);
}
