import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/widgets/live_audio_waveform_widget.dart';

void main() {
  testWidgets('LiveAudioWaveformWidget renders CustomPaint waveform cleanly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LiveAudioWaveformWidget(audioLevels: [0.2, 0.5, 0.8, 0.3, 0.9]),
        ),
      ),
    );

    expect(find.byType(LiveAudioWaveformWidget), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
