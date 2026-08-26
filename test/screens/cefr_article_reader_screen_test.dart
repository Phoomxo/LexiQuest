import 'dart:io';

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
  test('f13 CEFR reading declares exposure through its typed adapter', () {
    final source = File(
      'lib/screens/cefr_article_reader_screen.dart',
    ).readAsStringSync();
    expect(source, contains('CefrReadingModeAdapter'));
    expect(source, contains('_modeAdapter.evaluate()'));
  });

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
            voice: VoiceUseCases(
              provider: fakeVoice,
              disposeProvider: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Learning Languages'), findsOneWidget);
      expect(find.text('Practice'), findsOneWidget);
      expect(find.byType(PopScope), findsOneWidget);

      await tester.tap(find.text('Practice'));
      await tester.pumpAndSettle();

      expect(fakeVoice.requests.length, 1);
      expect(fakeVoice.requests.first.text, 'Practice');
    },
  );
}
