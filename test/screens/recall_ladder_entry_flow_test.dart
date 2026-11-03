import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/matching_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_recall_ladder_reader.dart';
import 'package:vocab_learning_app/features/learning/domain/recall_ladder.dart';
import 'package:vocab_learning_app/features/learning/presentation/recall_ladder_panel.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/presentation/learning_pack_catalog_screen.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/matching_quiz_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/select_category_for_quiz.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/configured_quiz_harness.dart';
import '../support/motivation_presentation_io.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets(
    'empty library opens starter preview and installs only on confirmation',
    (tester) async {
      final f = await motivationPresentationIo(tester, _Fixture.open);
      try {
        await motivationPresentationIo(
          tester,
          () => f.h.database.customStatement(
            'DELETE FROM vocabulary_words WHERE owner_id = ?',
            [configuredOwnerId],
          ),
        );
        final before = await motivationPresentationIo(tester, f.h.snapshot);
        await tester.pumpWidget(f.app());
        final starter = find.byKey(const ValueKey('recall-ladder-starter'));
        await _until(tester, () => starter.evaluate().isNotEmpty);
        await tester.ensureVisible(starter);
        await tester.tap(starter);
        final confirm = find.byKey(const ValueKey('pack-confirm-install'));
        await _until(
          tester,
          () =>
              confirm.evaluate().isNotEmpty &&
              tester.widget<FilledButton>(confirm).onPressed != null,
        );
        expect(await motivationPresentationIo(tester, f.h.snapshot), before);
        Navigator.of(tester.element(confirm)).pop();
        await _until(tester, () => starter.evaluate().isNotEmpty);
        expect(await motivationPresentationIo(tester, f.h.snapshot), before);
        await tester.ensureVisible(starter);
        await tester.tap(starter);
        await _until(
          tester,
          () =>
              confirm.evaluate().isNotEmpty &&
              tester.widget<FilledButton>(confirm).onPressed != null,
        );
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await _until(
          tester,
          () => find.text('ติดตั้งแพ็กบทเรียนแล้ว').evaluate().isNotEmpty,
        );
        expect(
          await motivationPresentationIo(
            tester,
            () => f.h.count('learning_pack_versions'),
          ),
          1,
        );
        expect(
          await motivationPresentationIo(
            tester,
            () => f.h.count('vocabulary_words'),
          ),
          greaterThan(1),
        );
        expect(
          await motivationPresentationIo(
            tester,
            () => f.h.count('learning_sessions'),
          ),
          0,
        );
      } finally {
        await closeMotivationPresentation(tester, f.close);
      }
    },
  );

  for (final stage in RecallLadderStage.values) {
    testWidgets(
      'actual recall ${stage.name} entry preserves its scope and returns to the hub',
      (tester) async {
        final f = await motivationPresentationIo(tester, _Fixture.open);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(f.app());
          await _ready(tester, 'journey');
          final details = find.byKey(const ValueKey('recall-ladder-details'));
          await tester.ensureVisible(details);
          await tester.tap(details);
          await tester.pumpAndSettle();
          final button = find.byKey(ValueKey('recall-ladder-${stage.name}'));
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
          expect(
            tester.getSemantics(button).label,
            contains(recallLadderStageLabel(stage)),
          );
          if (stage == RecallLadderStage.speaking) {
            expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
            expect(
              await motivationPresentationIo(
                tester,
                () => f.h.count('learning_sessions'),
              ),
              0,
            );
            return;
          }
          expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
          await tester.tap(button.hitTestable());
          if (stage == RecallLadderStage.cloze) {
            final variant = find.byKey(const ValueKey('cloze-variant-typed'));
            await _until(tester, () => variant.evaluate().isNotEmpty);
            await tester.tap(variant);
          }
          final page = switch (stage) {
            RecallLadderStage.exposure => find.byType(SrsFlashcardsScreen),
            RecallLadderStage.recognition => find.byType(QuizScreen),
            RecallLadderStage.matching => find.byType(MatchingQuizScreen),
            RecallLadderStage.typedRecall => find.byType(
              LearningPackCatalogScreen,
            ),
            RecallLadderStage.cloze ||
            RecallLadderStage.dictation => find.byType(SelectCategoryForQuiz),
            RecallLadderStage.speaking => throw StateError(
              'Unavailable speaking cannot navigate',
            ),
          };
          await _until(tester, () => page.evaluate().isNotEmpty);
          if (stage == RecallLadderStage.exposure) {
            await _until(
              tester,
              () => find.byKey(const Key('srs-card')).evaluate().isNotEmpty,
            );
            final screen = tester.widget<SrsFlashcardsScreen>(page);
            expect(screen.sourceWordIds, [configuredWordIds.last]);
            expect(screen.expectedOwnerId, configuredOwnerId);
          } else if (stage == RecallLadderStage.recognition) {
            final screen = tester.widget<QuizScreen>(page);
            expect(screen.wordIds, [configuredWordIds.last]);
            expect(screen.expectedOwnerId, configuredOwnerId);
          } else if (stage == RecallLadderStage.matching) {
            await _until(
              tester,
              () => find
                  .byKey(const ValueKey('matching-word-0'))
                  .evaluate()
                  .isNotEmpty,
            );
            expect(
              tester.widget<MatchingQuizScreen>(page).expectedOwnerId,
              configuredOwnerId,
            );
          }
          Navigator.of(tester.element(page)).pop();
          await _until(tester, () => page.evaluate().isEmpty);
          await tester.scrollUntilVisible(
            find.text('วันนี้อยากฝึกอะไร'),
            -300,
            scrollable: find
                .descendant(
                  of: find.byType(ChooseModeScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await _ready(tester, 'journey');
          expect(page, findsNothing);
          expect(find.byType(ChooseModeScreen), findsOneWidget);
          expect(
            await motivationPresentationIo(
              tester,
              () => f.h.count('answer_attempts'),
            ),
            0,
          );
          expect(
            (await motivationPresentationIo(tester, f.h.researchCounts)).values,
            everyElement(0),
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await closeMotivationPresentation(tester, f.close);
        }
      },
    );
  }

  testWidgets(
    'actual ChooseMode recommendation is a pure read and opens the current word in SRS',
    (tester) async {
      final f = await motivationPresentationIo(tester, _Fixture.open);
      try {
        final before = await motivationPresentationIo(tester, f.h.snapshot);
        await tester.pumpWidget(f.app());
        await _ready(tester, 'journey');
        expect(find.byType(RecallLadderPanel), findsOneWidget);
        expect(find.text('แนะนำ: อ่านคำและตัวอย่าง'), findsOneWidget);
        expect(await motivationPresentationIo(tester, f.h.snapshot), before);

        final suggested = find.byKey(const ValueKey('recall-ladder-suggested'));
        expect(suggested.hitTestable(), findsOneWidget);
        expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
        expect(
          find.widgetWithText(OutlinedButton, 'เริ่มฝึกคำศัพท์'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('recall-ladder-dictation')),
          findsNothing,
        );
        await tester.ensureVisible(suggested);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.tap(suggested.hitTestable());
        await _until(
          tester,
          () => find.byKey(const Key('srs-card')).evaluate().isNotEmpty,
        );
        expect(find.byType(SrsFlashcardsScreen), findsOneWidget);
        final screen = tester.widget<SrsFlashcardsScreen>(
          find.byType(SrsFlashcardsScreen),
        );
        expect(screen.sourceWordIds, [configuredWordIds.last]);
        expect(screen.expectedOwnerId, configuredOwnerId);
        expect(find.text('journey'), findsOneWidget);
        final sessions = await motivationPresentationIo(
          tester,
          () => f.h.database
              .customSelect('SELECT * FROM learning_sessions')
              .get(),
        );
        expect(sessions, hasLength(1));
        expect(sessions.single.read<String>('owner_id'), configuredOwnerId);
        expect(sessions.single.read<String>('activity_type'), 'srsReview');
        expect(
          await motivationPresentationIo(
            tester,
            () => f.h.count('answer_attempts'),
          ),
          0,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await closeMotivationPresentation(tester, f.close);
      }
    },
  );

  testWidgets(
    'actual SQL owner A-B-A retires the old ChooseMode recommendation callback without writes',
    (tester) async {
      final f = await motivationPresentationIo(tester, _Fixture.open);
      try {
        await tester.pumpWidget(f.app());
        await _ready(tester, 'journey');
        final retained = tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('recall-ladder-suggested')),
            )
            .onPressed!;

        await motivationPresentationIo(
          tester,
          () => f.switchOwner(configuredOtherOwnerId),
        );
        await _ready(tester, 'unrelated');
        await motivationPresentationIo(
          tester,
          () => f.switchOwner(configuredOwnerId),
        );
        await _ready(tester, 'journey');
        final before = await motivationPresentationIo(tester, f.h.snapshot);

        retained();
        for (var frame = 0; frame < 8; frame++) {
          await _flush(tester);
        }
        expect(find.byType(SrsFlashcardsScreen), findsNothing);
        expect(find.byType(ChooseModeScreen), findsOneWidget);
        expect(find.text('คำอ้างอิง: journey'), findsOneWidget);
        expect(await motivationPresentationIo(tester, f.h.snapshot), before);
        expect(
          await motivationPresentationIo(
            tester,
            () => f.h.count('learning_sessions'),
          ),
          0,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await closeMotivationPresentation(tester, f.close);
      }
    },
  );
}

Future<void> _ready(WidgetTester tester, String word) => _until(
  tester,
  () =>
      find.text('คำอ้างอิง: $word').evaluate().isNotEmpty &&
      find
          .byKey(const ValueKey('recall-ladder-suggested'))
          .evaluate()
          .isNotEmpty &&
      tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('recall-ladder-suggested')),
              )
              .onPressed !=
          null,
);

Future<void> _flush(WidgetTester tester) async {
  await motivationPresentationDeadline(
    tester,
    'recall-entry/frame',
    () => tester.pump(const Duration(milliseconds: 16)),
  );
  await motivationPresentationDeadline(
    tester,
    'recall-entry/io',
    () => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    ),
  );
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 200; frame++) {
    await _flush(tester);
    if (ready()) return;
  }
  fail(
    'Actual ChooseMode recall recommendation or SRS route did not become ready',
  );
}

final class _Fixture {
  _Fixture(this.h, this.dependencies);
  final ConfiguredQuizHarness h;
  final AppDependencies dependencies;

  static Future<_Fixture> open() async {
    final h = await ConfiguredQuizHarness.open();
    final repository = DriftLearningRepository(
      h.database,
      ownerWrites: h.ownerWrites,
    );
    var ids = 0;
    return _Fixture(
      h,
      AppDependencies(
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: _NoGuest(),
        database: h.database,
        localOwners: h.owners,
        vocabulary: VocabularyUseCases(
          owners: h.owners,
          vocabulary: DriftVocabularyRepository(h.database),
          generateId: () => 'synthetic-recall-vocabulary-${++ids}',
          nowUtc: () => h.now,
        ),
        matching: MatchingUseCases(
          repository: DriftMatchingRepository(repository),
          generateId: () => 'synthetic-recall-matching-${++ids}',
          nowUtc: () => h.now,
          buildInfo: const AppBuildInfo(
            version: 'synthetic',
            buildId: 'synthetic-recall-entry',
          ),
        ),
        learningPacks: LearningPackUseCases(
          repository: DriftLearningPackRepository(
            database: h.database,
            ownerWrites: h.ownerWrites,
          ),
          generateId: () => 'synthetic-recall-pack-${++ids}',
          nowUtc: () => h.now,
        ),
        learning: LearningUseCases(
          owners: h.owners,
          repository: repository,
          generateId: () => 'synthetic-recall-entry-${++ids}',
          nowUtc: () => h.now,
          buildInfo: const AppBuildInfo(
            version: 'synthetic',
            buildId: 'synthetic-recall-entry',
          ),
        ),
        progress: ProgressUseCases(
          owners: h.owners,
          queries: DriftProgressQueries(h.database),
          nowUtc: () => h.now,
        ),
        recallLadder: DriftRecallLadderReader(
          database: h.database,
          ownerWrites: h.ownerWrites,
        ),
      ),
    );
  }

  Future<void> switchOwner(String ownerId) async {
    await h.switchOwner(ownerId);
    h.database.notifyUpdates({TableUpdate.onTable(h.database.localOwners)});
  }

  Future<void> close() async {
    await dependencies.learningPacks!.dispose();
    await h.close();
  }

  Widget app() => AppDependenciesScope(
    dependencies: dependencies,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: const ChooseModeScreen(),
    ),
  );
}

final class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('Synthetic recall entry must not authenticate');
}
