import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/definition_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lexical_prompt_artifact_identity.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/review/application/review_center_use_cases.dart';
import 'package:vocab_learning_app/features/review/data/drift_review_center_reader.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart'
    as vocabulary_domain;

void main() {
  late AppDatabase database;
  late DriftReviewCenterReader reader;
  late Map<ContentIdentity, Uint8List> lexicalArtifacts;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    lexicalArtifacts = <ContentIdentity, Uint8List>{};
    reader = DriftReviewCenterReader(
      database,
      contentManifests: DriftContentManifestRepository(
        database,
        loadArtifactBytes: (identity) async => lexicalArtifacts[identity],
      ),
    );
    await _insertOwner(database, 'owner-1');
    await _insertOwner(database, 'owner-2', active: false);
    await _insertCategory(database, ownerId: 'owner-1', id: 'category-1');
    await _insertCategory(database, ownerId: 'owner-2', id: 'category-2');
  });

  tearDown(() => database.close());

  test(
    'merges saved incorrect reported and due sources with exact provenance',
    () async {
      await _insertWord(database, id: 'word-1', spelling: 'station');
      await _insertSaved(database, id: 'saved-1', wordId: 'word-1');
      await _insertAttempt(database, id: 'attempt-1', wordId: 'word-1');
      await _insertReport(database, id: 'report-1', wordId: 'word-1');
      await _insertSrs(database, id: 'srs-1', wordId: 'word-1', dueAtUtc: _now);

      final queue = await reader.compose(_filter());

      expect(queue, hasLength(1));
      final item = queue.single;
      expect(
        item.identity,
        const ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: 'word-1',
          revision: 1,
        ),
      );
      expect(item.spelling, 'station');
      expect(item.reasons, [
        ReviewQueueReason.dueSrs,
        ReviewQueueReason.incorrectAnswer,
        ReviewQueueReason.reported,
        ReviewQueueReason.saved,
      ]);
      expect(
        item.provenance.map((source) => source.authority),
        containsAllInOrder([
          ReviewQueueAuthority.srs,
          ReviewQueueAuthority.answerAttempts,
          ReviewQueueAuthority.contentQualityReports,
          ReviewQueueAuthority.savedLearningItems,
        ]),
      );
      expect(
        item.provenance.map((source) => source.sourceId),
        containsAll(<String>['srs-1', 'attempt-1', 'report-1', 'saved-1']),
      );
      expect(
        item.provenance.singleWhere((source) => source.isReport).reportReason,
        ContentReportReason.answer,
      );
    },
  );

  test(
    'orders by typed priority, source time, spelling, id, and revision',
    () async {
      await _insertWord(database, id: 'word-due-z', spelling: 'zebra');
      await _insertWord(
        database,
        id: 'word-due-a2',
        spelling: 'alpha',
        meaning: 'second',
      );
      await _insertWord(
        database,
        id: 'word-due-a1',
        spelling: 'alpha',
        meaning: 'first',
      );
      await _insertWord(database, id: 'word-wrong', spelling: 'beta');
      await _insertWord(database, id: 'word-report', spelling: 'gamma');
      await _insertWord(database, id: 'word-saved', spelling: 'delta');
      await _insertSrs(
        database,
        id: 'srs-z',
        wordId: 'word-due-z',
        dueAtUtc: _now.subtract(const Duration(hours: 2)),
      );
      await _insertSrs(
        database,
        id: 'srs-a2',
        wordId: 'word-due-a2',
        dueAtUtc: _now.subtract(const Duration(hours: 1)),
      );
      await _insertSrs(
        database,
        id: 'srs-a1',
        wordId: 'word-due-a1',
        dueAtUtc: _now.subtract(const Duration(hours: 1)),
      );
      await _insertAttempt(database, id: 'wrong', wordId: 'word-wrong');
      await _insertReport(database, id: 'report', wordId: 'word-report');
      await _insertSaved(database, id: 'saved', wordId: 'word-saved');

      final first = await reader.compose(_filter());
      final replay = await reader.compose(_filter());

      expect(first.map((item) => item.identity.id), [
        'word-due-z',
        'word-due-a1',
        'word-due-a2',
        'word-wrong',
        'word-report',
        'word-saved',
      ]);
      expect(
        replay.map((item) => item.identity),
        first.map((item) => item.identity),
      );
    },
  );

  test(
    'includes the exact due boundary and excludes one millisecond later',
    () async {
      await _insertWord(database, id: 'word-now', spelling: 'now');
      await _insertWord(database, id: 'word-later', spelling: 'later');
      await _insertSrs(
        database,
        id: 'srs-now',
        wordId: 'word-now',
        dueAtUtc: _now,
      );
      await _insertSrs(
        database,
        id: 'srs-later',
        wordId: 'word-later',
        dueAtUtc: _now.add(const Duration(milliseconds: 1)),
      );

      final queue = await reader.compose(_filter());

      expect(queue.map((item) => item.identity.id), ['word-now']);
    },
  );

  test('isolates owners across content and every source authority', () async {
    await _insertWord(database, id: 'owner-1-word', spelling: 'mine');
    await _insertWord(
      database,
      ownerId: 'owner-2',
      categoryId: 'category-2',
      id: 'owner-2-word',
      spelling: 'theirs',
    );
    await _insertSaved(database, id: 'mine', wordId: 'owner-1-word');
    await _insertSaved(
      database,
      ownerId: 'owner-2',
      id: 'theirs-saved',
      wordId: 'owner-2-word',
    );
    await _insertAttempt(
      database,
      ownerId: 'owner-2',
      id: 'theirs-attempt',
      wordId: 'owner-2-word',
    );
    await _insertReport(
      database,
      ownerId: 'owner-2',
      id: 'theirs-report',
      wordId: 'owner-2-word',
    );
    await _insertSrs(
      database,
      ownerId: 'owner-2',
      id: 'theirs-srs',
      wordId: 'owner-2-word',
      dueAtUtc: _now,
    );

    final queue = await reader.compose(_filter());

    expect(queue.map((item) => item.identity.id), ['owner-1-word']);
    expect(queue.single.provenance, hasLength(1));
  });

  test(
    'fails closed for deleted tombstoned unavailable and stale revisions',
    () async {
      await _insertWord(database, id: 'live', spelling: 'live', revision: 2);
      await _insertWord(
        database,
        id: 'deleted',
        spelling: 'deleted',
        deleted: true,
      );
      await _insertWord(
        database,
        id: 'retired',
        spelling: 'retired',
        publicationState: ContentPublicationState.retired.name,
      );
      await _insertWord(
        database,
        id: 'tombstoned-word',
        spelling: 'tombstoned',
      );
      await _insertSaved(database, id: 'current', wordId: 'live', revision: 2);
      await _insertSaved(database, id: 'stale', wordId: 'live', revision: 1);
      await _insertSaved(
        database,
        id: 'tombstone',
        wordId: 'tombstoned-word',
        deleted: true,
      );
      await _insertSaved(database, id: 'deleted-save', wordId: 'deleted');
      await _insertSaved(database, id: 'retired-save', wordId: 'retired');
      await _insertReport(
        database,
        id: 'stale-report',
        wordId: 'live',
        revision: 1,
      );

      final queue = await reader.compose(_filter());

      expect(queue, hasLength(1));
      expect(queue.single.identity.id, 'live');
      expect(queue.single.identity.revision, 2);
      expect(queue.single.provenance.map((source) => source.sourceId), [
        'current',
      ]);
    },
  );

  test(
    'fails closed for corrupt or unknown source identity metadata',
    () async {
      await _insertWord(database, id: 'word-1', spelling: 'station');
      await _insertAttempt(
        database,
        id: 'bad-attempt',
        wordId: 'word-1',
        evidenceContextJson: '{not-json',
      );
      await _insertSaved(
        database,
        id: 'bad-type',
        wordId: 'word-1',
        contentType: 'unknown',
      );
      await _insertReport(
        database,
        id: 'bad-report',
        wordId: 'word-1',
        reasonCode: 'unknown',
      );

      final queue = await reader.compose(_filter());

      expect(queue, isEmpty);
    },
  );

  test(
    'incorrect requires a canonical correlated event and exact lexical revision',
    () async {
      for (final id in <String>[
        'valid',
        'valid-matching',
        'checksum-mismatch',
        'artifact-mismatch',
        'orphan',
        'event-mismatch',
        'actor-mismatch',
        'session-mismatch',
        'prompt-mismatch',
        'event-revision-mismatch',
      ]) {
        await _insertWord(database, id: id, spelling: id);
      }
      await _insertWord(
        database,
        id: 'stale-revision',
        spelling: 'stale revision',
        revision: 2,
      );
      await _insertAttempt(database, id: 'valid', wordId: 'valid');
      await _insertAttempt(
        database,
        id: 'valid-matching',
        wordId: 'valid-matching',
        promptMode: 'matchingPair',
      );
      await _insertAttempt(
        database,
        id: 'checksum-mismatch',
        wordId: 'checksum-mismatch',
        contentRevisionText: _lexicalRevision(
          'checksum-mismatch',
          1,
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        ),
      );
      await _insertAttempt(
        database,
        id: 'artifact-mismatch',
        wordId: 'artifact-mismatch',
        contentRevisionText: _lexicalRevision(
          'artifact-mismatch',
          1,
          _canonicalWordChecksum(spelling: 'artifact-mismatch'),
          artifact: 'lexical-cloze',
        ),
      );
      await _insertAttempt(
        database,
        id: 'orphan',
        wordId: 'orphan',
        includeSourceEvent: false,
      );
      await _insertAttempt(
        database,
        id: 'event-mismatch',
        wordId: 'event-mismatch',
        mutateSourceEvent: (json) => json['eventType'] = 'QuizCompleted',
      );
      await _insertAttempt(
        database,
        id: 'actor-mismatch',
        wordId: 'actor-mismatch',
        mutateSourceEvent: (json) => json['actorIdentity'] = 'owner-2',
      );
      await _insertAttempt(
        database,
        id: 'session-mismatch',
        wordId: 'session-mismatch',
        mutateSourceEvent: (json) => json['aggregateId'] = 'other-session',
      );
      await _insertAttempt(
        database,
        id: 'prompt-mismatch',
        wordId: 'prompt-mismatch',
        mutateSourceEvent: (json) =>
            (json['payload']! as Map<String, dynamic>)['promptMode'] =
                'differentPrompt',
      );
      await _insertAttempt(
        database,
        id: 'event-revision-mismatch',
        wordId: 'event-revision-mismatch',
        mutateSourceEvent: (json) => json['contentRevision'] = _lexicalRevision(
          'event-revision-mismatch',
          9,
          _canonicalWordChecksum(spelling: 'event-revision-mismatch'),
        ),
      );
      await _insertAttempt(
        database,
        id: 'stale-revision',
        wordId: 'stale-revision',
        contentRevision: 1,
      );

      final queue = await reader.compose(
        _filter(includeReasons: const {ReviewQueueReason.incorrectAnswer}),
      );

      expect(queue.map((item) => item.identity.id), [
        'valid',
        'valid-matching',
      ]);
      expect(
        queue
            .expand((item) => item.provenance)
            .map((source) => source.sourceId),
        ['valid', 'valid-matching'],
      );
    },
  );

  test(
    'accepts exact evidence identities emitted by every review mode adapter',
    () async {
      final richChecksums = <String, String>{};
      final spellings = <String, String>{
        'meaning': 'station',
        'meaning-distractor': 'airport',
        'definition': 'platform',
        'definition-distractor': 'terminal',
        'cloze': 'ticket',
        'cloze-distractor': 'passport',
        'typed-variants': 'color',
        'typed-core': 'signal',
        'matching': 'train',
        'matching-distractor': 'bus',
      };
      for (final entry in spellings.entries) {
        await _insertWord(
          database,
          id: entry.key,
          spelling: entry.value,
          packaged: true,
        );
        if (entry.key != 'typed-core' &&
            entry.key != 'matching' &&
            entry.key != 'matching-distractor') {
          richChecksums[entry.key] = await _insertLexicalArtifact(
            database,
            artifacts: lexicalArtifacts,
            wordId: entry.key,
            englishDefinition: entry.key.startsWith('definition')
                ? entry.key == 'definition'
                      ? 'A raised area beside a railway track.'
                      : 'A building for arriving and departing passengers.'
                : null,
            examples: entry.key.startsWith('cloze')
                ? [
                    entry.key == 'cloze'
                        ? 'Keep your ticket until the journey ends.'
                        : 'Show your passport at the border.',
                  ]
                : const <String>[],
            acceptedVariants: entry.key == 'typed-variants'
                ? const <String>['colour']
                : const <String>[],
          );
        }
      }
      final learning = _learningUseCases(database);
      final evidence = CurrentActivityEvidenceAdapter(learning: learning);

      await _recordMeaningIncorrect(
        database: database,
        learning: learning,
        evidence: evidence,
        target: _packagedWord(
          id: 'meaning',
          spelling: spellings['meaning']!,
          artifactChecksum: richChecksums['meaning']!,
        ),
        distractor: _packagedWord(
          id: 'meaning-distractor',
          spelling: spellings['meaning-distractor']!,
          artifactChecksum: richChecksums['meaning-distractor']!,
        ),
      );
      await _recordDefinitionIncorrect(
        database: database,
        learning: learning,
        evidence: evidence,
        target: _packagedWord(
          id: 'definition',
          spelling: spellings['definition']!,
          artifactChecksum: richChecksums['definition']!,
          definition: 'A raised area beside a railway track.',
        ),
        distractor: _packagedWord(
          id: 'definition-distractor',
          spelling: spellings['definition-distractor']!,
          artifactChecksum: richChecksums['definition-distractor']!,
          definition: 'A building for arriving and departing passengers.',
        ),
      );
      await _recordClozeIncorrect(
        database: database,
        learning: learning,
        evidence: evidence,
        target: _packagedWord(
          id: 'cloze',
          spelling: spellings['cloze']!,
          artifactChecksum: richChecksums['cloze']!,
          example: 'Keep your ticket until the journey ends.',
        ),
        distractor: _packagedWord(
          id: 'cloze-distractor',
          spelling: spellings['cloze-distractor']!,
          artifactChecksum: richChecksums['cloze-distractor']!,
          example: 'Show your passport at the border.',
        ),
      );
      await _recordTypedRecallIncorrect(
        database: database,
        evidence: evidence,
        word: _quizWord(
          id: 'typed-variants',
          spelling: spellings['typed-variants']!,
          acceptedVariants: const ['colour'],
          acceptedVariantsChecksum: richChecksums['typed-variants'],
        ),
      );
      await _recordTypedRecallIncorrect(
        database: database,
        evidence: evidence,
        word: _quizWord(id: 'typed-core', spelling: spellings['typed-core']!),
      );
      await _recordMatchingIncorrect(
        database: database,
        learning: learning,
        evidence: evidence,
        target: _quizWord(id: 'matching', spelling: spellings['matching']!),
        distractor: _quizWord(
          id: 'matching-distractor',
          spelling: spellings['matching-distractor']!,
        ),
      );

      final queue = await reader.compose(
        _filter(includeReasons: const {ReviewQueueReason.incorrectAnswer}),
      );

      expect(queue.map((item) => item.identity.id).toSet(), {
        'meaning',
        'definition',
        'cloze',
        'typed-variants',
        'typed-core',
        'matching',
      });
    },
  );

  test(
    'rejects validly shaped wrong rich checksum and prompt artifact identity',
    () async {
      final artifactChecksums = <String, String>{};
      for (final id in <String>['rich-valid', 'rich-wrong', 'rich-artifact']) {
        await _insertWord(database, id: id, spelling: id, packaged: true);
        artifactChecksums[id] = await _insertLexicalArtifact(
          database,
          artifacts: lexicalArtifacts,
          wordId: id,
        );
      }
      await _insertAttempt(
        database,
        id: 'rich-valid',
        wordId: 'rich-valid',
        promptMode: 'meaningChoice',
        contentRevisionText: _promptRevision(
          promptMode: 'meaningChoice',
          wordId: 'rich-valid',
          coreChecksumSha256: _canonicalWordChecksum(
            spelling: 'rich-valid',
            source: 'pack',
            isGlobal: true,
          ),
          artifactChecksumSha256: artifactChecksums['rich-valid']!,
        ),
      );
      await _insertAttempt(
        database,
        id: 'rich-wrong',
        wordId: 'rich-wrong',
        promptMode: 'meaningChoice',
        contentRevisionText: _promptRevision(
          promptMode: 'meaningChoice',
          wordId: 'rich-wrong',
          coreChecksumSha256: _canonicalWordChecksum(
            spelling: 'rich-wrong',
            source: 'pack',
            isGlobal: true,
          ),
          artifactChecksumSha256:
              'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        ),
      );
      await _insertAttempt(
        database,
        id: 'rich-artifact',
        wordId: 'rich-artifact',
        promptMode: 'meaningChoice',
        contentRevisionText: _promptRevision(
          promptMode: 'clozeSelected',
          wordId: 'rich-artifact',
          coreChecksumSha256: _canonicalWordChecksum(
            spelling: 'rich-artifact',
            source: 'pack',
            isGlobal: true,
          ),
          artifactChecksumSha256: artifactChecksums['rich-artifact']!,
        ),
      );

      final queue = await reader.compose(
        _filter(includeReasons: const {ReviewQueueReason.incorrectAnswer}),
      );

      expect(queue.map((item) => item.identity.id), ['rich-valid']);
    },
  );

  test(
    'typed recall derives identity only from verified artifact variants',
    () async {
      for (final id in <String>[
        'typed-no-variants',
        'typed-variants',
        'typed-corrupt',
        'typed-missing',
      ]) {
        await _insertWord(database, id: id, spelling: id, packaged: true);
      }
      final noVariantsChecksum = await _insertLexicalArtifact(
        database,
        artifacts: lexicalArtifacts,
        wordId: 'typed-no-variants',
      );
      final variantsChecksum = await _insertLexicalArtifact(
        database,
        artifacts: lexicalArtifacts,
        wordId: 'typed-variants',
        acceptedVariants: const <String>['typed variants'],
      );
      final corruptBytes = Uint8List.fromList(utf8.encode('{"corrupt":true}'));
      final corruptChecksum = sha256.convert(corruptBytes).toString();
      lexicalArtifacts[const ContentIdentity(
            type: ContentType.lexicalMetadata,
            id: 'typed-corrupt',
            revision: 1,
          )] =
          corruptBytes;
      await _insertLexicalManifest(
        database,
        wordId: 'typed-corrupt',
        checksum: corruptChecksum,
        byteLength: corruptBytes.length,
      );
      final missingBytes = _lexicalArtifactBytes(wordId: 'typed-missing');
      final missingChecksum = sha256.convert(missingBytes).toString();
      await _insertLexicalManifest(
        database,
        wordId: 'typed-missing',
        checksum: missingChecksum,
        byteLength: missingBytes.length,
      );
      for (final entry in <String, String>{
        'typed-no-variants': noVariantsChecksum,
        'typed-variants': variantsChecksum,
        'typed-corrupt': corruptChecksum,
        'typed-missing': missingChecksum,
      }.entries) {
        final coreChecksum = _canonicalWordChecksum(
          spelling: entry.key,
          source: 'pack',
          isGlobal: true,
        );
        final derived =
            LexicalPromptArtifactResolver.typedRecallAnswerSetChecksumSha256(
              coreChecksumSha256: coreChecksum,
              acceptedVariantsRevision: 1,
              acceptedVariantsChecksumSha256: entry.value,
            );
        await _insertAttempt(
          database,
          id: entry.key,
          wordId: entry.key,
          promptMode: 'typedRecall',
          contentRevisionText: _lexicalRevision(
            entry.key,
            1,
            derived,
            artifact: 'lexical-typed-recall',
          ),
        );
      }

      final queue = await reader.compose(
        _filter(includeReasons: const {ReviewQueueReason.incorrectAnswer}),
      );

      expect(queue.map((item) => item.identity.id), ['typed-variants']);
    },
  );

  test(
    'launch rejects a category deleted after compose and creates no session',
    () async {
      await _insertWord(database, id: 'word-1', spelling: 'station');
      await _insertSaved(database, id: 'saved-1', wordId: 'word-1');
      final item = (await reader.compose(_filter())).single;
      await (database.update(database.vocabularyCategories)
            ..where((row) => row.id.equals('category-1')))
          .write(const VocabularyCategoriesCompanion(isDeleted: Value(true)));
      final useCases = _launchUseCases(database);

      await expectLater(useCases.launch(item), throwsStateError);

      expect(await database.select(database.learningSessions).get(), isEmpty);
    },
  );

  for (final mutation in <String, VocabularyWordsCompanion>{
    'lifecycle': const VocabularyWordsCompanion(
      contentReviewState: Value('rejected'),
    ),
    'provenance': const VocabularyWordsCompanion(
      contentProvenance: Value('packaged'),
    ),
    'checksum': const VocabularyWordsCompanion(
      contentChecksumSha256: Value(
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      ),
    ),
  }.entries) {
    test(
      'launch rejects ${mutation.key} drift without a revision bump',
      () async {
        await _insertWord(database, id: 'word-1', spelling: 'station');
        await _insertSaved(database, id: 'saved-1', wordId: 'word-1');
        final item = (await reader.compose(_filter())).single;
        await (database.update(
          database.vocabularyWords,
        )..where((row) => row.id.equals('word-1'))).write(mutation.value);
        final useCases = _launchUseCases(database);

        await expectLater(useCases.launch(item), throwsStateError);

        expect(await database.select(database.learningSessions).get(), isEmpty);
      },
    );
  }

  test(
    'launch rejects a same-revision core rewrite with a new valid checksum',
    () async {
      await _insertWord(database, id: 'word-1', spelling: 'station');
      await _insertSaved(database, id: 'saved-1', wordId: 'word-1');
      final item = (await reader.compose(_filter())).single;
      const rewrittenSpelling = 'platform';
      const rewrittenMeaning = 'ชานชาลา';
      await (database.update(
        database.vocabularyWords,
      )..where((row) => row.id.equals('word-1'))).write(
        VocabularyWordsCompanion(
          spelling: const Value(rewrittenSpelling),
          normalizedSpelling: const Value(rewrittenSpelling),
          meaning: const Value(rewrittenMeaning),
          normalizedMeaning: const Value(rewrittenMeaning),
          contentChecksumSha256: Value(
            _canonicalWordChecksum(
              spelling: rewrittenSpelling,
              meaning: rewrittenMeaning,
            ),
          ),
          updatedAtUtcMs: const Value(2),
        ),
      );
      final useCases = _launchUseCases(database);

      await expectLater(useCases.launch(item), throwsStateError);

      expect(await database.select(database.learningSessions).get(), isEmpty);
    },
  );

  for (final removeArtifact in <bool>[false, true]) {
    test(
      'launch rejects a reviewed artifact ${removeArtifact ? 'removal' : 'replacement'} after compose',
      () async {
        await _insertWord(database, id: 'word-1', spelling: 'station');
        await _insertSaved(database, id: 'saved-1', wordId: 'word-1');
        await _insertLexicalManifest(
          database,
          wordId: 'word-1',
          checksum:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );
        final item = (await reader.compose(_filter())).single;
        await database.customStatement(
          'DROP TRIGGER IF EXISTS content_manifests_reject_update',
        );
        await database.customStatement(
          'DROP TRIGGER IF EXISTS content_manifests_reject_delete',
        );
        if (removeArtifact) {
          await (database.delete(
            database.contentManifests,
          )..where((row) => row.contentId.equals('word-1'))).go();
        } else {
          await (database.update(
            database.contentManifests,
          )..where((row) => row.contentId.equals('word-1'))).write(
            const ContentManifestsCompanion(
              checksumSha256: Value(
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              ),
            ),
          );
        }
        final useCases = _launchUseCases(database);

        await expectLater(useCases.launch(item), throwsStateError);

        expect(await database.select(database.learningSessions).get(), isEmpty);
      },
    );
  }

  for (final switchOwner in <bool>[false, true]) {
    final scenario = switchOwner ? 'owner switch' : 'owner logout';
    test(
      'launch transaction rejects $scenario after owner resolution',
      () async {
        await _insertWord(database, id: 'word-1', spelling: 'station');
        await _insertSaved(database, id: 'saved-1', wordId: 'word-1');
        final item = (await reader.compose(_filter())).single;
        final useCases = _launchUseCases(
          database,
          beforeStart: () => database.transaction(() async {
            await (database.update(database.localOwners)
                  ..where((row) => row.id.equals('owner-1')))
                .write(const LocalOwnersCompanion(isActive: Value(false)));
            if (switchOwner) {
              await (database.update(database.localOwners)
                    ..where((row) => row.id.equals('owner-2')))
                  .write(const LocalOwnersCompanion(isActive: Value(true)));
            }
          }),
        );

        await expectLater(useCases.launch(item), throwsStateError);

        expect(await database.select(database.learningSessions).get(), isEmpty);
      },
    );
  }

  test(
    'review launch rejects invalid generated session IDs before insert',
    () async {
      await _insertWord(database, id: 'word-1', spelling: 'station');
      final item = _item();
      for (final generatedId in <String>[
        List<String>.filled(300, 'x').join(),
        'review\u0000invalid',
      ]) {
        final useCases = _launchUseCases(
          database,
          generateId: () => generatedId,
        );

        await expectLater(useCases.launch(item), throwsArgumentError);
        expect(await database.select(database.learningSessions).get(), isEmpty);
      }
    },
  );

  test(
    'review launch rejects the canonical learning clock before insert',
    () async {
      await _insertWord(database, id: 'word-1', spelling: 'station');
      final useCases = _launchUseCases(
        database,
        learningNowUtc: () =>
            DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true),
        reviewNowUtc: () => _now,
      );

      await expectLater(useCases.launch(_item()), throwsArgumentError);

      expect(await database.select(database.learningSessions).get(), isEmpty);
    },
  );

  test(
    'review launch fails closed on a duplicate session ID for another item',
    () async {
      await _insertWord(database, id: 'word-1', spelling: 'station');
      await _insertWord(database, id: 'word-2', spelling: 'platform');
      final useCases = _launchUseCases(
        database,
        generateId: () => 'review-collision',
      );
      final firstItem = _item();
      final secondItem = ReviewQueueItem(
        snapshot: _reviewSnapshot(
          id: 'word-2',
          spelling: 'platform',
          meaning: 'meaning-platform',
        ),
        provenance: [
          ReviewReasonProvenance.saved(
            sourceId: 'saved-2',
            occurredAtUtc: _now,
          ),
        ],
      );

      final first = await useCases.launch(firstItem);
      await expectLater(useCases.launch(secondItem), throwsStateError);

      final sessions = await database.select(database.learningSessions).get();
      expect(sessions, hasLength(1));
      expect(sessions.single.id, first.session.id);
      expect(sessions.single.ownerId, 'owner-1');
      expect(sessions.single.state, 'active');
      expect(first.session.questions.single.word.id, 'word-1');
    },
  );

  test(
    'user-authored content accepts only unreviewed private lifecycle metadata',
    () async {
      final cases = <String, (String, String)>{
        'allowed': (
          ContentReviewState.unreviewed.name,
          ContentPublicationState.private.name,
        ),
        'unknown-review': ('unknown', ContentPublicationState.private.name),
        'unknown-publication': (ContentReviewState.unreviewed.name, 'unknown'),
        'rejected': (
          ContentReviewState.rejected.name,
          ContentPublicationState.private.name,
        ),
        'retired': (
          ContentReviewState.unreviewed.name,
          ContentPublicationState.retired.name,
        ),
        'approved-private': (
          ContentReviewState.approved.name,
          ContentPublicationState.private.name,
        ),
        'unreviewed-published': (
          ContentReviewState.unreviewed.name,
          ContentPublicationState.published.name,
        ),
      };
      for (final entry in cases.entries) {
        await _insertWord(
          database,
          id: entry.key,
          spelling: entry.key,
          reviewState: entry.value.$1,
          publicationState: entry.value.$2,
        );
        await _insertSaved(
          database,
          id: 'saved-${entry.key}',
          wordId: entry.key,
        );
      }

      final queue = await reader.compose(
        _filter(includeReasons: const {ReviewQueueReason.saved}),
      );

      expect(queue.map((item) => item.identity.id), ['allowed']);
    },
  );

  test('filters by reason without discarding merged provenance', () async {
    await _insertWord(database, id: 'mixed', spelling: 'mixed');
    await _insertWord(database, id: 'due-only', spelling: 'due');
    await _insertSaved(database, id: 'saved', wordId: 'mixed');
    await _insertSrs(
      database,
      id: 'mixed-due',
      wordId: 'mixed',
      dueAtUtc: _now,
    );
    await _insertSrs(
      database,
      id: 'only-due',
      wordId: 'due-only',
      dueAtUtc: _now,
    );

    final saved = await reader.compose(
      _filter(includeReasons: const {ReviewQueueReason.saved}),
    );
    final none = await reader.compose(_filter(includeReasons: const {}));

    expect(saved.map((item) => item.identity.id), ['mixed']);
    expect(saved.single.reasons, [
      ReviewQueueReason.dueSrs,
      ReviewQueueReason.saved,
    ]);
    expect(none, isEmpty);
  });

  test('compose creates no writes projection or review table', () async {
    await _insertWord(database, id: 'word-1', spelling: 'station');
    await _insertSaved(database, id: 'saved-1', wordId: 'word-1');
    final tablesBefore = await _tableNames(database);
    final countsBefore = await _tableCounts(database);

    final queue = await reader.compose(_filter());

    expect(queue, hasLength(1));
    expect(await _tableNames(database), tablesBefore);
    expect(await _tableCounts(database), countsBefore);
    expect(
      tablesBefore.where((name) => name.contains('review_center')),
      isEmpty,
    );
  });

  test('public load resolves exactly one owner without writes', () async {
    await _insertWord(database, id: 'word-1', spelling: 'station');
    await _insertSaved(database, id: 'saved-1', wordId: 'word-1');
    final useCases = ReviewCenterUseCases(
      reader: reader,
      ownerIdentities: DriftReviewOwnerIdentityReader(database),
      sessionLauncher: _SessionLauncher(),
      nowUtc: () => _now,
      timezoneId: 'Asia/Bangkok',
    );
    final countsBefore = await _tableCounts(database);

    final queue = await useCases.load();

    expect(queue.map((item) => item.identity.id), ['word-1']);
    expect(await _tableCounts(database), countsBefore);
  });

  test('public load fails closed for zero or multiple active owners', () async {
    final capturingReader = _CapturingReader();
    final useCases = ReviewCenterUseCases(
      reader: capturingReader,
      ownerIdentities: DriftReviewOwnerIdentityReader(database),
      sessionLauncher: _SessionLauncher(),
      nowUtc: () => _now,
      timezoneId: 'Asia/Bangkok',
    );
    await (database.update(database.localOwners)
          ..where((row) => row.id.equals('owner-1')))
        .write(const LocalOwnersCompanion(isActive: Value(false)));
    var countsBefore = await _tableCounts(database);

    await expectLater(useCases.load(), throwsStateError);

    expect(await _tableCounts(database), countsBefore);
    await (database.update(database.localOwners)
          ..where((row) => row.id.equals('owner-1')))
        .write(const LocalOwnersCompanion(isActive: Value(true)));
    await _insertOwner(database, 'owner-3');
    countsBefore = await _tableCounts(database);

    await expectLater(useCases.load(), throwsStateError);

    expect(await _tableCounts(database), countsBefore);
    expect(capturingReader.filter, isNull);
  });

  test(
    'use cases inject owner clock timezone and launch exact pinned content',
    () async {
      final capturingReader = _CapturingReader();
      final launcher = _SessionLauncher();
      final useCases = ReviewCenterUseCases(
        reader: capturingReader,
        ownerIdentities: const _OwnerIdentities(),
        sessionLauncher: launcher,
        nowUtc: () => _now,
        timezoneId: 'Asia/Bangkok',
      );
      final item = _item();
      capturingReader.result = [item];

      final loaded = await useCases.load(
        includeReasons: const {ReviewQueueReason.saved},
        limit: 10,
      );
      final first = await useCases.launch(item);
      final second = await useCases.launch(item);

      expect(loaded, [item]);
      expect(capturingReader.filter!.ownerId, 'owner-1');
      expect(capturingReader.filter!.evaluatedAtUtc, _now);
      expect(capturingReader.filter!.timezoneId, 'Asia/Bangkok');
      expect(capturingReader.filter!.limit, 10);
      expect(first.session.id, 'review-session-1');
      expect(first.session.startedAtUtc, _now);
      expect(first.session.questions, hasLength(1));
      expect(first.items, [item.snapshot]);
      expect(second.session.id, 'review-session-2');
      expect(launcher.ownerIds, ['owner-1', 'owner-1']);
      expect(launcher.items.expand((items) => items), [
        item.snapshot,
        item.snapshot,
      ]);
    },
  );
}

final _now = DateTime.utc(2026, 8, 28, 12);

ReviewQueueFilter _filter({
  Set<ReviewQueueReason> includeReasons = ReviewQueueFilter.allReasons,
}) => ReviewQueueFilter(
  ownerId: 'owner-1',
  evaluatedAtUtc: _now,
  timezoneId: 'Asia/Bangkok',
  includeReasons: includeReasons,
);

ReviewQueueItem _item() => ReviewQueueItem(
  snapshot: _reviewSnapshot(
    id: 'word-1',
    spelling: 'station',
    meaning: 'meaning-station',
  ),
  provenance: [
    ReviewReasonProvenance.saved(sourceId: 'saved-1', occurredAtUtc: _now),
  ],
);

ReviewedLexicalContentSnapshot _reviewSnapshot({
  required String id,
  required String spelling,
  required String meaning,
}) => ReviewedLexicalContentSnapshot(
  identity: ContentIdentity(
    type: ContentType.lexicalMetadata,
    id: id,
    revision: 1,
  ),
  categoryId: 'category-1',
  spelling: spelling,
  normalizedSpelling: spelling,
  meaning: meaning,
  normalizedMeaning: meaning,
  partOfSpeech: 'noun',
  cefrLevel: null,
  source: 'manual',
  isGlobal: false,
  coreChecksumSha256: _canonicalWordChecksum(
    spelling: spelling,
    meaning: meaning,
  ),
  provenance: ContentProvenance.userAuthored,
  reviewState: ContentReviewState.unreviewed,
  publicationState: ContentPublicationState.private,
  artifact: null,
);

Future<void> _insertOwner(
  AppDatabase database,
  String id, {
  bool active = true,
}) => database
    .into(database.localOwners)
    .insert(
      LocalOwnersCompanion.insert(
        id: id,
        createdAtUtcMs: 1,
        isActive: Value(active),
      ),
    );

Future<void> _insertCategory(
  AppDatabase database, {
  required String ownerId,
  required String id,
}) => database
    .into(database.vocabularyCategories)
    .insert(
      VocabularyCategoriesCompanion.insert(
        id: id,
        ownerId: ownerId,
        name: id,
        normalizedName: id,
        createdAtUtcMs: 1,
        updatedAtUtcMs: 1,
      ),
    );

Future<void> _insertWord(
  AppDatabase database, {
  String ownerId = 'owner-1',
  String categoryId = 'category-1',
  required String id,
  required String spelling,
  String? meaning,
  int revision = 1,
  bool deleted = false,
  String reviewState = 'unreviewed',
  String publicationState = 'private',
  bool packaged = false,
}) {
  final resolvedMeaning = meaning ?? 'meaning-$spelling';
  return database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: id,
          ownerId: ownerId,
          categoryId: categoryId,
          spelling: spelling,
          normalizedSpelling: spelling,
          meaning: resolvedMeaning,
          normalizedMeaning: resolvedMeaning,
          partOfSpeech: 'noun',
          source: Value(packaged ? 'pack' : 'manual'),
          isGlobal: Value(packaged),
          contentRevision: Value(revision),
          contentChecksumSha256: Value(
            _canonicalWordChecksum(
              categoryId: categoryId,
              spelling: spelling,
              meaning: resolvedMeaning,
              source: packaged ? 'pack' : 'manual',
              isGlobal: packaged,
            ),
          ),
          contentProvenance: Value(
            packaged
                ? ContentProvenance.packaged.name
                : ContentProvenance.userAuthored.name,
          ),
          contentReviewState: Value(
            packaged ? ContentReviewState.approved.name : reviewState,
          ),
          contentPublicationState: Value(
            packaged
                ? ContentPublicationState.published.name
                : publicationState,
          ),
          isDeleted: Value(deleted),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<void> _insertLexicalManifest(
  AppDatabase database, {
  required String wordId,
  required String checksum,
  int byteLength = 1,
}) => database
    .into(database.contentManifests)
    .insert(
      ContentManifestsCompanion.insert(
        id: 'manifest:$wordId:1',
        contentType: ContentType.lexicalMetadata.name,
        contentId: wordId,
        revision: 1,
        checksumSha256: checksum,
        byteLength: byteLength,
        provenance: ContentProvenance.packaged.name,
        sourceUri: 'asset://lexical/$wordId.json',
        reviewState: ContentReviewState.approved.name,
        publicationState: ContentPublicationState.published.name,
        createdAtUtcMs: 1,
        reviewedAtUtcMs: const Value(1),
        publishedAtUtcMs: const Value(1),
      ),
    );

Future<String> _insertLexicalArtifact(
  AppDatabase database, {
  required Map<ContentIdentity, Uint8List> artifacts,
  required String wordId,
  String? englishDefinition,
  List<String> examples = const <String>[],
  List<String> acceptedVariants = const <String>[],
}) async {
  final identity = ContentIdentity(
    type: ContentType.lexicalMetadata,
    id: wordId,
    revision: 1,
  );
  final bytes = _lexicalArtifactBytes(
    wordId: wordId,
    englishDefinition: englishDefinition,
    examples: examples,
    acceptedVariants: acceptedVariants,
  );
  final checksum = sha256.convert(bytes).toString();
  artifacts[identity] = bytes;
  await _insertLexicalManifest(
    database,
    wordId: wordId,
    checksum: checksum,
    byteLength: bytes.length,
  );
  return checksum;
}

Uint8List _lexicalArtifactBytes({
  required String wordId,
  String? englishDefinition,
  List<String> examples = const <String>[],
  List<String> acceptedVariants = const <String>[],
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode(<String, Object?>{
      'schemaVersion': 3,
      'wordId': wordId,
      'contentRevision': 1,
      'englishDefinition': englishDefinition,
      'ipa': null,
      'examples': examples,
      'synonyms': const <String>[],
      'antonyms': const <String>[],
      'acceptedSpellingVariants': acceptedVariants,
      'audio': null,
    }),
  ),
);

LearningUseCases _learningUseCases(AppDatabase database) {
  var nextId = 0;
  return LearningUseCases(
    owners: const _LearningOwners(),
    repository: DriftLearningRepository(database),
    generateId: () => 'adapter-evidence-${++nextId}',
    nowUtc: () => _now,
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'f22-adapters'),
  );
}

Future<QuizSession> _adapterSession(
  AppDatabase database, {
  required String id,
  required List<QuizWord> words,
}) async {
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: id,
          ownerId: 'owner-1',
          activityType: 'reviewCenter',
          state: 'active',
          startedAtUtcMs: _now.millisecondsSinceEpoch,
          appVersion: 'test',
          buildId: 'f22-adapters',
        ),
      );
  return QuizSession(
    id: id,
    startedAtUtc: _now,
    questions: [
      for (final word in words)
        QuizQuestion(word: word, options: const <String>[]),
    ],
  );
}

Future<void> _recordMeaningIncorrect({
  required AppDatabase database,
  required LearningUseCases learning,
  required CurrentActivityEvidenceAdapter evidence,
  required vocabulary_domain.VocabularyWord target,
  required vocabulary_domain.VocabularyWord distractor,
}) async {
  final session = await _adapterSession(
    database,
    id: 'session:meaning',
    words: [
      _quizWordFromVocabulary(target),
      _quizWordFromVocabulary(distractor),
    ],
  );
  final review = const MeaningQuizModeAdapter().createReview(
    session: session,
    direction: SessionDirection.forward,
    lexicalWords: [target, distractor],
    learning: learning,
    evidence: evidence,
  );
  try {
    await review.answer(
      option: review.currentQuestion.options.singleWhere(
        (option) => option != review.currentQuestion.correctOption,
      ),
      responseTimeMs: 100,
    );
  } finally {
    review.dispose();
  }
}

Future<void> _recordDefinitionIncorrect({
  required AppDatabase database,
  required LearningUseCases learning,
  required CurrentActivityEvidenceAdapter evidence,
  required vocabulary_domain.VocabularyWord target,
  required vocabulary_domain.VocabularyWord distractor,
}) async {
  final session = await _adapterSession(
    database,
    id: 'session:definition',
    words: [
      _quizWordFromVocabulary(target),
      _quizWordFromVocabulary(distractor),
    ],
  );
  final review = const DefinitionQuizModeAdapter().createReview(
    session: session,
    lexicalWords: [target, distractor],
    learning: learning,
    evidence: evidence,
    hintUsage: () => const HintUsageSnapshot.unavailable(),
  );
  try {
    final question = review.currentItem.question!;
    await review.answer(
      option: question.options.singleWhere(
        (option) => option != question.correctOption,
      ),
      responseTimeMs: 100,
    );
  } finally {
    review.dispose();
  }
}

Future<void> _recordClozeIncorrect({
  required AppDatabase database,
  required LearningUseCases learning,
  required CurrentActivityEvidenceAdapter evidence,
  required vocabulary_domain.VocabularyWord target,
  required vocabulary_domain.VocabularyWord distractor,
}) async {
  final session = await _adapterSession(
    database,
    id: 'session:cloze',
    words: [
      _quizWordFromVocabulary(target),
      _quizWordFromVocabulary(distractor),
    ],
  );
  final review = const ClozeModeAdapter().createReview(
    session: session,
    lexicalWords: [target, distractor],
    learning: learning,
    evidence: evidence,
    hintUsage: () => const HintUsageSnapshot.unavailable(),
  );
  try {
    final question = review.currentItem.question!;
    await review.answerSelected(
      option: question.options.singleWhere(
        (option) => option != question.correctAnswer,
      ),
      responseTimeMs: 100,
    );
  } finally {
    review.dispose();
  }
}

Future<void> _recordTypedRecallIncorrect({
  required AppDatabase database,
  required CurrentActivityEvidenceAdapter evidence,
  required QuizWord word,
}) async {
  final session = await _adapterSession(
    database,
    id: 'session:${word.id}',
    words: [word],
  );
  final adapter = const TypedRecallModeAdapter();
  final captured = adapter.capture(
    evidence: evidence,
    sessionId: session.id,
    prompt: adapter.pinQuizPrompt(word),
    response: 'definitely-wrong',
    responseTimeMs: 100,
    attemptNumber: 1,
    support: const TypedRecallSupport.unassisted(),
  );
  await captured.pending.record();
}

Future<void> _recordMatchingIncorrect({
  required AppDatabase database,
  required LearningUseCases learning,
  required CurrentActivityEvidenceAdapter evidence,
  required QuizWord target,
  required QuizWord distractor,
}) async {
  final session = await _adapterSession(
    database,
    id: 'session:matching',
    words: [target, distractor],
  );
  final review = const MatchingModeAdapter(maximumPairs: 2).createReview(
    session: session,
    learning: learning,
    evidence: evidence,
    hintUsage: () => const HintUsageSnapshot.unavailable(),
  );
  try {
    await review.selectWord(target.id, responseTimeMs: 100);
    await review.selectMeaning(distractor.id, responseTimeMs: 100);
  } finally {
    review.dispose();
  }
}

vocabulary_domain.VocabularyWord _packagedWord({
  required String id,
  required String spelling,
  required String artifactChecksum,
  String? definition,
  String? example,
}) => vocabulary_domain.VocabularyWord(
  id: id,
  ownerId: 'owner-1',
  categoryId: 'category-1',
  spelling: spelling,
  normalizedSpelling: spelling,
  meaning: 'meaning-$spelling',
  normalizedMeaning: 'meaning-$spelling',
  partOfSpeech: 'noun',
  source: 'pack',
  isGlobal: true,
  localRevision: 1,
  isDeleted: false,
  createdAtUtc: _now,
  updatedAtUtc: _now,
  contentRevision: 1,
  contentChecksumSha256: _canonicalWordChecksum(
    spelling: spelling,
    source: 'pack',
    isGlobal: true,
  ),
  contentProvenance: ContentProvenance.packaged,
  contentReviewState: ContentReviewState.approved,
  contentPublicationState: ContentPublicationState.published,
  richMetadata: vocabulary_domain.RichLexicalMetadata(
    englishDefinition: definition,
    verifiedContentRevision: 1,
    verifiedArtifactChecksumSha256: artifactChecksum,
    examples: [?example],
  ),
);

QuizWord _quizWordFromVocabulary(vocabulary_domain.VocabularyWord word) =>
    _quizWord(id: word.id, spelling: word.spelling);

QuizWord _quizWord({
  required String id,
  required String spelling,
  List<String> acceptedVariants = const <String>[],
  String? acceptedVariantsChecksum,
}) => QuizWord(
  id: id,
  categoryId: 'category-1',
  spelling: spelling,
  meaning: 'meaning-$spelling',
  partOfSpeech: 'noun',
  normalizedSpelling: spelling,
  normalizedMeaning: 'meaning-$spelling',
  contentRevision: 1,
  contentChecksumSha256: _canonicalWordChecksum(
    spelling: spelling,
    source: 'pack',
    isGlobal: true,
  ),
  acceptedSpellingVariants: acceptedVariants,
  acceptedSpellingVariantsRevision: acceptedVariants.isEmpty ? null : 1,
  acceptedSpellingVariantsChecksumSha256: acceptedVariantsChecksum,
);

Future<void> _insertSaved(
  AppDatabase database, {
  String ownerId = 'owner-1',
  required String id,
  required String wordId,
  int revision = 1,
  bool deleted = false,
  String contentType = 'lexicalMetadata',
}) => database
    .into(database.savedLearningItems)
    .insert(
      SavedLearningItemsCompanion.insert(
        id: id,
        ownerId: ownerId,
        contentType: contentType,
        contentId: wordId,
        contentRevision: revision,
        savedAtUtcMs: _now
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
        updatedAtUtcMs: _now.millisecondsSinceEpoch,
        isDeleted: Value(deleted),
      ),
    );

Future<void> _insertReport(
  AppDatabase database, {
  String ownerId = 'owner-1',
  required String id,
  required String wordId,
  int revision = 1,
  String reasonCode = 'answer',
}) => database
    .into(database.contentQualityReports)
    .insert(
      ContentQualityReportsCompanion.insert(
        id: id,
        ownerId: ownerId,
        contentType: ContentType.lexicalMetadata.name,
        contentId: wordId,
        contentRevision: revision,
        reasonCode: reasonCode,
        submittedAtUtcMs: _now
            .subtract(const Duration(hours: 12))
            .millisecondsSinceEpoch,
      ),
    );

Future<void> _insertSrs(
  AppDatabase database, {
  String ownerId = 'owner-1',
  required String id,
  required String wordId,
  required DateTime dueAtUtc,
}) => database
    .into(database.srsStates)
    .insert(
      SrsStatesCompanion.insert(
        id: id,
        ownerId: ownerId,
        wordId: wordId,
        dueAtUtcMs: dueAtUtc.millisecondsSinceEpoch,
        algorithmVersion: 1,
      ),
    );

Future<void> _insertAttempt(
  AppDatabase database, {
  String ownerId = 'owner-1',
  required String id,
  required String wordId,
  String? evidenceContextJson,
  int contentRevision = 1,
  String? contentRevisionText,
  String promptMode = 'matchingPair',
  bool includeSourceEvent = true,
  void Function(Map<String, dynamic> json)? mutateSourceEvent,
}) async {
  final sessionId = 'session-$id';
  final occurredAtUtc = _now.subtract(const Duration(hours: 2));
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: sessionId,
          ownerId: ownerId,
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: _now
              .subtract(const Duration(hours: 3))
              .millisecondsSinceEpoch,
          appVersion: 'test',
          buildId: 'test',
        ),
      );
  final context = EvidenceContext.legacyCompatibility(
    evidenceClass: EvidenceClass.independentRecall,
    skillId: 'typed-recall',
    hintLevel: 0,
    contentRevision:
        contentRevisionText ??
        await _evidenceRevision(
          database,
          wordId: wordId,
          revision: contentRevision,
          promptMode: promptMode,
        ),
    engagementAllowed: false,
  );
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: id,
          ownerId: ownerId,
          sessionId: sessionId,
          wordId: wordId,
          promptMode: promptMode,
          isCorrect: false,
          attemptNumber: 1,
          occurredAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          evidenceClass: Value(EvidenceClass.independentRecall.name),
          evidenceContextJson: Value(
            evidenceContextJson ?? jsonEncode(context.toJson()),
          ),
        ),
      );
  if (!includeSourceEvent) return;
  var source = const EventV1ToV2Adapter(appVersion: 'test', buildId: 'test')
      .adaptFromCommand(
        sourceEvidenceId: id,
        ownerId: ownerId,
        sessionId: sessionId,
        wordId: wordId,
        promptMode: promptMode,
        isCorrect: false,
        attemptNumber: 1,
        occurredAtUtc: occurredAtUtc,
        evidenceContext: context,
        learningEventContext: LearningEventContext.noResearch(context),
      );
  if (mutateSourceEvent != null) {
    final sourceJson = (jsonDecode(jsonEncode(source.toJson())) as Map)
        .cast<String, dynamic>();
    mutateSourceEvent(sourceJson);
    source = EventEnvelopeV2.fromJson(sourceJson);
  }
  await _insertSourceEvent(database, source);
}

Future<String> _evidenceRevision(
  AppDatabase database, {
  required String wordId,
  required int revision,
  required String promptMode,
}) async {
  final word = await (database.select(
    database.vocabularyWords,
  )..where((row) => row.id.equals(wordId))).getSingle();
  final manifestRows = await (database.select(
    database.contentManifests,
  )..where((row) => row.contentId.equals(wordId))).get();
  final exactManifests = manifestRows
      .where(
        (row) =>
            row.contentType == ContentType.lexicalMetadata.name &&
            row.revision == revision,
      )
      .toList(growable: false);
  final manifest = exactManifests.length == 1 ? exactManifests.single : null;
  final candidates = LexicalPromptArtifactResolver.resolveReaderCandidates(
    promptMode: promptMode,
    wordId: wordId,
    coreRevision: revision,
    coreChecksumSha256: word.contentChecksumSha256,
    verifiedArtifactLoaded: false,
    usesAcceptedVariants: false,
    verifiedArtifactRevision: manifest?.revision,
    verifiedArtifactChecksumSha256: manifest?.checksumSha256,
  );
  if (candidates.length != 1) {
    throw StateError(
      'test evidence requires one exact prompt artifact identity',
    );
  }
  return candidates.single.evidenceContentRevision;
}

String _lexicalRevision(
  String wordId,
  int revision,
  String checksum, {
  String artifact = 'lexical-meaning',
}) => '$artifact:$wordId@$revision:$checksum';

String _promptRevision({
  required String promptMode,
  required String wordId,
  required String coreChecksumSha256,
  required String artifactChecksumSha256,
}) => LexicalPromptArtifactResolver.resolveForAdapter(
  promptMode: promptMode,
  wordId: wordId,
  coreRevision: 1,
  coreChecksumSha256: coreChecksumSha256,
  verifiedArtifactRevision: 1,
  verifiedArtifactChecksumSha256: artifactChecksumSha256,
)!.evidenceContentRevision;

String _canonicalWordChecksum({
  String categoryId = 'category-1',
  required String spelling,
  String? meaning,
  String source = 'manual',
  bool isGlobal = false,
}) => ContentQualityPolicy.vocabularyChecksumSha256(
  categoryId: categoryId,
  spelling: spelling,
  normalizedSpelling: spelling,
  meaning: meaning ?? 'meaning-$spelling',
  normalizedMeaning: meaning ?? 'meaning-$spelling',
  partOfSpeech: 'noun',
  cefrLevel: null,
  source: source,
  isGlobal: isGlobal,
);

ReviewCenterUseCases _launchUseCases(
  AppDatabase database, {
  Future<void> Function()? beforeStart,
  String Function()? generateId,
  DateTime Function()? learningNowUtc,
  DateTime Function()? reviewNowUtc,
}) {
  var nextId = 0;
  final learning = LearningUseCases(
    owners: const _LearningOwners(),
    repository: DriftLearningRepository(database),
    generateId: generateId ?? () => 'review-${++nextId}',
    nowUtc: learningNowUtc ?? () => _now,
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'f22-test'),
  );
  final launcher = LearningUseCasesReviewSessionLauncher(learning);
  return ReviewCenterUseCases(
    reader: DriftReviewCenterReader(database),
    ownerIdentities: DriftReviewOwnerIdentityReader(database),
    sessionLauncher: beforeStart == null
        ? launcher
        : _BeforeStartSessionLauncher(launcher, beforeStart),
    nowUtc: reviewNowUtc ?? () => _now,
    timezoneId: 'Asia/Bangkok',
  );
}

final class _BeforeStartSessionLauncher implements ReviewSessionLauncher {
  const _BeforeStartSessionLauncher(this.delegate, this.beforeStart);

  final ReviewSessionLauncher delegate;
  final Future<void> Function() beforeStart;

  @override
  Object get authorityIdentity => delegate.authorityIdentity;

  @override
  Future<PinnedReviewSessionLaunch> start({
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> items,
  }) async {
    await beforeStart();
    return delegate.start(ownerId: ownerId, items: items);
  }

  @override
  Future<void> abandon({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) => delegate.abandon(
    ownerId: ownerId,
    sessionId: sessionId,
    abandonedAtUtc: abandonedAtUtc,
  );
}

Future<void> _insertSourceEvent(AppDatabase database, EventEnvelopeV2 event) =>
    database
        .into(database.eventsV2)
        .insert(
          EventsV2Companion.insert(
            eventId: event.eventId,
            eventType: event.eventType,
            eventVersion: event.eventVersion,
            occurredAtUtc: event.occurredAtUtc,
            recordedAtUtc: event.recordedAtUtc,
            actorIdentity: event.actorIdentity,
            ownerId: event.ownerIdentity,
            tenantContextJson: Value(
              event.tenantContext == null
                  ? null
                  : jsonEncode(event.tenantContext!.toJson()),
            ),
            aggregateType: event.aggregateType,
            aggregateId: event.aggregateId,
            correlationId: Value(event.correlationId),
            causationId: Value(event.causationId),
            idempotencyKey: event.idempotencyKey,
            consentContextJson: jsonEncode(event.consentContext.toJson()),
            experimentContextJson: Value(
              event.experimentContext == null
                  ? null
                  : jsonEncode(event.experimentContext!.toJson()),
            ),
            contentRevision: Value(event.contentRevision),
            policyVersion: Value(event.policyVersion),
            appVersion: event.appVersion,
            buildId: event.buildId,
            providerProvenanceJson: Value(
              event.providerProvenance == null
                  ? null
                  : jsonEncode(event.providerProvenance!.toJson()),
            ),
            privacyClassification: event.privacyClassification.name,
            payloadJson: jsonEncode(event.payload),
          ),
        );

Future<List<String>> _tableNames(AppDatabase database) async {
  final rows = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
      )
      .get();
  return rows.map((row) => row.read<String>('name')).toList(growable: false);
}

Future<Map<String, int>> _tableCounts(AppDatabase database) async {
  final result = <String, int>{};
  for (final table in database.allTables) {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS row_count FROM ${table.actualTableName}',
          readsFrom: {table},
        )
        .getSingle();
    result[table.actualTableName] = row.read<int>('row_count');
  }
  return result;
}

final class _CapturingReader implements ReviewCenterReader {
  ReviewQueueFilter? filter;
  List<ReviewQueueItem> result = const [];

  @override
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter) async {
    this.filter = filter;
    return result;
  }
}

final class _OwnerIdentities implements ReviewOwnerIdentityReader {
  const _OwnerIdentities();

  @override
  Future<String> requireSingleActiveOwnerId() async => 'owner-1';
}

final class _LearningOwners implements LocalOwnerRepository {
  const _LearningOwners();

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(id: 'owner-1', createdAtUtc: _now);

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

final class _SessionLauncher implements ReviewSessionLauncher {
  final Object _authorityIdentity = Object();
  final List<String> ownerIds = [];
  final List<List<ReviewedLexicalContentSnapshot>> items = [];
  var _nextId = 0;

  @override
  Object get authorityIdentity => _authorityIdentity;

  @override
  Future<PinnedReviewSessionLaunch> start({
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> items,
  }) async {
    ownerIds.add(ownerId);
    this.items.add(List<ReviewedLexicalContentSnapshot>.of(items));
    return PinnedReviewSessionLaunch(
      session: QuizSession(
        id: 'review-session-${++_nextId}',
        ownerId: ownerId,
        startedAtUtc: _now,
        questions: [
          for (final snapshot in items)
            QuizQuestion(
              word: QuizWord(
                id: snapshot.identity.id,
                categoryId: snapshot.categoryId,
                spelling: snapshot.spelling,
                meaning: snapshot.meaning,
                partOfSpeech: snapshot.partOfSpeech,
                cefrLevel: snapshot.cefrLevel,
                normalizedSpelling: snapshot.normalizedSpelling,
                normalizedMeaning: snapshot.normalizedMeaning,
                contentRevision: snapshot.identity.revision,
                contentChecksumSha256: snapshot.coreChecksumSha256,
              ),
              options: [snapshot.meaning],
            ),
        ],
      ),
      content: items,
    );
  }

  @override
  Future<void> abandon({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) async {}
}
