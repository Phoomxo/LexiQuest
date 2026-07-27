import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/ai_reading_content_adapter.dart';
import 'package:vocab_learning_app/services/voice_reading_adapter.dart';

void main() {
  group('B4 AI & Voice Reading Adapters Tests', () {
    test(
      'AiReadingContentAdapter falls back seamlessly when forced offline',
      () async {
        final adapter = AiReadingContentAdapter();
        final passage = await adapter.generatePassage(
          cefrLevel: 'B2',
          targetWords: ['ephemeral', 'resilient'],
          forceOffline: true,
        );

        expect(passage.isFallback, isTrue);
        expect(passage.passageText, contains('ephemeral'));
      },
    );

    test(
      'VoiceReadingAdapter uses OmniVoice when available and native TTS when offline',
      () async {
        final adapter = VoiceReadingAdapter();

        final onlineRes = await adapter.speakText(
          text: 'Hello world',
          preferOmniVoice: true,
          isNetworkAvailable: true,
        );
        expect(onlineRes.engine, SpeechSynthesisEngine.omniVoice);
        expect(onlineRes.success, isTrue);

        final offlineRes = await adapter.speakText(
          text: 'Hello world',
          preferOmniVoice: true,
          isNetworkAvailable: false,
        );
        expect(offlineRes.engine, SpeechSynthesisEngine.nativeTts);
        expect(offlineRes.success, isTrue);
        expect(offlineRes.errorReason, contains('native TTS fallback'));
      },
    );
  });
}
