import 'dart:async';
import 'package:vocab_learning_app/features/achievements/presentation/achievement_share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/achievements/application/achievement_share_card_use_cases.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';

void main() {
  testWidgets('completed preview clears when the current progress changes', (
    tester,
  ) async {
    final shares = AchievementShareCardUseCases(store: _ScreenShareCardStore());
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async => _withAchievement,
          shareCards: shares,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _confirmShare(tester);
    expect(find.byType(AchievementShareCard), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async => _empty,
          shareCards: shares,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AchievementShareCard), findsNothing);
  });

  testWidgets('old share completion cannot publish a preview after reload', (
    tester,
  ) async {
    final pending = Completer<AchievementShareCardStoreResult>();
    final store = _ScreenShareCardStore()..pending = pending;
    final shares = AchievementShareCardUseCases(store: store);
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async => _withAchievement,
          shareCards: shares,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('achievement-share/first_session')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.selectionCalls, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async => _empty,
          shareCards: shares,
        ),
      ),
    );
    await tester.pumpAndSettle();
    pending.complete(
      const AchievementShareCardStoreResult.saved(destination: 'local.svg'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AchievementShareCard), findsNothing);
  });

  testWidgets('captured share action is invalid after its receipt reload', (
    tester,
  ) async {
    final store = _ScreenShareCardStore();
    final shares = AchievementShareCardUseCases(store: store);
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async => _withAchievement,
          shareCards: shares,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final oldAction = tester
        .widget<IconButton>(
          find.byKey(const ValueKey<String>('achievement-share/first_session')),
        )
        .onPressed!;
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async => _empty,
          shareCards: shares,
        ),
      ),
    );
    await tester.pumpAndSettle();
    oldAction();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(store.selectionCalls, 0);
  });

  testWidgets('achievement retry exposes pending and prevents another read', (
    tester,
  ) async {
    final pending = Completer<ProgressSnapshot>();
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () {
            reads++;
            return reads == 1
                ? Future.error(StateError('synthetic'))
                : pending.future;
          },
          onOpenQuests: () {},
          onOpenShop: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลองใหม่'));
    await tester.pump();
    expect(find.text('ลองใหม่'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('rewards-open-quests')), findsOneWidget);
    expect(find.byKey(const ValueKey('rewards-open-shop')), findsOneWidget);
    expect(reads, 2);
    pending.complete(_empty);
    await tester.pumpAndSettle();
    expect(find.text('ความสำเร็จ'), findsOneWidget);
    expect(reads, 2);
  });
  testWidgets(
    'reward hub callbacks stay available when progress cannot load and hide when absent',
    (tester) async {
      var quests = 0;
      var shop = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AchievementsScreen(
            loader: () =>
                Future.error(StateError('synthetic progress unavailable')),
            onOpenQuests: () => quests++,
            onOpenShop: () => shop++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rewards-open-quests')));
      await tester.tap(find.byKey(const ValueKey('rewards-open-shop')));
      expect([quests, shop], [1, 1]);
      await tester.pumpWidget(
        MaterialApp(home: AchievementsScreen(loader: () async => _empty)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rewards-open-quests')), findsNothing);
      expect(find.byKey(const ValueKey('rewards-open-shop')), findsNothing);
    },
  );

  testWidgets('no unlocked badges preserves nonzero answer evidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async => const ProgressSnapshot(
            sampleSize: 6,
            correctCount: 0,
            wrongCount: 6,
            accuracy: 0,
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('จำนวนหลักฐาน: 6'), findsOneWidget);
    expect(find.textContaining('จำนวนหลักฐาน: 0'), findsNothing);
    expect(find.byIcon(Icons.workspace_premium_outlined), findsNothing);
  });
  testWidgets('renders durable achievement evidence without redefining it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(loader: () async => _withAchievement),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ความสำเร็จ'), findsOneWidget);
    expect(find.text('เรียนจบเซสชันแรก'), findsOneWidget);
    expect(find.textContaining('session-1'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('achievement-details/first_session')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('session-1'), findsOneWidget);
    expect(find.textContaining('นิยาม v7'), findsOneWidget);
  });

  testWidgets('fresh account reports zero evidence without sample badges', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AchievementsScreen(loader: () async => _empty)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('จำนวนหลักฐาน: 0'), findsOneWidget);
    expect(find.byIcon(Icons.workspace_premium_outlined), findsNothing);
  });

  testWidgets('does not load while its indexed destination is inactive', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: false,
          child: AchievementsScreen(
            loader: () async {
              calls += 1;
              return _empty;
            },
          ),
        ),
      ),
    );

    expect(calls, 0);
  });

  testWidgets(
    'share action is available only for a current known unlocked achievement',
    (tester) async {
      final useCases = AchievementShareCardUseCases(
        store: _ScreenShareCardStore(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AchievementsScreen(
            loader: () async => _withAchievement,
            shareCards: useCases,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('บันทึกการ์ดความสำเร็จ: เรียนจบเซสชันแรก'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('achievement-share/first_session')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AchievementsScreen(
            loader: () async => _unknownAchievement,
            shareCards: useCases,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('บันทึกการ์ดความสำเร็จ'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('achievement-share/unknown')),
        findsNothing,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AchievementsScreen(
            loader: () async => _empty,
            shareCards: useCases,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('บันทึกการ์ดความสำเร็จ'), findsNothing);
    },
  );

  testWidgets('confirmation cancellation never opens destination selection', (
    tester,
  ) async {
    final store = _ScreenShareCardStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async => _withAchievement,
          shareCards: AchievementShareCardUseCases(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('achievement-share/first_session')),
    );
    await tester.pumpAndSettle();
    expect(find.text('บันทึกการ์ดความสำเร็จนี้?'), findsOneWidget);
    expect(
      find.bySemanticsLabel('ยืนยันการเลือกตำแหน่งบันทึกการ์ดความสำเร็จ'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'ยกเลิก'));
    await tester.pumpAndSettle();

    expect(store.selectionCalls, 0);
    expect(store.writeCalls, 0);
    expect(find.text('บันทึกการ์ดความสำเร็จนี้?'), findsNothing);
  });

  testWidgets(
    'stale confirmation cannot export after its canonical unlock disappears',
    (tester) async {
      final store = _ScreenShareCardStore();
      final useCases = AchievementShareCardUseCases(store: store);
      const screenKey = ValueKey<String>('achievement-screen');
      Future<ProgressSnapshot> Function() loader = () async => _withAchievement;
      late StateSetter updateHost;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return AchievementsScreen(
                key: screenKey,
                loader: loader,
                shareCards: useCases,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('achievement-share/first_session')),
      );
      await tester.pumpAndSettle();
      expect(find.text('บันทึกการ์ดความสำเร็จนี้?'), findsOneWidget);

      updateHost(() => loader = () async => _empty);
      await tester.pumpAndSettle();

      expect(find.text('บันทึกการ์ดความสำเร็จนี้?'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('achievement-share/first_session')),
        findsNothing,
      );
      await tester.tap(
        find.bySemanticsLabel('ยืนยันการเลือกตำแหน่งบันทึกการ์ดความสำเร็จ'),
      );
      await tester.pumpAndSettle();

      expect(store.selectionCalls, 0);
      expect(store.writeCalls, 0);
    },
  );

  testWidgets('selection cancellation is retryable and writes nothing', (
    tester,
  ) async {
    final store = _ScreenShareCardStore()
      ..results.add(const AchievementShareCardStoreResult.cancelled())
      ..results.add(
        const AchievementShareCardStoreResult.saved(
          destination: 'content://downloads/first-session.svg',
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async => _withAchievement,
          shareCards: AchievementShareCardUseCases(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _confirmShare(tester);
    expect(find.text('ยกเลิกการเลือกตำแหน่งบันทึก'), findsOneWidget);
    expect(store.selectionCalls, 1);
    expect(store.writeCalls, 0);

    await _confirmShare(tester);
    expect(find.text('บันทึกการ์ดความสำเร็จแล้ว'), findsOneWidget);
    expect(store.selectionCalls, 2);
    expect(store.writeCalls, 1);
  });

  testWidgets('write error remains retryable without exposing write details', (
    tester,
  ) async {
    final store = _ScreenShareCardStore()
      ..errors.add(StateError('injected write failure'))
      ..results.add(
        const AchievementShareCardStoreResult.saved(
          destination: 'content://downloads/first-session.svg',
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async => _withAchievement,
          shareCards: AchievementShareCardUseCases(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _confirmShare(tester);
    expect(find.text('ไม่สามารถบันทึกการ์ดความสำเร็จได้'), findsOneWidget);
    expect(find.textContaining('injected write failure'), findsNothing);
    expect(store.selectionCalls, 1);
    expect(store.writeCalls, 0);

    await tester.tap(find.widgetWithText(TextButton, 'ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    await _confirmShare(tester);

    expect(find.text('บันทึกการ์ดความสำเร็จแล้ว'), findsOneWidget);
    expect(store.selectionCalls, 2);
    expect(store.writeCalls, 1);
  });
}

Future<void> _confirmShare(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('achievement-share/first_session')),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.bySemanticsLabel('ยืนยันการเลือกตำแหน่งบันทึกการ์ดความสำเร็จ'),
  );
  await tester.pumpAndSettle();
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
      definitionVersion: 7,
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
  completedSessions: 0,
  streakDays: 1,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 1,
  gameLevel: 1,
  skills: const [],
  weaknesses: const [],
  recommendations: const [],
  achievements: [
    AchievementEvidence(
      id: 'unknown',
      definitionVersion: 1,
      sourceEventId: 'source-unknown',
      unlockedAtUtc: DateTime.utc(2026, 8, 30),
    ),
  ],
);

final class _ScreenShareCardStore implements AchievementShareCardStore {
  final results = <AchievementShareCardStoreResult>[];
  final errors = <Object>[];
  Completer<AchievementShareCardStoreResult>? pending;
  var selectionCalls = 0;
  var writeCalls = 0;

  @override
  Future<AchievementShareCardStoreResult> selectDestinationAndSave(
    AchievementShareCardArtifact artifact,
  ) async {
    selectionCalls += 1;
    if (pending != null) return pending!.future;
    if (errors.isNotEmpty) throw errors.removeAt(0);
    final result = results.isEmpty
        ? const AchievementShareCardStoreResult.saved(
            destination: 'content://downloads/first-session.svg',
          )
        : results.removeAt(0);
    if (result.status == AchievementShareCardStoreStatus.saved) {
      writeCalls += 1;
    }
    return result;
  }
}
