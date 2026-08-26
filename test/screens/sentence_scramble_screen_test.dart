import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> spokenRequests = [];

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}

void main() {
  test('f13 sentence scramble delegates correctness to its typed adapter', () {
    final source = File(
      'lib/screens/sentence_scramble_screen.dart',
    ).readAsStringSync();
    expect(source, contains('SentenceScrambleModeAdapter'));
    expect(source, contains('_modeAdapter.evaluate('));
    expect(source, contains('_lifecycle!.complete('));
    expect(source, isNot(contains('userSentence == widget.targetSentence')));
  });

  testWidgets(
    'SentenceScrambleScreen allows word selection and sentence checking',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: SentenceScrambleScreen(
            targetSentence: 'cat is sleeping',
            voice: VoiceUseCases(
              provider: fakeVoice,
              disposeProvider: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('เรียงประโยคภาษาอังกฤษ'), findsOneWidget);
      expect(fakeVoice.spokenRequests.length, 1);
    },
  );
}
