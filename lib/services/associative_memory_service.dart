import '../learning/association_record.dart';
import '../learning/local_learning_repository.dart';

class AssociativeMemoryService {
  final LocalLearningRepository repository;

  AssociativeMemoryService({required this.repository});

  final Map<String, List<AssociationRecord>> _curatedPrompts = {
    'ephemeral': [
      AssociationRecord(
        associationId: 'curated-e1',
        ownerId: 'system',
        wordKey: 'ephemeral',
        cueType: CueType.sensory,
        cueText: 'Think of morning mist disappearing when the sun comes up.',
        source: AssociationSource.curated,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      AssociationRecord(
        associationId: 'curated-e2',
        ownerId: 'system',
        wordKey: 'ephemeral',
        cueType: CueType.synonym,
        cueText: 'Transient / short-lived / fleeting',
        source: AssociationSource.curated,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ],
    'resilient': [
      AssociationRecord(
        associationId: 'curated-r1',
        ownerId: 'system',
        wordKey: 'resilient',
        cueType: CueType.sensory,
        cueText: 'Like a bamboo tree bending in the storm but never snapping.',
        source: AssociationSource.curated,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ],
  };

  Future<List<AssociationRecord>> getPromptsForWord(
    String ownerId,
    String wordKey,
  ) async {
    final userAssocs = await repository.getAssociationsForWord(
      ownerId,
      wordKey,
    );
    final curated = _curatedPrompts[wordKey] ?? [];
    return [...userAssocs, ...curated];
  }

  Future<AssociationRecord> createUserAssociation({
    required String ownerId,
    required String wordKey,
    required CueType cueType,
    required String cueText,
  }) async {
    final record = AssociationRecord(
      associationId: 'assoc-${DateTime.now().millisecondsSinceEpoch}',
      ownerId: ownerId,
      wordKey: wordKey,
      cueType: cueType,
      cueText: cueText,
      source: AssociationSource.user,
      privacy: AssociationPrivacy.private,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    await repository.saveAssociation(record);
    return record;
  }
}
