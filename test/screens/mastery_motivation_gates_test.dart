import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner, StreakState;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/streak_policy.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_progress_models.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

final _now = DateTime.utc(2026, 11, 10, 12);

void main() {
  for (final hidden in ['quest', 'mastery', 'field-mastery']) {
    testWidgets(
      '$hidden gate suppresses Quest and respects Streak visibility',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final dependencies = _dependencies(db, hidden: hidden);
        final view = _snapshot(
          current: [_card('current', QuestProgressState.completedUnclaimed)],
        );
        await tester.pumpWidget(
          _app(dependencies, MasteryDashboardScreen(loader: () async => view)),
        );
        await tester.pumpAndSettle();
        expect(find.text('ภารกิจรายวัน'), findsNothing);
        expect(find.byKey(const ValueKey('quest-claim:current')), findsNothing);
        if (hidden == 'quest') {
          expect(find.text('วันเรียนของสัปดาห์นี้'), findsOneWidget);
          expect(find.text('เรียนต่อเนื่อง'), findsOneWidget);
        } else {
          expect(find.text('วันเรียนของสัปดาห์นี้'), findsNothing);
          expect(find.text('เรียนต่อเนื่อง'), findsNothing);
        }
        await tester.pumpWidget(
          _app(dependencies, ProfileSettingsScreen(loader: () async => view)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('เรียนต่อเนื่อง'),
          hidden == 'quest' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'all historical cards remain visible and only completed history can be claimed',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final history = [
          for (var i = 0; i < 12; i++)
            _card('legacy-$i', QuestProgressState.legacy),
          _card('conflict', QuestProgressState.conflict),
          _card('expired', QuestProgressState.expired),
          _card('old-complete', QuestProgressState.completedUnclaimed),
        ];
        await tester.pumpWidget(
          _app(
            _dependencies(db),
            MasteryDashboardScreen(
              loader: () async => _snapshot(history: history),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('quest-claim:old-complete')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('quest-claim:old-complete')),
              )
              .onPressed,
          isNotNull,
        );
        for (final id in ['legacy-0', 'legacy-11', 'conflict', 'expired']) {
          expect(find.byKey(ValueKey('quest-claim:$id')), findsNothing);
        }
        final tile = find.byKey(const ValueKey('learning-day:2026-11-09'));
        final label = tester.getSemantics(tile).getSemanticsData().label;
        expect(label, contains('เรียนแล้ว'));
        expect(label, contains('ใช้สิทธิ์รักษาวันเรียนแล้ว'));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}

Widget _app(AppDependencies dependencies, Widget child) => AppDependenciesScope(
  dependencies: dependencies,
  child: MaterialApp(home: child),
);

AppDependencies _dependencies(AppDatabase db, {String? hidden}) {
  final owners = _Owners();
  return AppDependencies(
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _Guest(),
    features: BuildFeatureRegistry({
      Feature.mastery: hidden == 'mastery'
          ? FeatureState.hidden
          : FeatureState.enabled,
      Feature.questV2: hidden == 'quest'
          ? FeatureState.hidden
          : FeatureState.enabled,
    }),
    fieldFeatures: BuildFieldFeatureRegistry({
      FieldFeature.mastery: hidden == 'field-mastery'
          ? FieldFeatureState.hidden
          : FieldFeatureState.enabled,
    }),
    rewards: RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(db),
      generateId: () => 'unused',
      nowUtc: () => _now,
    ),
  );
}

ProgressSnapshot _snapshot({
  List<QuestProgressCard> current = const [],
  List<QuestProgressCard> history = const [],
}) => ProgressSnapshot(
  ownerId: 'a',
  asOfUtc: _now,
  sampleSize: 1,
  correctCount: 1,
  wrongCount: 0,
  accuracy: 1,
  totalXp: 1,
  completedSessions: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: const [],
  weaknesses: const [],
  recommendations: const [],
  quests: QuestSummary(current: current, history: history, issues: const []),
  learningDays: StreakFoldResult(
    state: StreakState.initial(
      ownerId: 'a',
      nowMs: _now.millisecondsSinceEpoch,
    ),
    currentStreakDays: 1,
    status: StreakFoldStatus.ready,
    uncertainHistory: false,
    days: [
      for (var i = 0; i < 7; i++)
        StreakDayMarker(
          day: DateTime.utc(2026, 11, 9 + i),
          studied: i == 0,
          protected: i == 0,
        ),
    ],
  ),
);

QuestProgressCard _card(String id, QuestProgressState state) =>
    QuestProgressCard(
      instanceId: id,
      cadence: QuestType.daily,
      civilLabel: '2026-11-01',
      title: 'Synthetic',
      targetCount: 5,
      xpAmount: 50,
      correctCount: 5,
      completedAtUtc: _now,
      lastEndUtc: _now,
      state: state,
    );

class _Owners implements LocalOwnerRepository {
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: 'a', createdAtUtc: DateTime.utc(2026));
  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String uid) =>
      throw UnimplementedError();
}

class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() => throw UnimplementedError();
}
