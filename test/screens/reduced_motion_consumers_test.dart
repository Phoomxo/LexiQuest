import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/cloze_session_harness.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  testWidgets('reduced-motion SRS reveals the answer in one frame', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      _app(
        reducedMotion: true,
        child: SrsFlashcardsScreen(
          wordList: const [
            {'word': 'synthetic word', 'translation': 'synthetic answer'},
          ],
          voice: VoiceUseCases(_Voice()),
        ),
      ),
    );
    await _previewReady(tester);
    await tester.tap(find.text('ดูคำแปล'));
    await tester.pump();
    expect(find.text('synthetic answer').hitTestable(), findsOneWidget);
  });

  testWidgets('normal SRS keeps its existing animated reveal', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      _app(
        reducedMotion: false,
        child: SrsFlashcardsScreen(
          wordList: const [
            {'word': 'synthetic word', 'translation': 'synthetic answer'},
          ],
          voice: VoiceUseCases(_Voice()),
        ),
      ),
    );
    await _previewReady(tester);
    await tester.tap(find.text('ดูคำแปล'));
    await tester.pump();
    expect(find.text('synthetic answer'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('synthetic answer').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'reduced-motion scramble shows the drop colour without tweening',
    (tester) async {
      final h = (await tester.runAsync(ClozeSessionHarness.open))!;
      final owners = StreamController<String?>.broadcast(sync: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      try {
        final session = (await tester.runAsync(
          () => h.learning.prepareWordScramble(
            categoryId: configuredCategoryId,
            stillCurrent: () => true,
          ),
        ))!;
        await tester.pumpWidget(
          _app(
            reducedMotion: true,
            child: WordScrambleScreen(
              session: session,
              learning: h.learning,
              ownerChanges: owners.stream,
            ),
          ),
        );
        await tester.pump();
        owners.add(configuredOwnerId);
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          final response = find.byKey(const ValueKey('scramble-response'));
          if (response.evaluate().isNotEmpty &&
              tester.widget<TextField>(response).enabled == true) {
            break;
          }
        }
        final source = find.byType(Draggable<int>).first;
        final target = find.byType(DragTarget<int>).first;
        final gesture = await tester.startGesture(tester.getCenter(source));
        await gesture.moveBy(const Offset(0, -30));
        await gesture.moveTo(tester.getCenter(target));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(of: target, matching: find.byType(DecoratedBox))
              .first,
        );
        expect(
          (box.decoration as BoxDecoration).color,
          Theme.of(tester.element(target)).colorScheme.primaryContainer,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(owners.close);
        await tester.runAsync(h.close);
      }
    },
  );
}

Widget _app({required bool reducedMotion, required Widget child}) =>
    MaterialApp(
      theme: M3Theme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: child,
    );

final class _Voice implements VoiceProvider {
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async =>
      const VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: false,
      );

  @override
  Future<void> stop() async {}
}

Future<void> _previewReady(WidgetTester tester) async {
  final card = find.byKey(const ValueKey('srs-card'));
  final flip = find.byKey(const ValueKey('srs-flip'));
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (card.evaluate().isNotEmpty &&
        flip.evaluate().isNotEmpty &&
        tester.widget<TextButton>(flip).onPressed != null) {
      final route = ModalRoute.of(tester.element(card));
      if (route?.isCurrent == true &&
          (route?.animation?.status == AnimationStatus.completed ||
              route?.animation == null)) {
        await tester.ensureVisible(flip);
        await tester.pump();
        return;
      }
    }
  }
  fail('The actual SRS preview card did not become ready');
}
