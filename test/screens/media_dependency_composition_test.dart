import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/screens/media_dependency_unavailable.dart';
import 'package:vocab_learning_app/screens/object_scanner_screen.dart';
import 'package:vocab_learning_app/screens/phonetic_explorer_screen.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/screens/speak_to_text_screen.dart';

void main() {
  testWidgets('Object Scanner fails closed without its composed controller', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ObjectScannerScreen()));
    await tester.pump();

    final state = tester.widget<MediaDependencyUnavailable>(
      find.byType(MediaDependencyUnavailable),
    );
    expect(state.reason, MediaDependencyUnavailableReason.objectScanner);
    expect(
      find.byKey(const ValueKey('object-scanner-capture-button')),
      findsNothing,
    );
  });

  testWidgets('Shadowing fails closed without composed voice', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ShadowingChallengeScreen(referenceSentence: 'Keep going'),
      ),
    );
    await tester.pump();

    final state = tester.widget<MediaDependencyUnavailable>(
      find.byType(MediaDependencyUnavailable),
    );
    expect(state.reason, MediaDependencyUnavailableReason.voice);
    expect(find.byKey(const ValueKey('shadowing-listen-button')), findsNothing);
  });

  testWidgets('Speak-to-Text fails closed without composed voice', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SpeakToTextScreen(correctWord: 'cat')),
    );
    await tester.pump();

    final state = tester.widget<MediaDependencyUnavailable>(
      find.byType(MediaDependencyUnavailable),
    );
    expect(state.reason, MediaDependencyUnavailableReason.voice);
    expect(find.byKey(const ValueKey('speech-listen-button')), findsNothing);
  });

  testWidgets('Dictation fails closed without composed voice', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DictationQuizScreen(targetWord: 'cat')),
    );
    await tester.pump();

    final state = tester.widget<MediaDependencyUnavailable>(
      find.byType(MediaDependencyUnavailable),
    );
    expect(state.reason, MediaDependencyUnavailableReason.voice);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Phonetic Explorer fails closed without composed voice', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PhoneticExplorerScreen()));
    await tester.pump();

    final state = tester.widget<MediaDependencyUnavailable>(
      find.byType(MediaDependencyUnavailable),
    );
    expect(state.reason, MediaDependencyUnavailableReason.voice);
    expect(find.text('/æ/'), findsNothing);
  });
}
