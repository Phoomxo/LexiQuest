import 'package:drift/drift.dart';
import '../../learning/application/cloze_mode_adapter.dart';
import '../../learning/domain/context_practice.dart';
import '../../identity/application/owner_generation.dart';
import '../../ai_tutor/domain/ai_tutor_contracts.dart';
import '../../learning/application/learning_use_cases.dart';
import '../../learning/data/drift_learning_repository.dart';
import '../../learning/domain/learning_models.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../../vocabulary/data/drift_vocabulary_repository.dart';
import '../../vocabulary/data/packaged_starter_access.dart';
import '../domain/content_manifest.dart';
import '../domain/personal_sets.dart';
import 'personal_sets_use_cases.dart';

final class PersonalSetActivityLaunch {
  PersonalSetActivityLaunch(
    this.session,
    this.revision,
    List<ReviewedLexicalContentSnapshot> items, {
    this.contextInput,
    this.recovery,
  }) : items = List.unmodifiable(items);
  final QuizSession session;
  final ClozeInputMode? contextInput;
  final LearningActivityRecovery? recovery;
  final PersonalSetRevision revision;
  final List<ReviewedLexicalContentSnapshot> items;
}

final class PersonalSetActivities {
  const PersonalSetActivities({
    required this.sets,
    required this.learning,
    required this.isAvailable,
    this.contextAvailable,
  });
  final PersonalSetsUseCases sets;
  final LearningUseCases learning;
  final bool Function() isAvailable;
  final bool Function()? contextAvailable;
  bool get canPracticeContext =>
      isAvailable() && (contextAvailable?.call() ?? false);
  Future<PersonalSetActivityLaunch> start(
    OwnerGenerationToken owner, {
    required String setId,
    required int revision,
    required String operationId,
    ClozeInputMode? contextInput,
  }) async {
    if (operationId.isEmpty ||
        operationId != operationId.trim() ||
        operationId.length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(operationId)) {
      throw ArgumentError('Invalid personal set launch operation');
    }
    final activityType = contextInput == null
        ? 'personalSetMeaningQuiz'
        : 'contextPractice';
    void contextFence() {
      if (contextInput != null && !canPracticeContext) {
        throw StateError('Context practice is disabled');
      }
    }

    contextFence();
    await sets.ownerGeneration.requireCurrentAsync(owner);
    _requireAvailable();
    final database = sets.repository.database;
    final canonical = learning.repository;
    if (canonical is! DriftLearningRepository ||
        !identical(canonical.database, database)) {
      throw StateError(
        'Personal set activity requires the same durable learning authority',
      );
    }
    return sets.ownerOperations.run(AiCancellation(), (activeOwner) async {
      if (activeOwner != owner.ownerId) {
        throw StateError('Personal set owner changed');
      }
      Future<void> fence() async {
        contextFence();
        _requireAvailable();
        await sets.ownerGeneration.requireCurrentAsync(owner);
        await DriftOwnerOperationGate(database).requireOwned(
          token: sets.ownerOperations.currentOperationVersion,
          nowUtc: sets.repository.nowUtc(),
        );
        final active = await (database.select(
          database.localOwners,
        )..where((r) => r.isActive.equals(true))).get();
        if (active.length != 1 || active.single.id != owner.ownerId) {
          throw StateError('Personal set owner changed');
        }
      }

      await fence();
      // The outer transaction includes canonical admission. A late ownership,
      // feature or content failure rolls back BOTH session and checkpoint.
      return database.transaction(() async {
        await fence();
        final saved = await sets.repository.readExact(
          ownerId: owner.ownerId,
          setId: setId,
          revision: revision,
        );
        if (saved == null || saved.archived || saved.members.length > 100) {
          throw StateError(
            'Saved personal set is unavailable for this activity',
          );
        }
        final (pins, items) = await _scoredPins(owner.ownerId, saved);
        if (contextInput != null) await _requireContextInventory(saved);
        final existing = await database
            .customSelect(
              "SELECT aggregate_id FROM events_v2 WHERE owner_id = ? AND event_type = 'LearningActivityCheckpoint' "
              "AND json_extract(payload_json, '\$.state.kind') IN ('personalSetMeaningQuiz', 'contextPractice') "
              "AND json_extract(payload_json, '\$.state.launchOperationId') = ?",
              variables: [
                Variable<String>(owner.ownerId),
                Variable<String>(operationId),
              ],
            )
            .get();
        if (existing.isNotEmpty) {
          if (existing.length != 1) {
            throw StateError('Ambiguous personal set launch operation');
          }
          final recovery = await learning.loadExactActivityRecovery(
            ownerId: owner.ownerId,
            sessionId: existing.single.read<String>('aggregate_id'),
            activityType: activityType,
          );
          final state = recovery?.checkpoint?.state;
          if (recovery == null ||
              state == null ||
              (contextInput == null ? state.length != 4 : state.length != 7) ||
              state['schemaVersion'] != 1 ||
              state['kind'] != activityType ||
              (contextInput != null &&
                  (state['inputMode'] != contextInput.name ||
                      state['inventoryRevision'] !=
                          ContextPracticeInventory.revision ||
                      state['inventoryHash'] !=
                          ContextPracticeInventory.fingerprint)) ||
              state['launchOperationId'] != operationId ||
              PersonalSetRevision.fromJson(
                    Map<String, Object?>.from(
                      state['personalSetRevision'] as Map,
                    ),
                  ).payloadHash !=
                  saved.payloadHash) {
            throw StateError('Personal set launch operation collision');
          }
          // Meaning-quiz launch retries require an untouched session. Context
          // recovery authenticates attempts and reopens acknowledged feedback.
          if (recovery.session.state != 'active' ||
              (contextInput == null && recovery.attempts.isNotEmpty)) {
            throw StateError(
              'This launch already has activity; start a new operation',
            );
          }
          final replay = await learning.reconstructPinnedQuizSession(
            session: recovery.session,
            content: pins.map((p) => p.identity).toList(),
            contentChecksumsSha256: {
              for (final pin in pins) pin.identity.id: pin.checksumSha256,
            },
          );
          await fence();
          return PersonalSetActivityLaunch(
            replay,
            saved,
            items,
            contextInput: contextInput,
            recovery: recovery,
          );
        }
        final session = await learning.startCheckpointedQuiz(
          activityType: activityType,
          limit: pins.length,
          pinnedContent: pins,
          initialState: (_) => {
            'schemaVersion': 1,
            'kind': activityType,
            if (contextInput != null) ...{
              'inputMode': contextInput.name,
              'inventoryRevision': ContextPracticeInventory.revision,
              'inventoryHash': ContextPracticeInventory.fingerprint,
            },
            'launchOperationId': operationId,
            // Owner is held in the canonical event envelope so guest remap
            // retains the immutable owner-independent revision hash.
            'personalSetRevision': saved.toJson(),
          },
        );
        if (session.isEmpty || session.ownerId != owner.ownerId) {
          throw StateError('Personal set admission failed');
        }
        await _scoredPins(owner.ownerId, saved);
        if (contextInput != null) await _requireContextInventory(saved);
        await fence();
        return PersonalSetActivityLaunch(
          session,
          saved,
          items,
          contextInput: contextInput,
        );
      });
    });
  }

  Future<void> _requireContextInventory(PersonalSetRevision saved) async {
    for (final member in saved.members) {
      final entry = const ContextPracticeInventory().find(member.wordId);
      if (entry == null ||
          member.senseKey != 'starter-object-v1' ||
          member.senseRevision != 1 ||
          member.lexicalArtifactHash != entry.artifactHash) {
        throw StateError('Reviewed context is unavailable for this sense');
      }
      final identity = ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: entry.distractorId,
        revision: 1,
      );
      final alternative = await sets.repository.crosswalks.manifests
          .requireVerified(identity);
      final manifest = alternative.manifest;
      if (manifest.identity != identity ||
          manifest.checksumSha256 != entry.distractorArtifactHash ||
          manifest.provenance != ContentProvenance.packaged ||
          manifest.reviewState != ContentReviewState.approved ||
          manifest.publicationState != ContentPublicationState.published ||
          manifest.reviewedAtUtc == null ||
          manifest.publishedAtUtc == null) {
        throw StateError('Reviewed context alternative is unavailable');
      }
    }
  }

  void _requireAvailable() {
    if (!isAvailable()) throw StateError('Personal set activity is disabled');
  }

  Future<(List<PinnedQuizContent>, List<ReviewedLexicalContentSnapshot>)>
  _scoredPins(String ownerId, PersonalSetRevision saved) async {
    final repository = sets.repository;
    final database = repository.database;
    final crosswalk = await repository.crosswalks.requirePinned(
      saved.crosswalkPin,
    );
    final words = await DriftVocabularyRepository(
      database,
      contentManifests: repository.crosswalks.manifests,
    ).readPinnedByIds(saved.members.map((r) => r.wordId));
    final categories =
        await (database.select(database.vocabularyCategories)..where(
              (r) =>
                  PackagedStarterAccess.categoriesFor(database, ownerId) &
                  r.isDeleted.equals(false),
            ))
            .get();
    final availableCategories = categories.map((r) => r.id).toSet();
    final pins = <PinnedQuizContent>[];
    final items = <ReviewedLexicalContentSnapshot>[];
    for (var index = 0; index < saved.members.length; index++) {
      final ref = saved.members[index];
      final word = words[index];
      final entry = crosswalk.resolve(ref);
      final identity = ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: ref.wordId,
        revision: entry.wordRevision,
      );
      final artifact = await repository.crosswalks.manifests.requireVerified(
        identity,
      );
      crosswalk.requireScored(
        ref,
        word: word,
        categoryAvailable: availableCategories.contains(word.categoryId),
        lexicalArtifact: artifact,
      );
      pins.add(
        PinnedQuizContent(
          identity: identity,
          checksumSha256: entry.wordChecksumSha256,
        ),
      );
      items.add(
        ReviewedLexicalContentSnapshot(
          identity: identity,
          categoryId: word.categoryId,
          spelling: word.spelling,
          normalizedSpelling: word.normalizedSpelling,
          meaning: word.meaning,
          normalizedMeaning: word.normalizedMeaning,
          partOfSpeech: word.partOfSpeech,
          cefrLevel: word.cefrLevel,
          source: word.source,
          isGlobal: word.isGlobal,
          coreChecksumSha256: entry.wordChecksumSha256,
          provenance: word.contentProvenance,
          reviewState: word.contentReviewState,
          publicationState: word.contentPublicationState,
          artifact: ReviewedLexicalArtifactSnapshot(
            storageId: artifact.manifest.storageId,
            identity: identity,
            checksumSha256: artifact.manifest.checksumSha256,
            byteLength: artifact.manifest.byteLength,
          ),
        ),
      );
    }
    return (
      List<PinnedQuizContent>.unmodifiable(pins),
      List<ReviewedLexicalContentSnapshot>.unmodifiable(items),
    );
  }
}
