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
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  for (final collapseTabs in [false, true]) {
    testWidgets(
      collapseTabs
          ? 'account rereads saved metrics when feature collapse activates it'
          : 'account tab rereads saved practice metrics on every return',
      (tester) async {
        final database = AppDatabase(NativeDatabase.memory());
        var now = DateTime.now().toUtc();
        var nextId = 0;
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'synthetic-profile-owner',
          nowUtc: () => now,
        );
        final vocabulary = VocabularyUseCases(
          owners: owners,
          vocabulary: DriftVocabularyRepository(database),
          generateId: () => 'synthetic-vocabulary-${++nextId}',
          nowUtc: () => now,
        );
        final learning = LearningUseCases(
          owners: owners,
          repository: DriftLearningRepository(database),
          generateId: () => 'synthetic-learning-${++nextId}',
          nowUtc: () => now,
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'profile-refresh',
          ),
        );
        final progress = ProgressUseCases(
          owners: owners,
          queries: DriftProgressQueries(database),
          nowUtc: () => now,
        );
        final dependencies = AppDependencies(
          runtimeStatus: const AppRuntimeStatus(
            localData: RuntimeAvailability.ready,
            firebase: RuntimeAvailability.unavailable,
            supabase: RuntimeAvailability.unavailable,
            backends: RuntimeAvailability.unavailable,
          ),
          config: null,
          guestSessionService: _Guest(),
          database: database,
          localOwners: owners,
          vocabulary: vocabulary,
          learning: learning,
          progress: progress,
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (_) async => 1,
        );
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        try {
          final ownerId = (await tester.runAsync(() async {
            final category = await vocabulary.createCategory('ชุดทดสอบโปรไฟล์');
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
                    id: 'synthetic-profile-due',
                    ownerId: owner.id,
                    wordId: word.id,
                    dueAtUtcMs: now
                        .subtract(const Duration(days: 1))
                        .millisecondsSinceEpoch,
                    algorithmVersion: 1,
                  ),
                );
            return owner.id;
          }))!;
          await tester.pumpWidget(
            AppDependenciesScope(
              dependencies: dependencies,
              child: const MaterialApp(home: MainNavigationScreen()),
            ),
          );
          await _pumpUntil(
            tester,
            () => _metricFinder(
              'คะแนนประสบการณ์',
              offstage: true,
            ).evaluate().isNotEmpty,
          );
          final profileState = tester.state(
            find.byType(ProfileSettingsScreen, skipOffstage: false),
          );
          expect(_metric(tester, 'คะแนนประสบการณ์', offstage: true), '0');
          expect(_metric(tester, 'คำตอบที่ใช้คำนวณ', offstage: true), '0');

          for (
            var completed = 1;
            completed <= (collapseTabs ? 1 : 2);
            completed++
          ) {
            await _practiceDue(tester);
            final answers = (await tester.runAsync(
              () => database.select(database.answerAttempts).get(),
            ))!;
            expect(answers, hasLength(completed));
            expect(
              answers.every(
                (answer) => answer.ownerId == ownerId && answer.isCorrect,
              ),
              isTrue,
            );
            final sessions = (await tester.runAsync(
              () => database.select(database.learningSessions).get(),
            ))!;
            expect(
              sessions.where((session) => session.state == 'completed'),
              hasLength(completed),
            );
            final persisted = (await tester.runAsync(
              () => DriftProgressQueries(
                database,
              ).load(ownerId: ownerId, nowUtc: now),
            ))!;
            expect(persisted.totalXp, completed);
            expect(persisted.sampleSize, completed);

            if (collapseTabs) {
              await tester.tap(find.byType(NavigationDestination).at(2));
              await tester.pumpAndSettle();
              expect(find.byType(MasteryDashboardScreen), findsOneWidget);
              expect(
                tester
                    .widget<NavigationBar>(find.byType(NavigationBar))
                    .selectedIndex,
                2,
              );
              expect(_metric(tester, 'คะแนนประสบการณ์', offstage: true), '0');
              final collapsedDependencies = AppDependencies(
                runtimeStatus: dependencies.runtimeStatus,
                config: dependencies.config,
                guestSessionService: dependencies.guestSessionService,
                fieldFeatures: const BuildFieldFeatureRegistry({
                  FieldFeature.mastery: FieldFeatureState.enabled,
                }),
                database: database,
                localOwners: owners,
                vocabulary: vocabulary,
                learning: learning,
                progress: progress,
              );
              expect(
                collapsedDependencies.progress,
                same(dependencies.progress),
              );
              expect(
                collapsedDependencies.localOwners,
                same(dependencies.localOwners),
              );
              await tester.pumpWidget(
                AppDependenciesScope(
                  dependencies: collapsedDependencies,
                  child: const MaterialApp(home: MainNavigationScreen()),
                ),
              );
              expect(find.byType(NavigationDestination), findsNWidgets(2));
              expect(
                tester
                    .widget<NavigationBar>(find.byType(NavigationBar))
                    .selectedIndex,
                1,
              );
              expect(find.byType(ProfileSettingsScreen), findsOneWidget);
              await _pumpUntil(
                tester,
                () =>
                    _metricFinder('คะแนนประสบการณ์').evaluate().isNotEmpty &&
                    _metric(tester, 'คะแนนประสบการณ์') == '1',
              );
              expect(_metric(tester, 'คะแนนประสบการณ์'), '1');
              expect(_metric(tester, 'คำตอบที่ใช้คำนวณ'), '1');
              continue;
            }

            await tester.tap(find.byType(NavigationDestination).last);
            await _pumpUntil(
              tester,
              () => _metricFinder('คะแนนประสบการณ์').evaluate().isNotEmpty,
            );
            await tester.pumpAndSettle();
            expect(
              tester.state(find.byType(ProfileSettingsScreen)),
              same(profileState),
            );
            expect(_metric(tester, 'คะแนนประสบการณ์'), '$completed');
            expect(_metric(tester, 'คำตอบที่ใช้คำนวณ'), '$completed');
            if (completed == 1) {
              now = now.add(const Duration(days: 365));
              await tester.tap(find.byType(NavigationDestination).first);
              await tester.pump();
            }
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
          await tester.runAsync(database.close);
          await tester.pump(const Duration(milliseconds: 1));
          messenger.setMockMethodCallHandler(
            const MethodChannel('flutter_tts'),
            null,
          );
        }
      },
    );
  }

  testWidgets('unrelated profile rebuilds do not duplicate its progress read', (
    tester,
  ) async {
    final revision = ValueNotifier(0);
    var reads = 0;
    Future<ProgressSnapshot> load() async {
      reads++;
      return _empty;
    }

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: revision,
            builder: (_, _, _) => ProfileSettingsScreen(loader: load),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 1);
      final state = tester.state(find.byType(ProfileSettingsScreen));
      for (var value = 1; value <= 3; value++) {
        revision.value = value;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ProfileSettingsScreen)), same(state));
        expect(reads, 1);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      revision.dispose();
    }
  });
}

Finder _metricFinder(String label, {bool offstage = false}) => find.descendant(
  of: find.byType(ProfileSettingsScreen, skipOffstage: !offstage),
  matching: find.widgetWithText(ListTile, label, skipOffstage: !offstage),
  skipOffstage: !offstage,
);

String? _metric(WidgetTester tester, String label, {bool offstage = false}) =>
    (tester.widget<ListTile>(_metricFinder(label, offstage: offstage)).trailing
            as Text)
        .data;

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var index = 0; index < 80; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
  }
  fail(
    'Timed out waiting for profile refresh journey: ${tester.takeException()}',
  );
}

Future<void> _practiceDue(WidgetTester tester) async {
  final due = find.widgetWithText(FilledButton, 'ทบทวนคำนี้');
  await _pumpUntil(tester, () => due.evaluate().isNotEmpty);
  await tester.tap(due);
  await _pumpUntil(
    tester,
    () => find.byType(SrsFlashcardsScreen).evaluate().isNotEmpty,
  );
  await _pumpUntil(tester, () => find.text('ดูคำแปล').evaluate().isNotEmpty);
  await tester.tap(find.text('ดูคำแปล'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('จำได้แล้ว'));
  await _pumpUntil(tester, () => find.text('บันทึกแล้ว').evaluate().isNotEmpty);
  await tester.tap(find.text('จบการทบทวน'));
  await _pumpUntil(
    tester,
    () => find.text('กลับไปเลือกกิจกรรม').evaluate().isNotEmpty,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('กลับไปเลือกกิจกรรม'));
  await _pumpUntil(
    tester,
    () => find.byType(NavigationBar).evaluate().isNotEmpty,
  );
}

final class _Guest extends Fake implements GuestSessionService {}

const _empty = ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);
