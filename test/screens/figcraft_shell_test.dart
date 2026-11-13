import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

final class _GuestSession extends Fake implements GuestSessionService {}

void main() {
  late AppDatabase database;
  late AppDependencies dependencies;
  late VocabularyUseCases vocabulary;
  late DriftLocalOwnerRepository owners;
  late DateTime now;
  var nextId = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    nextId = 0;
    now = DateTime.now().toUtc();
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-figcraft-owner',
      nowUtc: () => now,
    );
    vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'synthetic-${++nextId}',
      nowUtc: () => now,
    );
    dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSession(),
      vocabulary: vocabulary,
      learning: LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'synthetic-learning-${++nextId}',
        nowUtc: () => now,
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      ),
      progress: ProgressUseCases(
        owners: owners,
        queries: DriftProgressQueries(database),
        nowUtc: () => now,
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: const MaterialApp(home: MainNavigationScreen()),
      ),
    );
  }

  testWidgets('library shortcut opens the existing tab and retains its place', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (var index = 0; index < 24; index++) {
        await vocabulary.createCategory(
          'ชุดสังเคราะห์ ${index.toString().padLeft(2, '0')}',
        );
      }
    });
    await pumpShell(tester);
    await _pumpUntil(tester, find.text('เพิ่มคำศัพท์เพื่อเริ่มฝึก'));
    await tester.tap(find.widgetWithText(FilledButton, 'เลือกชุดคำศัพท์'));
    await _pumpUntil(tester, find.text('ชุดสังเคราะห์ 00'));

    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(find.byType(CategoriesPage), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await tester.scrollUntilVisible(find.text('ชุดสังเคราะห์ 20'), 300);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NavigationDestination).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'เลือกชุดคำศัพท์'));
    await tester.pumpAndSettle();

    expect(find.text('ชุดสังเคราะห์ 20').hitTestable(), findsOneWidget);
    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('due review returns to the same shell with its saved result', (
    tester,
  ) async {
    final wordId = (await tester.runAsync(() async {
      final category = await vocabulary.createCategory('ชุดเดินทางสังเคราะห์');
      final word = await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'station',
          meaning: 'สถานี',
          partOfSpeech: 'noun',
        ),
      );
      final owner = await owners.getOrCreateActiveOwner();
      await database
          .into(database.srsStates)
          .insert(
            SrsStatesCompanion.insert(
              id: 'synthetic-due',
              ownerId: owner.id,
              wordId: word.id,
              dueAtUtcMs: now
                  .subtract(const Duration(days: 1))
                  .millisecondsSinceEpoch,
              algorithmVersion: 1,
            ),
          );
      return word.id;
    }))!;
    await pumpShell(tester);
    await _pumpUntil(tester, find.widgetWithText(FilledButton, 'ทบทวนคำนี้'));
    expect(find.text('station'), findsOneWidget);
    expect(find.text('สถานี'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'ทบทวนคำนี้'));
    await _pumpUntil(tester, find.byType(SrsFlashcardsScreen));
    await _pumpUntil(tester, find.text('ดูคำแปล'));
    await tester.tap(find.text('ดูคำแปล'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('จำได้แล้ว'));
    await _pumpUntil(tester, find.text('บันทึกแล้ว'));
    await tester.tap(find.text('จบการทบทวน'));
    await _pumpUntil(tester, find.text('ทบทวนครบแล้ว'));
    await tester.pumpAndSettle();

    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(find.byType(SrsFlashcardsScreen), findsNothing);
    final attempts = await tester.runAsync(
      () => database.select(database.answerAttempts).get(),
    );
    final sessions = await tester.runAsync(
      () => database.select(database.learningSessions).get(),
    );
    expect(attempts, hasLength(1));
    expect(attempts!.single.wordId, wordId);
    expect(sessions!.single.state, 'completed');
    expect(sessions.single.correctCount, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
    await tester.pump(const Duration(milliseconds: 1));
  });
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 60; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}
