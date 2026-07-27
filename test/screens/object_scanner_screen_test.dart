import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/object_scanner_screen.dart';
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
    'ObjectScannerScreen runs an explicit vocabulary simulation on tap',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(home: ObjectScannerScreen(voiceProvider: fakeVoice)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('โหมดจำลอง — เวอร์ชันนี้ยังไม่ใช้กล้องหรือ ML จริง'),
        findsOneWidget,
      );
      final simulateButton = find.byKey(
        const ValueKey<String>('object-scanner-simulate-button'),
      );
      expect(simulateButton, findsOneWidget);
      expect(
        find.descendant(
          of: simulateButton,
          matching: find.text('สุ่มตัวอย่างวัตถุ (โหมดจำลอง)'),
        ),
        findsOneWidget,
      );

      await tester.tap(simulateButton);
      await tester.pump();

      expect(find.text('กำลังสุ่มตัวอย่างคำศัพท์...'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 900));

      expect(find.textContaining('ผลจำลอง:'), findsOneWidget);
    },
  );

  testWidgets(
    'ObjectScannerScreen shows All category chip selected by default',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(home: ObjectScannerScreen(voiceProvider: fakeVoice)),
      );
      await tester.pumpAndSettle();

      // Should have 'All' category chip visible
      expect(find.text('All'), findsOneWidget);
    },
  );

  testWidgets('ObjectScannerScreen displays database stats', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(home: ObjectScannerScreen(voiceProvider: fakeVoice)),
    );
    await tester.pumpAndSettle();

    // Should show database count
    expect(find.textContaining('ฐานข้อมูล:'), findsOneWidget);
    expect(find.textContaining('สุ่มแล้ว: 0'), findsOneWidget);
  });
}
