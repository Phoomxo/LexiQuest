import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner, StreakState;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/motivation/domain/streak_policy.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_progress_reader.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_progress_models.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

final _now = DateTime.utc(2026, 11, 10, 12);

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final profile in [false, true]) {
    testWidgets(
      'progress notification refreshes visible motivation without replacing dependencies profile=$profile',
      (tester) async {
        final revision = ValueNotifier<int>(0);
        addTearDown(revision.dispose);
        var status = StreakFoldStatus.ready;
        var loads = 0;
        Future<ProgressSnapshot> load() async {
          loads++;
          return _zeroView([
            for (var i = 0; i < 7; i++) DateTime.utc(2026, 11, 9 + i),
          ], status: status);
        }

        final dependencies = AppDependencies(
          runtimeStatus: const AppRuntimeStatus(
            localData: RuntimeAvailability.ready,
            firebase: RuntimeAvailability.unavailable,
            supabase: RuntimeAvailability.unavailable,
            backends: RuntimeAvailability.unavailable,
          ),
          config: null,
          guestSessionService: _NoGuest(),
          progressUpdates: revision,
        );
        await tester.pumpWidget(
          _app(
            profile
                ? ProfileSettingsScreen(loader: load)
                : MasteryDashboardScreen(loader: load),
            dependencies: dependencies,
          ),
        );
        await tester.pumpAndSettle();
        expect(loads, 1);
        status = StreakFoldStatus.unavailable;
        revision.value++;
        await tester.pumpAndSettle();
        expect(loads, 2);
        await tester.scrollUntilVisible(
          find.text('รอตรวจวันเรียน'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('รอตรวจวันเรียน'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        revision.value++;
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'zero answers retain daily weekly and seven honest days at Thai200percent',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        final week = [
          for (var i = 0; i < 7; i++) DateTime.utc(2026, 11, 9 + i),
        ];
        final view = _zeroView(week);
        await tester.pumpWidget(
          _app(MasteryDashboardScreen(loader: () async => view), scale: 2),
        );
        await tester.pumpAndSettle();
        expect(find.text('วันเรียนของสัปดาห์นี้'), findsOneWidget);
        await _capture(tester, 's6-d4-mastery-200.png');
        for (final day in week) {
          final label = day.toIso8601String().substring(0, 10);
          final tile = find.byKey(ValueKey('learning-day:$label'));
          expect(tile, findsOneWidget);
          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          final spoken = tester.getSemantics(tile).getSemanticsData().label;
          expect(spoken, contains(label));
          expect(spoken, contains('ยังไม่ได้เรียน'));
        }
        expect(find.text('รับ 50 XP'), findsNothing);
        expect(tester.takeException(), isNull);
        await _capture(tester, 's6-d4-mastery-200-scrolled.png');
        for (final title in [
          'ภารกิจรายวัน',
          'ภารกิจรายสัปดาห์',
          'ความแม่นยำ',
        ]) {
          await tester.scrollUntilVisible(
            find.text(title),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text(title), findsOneWidget);
        }
        expect(find.text('0%'), findsNothing);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'explicit claim disables duplicate tap and issues one real XP reward',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      addTearDown(f.db.close);
      await tester.pumpWidget(
        _app(
          MasteryDashboardScreen(loader: f.load),
          dependencies: f.dependencies,
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('รับ 50 XP').evaluate().isNotEmpty,
      );
      expect(
        (await tester.runAsync(
          () => f.db.select(f.db.questClaimReceipts).get(),
        ))!,
        isEmpty,
      );
      final beforeOutbox = (await tester.runAsync(
        () => f.db.select(f.db.outboxOperations).get(),
      ))!.length;
      f.owners.gate = await tester.runAsync(
        () async => Completer<LocalOwner>(),
      );
      final button = find.text('รับ 50 XP');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(ValueKey('quest-claim:${f.period}')),
            )
            .onPressed,
        isNull,
      );
      f.owners.gate!.complete(
        LocalOwner(id: 'a', createdAtUtc: DateTime.utc(2026)),
      );
      f.owners.gate = null;
      await _pumpUntil(
        tester,
        () => find.text('รับแล้ว').evaluate().isNotEmpty,
      );
      final after = (await tester.runAsync(f.load))!;
      expect(after.totalXp, 55);
      expect((await tester.runAsync(() => f.rewards.load()))!.balance, 5);
      expect(
        (await tester.runAsync(
          () => f.db.select(f.db.questClaimReceipts).get(),
        ))!,
        hasLength(1),
      );
      expect(
        (await tester.runAsync(
          () => f.db.select(f.db.outboxOperations).get(),
        ))!,
        hasLength(beforeOutbox),
      );
      expect(
        (await tester.runAsync(() => f.db.select(f.db.eventsV2).get()))!,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'owner change during claim suppresses the old card and writes no reward',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      addTearDown(f.db.close);
      await tester.pumpWidget(
        _app(
          MasteryDashboardScreen(loader: f.load),
          dependencies: f.dependencies,
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('รับ 50 XP').evaluate().isNotEmpty,
      );
      f.owners.gate = await tester.runAsync(
        () async => Completer<LocalOwner>(),
      );
      await tester.ensureVisible(find.text('รับ 50 XP'));
      await tester.tap(find.text('รับ 50 XP'));
      await tester.pump();
      await tester.runAsync(
        () => f.db.customStatement(
          "UPDATE local_owners SET is_active=CASE WHEN id='b' THEN 1 ELSE 0 END",
        ),
      );
      f.owners.id = 'b';
      f.owners.gate!.complete(
        LocalOwner(id: 'a', createdAtUtc: DateTime.utc(2026)),
      );
      f.owners.gate = null;
      await _pumpUntil(
        tester,
        () => find.textContaining('เจ้าของข้อมูลเปลี่ยน').evaluate().isNotEmpty,
      );
      expect(
        (await tester.runAsync(
          () => f.db.select(f.db.questClaimReceipts).get(),
        ))!,
        isEmpty,
      );
      final bPoints = await tester.runAsync(
        () => f.db
            .customSelect(
              "SELECT COUNT(*) AS n FROM points_ledger_entries WHERE owner_id='b'",
            )
            .getSingle(),
      );
      expect(bPoints!.read<int>('n'), 0);
      expect(find.text('รับแล้ว'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  testWidgets(
    'replacing claim dependencies does not let the old reply clear the new request',
    (tester) async {
      final old = (await tester.runAsync(_Fixture.create))!;
      final next = (await tester.runAsync(_Fixture.create))!;
      addTearDown(old.db.close);
      addTearDown(next.db.close);
      expect(old.period, next.period);
      var nextStarted = false;
      void release(_Owners owners) {
        final gate = owners.gate;
        if (gate != null && !gate.isCompleted) {
          gate.complete(LocalOwner(id: 'a', createdAtUtc: DateTime.utc(2026)));
        }
        owners.gate = null;
      }

      try {
        await tester.pumpWidget(
          _app(
            MasteryDashboardScreen(loader: old.load),
            dependencies: old.dependencies,
          ),
        );
        await _pumpUntil(
          tester,
          () => find.text('รับ 50 XP').evaluate().isNotEmpty,
        );
        old.owners.gate = await tester.runAsync(
          () async => Completer<LocalOwner>(),
        );
        await tester.ensureVisible(find.text('รับ 50 XP'));
        await tester.tap(find.text('รับ 50 XP'));
        await tester.pump();
        await tester.pumpWidget(
          _app(
            MasteryDashboardScreen(loader: next.load),
            dependencies: next.dependencies,
          ),
        );
        final button = find.byKey(ValueKey('quest-claim:${next.period}'));
        await _pumpUntil(tester, () => button.evaluate().isNotEmpty);
        expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
        next.owners.gate = await tester.runAsync(
          () async => Completer<LocalOwner>(),
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        nextStarted = true;
        await tester.pump();
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        release(old.owners);
        await _pumpUntil(tester, () => old.owners.reads >= 2);
        await tester.pump();
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        release(next.owners);
        await _pumpUntil(
          tester,
          () => find.text('รับแล้ว').evaluate().isNotEmpty,
        );
        expect((await tester.runAsync(next.load))!.totalXp, 55);
        expect((await tester.runAsync(old.load))!.totalXp, 55);
        expect(tester.takeException(), isNull);
      } finally {
        release(old.owners);
        release(next.owners);
        for (
          var i = 0;
          i < 100 &&
              (old.owners.reads < 2 || (nextStarted && next.owners.reads < 2));
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Widget _app(Widget home, {AppDependencies? dependencies, double scale = 1}) {
  final app = MaterialApp(
    theme: M3Theme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: RepaintBoundary(
      key: const ValueKey('motivation-capture'),
      child: home,
    ),
  );
  return dependencies == null
      ? app
      : AppDependenciesScope(dependencies: dependencies, child: app);
}

ProgressSnapshot _zeroView(
  List<DateTime> week, {
  StreakFoldStatus status = StreakFoldStatus.ready,
}) => ProgressSnapshot(
  ownerId: 'a',
  asOfUtc: _now,
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
  skills: const [],
  weaknesses: const [],
  recommendations: const [],
  quests: QuestSummary(
    current: [
      for (final daily in [true, false])
        QuestProgressCard(
          instanceId: daily ? 'daily' : 'weekly',
          cadence: daily ? QuestType.daily : QuestType.weekly,
          civilLabel: '2026-11-10',
          title: 'Synthetic',
          targetCount: daily ? 5 : 20,
          xpAmount: daily ? 50 : 200,
          correctCount: 0,
          completedAtUtc: null,
          lastEndUtc: DateTime.utc(2026, 11, 16),
          state: QuestProgressState.active,
        ),
    ],
    history: const [],
    issues: const [],
  ),
  learningDays: StreakFoldResult(
    state: StreakState.initial(
      ownerId: 'a',
      nowMs: _now.millisecondsSinceEpoch,
    ),
    currentStreakDays: 0,
    days: [
      for (final day in week)
        StreakDayMarker(day: day, studied: false, protected: false),
    ],
    status: status,
    uncertainHistory: false,
  ),
);

class _Owners implements LocalOwnerRepository {
  String id = 'a';
  int reads = 0;
  Completer<LocalOwner>? gate;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() {
    reads++;
    return gate?.future ??
        Future.value(LocalOwner(id: id, createdAtUtc: DateTime.utc(2026)));
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() => throw UnimplementedError();
}

class _Fixture {
  _Fixture(this.db, this.owners, this.rewards, this.queries, this.period);
  final AppDatabase db;
  final _Owners owners;
  final RewardUseCases rewards;
  final DriftProgressQueries queries;
  final String period;
  AppDependencies get dependencies => AppDependencies(
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _NoGuest(),
    rewards: rewards,
    localOwners: owners,
  );
  Future<ProgressSnapshot> load() =>
      queries.load(ownerId: owners.id, nowUtc: _now);

  static Future<_Fixture> create() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES ('a',1,1),('b',1,0)",
    );
    await db.customStatement(
      "INSERT INTO vocabulary_categories(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES ('cat','a','Synthetic','synthetic',1,1)",
    );
    await db.customStatement(
      "INSERT INTO vocabulary_words(id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) VALUES ('word','a','cat','test','test','ทดสอบ','ทดสอบ','noun',1,1)",
    );
    final catalog = await DriftQuestRepository(db).installAnswerCatalog();
    final learning = DriftLearningRepository(
      db,
      questCatalog: catalog,
      questVisible: () => true,
    );
    await learning.startSession(
      LearningSessionDraft(
        id: 'session',
        ownerId: 'a',
        activityType: 'quiz',
        startedAtUtc: _now,
        appVersion: 'synthetic',
        buildId: 'synthetic',
      ),
    );
    for (var i = 0; i < 5; i++) {
      await learning.recordAnswer(
        RecordAnswerCommand(
          id: 'answer-$i',
          ownerId: 'a',
          sessionId: 'session',
          wordId: 'word',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 100,
          attemptNumber: i + 1,
          occurredAtUtc: _now,
        ),
      );
    }
    final reader = DriftQuestProgressReader(db, catalog: catalog);
    final period = (await reader.load(ownerId: 'a', asOfUtc: _now)).current
        .singleWhere((card) => card.cadence == QuestType.daily)
        .instanceId;
    final owners = _Owners();
    final rewards = RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(
        db,
        questCatalog: catalog,
        questVisible: () => true,
        nowUtc: () => _now,
      ),
      generateId: () => 'unused',
      nowUtc: () => _now,
    );
    return _Fixture(
      db,
      owners,
      rewards,
      DriftProgressQueries(db, questReader: reader, questVisible: () => true),
      period,
    );
  }
}

Future<void> _capture(WidgetTester tester, String filename) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('motivation-capture')),
  );
  await tester.runAsync(() async {
    final captured = await boundary.toImage(pixelRatio: 1);
    final bytes = await captured.toByteData(format: ui.ImageByteFormat.png);
    captured.dispose();
    await File('build/$filename').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('Timed out waiting for the real local motivation operation');
}
