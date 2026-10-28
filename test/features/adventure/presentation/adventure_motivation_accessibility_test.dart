import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_result.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_result_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(M3Theme.thaiFontFamily)
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final large in [false, true]) {
    testWidgets('R15.8 no audio reduced motion readable large=$large', (
      tester,
    ) async {
      tester.view.physicalSize = Size(large ? 320 : 390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: large ? M3Theme.darkTheme : M3Theme.lightTheme,
          home: RepaintBoundary(
            key: boundary,
            child: MediaQuery(
              data: MediaQueryData(
                disableAnimations: true,
                highContrast: large,
                textScaler: TextScaler.linear(large ? 2 : 1),
              ),
              child: AdventureResultScreen(
                result: _result,
                onNextAction: () => actions++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byType(AdventureResultScreen)),
        ).scale(10),
        large ? 20 : 10,
      );
      for (final section in [
        'reward',
        'effort',
        'engagement',
        'motivation',
        'next-action',
      ]) {
        final target = find.byKey(ValueKey('adventure-result-$section'));
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump();
        await tester.scrollUntilVisible(target, 120);
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsNothing);
        if (Platform.environment['LEXIQUEST_R15_VISUAL_QA'] == '1') {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/verification/r15-motivation/large-$large-$section.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await tester.tap(
        find.byKey(const ValueKey('adventure-result-next-action')),
      );
      expect(actions, 1);
      // The next action is immediate; allow the standard button ink response
      // to settle before checking that no reward animation keeps ticking.
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}

final _result = AdventureResult(
  ownerId: 'synthetic-owner',
  sessionId: 'synthetic-session',
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
    questCodes: ['synthetic-daily-quest'],
  ),
  reward: const AdventureRewardReceiptView(
    state: AdventureCanonicalRewardState.accepted,
    receiptId: 'synthetic-reward',
    canonicalAmount: 12,
  ),
  nextAction: AdventureNextAction.reviewCenter,
);
