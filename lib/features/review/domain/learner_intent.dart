import '../../learning_packs/domain/content_manifest.dart';

typedef BookmarkLearningItemAction =
    Future<void> Function(ContentIdentity identity);

final class SaveLearningItemCommand {
  const SaveLearningItemCommand({
    required this.id,
    required this.contentIdentity,
    required this.savedAtUtc,
  });

  final String id;
  final ContentIdentity contentIdentity;
  final DateTime savedAtUtc;
}
