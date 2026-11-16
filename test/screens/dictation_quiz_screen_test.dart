import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  FakeVoiceProvider({this.fail = false});

  final bool fail;
  final List<VoiceRequest> spokenRequests = [];
  int stopCalls = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
    if (fail) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.playback,
        message: 'Playback unavailable',
      );
    }
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
  testWidgets(
    'DictationQuizScreen automatically plays word at 1.0x speed on start',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: DictationQuizScreen(
            targetWord: 'elephant',
            voice: VoiceUseCases(fakeVoice),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeVoice.spokenRequests.length, 1);
      final req = fakeVoice.spokenRequests.first;
      expect(req.text, 'elephant');
      expect(req.speed, 1.0);
    },
  );

  testWidgets('Tapping Slow-Mo button triggers 0.75x speed request', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: DictationQuizScreen(
          targetWord: 'elephant',
          voice: VoiceUseCases(fakeVoice),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final slowMoFinder = find.byIcon(Icons.slow_motion_video);
    expect(slowMoFinder, findsOneWidget);

    await tester.tap(slowMoFinder);
    await tester.pumpAndSettle();

    expect(fakeVoice.spokenRequests.length, 2);
    expect(fakeVoice.spokenRequests[1].speed, 0.75);
  });

  testWidgets('Typing correct word displays success feedback', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: DictationQuizScreen(
          targetWord: 'elephant',
          voice: VoiceUseCases(fakeVoice),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inputFinder = find.byType(TextField);
    await tester.enterText(inputFinder, 'elephant');
    await tester.tap(find.text('ตรวจคำตอบ'));
    await tester.pumpAndSettle();

    expect(find.text('สะกดถูกแล้ว'), findsOneWidget);
    expect(find.text('elephant'), findsOneWidget);
  });

  testWidgets('selected word plays only on request and returns to its detail', (
    tester,
  ) async {
    final voice = FakeVoiceProvider();
    await _openWord(tester, VoiceUseCases(voice));
    expect(voice.spokenRequests, isEmpty);
    expect(find.text('station'), findsNothing);

    await _tap(tester, 'ฟังด้วยความเร็วปกติ');
    await _tap(tester, 'ฟังช้าลง');
    expect(find.text('ความเร็ว 0.75 เท่า'), findsOneWidget);
    expect(voice.spokenRequests.map((request) => request.text), [
      'station',
      'station',
    ]);
    expect(voice.spokenRequests.map((request) => request.speed), [1, .75]);
    await _tap(tester, 'ลองเขียนคำที่ได้ยิน');
    await tester.enterText(find.byType(TextField), ' Station ');
    await _tap(tester, 'ตรวจคำตอบ');
    expect(find.text('สะกดถูกแล้ว'), findsOneWidget);
    expect(find.text('station'), findsOneWidget);
    expect(find.text('สถานี'), findsOneWidget);
    await _tap(tester, 'กลับไปดูคำเดิม');
    expect(find.text('รายละเอียด station'), findsOneWidget);
    expect(voice.stopCalls, 1);
  });

  testWidgets('failed playback exposes meaning and preserves typo on edit', (
    tester,
  ) async {
    final voice = FakeVoiceProvider(fail: true);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _openWord(tester, VoiceUseCases(voice), textScale: 2);

    await _tap(tester, 'ฟังด้วยความเร็วปกติ');
    expect(find.text('ตอนนี้ฟังเสียงไม่ได้'), findsOneWidget);
    await _tap(tester, 'เปิดคำใบ้แทน');
    expect(find.text('สถานี'), findsOneWidget);
    expect(find.text('Meet me at the ____.'), findsOneWidget);
    await _tap(tester, 'ลองเขียนคำ');
    final input = find.byType(TextField);
    await tester.enterText(input, 'staton');
    await _tap(tester, 'ตรวจคำตอบ');
    expect(find.text('ยังขาดตัว i'), findsOneWidget);
    expect(find.text('staton'), findsOneWidget);
    await _tap(tester, 'แก้คำตอบ');
    expect(tester.widget<TextField>(input).controller!.text, 'staton');
    await tester.enterText(input, 'station');
    await _tap(tester, 'ตรวจคำตอบ');
    expect(find.text('สะกดถูกแล้ว'), findsOneWidget);
    await _tap(tester, 'ลองฟังคำนี้อีกครั้ง');
    expect(find.text('ฟังแล้วเขียน'), findsOneWidget);
    expect(find.text('station'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openWord(
  WidgetTester tester,
  VoiceUseCases voice, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DictationQuizScreen(
                  targetWord: 'station',
                  meaning: 'สถานี',
                  partOfSpeech: 'คำนาม',
                  categoryName: 'การเดินทาง',
                  voice: voice,
                  autoPlay: false,
                ),
              ),
            ),
            child: const Text('รายละเอียด station'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, 'รายละเอียด station');
}

Future<void> _tap(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}
