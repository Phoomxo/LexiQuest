import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/learning_history_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/review_center_screen.dart';
import 'package:vocab_learning_app/screens/today_hub_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../../integration_test/support/native_baseline_cases.dart'
    show baselineAwait;
import 'composed_host_ui_audit_test.dart' show settleHost, tapHost;

// HOST SYNTHETIC: real bootstrap composition with in-memory DB, isolated support
// directory and no network/authentication. No production flag/source mutation.
class _NoLogin implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() => throw StateError('BR must not log in');
}

class _NoNetwork extends HttpOverrides {
  int calls = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) => _InertClient(this);
}

class _InertClient implements HttpClient {
  _InertClient(this.network);
  final _NoNetwork network;
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) {
    network.calls++;
    throw StateError('BR prohibits HTTP operations: ${invocation.memberName}');
  }
}

class _Entry implements AppEntryStateStore {
  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
  @override
  Future<void> markGuest() async {}
  @override
  Future<void> clear() async {}
}

Future<Map<String, Object?>> _rows(AppDatabase db) async {
  final result = <String, Object?>{};
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  for (final table in tables) {
    final name = table.read<String>('name');
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(name)) throw StateError(name);
    result[name] =
        (await db.customSelect('SELECT * FROM $name ORDER BY 1').get())
            .map((r) => r.data)
            .toList();
  }
  return result;
}

void main() {
  for (final preview in [false, true]) {
    testWidgets('BR actual bootstrap Today routes preview=$preview', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('br-host-synthetic-'),
      ))!;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => root.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final network = _NoNetwork();
      final previousNetwork = HttpOverrides.current;
      HttpOverrides.global = network;
      addTearDown(() => HttpOverrides.global = previousNetwork);
      final dependencies = (await tester.runAsync(
        () => AppBootstrap(
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: () => AppConfig.fromValues(
            voiceApiUrl: 'https://voice.example.com',
            aiApiUrl: 'https://ai.example.com',
            isDebug: false,
          ),
          guestSessionService: _NoLogin(),
          createDatabase: () => AppDatabase(NativeDatabase.memory()),
          createEntryStateStore: () async => _Entry(),
          cloudSyncEnabled: false,
          learningPreviewEnabled: preview,
        ).initialize(),
      ))!;
      try {
        final db = dependencies.database!;
        expect(
          dependencies.hasComposedDependencyFor(Feature.dailyContinuity),
          isTrue,
        );
        expect(
          dependencies.features.isEnabled(Feature.dailyContinuity),
          preview,
        );
        expect(
          dependencies.features.isEnabled(Feature.researchAssessment),
          isFalse,
        );
        final owner = await baselineAwait(
          tester,
          dependencies.activeOwnerIdentities!.requireSingleActiveOwnerId,
        );
        final beforeSeed = await baselineAwait(tester, () => _rows(db));
        // An active legacy quiz is a supported canonical-reader input. It is
        // only synthetic fixture data, never evidence of a completed lesson.
        await baselineAwait(
          tester,
          () => db
              .into(db.learningSessions)
              .insert(
                LearningSessionsCompanion.insert(
                  id: 'synthetic-br-resume',
                  ownerId: owner,
                  activityType: 'quiz',
                  state: 'active',
                  startedAtUtcMs: 1,
                  appVersion: 'synthetic-only',
                  buildId: 'br-host',
                ),
              ),
        );
        final before = await baselineAwait(tester, () => _rows(db));
        expect(
          before.keys
              .where((k) => jsonEncode(before[k]) != jsonEncode(beforeSeed[k]))
              .toSet(),
          {'learning_sessions'},
        );
        final snapshot = await baselineAwait(
          tester,
          dependencies.todayHub!.load,
        );
        expect(snapshot.ownerId, owner);
        expect(snapshot.resumableSession!.id, 'synthetic-br-resume');
        await tester.pumpWidget(
          MyApp(dependencies: dependencies, ownsDependencies: false),
        );
        await settleHost(tester);
        await tapHost(tester, 'home/today');
        if (preview) {
          expect(find.byType(TodayHubScreen), findsOneWidget);
          await tapHost(tester, 'today-hub-open-review');
          expect(find.byType(ReviewCenterScreen), findsOneWidget);
          expect(find.text('ยังไม่มีรายการที่ต้องทบทวน'), findsOneWidget);
          expect(find.text('ไม่สามารถโหลดรายการทบทวนได้'), findsNothing);
          expect(
            ModalRoute.of(
              tester.element(find.byType(ReviewCenterScreen)),
            )!.settings.name,
            'home/today/review',
          );
          await tester.tap(find.byType(BackButton));
          await settleHost(tester);
          await tapHost(tester, 'today-hub-open-history');
          expect(find.byType(LearningHistoryScreen), findsOneWidget);
          expect(find.text('ไม่สามารถโหลดประวัติการเรียนได้'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(
            ModalRoute.of(
              tester.element(find.byType(LearningHistoryScreen)),
            )!.settings.name,
            'home/today/history',
          );
          await tester.tap(find.byType(BackButton));
          await settleHost(tester);
          await tapHost(tester, 'today-hub-resume-action');
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            0,
          );
          // A legacy summary without a frozen checkpoint must remain on Today.
          // The unchanged all-table comparison below proves no replacement quiz.
          expect(find.byType(TodayHubScreen), findsOneWidget);
          (dependencies.features as RuntimeFeatureRegistry).emergencyOff(
            Feature.dailyContinuity,
          );
          await settleHost(tester);
        }
        expect(
          find.byKey(const ValueKey('today-unavailable-practice')),
          findsOneWidget,
        );
        await tapHost(tester, 'today-unavailable-practice');
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          1,
        );
        expect(find.byType(MainNavigationScreen), findsOneWidget);
        final after = await baselineAwait(tester, () => _rows(db));
        expect(
          after,
          before,
          reason: 'Navigation must preserve every synthetic table',
        );
        expect(network.calls, 0);
        await tester.runAsync(() async {
          final file = File(
            'build/verification/today-preview-routes/routes-$preview.json',
          );
          await file.parent.create(recursive: true);
          await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'scope': 'HOST_SYNTHETIC_REAL_BOOTSTRAP',
              'preview': preview,
              'composition': true,
              'seedChangedOnly': ['learning_sessions'],
              'tablesUnchangedByNavigation': after.length,
              'networkCalls': network.calls,
              'reviewHistoryRoutes': preview ? 'PASS' : 'NOT_RUN_FIELD_GATE',
              'legacyResumeRejectedWithoutMutation': preview
                  ? 'PASS'
                  : 'NOT_RUN_FIELD_GATE',
              'quizRehydration': 'NOT_RUN',
              'native': 'NOT_RUN',
              'userTrials': 'DEFERRED',
              'fallback': 'PASS',
            }),
          );
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await settleHost(tester);
        await tester.runAsync(dependencies.dispose);
      }
    });
  }
}
