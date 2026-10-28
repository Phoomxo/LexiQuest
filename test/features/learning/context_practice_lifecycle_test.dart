import 'package:vocab_learning_app/features/sync/domain/research_sync.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'dart:io';
import 'dart:convert';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/context_practice_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/contrastive_feedback_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/guided_repair_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';

import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/identity/application/owner_generation.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_generation.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/personal_sets_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/application/personal_set_activities.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_personal_set_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/packaged_sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/personal_sets.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/packaged_starter_catalog.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  late AppDatabase db;
  late Directory directory;
  late File databaseFile;
  late PersonalSetsUseCases sets;
  late PersonalSetActivities activities;
  late LearningUseCases learning;
  late PersonalSetRevision original;
  var enabled = true;
  var missing = false;
  String? missingId;
  Future<void> Function()? duringAdmission;
  var serial = 0;
  final now = DateTime.utc(2026, 9, 20);
  Future<void> wire() async {
    Future<Uint8List?> load(ContentIdentity identity) async {
      if (missing || identity.id == missingId) return null;
      if (identity == PackagedSenseCrosswalk.identity) {
        return File(PackagedSenseCrosswalk.assetPath).readAsBytes();
      }
      return File(
        'assets/content/lexical_metadata/${identity.id.substring(5)}/r${identity.revision}.json',
      ).readAsBytes();
    }

    final manifests = DriftContentManifestRepository(
      db,
      loadArtifactBytes: load,
    );
    await PackagedStarterCatalog.provision(db, manifests, load);
    await manifests.provisionPackagedArtifact(
      PackagedSenseCrosswalk.verify(
        (await load(PackagedSenseCrosswalk.identity))!,
      ),
    );
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'unused',
      nowUtc: () => now,
    );
    Future<String> activeOwner() async =>
        (await owners.getOrCreateActiveOwner()).id;
    sets = PersonalSetsUseCases(
      repository: DriftPersonalSetRepository(
        db,
        SenseCrosswalkRepository(manifests),
        nowUtc: () => now,
      ),
      ownerGeneration: OwnerGeneration(
        activeOwnerId: activeOwner,
        readDurableStamp: DriftOwnerGeneration(db).read,
      ),
      ownerOperations: OwnerOperationCoordinator(
        gate: DriftOwnerOperationGate(db),
        activeOwnerId: activeOwner,
        nowUtc: () => now,
      ),
    );

    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(
        db,
        lexicalVocabulary: DriftVocabularyRepository(
          db,
          contentManifests: manifests,
        ),
      ),
      generateId: () => 'quiz-${serial++}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      beforeSessionStart: (_) async {
        await duringAdmission?.call();
      },
    );
    activities = PersonalSetActivities(
      sets: sets,
      learning: learning,
      isAvailable: () => enabled,
      contextAvailable: () => enabled,
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('personal-set-activity-');
    databaseFile = File('${directory.path}/data.sqlite');
    db = AppDatabase(NativeDatabase(databaseFile));
    await db.customStatement(
      "INSERT INTO local_owners (id, created_at_utc_ms, is_active) VALUES ('a', 1, 1)",
    );
    enabled = true;
    missing = false;
    missingId = null;
    duringAdmission = null;
    await wire();
    final owner = await sets.begin();
    final pin = SenseCrosswalkPin.fromJson({
      'corpusManifestHash': PackagedSenseCrosswalk.corpusManifestHash,
      'revision': 1,
      'artifactHash': PackagedSenseCrosswalk.artifactHash,
    });
    final crosswalk = await sets.candidates(owner, pin);
    original = PersonalSetRevision.create(
      setId: 'set',
      operationId: 'create',
      expectedPriorRevision: 0,
      createdAtUtcMs: now.millisecondsSinceEpoch,
      title: 'Objects',
      crosswalkPin: pin,
      members: crosswalk.entries.take(2).map((e) => e.ref).toList(),
    );
    await sets.save(owner, original);
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<int> sessionCount() async =>
      (await db.select(db.learningSessions).get()).length;

  test(
    'context launch is pinned and exact launch retry reuses its session',
    () async {
      final owner = await sets.begin();
      final first = await activities.start(
        owner,
        setId: 'set',
        revision: 1,
        operationId: 'context',
        contextInput: ClozeInputMode.selected,
      );
      final retry = await activities.start(
        owner,
        setId: 'set',
        revision: 1,
        operationId: 'context',
        contextInput: ClozeInputMode.selected,
      );
      expect(retry.session.id, first.session.id);
      expect(await sessionCount(), 1);
      final recovery = await learning.loadExactActivityRecovery(
        ownerId: 'a',
        sessionId: first.session.id,
        activityType: 'contextPractice',
      );
      expect(recovery!.checkpoint!.state['inputMode'], 'selected');
      expect(
        recovery.checkpoint!.state['inventoryHash'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      await expectLater(
        activities.start(
          owner,
          setId: 'set',
          revision: 1,
          operationId: 'context',
          contextInput: ClozeInputMode.typed,
        ),
        throwsStateError,
      );
      expect(await sessionCount(), 1);
    },
  );
  test('disabled or unsupported context admission writes no session', () async {
    final owner = await sets.begin();
    enabled = false;
    await expectLater(
      activities.start(
        owner,
        setId: 'set',
        revision: 1,
        operationId: 'off',
        contextInput: ClozeInputMode.typed,
      ),
      throwsStateError,
    );
    expect(await sessionCount(), 0);
  });
  Future<ClozeReviewController> reviewFor(
    PersonalSetActivityLaunch launch,
  ) async {
    final words = await DriftVocabularyRepository(
      db,
      contentManifests: sets.repository.crosswalks.manifests,
    ).readPinnedByIds(launch.session.questions.map((q) => q.word.id));
    final review = const ClozeModeAdapter().createReview(
      session: launch.session,
      lexicalWords: words,
      learning: learning,
      evidence: CurrentActivityEvidenceAdapter(learning: learning),
      hintUsage: () => const HintUsageSnapshot.unavailable(),
      contextPractice: true,
      fixedInputMode: launch.contextInput,
      acceptsOperation: () => enabled,
    );
    addTearDown(review.dispose);
    await review.restoreContextProgress();
    return review;
  }

  for (final withdrawn in ['word', 'category']) {
    test(
      'guided repair rejects withdrawn $withdrawn without new writes',
      () async {
        final launch = await activities.start(
          await sets.begin(),
          setId: 'set',
          revision: 1,
          operationId: 'repair-withdrawal',
          contextInput: ClozeInputMode.selected,
        );
        final review = await reviewFor(launch);
        final q = review.currentItem.question!;
        await review.answerSelected(
          option: q.options.firstWhere((o) => o != q.correctAnswer),
          responseTimeMs: 100,
        );
        final repair = GuidedRepairUseCases(
          learning: learning.repository as DriftLearningRepository,
          manifests: sets.repository.crosswalks.manifests,
          ownerGeneration: sets.ownerGeneration,
          ownerOperations: sets.ownerOperations,
          nowUtc: () => now,
          isAvailable: () => enabled,
        );
        final ticket = await repair.open(review.feedback!);
        final attempts = await db.select(db.answerAttempts).get();
        final events = await db.select(db.eventsV2).get();
        if (withdrawn == 'word') {
          await db.customStatement(
            'UPDATE vocabulary_words SET is_deleted=1 WHERE id=?',
            [q.wordId],
          );
        } else {
          await db.customStatement(
            'UPDATE vocabulary_categories SET is_deleted=1 WHERE id='
            '(SELECT category_id FROM vocabulary_words WHERE id=?)',
            [q.wordId],
          );
        }
        await expectLater(repair.open(review.feedback!), throwsStateError);
        await expectLater(
          repair.act(ticket, operationId: 'late-hint', action: 'hint'),
          throwsStateError,
        );
        expect(await db.select(db.guidedRepairOperations).get(), isEmpty);
        expect(await db.select(db.answerAttempts).get(), attempts);
        expect(await db.select(db.eventsV2).get(), events);
      },
    );
  }
  test(
    'committed wrong answer reopens after real SQLite restart without a second answer',
    () async {
      final owner = await sets.begin();
      final launch = await activities.start(
        owner,
        setId: 'set',
        revision: 1,
        operationId: 'resume',
        contextInput: ClozeInputMode.selected,
      );
      final review = await reviewFor(launch);
      final q = review.currentItem.question!;
      await review.answerSelected(
        option: q.options.firstWhere((o) => o != q.correctAnswer),
        responseTimeMs: 100,
      );
      final feedback = review.feedback!;
      final explanation = await ContrastiveFeedbackUseCases(
        manifests: sets.repository.crosswalks.manifests,
      ).resolveForRepair(committedFeedback: feedback);
      expect(explanation, isNotNull);
      final repair = GuidedRepairUseCases(
        learning: learning.repository as DriftLearningRepository,
        manifests: sets.repository.crosswalks.manifests,
        ownerGeneration: sets.ownerGeneration,
        ownerOperations: sets.ownerOperations,
        nowUtc: () => now,
        isAvailable: () => enabled,
      );
      final ticket = await repair.open(feedback);
      expect(ticket.explanation, isNotNull);
      final hinted = await repair.act(
        ticket,
        operationId: 'context-repair-hint',
        action: 'hint',
      );
      await repair.act(
        hinted,
        operationId: 'context-repair-answer',
        action: 'answer',
        answer: q.correctAnswer,
      );
      expect(await db.select(db.guidedRepairOperations).get(), hasLength(2));
      final before = await db.select(db.answerAttempts).get();
      await db.close();
      db = AppDatabase(NativeDatabase(databaseFile));
      await wire();
      final reopened = await ContextPracticeUseCases(
        activities,
      ).resume(await sets.begin());
      expect(reopened!.session.id, launch.session.id);
      expect(await db.select(db.guidedRepairOperations).get(), hasLength(2));
      final restored = await reviewFor(reopened);
      expect(restored.phase, ClozeReviewPhase.answered);
      expect(restored.feedback!.isCorrect, isFalse);
      expect(
        restored.feedback!.committedContrastiveAttempt!.attemptIdentity,
        before.single.id,
      );
      expect(
        () => restored.answerSelected(
          option: q.correctAnswer,
          responseTimeMs: 100,
        ),
        throwsStateError,
      );
      await restored.advance();
      await restored.answerSelected(
        option: restored.currentItem.question!.correctAnswer,
        responseTimeMs: 100,
      );
      await restored.advance();
      expect(await db.select(db.answerAttempts).get(), hasLength(2));
      expect(await db.select(db.srsStates).get(), isEmpty);
      expect(
        (await db.select(db.learningSessions).get()).single.state,
        'completed',
      );
      expect(
        await ContextPracticeUseCases(activities).resume(await sets.begin()),
        isNull,
      );
    },
  );
  test(
    'typed context locks input mode and creates exactly one canonical review',
    () async {
      final launch = await activities.start(
        await sets.begin(),
        setId: 'set',
        revision: 1,
        operationId: 'typed',
        contextInput: ClozeInputMode.typed,
      );
      final review = await reviewFor(launch);
      final q = review.currentItem.question!;
      expect(
        () => review.answerSelected(option: q.correctAnswer, responseTimeMs: 1),
        throwsStateError,
      );
      await review.answerTyped(text: q.correctAnswer, responseTimeMs: 100);
      final attempts = await db.select(db.answerAttempts).get();
      expect(attempts, hasLength(1));
      expect(attempts.single.evidenceClass, 'independentRecall');
      final states = await db.select(db.srsStates).get();
      expect(states, hasLength(1));
      final reopened = await ContextPracticeUseCases(
        activities,
      ).resume(await sets.begin());
      final restored = await reviewFor(reopened!);
      expect(restored.phase, ClozeReviewPhase.answered);
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
      expect(await db.select(db.srsStates).get(), states);
      final research = await db
          .customSelect(
            "SELECT count(*) AS n FROM events_v2 WHERE privacy_classification = 'research' OR event_type LIKE 'Research%'",
          )
          .getSingle();
      expect(research.read<int>('n'), 0);
      final events = await db.select(db.eventsV2).get();
      expect(
        events.where(
          (e) => ResearchSyncContract.eventTypes.contains(e.eventType),
        ),
        isEmpty,
      );
      final outbox = await db.select(db.outboxOperations).get();
      expect(
        outbox.where(
          (o) =>
              ResearchSyncContract.collectionForEntityType(o.entityType) !=
              null,
        ),
        isEmpty,
      );
      expect(outbox.where((o) => o.entityType == 'attempt'), hasLength(1));
      expect(outbox.where((o) => o.entityType == 'srsState'), hasLength(1));

      for (final table in [
        'research_consents',
        'research_participation_permits',
        'research_session_proofs',
        'experiment_assignments',
      ]) {
        expect(
          (await db
                  .customSelect('SELECT count(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
          0,
          reason: table,
        );
      }
    },
  );
  test(
    'owner change and withdrawn content reject admission atomically',
    () async {
      final owner = await sets.begin();
      missing = true;
      await expectLater(
        activities.start(
          owner,
          setId: 'set',
          revision: 1,
          operationId: 'missing',
          contextInput: ClozeInputMode.selected,
        ),
        throwsA(isA<Object>()),
      );
      expect(await sessionCount(), 0);
      missing = false;
      duringAdmission = () async {
        enabled = false;
      };
      await expectLater(
        activities.start(
          owner,
          setId: 'set',
          revision: 1,
          operationId: 'late-off',
          contextInput: ClozeInputMode.selected,
        ),
        throwsStateError,
      );
      expect(await sessionCount(), 0);
    },
  );

  test(
    'unsupported sense and rollout-off reject before session admission',
    () async {
      final owner = await sets.begin();
      final candidates = await sets.candidates(owner, original.crosswalkPin);
      await sets.save(
        owner,
        PersonalSetRevision.create(
          setId: 'set',
          operationId: 'edit',
          expectedPriorRevision: 1,
          createdAtUtcMs: now.millisecondsSinceEpoch,
          title: 'Unsupported',
          crosswalkPin: original.crosswalkPin,
          members: [
            candidates.entries
                .firstWhere((e) => e.ref.wordId == 'word:starter-chair')
                .ref,
          ],
        ),
      );
      await expectLater(
        activities.start(
          owner,
          setId: 'set',
          revision: 2,
          operationId: 'unsupported',
          contextInput: ClozeInputMode.typed,
        ),
        throwsStateError,
      );
      final disabled = PersonalSetActivities(
        sets: sets,
        learning: learning,
        isAvailable: () => true,
      );
      expect(disabled.canPracticeContext, isFalse);
      await expectLater(
        disabled.start(
          owner,
          setId: 'set',
          revision: 1,
          operationId: 'off',
          contextInput: ClozeInputMode.typed,
        ),
        throwsStateError,
      );
      expect(await sessionCount(), 0);
    },
  );
  test(
    'RESTORE-OLDER rejects a future checkpoint before any new write',
    () async {
      final owner = await sets.begin();
      final launch = await activities.start(
        owner,
        setId: 'set',
        revision: 1,
        operationId: 'future',
        contextInput: ClozeInputMode.typed,
      );
      final recovery = await learning.loadExactActivityRecovery(
        ownerId: 'a',
        sessionId: launch.session.id,
        activityType: 'contextPractice',
      );
      await learning.appendActivityCheckpoint(
        LearningActivityCheckpoint(
          sessionId: launch.session.id,
          activityType: 'contextPractice',
          revision: 2,
          occurredAtUtc: now,
          state: {...recovery!.checkpoint!.state, 'schemaVersion': 999},
        ),
        ownerId: 'a',
      );
      final before = await db.select(db.eventsV2).get();
      await expectLater(
        ContextPracticeUseCases(activities).resume(owner),
        throwsStateError,
      );
      expect(await db.select(db.eventsV2).get(), before);
      expect(await db.select(db.answerAttempts).get(), isEmpty);
      expect(await sessionCount(), 1);
    },
  );
  test(
    'guest merge keeps pinned context and canonical evidence, export/delete include it',
    () async {
      final oldOwner = await sets.begin();
      final launch = await activities.start(
        oldOwner,
        setId: 'set',
        revision: 1,
        operationId: 'merge',
        contextInput: ClozeInputMode.selected,
      );
      final review = await reviewFor(launch);
      await review.answerSelected(option: 'pencil', responseTimeMs: 50);
      final prior = (await db.select(db.answerAttempts).get()).single;
      await db.customStatement(
        "INSERT INTO local_owners(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES('account','context-user','firebaseBound',1,0)",
      );
      await DriftOwnerUpgradeRepository(
        db,
        nowUtc: () => now,
        generateConflictId: () => 'conflict-${serial++}',
        generateOwnerId: () => 'guest-${serial++}',
        generateOwnerOperationToken: () => 'upgrade-${serial++}',
        deleteOwnerSecrets: (_) async {},
      ).upgrade(activeOwnerId: 'a', firebaseUid: 'context-user');
      await expectLater(
        ContextPracticeUseCases(activities).resume(oldOwner),
        throwsStateError,
      );
      final resumed = await ContextPracticeUseCases(
        activities,
      ).resume(await sets.begin());
      expect(resumed!.session.ownerId, 'account');
      final restored = await reviewFor(resumed);
      expect(
        restored.feedback!.committedContrastiveAttempt!.attemptIdentity,
        prior.id,
      );
      expect(
        restored.feedback!.committedContrastiveAttempt!.ownerId,
        'account',
      );
      final archive = await OwnerLifecycleArchiveExporter(
        database: db,
        nowUtc: () => now,
      ).prepareActive();
      final tables =
          ((jsonDecode(utf8.decode(archive.bytes)) as Map)['content']
                  as Map)['tables']
              as List;
      final sessions =
          (tables.cast<Map>().singleWhere(
                    (t) => t['alias'] == 'learningSessions',
                  )['records']
                  as List)
              .cast<Map>();
      expect(
        sessions.any((r) => r['activityType'] == 'contextPractice'),
        isTrue,
      );
      final secrets = <String>[];
      await LocalDataDeletion(
        db,
        deleteOwnerSecrets: (owner) async => secrets.add(owner),
      ).eraseAll(ownerId: 'account');
      expect(secrets, ['account']);
      expect(await db.select(db.answerAttempts).get(), isEmpty);
      expect(await db.select(db.learningSessions).get(), isEmpty);
      expect(
        (await db.select(db.eventsV2).get()).where(
          (r) => r.ownerId == 'account',
        ),
        isEmpty,
      );
      expect(
        (await db.select(db.personalSetRevisions).get()).where(
          (r) => r.ownerId == 'account',
        ),
        isEmpty,
      );
    },
  );
  test(
    'A to B to A generation rejects the previously captured context owner',
    () async {
      final owner = await sets.begin();
      await db.customStatement(
        "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES('b',1,0)",
      );
      await db.transaction(() async {
        await db.customStatement(
          "UPDATE local_owners SET is_active=0 WHERE id='a'",
        );
        await db.customStatement(
          "UPDATE local_owners SET is_active=1 WHERE id='b'",
        );
        await DriftOwnerGeneration(db).advance();
      });
      await db.transaction(() async {
        await db.customStatement(
          "UPDATE local_owners SET is_active=0 WHERE id='b'",
        );
        await db.customStatement(
          "UPDATE local_owners SET is_active=1 WHERE id='a'",
        );
        await DriftOwnerGeneration(db).advance();
      });
      await expectLater(
        activities.start(
          owner,
          setId: 'set',
          revision: 1,
          operationId: 'stale-owner',
          contextInput: ClozeInputMode.selected,
        ),
        throwsStateError,
      );
      expect(await sessionCount(), 0);
    },
  );

  test(
    'confusable distractor must retain its reviewed artifact at both admission fences',
    () async {
      final owner = await sets.begin();
      final candidates = await sets.candidates(owner, original.crosswalkPin);
      await sets.save(
        owner,
        PersonalSetRevision.create(
          setId: 'set',
          operationId: 'bottle-set',
          expectedPriorRevision: 1,
          createdAtUtcMs: now.millisecondsSinceEpoch,
          title: 'Bottle',
          crosswalkPin: original.crosswalkPin,
          members: [
            candidates.entries
                .firstWhere((e) => e.ref.wordId == 'word:starter-bottle')
                .ref,
          ],
        ),
      );
      missingId = 'word:starter-cup';
      await expectLater(
        activities.start(
          owner,
          setId: 'set',
          revision: 2,
          operationId: 'missing-cup',
          contextInput: ClozeInputMode.selected,
        ),
        throwsA(isA<Exception>()),
      );
      expect(await sessionCount(), 0);
      missingId = null;
      duringAdmission = () async {
        missingId = 'word:starter-cup';
      };
      await expectLater(
        activities.start(
          owner,
          setId: 'set',
          revision: 2,
          operationId: 'withdraw-cup',
          contextInput: ClozeInputMode.selected,
        ),
        throwsA(isA<Exception>()),
      );
      expect(await sessionCount(), 0);
      missingId = null;
      duringAdmission = null;
      final launch = await activities.start(
        owner,
        setId: 'set',
        revision: 2,
        operationId: 'bottle',
        contextInput: ClozeInputMode.selected,
      );
      final review = await reviewFor(launch);
      expect(review.currentItem.question!.options.toSet(), {'cup', 'bottle'});
    },
  );
  test(
    'restore rejects reordered session items even before the first answer',
    () async {
      final launch = await activities.start(
        await sets.begin(),
        setId: 'set',
        revision: 1,
        operationId: 'reordered',
        contextInput: ClozeInputMode.selected,
      );
      final session = launch.session;
      final changed = PersonalSetActivityLaunch(
        QuizSession(
          id: session.id,
          ownerId: session.ownerId,
          startedAtUtc: session.startedAtUtc,
          questions: session.questions.reversed.toList(),
        ),
        launch.revision,
        launch.items,
        contextInput: launch.contextInput,
      );
      await expectLater(reviewFor(changed), throwsStateError);
      expect(await db.select(db.answerAttempts).get(), isEmpty);
    },
  );
  test(
    'restore rejects a wrong choice without its reviewed alternative provenance',
    () async {
      final launch = await activities.start(
        await sets.begin(),
        setId: 'set',
        revision: 1,
        operationId: 'bad-provenance',
        contextInput: ClozeInputMode.selected,
      );
      final review = await reviewFor(launch);
      final q = review.currentItem.question!;
      final adapter = const ClozeModeAdapter();
      await CurrentActivityEvidenceAdapter(learning: learning)
          .captureCloze(
            ownerId: 'a',
            sessionId: launch.session.id,
            wordId: q.wordId,
            isCorrect: false,
            responseTimeMs: 10,
            attemptNumber: 1,
            contentRevision: 1,
            checksumSha256: q.checksumSha256,
            typed: false,
            classification: adapter.classifyResponse(
              inputMode: ClozeInputMode.selected,
              hint: const HintUsageSnapshot.unavailable(),
            ),
          )
          .record();
      await expectLater(reviewFor(launch), throwsStateError);
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
    },
  );
}
