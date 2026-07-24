import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/object_scanner_screen.dart';
import 'package:vocab_learning_app/services/ml_image_labeling_service.dart';
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
      'ObjectScannerScreen renders scan area and scans objects with ML service',
      (WidgetTester tester) async {
    final mockMl = MockMlImageLabelingService(fakeResults: [
      const LabelResult(label: 'Laptop', confidence: 0.95),
    ]);
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          mlService: mockMl,
          voiceProvider: fakeVoice,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify screen title renders in AppBar
    expect(
      find.text('สแกนวัตถุคำศัพท์ (Object Scanner)'),
      findsOneWidget,
    );

    // Verify scan button exists — use the exact button text
    expect(
      find.text('📸 สแกนวัตถุ (ML Kit Image Labeling)'),
      findsOneWidget,
    );

    // Tap scan button using exact text
    await tester.tap(find.text('📸 สแกนวัตถุ (ML Kit Image Labeling)'));
    await tester.pump();

    // Should show scanning indicator
    expect(find.textContaining('กำลังวิเคราะห์'), findsOneWidget);

    // Wait for scan to complete
    await tester.pump(const Duration(milliseconds: 900));

    // Should show a detected word
    expect(find.textContaining('สแกนพบ:'), findsOneWidget);
  });

  testWidgets('ObjectScannerScreen shows All category chip selected by default',
      (WidgetTester tester) async {
    final mockMl = MockMlImageLabelingService();
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          mlService: mockMl,
          voiceProvider: fakeVoice,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Should have 'All' category chip visible
    expect(find.text('All'), findsOneWidget);
  });

  testWidgets('ObjectScannerScreen displays database stats',
      (WidgetTester tester) async {
    final mockMl = MockMlImageLabelingService();
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          mlService: mockMl,
          voiceProvider: fakeVoice,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Should show database count
    expect(find.textContaining('ฐานข้อมูล:'), findsOneWidget);
    expect(find.textContaining('สแกนแล้ว: 0'), findsOneWidget);
  });
}
