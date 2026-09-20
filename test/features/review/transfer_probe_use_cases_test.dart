import 'package:vocab_learning_app/features/review/application/transfer_probe_use_cases.dart';
import 'package:vocab_learning_app/features/review/domain/transfer_probe.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/features/review/presentation/transfer_probe_screen.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/features/review/data/drift_review_center_reader.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/review/application/review_center_use_cases.dart';
import 'package:vocab_learning_app/screens/review_center_screen.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'dart:io';
import 'dart:convert';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';

import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Variable;
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
  var now = DateTime.utc(2026, 9, 20);
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
    now = DateTime.utc(2026, 9, 20);
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
      members: crosswalk.entries
          .where(
            (e) => [
              'word:starter-book',
              'word:starter-pencil',
              'word:starter-bottle',
            ].contains(e.ref.wordId),
          )
          .map((e) => e.ref)
          .toList(),
    );
    await sets.save(owner, original);
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  TransferProbeUseCases service() => TransferProbeUseCases(
    sets: sets,
    learning: learning,
    evidence: CurrentActivityEvidenceAdapter(learning: learning),
    isAvailable: () => enabled,
  );
  Future<String> origin([String word = 'book']) async {
    final owner = await sets.begin();
    final subset = PersonalSetRevision.create(
      setId: 'origin-$word',
      operationId: 'subset-$word',
      expectedPriorRevision: 0,
      createdAtUtcMs: now.millisecondsSinceEpoch,
      title: 'Prior context',
      crosswalkPin: original.crosswalkPin,
      members: [
        original.members.singleWhere((r) => r.wordId == 'word:starter-$word'),
      ],
    );
    await sets.save(owner, subset);
    final launch = await activities.start(
      owner,
      setId: subset.setId,
      revision: 1,
      operationId: 'origin',
      contextInput: ClozeInputMode.typed,
    );
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
      fixedInputMode: ClozeInputMode.typed,
      acceptsOperation: () => enabled,
    );
    await review.answerTyped(
      text: review.currentItem.question!.correctAnswer,
      responseTimeMs: 100,
    );
    review.dispose();
    await learning.abandonSession(
      ownerId: 'a',
      sessionId: launch.session.id,
      abandonedAtUtc: now,
    );
    return (await db.select(db.answerAttempts).get()).single.id;
  }

  test(
    'real prior attempt admits only after delay and commits once across SQLite reopen',
    () async {
      final id = await origin();
      final s = service();
      expect(await s.offers(await sets.begin()), isEmpty);
      now = now.add(const Duration(days: 1));
      final offers = await s.offers(await sets.begin());
      expect(offers, hasLength(2));
      expect(offers.first.originAttemptId, id);
      final run = await s.start(
        await sets.begin(),
        offer: offers.first,
        operationId: 'start',
      );
      final done = await s.answer(
        run,
        answer: offers.first.item.answer,
        operationId: 'answer',
      );
      expect(done.correct, isTrue);
      expect(done.summary, isNotNull);
      expect(done.timing, ProbeTiming.unverified);
      final count = (await db.select(db.answerAttempts).get()).length;
      await db.close();
      db = AppDatabase(NativeDatabase(databaseFile));
      await wire();
      final reopened = service();
      final restored = await reopened.resume(
        await sets.begin(),
        run.session.id,
      );
      expect(restored.correct, isTrue);
      final replay = await reopened.answer(
        restored,
        answer: offers.first.item.answer,
        operationId: 'answer',
      );
      expect(replay.summary!.id, done.summary!.id);
      expect(await db.select(db.answerAttempts).get(), hasLength(count));
      await expectLater(
        reopened.answer(restored, answer: 'wrong', operationId: 'answer'),
        throwsStateError,
      );
    },
  );
  test('assistance is durable and cannot become independent recall', () async {
    await origin();
    now = now.add(const Duration(days: 1));
    final s = service();
    final owner = await sets.begin();
    final run = await s.start(
      owner,
      offer: (await s.offers(owner)).first,
      operationId: 'start',
    );
    final hinted = await s.hint(run);
    expect(hinted.assisted, isTrue);
    final done = await s.answer(
      hinted,
      answer: hinted.item.answer,
      operationId: 'answer',
    );
    final a = (await db.select(db.answerAttempts).get()).last;
    expect(a.evidenceClass, 'guidedPractice');
    expect(done.assisted, isTrue);
  });
  test(
    'withdrawn content, disabled entry and retired handle cannot write',
    () async {
      await origin();
      now = now.add(const Duration(days: 1));
      final s = service();
      final owner = await sets.begin();
      final offer = (await s.offers(owner)).first;
      enabled = false;
      await expectLater(
        s.start(owner, offer: offer, operationId: 'start'),
        throwsStateError,
      );
      enabled = true;
      final run = await s.start(owner, offer: offer, operationId: 'start');
      s.retire();
      await expectLater(
        s.answer(run, answer: 'book', operationId: 'answer'),
        throwsStateError,
      );
      final resumed = await s.resume(owner, run.session.id);
      missing = true;
      await expectLater(
        s.answer(resumed, answer: 'book', operationId: 'answer'),
        throwsA(isA<ContentQualityFailure>()),
      );
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
      await s.abandon(owner, run.session.id);
    },
  );
  test(
    'forward and backward wall jumps during an open probe reject writes',
    () async {
      await origin();
      now = now.add(const Duration(days: 1));
      final s = service();
      final owner = await sets.begin();
      final run = await s.start(
        owner,
        offer: (await s.offers(owner)).first,
        operationId: 'start',
      );
      now = now.add(const Duration(hours: 2));
      await expectLater(
        s.answer(run, answer: run.item.answer, operationId: 'answer'),
        throwsStateError,
      );
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
    },
  );
  test(
    'checkpoint failure rolls back canonical attempt and completion',
    () async {
      await origin();
      now = now.add(const Duration(days: 1));
      final s = service();
      final owner = await sets.begin();
      final run = await s.start(
        owner,
        offer: (await s.offers(owner)).first,
        operationId: 'start',
      );
      await db.customStatement(
        "CREATE TRIGGER fail_probe BEFORE INSERT ON events_v2 WHEN NEW.event_type='LearningActivityCheckpoint' AND json_extract(NEW.payload_json, '\$.state.kind')='transferProbe' BEGIN SELECT RAISE(ABORT, 'injected checkpoint failure'); END",
      );
      await expectLater(
        s.answer(run, answer: run.item.answer, operationId: 'answer'),
        throwsA(isA<Exception>()),
      );
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
      final restored = await s.resume(owner, run.session.id);
      expect(restored.summary, isNull);
      await db.customStatement('DROP TRIGGER fail_probe');
      expect(
        (await s.answer(
          restored,
          answer: run.item.answer,
          operationId: 'answer',
        )).correct,
        isTrue,
      );
    },
  );
  for (final layout in [(320.0, 2.0), (390.0, 1.0)]) {
    testWidgets('probe typed answer and result remain usable at $layout', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final loader = FontLoader('NotoSansThai')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File(
                  'assets/fonts/NotoSansThai-Variable.ttf',
                ).readAsBytes(),
              ),
            ),
          );
        await loader.load();
      });
      await tester.runAsync(() async {
        await origin();
      });
      now = now.add(const Duration(days: 1));
      final s = service();
      final run = (await tester.runAsync(() async {
        final owner = await sets.begin();
        return s.start(
          owner,
          offer: (await s.offers(owner)).first,
          operationId: 'start',
        );
      }))!;
      tester.view.physicalSize = Size(layout.$1, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'NotoSansThai'),
          navigatorObservers: [appRouteObserver],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(layout.$2)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const ValueKey('probe-capture'),
            child: TransferProbeScreen(useCases: s, run: run),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
      }

      await settle();
      Future<void> capture(String name) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('probe-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('build/e52-visual');
          await dir.create(recursive: true);
          await File(
            '${dir.path}/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture(
        'probe-ready-${layout.$1.toInt()}-text${(layout.$2 * 100).toInt()}',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('probe-submit')));
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('probe-submit'))),
      );
      await settle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).enabled,
        isTrue,
        reason:
            'An empty answer must stay editable and must not become an uncertain write',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('probe-answer')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), run.item.answer);
      await tester.ensureVisible(find.byKey(const ValueKey('probe-submit')));
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('probe-submit'))),
      );
      await settle();
      expect(find.textContaining('Timing unverified'), findsWidgets);
      expect(find.text('Correct'), findsOneWidget);
      expect(
        find.textContaining('Independent spelling recall'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 1800),
      );
      await settle();
      await capture(
        'probe-result-${layout.$1.toInt()}-text${(layout.$2 * 100).toInt()}',
      );
      await tester.pumpWidget(const SizedBox());
      await settle();
    });
  }
  test(
    'used context remains unavailable even after an abandoned probe',
    () async {
      await origin();
      now = now.add(const Duration(days: 1));
      final s = service();
      final owner = await sets.begin();
      final offers = await s.offers(owner);
      final run = await s.start(
        owner,
        offer: offers.first,
        operationId: 'start',
      );
      await s.abandon(owner, run.session.id);
      await expectLater(s.resume(owner, run.session.id), throwsStateError);
      expect(await s.offers(owner), hasLength(1));
      await expectLater(
        s.start(owner, offer: offers.first, operationId: 'new'),
        throwsStateError,
      );
    },
  );
  test('ending probe retries retain terminal identity across reopen', () async {
    await origin();
    now = now.add(const Duration(days: 1));
    final s = service();
    final owner = await sets.begin();
    final run = await s.start(
      owner,
      offer: (await s.offers(owner)).first,
      operationId: 'start',
    );
    await s.abandon(owner, run.session.id);
    final endedAt = now.millisecondsSinceEpoch;
    final before = await db
        .customSelect(
          'SELECT * FROM learning_sessions WHERE id = ?',
          variables: [Variable(run.session.id)],
        )
        .getSingle();
    final eventCount = (await db.select(db.eventsV2).get()).length;
    now = now.add(const Duration(minutes: 2));
    await s.abandon(owner, run.session.id);
    await db.close();
    db = AppDatabase(NativeDatabase(databaseFile));
    await wire();
    now = now.add(const Duration(minutes: 2));
    await service().abandon(await sets.begin(), run.session.id);
    final after = await db
        .customSelect(
          'SELECT * FROM learning_sessions WHERE id = ?',
          variables: [Variable(run.session.id)],
        )
        .getSingle();
    expect(after.data, before.data);
    expect(after.read<int>('ended_at_utc_ms'), endedAt);
    expect(after.read<String>('state'), 'abandoned');
    expect((await db.select(db.eventsV2).get()).length, eventCount);
    expect((await db.select(db.answerAttempts).get()), hasLength(1));
  });
  test(
    'wrong probe reaches canonical incorrect review with its exact item pin',
    () async {
      await origin();
      now = now.add(const Duration(days: 1));
      final s = service();
      final owner = await sets.begin();
      final run = await s.start(
        owner,
        offer: (await s.offers(owner)).first,
        operationId: 'start',
      );
      final done = await s.answer(run, answer: 'wrong', operationId: 'answer');
      final reader = DriftReviewCenterReader(
        db,
        contentManifests: sets.repository.crosswalks.manifests,
      );
      final queue = await reader.compose(
        ReviewQueueFilter(
          ownerId: owner.ownerId,
          evaluatedAtUtc: now,
          timezoneId: 'Asia/Bangkok',
          includeReasons: {ReviewQueueReason.incorrectAnswer},
        ),
      );
      expect(
        queue.map((q) => q.snapshot.identity.id),
        contains(done.item.wordId),
      );
    },
  );
  testWidgets('Review probe offers clear when owner generation retires', (
    tester,
  ) async {
    await tester.runAsync(origin);
    now = now.add(const Duration(days: 1));
    final s = service();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransferProbeReviewPanel(useCases: s)),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
    }

    await settle();
    expect(find.byKey(const ValueKey('probe-offer-0')), findsOneWidget);
    await tester.runAsync(() => DriftOwnerGeneration(db).advance());
    await settle();
    expect(find.byKey(const ValueKey('probe-offer-0')), findsNothing);
    expect(find.text('Check again'), findsOneWidget);
    expect(
      await tester.runAsync(() => db.select(db.answerAttempts).get()),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle();
  });
  testWidgets('Review entry opens probe and returns to canonical queue', (
    tester,
  ) async {
    await tester.runAsync(origin);
    now = now.add(const Duration(days: 1));
    final s = service();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: ReviewCenterScreen(
          transferProbes: s,
          useCases: ReviewCenterUseCases(
            reader: DriftReviewCenterReader(
              db,
              contentManifests: sets.repository.crosswalks.manifests,
            ),
            ownerIdentities: DriftReviewOwnerIdentityReader(db),
            sessionLauncher: LearningUseCasesReviewSessionLauncher(learning),
            nowUtc: () => now,
            timezoneId: 'Asia/Bangkok',
          ),
          lessonShellBuilder: (_) =>
              throw StateError('Not launched in this probe journey'),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
    }

    await settle();
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('probe-offer-0'))),
    );
    await settle();
    expect(find.byType(TransferProbeScreen), findsOneWidget);
    expect(
      ModalRoute.of(
        tester.element(find.byType(TransferProbeScreen)),
      )!.settings.name,
      'home/today/review/probe',
    );
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.ensureVisible(find.byKey(const ValueKey('probe-submit')));
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('probe-submit'))),
    );
    await settle();
    await tester.ensureVisible(find.text('Return to Review'));
    await tester.tap(find.text('Return to Review'));
    await settle();
    expect(find.byType(TransferProbeScreen), findsNothing);
    expect(find.byType(ReviewCenterScreen), findsOneWidget);
    expect(find.text('เคยตอบผิด'), findsWidgets);
    expect(find.byKey(const ValueKey('probe-offer-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle();
  });
  for (final word in ['book', 'pencil', 'bottle']) {
    test(
      'both authored $word contexts complete with separate immutable identities',
      () async {
        await origin(word);
        now = now.add(const Duration(days: 1));
        final s = service();
        final owner = await sets.begin();
        final offers = await s.offers(owner);
        expect(offers, hasLength(2));
        for (final offer in offers) {
          final run = await s.start(
            owner,
            offer: offer,
            operationId: offer.item.id,
          );
          final done = await s.answer(
            run,
            answer: word,
            operationId: 'answer-${offer.item.id}',
          );
          expect(done.correct, isTrue);
          expect(done.summary!.state, 'completed');
          expect(done.offer.originAttemptId, offer.originAttemptId);
        }
        expect(await s.offers(owner), isEmpty);
        expect(await db.select(db.answerAttempts).get(), hasLength(3));
        for (final table in [
          'research_session_proofs',
          'motivation_responses',
          'reward_transactions',
        ]) {
          expect(
            (await db
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n'),
            0,
            reason: table,
          );
        }
      },
    );
  }
  test(
    'guest upgrade preserves origin and result identity; export and deletion include probe',
    () async {
      await origin();
      now = now.add(const Duration(days: 1));
      final s = service();
      final owner = await sets.begin();
      final started = await s.start(
        owner,
        offer: (await s.offers(owner)).first,
        operationId: 'start',
      );
      final run = await s.hint(started);
      final before = jsonEncode(run.state());
      await db.customStatement(
        "INSERT INTO local_owners(id,firebase_uid,account_state,created_at_utc_ms,is_active) VALUES('account','probe-user','firebaseBound',1,0)",
      );
      await DriftOwnerUpgradeRepository(
        db,
        nowUtc: () => now,
        generateConflictId: () => 'conflict-${serial++}',
        generateOwnerId: () => 'unused',
        generateOwnerOperationToken: () => 'merge-${serial++}',
        deleteOwnerSecrets: (_) async {},
      ).upgrade(activeOwnerId: 'a', firebaseUid: 'probe-user');
      final fresh = await s.resume(await sets.begin(), run.session.id);
      expect(jsonEncode(fresh.state()), before);
      await expectLater(
        s.answer(run, answer: run.item.answer, operationId: 'old'),
        throwsStateError,
      );
      final done = await s.answer(
        fresh,
        answer: fresh.item.answer,
        operationId: 'answer',
      );
      expect(done.assisted, isTrue);
      final archive = await OwnerLifecycleArchiveExporter(
        database: db,
        nowUtc: () => now,
      ).prepareActive();
      expect(utf8.decode(archive.bytes), isNot(contains(run.item.sentence)));
      await LocalDataDeletion(
        db,
        deleteOwnerSecrets: (_) async {},
      ).eraseAll(ownerId: 'account');
      expect(await db.select(db.answerAttempts).get(), isEmpty);
      await expectLater(
        s.resume(fresh.owner, run.session.id),
        throwsStateError,
      );
    },
  );
  for (final corruption in ['future', 'partial']) {
    test('unsupported or incomplete $corruption recovery cannot write', () async {
      await origin();
      now = now.add(const Duration(days: 1));
      final s = service();
      final owner = await sets.begin();
      var run = await s.start(
        owner,
        offer: (await s.offers(owner)).first,
        operationId: 'start',
      );
      run = await s.answer(run, answer: run.item.answer, operationId: 'answer');
      if (corruption == 'future') {
        await db.customStatement(
          r"UPDATE events_v2 SET payload_json=json_set(payload_json, '$.state.schemaVersion', 2) WHERE event_type='LearningActivityCheckpoint' AND json_extract(payload_json, '$.state.kind')='transferProbe'",
        );
      } else {
        await db.customStatement(
          r"DELETE FROM events_v2 WHERE event_type='LearningActivityCheckpoint' AND json_extract(payload_json, '$.state.kind')='transferProbe' AND json_extract(payload_json, '$.revision')=2",
        );
      }
      final before = (await db.customSelect('SELECT * FROM events_v2').get())
          .map((r) => r.data)
          .toList();
      await expectLater(s.resume(owner, run.session.id), throwsStateError);
      expect(
        (await db.customSelect('SELECT * FROM events_v2').get())
            .map((r) => r.data)
            .toList(),
        before,
      );
    });
  }
  test(
    'timing metadata corruption fails recovery without rewriting evidence',
    () async {
      await origin();
      now = now.add(const Duration(days: 1));
      final s = service();
      final owner = await sets.begin();
      final run = await s.start(
        owner,
        offer: (await s.offers(owner)).first,
        operationId: 'start',
      );
      await s.answer(run, answer: run.item.answer, operationId: 'answer');
      await db.customStatement(
        r"UPDATE events_v2 SET payload_json=json_set(payload_json, '$.state.result.elapsedMs', 1) WHERE event_type='LearningActivityCheckpoint' AND json_extract(payload_json, '$.state.kind')='transferProbe' AND json_extract(payload_json, '$.revision')=2",
      );
      await expectLater(s.resume(owner, run.session.id), throwsStateError);
      expect(await db.select(db.answerAttempts).get(), hasLength(2));
    },
  );
  test(
    'lost launch and answer acknowledgements reconcile after physical reopen',
    () async {
      await origin();
      now = now.add(const Duration(days: 1));
      var s = service();
      var owner = await sets.begin();
      final offer = (await s.offers(owner)).first;
      await expectLater(() async {
        await s.start(owner, offer: offer, operationId: 'lost-launch');
        throw StateError('injected acknowledgement loss');
      }(), throwsStateError);
      await db.close();
      db = AppDatabase(NativeDatabase(databaseFile));
      await wire();
      s = service();
      owner = await sets.begin();
      final run = await s.start(
        owner,
        offer: offer,
        operationId: 'lost-launch',
      );
      expect(await db.select(db.learningSessions).get(), hasLength(2));
      await expectLater(() async {
        await s.answer(
          run,
          answer: run.item.answer,
          operationId: 'lost-answer',
        );
        throw StateError('injected acknowledgement loss');
      }(), throwsStateError);
      await db.close();
      db = AppDatabase(NativeDatabase(databaseFile));
      await wire();
      s = service();
      owner = await sets.begin();
      final restored = await s.resume(owner, run.session.id);
      expect(
        (await s.answer(
          restored,
          answer: run.item.answer,
          operationId: 'lost-answer',
        )).summary!.state,
        'completed',
      );
      expect(await db.select(db.answerAttempts).get(), hasLength(2));
    },
  );
  for (final boundary in ['owner', 'feature', 'retire']) {
    test('in-flight $boundary revocation rolls back probe admission', () async {
      await origin();
      now = now.add(const Duration(days: 1));
      final s = service();
      final owner = await sets.begin();
      final offer = (await s.offers(owner)).first;
      duringAdmission = () async {
        if (boundary == 'owner') {
          await DriftOwnerGeneration(db).advance();
        } else if (boundary == 'feature') {
          enabled = false;
        } else {
          s.retire();
        }
      };
      await expectLater(
        s.start(owner, offer: offer, operationId: 'start'),
        throwsStateError,
      );
      expect(await db.select(db.learningSessions).get(), hasLength(1));
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
    });
  }
  for (final boundary in ['owner', 'route', 'background']) {
    testWidgets('probe permanently retires UI on $boundary', (tester) async {
      await tester.runAsync(origin);
      now = now.add(const Duration(days: 1));
      final s = service();
      final run = (await tester.runAsync(() async {
        final owner = await sets.begin();
        return s.start(
          owner,
          offer: (await s.offers(owner)).first,
          operationId: 'start',
        );
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: TransferProbeScreen(useCases: s, run: run),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 35; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
      }

      await settle();
      if (boundary == 'owner') {
        await tester.runAsync(() => DriftOwnerGeneration(db).advance());
      } else if (boundary == 'background') {
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
      } else {
        Navigator.of(tester.element(find.byType(TransferProbeScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Cover')),
          ),
        );
      }
      await settle();
      if (boundary == 'route') {
        Navigator.of(tester.element(find.text('Cover'))).pop();
        await settle();
      }
      if (boundary == 'background') {
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await settle();
      }
      expect(find.textContaining('Practice paused'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle();
      expect(
        await tester.runAsync(() => db.select(db.answerAttempts).get()),
        hasLength(1),
      );
    });
  }
}
