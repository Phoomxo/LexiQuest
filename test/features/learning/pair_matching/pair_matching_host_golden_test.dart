import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
import 'pair_matching_evidence_contract_test.dart' show PairHarness;
import 'pair_timeout_recovery_test.dart' show timedPlan, clocked;

final class _Protocols implements SessionConfigurationProtocolProvider {
  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(
    String ownerId,
  ) async => const SessionConfigurationProtocolLimits.standard();
}

PairMatchingExperienceRuntime _runtime(PairHarness h, int Function() clock) {
  final learning = LearningUseCases(
    owners: h.learning.owners,
    repository: h.real,
    generateId: h.learning.generateId,
    nowUtc: h.learning.nowUtc,
    buildInfo: h.learning.buildInfo,
  );
  final allowlist = PairCuratedAllowlist(
    version: h.operation.plan.allowlistVersion,
    items: h.operation.plan.orderedLexicalItems,
  );
  return PairMatchingExperienceRuntime(
    database: h.db,
    learning: learning,
    currentActivityEvidence: CurrentActivityEvidenceAdapter(learning: learning),
    registry: buildLessonModeRegistry(
      internalPairMatching: true,
      matchingDeliveryState: LessonModeDeliveryState.enabled,
    ),
    createController: (adapter) => UnifiedLessonController(
      learning: learning,
      adapter: adapter,
      sessionPurposeReader: h.real,
    ),
    composer: PairMatchingSourceComposer(allowlist: allowlist),
    protocols: _Protocols(),
    start: PairMatchingAtomicStartAdapter(
      repository: h.real,
      capability: InternalPairMatchingCapability(
        allowlist: allowlist,
        isEnabled: () => true,
      ),
    ),
    canStart: () => true,
    monotonicMicros: clock,
  );
}

Widget _app(Widget host, {Locale locale = const Locale('th')}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: M3Theme.lightTheme,
  locale: locale,
  supportedLocales: const [Locale('th'), Locale('en')],
  localizationsDelegates: const [
    _MaterialCopy(),
    _WidgetsCopy(),
    _CupertinoCopy(),
  ],
  home: host,
);

// Test-only framework resources; Pair's own visible Thai copy remains real.
final class _MaterialCopy extends LocalizationsDelegate<MaterialLocalizations> {
  const _MaterialCopy();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      DefaultMaterialLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(_MaterialCopy old) => false;
}

final class _WidgetsCopy extends LocalizationsDelegate<WidgetsLocalizations> {
  const _WidgetsCopy();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      DefaultWidgetsLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(_WidgetsCopy old) => false;
}

final class _CupertinoCopy
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _CupertinoCopy();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      DefaultCupertinoLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(_CupertinoCopy old) => false;
}

void _surface(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _golden(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/pair_board/$name'),
  );
}

void main() {
  setUpAll(() async {
    await (FontLoader(M3Theme.thaiFontFamily)
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('golden actual setup shows source count and configured maximum', (
    tester,
  ) async {
    _surface(tester);
    final h = PairHarness();
    addTearDown(h.db.close);
    await h.initialize();
    final launch = PairMatchingLaunchIntent(
      ownerId: h.owner,
      sourceSurface: PairSourceSurface.learn,
      sourceSnapshotRef: 'synthetic-golden-source',
      operationId: 'synthetic-golden-launch',
      createdAtUtc: h.learning.nowUtc(),
    );
    await tester.pumpWidget(
      _app(
        PairMatchingExperienceHost(
          runtime: _runtime(h, () => 0),
          launch: launch,
          source: PairSourceSnapshot.learn(
            ownerId: h.owner,
            reference: launch.sourceSnapshotRef,
            items: h.operation.plan.orderedLexicalItems,
          ),
          preferences: PairDensityPreferences(
            ownerId: h.owner,
            guardianOverride: PairDensity.compact4,
          ),
          onExit: () {},
        ),
      ),
    );
    await _golden(tester, 'host_setup_thai_guardian.png');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('golden actual timeout and Continue affordance', (tester) async {
    _surface(tester);
    var micros = 0;
    final h = PairHarness(pinnedPlan: timedPlan());
    addTearDown(h.db.close);
    await h.initialize(measured: true);
    final c = await clocked(h, () => micros);
    c.resumeInteraction();
    micros = 60000000;
    await c.expire();
    c.dispose();
    await tester.pumpWidget(
      _app(
        PairMatchingExperienceHost.recover(
          runtime: _runtime(h, () => micros),
          operation: h.operation,
          onExit: () {},
        ),
      ),
    );
    await _golden(tester, 'host_timeout_thai.png');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'golden actual authenticated result and fresh practice replay result',
    (tester) async {
      _surface(tester);
      var micros = 0;
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final host = PairMatchingExperienceHost.recover(
        runtime: _runtime(h, () => micros),
        operation: h.operation,
        onExit: () {},
      );
      await tester.pumpWidget(_app(host));
      await tester.pumpAndSettle();
      Future<void> answerSet() async {
        for (var i = 0; i < 4; i++) {
          for (final side in ['prompt', 'target']) {
            final tile = find.byKey(ValueKey('pair-tile:$side:synthetic-$i'));
            await tester.ensureVisible(tile);
            await tester.tap(tile);
            await tester.pumpAndSettle();
          }
        }
      }

      micros = 2000000;
      await answerSet();
      await _golden(tester, 'host_result_thai_measured.png');
      await tester.ensureVisible(find.text('ฝึกซ้ำชุดเดิม'));
      await tester.tap(find.text('ฝึกซ้ำชุดเดิม'));
      await tester.pumpAndSettle();
      micros = 5000000;
      await answerSet();
      const thaiCompletion = 'จบการฝึกรอบนี้แล้ว';
      const englishCompletion =
          'Session complete. You showed up for your learning.';
      expect(find.text(thaiCompletion), findsOneWidget);
      // Reusing the same host must update companion copy in both directions.
      for (final languageCode in ['en', 'th', 'en']) {
        await tester.pumpWidget(_app(host, locale: Locale(languageCode)));
        await tester.pumpAndSettle();
        expect(
          find.text(languageCode == 'en' ? englishCompletion : thaiCompletion),
          findsOneWidget,
        );
        expect(
          find.text(languageCode == 'en' ? thaiCompletion : englishCompletion),
          findsNothing,
        );
      }
      await _golden(tester, 'host_replay_result_english.png');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
