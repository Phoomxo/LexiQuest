import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/phonetic_explorer_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  FakeVoiceProvider({this.error, this.pending});

  final List<VoiceRequest> requests = [];
  final VoiceFailure? error;
  final Completer<VoicePlaybackResult>? pending;
  int stops = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    if (error case final failure?) throw failure;
    if (pending case final result?) return result.future;
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

const _shePlayback = 'ลองเสียง /ʃ/ ในคำว่า she';

void main() {
  testWidgets(
    'PhoneticExplorerScreen renders IPA symbols and handles audio tap',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: PhoneticExplorerScreen(voice: VoiceUseCases(fakeVoice)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('เลือกเสียงที่อยากฝึก'), findsOneWidget);
      const examples = [
        ('/æ/', 'cat', 'แมว'),
        ('/θ/', 'think', 'คิด'),
        ('/ʃ/', 'she', 'เธอ'),
        ('/ʒ/', 'vision', 'การมองเห็น'),
        ('/ŋ/', 'sing', 'ร้องเพลง'),
        ('/iː/', 'see', 'เห็น'),
      ];
      for (final (ipa, word, meaning) in examples) {
        await tester.ensureVisible(find.text('$ipa $word'));
        await tester.tap(find.text('$ipa $word'));
        await tester.pumpAndSettle();
        expect(find.text(meaning), findsOneWidget);
        final play = find.text('ลองเสียง $ipa ในคำว่า $word');
        await tester.ensureVisible(play);
        await tester.tap(play);
        await tester.pumpAndSettle();
      }
      expect(
        fakeVoice.requests.map((request) => request.text),
        examples.map((example) => example.$2),
      );
      expect(
        fakeVoice.requests.every(
          (request) =>
              request.language == 'en' &&
              request.speed == 0.8 &&
              request.mode == VoiceMode.practice &&
              request.contentType == 'phonetic_explorer',
        ),
        isTrue,
      );
    },
  );

  testWidgets('station mouth cues stay readable at 200% after TTS fails', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fakeVoice = FakeVoiceProvider(
      error: const VoiceFailure(
        category: VoiceFailureCategory.synthesis,
        message: 'test failure',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: PhoneticExplorerScreen(
          targetWord: 'station',
          voice: VoiceUseCases(fakeVoice),
        ),
      ),
    );

    expect(find.text('ห่อริมฝีปากเล็กน้อยแล้วปล่อยลม'), findsOneWidget);
    expect(find.text('เสียง /ʃ/ อยู่หลังสระ /eɪ/'), findsOneWidget);
    expect(fakeVoice.requests, isEmpty);
    final play = find.text(_shePlayback);
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('เปิดเสียงตัวอย่างไม่ได้'));
    expect(fakeVoice.requests.single.text, 'she');
    expect(find.text('ห่อริมฝีปากเล็กน้อยแล้วปล่อยลม'), findsOneWidget);
    expect(find.text('test failure'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending playback stops on Back and cannot update the old page', (
    tester,
  ) async {
    final pending = Completer<VoicePlaybackResult>();
    final fakeVoice = FakeVoiceProvider(pending: pending);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => PhoneticExplorerScreen(
                  targetWord: 'station',
                  voice: VoiceUseCases(fakeVoice),
                  returnLabel: 'กลับไปดูคำว่า station',
                ),
              ),
            ),
            child: const Text('เปิดจากหน้าคำศัพท์'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดจากหน้าคำศัพท์'));
    await tester.pumpAndSettle();
    final play = find.text(_shePlayback);
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.tap(play);
    await tester.pump();
    expect(fakeVoice.requests, hasLength(1));
    final back = find.text('กลับไปดูคำว่า station');
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(fakeVoice.stops, 1);
    expect(find.text('เปิดจากหน้าคำศัพท์'), findsOneWidget);
    pending.completeError(
      const VoiceFailure(
        category: VoiceFailureCategory.cancelled,
        message: 'cancelled test',
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a different saved word does not inherit station IPA', (
    tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneticExplorerScreen(
          targetWord: 'wallet',
          voice: VoiceUseCases(fakeVoice),
        ),
      ),
    );
    expect(find.text('wallet'), findsOneWidget);
    expect(find.text('เสียง /ʃ/ อยู่หลังสระ /eɪ/'), findsNothing);
    expect(find.textContaining('/ˈsteɪʃən/'), findsNothing);
    expect(fakeVoice.requests, isEmpty);
  });
}
