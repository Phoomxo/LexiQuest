import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/services/srs_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> spokenRequests = [];
  int stopCalls = 0;

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
  Future<void> stop() async {
    stopCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SrsFlashcardsScreen renders front side and auto-plays audio', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();
    final wordList = [
      {
        'word': 'apple',
        'translation': 'แอปเปิ้ล',
        'example': 'An apple a day.',
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: SrsFlashcardsScreen(wordList: wordList, voiceProvider: fakeVoice),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsOneWidget);
    expect(fakeVoice.spokenRequests.length, 1);
  });

  testWidgets(
    'Tapping card flips to back side displaying translation and buttons',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();
      final srsService = SrsService();
      final wordList = [
        {
          'word': 'banana',
          'translation': 'กล้วย',
          'example': 'Monkeys eat bananas.',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SrsFlashcardsScreen(
            wordList: wordList,
            voiceProvider: fakeVoice,
            srsService: srsService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap card to flip
      await tester.tap(find.text('banana'));
      await tester.pumpAndSettle();

      expect(find.text('จำได้แล้ว (Good)'), findsOneWidget);
      expect(find.text('จำไม่ได้ (Again)'), findsOneWidget);

      await tester.tap(find.text('จำได้แล้ว (Good)'));
      await tester.pumpAndSettle();

      final map = await srsService.loadItemsMap();
      expect(map.containsKey('banana'), true);
      expect(map['banana']!.boxLevel, 2);
    },
  );
}
