import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/accessibility/presentation/accessibility_scope.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_mixed_review_controller.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_mixed_review_prompt_catalog.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_recovery_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_session_plan.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_mixed_review_screen.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  late _MixedReviewFixture fixture;

  setUp(() async {
    fixture = await _MixedReviewFixture.create();
  });

  tearDown(() => fixture.close());

  testWidgets('playful typed prompt renders and submits canonical evidence', (
    tester,
  ) async {
    final harness = await _startHarness(tester, fixture, itemCount: 1);
    await tester.pumpWidget(harness.app());
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey<String>('mixed-review-typed-input'))
          .evaluate()
          .isNotEmpty,
    );

    expect(find.text('ภารกิจทบทวน'), findsOneWidget);
    expect(find.text('Playful Quest'), findsOneWidget);
    expect(find.text('พิมพ์จากความจำ'), findsOneWidget);
    expect(find.text('สถานี'), findsOneWidget);
    expect(find.text('พิมพ์คำศัพท์ที่ตรงกับความหมายนี้'), findsOneWidget);
    expect(harness.host.recordCalls, 0);
    expect(await _readAttempts(tester, fixture), isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey<String>('mixed-review-typed-input')),
      'station',
    );
    await tester.pump();
    final submit = find.byKey(const ValueKey<String>('mixed-review-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    expect(submit.hitTestable(), findsOneWidget);
    await tester.tap(submit);
    await tester.pump();
    await _pumpUntil(tester, () => harness.host.committedCalls == 1);
    await _pumpUntil(
      tester,
      () =>
          harness.host.committedCalls == 1 &&
          find
              .byKey(const ValueKey<String>('mixed-review-next'))
              .evaluate()
              .isNotEmpty,
      describeFailure: () =>
          'recordCalls=${harness.host.recordCalls}, '
          'committedCalls=${harness.host.committedCalls}, '
          'checkpoint=${harness.recovery.currentRun?.state.phase.name}, '
          'retry=${find.byKey(const ValueKey<String>('current-evidence-retry')).evaluate().length}',
    );

    expect(harness.host.recordCalls, 1);
    expect(harness.host.occurrenceModes, <LessonMode>[LessonMode.typedRecall]);
    final attempt = (await _readAttempts(tester, fixture)).single;
    expect(attempt.wordId, 'word:station');
    expect(attempt.attemptNumber, 1);
    expect(attempt.isCorrect, isTrue);
    expect(
      find.byKey(const ValueKey<String>('mixed-review-next')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('mixed-review-support')),
      findsNothing,
    );
  });

  testWidgets('prompt card uses the paired tertiary container color tokens', (
    tester,
  ) async {
    final harness = await _startHarness(tester, fixture, itemCount: 1);
    await tester.pumpWidget(harness.app());
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey<String>('mixed-review-typed-input'))
          .evaluate()
          .isNotEmpty,
    );

    final prompt = find.byKey(const ValueKey<String>('mixed-review-prompt'));
    final promptCard = find.ancestor(
      of: prompt,
      matching: find.byType(DecoratedBox),
    );
    expect(promptCard, findsOneWidget);

    final decoration = tester.widget<DecoratedBox>(promptCard).decoration;
    expect(decoration, isA<BoxDecoration>());
    final boxDecoration = decoration as BoxDecoration;
    final colors = Theme.of(tester.element(prompt)).colorScheme;
    expect(boxDecoration.gradient, isNull);
    expect(boxDecoration.color, colors.tertiaryContainer);
    expect(
      tester.widget<Text>(prompt).style?.color,
      colors.onTertiaryContainer,
    );
  });

  testWidgets('supportive copy appears only after wrong evidence commits', (
    tester,
  ) async {
    final commitGate = Completer<void>();
    final harness = await _startHarness(
      tester,
      fixture,
      itemCount: 5,
      recordGate: commitGate,
    );
    final host = harness.host;
    await tester.pumpWidget(harness.app());
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey<String>('mixed-review-typed-input'))
          .evaluate()
          .isNotEmpty,
    );

    const supportLead =
        'คำนี้ยังไม่ผ่านในครั้งนี้ เดี๋ยวระบบจะช่วยทบทวนอีกครั้งโดยไม่ลดความคืบหน้าเดิม';
    expect(find.textContaining(supportLead), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('mixed-review-typed-input')),
      'wrong-answer',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('mixed-review-submit')));
    await _pumpUntil(tester, () => host.recordCalls == 1);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('mixed-review-saving')),
      findsOneWidget,
    );
    expect(find.textContaining(supportLead), findsNothing);
    expect(host.committedCalls, 0);

    commitGate.complete();
    await _pumpUntil(tester, () => host.committedCalls == 1);
    await _pumpUntil(
      tester,
      () =>
          host.committedCalls == 1 &&
          find
              .byKey(const ValueKey<String>('mixed-review-support'))
              .evaluate()
              .isNotEmpty,
    );

    final attempt = (await _readAttempts(tester, fixture)).single;
    expect(attempt.isCorrect, isFalse);
    expect(
      find.byKey(const ValueKey<String>('mixed-review-support')),
      findsOneWidget,
    );
    expect(find.textContaining(supportLead), findsOneWidget);
    expect(find.textContaining('จะกลับมาอีกครั้ง'), findsOneWidget);
  });

  testWidgets(
    'flashcard repair reveal and continue create no answer evidence',
    (tester) async {
      final harness = await _startHarness(
        tester,
        fixture,
        itemCount: 5,
        lexicalWords: const <VocabularyWord>[],
      );
      await tester.pumpWidget(harness.app());
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey<String>('mixed-review-typed-input'))
            .evaluate()
            .isNotEmpty,
      );

      await _submitTyped(tester, harness.host, 'wrong-answer');
      for (final answerAndPrompt in <(String, String)>[
        ('ticket', 'ตั๋ว'),
        ('platform', 'ชานชาลา'),
        ('journey', 'การเดินทาง'),
      ]) {
        await _goNext(tester, expectedPrompt: answerAndPrompt.$2);
        await _submitTyped(tester, harness.host, answerAndPrompt.$1);
      }
      await _goNext(
        tester,
        expectedKey: const ValueKey<String>('mixed-review-flashcard-reveal'),
      );

      expect(
        find.byKey(const ValueKey<String>('mixed-review-repair-badge')),
        findsOneWidget,
      );
      expect(find.text('การ์ดช่วยจำ'), findsOneWidget);
      expect(find.text('station'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('mixed-review-flashcard-reveal')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('mixed-review-flashcard-answer')),
        findsNothing,
      );
      expect(harness.host.recordCalls, 4);
      expect(await _readAttempts(tester, fixture), hasLength(4));

      final reveal = find.byKey(
        const ValueKey<String>('mixed-review-flashcard-reveal'),
      );
      await tester.ensureVisible(reveal);
      await tester.pump();
      await tester.tap(reveal);
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('mixed-review-flashcard-answer')),
        findsOneWidget,
      );
      expect(find.text('สถานี'), findsOneWidget);

      final continueButton = find.byKey(
        const ValueKey<String>('mixed-review-flashcard-continue'),
      );
      await tester.ensureVisible(continueButton);
      await tester.pump();
      await tester.tap(continueButton);
      await _pumpUntil(
        tester,
        () => find.text('ทบทวนคำนี้แล้ว ไปต่อได้เลย').evaluate().isNotEmpty,
      );

      expect(find.text('ทบทวนคำนี้แล้ว ไปต่อได้เลย'), findsOneWidget);
      expect(harness.host.recordCalls, 4);
      expect(await _readAttempts(tester, fixture), hasLength(4));
    },
  );

  testWidgets(
    '320px dark high-contrast reduced-motion layout supports 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = await _startHarness(tester, fixture, itemCount: 1);

      await tester.pumpWidget(
        harness.app(
          themeMode: ThemeMode.dark,
          mediaQuery: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
            highContrast: true,
            disableAnimations: true,
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey<String>('mixed-review-typed-input'))
            .evaluate()
            .isNotEmpty,
      );

      final input = find.byKey(
        const ValueKey<String>('mixed-review-typed-input'),
      );
      final context = tester.element(input);
      final accessibility = AccessibilityScope.of(context);
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(accessibility.textScale, 2);
      expect(accessibility.highContrast, isTrue);
      expect(accessibility.reducedMotion, isTrue);
      final colors = Theme.of(context).colorScheme;
      expect(
        DefaultTextStyle.of(
          tester.element(find.text('Playful Quest')),
        ).style.color,
        colors.onPrimaryContainer,
      );
      expect(
        DefaultTextStyle.of(tester.element(find.text('สถานี'))).style.color,
        colors.onTertiaryContainer,
      );
      expect(tester.takeException(), isNull);

      final skip = find.byKey(const ValueKey<String>('mixed-review-skip'));
      await tester.ensureVisible(skip);
      await tester.pump();
      expect(skip, findsOneWidget);
      expect(tester.takeException(), isNull);

      await _submitTyped(tester, harness.host, 'wrong-answer');
      const supportLead = 'คำนี้ยังไม่ผ่านในครั้งนี้';
      final supportText = find.textContaining(supportLead);
      expect(supportText, findsOneWidget);
      expect(
        DefaultTextStyle.of(tester.element(supportText)).style.color,
        colors.onSecondaryContainer,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'semantic labels identify progress and input while primary targets are at least 48px',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final harness = await _startHarness(tester, fixture, itemCount: 1);
        await tester.pumpWidget(harness.app());
        await _pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey<String>('mixed-review-typed-input'))
              .evaluate()
              .isNotEmpty,
        );

        expect(find.bySemanticsLabel('ความคืบหน้า 0 จาก 1'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp(r'พิมพ์คำศัพท์ภาษาอังกฤษ')),
          findsOneWidget,
        );

        final input = find.byKey(
          const ValueKey<String>('mixed-review-typed-input'),
        );
        await tester.enterText(input, 'station');
        await tester.pump();

        final submit = find.byKey(
          const ValueKey<String>('mixed-review-submit'),
        );
        final skip = find.byKey(const ValueKey<String>('mixed-review-skip'));
        for (final control in <Finder>[submit, skip]) {
          final data = tester.getSemantics(control).getSemanticsData();
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          final size = tester.getSize(control);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        final inputSize = tester.getSize(input);
        expect(inputSize.width, greaterThanOrEqualTo(48));
        expect(inputSize.height, greaterThanOrEqualTo(48));

        expect(
          tester.getSemantics(submit).getSemanticsData().label,
          contains('ตรวจคำตอบ'),
        );
        expect(
          tester.getSemantics(skip).getSemanticsData().label,
          contains('ข้ามข้อนี้'),
        );
        expect(
          tester
              .getSemantics(find.byType(EditableText))
              .getSemanticsData()
              .flagsCollection
              .isTextField,
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('confirmed back exits the accepted lesson route exactly once', (
    tester,
  ) async {
    final harness = await _startHarness(tester, fixture, itemCount: 1);
    await tester.pumpWidget(harness.navigableApp());
    await tester.tap(
      find.byKey(const ValueKey<String>('open-mixed-review-route')),
    );
    await tester.pumpAndSettle();
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey<String>('mixed-review-typed-input'))
          .evaluate()
          .isNotEmpty,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ออกจากบทเรียน?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'ออกจากบทเรียน'));
    await tester.pumpAndSettle();

    expect(find.text('route-launcher'), findsOneWidget);
    expect(find.text('ออกจากบทเรียน?'), findsNothing);
    expect(find.byType(AdventureMixedReviewScreen), findsNothing);
  });
}

Future<void> _submitTyped(
  WidgetTester tester,
  _RecordingLessonHost host,
  String answer,
) async {
  final expectedCommits = host.committedCalls + 1;
  await tester.enterText(
    find.byKey(const ValueKey<String>('mixed-review-typed-input')),
    answer,
  );
  await tester.pump();
  final submit = find.byKey(const ValueKey<String>('mixed-review-submit'));
  await tester.ensureVisible(submit);
  await tester.pump();
  await tester.tap(submit);
  await tester.pump();
  await _pumpUntil(tester, () => host.committedCalls == expectedCommits);
  await _pumpUntil(
    tester,
    () =>
        host.committedCalls == expectedCommits &&
        find
            .byKey(const ValueKey<String>('mixed-review-next'))
            .evaluate()
            .isNotEmpty,
  );
}

Future<void> _goNext(
  WidgetTester tester, {
  String? expectedPrompt,
  Key? expectedKey,
}) async {
  final next = find.byKey(const ValueKey<String>('mixed-review-next'));
  await tester.ensureVisible(next);
  await tester.pump();
  expect(next.hitTestable(), findsOneWidget);
  await tester.tap(next);
  await tester.pump();
  await _pumpUntil(
    tester,
    () =>
        (expectedPrompt != null &&
            find.text(expectedPrompt).evaluate().isNotEmpty) ||
        (expectedKey != null && find.byKey(expectedKey).evaluate().isNotEmpty),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  String Function()? describeFailure,
}) async {
  for (var attempt = 0; attempt < 200 && !predicate(); attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(
    predicate(),
    isTrue,
    reason:
        'asynchronous widget state did not settle${describeFailure == null ? '' : ': ${describeFailure()}'}',
  );
}

Future<_MixedReviewHarness> _startHarness(
  WidgetTester tester,
  _MixedReviewFixture fixture, {
  required int itemCount,
  Iterable<VocabularyWord>? lexicalWords,
  Completer<void>? recordGate,
}) async {
  final host = _RecordingLessonHost(recordGate: recordGate);
  final harness = await tester.runAsync(
    () => fixture.start(
      itemCount: itemCount,
      lexicalWords: lexicalWords,
      host: host,
    ),
  );
  return harness!;
}

Future<List<AnswerAttempt>> _readAttempts(
  WidgetTester tester,
  _MixedReviewFixture fixture,
) async {
  final attempts = await tester.runAsync(
    () => fixture.database.select(fixture.database.answerAttempts).get(),
  );
  return attempts!;
}

final class _MixedReviewHarness {
  const _MixedReviewHarness({
    required this.recovery,
    required this.catalog,
    required this.registry,
    required this.host,
  });

  final AdventureRecoveryUseCases recovery;
  final AdventureMixedReviewPromptCatalog catalog;
  final LessonModeRegistry registry;
  final _RecordingLessonHost host;

  Widget app({
    ThemeMode themeMode = ThemeMode.light,
    MediaQueryData? mediaQuery,
  }) => MaterialApp(
    theme: M3Theme.lightTheme,
    darkTheme: M3Theme.darkTheme,
    themeMode: themeMode,
    builder: mediaQuery == null
        ? null
        : (context, child) => MediaQuery(data: mediaQuery, child: child!),
    home: AccessibilityScope(
      child: AdventureMixedReviewScreen(
        recovery: recovery,
        catalog: catalog,
        registry: registry,
        lessonHost: host,
        completionPageBuilder: (_, summary, presentation) =>
            const Scaffold(body: Center(child: Text('mixed-review-complete'))),
      ),
    ),
  );

  Widget navigableApp() => MaterialApp(
    theme: M3Theme.lightTheme,
    builder: (context, child) => AccessibilityScope(child: child!),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const ValueKey<String>('open-mixed-review-route'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AdventureMixedReviewScreen(
                  recovery: recovery,
                  catalog: catalog,
                  registry: registry,
                  lessonHost: host,
                  completionPageBuilder: (_, summary, presentation) =>
                      const Scaffold(
                        body: Center(child: Text('mixed-review-complete')),
                      ),
                ),
              ),
            ),
            child: const Text('route-launcher'),
          ),
        ),
      ),
    ),
  );
}

final class _RecordingLessonHost implements AdventureMixedReviewLessonHost {
  _RecordingLessonHost({this.recordGate});

  final Completer<void>? recordGate;
  int recordCalls = 0;
  int committedCalls = 0;
  final List<String> evidenceIds = <String>[];
  final List<LessonMode> occurrenceModes = <LessonMode>[];

  @override
  bool get acceptsOperations => true;

  @override
  Future<T> runRecoveryOperation<T>(Future<T> Function() operation) =>
      Future<T>.sync(operation);

  @override
  Future<QuizSession> initializeSession(
    QuizSession session, {
    PendingLearningSessionClose? recoveredClose,
  }) async => session;

  @override
  void noteSkippedItem() {}

  @override
  void recordInteraction() {}

  @override
  void ownRecoveryClose(
    PendingLearningSessionClose close,
    Future<void> Function() ensureDurable,
  ) {}

  @override
  Future<AnswerRecordResult> recordCapturedEvidence(
    PendingCurrentActivityEvidence pending, {
    required AnswerFeedbackContext feedbackContext,
    required LessonModeAdapter occurrenceAdapter,
  }) async {
    recordCalls += 1;
    evidenceIds.add(pending.sourceEvidenceId);
    occurrenceModes.add(occurrenceAdapter.mode);
    await recordGate?.future;
    final result = await (pending.requiresRetry
        ? pending.retry()
        : pending.record());
    committedCalls += 1;
    return result;
  }

  @override
  HintUsageSnapshot snapshotHintUsage() =>
      const HintUsageSnapshot.unavailable();

  @override
  Future<LearningSessionSummary> completeRecovery(
    PendingLearningSessionClose close,
  ) => close.requiresRetry ? close.retry() : close.finish();
}

final class _MixedReviewFixture {
  _MixedReviewFixture._({
    required this.database,
    required this.owners,
    required this.learning,
    required this.evidence,
    required this.registry,
    required this.ownerId,
    required this.identities,
    required this.lexicalWords,
  });

  final AppDatabase database;
  final DriftLocalOwnerRepository owners;
  final LearningUseCases learning;
  final CurrentActivityEvidenceAdapter evidence;
  final LessonModeRegistry registry;
  final String ownerId;
  final List<ContentIdentity> identities;
  final List<VocabularyWord> lexicalWords;

  static Future<_MixedReviewFixture> create() async {
    final database = AppDatabase(NativeDatabase.memory());
    var now = DateTime.utc(2026, 9, 5, 9);
    var nextId = 0;
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner:mixed-review-screen',
      nowUtc: () => now,
    );
    final ownerId = (await owners.getOrCreateActiveOwner()).id;
    final seeded = await _seedWords(database, ownerId);
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'mixed-review-screen-${++nextId}',
      nowUtc: () {
        final value = now;
        now = now.add(const Duration(seconds: 1));
        return value;
      },
      buildInfo: const AppBuildInfo(
        version: 'test',
        buildId: 'mixed-review-screen-test',
      ),
    );
    return _MixedReviewFixture._(
      database: database,
      owners: owners,
      learning: learning,
      evidence: CurrentActivityEvidenceAdapter(learning: learning),
      registry: buildLessonModeRegistry(),
      ownerId: ownerId,
      identities: seeded.$1,
      lexicalWords: seeded.$2,
    );
  }

  Future<_MixedReviewHarness> start({
    required int itemCount,
    Iterable<VocabularyWord>? lexicalWords,
    required _RecordingLessonHost host,
  }) async {
    final content = identities.take(itemCount).toList(growable: false);
    final plan = _plan(ownerId: ownerId, content: content);
    late AdventureMixedReviewPromptCatalog catalog;
    final recovery = AdventureRecoveryUseCases(
      learning: learning,
      evidence: evidence,
      canStartNewMission: () => true,
      isRepairModeEligible: (identity, mode, variant) =>
          catalog.supports(identity, mode, variant),
      spacingForIdentity: (_) => 3,
    );
    final run = await recovery.startOrResume(
      plan: plan,
      activeOwnerId: ownerId,
    );
    catalog = AdventureMixedReviewPromptCatalog(
      session: run.session,
      lexicalWords: lexicalWords ?? this.lexicalWords.take(itemCount),
      registry: registry,
      direction: plan.configuration.direction,
    );
    return _MixedReviewHarness(
      recovery: recovery,
      catalog: catalog,
      registry: registry,
      host: host,
    );
  }

  Future<void> close() => database.close();
}

Future<(List<ContentIdentity>, List<VocabularyWord>)> _seedWords(
  AppDatabase database,
  String ownerId,
) async {
  const categoryId = 'category:mixed-review-screen';
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: categoryId,
          ownerId: ownerId,
          name: 'Mixed review screen',
          normalizedName: 'mixed review screen',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  final identities = <ContentIdentity>[];
  final lexicalWords = <VocabularyWord>[];
  for (final (index, entry) in const <(String, String, String)>[
    ('word:station', 'station', 'สถานี'),
    ('word:ticket', 'ticket', 'ตั๋ว'),
    ('word:platform', 'platform', 'ชานชาลา'),
    ('word:journey', 'journey', 'การเดินทาง'),
    ('word:airport', 'airport', 'สนามบิน'),
  ].indexed) {
    final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
      categoryId: categoryId,
      spelling: entry.$2,
      normalizedSpelling: entry.$2,
      meaning: entry.$3,
      normalizedMeaning: entry.$3,
      partOfSpeech: 'noun',
      cefrLevel: null,
      source: 'manual',
      isGlobal: false,
    );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: entry.$1,
            ownerId: ownerId,
            categoryId: categoryId,
            spelling: entry.$2,
            normalizedSpelling: entry.$2,
            meaning: entry.$3,
            normalizedMeaning: entry.$3,
            partOfSpeech: 'noun',
            source: const Value('manual'),
            isGlobal: const Value(false),
            contentRevision: const Value(1),
            contentChecksumSha256: Value(checksum),
            contentProvenance: Value(ContentProvenance.userAuthored.name),
            contentReviewState: Value(ContentReviewState.unreviewed.name),
            contentPublicationState: Value(
              ContentPublicationState.private.name,
            ),
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    identities.add(
      ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: entry.$1,
        revision: 1,
      ),
    );
    lexicalWords.add(
      VocabularyWord(
        id: entry.$1,
        ownerId: ownerId,
        categoryId: categoryId,
        spelling: entry.$2,
        normalizedSpelling: entry.$2,
        meaning: entry.$3,
        normalizedMeaning: entry.$3,
        partOfSpeech: 'noun',
        source: 'manual',
        isGlobal: true,
        localRevision: 1,
        isDeleted: false,
        createdAtUtc: DateTime.utc(2026, 9, 1),
        updatedAtUtc: DateTime.utc(2026, 9, 1),
        contentRevision: 1,
        contentChecksumSha256: checksum,
        contentProvenance: ContentProvenance.packaged,
        contentReviewState: ContentReviewState.approved,
        contentPublicationState: ContentPublicationState.published,
        richMetadata: RichLexicalMetadata(
          englishDefinition: 'Definition of ${entry.$2}',
          examples: <String>['The ${entry.$2} is nearby.'],
          verifiedContentRevision: 1,
          verifiedArtifactChecksumSha256: '${index + 1}' * 64,
        ),
      ),
    );
  }
  return (identities, lexicalWords);
}

AdventureSessionPlanV1 _plan({
  required String ownerId,
  required List<ContentIdentity> content,
}) {
  final configuration = SessionConfiguration.validated(
    schemaVersion: sessionConfigurationSchemaVersion,
    policyVersion: sessionConfigurationPolicyVersion,
    ownerId: ownerId,
    mode: LessonMode.typedRecall,
    itemCount: content.length,
    direction: SessionDirection.reverse,
    difficulty: SessionDifficulty.standard,
    hintBudget: 1,
    timing: const SessionTiming.timed(Duration(minutes: 5)),
    packIdentity: null,
    protocolId: 'protocol:local',
    protocolVersion: '1',
    protocolLimitsIdentity: 'limits:mixed-review-screen',
  );
  const planId = 'adventure-plan:mixed-review-screen';
  return AdventureSessionPlanV1(
    planId: planId,
    ownerId: ownerId,
    createdAtUtc: DateTime.utc(2026, 9, 5, 9),
    sourceEvaluatedAtUtc: DateTime.utc(2026, 9, 5, 9),
    content: content,
    contentChecksumsSha256: <String, String>{
      for (final item in content) item.id: _checksum(item.id),
    },
    mode: LessonMode.typedRecall,
    configuration: configuration,
    recommendationPolicyVersion: 'recommendation-v1',
    sourceReasonCode: 'due',
    learnerOverrideApplied: false,
    origin: const AdventureOriginContextV1(
      planId: planId,
      nodeId: 'node:mixed-review-screen',
      catalogId: 'catalog:adventure',
      catalogVersion: '1.0.0',
      catalogSchemaVersion: 1,
      presentation: TodayExperiencePresentation.adventure,
    ),
  );
}

String _checksum(String id) {
  final values = <String, (String, String)>{
    'word:station': ('station', 'สถานี'),
    'word:ticket': ('ticket', 'ตั๋ว'),
    'word:platform': ('platform', 'ชานชาลา'),
    'word:journey': ('journey', 'การเดินทาง'),
    'word:airport': ('airport', 'สนามบิน'),
  };
  final value = values[id]!;
  return ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: 'category:mixed-review-screen',
    spelling: value.$1,
    normalizedSpelling: value.$1,
    meaning: value.$2,
    normalizedMeaning: value.$2,
    partOfSpeech: 'noun',
    cefrLevel: null,
    source: 'manual',
    isGlobal: false,
  );
}
