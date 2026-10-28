import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/cefr_article_reader_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
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
    'CefrArticleReaderScreen renders words and handles word tap speech',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: CefrArticleReaderScreen(
            title: 'Learning Languages',
            content: 'Practice brings great opportunity for everyone',
            cefrLevel: 'B1',
            voice: VoiceUseCases(fakeVoice),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Learning Languages'), findsOneWidget);
      expect(find.text('Practice'), findsOneWidget);

      await tester.tap(find.text('Practice'));
      await tester.pumpAndSettle();

      expect(fakeVoice.requests.length, 1);
      expect(fakeVoice.requests.first.text, 'Practice');
    },
  );
}
