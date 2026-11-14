import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  _f31Tests();
  testWidgets('announces achievement loading state', (tester) async {
    final pending = Completer<ProgressSnapshot>();
    await tester.pumpWidget(
      MaterialApp(home: AchievementsScreen(loader: () => pending.future)),
    );
    await tester.pump();

    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังอ่านประวัติความสำเร็จ',
    );
  });

  testWidgets('renders only stored achievement evidence', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(loader: () async => _withAchievement),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ความสำเร็จ'), findsOneWidget);
    expect(find.text('เรียนจบรอบแรก'), findsOneWidget);
    expect(find.text('คะแนนประสบการณ์'), findsOneWidget);
    expect(find.text('รวม XP จากคำตอบและภารกิจที่บันทึกไว้'), findsOneWidget);
    expect(find.text('เรียนจบรอบที่มีคำตอบอย่างน้อย 1 ครั้ง'), findsOneWidget);
    expect(find.text('30/07/2026'), findsOneWidget);
    expect(find.textContaining('session-1'), findsNothing);
    expect(find.textContaining('วิธีคำนวณรุ่น'), findsNothing);
    expect(find.textContaining('เกณฑ์รุ่น'), findsNothing);
  });

  testWidgets('fresh account reports zero evidence without sample badges', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AchievementsScreen(loader: () async => _empty)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('ยังไม่มีคำตอบที่บันทึกไว้'), findsOneWidget);
    expect(find.byIcon(Icons.workspace_premium_outlined), findsNothing);
  });

  testWidgets('unknown achievement identifier stays internal', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(loader: () async => _unknownAchievement),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ความสำเร็จจากการเรียน'), findsOneWidget);
    expect(find.textContaining('internal_badge_v7'), findsNothing);
  });

  testWidgets('retry recovers one failed achievement read', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async {
            if (calls++ == 0) throw StateError('synthetic failure');
            return _withAchievement;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('ไม่สามารถอ่านประวัติความสำเร็จในเครื่องได้'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsAtLeastNWidgets(1),
    );

    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('เรียนจบรอบแรก'), findsOneWidget);
  });
}

final _withAchievement = ProgressSnapshot(
  sampleSize: 2,
  correctCount: 2,
  wrongCount: 0,
  accuracy: 1,
  totalXp: 2,
  completedSessions: 1,
  streakDays: 1,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 1,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
  achievements: [
    AchievementEvidence(
      id: 'first_session',
      definitionVersion: 1,
      sourceEventId: 'session-1',
      unlockedAtUtc: DateTime.utc(2026, 7, 30),
    ),
  ],
);

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

final _unknownAchievement = ProgressSnapshot(
  sampleSize: 1,
  correctCount: 1,
  wrongCount: 0,
  accuracy: 1,
  totalXp: 1,
  completedSessions: 1,
  streakDays: 1,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 1,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
  achievements: [
    AchievementEvidence(
      id: 'internal_badge_v7',
      definitionVersion: 1,
      sourceEventId: 'internal-event-7',
      unlockedAtUtc: DateTime.utc(2026, 10, 24),
    ),
  ],
);

const _knownTitles = {
  'first_answer': 'บันทึกคำตอบครั้งแรก',
  'first_correct': 'ตอบถูกครั้งแรก',
  'ten_correct': 'ตอบถูกครบ 10 ครั้ง',
  'first_session': 'เรียนจบรอบแรก',
  'perfect_session': 'ตอบถูกครบทั้งรอบ',
};
const _knownConditions = {
  'first_answer': 'บันทึกคำตอบอย่างน้อย 1 ครั้ง',
  'first_correct': 'บันทึกคำตอบถูกอย่างน้อย 1 ครั้ง',
  'ten_correct': 'บันทึกคำตอบถูกอย่างน้อย 10 ครั้ง',
  'first_session': 'เรียนจบรอบที่มีคำตอบอย่างน้อย 1 ครั้ง',
  'perfect_session': 'เรียนจบรอบที่มีคำตอบอย่างน้อย 1 ครั้ง และไม่มีคำตอบผิด',
};

ProgressSnapshot _f31View({
  String ownerId = 'synthetic-a',
  int totalXp = 55,
  int sampleSize = 5,
  List<AchievementEvidence> achievements = const [],
}) => ProgressSnapshot(
  ownerId: ownerId,
  asOfUtc: DateTime.utc(2026, 11, 14),
  sampleSize: sampleSize,
  correctCount: sampleSize,
  wrongCount: 0,
  accuracy: sampleSize == 0 ? null : 1,
  totalXp: totalXp,
  completedSessions: 1,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: achievements.length,
  gameLevel: 1,
  skills: const [],
  weaknesses: const [],
  recommendations: const [],
  achievements: achievements,
);

List<AchievementEvidence> _fiveEarned() => [
  for (final (index, key) in _knownTitles.keys.indexed)
    AchievementEvidence(
      id: key,
      definitionVersion: 1,
      sourceEventId: 'synthetic-retained-source-$index',
      unlockedAtUtc: DateTime.utc(2024, 2, index + 1, 23, 59),
    ),
];

void _f31Tests() {
  testWidgets('f31 retained empty-round v1 labels only the current condition', (
    tester,
  ) async {
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: AchievementsScreen(
            loader: () async => _f31View(
              sampleSize: 0,
              totalXp: 0,
              achievements: [
                AchievementEvidence(
                  id: 'first_session',
                  definitionVersion: 1,
                  sourceEventId: 'synthetic-legacy-empty-round',
                  unlockedAtUtc: DateTime.utc(2023, 5, 17),
                ),
              ],
            ),
          ),
        ),
      );
      await _f31Frames(tester);
      final tile = find.ancestor(
        of: find.text('17/05/2023'),
        matching: find.byType(ListTile),
      );
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text('เรียนจบรอบแรก')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text('เงื่อนไขปัจจุบัน')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.text('เรียนจบรอบที่มีคำตอบอย่างน้อย 1 ครั้ง'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('synthetic-legacy-empty-round'), findsNothing);
      expect(find.text('ปลดล็อกจากคำตอบที่บันทึกไว้'), findsNothing);
      expect(find.textContaining('1 คำตอบที่บันทึกไว้'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'f31 names all five retained v1 unlocks with their original dates',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(900, 2400);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: AchievementsScreen(
              loader: () async => _f31View(achievements: _fiveEarned()),
            ),
          ),
        );
        await _f31Frames(tester);
        for (final (index, key) in _knownTitles.keys.indexed) {
          final title = find.text(_knownTitles[key]!);
          expect(title, findsOneWidget);
          final tile = find.ancestor(
            of: title,
            matching: find.byType(ListTile),
          );
          expect(
            find.descendant(
              of: tile,
              matching: find.text('0${index + 1}/02/2024'),
            ),
            findsOneWidget,
            reason: 'render the retained UTC date, not a rebuild/current date',
          );
          expect(
            find.descendant(
              of: tile,
              matching: find.text(_knownConditions[key]!),
            ),
            findsOneWidget,
          );
        }
        expect(find.byIcon(Icons.workspace_premium_outlined), findsNWidgets(5));
        expect(find.textContaining('synthetic-retained-source'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );

  testWidgets('f31 locked conditions do not pretend unknown history is zero', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 2400);
    try {
      await tester.pumpWidget(
        MaterialApp(home: AchievementsScreen(loader: () async => _f31View())),
      );
      await _f31Frames(tester);
      for (final title in _knownTitles.values) {
        expect(find.text(title), findsOneWidget);
      }
      for (final condition in _knownConditions.values) {
        expect(find.text(condition), findsOneWidget);
      }
      expect(find.textContaining('ยังไม่ปลดล็อก'), findsWidgets);
      expect(find.textContaining('0/10'), findsNothing);
      expect(find.textContaining('0 จาก 10'), findsNothing);
      expect(find.textContaining('ยังไม่มีคำตอบที่บันทึกไว้'), findsNothing);
      expect(find.byIcon(Icons.workspace_premium_outlined), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('f31 unknown key and known-key legacy version stay neutral', (
    tester,
  ) async {
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: AchievementsScreen(
            loader: () async => _f31View(
              achievements: [
                AchievementEvidence(
                  id: 'internal_legacy_key',
                  definitionVersion: 1,
                  sourceEventId: 'internal-legacy-source',
                  unlockedAtUtc: DateTime.utc(2020, 10, 24),
                ),
                AchievementEvidence(
                  id: 'first_session',
                  definitionVersion: 7,
                  sourceEventId: 'internal-versioned-source',
                  unlockedAtUtc: DateTime.utc(2021, 10, 25),
                ),
              ],
            ),
          ),
        ),
      );
      await _f31Frames(tester);
      for (final date in ['24/10/2020', '25/10/2021']) {
        await tester.scrollUntilVisible(find.text(date), 180, maxScrolls: 20);
        final tile = find.ancestor(
          of: find.text(date),
          matching: find.byType(ListTile),
        );
        expect(
          find.descendant(
            of: tile,
            matching: find.text('ความสำเร็จจากการเรียน'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: tile,
            matching: find.text('ปลดล็อกจากคำตอบที่บันทึกไว้'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: tile, matching: find.text('เรียนจบรอบแรก')),
          findsNothing,
        );
      }
      expect(find.textContaining('internal_legacy_key'), findsNothing);
      expect(find.textContaining('internal-'), findsNothing);
      expect(find.textContaining('รุ่น 7'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('f31 XP caption includes Quest XP without inventing answers', (
    tester,
  ) async {
    try {
      await tester.pumpWidget(
        MaterialApp(home: AchievementsScreen(loader: () async => _f31View())),
      );
      await _f31Frames(tester);
      expect(find.text('55'), findsOneWidget);
      expect(find.text('รวม XP จากคำตอบและภารกิจที่บันทึกไว้'), findsOneWidget);
      expect(find.text('คำนวณจาก 5 คำตอบที่บันทึกไว้'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('f31 retry and Back remain reachable at Thai 200 percent', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 640);
    var calls = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: M3Theme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: RepaintBoundary(
              key: const ValueKey('achievement-capture'),
              child: child!,
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => AchievementsScreen(
                      loader: () async {
                        if (calls++ == 0) {
                          throw StateError('synthetic f31 read');
                        }
                        return _f31View(achievements: _fiveEarned());
                      },
                    ),
                  ),
                ),
                child: const Text('เปิดความสำเร็จ'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('เปิดความสำเร็จ'));
      await tester.pump(const Duration(milliseconds: 350));
      await _f31Frames(tester);
      expect(
        find.text('ไม่สามารถอ่านประวัติความสำเร็จในเครื่องได้'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('ลองใหม่'));
      await tester.pump();
      expect(find.text('ลองใหม่').hitTestable(), findsOneWidget);
      await tester.tap(find.text('ลองใหม่'));
      await _f31Frames(tester);
      await tester.scrollUntilVisible(
        find.text(_knownConditions['perfect_session']!),
        160,
        maxScrolls: 30,
      );
      expect(find.text(_knownConditions['perfect_session']!), findsOneWidget);
      final lastCard = find.ancestor(
        of: find.text(_knownConditions['perfect_session']!),
        matching: find.byType(ListTile),
      );
      final currentCondition = find.descendant(
        of: lastCard,
        matching: find.text('เงื่อนไขปัจจุบัน'),
      );
      final originalDate = find.descendant(
        of: lastCard,
        matching: find.text('05/02/2024'),
      );
      await Scrollable.ensureVisible(
        tester.element(originalDate),
        alignment: 1,
      );
      await _f31Frames(tester);
      expect(currentCondition.hitTestable(), findsOneWidget);
      expect(originalDate.hitTestable(), findsOneWidget);
      expect(
        find.text(_knownConditions['perfect_session']!).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(calls, 2);
      await _captureF31(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('เปิดความสำเร็จ'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('f31 replaced loader hides late A and retains the B result', (
    tester,
  ) async {
    final old = Completer<ProgressSnapshot>();
    final next = Completer<ProgressSnapshot>();
    Future<ProgressSnapshot> a() => old.future;
    Future<ProgressSnapshot> b() => next.future;
    Widget screen(AchievementProgressLoader loader) =>
        MaterialApp(home: AchievementsScreen(loader: loader));
    try {
      await tester.pumpWidget(screen(a));
      await tester.pump();
      await tester.pumpWidget(screen(b));
      next.complete(_f31View(totalXp: 222));
      await _f31Frames(tester);
      expect(find.text('222'), findsOneWidget);
      old.complete(_f31View(totalXp: 111, achievements: _fiveEarned()));
      await _f31Frames(tester);
      expect(find.text('111'), findsNothing);
      expect(find.text('01/02/2024'), findsNothing);
      expect(find.text('222'), findsOneWidget);
    } finally {
      if (!old.isCompleted) old.complete(_f31View());
      if (!next.isCompleted) next.complete(_f31View());
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('f31 replaced dependency scope refreshes even the same loader', (
    tester,
  ) async {
    final old = Completer<ProgressSnapshot>();
    final next = Completer<ProgressSnapshot>();
    final oldUpdates = ValueNotifier<int>(0);
    final nextUpdates = ValueNotifier<int>(0);
    var reads = 0;
    Future<ProgressSnapshot> load() => reads++ == 0 ? old.future : next.future;
    final a = _f31Dependencies(updates: oldUpdates);
    final b = _f31Dependencies(updates: nextUpdates);
    Widget screen(AppDependencies scope) => AppDependenciesScope(
      dependencies: scope,
      child: MaterialApp(home: AchievementsScreen(loader: load)),
    );
    try {
      await tester.pumpWidget(screen(a));
      await tester.pump();
      await tester.pumpWidget(screen(b));
      next.complete(_f31View(ownerId: 'synthetic-b', totalXp: 222));
      await _f31Frames(tester);
      expect(reads, 2);
      expect(find.text('222'), findsOneWidget);
      old.complete(_f31View(totalXp: 111, achievements: _fiveEarned()));
      await _f31Frames(tester);
      expect(find.text('111'), findsNothing);
      expect(find.text('01/02/2024'), findsNothing);
      oldUpdates.value++;
      await _f31Frames(tester);
      expect(reads, 2, reason: 'the replaced notifier must be detached');
    } finally {
      if (!old.isCompleted) old.complete(_f31View());
      if (!next.isCompleted) next.complete(_f31View());
      await tester.pumpWidget(const SizedBox.shrink());
      oldUpdates.dispose();
      nextUpdates.dispose();
    }
  });

  testWidgets(
    'f31 real owner refresh hides A while B is loading without awards',
    (tester) async {
      final f = (await tester.runAsync(_F31Fixture.create))!;
      Completer<LocalOwner>? pending;
      try {
        final before = await tester.runAsync(f.snapshot);
        await tester.pumpWidget(f.screen());
        await _f31Wait(
          tester,
          () => find.text('03/03/2022').evaluate().isNotEmpty,
        );
        expect(find.text('เรียนจบรอบแรก'), findsOneWidget);
        await tester.runAsync(
          () => f.db.customStatement(
            "UPDATE local_owners SET is_active=CASE WHEN id='synthetic-b' THEN 1 ELSE 0 END",
          ),
        );
        pending = await tester.runAsync(() async => Completer<LocalOwner>());
        f.owners.pending = pending;
        f.updates.value++;
        await tester.pump();
        expect(find.text('03/03/2022'), findsNothing);
        pending!.complete(
          LocalOwner(id: 'synthetic-b', createdAtUtc: DateTime.utc(2020)),
        );
        f.owners.pending = null;
        await _f31Wait(
          tester,
          () => find.text('04/04/2023').evaluate().isNotEmpty,
        );
        expect(find.text('03/03/2022'), findsNothing);
        expect(find.text('ตอบถูกครบทั้งรอบ'), findsOneWidget);
        final after = await tester.runAsync(f.snapshot);
        for (final table in before!.keys.where(
          (key) => key != 'local_owners',
        )) {
          expect(
            after![table],
            before[table],
            reason: 'reading $table is not an award command',
          );
        }
      } finally {
        if (pending != null && !pending.isCompleted) {
          pending.complete(
            LocalOwner(id: 'synthetic-b', createdAtUtc: DateTime.utc(2020)),
          );
        }
        f.owners.pending = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await f.close(tester);
      }
    },
  );

  testWidgets('f31 opening real SQLite collection changes no persisted table', (
    tester,
  ) async {
    final f = (await tester.runAsync(_F31Fixture.create))!;
    try {
      final before = await tester.runAsync(f.snapshot);
      await tester.pumpWidget(f.screen());
      await _f31Wait(
        tester,
        () => find.text('03/03/2022').evaluate().isNotEmpty,
      );
      expect(await tester.runAsync(f.snapshot), before);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await f.close(tester);
    }
  });

  testWidgets('f31 late A owner read cannot replace already visible B evidence', (
    tester,
  ) async {
    final f = (await tester.runAsync(_F31Fixture.create))!;
    final oldRead = (await tester.runAsync(
      () async => Completer<LocalOwner>(),
    ))!;
    try {
      f.owners.nextRead = oldRead;
      await tester.pumpWidget(f.screen());
      await tester.pump();
      await tester.runAsync(
        () => f.db.customStatement(
          "UPDATE local_owners SET is_active=CASE WHEN id='synthetic-b' THEN 1 ELSE 0 END",
        ),
      );
      final beforeRead = await tester.runAsync(f.snapshot);
      f.updates.value++;
      await _f31Wait(
        tester,
        () => find.text('04/04/2023').evaluate().isNotEmpty,
      );
      final completedReads = f.owners.completedReads;
      oldRead.complete(
        LocalOwner(id: 'synthetic-a', createdAtUtc: DateTime.utc(2020)),
      );
      // Pump through both the held read and its actual post-query owner check.
      await _f31Wait(
        tester,
        () => f.owners.completedReads >= completedReads + 2,
      );
      await _f31Frames(tester);
      expect(find.text('03/03/2022'), findsNothing);
      expect(find.text('04/04/2023'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(await tester.runAsync(f.snapshot), beforeRead);
    } finally {
      if (!oldRead.isCompleted) {
        oldRead.complete(
          LocalOwner(id: 'synthetic-a', createdAtUtc: DateTime.utc(2020)),
        );
      }
      f.owners.nextRead = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await f.close(tester);
    }
  });
}

Future<void> _f31Frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _captureF31(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('achievement-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/s7-achievements-200.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _f31Wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) {
      return;
    }
  }
  fail('Timed out waiting for the real f31 collection read');
}

AppDependencies _f31Dependencies({
  required ValueNotifier<int> updates,
  AppDatabase? database,
  LocalOwnerRepository? owners,
  ProgressUseCases? progress,
}) => AppDependencies(
  runtimeStatus: const AppRuntimeStatus(
    localData: RuntimeAvailability.ready,
    firebase: RuntimeAvailability.unavailable,
    supabase: RuntimeAvailability.unavailable,
    backends: RuntimeAvailability.unavailable,
  ),
  config: null,
  guestSessionService: _F31Guest(),
  database: database,
  localOwners: owners,
  progress: progress,
  progressUpdates: updates,
);

final class _F31Guest extends Fake implements GuestSessionService {}

final class _F31Owners implements LocalOwnerRepository {
  _F31Owners(this.delegate);
  final LocalOwnerRepository delegate;
  Completer<LocalOwner>? pending;
  Completer<LocalOwner>? nextRead;
  int completedReads = 0;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() {
    final next = nextRead;
    if (next != null) {
      nextRead = null;
      return next.future.whenComplete(() => completedReads++);
    }
    return (pending?.future ?? delegate.getOrCreateActiveOwner()).whenComplete(
      () => completedReads++,
    );
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      delegate.bindFirebaseUid(ownerId, firebaseUid);
}

final class _F31Fixture {
  final db = AppDatabase(NativeDatabase.memory());
  final updates = ValueNotifier<int>(0);
  late final _F31Owners owners;
  late final AppDependencies dependencies;

  static Future<_F31Fixture> create() async {
    final f = _F31Fixture();
    f.owners = _F31Owners(
      DriftLocalOwnerRepository(
        f.db,
        generateId: () => 'unused-synthetic-owner',
        nowUtc: () => DateTime.utc(2026, 11, 14),
      ),
    );
    await f.db.customStatement(
      "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES ('synthetic-a',1,1),('synthetic-b',1,0)",
    );
    // Explicitly synthetic retained legacy unlocks, not newly proven awards.
    for (final (owner, key, date) in [
      ('synthetic-a', 'first_session', DateTime.utc(2022, 3, 3)),
      ('synthetic-b', 'perfect_session', DateTime.utc(2023, 4, 4)),
    ]) {
      await f.db.customStatement(
        'INSERT INTO achievement_unlocks(id,owner_id,achievement_id,definition_version,source_event_id,unlocked_at_utc_ms) VALUES (?,?,?,?,?,?)',
        [
          'synthetic-unlock-$owner',
          owner,
          key,
          1,
          'synthetic-retained-$owner',
          date.millisecondsSinceEpoch,
        ],
      );
    }
    final progress = ProgressUseCases(
      owners: f.owners,
      queries: DriftProgressQueries(f.db),
      nowUtc: () => DateTime.utc(2026, 11, 14),
    );
    f.dependencies = _f31Dependencies(
      updates: f.updates,
      database: f.db,
      owners: f.owners,
      progress: progress,
    );
    // Open/read the actual schema before the UI's no-write baseline.
    await progress.load();
    return f;
  }

  Widget screen() => AppDependenciesScope(
    dependencies: dependencies,
    child: const MaterialApp(home: AchievementsScreen()),
  );

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async => {
    for (final table in db.allTables)
      table.actualTableName: [
        for (final row
            in await db
                .customSelect(
                  'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
                )
                .get())
          Map<String, Object?>.of(row.data),
      ],
  };

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    updates.dispose();
    var closed = false;
    final closing = db.close().whenComplete(() => closed = true);
    closing.ignore();
    await _f31Wait(tester, () => closed);
    await closing;
    await tester.pump();
  }
}
