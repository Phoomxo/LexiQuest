// Ignored local C1/D2 visual QA fixture; not a golden baseline.
// Run only after all application writers freeze the source snapshot.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_result.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_result_screen.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_practice_replay.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_history_projection.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_session_coordinator.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_result_view.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/study_planning_hub_screen.dart';

import '../../test/features/learning/pair_matching/pair_matching_evidence_contract_test.dart'
    show PairHarness;

const _boundary = ValueKey<String>('motivation-result-visual-boundary');
const _output = 'build/verification/motivation-ui-20260908/visual/c1/results';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final thaiFont = FontLoader(M3Theme.thaiFontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait<void>([thaiFont.load(), icons.load()]);
  });

  for (final spec in <_Spec>[
    const _Spec('390x844', Size(390, 844), 1),
    const _Spec(
      '360x800-text200-dark-reduced',
      Size(360, 800),
      2,
      dark: true,
      reducedMotion: true,
    ),
    const _Spec(
      '240x640-text200-highcontrast',
      Size(240, 640),
      2,
      highContrast: true,
    ),
  ]) {
    testWidgets('C1 result visual ${spec.name}', (tester) async {
      tester.view.physicalSize = spec.size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 16);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);

      final pairs = await tester.runAsync(_PairResults.create);
      expect(pairs, isNotNull);
      final captures = <String>[];
      try {
        await _pump(
          tester,
          spec,
          const ScoreScreen(correctAnswers: 8, wrongAnswers: 2),
        );
        expect(find.text('80%'), findsOneWidget);
        await _capture(tester, spec, '01-score-8-correct-2-wrong', captures);

        await _pump(
          tester,
          spec,
          const ScoreScreen(correctAnswers: 0, wrongAnswers: 0),
        );
        expect(find.text('0%'), findsOneWidget);
        await _capture(tester, spec, '02-score-zero-of-zero', captures);

        await _pump(
          tester,
          spec,
          AchievementsScreen(loader: () async => _progress),
        );
        expect(find.text('42'), findsWidgets);
        await _capture(tester, spec, '03-achievements-42-xp', captures);

        for (final entry in <(String, AdventureCanonicalRewardState)>[
          ('04-adventure-pending', AdventureCanonicalRewardState.pending),
          ('05-adventure-accepted', AdventureCanonicalRewardState.accepted),
          (
            '06-adventure-unavailable',
            AdventureCanonicalRewardState.unavailable,
          ),
        ]) {
          await _pump(
            tester,
            spec,
            AdventureResultScreen(
              result: _adventure(entry.$2),
              onNextAction: () {},
            ),
          );
          expect(find.text('ตอบถูก 3 รายการ'), findsOneWidget);
          await _capture(tester, spec, entry.$1, captures);
        }

        await _pump(
          tester,
          spec,
          Scaffold(
            body: PairMatchingResultView(
              result: pairs!.normal,
              onReturn: () {},
              onPracticeReplay: () {},
            ),
          ),
        );
        expect(find.text('จับคู่แล้ว 4 คู่'), findsOneWidget);
        await _capture(tester, spec, '07-pair-normal', captures);

        await _pump(
          tester,
          spec,
          Scaffold(
            body: PairMatchingResultView(
              result: pairs.replay,
              onReturn: () {},
              onPracticeReplay: () {},
            ),
          ),
        );
        expect(pairs.replay.sourceSessionId, pairs.normal.sessionId);
        await _capture(tester, spec, '08-pair-practice-replay', captures);

        await _pump(tester, spec, const StudyPlanningHubScreen());
        expect(
          find.byKey(const ValueKey('study-planning/open-goals')),
          findsOneWidget,
        );
        await _capture(tester, spec, '09-study-planning-hub', captures);

        expect(captures, hasLength(9));
        await tester.runAsync(() async {
          final source = File(
            '.superpowers/sdd/motivation-result-visual-test.dart',
          );
          final out = File('$_output/${spec.name}-capture.json');
          await out.parent.create(recursive: true);
          await out.writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'fixture': source.path,
              'fixtureSha256': crypto.sha256
                  .convert(await source.readAsBytes())
                  .toString(),
              'viewport': [spec.size.width, spec.size.height],
              'textScale': spec.textScale,
              'brightness': spec.dark ? 'dark' : 'light',
              'highContrast': spec.highContrast,
              'reducedMotion': spec.reducedMotion,
              'captures': captures,
              'data': 'Synthetic local result projections only',
              'limitations': [
                'Widget renderer; not native device, TalkBack, UAT, or efficacy evidence',
                'Every PNG requires human inspection; capture is not approval',
              ],
            }),
          );
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (pairs != null) await tester.runAsync(pairs.close);
      }
    });
  }
}

Future<void> _pump(WidgetTester tester, _Spec spec, Widget home) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: M3Theme.lightTheme,
        darkTheme: M3Theme.darkTheme,
        themeMode: spec.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(spec.textScale),
            highContrast: spec.highContrast,
            disableAnimations: spec.reducedMotion,
          ),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  final error = tester.takeException();
  expect(error, isNull, reason: 'Result surface overflowed or threw.');
}

Future<void> _capture(
  WidgetTester tester,
  _Spec spec,
  String name,
  List<String> captures,
) async {
  final render = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  final filename = '${spec.name}-$name.png';
  await tester.runAsync(() async {
    ui.Image? image;
    try {
      image = await render
          .toImage(pixelRatio: 1)
          .timeout(const Duration(seconds: 8));
      final data = await image
          .toByteData(format: ui.ImageByteFormat.png)
          .timeout(const Duration(seconds: 8));
      if (data == null) throw StateError('No PNG bytes for $filename');
      final file = File('$_output/$filename');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image?.dispose();
    }
  });
  captures.add(filename);
}

final class _Spec {
  const _Spec(
    this.name,
    this.size,
    this.textScale, {
    this.dark = false,
    this.highContrast = false,
    this.reducedMotion = false,
  });
  final String name;
  final Size size;
  final double textScale;
  final bool dark;
  final bool highContrast;
  final bool reducedMotion;
}

const _progress = ProgressSnapshot(
  sampleSize: 10,
  correctCount: 8,
  wrongCount: 2,
  accuracy: .8,
  totalXp: 42,
  completedSessions: 2,
  streakDays: 3,
  dueReviewCount: 1,
  masteredWordCount: 2,
  achievementCount: 0,
  gameLevel: 3,
  skills: [],
  weaknesses: [],
  recommendations: [],
);

AdventureResult _adventure(AdventureCanonicalRewardState state) =>
    AdventureResult(
      ownerId: 'synthetic-result-owner',
      sessionId: 'synthetic-adventure-session',
      learning: const AdventureLearningResult(
        correctCount: 3,
        incorrectCount: 1,
        reviewDueCount: 1,
      ),
      effort: const AdventureEffortResult(
        activeDuration: Duration(minutes: 5),
        completedItems: 4,
      ),
      engagement: const AdventureEngagementResult(
        completedMission: true,
        returnedAfterBreak: false,
      ),
      motivation: AdventureMotivationReceiptView(
        questState: AdventureCanonicalReceiptState.committed,
        streakState: AdventureCanonicalReceiptState.committed,
        achievementState: AdventureCanonicalReceiptState.notEligible,
        questCodes: const ['synthetic-daily-quest'],
        streakCodes: const ['synthetic-daily-streak'],
      ),
      reward: AdventureRewardReceiptView(
        state: state,
        receiptId: state == AdventureCanonicalRewardState.accepted
            ? 'synthetic-receipt'
            : null,
      ),
      nextAction: AdventureNextAction.reviewCenter,
    );

final class _PairResults {
  _PairResults(this.harness, this.normal, this.replay);

  static Future<_PairResults> create() async {
    final h = PairHarness();
    await h.initialize();
    final normalCoordinator = await h.restore();
    await _finish(
      normalCoordinator,
      ownerId: h.owner,
      sessionId: h.operation.plan.learningSessionId,
      wordIds: h.operation.plan.orderedLexicalItems.map((item) => item.wordId),
    );
    final normal = PairMatchingHistoryProjection(
      (await DriftPairMatchingSessionPurposeReader(h.db).read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      )).snapshot!,
    );
    final replayAtomic = PairMatchingAtomicStartAdapter(
      repository: h.real,
      capability: InternalPairMatchingCapability(
        allowlist: PairCuratedAllowlist(
          version: h.operation.plan.allowlistVersion,
          items: h.operation.plan.orderedLexicalItems,
        ),
        isEnabled: () => true,
      ),
    );
    final replayStart = PairPracticeReplay(
      reader: DriftPairMatchingSessionPurposeReader(h.db),
      start: replayAtomic,
    );
    final replayOperation = await replayStart.prepare(
      ownerId: h.owner,
      sourceSessionId: normal.sessionId,
      launchOperationId: 'synthetic-result-replay',
      createdAtUtc: h.learning.nowUtc(),
      appVersion: 'synthetic',
      buildId: 'synthetic',
    );
    await replayAtomic.start(replayOperation);
    final replayCoordinator = await PairMatchingSessionCoordinator.restore(
      operation: replayOperation,
      learning: h.learning,
      evidence: CurrentActivityEvidenceAdapter(learning: h.learning),
      activeOwnerId: () => h.owner,
    );
    await _finish(
      replayCoordinator,
      ownerId: h.owner,
      sessionId: replayOperation.plan.learningSessionId,
      wordIds: replayOperation.plan.orderedLexicalItems.map(
        (item) => item.wordId,
      ),
    );
    final replay = PairMatchingHistoryProjection(
      (await DriftPairMatchingSessionPurposeReader(h.db).read(
        ownerId: h.owner,
        sessionId: replayOperation.plan.learningSessionId,
      )).snapshot!,
    );
    return _PairResults(h, normal, replay);
  }

  static Future<void> _finish(
    PairMatchingSessionCoordinator coordinator, {
    required String ownerId,
    required String sessionId,
    required Iterable<String> wordIds,
  }) async {
    for (final wordId in wordIds) {
      await coordinator.dispatch(
        PairSelectTile(
          operationId: '${coordinator.state.operationRevision}:prompt',
          ownerId: ownerId,
          sessionId: sessionId,
          roundOrdinal: coordinator.state.roundOrdinal,
          expectedRevision: coordinator.state.operationRevision,
          tile: PairTile(PairTileSide.prompt, wordId),
          responseTimeMs: 25,
        ),
      );
      await coordinator.dispatch(
        PairSelectTile(
          operationId: '${coordinator.state.operationRevision}:target',
          ownerId: ownerId,
          sessionId: sessionId,
          roundOrdinal: coordinator.state.roundOrdinal,
          expectedRevision: coordinator.state.operationRevision,
          tile: PairTile(PairTileSide.target, wordId),
          responseTimeMs: 25,
        ),
      );
    }
    await coordinator.finish();
  }

  final PairHarness harness;
  final PairMatchingHistoryProjection normal;
  final PairMatchingHistoryProjection replay;
  Future<void> close() => harness.db.close();
}
