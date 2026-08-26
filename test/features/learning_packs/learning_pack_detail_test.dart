import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/legacy_lesson_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_detail_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_detail.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

void main() {
  late AppDatabase database;
  late DriftLearningPackRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftLearningPackRepository(
      database,
      contentManifests: DriftContentManifestRepository(database),
    );
    await _insertVocabularyAuthority(database);
  });

  tearDown(() => database.close());

  test('reads only the requested verified pinned pack revision', () async {
    await _insertVerifiedPack(
      database,
      packId: 'pack:travel',
      revision: 1,
      title: 'Travel basics',
      wordIds: const ['word:station', 'word:market'],
    );
    await _insertVerifiedPack(
      database,
      packId: 'pack:travel',
      revision: 2,
      title: 'Travel revised',
      wordIds: const ['word:market', 'word:station'],
    );

    final detail = await repository.getVersion('pack:travel', 1);

    expect(detail.summary.revision, 1);
    expect(detail.summary.title, 'Travel basics');
    expect(detail.vocabularyWordIds, const ['word:station', 'word:market']);
    await expectLater(
      repository.getVersion('pack:travel', 3),
      throwsA(
        isA<ContentQualityFailure>().having(
          (failure) => failure.code,
          'code',
          ContentQualityFailureCode.missingReference,
        ),
      ),
    );
  });

  test(
    'fails closed when the requested revision is unpublished or corrupt',
    () async {
      await _insertVerifiedPack(
        database,
        packId: 'pack:private',
        revision: 1,
        title: 'Private travel',
        wordIds: const ['word:station'],
        publicationState: ContentPublicationState.private,
      );
      await _insertVerifiedPack(
        database,
        packId: 'pack:corrupt',
        revision: 1,
        title: 'Corrupt travel',
        wordIds: const ['word:market'],
        manifestChecksum:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      await expectLater(
        repository.getVersion('pack:private', 1),
        throwsA(
          isA<ContentQualityFailure>().having(
            (failure) => failure.code,
            'code',
            ContentQualityFailureCode.unpublished,
          ),
        ),
      );
      await expectLater(
        repository.getVersion('pack:corrupt', 1),
        throwsA(
          isA<ContentQualityFailure>().having(
            (failure) => failure.code,
            'code',
            ContentQualityFailureCode.checksumMismatch,
          ),
        ),
      );
    },
  );

  test(
    'derives detail progress from canonical sessions without pack writes',
    () async {
      await _insertVerifiedPack(
        database,
        packId: 'pack:travel',
        revision: 1,
        title: 'Travel basics',
        wordIds: const ['word:station'],
      );
      await _insertLearnerProgress(database);
      final before = await _packRows(database);
      final useCases = LearningPackDetailUseCases(
        packs: repository,
        progress: ProgressUseCases(
          owners: _Owner(),
          queries: DriftProgressQueries(database),
          nowUtc: () => DateTime.utc(2026, 8, 24),
        ),
        lessonModes: buildLegacyLessonModeRegistry(),
        features: const BuildFeatureRegistry.allEnabled(),
        hasComposedDependency: (_) => true,
      );

      final view = await useCases.loadVersion('pack:travel', 1);

      expect(view.progress.completedSessions, 1);
      expect(view.progress.sampleSize, 1);
      expect(view.progress.accuracy, 1);
      expect(await _packRows(database), before);
    },
  );

  test(
    'lists registered activities deterministically and marks missing modes unavailable',
    () async {
      await _insertVerifiedPack(
        database,
        packId: 'pack:travel',
        revision: 1,
        title: 'Travel basics',
        wordIds: const ['word:station'],
      );
      final useCases = LearningPackDetailUseCases(
        packs: repository,
        progress: ProgressUseCases(
          owners: _Owner(),
          queries: DriftProgressQueries(database),
          nowUtc: () => DateTime.utc(2026, 8, 24),
        ),
        lessonModes: LessonModeRegistry(const <LessonModeRegistration>[
          LessonModeRegistration(
            adapter: LegacyLessonModeAdapter(LessonMode.meaningQuiz),
            feature: Feature.quiz,
            productionEntryId: 'home/learn/quiz',
            routeName: 'learning/quiz',
          ),
        ]),
        features: const BuildFeatureRegistry.allEnabled(),
        hasComposedDependency: (_) => true,
      );

      final view = await useCases.loadVersion('pack:travel', 1);

      expect(view.activities.map((activity) => activity.mode).toList(), const [
        LessonMode.associativeReading,
        LessonMode.cloze,
        LessonMode.definitionQuiz,
        LessonMode.flashcard,
        LessonMode.matching,
        LessonMode.meaningQuiz,
        LessonMode.typedRecall,
      ]);
      expect(
        view.activities
            .where((activity) => activity.mode != LessonMode.meaningQuiz)
            .map((activity) => activity.availability),
        everyElement(LearningPackActivityAvailability.unavailable),
      );
      expect(
        view.activities
            .singleWhere((activity) => activity.mode == LessonMode.meaningQuiz)
            .availability,
        LearningPackActivityAvailability.available,
      );
    },
  );

  test('implemented-off modes are omitted from pack detail', () async {
    await _insertVerifiedPack(
      database,
      packId: 'pack:travel',
      revision: 1,
      title: 'Travel basics',
      wordIds: const ['word:station'],
    );
    final view = await LearningPackDetailUseCases(
      packs: repository,
      progress: ProgressUseCases(
        owners: _Owner(),
        queries: DriftProgressQueries(database),
        nowUtc: () => DateTime.utc(2026, 8, 24),
      ),
      lessonModes: buildLessonModeRegistry(),
      features: const BuildFeatureRegistry.allEnabled(),
      hasComposedDependency: (_) => true,
    ).loadVersion('pack:travel', 1);

    expect(
      view.activities.where((activity) => activity.mode == LessonMode.matching),
      isEmpty,
    );
    expect(
      view.activities.where(
        (activity) => activity.mode == LessonMode.handwritingScratchpad,
      ),
      isEmpty,
    );
  });

  test('enabled matching requires two ambiguity-safe pinned choices', () async {
    await _insertVerifiedPack(
      database,
      packId: 'pack:travel',
      revision: 1,
      title: 'Travel basics',
      wordIds: const ['word:station'],
    );
    LearningPackDetailUseCases useCases(
      Future<List<VocabularyWord>> Function(Iterable<String>) reader,
    ) => LearningPackDetailUseCases(
      packs: repository,
      progress: ProgressUseCases(
        owners: _Owner(),
        queries: DriftProgressQueries(database),
        nowUtc: () => DateTime.utc(2026, 8, 24),
      ),
      lessonModes: buildLessonModeRegistry(
        matchingDeliveryState: LessonModeDeliveryState.enabled,
      ),
      features: const BuildFeatureRegistry.allEnabled(),
      hasComposedDependency: (_) => true,
      readPinnedVocabulary: reader,
    );

    final oneChoice = await useCases(
      (_) async => <VocabularyWord>[_definitionWord()],
    ).loadVersion('pack:travel', 1);
    expect(
      oneChoice.activities
          .singleWhere((activity) => activity.mode == LessonMode.matching)
          .availability,
      LearningPackActivityAvailability.unavailable,
    );

    await _insertVerifiedPack(
      database,
      packId: 'pack:travel-two',
      revision: 1,
      title: 'Travel pairs',
      wordIds: const ['word:station', 'word:market'],
    );
    final safeChoices = await useCases(
      (_) async => <VocabularyWord>[
        _definitionWord(),
        _definitionWord(id: 'word:market', spelling: 'market', meaning: 'ตลาด'),
      ],
    ).loadVersion('pack:travel-two', 1);
    expect(
      safeChoices.activities
          .singleWhere((activity) => activity.mode == LessonMode.matching)
          .availability,
      LearningPackActivityAvailability.available,
    );
  });

  test(
    'definition quiz is unavailable when pinned vocabulary is not composed',
    () async {
      await _insertVerifiedPack(
        database,
        packId: 'pack:travel',
        revision: 1,
        title: 'Travel basics',
        wordIds: const ['word:station'],
      );
      final useCases = _definitionPackDetailUseCases(database);

      final view = await useCases.loadVersion('pack:travel', 1);

      expect(
        _definitionAvailability(view),
        LearningPackActivityAvailability.unavailable,
      );
    },
  );

  test(
    'definition quiz is unavailable without a qualifying reviewed definition',
    () async {
      await _insertVerifiedPack(
        database,
        packId: 'pack:travel',
        revision: 1,
        title: 'Travel basics',
        wordIds: const ['word:station'],
      );
      final useCases = _definitionPackDetailUseCases(
        database,
        readPinnedVocabulary: (_) async => <VocabularyWord>[_definitionWord()],
      );

      final view = await useCases.loadVersion('pack:travel', 1);

      expect(
        _definitionAvailability(view),
        LearningPackActivityAvailability.unavailable,
      );
    },
  );

  test(
    'definition quiz is available with a qualifying pinned reviewed definition',
    () async {
      await _insertVerifiedPack(
        database,
        packId: 'pack:travel',
        revision: 1,
        title: 'Travel basics',
        wordIds: const ['word:station'],
      );
      final useCases = _definitionPackDetailUseCases(
        database,
        readPinnedVocabulary: (_) async => <VocabularyWord>[
          _definitionWord(
            definition: 'A place where trains stop for passengers.',
          ),
        ],
      );

      final view = await useCases.loadVersion('pack:travel', 1);

      expect(
        _definitionAvailability(view),
        LearningPackActivityAvailability.available,
      );
    },
  );

  test(
    'cloze is unavailable without one qualifying reviewed example',
    () async {
      await _insertVerifiedPack(
        database,
        packId: 'pack:travel',
        revision: 1,
        title: 'Travel basics',
        wordIds: const ['word:station'],
      );
      final missing = _definitionPackDetailUseCases(
        database,
        readPinnedVocabulary: (_) async => <VocabularyWord>[_definitionWord()],
      );
      final ambiguous = _definitionPackDetailUseCases(
        database,
        readPinnedVocabulary: (_) async => <VocabularyWord>[
          _definitionWord(
            examples: const <String>[
              'The station and another station are nearby.',
            ],
          ),
        ],
      );

      expect(
        _clozeAvailability(await missing.loadVersion('pack:travel', 1)),
        LearningPackActivityAvailability.unavailable,
      );
      expect(
        _clozeAvailability(await ambiguous.loadVersion('pack:travel', 1)),
        LearningPackActivityAvailability.unavailable,
      );
    },
  );

  test(
    'cloze is available with one qualifying pinned reviewed example',
    () async {
      await _insertVerifiedPack(
        database,
        packId: 'pack:travel',
        revision: 1,
        title: 'Travel basics',
        wordIds: const ['word:station'],
      );
      final useCases = _definitionPackDetailUseCases(
        database,
        readPinnedVocabulary: (_) async => <VocabularyWord>[
          _definitionWord(
            examples: const <String>['The station closes at midnight.'],
          ),
        ],
      );

      expect(
        _clozeAvailability(await useCases.loadVersion('pack:travel', 1)),
        LearningPackActivityAvailability.available,
      );
    },
  );

  test(
    'requires a full production delivery before advertising a registered activity',
    () async {
      await _insertVerifiedPack(
        database,
        packId: 'pack:travel',
        revision: 1,
        title: 'Travel basics',
        wordIds: const ['word:station'],
      );
      final progress = ProgressUseCases(
        owners: _Owner(),
        queries: DriftProgressQueries(database),
        nowUtc: () => DateTime.utc(2026, 8, 24),
      );
      final missingAssociativeLearning = LearningPackDetailUseCases(
        packs: repository,
        progress: progress,
        lessonModes: buildLegacyLessonModeRegistry(),
        features: const BuildFeatureRegistry.allEnabled(),
        hasComposedDependency: (feature) => feature != Feature.reading,
      );
      final fullyComposed = LearningPackDetailUseCases(
        packs: repository,
        progress: progress,
        lessonModes: buildLegacyLessonModeRegistry(),
        features: const BuildFeatureRegistry.allEnabled(),
        hasComposedDependency: (_) => true,
      );

      final unavailable = await missingAssociativeLearning.loadVersion(
        'pack:travel',
        1,
      );
      final available = await fullyComposed.loadVersion('pack:travel', 1);

      expect(
        unavailable.activities
            .singleWhere(
              (activity) => activity.mode == LessonMode.associativeReading,
            )
            .availability,
        LearningPackActivityAvailability.unavailable,
      );
      expect(
        available.activities
            .singleWhere(
              (activity) => activity.mode == LessonMode.associativeReading,
            )
            .availability,
        LearningPackActivityAvailability.available,
      );
    },
  );
}

final _createdAt = DateTime.utc(2026, 8, 24, 8);

LearningPackDetailUseCases _definitionPackDetailUseCases(
  AppDatabase database, {
  Future<List<VocabularyWord>> Function(Iterable<String>)? readPinnedVocabulary,
}) => LearningPackDetailUseCases(
  packs: repositoryFor(database),
  progress: ProgressUseCases(
    owners: _Owner(),
    queries: DriftProgressQueries(database),
    nowUtc: () => DateTime.utc(2026, 8, 24),
  ),
  lessonModes: buildLessonModeRegistry(),
  features: const BuildFeatureRegistry.allEnabled(),
  hasComposedDependency: (_) => true,
  readPinnedVocabulary: readPinnedVocabulary,
);

DriftLearningPackRepository repositoryFor(AppDatabase database) =>
    DriftLearningPackRepository(
      database,
      contentManifests: DriftContentManifestRepository(database),
    );

LearningPackActivityAvailability _definitionAvailability(
  LearningPackDetailView view,
) => view.activities
    .singleWhere((activity) => activity.mode == LessonMode.definitionQuiz)
    .availability;

LearningPackActivityAvailability _clozeAvailability(
  LearningPackDetailView view,
) => view.activities
    .singleWhere((activity) => activity.mode == LessonMode.cloze)
    .availability;

VocabularyWord _definitionWord({
  String id = 'word:station',
  String spelling = 'station',
  String meaning = 'สถานี',
  String? definition,
  List<String> examples = const <String>[],
}) {
  final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: 'category:pack',
    spelling: spelling,
    normalizedSpelling: spelling,
    meaning: meaning,
    normalizedMeaning: meaning,
    partOfSpeech: 'noun',
    cefrLevel: null,
    source: 'pack:v1',
    isGlobal: true,
  );
  return VocabularyWord(
    id: id,
    ownerId: 'packaged-owner',
    categoryId: 'category:pack',
    spelling: spelling,
    normalizedSpelling: spelling,
    meaning: meaning,
    normalizedMeaning: meaning,
    partOfSpeech: 'noun',
    source: 'pack:v1',
    isGlobal: true,
    localRevision: 1,
    isDeleted: false,
    createdAtUtc: _createdAt,
    updatedAtUtc: _createdAt,
    contentRevision: 1,
    contentChecksumSha256: checksum,
    contentProvenance: ContentProvenance.packaged,
    contentReviewState: ContentReviewState.approved,
    contentPublicationState: ContentPublicationState.published,
    richMetadata: definition == null && examples.isEmpty
        ? null
        : RichLexicalMetadata(
            englishDefinition: definition,
            examples: examples,
            verifiedArtifactChecksumSha256:
                'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
          ),
  );
}

Future<void> _insertVocabularyAuthority(AppDatabase database) async {
  await database.customInsert(
    "INSERT INTO local_owners(id, account_state, created_at_utc_ms, is_active) "
    "VALUES ('packaged-owner', 'localGuest', 1, 0)",
  );
  await database.customInsert(
    "INSERT INTO local_owners(id, account_state, created_at_utc_ms, is_active) "
    "VALUES ('owner:detail', 'localGuest', 1, 1)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_categories "
    "(id, owner_id, name, normalized_name, created_at_utc_ms, "
    "updated_at_utc_ms) VALUES "
    "('category:pack', 'packaged-owner', 'Pack', 'pack', 1, 1)",
  );
  await _insertVocabularyWord(
    database,
    id: 'word:station',
    spelling: 'station',
    meaning: 'สถานี',
  );
  await _insertVocabularyWord(
    database,
    id: 'word:market',
    spelling: 'market',
    meaning: 'ตลาด',
  );
}

Future<void> _insertVocabularyWord(
  AppDatabase database, {
  required String id,
  required String spelling,
  required String meaning,
}) async {
  final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: 'category:pack',
    spelling: spelling,
    normalizedSpelling: spelling,
    meaning: meaning,
    normalizedMeaning: meaning,
    partOfSpeech: 'noun',
    cefrLevel: null,
    source: 'pack:v1',
    isGlobal: true,
  );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: id,
          ownerId: 'packaged-owner',
          categoryId: 'category:pack',
          spelling: spelling,
          normalizedSpelling: spelling,
          meaning: meaning,
          normalizedMeaning: meaning,
          partOfSpeech: 'noun',
          source: const Value('pack:v1'),
          isGlobal: const Value(true),
          contentRevision: const Value(1),
          contentChecksumSha256: Value(checksum),
          contentProvenance: Value(ContentProvenance.packaged.name),
          contentReviewState: Value(ContentReviewState.approved.name),
          contentPublicationState: Value(
            ContentPublicationState.published.name,
          ),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<void> _insertVerifiedPack(
  AppDatabase database, {
  required String packId,
  required int revision,
  required String title,
  required List<String> wordIds,
  ContentPublicationState publicationState = ContentPublicationState.published,
  String? manifestChecksum,
}) async {
  final words = await (database.select(
    database.vocabularyWords,
  )..where((word) => word.id.isIn(wordIds))).get();
  final wordsById = {for (final word in words) word.id: word};
  final references = wordIds
      .map(
        (id) => ContentVocabularyReference(
          id: id,
          revision: wordsById[id]!.contentRevision,
          checksumSha256: wordsById[id]!.contentChecksumSha256!,
        ),
      )
      .toList(growable: false);
  final bytes = ContentQualityPolicy.canonicalLearningPackBytes(
    packId: packId,
    revision: revision,
    title: title,
    cefrLevel: 'A1',
    topic: 'travel',
    skill: 'vocabulary',
    goal: 'recognition',
    vocabularyReferences: references,
  );
  final manifestId = 'manifest:$packId:r$revision';
  final packRowId = '$packId:r$revision';
  await database
      .into(database.contentManifests)
      .insert(
        ContentManifestsCompanion.insert(
          id: manifestId,
          contentType: ContentType.learningPack.name,
          contentId: packId,
          revision: revision,
          checksumSha256: manifestChecksum ?? sha256.convert(bytes).toString(),
          byteLength: bytes.length,
          provenance: ContentProvenance.packaged.name,
          sourceUri: 'asset://learning-packs/$packId-r$revision.json',
          reviewState: ContentReviewState.approved.name,
          publicationState: publicationState.name,
          createdAtUtcMs: _createdAt.millisecondsSinceEpoch,
          reviewedAtUtcMs: Value(
            _createdAt.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
          ),
          publishedAtUtcMs:
              publicationState == ContentPublicationState.published
              ? Value(
                  _createdAt
                      .add(const Duration(minutes: 2))
                      .millisecondsSinceEpoch,
                )
              : const Value.absent(),
        ),
      );
  await database
      .into(database.learningPacks)
      .insert(
        LearningPacksCompanion.insert(
          id: packRowId,
          packId: packId,
          revision: revision,
          manifestId: manifestId,
          title: title,
          cefrLevel: 'A1',
          topic: 'travel',
          skill: 'vocabulary',
          goal: 'recognition',
          createdAtUtcMs: _createdAt.millisecondsSinceEpoch,
        ),
      );
  for (final item in wordIds.indexed) {
    await database
        .into(database.learningPackItems)
        .insert(
          LearningPackItemsCompanion.insert(
            id: '$packRowId:item:${item.$1}',
            learningPackId: packRowId,
            vocabularyWordId: item.$2,
            position: item.$1,
          ),
        );
  }
}

Future<void> _insertLearnerProgress(AppDatabase database) async {
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'session:detail',
          ownerId: 'owner:detail',
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: 1,
          endedAtUtcMs: const Value(2),
          correctCount: const Value(1),
          wrongCount: const Value(0),
          appVersion: 'test',
          buildId: 'test',
        ),
      );
  final context = EvidenceContext.legacyCompatibility(
    evidenceClass: EvidenceClass.recognition,
    skillId: 'learning-pack-detail',
    hintLevel: 0,
    contentRevision: 'pack:travel@1',
    engagementAllowed: true,
  );
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: 'attempt:detail',
          ownerId: 'owner:detail',
          sessionId: 'session:detail',
          wordId: 'word:station',
          promptMode: 'meaningChoice',
          isCorrect: true,
          attemptNumber: 1,
          occurredAtUtcMs: 2,
          evidenceClass: Value(context.evidenceClass.name),
          evidenceContextJson: Value(jsonEncode(context.toJson())),
        ),
      );
}

Future<List<Map<String, Object?>>> _packRows(AppDatabase database) async {
  final rows = await database.customSelect('''
    SELECT p.id, p.pack_id, p.revision, p.manifest_id, p.title,
           p.cefr_level, p.topic, p.skill, p.goal, p.created_at_utc_ms,
           i.id AS item_id, i.vocabulary_word_id, i.position
    FROM learning_packs p
    LEFT JOIN learning_pack_items i ON i.learning_pack_id = p.id
    ORDER BY p.pack_id, p.revision, i.position
  ''').get();
  return rows
      .map((row) => Map<String, Object?>.unmodifiable(row.data))
      .toList(growable: false);
}

final class _Owner implements LocalOwnerRepository {
  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'owner:detail',
        createdAtUtc: DateTime.utc(2026, 8, 24),
      );

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}
