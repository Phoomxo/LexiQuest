import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_reaction_selector.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_reaction.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_world_catalog.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_hub_screen.dart';
import 'package:vocab_learning_app/features/adventure/presentation/widgets/adventure_companion_panel.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

void main() {
  testWidgets(
    'renders one primary mission and always-visible Standard switch',
    (tester) async {
      await tester.pumpWidget(_app(_snapshot()));

      expect(
        find.byKey(const ValueKey('adventure-standard-switch')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('adventure-primary-mission')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('adventure-start-mission')),
        findsOneWidget,
      );
      expect(find.byType(AdventureCompanionPanel), findsOneWidget);
      expect(
        find.text('Your mission is ready. Start when you are ready.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('mission CTA is single-flight', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      _app(
        _snapshot(),
        onStart: (_) {
          calls += 1;
          return pending.future;
        },
      ),
    );
    final button = find.byKey(const ValueKey('adventure-start-mission'));
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('stale, corrupt, unavailable and empty states are explicit', (
    tester,
  ) async {
    const labels = <AdventureSnapshotFreshness, String>{
      AdventureSnapshotFreshness.stale: 'ข้อมูลเส้นทางล้าสมัย กรุณารีเฟรช',
      AdventureSnapshotFreshness.corrupt: 'ข้อมูลเส้นทางไม่สมบูรณ์',
      AdventureSnapshotFreshness.unavailable: 'เส้นทางยังไม่พร้อมใช้งาน',
    };
    for (final entry in labels.entries) {
      await tester.pumpWidget(
        _app(_snapshot(freshness: entry.key, mission: false)),
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('ยังไม่มีภารกิจหลัก'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('adventure-start-mission')),
            )
            .onPressed,
        isNull,
      );
    }
  });

  testWidgets(
    'supports dark, high contrast, reduced motion and 200 percent text',
    (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(2),
            highContrast: true,
            disableAnimations: true,
          ),
          child: MaterialApp(
            theme: M3Theme.lightTheme,
            darkTheme: M3Theme.darkTheme,
            themeMode: ThemeMode.dark,
            home: AdventureHubScreen(
              snapshot: _snapshot(),
              reaction: _missionReady,
              rewardOwnership: _rewardAccount,
              onStartMission: (_) async {},
              onPresentationChanged: (_) {},
              onRefresh: () {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('adventure-standard-switch')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('adventure-map')), findsOneWidget);
    },
  );
}

Widget _app(
  AdventureJourneySnapshot snapshot, {
  Future<void> Function(AdventureMissionRef)? onStart,
}) => MaterialApp(
  theme: M3Theme.lightTheme,
  home: AdventureHubScreen(
    snapshot: snapshot,
    reaction: snapshot.primaryMission == null ? null : _missionReady,
    rewardOwnership: _rewardAccount,
    onStartMission: onStart ?? (_) async {},
    onPresentationChanged: (_) {},
    onRefresh: () {},
  ),
);

final _missionReady = const AdventureReactionSelector().select(
  catalogVersion: AdventureReactionCatalog.v1Version,
  trigger: AdventureReactionTrigger.missionReady,
  variantSeed: 0,
);

const _rewardAccount = RewardAccount(
  coinBalance: 0,
  catalogVersion: RewardCatalog.version,
  ownedItemIds: <String>{},
  equippedBySlot: <String, String>{},
  transactionCount: 0,
);

final _now = DateTime.utc(2026, 9, 4, 8);

AdventureJourneySnapshot _snapshot({
  AdventureSnapshotFreshness freshness = AdventureSnapshotFreshness.current,
  bool mission = true,
}) {
  final primary = mission
      ? AdventureMissionRef(
          missionId: 'mission:today',
          ownerId: 'owner:one',
          nodeId: 'today-mission',
          kind: AdventureMissionKind.review,
          sourceId: 'today:review',
          content: const [],
          reasonCode: 'due',
          sourceEvaluatedAtUtc: _now,
        )
      : null;
  return AdventureJourneySnapshot(
    ownerId: 'owner:one',
    evaluatedAtUtc: _now,
    sourceEvaluatedAtUtc: _now,
    catalogId: 'catalog:one',
    catalogVersion: '1.0.0',
    catalogSchemaVersion: 1,
    freshness: freshness,
    dependencyStates:
        <AdventureJourneyAuthority, AdventureJourneyDependencyState>{
          for (final authority in AdventureJourneyAuthority.values)
            authority: AdventureJourneyDependencyState.ready,
        },
    nodes: <AdventureNodeSnapshot>[
      AdventureNodeSnapshot(
        nodeId: 'today-mission',
        kind: AdventureNodeKind.mission,
        state: mission
            ? AdventureNodeState.current
            : AdventureNodeState.unavailable,
        label: 'ภารกิจวันนี้',
        accessibilityLabel: 'ภารกิจวันนี้',
        reasonCode: mission ? 'current' : 'unavailable',
        mission: primary,
      ),
    ],
    primaryMission: primary,
    inputFingerprintSha256: 'a' * 64,
  );
}
