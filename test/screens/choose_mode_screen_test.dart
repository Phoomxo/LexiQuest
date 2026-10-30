import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../support/dictation_session_harness.dart';
import '../support/cloze_session_harness.dart' as cloze;

void main() {
  for (final variant in ClozeVariant.values) {
    testWidgets('Cloze selects explicit $variant before any generation', (
      tester,
    ) async {
      final h = (await tester.runAsync(cloze.ClozeSessionHarness.open))!;
      try {
        await _pumpClozeEntry(tester, h);
        expect(h.provider.requests, isEmpty);
        await tester.scrollUntilVisible(
          find.text('เติมคำในบริบท').hitTestable(),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('เติมคำในบริบท').hitTestable());
        await _dictationEntryUntil(
          tester,
          () => find
              .byKey(ValueKey('cloze-variant-${variant.name}'))
              .evaluate()
              .isNotEmpty,
        );
        expect(h.provider.requests, isEmpty);
        await tester.tap(find.byKey(ValueKey('cloze-variant-${variant.name}')));
        await _dictationEntryUntil(
          tester,
          () => find.text('Synthetic travel').evaluate().isNotEmpty,
        );
        expect(h.provider.requests, isEmpty);
        expect(
          await tester.runAsync(() => h.storage.count('learning_sessions')),
          0,
        );
        await tester.tap(find.text('Synthetic travel'));
        await _dictationEntryUntil(
          tester,
          () =>
              find.byKey(const ValueKey('cloze-context')).evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        final screen = tester.widget<FillInTheBlanksScreen>(
          find.byType(FillInTheBlanksScreen),
        );
        expect(screen.session.variant, variant);
        expect(screen.languageCode, 'th');
        expect(screen.session.ownerId, configuredOwnerId);
        expect(h.provider.requests, hasLength(1));
        expect(
          await tester.runAsync(() => h.storage.count('learning_sessions')),
          1,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(h.close);
      }
    });
  }

  testWidgets(
    'Cloze null with actual owned words is unavailable rather than empty',
    (tester) async {
      final h = (await tester.runAsync(cloze.ClozeSessionHarness.open))!;
      try {
        final words = await tester.runAsync(
          () => h.repository.listQuizWords(
            ownerId: configuredOwnerId,
            categoryId: configuredCategoryId,
            limit: 100,
          ),
        );
        expect(words, isNotEmpty);
        await _pumpClozeEntry(
          tester,
          h,
          learning: h.useCases(withProvider: false),
        );
        expect(h.provider.requests, isEmpty);
        await tester.scrollUntilVisible(
          find.text('เติมคำในบริบท').hitTestable(),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('เติมคำในบริบท').hitTestable());
        await _dictationEntryUntil(
          tester,
          () => find
              .byKey(const ValueKey('cloze-variant-typed'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('cloze-variant-typed')));
        await _dictationEntryUntil(
          tester,
          () => find.text('Synthetic travel').evaluate().isNotEmpty,
        );
        expect(h.provider.requests, isEmpty);
        await tester.tap(find.text('Synthetic travel'));
        await _dictationEntryUntil(
          tester,
          () => find.byType(SnackBar).evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('ยังเปิดกิจกรรมเติมคำไม่ได้ กรุณาลองใหม่ภายหลัง'),
          findsOneWidget,
        );
        expect(
          find.text('ยังไม่มีประโยคหรือคำที่พร้อมสำหรับรูปแบบนี้'),
          findsNothing,
        );
        expect(find.byType(FillInTheBlanksScreen), findsNothing);
        expect(h.provider.requests, isEmpty);
        expect(
          await tester.runAsync(() => h.storage.count('learning_sessions')),
          0,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(h.close);
      }
    },
  );

  testWidgets(
    'cancelled Cloze variant selection creates no generation or session',
    (tester) async {
      final h = (await tester.runAsync(cloze.ClozeSessionHarness.open))!;
      try {
        await _pumpClozeEntry(tester, h);
        await tester.scrollUntilVisible(
          find.text('เติมคำในบริบท').hitTestable(),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('เติมคำในบริบท').hitTestable());
        await _dictationEntryUntil(
          tester,
          () => find
              .byKey(const ValueKey('cloze-variant-typed'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.text('ยกเลิก'));
        await tester.pumpAndSettle();
        expect(h.provider.requests, isEmpty);
        expect(
          await tester.runAsync(() => h.storage.count('learning_sessions')),
          0,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(h.close);
      }
    },
  );

  for (final phase in ['variant', 'category', 'generation']) {
    testWidgets('external cover burns Cloze launch during $phase', (
      tester,
    ) async {
      final h = (await tester.runAsync(cloze.ClozeSessionHarness.open))!;
      final responseGate = Completer<void>();
      if (phase == 'generation') {
        h.provider.beforeResponse = (_) => responseGate.future;
      }
      try {
        await _pumpClozeEntry(tester, h);
        await tester.scrollUntilVisible(
          find.text('เติมคำในบริบท').hitTestable(),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('เติมคำในบริบท').hitTestable());
        await _dictationEntryUntil(
          tester,
          () => find
              .byKey(const ValueKey('cloze-variant-typed'))
              .evaluate()
              .isNotEmpty,
        );
        if (phase != 'variant') {
          await tester.tap(find.byKey(const ValueKey('cloze-variant-typed')));
          await _dictationEntryUntil(
            tester,
            () => find.text('Synthetic travel').evaluate().isNotEmpty,
          );
        }
        if (phase == 'generation') {
          await tester.tap(find.text('Synthetic travel'));
          await _dictationEntryUntil(
            tester,
            () => h.provider.requests.isNotEmpty,
          );
        }
        final context = phase == 'variant'
            ? tester.element(find.byType(AlertDialog))
            : phase == 'category'
            ? tester.element(find.text('Synthetic travel'))
            : tester.element(find.byType(ChooseModeScreen));
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('External route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        if (phase == 'variant') {
          await tester.tap(find.byKey(const ValueKey('cloze-variant-typed')));
        }
        if (phase == 'category') {
          await tester.tap(find.text('Synthetic travel'));
        }
        if (!responseGate.isCompleted) {
          responseGate.complete();
        }
        await tester.pumpAndSettle();
        expect(find.byType(FillInTheBlanksScreen), findsNothing);
        expect(
          await tester.runAsync(() => h.storage.count('learning_sessions')),
          0,
        );
        expect(h.provider.requests.length, phase == 'generation' ? 1 : 0);
      } finally {
        if (!responseGate.isCompleted) {
          responseGate.complete();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(h.close);
      }
    });
  }

  testWidgets('dictation entry uses the existing quiz feature gate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(),
          featureRegistry: const BuildFieldFeatureRegistry({
            FieldFeature.quiz: FieldFeatureState.hidden,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dictation-entry')), findsNothing);
    expect(find.byKey(const ValueKey('cloze-entry')), findsNothing);
  });

  testWidgets('dictation entry without real owner dependencies fails closed', (
    tester,
  ) async {
    final h = (await tester.runAsync(DictationSessionHarness.open))!;
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            loader: () async => snapshot(),
            learning: h.learning,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('dictation-entry')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('ฟังแล้วพิมพ์คำศัพท์').hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dictation-entry')));
      await tester.pump();
      expect(find.byType(DictationQuizScreen), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        await tester.runAsync(() => h.storage.count('learning_sessions')),
        0,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(h.close);
    }
  });

  for (final empty in [false, true]) {
    testWidgets(
      'dictation selects one actual owned category target (empty=$empty)',
      (tester) async {
        final h = (await tester.runAsync(DictationSessionHarness.open))!;
        try {
          if (empty) {
            await tester.runAsync(
              () =>
                  (h.database.update(h.database.vocabularyWords)..where(
                        (word) => word.ownerId.equals(configuredOwnerId),
                      ))
                      .write(
                        const db.VocabularyWordsCompanion(
                          isDeleted: Value(true),
                        ),
                      ),
            );
          }
          final voice = _DictationEntryVoice();
          await _pumpDictationEntry(tester, h, voice);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('dictation-entry')),
            200,
            scrollable: find.byType(Scrollable).last,
          );
          expect(
            find.text('ฟังแล้วพิมพ์คำศัพท์').hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('dictation-entry')));
          await _dictationEntryUntil(
            tester,
            () => find.text('Synthetic travel').evaluate().isNotEmpty,
          );
          expect(find.text('Synthetic unrelated'), findsNothing);
          expect(
            await tester.runAsync(() => h.storage.count('learning_sessions')),
            0,
          );
          await tester.tap(find.text('Synthetic travel'));
          if (empty) {
            await _dictationEntryUntil(
              tester,
              () => find.byType(SnackBar).evaluate().isNotEmpty,
            );
            expect(find.byType(DictationQuizScreen), findsNothing);
            expect(
              await tester.runAsync(() => h.storage.count('learning_sessions')),
              0,
            );
            expect(voice.requests, isEmpty);
          } else {
            await _dictationEntryUntil(tester, () => voice.requests.isNotEmpty);
            await tester.pumpAndSettle();
            expect(find.byType(DictationQuizScreen), findsOneWidget);
            expect(
              await tester.runAsync(() => h.storage.count('learning_sessions')),
              1,
            );
            final screen = tester.widget<DictationQuizScreen>(
              find.byType(DictationQuizScreen),
            );
            expect(screen.languageCode, 'th');
            expect(screen.session.ownerId, configuredOwnerId);
            expect(
              screen.session.evidenceContentRevision,
              startsWith('local-vocabulary-v1:'),
            );
            expect(voice.requests.single.text, screen.session.word.spelling);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.runAsync(h.close);
        }
      },
    );
  }

  testWidgets(
    'Thai hub reaches actual Dictation at 200 percent on 320 pixels',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = (await tester.runAsync(DictationSessionHarness.open))!;
      try {
        final voice = _DictationEntryVoice();
        await _pumpDictationEntry(tester, h, voice, textScale: 2);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('dictation-entry')),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('ฟังแล้วพิมพ์คำศัพท์').hitTestable(), findsOneWidget);
        expect(find.text('Listen and spell'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('ฟังแล้วพิมพ์คำศัพท์').hitTestable());
        await _dictationEntryUntil(
          tester,
          () => find.text('Synthetic travel').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('Synthetic travel'));
        await _dictationEntryUntil(tester, () => voice.requests.isNotEmpty);
        await tester.pumpAndSettle();
        final screen = tester.widget<DictationQuizScreen>(
          find.byType(DictationQuizScreen),
        );
        expect(screen.languageCode, 'th');
        expect(screen.session.ownerId, configuredOwnerId);
        expect(
          screen.session.evidenceContentRevision,
          startsWith('local-vocabulary-v1:'),
        );
        expect(voice.requests.single.text, screen.session.word.spelling);
        expect(
          await tester.runAsync(() => h.storage.count('learning_sessions')),
          1,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(h.close);
      }
    },
  );

  for (final invalidation in [
    'owner',
    'owner error',
    'owner done',
    'covered',
    'paused',
    'hidden',
    'disposed',
  ]) {
    testWidgets('pending study tap is cancelled on $invalidation', (
      tester,
    ) async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final ownerChanges = StreamController<String?>.broadcast(sync: true);
      addTearDown(() async {
        if (!ownerChanges.isClosed) await ownerChanges.close();
      });
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final navigation = _StudyEntryNavigation();
      final pending = Completer<StudyView>();
      var tapped = false;
      var requestedAfterTap = 0;
      final runtime = _StudyEntryRuntime((ownerId) {
        if (tapped && ownerId == 'local:study-entry-owner') {
          requestedAfterTap++;
          return pending.future;
        }
        return Future.value(
          _studyView(ownerId, eligible: ownerId == 'local:study-entry-owner'),
        );
      });
      await _pumpStudyEntry(
        tester,
        database,
        runtime,
        ownerChanges: ownerChanges.stream,
        visible: visible,
        navigation: navigation,
      );
      ownerChanges.add('local:study-entry-owner');
      await tester.pumpAndSettle();
      expect(find.text('Your study activity'), findsOneWidget);
      tapped = true;
      await tester.tap(find.text('Your study activity'));
      await tester.pump();
      expect(requestedAfterTap, greaterThan(0));
      var expectedPushes = 1;
      switch (invalidation) {
        case 'owner':
          ownerChanges.add('synthetic-next-study-owner');
        case 'owner error':
          ownerChanges.addError(StateError('synthetic owner watch error'));
        case 'owner done':
          unawaited(ownerChanges.close());
        case 'covered':
          unawaited(
            Navigator.of(tester.element(find.byType(ChooseModeScreen))).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other activity')),
              ),
            ),
          );
          expectedPushes++;
        case 'paused':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        case 'hidden':
          visible.value = false;
        case 'disposed':
          await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pumpAndSettle();
      pending.complete(_studyView('local:study-entry-owner', eligible: true));
      await tester.pumpAndSettle();
      expect(navigation.pushes, expectedPushes);
      expect(find.byType(SnackBar), findsNothing);
      if (invalidation == 'paused') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(navigation.pushes, expectedPushes);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final eligible in [false, true]) {
    testWidgets('eager study entry reads without creating facts ($eligible)', (
      tester,
    ) async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final runtime = _StudyEntryRuntime(
        (ownerId) async => _studyView(ownerId, eligible: eligible),
      );
      await _pumpStudyEntry(tester, database, runtime);
      expect(runtime.loads, isNotEmpty);
      expect(
        find.text('Your study activity'),
        eligible ? findsOneWidget : findsNothing,
      );
      expect(find.text('ฝึกคำศัพท์'), findsOneWidget);
      for (final table in [
        'research_consents',
        'experiment_assignments',
        'research_participation_permits',
        'motivation_measurement_runs',
        'motivation_responses',
        'measurement_opportunities',
        'events_v2',
        'outbox_operations',
      ]) {
        final row = await database
            .customSelect('SELECT COUNT(*) AS n FROM $table')
            .getSingle();
        expect(row.read<int>('n'), 0, reason: table);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('late old-owner eligibility cannot reveal a study entry', (
    tester,
  ) async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final oldRead = Completer<StudyView>();
    final runtime = _StudyEntryRuntime(
      (ownerId) => ownerId == 'local:study-entry-owner'
          ? oldRead.future
          : Future.value(_studyView(ownerId, eligible: false)),
    );
    await _pumpStudyEntry(tester, database, runtime);
    expect(runtime.loads, contains('local:study-entry-owner'));
    await database.transaction(() async {
      await (database.update(database.localOwners)
            ..where((row) => row.id.equals('local:study-entry-owner')))
          .write(const db.LocalOwnersCompanion(isActive: Value(false)));
      await database
          .into(database.localOwners)
          .insert(
            db.LocalOwnersCompanion.insert(
              id: 'synthetic-next-study-owner',
              createdAtUtcMs: 1,
            ),
          );
    });
    await tester.pumpAndSettle();
    oldRead.complete(_studyView('local:study-entry-owner', eligible: true));
    await tester.pumpAndSettle();
    expect(runtime.loads, contains('synthetic-next-study-owner'));
    expect(find.text('Your study activity'), findsNothing);
    expect(find.text('Synthetic study mission'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('hub prioritizes due review and displays real queue counts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ChooseModeScreen(loader: () async => snapshot(due: 3))),
    );
    await tester.pumpAndSettle();
    expect(find.text('ทบทวน 3 คำ'), findsOneWidget);
    expect(find.text('ถึงกำหนด 3 คำ • คำที่ควรฝึก 1 คำ'), findsOneWidget);
    expect(find.text('ฝึกคำศัพท์'), findsOneWidget);
    expect(find.text('ฝึกคำแปล แล้วดูคำที่ควรทบทวน'), findsOneWidget);
    expect(find.text('ฝึกจากคลังคำศัพท์'), findsNothing);
  });

  testWidgets(
    'hub prioritizes weaknesses when nothing is due and refreshes on return',
    (tester) async {
      var calls = 0;
      var due = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            loader: () async {
              calls++;
              return snapshot(due: due);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ฝึกคำที่ผิด 1 คำ'), findsOneWidget);
      await tester.tap(find.text('ฝึกคำที่ผิด 1 คำ'));
      await tester.pumpAndSettle();
      expect(find.byType(WeaknessClinicScreen), findsOneWidget);
      due = 2;
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('ทบทวน 2 คำ'), findsOneWidget);
      expect(calls, greaterThanOrEqualTo(3));
    },
  );

  testWidgets(
    'hub recovers from a failed load without inventing queue counts',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            loader: () async {
              if (calls++ == 0) throw StateError('synthetic read failure');
              return snapshot(due: 2);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final error = find.text('โหลดคำแนะนำการฝึกไม่สำเร็จ');
      expect(error, findsOneWidget);
      expect(
        find.ancestor(
          of: error,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('ทบทวน 2 คำ'), findsNothing);
      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();
      expect(find.text('ทบทวน 2 คำ'), findsOneWidget);
    },
  );

  testWidgets('fresh owner sees a quiz recommendation without fake progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(loader: () async => snapshot(empty: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('เริ่มฝึกคำศัพท์'), findsOneWidget);
    expect(find.textContaining('ถึงกำหนด 0 คำ'), findsNothing);
    expect(find.textContaining('คำที่ควรฝึก 0 คำ'), findsNothing);
    expect(find.textContaining('100%'), findsNothing);
  });

  testWidgets('tablet centers the learning actions within 720dp', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(),
          featureRegistry: const BuildFieldFeatureRegistry.allEnabled(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final primaryAction = tester.getRect(find.byType(FilledButton).first);
    expect(primaryAction.width, lessThanOrEqualTo(720));
    expect(primaryAction.center.dx, closeTo(640, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading-only registry does not expose hidden practice modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(due: 3),
          featureRegistry: const BuildFieldFeatureRegistry({
            FieldFeature.reading: FieldFeatureState.enabled,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ทบทวน 3 คำ'), findsNothing);
    expect(find.text('เริ่มฝึกคำศัพท์'), findsNothing);
    expect(find.text('ฝึกคำศัพท์'), findsNothing);
    expect(find.text('ฝึกตามหมวดหมู่'), findsNothing);
    expect(find.text('ทบทวนคำศัพท์ที่ถึงกำหนด'), findsNothing);
    expect(find.text('ภาพรวมการเรียน'), findsNothing);
    expect(find.text('ฝึกจุดอ่อน'), findsNothing);
    expect(find.text('อ่านเรื่องสั้นและจำคำศัพท์'), findsOneWidget);
  });

  testWidgets('nested progress keeps the feature registry closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(due: 3),
          featureRegistry: const BuildFieldFeatureRegistry({
            FieldFeature.mastery: FieldFeatureState.enabled,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ภาพรวมการเรียน'));
    await tester.pumpAndSettle();
    expect(find.byType(MasteryDashboardScreen), findsOneWidget);
    expect(find.text('คำที่ควรฝึกเพิ่ม'), findsNothing);
    expect(find.text('ความสำเร็จ'), findsNothing);
    expect(find.text('ร้านธีม'), findsNothing);
  });

  testWidgets('progress activity explains that it uses saved answers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChooseModeScreen(
          loader: () async => snapshot(),
          featureRegistry: const BuildFieldFeatureRegistry({
            FieldFeature.mastery: FieldFeatureState.enabled,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ดูความก้าวหน้าจากคำตอบที่บันทึกไว้'), findsOneWidget);
  });
}

StudyView _studyView(String ownerId, {required bool eligible}) => StudyView(
  ownerId: ownerId,
  catalog: StudyPresentationCatalog(
    version: 'synthetic-catalog-v1',
    missionId: 'synthetic-mission',
    titles: const {'th': 'ภารกิจสังเคราะห์', 'en': 'Synthetic study mission'},
    descriptions: const {
      'th': 'สำหรับทดสอบเท่านั้น',
      'en': 'Test fixture only',
    },
    configuration: QuizConfiguration.category(limit: 1),
  ),
  phase: eligible ? StudyPhase.baseline : StudyPhase.unavailable,
);

final class _StudyEntryRuntime extends Fake implements StudyRuntime {
  _StudyEntryRuntime(this.read);
  final Future<StudyView> Function(String ownerId) read;
  final loads = <String>[];

  @override
  Future<StudyView> load(String ownerId) {
    loads.add(ownerId);
    return read(ownerId);
  }
}

final class _StudyEntryGuestService extends Fake
    implements GuestSessionService {}

final class _StudyEntryNavigation extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

Future<void> _pumpStudyEntry(
  WidgetTester tester,
  db.AppDatabase database,
  StudyRuntime runtime, {
  Stream<String?>? ownerChanges,
  ValueNotifier<bool>? visible,
  NavigatorObserver? navigation,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'study-entry-owner',
    nowUtc: () => DateTime.utc(2026, 10, 29),
  );
  await owners.getOrCreateActiveOwner();
  final dependencies = AppDependencies(
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _StudyEntryGuestService(),
    database: database,
    localOwners: owners,
    progress: ProgressUseCases(
      owners: owners,
      queries: DriftProgressQueries(database),
      nowUtc: () => DateTime.utc(2026, 10, 29),
    ),
    studyRuntime: runtime,
  );
  final screen = ChooseModeScreen(
    loader: () async => snapshot(),
    ownerChanges: ownerChanges,
  );
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: dependencies,
      child: MaterialApp(
        navigatorObservers: [?navigation],
        home: visible == null
            ? screen
            : ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (_, isVisible, child) =>
                    Visibility.maintain(visible: isVisible, child: child!),
                child: screen,
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ProgressSnapshot snapshot({int due = 0, bool empty = false}) =>
    ProgressSnapshot(
      sampleSize: empty ? 0 : 3,
      correctCount: empty ? 0 : 1,
      wrongCount: empty ? 0 : 2,
      accuracy: empty ? null : 1 / 3,
      totalXp: 0,
      completedSessions: 0,
      streakDays: 0,
      dueReviewCount: due,
      masteredWordCount: 0,
      achievementCount: 0,
      gameLevel: 1,
      skills: [],
      weaknesses: empty
          ? []
          : const [
              WeaknessEvidence(
                wordId: 'synthetic-1',
                spelling: 'station',
                meaning: 'สถานี',
                sampleSize: 3,
                incorrectCount: 2,
                errorRate: 2 / 3,
                dueAtUtc: null,
              ),
            ],
      recommendations: [],
    );

final class _DictationEntryVoice implements VoiceProvider {
  final requests = <VoiceRequest>[];
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}

Future<void> _pumpDictationEntry(
  WidgetTester tester,
  DictationSessionHarness h,
  _DictationEntryVoice voice, {
  double textScale = 1,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final dependencies = AppDependencies(
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _StudyEntryGuestService(),
    database: h.database,
    localOwners: h.storage.owners,
    learning: h.learning,
    progress: ProgressUseCases(
      owners: h.storage.owners,
      queries: DriftProgressQueries(h.database),
      nowUtc: () => h.now,
    ),
    vocabulary: VocabularyUseCases(
      owners: h.storage.owners,
      vocabulary: DriftVocabularyRepository(h.database),
      generateId: () => 'synthetic-entry-id',
      nowUtc: () => h.now,
    ),
    voice: VoiceUseCases(voice),
  );
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: dependencies,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ChooseModeScreen(loader: () async => snapshot()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump();
}

Future<void> _dictationEntryUntil(
  WidgetTester tester,
  bool Function() ready,
) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Dictation entry did not reach expected UI state',
  );
}

Future<void> _pumpClozeEntry(
  WidgetTester tester,
  cloze.ClozeSessionHarness h, {
  LearningUseCases? learning,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final dependencies = AppDependencies(
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _StudyEntryGuestService(),
    database: h.database,
    localOwners: h.storage.owners,
    learning: learning ?? h.learning,
    progress: ProgressUseCases(
      owners: h.storage.owners,
      queries: DriftProgressQueries(h.database),
      nowUtc: () => h.now,
    ),
    vocabulary: VocabularyUseCases(
      owners: h.storage.owners,
      vocabulary: DriftVocabularyRepository(h.database),
      generateId: () => 'synthetic-cloze-entry',
      nowUtc: () => h.now,
    ),
  );
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: dependencies,
      child: MaterialApp(
        home: ChooseModeScreen(loader: () async => snapshot()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => dependencies.localOwners!.getOrCreateActiveOwner(),
  );
  await tester.pump();
}
