import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('ดูคำแปล'));
    await tester.pump();
    expect(find.text('synthetic answer').hitTestable(), findsOneWidget);
  });

  testWidgets('normal SRS keeps its existing animated reveal', (tester) async {
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('ดูคำแปล'));
    await tester.pump();
    expect(find.text('synthetic answer'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('synthetic answer').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'reduced-motion scramble shows the drop colour without tweening',
    (tester) async {
      await tester.pumpWidget(
        _app(reducedMotion: true, child: const WordScrambleScreen(word: 'cat')),
      );
      await tester.pumpAndSettle();
      final source = find.byType(Draggable<int>).first;
      final target = find.byType(DragTarget<int>).first;
      final gesture = await tester.startGesture(tester.getCenter(source));
      await gesture.moveBy(const Offset(0, -30));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: target, matching: find.byType(DecoratedBox)).first,
      );
      expect(
        (box.decoration as BoxDecoration).color,
        Theme.of(tester.element(target)).colorScheme.primaryContainer,
      );
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
