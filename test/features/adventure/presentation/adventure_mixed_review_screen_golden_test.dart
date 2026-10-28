import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const _goldenSurfaceKey = ValueKey<String>('mixed-review-golden-surface');
const _phone = Size(412, 915);
const _narrowPhone = Size(320, 640);
const _goldenDirectory = 'goldens/adventure_mixed_review_screen';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final thaiFont = FontLoader(M3Theme.thaiFontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'));
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait(<Future<void>>[thaiFont.load(), materialIcons.load()]);
  });

  testWidgets('golden: Adventure active typed prompt', (tester) async {
    _setSurface(tester, _phone);
    final fixture = await tester.runAsync(_GoldenFixture.create);
    addTearDown(() => fixture!.close());
    final harness = await tester.runAsync(
      () => fixture!.start(
        itemCount: 1,
        presentation: TodayExperiencePresentation.adventure,
      ),
    );

    await tester.pumpWidget(harness!.app(mediaQuery: _mediaQuery(_phone)));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey<String>('mixed-review-typed-input'))
          .evaluate()
          .isNotEmpty,
    );

    expect(
      harness.recovery.currentRun?.presentation,
      AdventureLearningPresentation.adventure,
    );
    expect(find.text('ภารกิจทบทวน'), findsOneWidget);
    expect(find.text('Playful Quest'), findsOneWidget);
    await _expectGolden(tester, 'adventure_active_typed_light.png');
  });

  testWidgets('golden: Standard recovered active typed prompt', (tester) async {
    _setSurface(tester, _phone);
    final fixture = await tester.runAsync(_GoldenFixture.create);
    addTearDown(() => fixture!.close());
    final harness = await tester.runAsync(
      () => fixture!.start(
        itemCount: 1,
        presentation: TodayExperiencePresentation.standard,
      ),
    );

    await tester.pumpWidget(harness!.app(mediaQuery: _mediaQuery(_phone)));
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey<String>('mixed-review-typed-input'))
          .evaluate()
          .isNotEmpty,
    );

    expect(
      harness.recovery.currentRun?.presentation,
      AdventureLearningPresentation.standard,
    );
    expect(find.text('ทบทวนคำศัพท์'), findsOneWidget);
    expect(find.text('ทบทวนต่อจากเดิม'), findsOneWidget);
    await _expectGolden(tester, 'standard_recovered_active_typed_light.png');
  });

  testWidgets('golden: Adventure committed support in dark high contrast', (
    tester,
  ) async {
    _setSurface(tester, _phone);
    final fixture = await tester.runAsync(_GoldenFixture.create);
    addTearDown(() => fixture!.close());
    final harness = await tester.runAsync(
      () => fixture!.start(
        itemCount: 5,
        presentation: TodayExperiencePresentation.adventure,
      ),
    );
    final mediaQuery = _mediaQuery(
      _phone,
      highContrast: true,
      disableAnimations: true,
    );

    await tester.pumpWidget(
      harness!.app(themeMode: ThemeMode.dark, mediaQuery: mediaQuery),
    );
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey<String>('mixed-review-typed-input'))
          .evaluate()
          .isNotEmpty,
    );
    await _submitTyped(tester, harness.host, 'wrong-answer');

    final support = find.byKey(const ValueKey<String>('mixed-review-support'));
    expect(support, findsOneWidget);
    final context = tester.element(support);
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(AccessibilityScope.of(context).highContrast, isTrue);
    await tester.ensureVisible(support);
    await _expectGolden(tester, 'adventure_support_dark_high_contrast.png');
  });

  testWidgets('golden: Adventure flashcard repair at narrow 200 percent text', (
    tester,
  ) async {
    _setSurface(tester, _narrowPhone);
    final fixture = await tester.runAsync(_GoldenFixture.create);
    addTearDown(() => fixture!.close());
    final harness = await tester.runAsync(
      () => fixture!.start(
        itemCount: 5,
        presentation: TodayExperiencePresentation.adventure,
        lexicalWords: const <VocabularyWord>[],
      ),
    );
    final mediaQuery = _mediaQuery(
      _narrowPhone,
      textScaler: const TextScaler.linear(2),
      disableAnimations: true,
    );

    await tester.pumpWidget(harness!.app(mediaQuery: mediaQuery));
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
    final reveal = find.byKey(
      const ValueKey<String>('mixed-review-flashcard-reveal'),
    );
    await tester.ensureVisible(reveal);
    await tester.pump();
    await tester.tap(reveal);
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey<String>('mixed-review-flashcard-answer'))
          .evaluate()
          .isNotEmpty,
    );

    final answer = find.byKey(
      const ValueKey<String>('mixed-review-flashcard-answer'),
    );
    final context = tester.element(answer);
    final accessibility = AccessibilityScope.of(context);
    expect(accessibility.textScale, 2);
    expect(accessibility.reducedMotion, isTrue);
    expect(
      find.byKey(const ValueKey<String>('mixed-review-repair-badge')),
      findsOneWidget,
    );
    await tester.ensureVisible(answer);
    await _expectGolden(
      tester,
      'adventure_flashcard_revealed_narrow_text_200_reduced_motion.png',
    );
    final next = find.byKey(
      const ValueKey<String>('mixed-review-flashcard-continue'),
    );
    await Scrollable.ensureVisible(tester.element(next), alignment: 0.5);
    await tester.pump();
    expect(next.hitTestable(), findsOneWidget);
    expect(tester.getRect(next).bottom, lessThanOrEqualTo(_narrowPhone.height));
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    await tester.tap(next);
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey<String>('mixed-review-next'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.text('ทบทวนคำนี้แล้ว ไปต่อได้เลย'), findsOneWidget);
    await _goNext(tester, expectedPrompt: 'สนามบิน');
  });
}

MediaQueryData _mediaQuery(
  Size size, {
  TextScaler textScaler = TextScaler.noScaling,
  bool highContrast = false,
  bool disableAnimations = false,
}) => MediaQueryData(
  size: size,
  devicePixelRatio: 1,
  textScaler: textScaler,
  highContrast: highContrast,
  disableAnimations: disableAnimations,
);

void _setSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _expectGolden(WidgetTester tester, String fileName) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 500));
  await expectLater(
    find.byKey(_goldenSurfaceKey),
    matchesGoldenFile('$_goldenDirectory/$fileName'),
  );
}

Future<void> _submitTyped(
  WidgetTester tester,
  _GoldenLessonHost host,
  String answer,
) async {
  final expectedCommits = host.committedCalls + 1;
  final input = find.byKey(const ValueKey<String>('mixed-review-typed-input'));
  await tester.ensureVisible(input);
  await tester.enterText(input, answer);
  await tester.pump();
  final submit = find.byKey(const ValueKey<String>('mixed-review-submit'));
  await tester.ensureVisible(submit);
  await tester.pump();
  await tester.tap(submit);
  await tester.pump();
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

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var attempt = 0; attempt < 200 && !predicate(); attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(
    predicate(),
    isTrue,
    reason: 'asynchronous golden state did not settle',
  );
}

final class _GoldenHarness {
  const _GoldenHarness({
    required this.recovery,
    required this.catalog,
    required this.registry,
    required this.host,
  });

  final AdventureRecoveryUseCases recovery;
  final AdventureMixedReviewPromptCatalog catalog;
  final LessonModeRegistry registry;
  final _GoldenLessonHost host;

  Widget app({
    ThemeMode themeMode = ThemeMode.light,
    required MediaQueryData mediaQuery,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: M3Theme.lightTheme,
    darkTheme: M3Theme.darkTheme,
    themeMode: themeMode,
    builder: (context, child) => MediaQuery(data: mediaQuery, child: child!),
    home: RepaintBoundary(
      key: _goldenSurfaceKey,
      child: AccessibilityScope(
        child: AdventureMixedReviewScreen(
          recovery: recovery,
          catalog: catalog,
          registry: registry,
          lessonHost: host,
          completionPageBuilder: (_, _, _) =>
              const Scaffold(body: Center(child: Text('complete'))),
        ),
      ),
    ),
  );
}

final class _GoldenLessonHost implements AdventureMixedReviewLessonHost {
  int committedCalls = 0;

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

final class _GoldenFixture {
  _GoldenFixture._({
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

  static Future<_GoldenFixture> create() async {
    final database = AppDatabase(NativeDatabase.memory());
    var now = DateTime.utc(2026, 9, 5, 9);
    var nextId = 0;
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner:mixed-review-golden',
      nowUtc: () => now,
    );
    final ownerId = (await owners.getOrCreateActiveOwner()).id;
    final seeded = await _seedWords(database, ownerId);
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'mixed-review-golden-${++nextId}',
      nowUtc: () {
        final value = now;
        now = now.add(const Duration(seconds: 1));
        return value;
      },
      buildInfo: const AppBuildInfo(
        version: 'test',
        buildId: 'mixed-review-golden-test',
      ),
    );
    return _GoldenFixture._(
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

  Future<_GoldenHarness> start({
    required int itemCount,
    required TodayExperiencePresentation presentation,
    Iterable<VocabularyWord>? lexicalWords,
  }) async {
    final content = identities.take(itemCount).toList(growable: false);
    final plan = _plan(ownerId: ownerId, content: content);
    late AdventureMixedReviewPromptCatalog catalog;

    AdventureRecoveryUseCases buildRecovery({required bool canStart}) =>
        AdventureRecoveryUseCases(
          learning: learning,
          evidence: evidence,
          canStartNewMission: () => canStart,
          isRepairModeEligible: (identity, mode, variant) =>
              catalog.supports(identity, mode, variant),
          spacingForIdentity: (_) => 3,
        );

    var recovery = buildRecovery(canStart: true);
    var run = await recovery.startOrResume(plan: plan, activeOwnerId: ownerId);
    if (presentation == TodayExperiencePresentation.standard) {
      recovery = buildRecovery(canStart: false);
      run = (await recovery.recoverExact(
        ownerId: ownerId,
        sessionId: run.session.id,
      ))!;
    }
    catalog = AdventureMixedReviewPromptCatalog(
      session: run.session,
      lexicalWords: lexicalWords ?? this.lexicalWords.take(itemCount),
      registry: registry,
      direction: plan.configuration.direction,
    );
    return _GoldenHarness(
      recovery: recovery,
      catalog: catalog,
      registry: registry,
      host: _GoldenLessonHost(),
    );
  }

  Future<void> close() => database.close();
}

Future<(List<ContentIdentity>, List<VocabularyWord>)> _seedWords(
  AppDatabase database,
  String ownerId,
) async {
  const categoryId = 'category:mixed-review-golden';
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: categoryId,
          ownerId: ownerId,
          name: 'Mixed review golden',
          normalizedName: 'mixed review golden',
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
    final checksum = _checksum(entry.$1);
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
    protocolLimitsIdentity: 'limits:mixed-review-golden',
  );
  const planId = 'adventure-plan:mixed-review-golden';
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
      nodeId: 'node:mixed-review-golden',
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
    categoryId: 'category:mixed-review-golden',
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
