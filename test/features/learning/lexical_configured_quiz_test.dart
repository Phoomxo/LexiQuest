import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart'
    show LearningPackException, LearningPackFailureCode;
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';
import '../../support/authored_lexical_pack.dart';

void main() {
  late Directory directory;
  late ConfiguredQuizHarness h;
  late LearningPackUseCases packs;
  late LearningUseCases learning;
  late StoredLearningPack installed;
  late DriftLearningPackRepository packReader;
  late DriftLearningRepository repository;
  var sequence = 0;
  OrdinaryAnswerPreparation? hook;

  void wire() {
    packReader = DriftLearningPackRepository(
      database: h.database,
      ownerWrites: h.ownerWrites,
    );
    packs = LearningPackUseCases(
      repository: packReader,
      nowUtc: () => h.now,
      generateId: () => 'synthetic-lexical-pack-${++sequence}',
    );
    repository = DriftLearningRepository(
      h.database,
      ownerWrites: h.ownerWrites,
      lexicalContent: packReader,
    );
    learning = LearningUseCases(
      owners: h.owners,
      repository: repository,
      generateId: () => 'synthetic-lexical-learning-${++sequence}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(
        version: 'synthetic-v1',
        buildId: 'synthetic-build',
      ),
      beforeOrdinaryAnswer: hook,
    );
  }

  Future<void> reopen() async {
    await packs.dispose();
    h = await h.reopen();
    wire();
  }

  Future<ConfiguredQuizLaunch> prepare(
    LexicalQuizInput input, {
    int limit = 2,
  }) => learning.prepareLexicalQuiz(
    expectedOwnerId: configuredOwnerId,
    packVersionId: installed.id,
    entryCodes: const ['cat', 'dog'],
    input: input,
    limit: limit,
    stillCurrent: () => true,
  );

  Future<ConfiguredQuizState> resume(String id) =>
      learning.resumeQuiz(sessionId: id, expectedOwnerId: configuredOwnerId);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'synthetic-lexical-quiz-',
    );
    h = await ConfiguredQuizHarness.open(
      file: File('${directory.path}/learning.sqlite'),
    );
    sequence = 0;
    hook = null;
    wire();
    final owner = await packs.captureOwner(stillCurrent: () => true);
    installed = await packs.importPack(
      packs.prepareImport(scope: owner!, pack: authoredLexicalPack()),
    );
  });
  tearDown(() async {
    await packs.dispose();
    await h.close();
    await directory.delete(recursive: true);
  });

  test(
    'negative control: genuine authored pack does not create learning evidence on inspection',
    () async {
      final scope = await packs.captureOwner(stillCurrent: () => true);
      final before = await h.snapshot();
      final detail = await packs.detail(scope!, installed.id);
      expect(detail.bindings, hasLength(2));
      expect(
        detail.content!.entries.first.definitionQuestion!.options,
        hasLength(2),
      );
      expect(detail.bindings.every((binding) => binding.isCurrent), isTrue);
      expect(await h.snapshot(), before);
      expect(await h.count('learning_sessions'), 0);
      expect(await h.count('answer_attempts'), 0);
      expect((await h.researchCounts()).values, everyElement(0));
    },
  );

  test(
    'configuration snapshots caller selection before await and pins optional settings',
    () async {
      final codes = ['dog', 'cat'];
      const settings = LexicalQuizSettings(
        advisoryMinutes: 180,
        manualAudio: true,
        accessibleInput: true,
        reduceMotion: true,
      );
      final pending = learning.prepareLexicalQuiz(
        expectedOwnerId: configuredOwnerId,
        packVersionId: installed.id,
        entryCodes: codes,
        input: LexicalQuizInput.definitionTyped,
        limit: 2,
        settings: settings,
        stillCurrent: () => true,
      );
      codes
        ..clear()
        ..add('missing');
      final launch = await pending;
      final state = await learning.startConfiguredQuiz(launch);
      expect(state.plan.questions.map((question) => question.correctAnswer), [
        'dog',
        'cat',
      ]);
      expect(
        state.plan.configuration.lexical!.settings.toJson(),
        settings.toJson(),
      );
      expect(
        AcceptedQuizPlan.parse(
          id: state.plan.id,
          json: state.plan.stableSerialization,
        ).stableSerialization,
        state.plan.stableSerialization,
      );
      expect(
        () => state.plan.configuration.lexical!.entryCodes.add('new'),
        throwsUnsupportedError,
      );
      for (final minutes in [0, 181]) {
        await expectLater(
          learning.prepareLexicalQuiz(
            expectedOwnerId: configuredOwnerId,
            packVersionId: installed.id,
            entryCodes: const ['cat'],
            input: LexicalQuizInput.definitionChoice,
            limit: 1,
            settings: LexicalQuizSettings(advisoryMinutes: minutes),
            stillCurrent: () => true,
          ),
          throwsFormatException,
        );
      }
      expect(const LexicalQuizSettings().manualAudio, isFalse);
      expect(const LexicalQuizSettings().advisoryMinutes, isNull);
    },
  );

  test('typed draft lost ACK repeats once without stale overwrite', () async {
    var state = await learning.startConfiguredQuiz(
      await prepare(LexicalQuizInput.definitionTyped),
    );
    final initialRevision = state.checkpointRevision;
    state = await learning.saveQuizTypedDraft(
      sessionId: state.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: initialRevision,
      text: 'synthetic-private-draft',
    );
    final before = await h.snapshot();
    final same = await learning.saveQuizTypedDraft(
      sessionId: state.sessionId,
      expectedOwnerId: configuredOwnerId,
      expectedRevision: initialRevision,
      text: 'synthetic-private-draft',
    );
    expect(same.checkpointRevision, state.checkpointRevision);
    expect(await h.snapshot(), before);
    await expectLater(
      learning.saveQuizTypedDraft(
        sessionId: state.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: initialRevision,
        text: 'changed',
      ),
      throwsStateError,
    );
    expect(await h.snapshot(), before);
  });

  test('copied plan cannot mint a lexical launch', () async {
    final launch = await prepare(LexicalQuizInput.definitionChoice);
    final plan = launch.preparedPlan!;
    final copy = AcceptedQuizPlan.parse(
      id: plan.id,
      json: plan.stableSerialization,
    );
    final before = await h.snapshot();
    await expectLater(
      learning.startConfiguredQuiz(
        ConfiguredQuizLaunch(
          session: launch.session,
          configuration: launch.configuration,
          preparedPlan: copy,
        ),
      ),
      throwsStateError,
    );
    expect(await h.snapshot(), before);
    expect((await learning.startConfiguredQuiz(launch)).plan.id, plan.id);
  });

  test(
    'actual owner ABA retires the original prepared lexical launch',
    () async {
      final launch = await prepare(LexicalQuizInput.definitionChoice);
      final upgrades = DriftOwnerUpgradeRepository(
        h.database,
        nowUtc: () => h.now,
        generateConflictId: () =>
            'synthetic-lexical-aba-conflict-${++sequence}',
        generateOwnerId: () => 'synthetic-lexical-aba-guest-${++sequence}',
      );
      final guest = await upgrades.createLocalGuestAfterLogout();
      await upgrades.rollbackLocalGuestLogout(
        previousOwnerId: configuredOwnerId,
        guestOwnerId: guest.targetOwnerId,
      );
      await Future<void>.delayed(Duration.zero);
      final before = await h.snapshot();
      await expectLater(learning.startConfiguredQuiz(launch), throwsStateError);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'captured current predicate retires permanently after rejection',
    () async {
      var current = true;
      final launch = await learning.prepareLexicalQuiz(
        expectedOwnerId: configuredOwnerId,
        packVersionId: installed.id,
        entryCodes: const ['cat'],
        input: LexicalQuizInput.definitionChoice,
        limit: 1,
        stillCurrent: () => current,
      );
      current = false;
      await expectLater(learning.startConfiguredQuiz(launch), throwsStateError);
      current = true;
      await expectLater(learning.startConfiguredQuiz(launch), throwsStateError);
      expect(await h.count('learning_sessions'), 0);
    },
  );

  test(
    'actual deletion fence rejects resume without learning mutations',
    () async {
      final state = await learning.startConfiguredQuiz(
        await prepare(LexicalQuizInput.definitionTyped),
      );
      await h.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'synthetic-lexical-deletion',
      );
      final before = await h.snapshot();
      await expectLater(
        resume(state.sessionId),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.unavailable,
          ),
        ),
      );
      expect(await h.snapshot(), before);
    },
  );

  test(
    'actual owner merge cannot resume even an unanswered lexical plan under the new owner',
    () async {
      final state = await learning.startConfiguredQuiz(
        await prepare(LexicalQuizInput.definitionTyped),
      );
      final result =
          await DriftOwnerUpgradeRepository(
            h.database,
            nowUtc: () => h.now,
            generateConflictId: () => 'synthetic-lexical-merge-${++sequence}',
            generateOwnerId: () =>
                'synthetic-lexical-merge-owner-${++sequence}',
          ).upgrade(
            activeOwnerId: configuredOwnerId,
            firebaseUid: 'synthetic-configured-uid-b',
          );
      expect(result.targetOwnerId, configuredOtherOwnerId);
      final before = await h.snapshot();
      await expectLater(
        learning.resumeQuiz(
          sessionId: state.sessionId,
          expectedOwnerId: configuredOtherOwnerId,
        ),
        throwsA(
          isA<ConfiguredQuizUnavailable>().having(
            (error) => error.reason,
            'reason',
            ConfiguredQuizUnavailableReason.ownerChanged,
          ),
        ),
      );
      expect(await h.snapshot(), before);
    },
  );

  test(
    'raw package eviction retains genuine definition content and accepted identity',
    () async {
      final launch = await prepare(LexicalQuizInput.definitionChoice);
      final scope = await packs.captureOwner(stillCurrent: () => true);
      final stored = await packs.changeCache(
        packs.prepareCacheChange(
          scope: scope!,
          stored: installed,
          pinned: false,
          remove: true,
        ),
      );
      expect(stored.cacheState, PackCacheState.notCached);
      final state = await learning.startConfiguredQuiz(launch);
      expect(state.plan.id, launch.preparedPlan!.id);
      expect(state.plan.questions.first.prompt, 'A small animal that meows.');
    },
  );

  for (final code in ['cat', 'dog']) {
    test(
      'changed actual $code target or distractor rejects launch atomically',
      () async {
        final launch = await prepare(
          LexicalQuizInput.definitionChoice,
          limit: 1,
        );
        final scope = await packs.captureOwner(stillCurrent: () => true);
        final detail = await packs.detail(scope!, installed.id);
        final wordId = detail.bindings
            .singleWhere((binding) => binding.entry.code == code)
            .wordId;
        await h.database.customStatement(
          'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?',
          [wordId],
        );
        final before = await h.snapshot();
        await expectLater(
          learning.startConfiguredQuiz(launch),
          throwsA(
            isA<ConfiguredQuizUnavailable>().having(
              (error) => error.reason,
              'reason',
              ConfiguredQuizUnavailableReason.contentChanged,
            ),
          ),
        );
        expect(await h.snapshot(), before);
      },
    );
  }

  test(
    'corrupt retained lexical entry rejects pending replay and inserts no attempt',
    () async {
      var state = await learning.startConfiguredQuiz(
        await prepare(LexicalQuizInput.definitionChoice),
      );
      state = await learning.prepareQuizAnswer(
        sessionId: state.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: state.checkpointRevision,
        selectedOptionOrdinal: 0,
      );
      await h.database.customStatement(
        "UPDATE lexical_content_snapshots SET lexical_json = '{}' WHERE owner_id = ? AND entry_code = 'dog'",
        [configuredOwnerId],
      );
      final before = await h.snapshot();
      await expectLater(
        learning.commitQuizAnswer(
          sessionId: state.sessionId,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: state.checkpointRevision,
        ),
        throwsA(
          isA<ConfiguredQuizUnavailable>().having(
            (error) => error.reason,
            'reason',
            ConfiguredQuizUnavailableReason.contentChanged,
          ),
        ),
      );
      expect(await h.snapshot(), before);
      expect(await h.count('answer_attempts'), 0);
    },
  );

  test(
    'missing owner pack never falls back to ordinary meaning or caller dictionary',
    () async {
      final before = await h.snapshot();
      await expectLater(
        learning.prepareLexicalQuiz(
          expectedOwnerId: configuredOwnerId,
          packVersionId: 'synthetic-missing-pack',
          entryCodes: const ['cat'],
          input: LexicalQuizInput.definitionChoice,
          limit: 1,
          stillCurrent: () => true,
        ),
        throwsA(
          isA<PackStorageException>().having(
            (error) => error.code,
            'code',
            PackStorageFailureCode.notFound,
          ),
        ),
      );
      expect(await h.snapshot(), before);
    },
  );

  for (final missing in [true, false]) {
    test(
      missing
          ? 'missing authored definition fails closed'
          : 'ambiguous duplicate visible spellings fail closed',
      () async {
        if (!missing) {
          final before = await h.snapshot();
          expect(
            () =>
                authoredLexicalPack(version: '2.0.0', duplicateSpelling: true),
            throwsA(
              isA<LearningPackException>().having(
                (error) => error.code,
                'code',
                LearningPackFailureCode.duplicateIdentity,
              ),
            ),
          );
          expect(await h.snapshot(), before);
          return;
        }
        final scope = await packs.captureOwner(stillCurrent: () => true);
        final extra = await packs.importPack(
          packs.prepareImport(
            scope: scope!,
            pack: authoredLexicalPack(
              version: '2.0.0',
              includeDefinitions: !missing,
              duplicateSpelling: !missing,
            ),
          ),
        );
        final before = await h.snapshot();
        await expectLater(
          learning.prepareLexicalQuiz(
            expectedOwnerId: configuredOwnerId,
            packVersionId: extra.id,
            entryCodes: const ['cat'],
            input: missing
                ? LexicalQuizInput.definitionTyped
                : LexicalQuizInput.definitionChoice,
            limit: 1,
            stillCurrent: () => true,
          ),
          throwsFormatException,
        );
        expect(await h.snapshot(), before);
      },
    );
  }

  for (final language in ['en', 'fr']) {
    test(
      'definition-only $language source uses the actual English pack boundary',
      () async {
        final scope = await packs.captureOwner(stillCurrent: () => true);
        final extra = await packs.importPack(
          packs.prepareImport(
            scope: scope!,
            pack: authoredLexicalPack(
              version: '2.0.0',
              language: language,
              includeChoiceQuestions: false,
            ),
          ),
        );
        final before = await h.snapshot();
        final prepared = learning.prepareLexicalQuiz(
          expectedOwnerId: configuredOwnerId,
          packVersionId: extra.id,
          entryCodes: const ['cat'],
          input: LexicalQuizInput.definitionTyped,
          limit: 1,
          stillCurrent: () => true,
        );
        if (language == 'en') {
          final launch = await prepared;
          expect(
            launch.preparedPlan!.questions.single.prompt,
            'A small animal that meows.',
          );
        } else {
          await expectLater(
            prepared,
            throwsA(
              isA<ConfiguredQuizUnavailable>().having(
                (error) => error.reason,
                'reason',
                ConfiguredQuizUnavailableReason.contentChanged,
              ),
            ),
          );
        }
        expect(await h.snapshot(), before);
      },
    );
  }

  test(
    'post-abandon SQL owner change rolls the lexical checkpoint and owner back together',
    () async {
      final state = await learning.startConfiguredQuiz(
        await prepare(LexicalQuizInput.definitionTyped),
      );
      final before = await h.snapshot();
      final interference = _AfterLexicalAbandon(
        (executor) => executor.runCustom(
          'UPDATE local_owners SET is_active = (id = ?)',
          [configuredOtherOwnerId],
        ),
      );
      await expectLater(
        h.database.runWithInterceptor(
          () => learning.abandonQuiz(
            sessionId: state.sessionId,
            expectedOwnerId: configuredOwnerId,
            expectedRevision: state.checkpointRevision,
          ),
          interceptor: interference,
        ),
        throwsStateError,
      );
      expect(interference.fired, isTrue);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'ordinary answer hook runs before immutable timestamp and never reruns exact pending retry',
    () async {
      var calls = 0;
      hook =
          ({
            required String expectedOwnerId,
            required String sessionId,
            required bool Function() stillCurrent,
          }) async {
            expect(expectedOwnerId, configuredOwnerId);
            expect(stillCurrent(), isTrue);
            expect(await h.count('answer_attempts'), 0);
            calls++;
            h.now = h.now.add(const Duration(seconds: 7));
          };
      await packs.dispose();
      wire();
      var state = await learning.startConfiguredQuiz(
        await prepare(LexicalQuizInput.definitionTyped),
      );
      final revision = state.checkpointRevision;
      state = await learning.prepareQuizAnswer(
        sessionId: state.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: revision,
        typedResponse: 'cat',
        responseTimeMs: 2222,
      );
      expect(
        state.checkpoint.answer!.occurredAtUtcMs,
        h.now.millisecondsSinceEpoch,
      );
      final original = state.checkpoint.answer!.toJson();
      h.now = h.now.add(const Duration(seconds: 99));
      final retry = await learning.prepareQuizAnswer(
        sessionId: state.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: revision,
        typedResponse: 'cat',
        responseTimeMs: 9999,
      );
      expect(retry.checkpoint.answer!.toJson(), original);
      expect(calls, 1);
    },
  );

  test(
    'failed ordinary hook preserves original checkpoint and emits no learning mutation',
    () async {
      hook =
          ({
            required String expectedOwnerId,
            required String sessionId,
            required bool Function() stillCurrent,
          }) async {
            throw StateError('Synthetic optional hook did not acknowledge');
          };
      await packs.dispose();
      wire();
      final state = await learning.startConfiguredQuiz(
        await prepare(LexicalQuizInput.definitionTyped),
      );
      final before = await h.snapshot();
      await expectLater(
        learning.prepareQuizAnswer(
          sessionId: state.sessionId,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: state.checkpointRevision,
          typedResponse: 'cat',
        ),
        throwsStateError,
      );
      expect(await h.snapshot(), before);
    },
  );

  test(
    'new direct answer waits for hook while supplied retry retains original identity and time',
    () async {
      var calls = 0;
      hook =
          ({
            required String expectedOwnerId,
            required String sessionId,
            required bool Function() stillCurrent,
          }) async {
            calls++;
            h.now = h.now.add(const Duration(seconds: 9));
          };
      await packs.dispose();
      wire();
      final session = await learning.startShadowing(limit: 1);
      final word = session.questions.single.word;
      await learning.recordAnswer(
        sessionId: session.id,
        wordId: word.id,
        promptMode: 'shadowing',
        isCorrect: true,
        responseTimeMs: 1000,
        attemptNumber: 1,
      );
      final row = await h.database
          .select(h.database.answerAttempts)
          .getSingle();
      expect(row.occurredAtUtcMs, h.now.millisecondsSinceEpoch);
      h.now = h.now.add(const Duration(hours: 1));
      final retry = await learning.recordAnswer(
        sessionId: session.id,
        wordId: word.id,
        promptMode: 'shadowing',
        isCorrect: true,
        responseTimeMs: 1000,
        attemptNumber: 1,
        attemptId: row.id,
        occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
          row.occurredAtUtcMs,
          isUtc: true,
        ),
      );
      expect(retry.inserted, isFalse);
      expect(calls, 1);
      expect(
        (await h.database.select(h.database.answerAttempts).getSingle())
            .occurredAtUtcMs,
        row.occurredAtUtcMs,
      );
    },
  );

  for (final input in LexicalQuizInput.values) {
    test(
      '${input.name} uses approved policy for every projection and cannot use legacy inferred fallback',
      () async {
        final launch = await prepare(input);
        final question = launch.preparedPlan!.questions.first;
        for (final level in [0, 1, 2]) {
          final context = EvidenceContext.forNewEvidence(
            evidenceClass: level == 0
                ? question.unassistedEvidenceClass
                : EvidenceClass.guidedPractice,
            skillId: question.skillId,
            hintLevel: level,
            contentRevision: question.evidenceContentRevision,
            rolloutMode: EvidencePolicyRolloutMode.legacy,
          );
          final allowed = {
            LearningProjection.sessionOutcome,
            LearningProjection.activeLearningEffort,
            LearningProjection.history,
            if (input == LexicalQuizInput.definitionTyped && level == 0)
              LearningProjection.masterySrs,
          };
          for (final projection in LearningProjection.values) {
            expect(
              LearningEvidenceContract.allowsOrdinaryProjection(
                promptMode: input.name,
                evidenceClass: context.evidenceClass.name,
                evidenceContextJson: jsonEncode(context.toJson()),
                projection: projection,
              ),
              allowed.contains(projection),
              reason: '${input.name}/$level/${projection.name}',
            );
            expect(
              LearningEvidenceContract.allowsOrdinaryProjection(
                promptMode: input.name,
                evidenceClass: 'independentRecall',
                evidenceContextJson:
                    LearningEvidenceContract.frozenV13LegacyEvidenceContextJson,
                projection: projection,
              ),
              isFalse,
            );
          }
        }
      },
    );

    test(
      '${input.name} ordinary time derives actual variant and Study controlled capture stays rejected',
      () async {
        final state = await learning.startConfiguredQuiz(await prepare(input));
        final before = await h.snapshot();
        final proof = await learning.admitCanonicalLearningTime(
          ConfiguredQuizTimeAdmission(
            state,
            callerContext: LearningTimeCallerContext.ordinary,
          ),
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        final body =
            jsonDecode(proof.contextBindingJson) as Map<String, dynamic>;
        expect(body['promptMode'], input.name);
        expect(
          body['contentRevision'],
          state.plan.questions.first.evidenceContentRevision,
        );
        expect(proof.evidenceContext.skillId, 'definition-recall');
        expect(
          proof.evidenceContext.evidenceClass,
          state.plan.questions.first.unassistedEvidenceClass,
        );
        await learning.requireLiveCanonicalLearningTimeAdmission(
          proof,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        await expectLater(
          learning.admitCanonicalLearningTime(
            ConfiguredQuizTimeAdmission(
              state,
              callerContext: LearningTimeCallerContext.researchControlled,
            ),
            expectedOwnerId: configuredOwnerId,
            stillCurrent: () => true,
          ),
          throwsStateError,
        );
        expect(await h.snapshot(), before);
        expect((await h.researchCounts()).values, everyElement(0));
      },
    );

    test(
      '${input.name} reopens every phase and replays original answers and close without private-text upload',
      () async {
        final typed = input == LexicalQuizInput.definitionTyped;
        final launch = await prepare(input);
        var state = await learning.startConfiguredQuiz(launch);
        final id = state.sessionId;
        final planJson = state.plan.stableSerialization;
        if (typed) {
          state = await learning.saveQuizTypedDraft(
            sessionId: id,
            expectedOwnerId: configuredOwnerId,
            expectedRevision: state.checkpointRevision,
            text: 'synthetic-private-draft',
          );
        }
        await reopen();
        state = await resume(id);
        expect(state.checkpoint, isA<AwaitingQuizAnswer>());
        expect(state.plan.stableSerialization, planJson);
        if (typed) {
          expect(
            (state.checkpoint.lexical! as LexicalTypedLocalData).draft,
            'synthetic-private-draft',
          );
        }
        h.now = h.now.add(const Duration(seconds: 2));
        state = await learning.setQuizHint(
          sessionId: id,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: state.checkpointRevision,
          visible: true,
        );
        final hintAt = state.checkpoint.assistance.hintFirstShownAtUtcMs;
        state = await learning.setQuizHint(
          sessionId: id,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: state.checkpointRevision,
          visible: false,
        );
        state = await learning.prepareQuizAnswer(
          sessionId: id,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: state.checkpointRevision,
          selectedOptionOrdinal: typed ? null : 1,
          typedResponse: typed ? 'synthetic-private-wrong-cat' : null,
          responseTimeMs: 1234,
        );
        final pendingRevision = state.checkpointRevision;
        final firstAnswer = state.checkpoint.answer!.toJson();
        expect(state.acknowledgedContrastiveExplanation, isNull);
        expect(
          state.checkpoint.answer!.responseTimeMs,
          isNull,
          reason: 'restored question never invents latency',
        );
        expect(
          state.checkpoint.answer!.evidenceContext.evidenceClass,
          EvidenceClass.guidedPractice,
        );
        expect(state.checkpoint.assistance.hintFirstShownAtUtcMs, hintAt);
        await reopen();
        state = await resume(id);
        expect(state.checkpoint, isA<PendingQuizAnswer>());
        expect(state.checkpoint.answer!.toJson(), firstAnswer);
        h.now = h.now.add(const Duration(minutes: 3));
        state = await learning.prepareQuizAnswer(
          sessionId: id,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: pendingRevision - 1,
          selectedOptionOrdinal: typed ? null : 1,
          typedResponse: typed ? 'synthetic-private-wrong-cat' : null,
          responseTimeMs: 9999,
        );
        expect(state.checkpoint.answer!.toJson(), firstAnswer);
        final beforeChanged = await h.snapshot();
        await expectLater(
          learning.prepareQuizAnswer(
            sessionId: id,
            expectedOwnerId: configuredOwnerId,
            expectedRevision: pendingRevision - 1,
            selectedOptionOrdinal: typed ? null : 0,
            typedResponse: typed ? 'cat' : null,
          ),
          throwsStateError,
        );
        expect(await h.snapshot(), beforeChanged);
        final first = await learning.commitQuizAnswer(
          sessionId: id,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: pendingRevision,
        );
        state = first.state;
        expect(first.record.inserted, isTrue);
        expect(
          state.acknowledgedContrastiveExplanation,
          typed ? isNull : 'dog makes a different sound.',
        );
        expect(first.record.srs, isNull);
        await reopen();
        state = await resume(id);
        expect(state.checkpoint, isA<AnsweredQuizQuestion>());
        final replay = await learning.commitQuizAnswer(
          sessionId: id,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: pendingRevision,
        );
        expect(replay.record.inserted, isFalse);
        expect(replay.state.checkpoint.answer!.toJson(), firstAnswer);
        expect(await h.count('answer_attempts'), 1);
        state = await learning.advanceQuiz(
          sessionId: id,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: replay.state.checkpointRevision,
        );
        h.now = h.now.add(const Duration(seconds: 4));
        state = await learning.prepareQuizAnswer(
          sessionId: id,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: state.checkpointRevision,
          selectedOptionOrdinal: typed ? null : 1,
          typedResponse: typed ? '  DOG  ' : null,
          responseTimeMs: 4000,
        );
        final secondAnswer = state.checkpoint.answer!.toJson();
        expect(state.checkpoint.answer!.responseTimeMs, 4000);
        expect(
          state.checkpoint.answer!.evidenceContext.evidenceClass,
          typed ? EvidenceClass.independentRecall : EvidenceClass.recognition,
        );
        await reopen();
        state = await resume(id);
        final second = await learning.commitQuizAnswer(
          sessionId: id,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: state.checkpointRevision,
        );
        state = second.state;
        expect(state.checkpoint.answer!.toJson(), secondAnswer);
        expect(state.checkpoint.answer!.isCorrect, isTrue);
        expect(second.record.srs, typed ? isNotNull : isNull);
        h.now = h.now.add(const Duration(seconds: 1));
        state = await learning.prepareQuizFinish(
          sessionId: id,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: state.checkpointRevision,
        );
        final close = state.checkpoint.close!.toJson();
        final closingRevision = state.checkpointRevision;
        await reopen();
        state = await resume(id);
        expect(state.checkpoint, isA<ClosingQuizSession>());
        expect(state.checkpoint.close!.toJson(), close);
        h.now = h.now.add(const Duration(days: 1));
        final completed = await learning.finishConfiguredQuiz(
          sessionId: id,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: closingRevision,
        );
        expect(completed.summary.correctCount, 1);
        expect(completed.summary.wrongCount, 1);
        expect(completed.summary.score, 50);
        await reopen();
        state = await resume(id);
        expect(state.checkpoint, isA<CompletedQuizSession>());
        expect(state.checkpoint.close!.toJson(), close);
        final completedAgain = await learning.finishConfiguredQuiz(
          sessionId: id,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: closingRevision,
        );
        expect(completedAgain.summary.score, completed.summary.score);
        expect(await h.count('answer_attempts'), 2);
        expect(await h.count('srs_states'), typed ? 1 : 0);
        expect(await h.count('points_ledger_entries'), 0);
        final rawRows = await h.snapshot();
        for (final table in [
          'answer_attempts',
          'outbox_operations',
          'events_v2',
        ]) {
          expect(
            rawRows[table].toString(),
            isNot(contains('synthetic-private')),
          );
        }
        final snapshot = await DriftAccountSnapshotBuilder(
          h.database,
          nowUtc: () => h.now,
        ).build(ownerId: configuredOwnerId);
        expect(
          utf8.decode(snapshot.bytes).contains('synthetic-private-wrong-cat'),
          typed,
        );
        final claims = await DriftSyncStore(h.database).claimPending(
          ownerId: configuredOwnerId,
          firebaseUid: configuredFirebaseUid,
          limit: 50,
          leaseToken: 'synthetic-lexical-claim',
          leaseDuration: const Duration(minutes: 1),
          nowUtc: h.now,
        );
        final attemptClaims = claims
            .where((claim) => claim.mutation.payload.containsKey('promptMode'))
            .toList();
        expect(attemptClaims, hasLength(2));
        for (final claim in attemptClaims) {
          expect(claim.mutation.payloadVersion, 2);
          expect(
            jsonEncode(claim.mutation.payload),
            isNot(contains('synthetic-private')),
          );
          expect(claim.mutation.payload.keys, isNot(contains('submittedText')));
          expect(claim.mutation.payload['promptMode'], input.name);
        }
        expect((await h.researchCounts()).values, everyElement(0));
      },
    );

    test(
      'actual SQLite starts authored ${input.name} as a two-question configured deck',
      () async {
        final before = await h.snapshot();
        final launch = await learning.prepareLexicalQuiz(
          expectedOwnerId: configuredOwnerId,
          packVersionId: installed.id,
          entryCodes: const ['cat', 'dog'],
          input: input,
          limit: 2,
          stillCurrent: () => true,
        );
        expect(await h.snapshot(), before);
        final state = await learning.startConfiguredQuiz(launch);
        expect(state.plan.mode, 'definition-quiz');
        expect(state.plan.questions, hasLength(2));
        expect(state.plan.questions.first.correctAnswer, 'cat');
        expect(state.plan.toJson()['schemaVersion'], 2);
        expect(
          state.plan.toJson()['questions'].toString(),
          contains('A small animal that meows.'),
        );
        expect(await h.count('learning_sessions'), 1);
        expect(await h.count('answer_attempts'), 0);
        expect((await h.researchCounts()).values, everyElement(0));
      },
    );
  }
}

final class _AfterLexicalAbandon extends QueryInterceptor {
  _AfterLexicalAbandon(this.interfere);
  final Future<void> Function(QueryExecutor) interfere;
  bool fired = false;

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runUpdate(statement, args);
    if (!fired &&
        statement.startsWith(
          "UPDATE learning_sessions SET state = 'abandoned'",
        )) {
      fired = true;
      await interfere(executor);
    }
    return result;
  }
}
