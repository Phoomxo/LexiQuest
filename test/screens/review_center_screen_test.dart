import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/review/application/review_center_use_cases.dart';
import 'package:vocab_learning_app/features/review/data/drift_review_center_reader.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/product/feature_contract/alltcas_idea_integration_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/review_center_screen.dart';

void main() {
  testWidgets('presents every typed reason and source detail', (tester) async {
    final item = _item(allReasons: true);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: _useCases(result: [item]),
          lessonShellBuilder: _unusedDestination,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'ศูนย์ทบทวน'), findsOneWidget);
    expect(find.text('ถึงกำหนด SRS'), findsOneWidget);
    expect(find.text('เคยตอบผิด'), findsOneWidget);
    expect(find.text('รายงานไว้: คำตอบ'), findsOneWidget);
    expect(find.text('บันทึกไว้'), findsOneWidget);
    expect(find.text('station'), findsOneWidget);
    expect(find.text('สถานี'), findsOneWidget);
  });

  testWidgets('exposes labelled loading state', (tester) async {
    final pending = Completer<List<ReviewQueueItem>>();
    final reader = _Reader(load: () => pending.future);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: _useCases(reader: reader),
          lessonShellBuilder: _unusedDestination,
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('กำลังโหลดรายการทบทวน'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(const []);
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('renders an accessible empty state', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: _useCases(result: const []),
          lessonShellBuilder: _unusedDestination,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ยังไม่มีรายการที่ต้องทบทวน'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('รายการทบทวนว่าง')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('shows a bounded error and retries on explicit action', (
    tester,
  ) async {
    var calls = 0;
    final item = _item();
    final reader = _Reader(
      load: () async {
        calls += 1;
        if (calls == 1) throw StateError('offline');
        return [item];
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: _useCases(reader: reader),
          lessonShellBuilder: _unusedDestination,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ไม่สามารถโหลดรายการทบทวนได้'), findsOneWidget);
    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('station'), findsOneWidget);
  });

  testWidgets('supports 200 percent text without overflow', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: ReviewCenterScreen(
            useCases: _useCases(result: [_item(allReasons: true)]),
            lessonShellBuilder: _unusedDestination,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('station'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('เริ่มทบทวน'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('เริ่มทบทวน'), findsOneWidget);
  });

  testWidgets(
    'launches one fresh deterministic session through Unified Lesson shell',
    (tester) async {
      final fixture = await _durableFixture();
      addTearDown(fixture.database.close);
      final controllers = <UnifiedLessonController>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewCenterScreen(
            useCases: fixture.useCases,
            lessonShellBuilder: (_) => _lessonDestination(
              learning: fixture.learning,
              controllers: controllers,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.tap(find.text('เริ่มทบทวน'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(controllers, hasLength(1));
      expect(controllers.single.state.sessionId, 'session:review-1');
      expect(find.byType(UnifiedLessonShell), findsOneWidget);
      expect(find.text('session session:review-1'), findsOneWidget);

      Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
      await tester.pumpAndSettle();
      final retired = await fixture.database
          .select(fixture.database.learningSessions)
          .get();
      expect(retired.single.state, 'abandoned');
      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.pumpAndSettle();

      expect(controllers, hasLength(2));
      expect(controllers.last.state.sessionId, 'session:review-2');
    },
  );

  testWidgets(
    'launch persists one exact pinned canonical session before learner action',
    (tester) async {
      final fixture = await _durableFixture();
      addTearDown(fixture.database.close);
      final controllers = <UnifiedLessonController>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewCenterScreen(
            useCases: fixture.useCases,
            lessonShellBuilder: (_) => _lessonDestination(
              learning: fixture.learning,
              controllers: controllers,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.pumpAndSettle();

      final sessions = await fixture.database
          .select(fixture.database.learningSessions)
          .get();
      expect(sessions, hasLength(1));
      expect(sessions.single.id, 'session:review-1');
      expect(sessions.single.ownerId, 'owner-1');
      expect(sessions.single.activityType, 'reviewCenter');
      expect(sessions.single.state, 'active');
      expect(controllers.single.state.sessionId, sessions.single.id);
      expect(controllers.single.state.itemCount, 1);
      expect(
        await fixture.database.select(fixture.database.answerAttempts).get(),
        isEmpty,
      );
      expect(
        await fixture.database.select(fixture.database.eventsV2).get(),
        isEmpty,
      );
      expect(
        await fixture.database.select(fixture.database.srsStates).get(),
        isEmpty,
      );
      expect(
        await fixture.database
            .select(fixture.database.pointsLedgerEntries)
            .get(),
        isEmpty,
      );
      expect(
        await fixture.database
            .select(fixture.database.rewardTransactions)
            .get(),
        isEmpty,
      );
    },
  );

  testWidgets(
    'successful launch builds the shell from a returned immutable queue item',
    (tester) async {
      final fixture = await _durableFixture();
      addTearDown(fixture.database.close);
      final item = _item();
      ReviewQueueItem? builderItem;
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewCenterScreen(
            useCases: ReviewCenterUseCases(
              reader: _Reader(load: () async => [item]),
              ownerIdentities: const _OwnerIdentities(),
              sessionLauncher: LearningUseCasesReviewSessionLauncher(
                fixture.learning,
              ),
              nowUtc: () => _now,
              timezoneId: 'Asia/Bangkok',
            ),
            lessonShellBuilder: (returnedItem) {
              builderItem = returnedItem;
              return _lessonDestination(learning: fixture.learning);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.pumpAndSettle();

      expect(builderItem, isNotNull);
      expect(identical(builderItem, item), isFalse);
      expect(identical(builderItem!.snapshot, item.snapshot), isFalse);
      expect(builderItem!.identity, item.identity);
      expect(builderItem!.spelling, item.spelling);
      expect(builderItem!.meaning, item.meaning);
      expect(find.byType(UnifiedLessonShell), findsOneWidget);
    },
  );

  testWidgets('builder throw leaves no active durable session', (tester) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) => throw StateError('builder failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();

    expect(find.text('ไม่สามารถเริ่มการทบทวนได้'), findsOneWidget);
    expect(
      await _activeSessions(fixture.database),
      isEmpty,
      reason: 'a widget builder failure must compensate its durable session',
    );
  });

  testWidgets('different learning authority compensates the validated launch', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    var otherId = 0;
    final otherLearning = LearningUseCases(
      owners: const _Owners(),
      repository: DriftLearningRepository(fixture.database),
      generateId: () => 'other-${++otherId}',
      nowUtc: () => _now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'other'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) =>
              _lessonDestination(learning: otherLearning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();

    expect(find.text('ไม่สามารถเริ่มการทบทวนได้'), findsOneWidget);
    final sessions = await fixture.database
        .select(fixture.database.learningSessions)
        .get();
    expect(sessions, hasLength(1));
    expect(sessions.single.state, 'abandoned');
    expect(await _activeSessions(fixture.database), isEmpty);
  });

  testWidgets('configuration mismatch compensates failed attachment', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) => _lessonDestination(
            learning: fixture.learning,
            configuration: _sessionConfiguration(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();

    final sessions = await fixture.database
        .select(fixture.database.learningSessions)
        .get();
    expect(sessions, hasLength(1));
    expect(sessions.single.state, 'abandoned');
    expect(await _activeSessions(fixture.database), isEmpty);
    expect(find.text('ไม่สามารถเริ่มการทบทวนได้'), findsOneWidget);
  });

  testWidgets('unmount during durable start compensates the returned session', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    final release = Completer<void>();
    final persisted = Completer<void>();
    final delayed = _DelayedSessionLauncher(
      LearningUseCasesReviewSessionLauncher(fixture.learning),
      persisted: persisted,
      release: release,
    );
    final useCases = ReviewCenterUseCases(
      reader: _Reader(load: () async => [_item()]),
      ownerIdentities: DriftReviewOwnerIdentityReader(fixture.database),
      sessionLauncher: delayed,
      nowUtc: () => _now,
      timezoneId: 'Asia/Bangkok',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: useCases,
          lessonShellBuilder: (_) =>
              _lessonDestination(learning: fixture.learning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await persisted.future;
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    release.complete();
    await tester.pumpAndSettle();

    expect(await _activeSessions(fixture.database), isEmpty);
  });

  testWidgets('returned controller attaches to the exact durable session', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    late UnifiedLessonController controller;
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) {
            final controllers = <UnifiedLessonController>[];
            final destination = _lessonDestination(
              learning: fixture.learning,
              controllers: controllers,
            );
            controller = controllers.single;
            return destination;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();
    final durable = (await _activeSessions(fixture.database)).single;

    expect(controller.state.sessionId, durable.id);
    expect(controller.state.status, LessonSessionStatus.active);
  });

  testWidgets('negative launch clock fails before session persistence', (
    tester,
  ) async {
    var now = _now;
    final fixture = await _durableFixture(nowUtc: () => now);
    addTearDown(fixture.database.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) =>
              _lessonDestination(learning: fixture.learning),
        ),
      ),
    );
    await tester.pumpAndSettle();
    now = DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true);

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();

    expect(find.text('ไม่สามารถเริ่มการทบทวนได้'), findsOneWidget);
    expect(
      await fixture.database.select(fixture.database.learningSessions).get(),
      isEmpty,
    );
  });

  testWidgets('retired reused lease compensates every later session', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    UnifiedLessonShellLease? reused;
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) =>
              reused ??= _lessonDestination(learning: fixture.learning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();

    final sessions = await fixture.database
        .select(fixture.database.learningSessions)
        .get();
    expect(sessions, hasLength(2));
    expect(sessions.map((session) => session.state), everyElement('abandoned'));
    expect(await _activeSessions(fixture.database), isEmpty);
  });

  testWidgets('route retirement closes the pinned owner after owner switch', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) =>
              _lessonDestination(learning: fixture.learning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();
    await _switchToOwnerTwo(fixture.database);
    await fixture.database
        .into(fixture.database.learningSessions)
        .insert(
          LearningSessionsCompanion.insert(
            id: 'owner-2-active',
            ownerId: 'owner-2',
            activityType: 'quiz',
            state: 'active',
            startedAtUtcMs: _now.millisecondsSinceEpoch,
            appVersion: 'test',
            buildId: 'owner-2',
          ),
        );

    Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
    await tester.pumpAndSettle();

    final sessions = await fixture.database
        .select(fixture.database.learningSessions)
        .get();
    final review = sessions.singleWhere(
      (session) => session.id == 'session:review-1',
    );
    final ownerTwo = sessions.singleWhere(
      (session) => session.id == 'owner-2-active',
    );
    expect(review.state, 'abandoned');
    expect(ownerTwo.state, 'active');
  });

  test('f22 is not exposed by navigation before f42 composes the action', () {
    final record = allTcasIdeaIntegrationCatalog.records.singleWhere(
      (candidate) => candidate.id == FeatureContractId.f22,
    );
    final todayHubRecord = allTcasIdeaIntegrationCatalog.records.singleWhere(
      (candidate) => candidate.id == FeatureContractId.f42,
    );
    final mainNavigation = File(
      'lib/screens/main_navigation_screen.dart',
    ).readAsStringSync();
    final todayHub = File(
      'lib/screens/today_hub_screen.dart',
    ).readAsStringSync();
    final productionEntryIds = RegExp(r"productionEntryId: '([^']+)'")
        .allMatches(mainNavigation)
        .map((match) => match.group(1))
        .whereType<String>()
        .toSet();
    final drawerKeys = RegExp(r"ValueKey<String>\('([^']+)'\)")
        .allMatches(mainNavigation)
        .map((match) => match.group(1))
        .whereType<String>()
        .where((key) => key.startsWith('drawer/'))
        .toSet();
    final todayHubBuilderStart = mainNavigation.indexOf(
      'Widget _buildTodayHub(BuildContext context)',
    );
    expect(todayHubBuilderStart, greaterThanOrEqualTo(0));
    final todayHubBuilderEnd = mainNavigation.indexOf(
      'Future<void> _resumeFromToday',
      todayHubBuilderStart,
    );
    expect(todayHubBuilderEnd, greaterThan(todayHubBuilderStart));
    final todayHubBuilder = mainNavigation.substring(
      todayHubBuilderStart,
      todayHubBuilderEnd,
    );

    expect(record.dependencies, contains(FeatureContractId.f20));
    expect(record.dependencies, contains(FeatureContractId.f21));
    expect(todayHubRecord.dependencies, contains(FeatureContractId.f22));
    expect(productionEntryIds, contains('home/today'));
    expect(productionEntryIds, isNot(contains('home/today/review')));
    expect(productionEntryIds, isNot(contains('home/review')));
    expect(drawerKeys, isNot(contains('drawer/review/center')));
    expect(todayHub, contains("key: const ValueKey('today-hub-open-review')"));
    expect(
      todayHub,
      contains('widget.actions.openReview(snapshot.reviewWork)'),
    );
    expect(todayHubBuilder, contains('openReview: _openTodayReview'));
    expect(
      todayHubBuilder,
      contains('hasComposedDependencyFor(Feature.dailyContinuity)'),
    );
    expect(todayHubBuilder, contains('ProductionFeatureUnavailable'));
    expect(
      todayHubBuilder,
      contains('ProductionFeatureUnavailableReason.missingDependency'),
    );
    expect(mainNavigation, contains("'home/today/review'"));
    expect(mainNavigation, contains('ReviewCenterScreen('));
  });
}

ReviewCenterUseCases _useCases({
  List<ReviewQueueItem>? result,
  ReviewCenterReader? reader,
  ReviewSessionLauncher? sessionLauncher,
}) => ReviewCenterUseCases(
  reader: reader ?? _Reader(load: () async => result ?? const []),
  ownerIdentities: const _OwnerIdentities(),
  sessionLauncher: sessionLauncher ?? _SessionLauncher(),
  nowUtc: () => DateTime.utc(2026, 8, 28, 12),
  timezoneId: 'Asia/Bangkok',
);

UnifiedLessonShellLease _unusedDestination(ReviewQueueItem _) =>
    throw StateError('launch is not expected in this test');

UnifiedLessonShellLease _lessonDestination({
  required LearningUseCases learning,
  List<UnifiedLessonController>? controllers,
  SessionConfiguration? configuration,
}) {
  final controller = UnifiedLessonController(
    learning: learning,
    adapter: const _ReviewLessonAdapter(),
  );
  if (configuration != null) {
    controller.bindSessionConfiguration(
      configuration,
      revalidate: (candidate) async => candidate,
    );
  }
  controllers?.add(controller);
  return UnifiedLessonShellLease(
    controller: controller,
    learning: learning,
    nowUtc: () => _now,
    builder: (_) => Scaffold(
      body: Center(child: Text('session ${controller.state.sessionId}')),
    ),
  );
}

ReviewQueueItem _item({bool allReasons = false}) => ReviewQueueItem(
  snapshot: ReviewedLexicalContentSnapshot(
    identity: const ContentIdentity(
      type: ContentType.lexicalMetadata,
      id: 'word-1',
      revision: 1,
    ),
    categoryId: 'category-1',
    spelling: 'station',
    normalizedSpelling: 'station',
    meaning: 'สถานี',
    normalizedMeaning: 'สถานี',
    partOfSpeech: 'noun',
    cefrLevel: null,
    source: 'manual',
    isGlobal: false,
    coreChecksumSha256: _canonicalChecksum(
      spelling: 'station',
      meaning: 'สถานี',
    ),
    provenance: ContentProvenance.userAuthored,
    reviewState: ContentReviewState.unreviewed,
    publicationState: ContentPublicationState.private,
    artifact: null,
  ),
  provenance: [
    if (allReasons)
      ReviewReasonProvenance.due(
        sourceId: 'srs-1',
        dueAtUtc: DateTime.utc(2026, 8, 28, 12),
      ),
    if (allReasons)
      ReviewReasonProvenance.incorrect(
        sourceId: 'attempt-1',
        occurredAtUtc: DateTime.utc(2026, 8, 27, 12),
      ),
    if (allReasons)
      ReviewReasonProvenance.reported(
        sourceId: 'report-1',
        occurredAtUtc: DateTime.utc(2026, 8, 27, 13),
        reportReason: ContentReportReason.answer,
      ),
    ReviewReasonProvenance.saved(
      sourceId: 'saved-1',
      occurredAtUtc: DateTime.utc(2026, 8, 27, 14),
    ),
  ],
);

final class _Reader implements ReviewCenterReader {
  const _Reader({required this.load});

  final Future<List<ReviewQueueItem>> Function() load;

  @override
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter) => load();
}

final class _Owners implements LocalOwnerRepository {
  const _Owners();

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'owner-1',
        createdAtUtc: DateTime.utc(2026, 8, 28),
      );

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

final class _OwnerIdentities implements ReviewOwnerIdentityReader {
  const _OwnerIdentities();

  @override
  Future<String> requireSingleActiveOwnerId() async => 'owner-1';
}

final class _SessionLauncher implements ReviewSessionLauncher {
  final Object _authorityIdentity = Object();
  var _nextId = 0;

  @override
  Object get authorityIdentity => _authorityIdentity;

  @override
  Future<PinnedReviewSessionLaunch> start({
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> items,
  }) async => PinnedReviewSessionLaunch(
    session: QuizSession(
      id: 'review-${++_nextId}',
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

  @override
  Future<void> abandon({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) async {}
}

final class _DelayedSessionLauncher implements ReviewSessionLauncher {
  const _DelayedSessionLauncher(
    this.delegate, {
    required this.persisted,
    required this.release,
  });

  final ReviewSessionLauncher delegate;
  final Completer<void> persisted;
  final Completer<void> release;

  @override
  Object get authorityIdentity => delegate.authorityIdentity;

  @override
  Future<PinnedReviewSessionLaunch> start({
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> items,
  }) async {
    final session = await delegate.start(ownerId: ownerId, items: items);
    persisted.complete();
    await release.future;
    return session;
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

final class _ReviewLessonAdapter implements LessonModeAdapter {
  const _ReviewLessonAdapter();

  @override
  LessonMode get mode => LessonMode.meaningQuiz;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) =>
      support.evidenceContext;

  @override
  Future<LessonItem> next(LessonCursor cursor) async =>
      const LessonItem(id: 'word-1');
}

final class _DurableFixture {
  const _DurableFixture({
    required this.database,
    required this.learning,
    required this.useCases,
  });

  final AppDatabase database;
  final LearningUseCases learning;
  final ReviewCenterUseCases useCases;
}

Future<_DurableFixture> _durableFixture({DateTime Function()? nowUtc}) async {
  final clock = nowUtc ?? () => _now;
  final database = AppDatabase(NativeDatabase.memory());
  await database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: 'owner-1',
          createdAtUtcMs: _now.millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category-1',
          ownerId: 'owner-1',
          name: 'review',
          normalizedName: 'review',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word-1',
          ownerId: 'owner-1',
          categoryId: 'category-1',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          contentRevision: const Value(1),
          contentChecksumSha256: Value(
            _canonicalChecksum(spelling: 'station', meaning: 'สถานี'),
          ),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  var nextId = 0;
  final learning = LearningUseCases(
    owners: DriftLocalOwnerRepository(
      database,
      generateId: () => 'generated-owner',
      nowUtc: clock,
    ),
    repository: DriftLearningRepository(database),
    generateId: () => 'review-${++nextId}',
    nowUtc: clock,
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'f22-test'),
  );
  final useCases = ReviewCenterUseCases(
    reader: _Reader(load: () async => [_item()]),
    ownerIdentities: DriftReviewOwnerIdentityReader(database),
    sessionLauncher: LearningUseCasesReviewSessionLauncher(learning),
    nowUtc: clock,
    timezoneId: 'Asia/Bangkok',
  );
  return _DurableFixture(
    database: database,
    learning: learning,
    useCases: useCases,
  );
}

Future<void> _switchToOwnerTwo(AppDatabase database) async {
  await database.transaction(() async {
    await (database.update(database.localOwners)
          ..where((row) => row.id.equals('owner-1')))
        .write(const LocalOwnersCompanion(isActive: Value(false)));
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'owner-2',
            createdAtUtcMs: _now.millisecondsSinceEpoch,
          ),
        );
  });
}

Future<List<LearningSession>> _activeSessions(AppDatabase database) =>
    (database.select(
      database.learningSessions,
    )..where((row) => row.state.equals('active'))).get();

String _canonicalChecksum({
  required String spelling,
  required String meaning,
}) => ContentQualityPolicy.vocabularyChecksumSha256(
  categoryId: 'category-1',
  spelling: spelling,
  normalizedSpelling: spelling,
  meaning: meaning,
  normalizedMeaning: meaning,
  partOfSpeech: 'noun',
  cefrLevel: null,
  source: 'manual',
  isGlobal: false,
);

SessionConfiguration _sessionConfiguration() => SessionConfiguration.validated(
  schemaVersion: sessionConfigurationSchemaVersion,
  policyVersion: sessionConfigurationPolicyVersion,
  ownerId: 'owner-1',
  mode: LessonMode.meaningQuiz,
  itemCount: 1,
  direction: SessionDirection.forward,
  difficulty: SessionDifficulty.standard,
  hintBudget: 0,
  timing: const SessionTiming.timed(Duration(minutes: 1)),
  packIdentity: null,
  protocolId: 'protocol:test',
  protocolVersion: '1',
  protocolLimitsIdentity: 'authority:test',
);

final _now = DateTime.utc(2026, 8, 28, 12);
