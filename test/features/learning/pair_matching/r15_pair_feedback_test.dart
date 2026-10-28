import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/learning_feedback_theme.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_board_view.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_feedback_episode.dart';
import 'pair_board_view_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(M3Theme.thaiFontFamily)
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test('success and support text meet contrast in both themes', () {
    for (final palette in [
      LearningFeedbackTheme.light,
      LearningFeedbackTheme.dark,
    ]) {
      for (final pair in [
        (palette.success, palette.onSuccess),
        (palette.support, palette.onSupport),
      ]) {
        final a = pair.$1.computeLuminance(), b = pair.$2.computeLuminance();
        expect(
          ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });
  test('only a new acknowledged matching operation creates an episode', () {
    final before = PairMatchingState.initial(pairBoardTestPlan());
    final after = pairBoardMatch(before, 'word:0');
    expect(PairFeedbackEpisode.accepted(before, after).single.assisted, false);
    expect(PairFeedbackEpisode.accepted(after, after), isEmpty);
    final selected = pairBoardSelect(before, PairTileSide.prompt, 'word:0');
    final pending = pairBoardSelect(selected, PairTileSide.target, 'word:0');
    expect(PairFeedbackEpisode.accepted(before, pending), isEmpty);
    expect(
      PairFeedbackEpisode.accepted(before, pairBoardWrong(before, 'word:0')),
      isEmpty,
    );
  });
  for (final density in [PairDensity.compact4, PairDensity.standard6]) {
    for (final width in <double>[320, 390, 840]) {
      final narrow = width == 320;
      for (final kind in ['selected', 'correct', 'wrong', 'support', 'final']) {
        testWidgets('B04 Pair ${density.name} $kind width=$width', (
          tester,
        ) async {
          final size = Size(width, 900);
          final plan = pairBoardTestPlan(density: density);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var before = PairMatchingState.initial(plan);
          if (kind == 'final') {
            for (final id in [
              for (var i = 1; i < density.pairCount; i++) 'word:$i',
            ]) {
              before = pairBoardMatch(before, id);
            }
          }
          if (kind == 'support') {
            before = pairBoardGuidedState(plan);
          }
          final PairMatchingState after;
          if (kind == 'selected') {
            after = pairBoardSelect(before, PairTileSide.prompt, 'word:0');
          } else if (kind == 'wrong') {
            after = pairBoardWrong(before, 'word:0');
          } else if (kind == 'support') {
            final pending = PairMatchingEngine.reduce(
              before,
              PairConfirmGuidedMapping(
                operationId: '${before.operationRevision}:r15-guided',
                ownerId: before.plan.ownerId,
                sessionId: before.plan.learningSessionId,
                roundOrdinal: before.roundOrdinal,
                expectedRevision: before.operationRevision,
                wordId: 'word:0',
                shownSupportRevision: before.supportAtRevision['word:0']!,
                responseTimeMs: 25,
              ),
            ).state;
            after = pairBoardAcknowledge(pending);
          } else {
            after = pairBoardMatch(before, 'word:0');
          }
          final episodes = PairFeedbackEpisode.accepted(before, after);
          final base = pairBoardTestModel(state: after);
          await tester.pumpWidget(
            pairBoardTestApp(
              model: PairBoardModel(
                state: after,
                timer: base.timer,
                feedbackEpisodes: {for (final e in episodes) e.wordId: e},
              ),
              size: size,
              textScale: narrow ? 2 : 1,
              themeMode: narrow ? ThemeMode.dark : ThemeMode.light,
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          if (kind == 'correct' || kind == 'support' || kind == 'final') {
            expect(
              find.text(kind == 'support' ? 'สำเร็จด้วยตัวช่วย' : 'ถูกต้อง'),
              findsWidgets,
            );
            expect(
              find.byKey(const ValueKey('pair-tile:prompt:word:0')),
              findsNothing,
            );
          }
          if (kind == 'support') expect(find.text('ถูกต้อง'), findsNothing);
          if (kind == 'selected' || kind == 'wrong') {
            expect(episodes, isEmpty);
            expect(find.text('ถูกต้อง'), findsNothing);
          }
          if (kind == 'final') expect(after.complete, isTrue);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(pairBoardSurfaceKey),
          );
          await tester.runAsync(() async {
            final capture = await boundary.toImage();
            final bytes = await capture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/verification/r15-pair-visual/B04-${density.name}-$kind-w$width-${narrow ? 's2-dark' : 's1-light'}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            capture.dispose();
          });
        });
      }
    }
  }
}
