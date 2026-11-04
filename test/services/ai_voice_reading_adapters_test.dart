import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/services/offline_reading_material.dart';
import 'package:vocab_learning_app/services/voice_reading_adapter.dart';

void main() {
  group('B4 AI & Voice Reading Adapters Tests', () {
    test('missing examples show the selected words and meanings honestly', () {
      const words = [
        QuizWord(
          id: '1',
          categoryId: 'c',
          spelling: 'station',
          meaning: 'สถานี',
          partOfSpeech: 'noun',
          contentRevision: 'r1',
        ),
        QuizWord(
          id: '2',
          categoryId: 'c',
          spelling: 'ticket',
          meaning: 'ตั๋ว',
          partOfSpeech: 'noun',
          contentRevision: 'r2',
        ),
      ];
      final items = [for (final word in words) (word: word, lexical: null)];
      final material = ReadingMaterial(items);

      expect(material.items.map((item) => item.word), words);
      expect(material.passageText, 'station\n\nticket');
      expect(material.supportedText, contains('station: สถานี'));
      expect(material.supportedText, contains('ticket: ตั๋ว'));
      expect(material.supportedText, contains('ไม่มีประโยคตัวอย่าง'));
      expect(ReadingMaterial(items).contentId, material.contentId);
      expect(
        ReadingMaterial(items.reversed.toList()).contentId,
        isNot(material.contentId),
      );
    });

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
