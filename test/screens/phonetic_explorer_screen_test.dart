import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/phonetic_explorer_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> requests = [];

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
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
  testWidgets(
    'PhoneticExplorerScreen renders IPA symbols and handles audio tap',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(home: PhoneticExplorerScreen(voiceProvider: fakeVoice)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('สำรวจสัทอักษร IPA (Phonetic Explorer)'),
        findsOneWidget,
      );
      expect(find.text('/æ/'), findsOneWidget);

      await tester.tap(find.text('/æ/'));
      await tester.pumpAndSettle();

      expect(fakeVoice.requests.length, 1);
      expect(fakeVoice.requests.first.text, 'cat');
    },
  );
}
