import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/application/contrastive_feedback_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/contrastive_explanation.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'package:vocab_learning_app/features/learning/presentation/contrastive_feedback_panel.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart'
    as vocabulary_domain;
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

void main() {
  group('ContrastiveFeedbackUseCases', () {
    test(
      'requests only the revision pinned by the committed attempt',
      () async {
        final repository = _MemoryManifestRepository(
          <ContentIdentity, VerifiedContentManifest>{
            _identity('word:station', 4): _verifiedArtifact(
              identity: _identity('word:station', 4),
            ),
          },
        );

        final explanation = await ContrastiveFeedbackUseCases(
          manifests: repository,
        ).resolveAfterCommit(committedFeedback: _feedback(revision: 5));

        expect(explanation, isNull);
        expect(repository.requested, <ContentIdentity>[
          _identity('word:station', 5),
        ]);
      },
    );

    test('missing or wrong distractor rationale fails closed', () async {
      final identity = _identity('word:station', 4);
      final repository =
          _MemoryManifestRepository(<ContentIdentity, VerifiedContentManifest>{
            identity: _verifiedArtifact(
              identity: identity,
              distractorRationales: const <String, String>{},
            ),
          });

      expect(
        await ContrastiveFeedbackUseCases(
          manifests: repository,
        ).resolveAfterCommit(committedFeedback: _feedback()),
        isNull,
      );

      final wrongRepository = _MemoryManifestRepository(
        <ContentIdentity, VerifiedContentManifest>{
          identity: _verifiedArtifact(identity: identity),
        },
      );
      expect(
        await ContrastiveFeedbackUseCases(
          manifests: wrongRepository,
        ).resolveAfterCommit(
          committedFeedback: _feedback(selectedDistractorId: 'word:airport'),
        ),
        isNull,
      );
    });

    test(
      'A feedback cannot resolve B or any cross-owner/content identity',
      () async {
        final identityA = _identity('word:station', 4);
        final identityB = _identity('word:market', 7);
        final repository = _MemoryManifestRepository(
          <ContentIdentity, VerifiedContentManifest>{
            identityA: _verifiedArtifact(identity: identityA),
            identityB: _verifiedArtifact(
              identity: identityB,
              correctOptionId: 'word:market',
            ),
          },
        );
        final useCases = ContrastiveFeedbackUseCases(manifests: repository);

        final first = await useCases.resolveAfterCommit(
          committedFeedback: _feedback(),
        );
        final second = await useCases.resolveAfterCommit(
          committedFeedback: _feedback(
            attemptIdentity: 'attempt:b',
            ownerId: 'owner:b',
            sessionId: 'session:b',
            wordId: 'word:market',
            revision: 7,
            correctOptionId: 'word:market',
          ),
        );
        final rejected = await useCases.resolveAfterCommit(
          committedFeedback: _feedback(
            wordId: 'word:market',
            manifestWordId: 'word:station',
          ),
        );

        expect(first, isNotNull);
        expect(second, isNotNull);
        expect(second!.manifestIdentity, identityB);
        expect(rejected, isNull);
        expect(repository.requested, <ContentIdentity>[identityA, identityB]);
      },
    );

    test(
      'lost-ack replay resolves once and remains guided feedback only',
      () async {
        final identity = _identity('word:station', 4);
        final repository = _MemoryManifestRepository(
          <ContentIdentity, VerifiedContentManifest>{
            identity: _verifiedArtifact(identity: identity),
          },
        );
        final useCases = ContrastiveFeedbackUseCases(manifests: repository);
        final feedback = _feedback();

        final first = await useCases.resolveAfterCommit(
          committedFeedback: feedback,
        );
        final replay = await useCases.resolveAfterCommit(
          committedFeedback: feedback,
        );

        expect(replay, same(first));
        expect(first!.evidenceClass, EvidenceClass.guidedPractice);
        expect(repository.calls, 1);
      },
    );

    test(
      'real Drift f04 lexical artifact verifies exact bytes and checksum',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final identity = _identity('word:station', 4);
        final bytes = _lexicalArtifactBytes(identity: identity);
        final checksum = sha256.convert(bytes).toString();
        await database
            .into(database.contentManifests)
            .insert(
              ContentManifestsCompanion.insert(
                id: 'manifest:word:station:4',
                contentType: ContentType.lexicalMetadata.name,
                contentId: identity.id,
                revision: identity.revision,
                checksumSha256: checksum,
                byteLength: bytes.length,
                provenance: ContentProvenance.packaged.name,
                sourceUri:
                    'asset://assets/content/lexical_metadata/station/r4.json',
                reviewState: ContentReviewState.approved.name,
                publicationState: ContentPublicationState.published.name,
                createdAtUtcMs: DateTime.utc(2026, 8, 1).millisecondsSinceEpoch,
                reviewedAtUtcMs: Value(
                  DateTime.utc(2026, 8, 2).millisecondsSinceEpoch,
                ),
                publishedAtUtcMs: Value(
                  DateTime.utc(2026, 8, 3).millisecondsSinceEpoch,
                ),
              ),
            );
        final manifests = DriftContentManifestRepository(
          database,
          loadArtifactBytes: (requested) async =>
              requested == identity ? bytes : null,
        );

        final explanation =
            await ContrastiveFeedbackUseCases(
              manifests: manifests,
            ).resolveAfterCommit(
              committedFeedback: _feedback(manifestChecksumSha256: checksum),
            );

        expect(explanation, isNotNull);
        expect(explanation!.manifestIdentity, identity);
        expect(explanation.selectedDistractorId, 'word:terminal');
      },
    );

    test('verified parser accepts two 4000-rune four-byte rationales', () {
      final rationale = List<String>.filled(4000, '😀').join();
      final identity = _identity('word:station', 4);
      final bytes = _lexicalArtifactBytes(
        identity: identity,
        correctRationale: rationale,
        distractorRationales: <String, String>{'word:terminal': rationale},
      );
      expect(bytes.length, greaterThan(8 * 1024));
      expect(bytes.length, lessThanOrEqualTo(maxLexicalMetadataArtifactBytes));

      final metadata =
          vocabulary_domain.RichLexicalMetadata.fromVerifiedArtifact(
            bytes: bytes,
            wordId: identity.id,
            contentRevision: identity.revision,
            verifiedArtifactChecksumSha256: sha256.convert(bytes).toString(),
          );

      final matching = metadata.contrastiveFeedback['meaningChoice']!;
      expect(matching.correctRationale.runes, hasLength(4000));
      expect(
        matching.distractorRationales['word:terminal']!.runes,
        hasLength(4000),
      );
    });

    test(
      'real meaning review publishes exact token only after canonical commit',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final now = DateTime.utc(2026, 8, 26, 9);
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'owner:review',
          nowUtc: () => now,
        );
        final owner = await owners.getOrCreateActiveOwner();
        final stationIdentity = _identity('word:station', 4);
        final terminalIdentity = _identity('word:terminal', 4);
        final stationBytes = _lexicalArtifactBytes(identity: stationIdentity);
        final terminalBytes = _lexicalArtifactBytes(
          identity: terminalIdentity,
          correctOptionId: 'word:terminal',
          distractorRationales: const <String, String>{
            'word:station': 'A station is not this endpoint.',
          },
        );
        final stationChecksum = sha256.convert(stationBytes).toString();
        final terminalChecksum = sha256.convert(terminalBytes).toString();
        await database
            .into(database.vocabularyCategories)
            .insert(
              VocabularyCategoriesCompanion.insert(
                id: 'category:travel',
                ownerId: owner.id,
                name: 'Travel',
                normalizedName: 'travel',
                createdAtUtcMs: now.millisecondsSinceEpoch,
                updatedAtUtcMs: now.millisecondsSinceEpoch,
              ),
            );
        Future<void> insertWord({
          required String id,
          required String spelling,
          required String meaning,
        }) async {
          final coreChecksum = ContentQualityPolicy.vocabularyChecksumSha256(
            categoryId: 'category:travel',
            spelling: spelling,
            normalizedSpelling: spelling,
            meaning: meaning,
            normalizedMeaning: meaning,
            partOfSpeech: 'noun',
            cefrLevel: 'A1',
            source: 'pack:f18',
            isGlobal: true,
          );
          await database
              .into(database.vocabularyWords)
              .insert(
                VocabularyWordsCompanion.insert(
                  id: id,
                  ownerId: owner.id,
                  categoryId: 'category:travel',
                  spelling: spelling,
                  normalizedSpelling: spelling,
                  meaning: meaning,
                  normalizedMeaning: meaning,
                  partOfSpeech: 'noun',
                  cefrLevel: const Value('A1'),
                  source: const Value('pack:f18'),
                  isGlobal: const Value(true),
                  contentRevision: const Value(4),
                  contentChecksumSha256: Value(coreChecksum),
                  contentProvenance: const Value('packaged'),
                  contentReviewState: const Value('approved'),
                  contentPublicationState: const Value('published'),
                  createdAtUtcMs: now.millisecondsSinceEpoch,
                  updatedAtUtcMs: now.millisecondsSinceEpoch,
                ),
              );
        }

        await insertWord(
          id: 'word:station',
          spelling: 'station',
          meaning: 'train stop',
        );
        await insertWord(
          id: 'word:terminal',
          spelling: 'terminal',
          meaning: 'endpoint',
        );
        Future<void> insertManifest({
          required ContentIdentity identity,
          required Uint8List bytes,
          required String checksum,
        }) async {
          await database
              .into(database.contentManifests)
              .insert(
                ContentManifestsCompanion.insert(
                  id: 'manifest:${identity.id}:${identity.revision}',
                  contentType: identity.type.name,
                  contentId: identity.id,
                  revision: identity.revision,
                  checksumSha256: checksum,
                  byteLength: bytes.length,
                  provenance: ContentProvenance.packaged.name,
                  sourceUri: 'asset://lexical/${identity.id}.json',
                  reviewState: ContentReviewState.approved.name,
                  publicationState: ContentPublicationState.published.name,
                  createdAtUtcMs: now.millisecondsSinceEpoch,
                  reviewedAtUtcMs: Value(now.millisecondsSinceEpoch),
                  publishedAtUtcMs: Value(now.millisecondsSinceEpoch),
                ),
              );
        }

        await insertManifest(
          identity: stationIdentity,
          bytes: stationBytes,
          checksum: stationChecksum,
        );
        await insertManifest(
          identity: terminalIdentity,
          bytes: terminalBytes,
          checksum: terminalChecksum,
        );
        final artifactBytes = <ContentIdentity, Uint8List>{
          stationIdentity: stationBytes,
          terminalIdentity: terminalBytes,
        };
        final manifests = DriftContentManifestRepository(
          database,
          loadArtifactBytes: (identity) async => artifactBytes[identity],
        );
        var id = 0;
        final learning = LearningUseCases(
          owners: owners,
          repository: DriftLearningRepository(database),
          generateId: () => 'id:${++id}',
          nowUtc: () => now.add(Duration(milliseconds: id)),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f18'),
        );
        final session = await learning.startQuiz(
          categoryId: 'category:travel',
          limit: 2,
        );
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        final lexicalWords =
            await DriftVocabularyRepository(
              database,
              contentManifests: manifests,
            ).readPinnedByIds(
              session.questions.map((question) => question.word.id),
            );
        final review = const MeaningQuizModeAdapter().createReview(
          session: session,
          learning: learning,
          evidence: evidence,
          lexicalWords: lexicalWords,
        );
        addTearDown(review.dispose);
        final question = review.currentQuestion;
        final wrongOption = question.options.firstWhere(
          (option) => option != question.correctOption,
        );
        final eventsBefore = await database.select(database.eventsV2).get();

        final operation = review.answer(
          option: wrongOption,
          responseTimeMs: 50,
        );
        expect(review.feedback, isNull);
        final result = await operation;

        final attempt = result.committedContrastiveAttempt;
        expect(review.feedback, isNotNull);
        expect(attempt, isNotNull);
        expect(attempt!.ownerId, owner.id);
        expect(attempt.sessionId, session.id);
        expect(attempt.wordId, question.word.id);
        expect(attempt.promptMode, 'meaningChoice');
        expect(attempt.manifestIdentity.id, question.word.id);
        expect(
          attempt.manifestIdentity.revision,
          question.word.contentRevision,
        );
        expect(
          attempt.correctOptionId,
          question.optionIdentity(question.correctOption),
        );
        expect(
          attempt.selectedDistractorId,
          question.optionIdentity(wrongOption),
        );
        final attemptsAfterCommit = await database
            .select(database.answerAttempts)
            .get();
        final eventsAfterCommit = await database
            .select(database.eventsV2)
            .get();
        expect(attemptsAfterCommit, hasLength(1));
        expect(eventsAfterCommit.length, greaterThan(eventsBefore.length));

        final committedRow = attemptsAfterCommit.single;
        final committedEvidenceContext = EvidenceContext.fromJson(
          (jsonDecode(committedRow.evidenceContextJson) as Map)
              .cast<String, Object?>(),
        );
        await expectLater(
          learning.recordEvidence(
            sourceEvidenceId: committedRow.id,
            occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
              committedRow.occurredAtUtcMs,
              isUtc: true,
            ),
            sessionId: committedRow.sessionId,
            wordId: committedRow.wordId,
            promptMode: committedRow.promptMode,
            isCorrect: committedRow.isCorrect,
            responseTimeMs: committedRow.responseTimeMs,
            attemptNumber: committedRow.attemptNumber,
            evidenceContext: committedEvidenceContext,
            providerProvenance: committedRow.providerProvenance,
            contrastiveFeedback: ContrastiveFeedbackContext(
              manifestIdentity: attempt.manifestIdentity,
              manifestChecksumSha256: attempt.manifestChecksumSha256,
              promptMode: attempt.promptMode,
              evidenceContentRevision: attempt.evidenceContentRevision,
              correctOptionId: attempt.correctOptionId,
              selectedDistractorId: 'word:uncommitted-other',
            ),
          ),
          throwsStateError,
        );

        final explanation = await ContrastiveFeedbackUseCases(
          manifests: manifests,
        ).resolveAfterCommit(committedFeedback: review.feedback!);
        expect(explanation, isNotNull);
        expect(
          await database.select(database.answerAttempts).get(),
          attemptsAfterCommit,
        );
        expect(
          await database.select(database.eventsV2).get(),
          eventsAfterCommit,
        );
      },
    );
  });

  test('typed f18 rollout is implemented-off by default', () {
    expect(
      const ContrastiveFeedbackRollout.implementedOff().allowsPresentation,
      isFalse,
    );
    expect(
      const ContrastiveFeedbackRollout.internal().allowsPresentation,
      isTrue,
    );
  });

  testWidgets(
    'no pre-commit leak; enabled post-commit panel obeys live emergency-off',
    (tester) async {
      final identity = _identity('word:station', 4);
      final repository = _MemoryManifestRepository(
        <ContentIdentity, VerifiedContentManifest>{
          identity: _verifiedArtifact(identity: identity),
        },
      );
      final useCases = ContrastiveFeedbackUseCases(manifests: repository);
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry(<Feature, FeatureState>{
          Feature.quiz: FeatureState.enabled,
        }),
      );
      addTearDown(registry.dispose);

      Future<void> pump(AnswerFeedback? feedback) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: feedback == null
                ? const Text('awaiting canonical commit')
                : AnswerFeedbackPanel(
                    feedback: feedback,
                    contrastiveFeedback: useCases,
                    featureRegistry: registry,
                  ),
          ),
        ),
      );

      await pump(null);
      await tester.pump();
      expect(find.byType(ContrastiveFeedbackPanel), findsNothing);
      expect(repository.calls, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnswerFeedbackPanel(
              feedback: _feedback(),
              featureRegistry: registry,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ContrastiveFeedbackPanel), findsNothing);
      expect(repository.calls, 0);

      await pump(_feedback());
      await tester.pumpAndSettle();
      expect(find.byType(ContrastiveFeedbackPanel), findsOneWidget);
      expect(repository.calls, 1);

      registry.emergencyOff(Feature.quiz);
      await tester.pump();
      expect(find.byType(ContrastiveFeedbackPanel), findsNothing);
      expect(repository.calls, 1);

      registry.clearOverride(Feature.quiz);
      await tester.pump();
      await tester.pump();
      expect(find.byType(ContrastiveFeedbackPanel), findsOneWidget);
      expect(repository.calls, 1);
    },
  );

  testWidgets(
    'stale A resolution cannot paint over newer committed B feedback',
    (tester) async {
      final identityA = _identity('word:station', 4);
      final identityB = _identity('word:market', 7);
      final artifactA = _verifiedArtifact(identity: identityA);
      final artifactB = _verifiedArtifact(
        identity: identityB,
        correctOptionId: 'word:market',
        distractorRationales: const <String, String>{
          'word:terminal': 'B selected rationale.',
        },
      );
      final repository = _DelayedManifestRepository();
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry(<Feature, FeatureState>{
          Feature.quiz: FeatureState.enabled,
        }),
      );
      addTearDown(registry.dispose);
      final useCases = ContrastiveFeedbackUseCases(manifests: repository);

      Future<void> pump(AnswerFeedback feedback) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnswerFeedbackPanel(
              feedback: feedback,
              contrastiveFeedback: useCases,
              featureRegistry: registry,
            ),
          ),
        ),
      );

      await pump(
        _feedback(manifestChecksumSha256: artifactA.manifest.checksumSha256),
      );
      await tester.pump();
      expect(repository.requested, <ContentIdentity>[identityA]);

      await pump(
        _feedback(
          attemptIdentity: 'attempt:b',
          ownerId: 'owner:b',
          sessionId: 'session:b',
          wordId: 'word:market',
          revision: 7,
          correctOptionId: 'word:market',
          manifestChecksumSha256: artifactB.manifest.checksumSha256,
        ),
      );
      await tester.pump();
      expect(repository.requested, <ContentIdentity>[identityA, identityB]);

      repository.complete(identityB, artifactB);
      await tester.pump();
      await tester.pump();
      expect(find.text('B selected rationale.'), findsOneWidget);

      repository.complete(identityA, artifactA);
      await tester.pump();
      await tester.pump();
      expect(find.text('B selected rationale.'), findsOneWidget);
      expect(
        find.text('A terminal is a broader endpoint, not this train stop.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    '4000-rune rationale remains scrollable at 200 percent text scale',
    (tester) async {
      final longRationale = List<String>.filled(4000, 'x').join();
      final identity = _identity('word:station', 4);
      final artifact = _verifiedArtifact(
        identity: identity,
        correctRationale: longRationale,
      );
      final useCases = ContrastiveFeedbackUseCases(
        manifests: _MemoryManifestRepository(
          <ContentIdentity, VerifiedContentManifest>{identity: artifact},
        ),
      );
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry(<Feature, FeatureState>{
          Feature.quiz: FeatureState.enabled,
        }),
      );
      addTearDown(registry.dispose);
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 480),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: AnswerFeedbackPanel(
                feedback: _feedback(
                  manifestChecksumSha256: artifact.manifest.checksumSha256,
                ),
                contrastiveFeedback: useCases,
                featureRegistry: registry,
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(
        tester.getBottomRight(find.text('Try again')).dy,
        lessThanOrEqualTo(480),
      );
    },
  );
}

AnswerFeedback _feedback({
  String attemptIdentity = 'attempt:a',
  String ownerId = 'owner:a',
  String sessionId = 'session:a',
  String wordId = 'word:station',
  String? manifestWordId,
  int revision = 4,
  String correctOptionId = 'word:station',
  String selectedDistractorId = 'word:terminal',
  String? manifestChecksumSha256,
}) {
  final checksum =
      manifestChecksumSha256 ??
      sha256
          .convert(
            _lexicalArtifactBytes(
              identity: _identity(manifestWordId ?? wordId, revision),
              correctOptionId: correctOptionId,
            ),
          )
          .toString();
  return AnswerFeedback.fromCommittedResult(
    result: AnswerRecordResult(
      inserted: true,
      isCorrect: false,
      srs: null,
      committedContrastiveAttempt: CommittedContrastiveAttempt(
        attemptIdentity: attemptIdentity,
        ownerId: ownerId,
        sessionId: sessionId,
        wordId: wordId,
        promptMode: 'meaningChoice',
        evidenceContentRevision: 'lexical-meaning:$wordId@$revision:$checksum',
        manifestIdentity: _identity(manifestWordId ?? wordId, revision),
        manifestChecksumSha256: checksum,
        correctOptionId: correctOptionId,
        selectedDistractorId: selectedDistractorId,
      ),
    ),
    context: const AnswerFeedbackContext(canonicalCorrectAnswer: 'station'),
  );
}

ContentIdentity _identity(String wordId, int revision) => ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: wordId,
  revision: revision,
);

Uint8List _lexicalArtifactBytes({
  required ContentIdentity identity,
  String correctOptionId = 'word:station',
  String correctRationale = 'A station is where trains stop.',
  Map<String, String> distractorRationales = const <String, String>{
    'word:terminal': 'A terminal is a broader endpoint, not this train stop.',
  },
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode(<String, Object?>{
      'schemaVersion': 4,
      'wordId': identity.id,
      'contentRevision': identity.revision,
      'englishDefinition': 'A place where trains stop.',
      'ipa': '/steɪʃən/',
      'examples': <String>['The train reached the station.'],
      'synonyms': <String>[],
      'antonyms': <String>[],
      'acceptedSpellingVariants': <String>[],
      'audio': null,
      'contrastiveFeedback': <String, Object?>{
        'meaningChoice': <String, Object?>{
          'correctOptionId': correctOptionId,
          'correctRationale': correctRationale,
          'distractorRationales': distractorRationales,
        },
      },
    }),
  ),
);

VerifiedContentManifest _verifiedArtifact({
  required ContentIdentity identity,
  String correctOptionId = 'word:station',
  String correctRationale = 'A station is where trains stop.',
  Map<String, String> distractorRationales = const <String, String>{
    'word:terminal': 'A terminal is a broader endpoint, not this train stop.',
  },
}) {
  final bytes = _lexicalArtifactBytes(
    identity: identity,
    correctOptionId: correctOptionId,
    correctRationale: correctRationale,
    distractorRationales: distractorRationales,
  );
  return VerifiedContentManifest(
    manifest: ContentManifest(
      storageId: 'manifest:${identity.id}:${identity.revision}',
      identity: identity,
      checksumSha256: sha256.convert(bytes).toString(),
      byteLength: bytes.length,
      provenance: ContentProvenance.packaged,
      sourceUri: 'asset://assets/content/lexical_metadata/test.json',
      reviewState: ContentReviewState.approved,
      publicationState: ContentPublicationState.published,
      createdAtUtc: DateTime.utc(2026, 8, 1),
      reviewedAtUtc: DateTime.utc(2026, 8, 2),
      publishedAtUtc: DateTime.utc(2026, 8, 3),
    ),
    bytes: bytes,
  );
}

final class _MemoryManifestRepository implements ContentManifestRepository {
  _MemoryManifestRepository(this.artifacts);

  final Map<ContentIdentity, VerifiedContentManifest> artifacts;
  final List<ContentIdentity> requested = <ContentIdentity>[];

  int get calls => requested.length;

  @override
  Future<VerifiedContentManifest> requireVerified(
    ContentIdentity identity,
  ) async {
    requested.add(identity);
    final artifact = artifacts[identity];
    if (artifact == null) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingReference,
      );
    }
    return artifact;
  }
}

final class _DelayedManifestRepository implements ContentManifestRepository {
  final List<ContentIdentity> requested = <ContentIdentity>[];
  final Map<ContentIdentity, Completer<VerifiedContentManifest>> _pending =
      <ContentIdentity, Completer<VerifiedContentManifest>>{};

  @override
  Future<VerifiedContentManifest> requireVerified(ContentIdentity identity) {
    requested.add(identity);
    return _pending
        .putIfAbsent(identity, Completer<VerifiedContentManifest>.new)
        .future;
  }

  void complete(ContentIdentity identity, VerifiedContentManifest artifact) {
    _pending[identity]!.complete(artifact);
  }
}
