import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/screens/smart_audio_playlist_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  final requests = <VoiceRequest>[];
  final playback = <Completer<VoicePlaybackResult>>[];
  int stops = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) {
    requests.add(request);
    final completion = Completer<VoicePlaybackResult>();
    playback.add(completion);
    return completion.future;
  }

  void finish(int index) => playback[index].complete(
    const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    ),
  );

  @override
  Future<void> stop() async {
    stops++;
  }
}

const words = [
  {'word': 'station', 'translation': 'สถานี'},
  {'word': 'ticket', 'translation': 'ตั๋ว'},
];

Future<void> openPlaylist(
  WidgetTester tester,
  FakeVoiceProvider voice, {
  List<Map<String, String>> wordList = words,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => SmartAudioPlaylistScreen(
                  wordList: wordList,
                  categoryName: 'การเดินทาง',
                  returnLabel: 'กลับไปดูชุดการเดินทาง',
                  voice: VoiceUseCases(voice),
                ),
              ),
            ),
            child: const Text('ฟังคำในชุดนี้'),
          ),
        ),
      ),
    ),
  );
  await tapLabel(tester, 'ฟังคำในชุดนี้');
}

Future<void> tapLabel(WidgetTester tester, String text) async {
  final label = find.text(text);
  await tester.ensureVisible(label);
  await tester.tap(label);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('leaving the app stops playback until the learner restarts', (
    tester,
  ) async {
    final voice = FakeVoiceProvider();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await openPlaylist(tester, voice);
    await tapLabel(tester, 'ฟังคำแรก');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    expect(voice.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('หยุดที่คำ 1 จาก 2'), findsOneWidget);
    voice.finish(0);
    await tester.pumpAndSettle();
    expect(voice.requests, hasLength(1));
    expect(find.text('ฟังตั้งแต่คำแรก'), findsOneWidget);
  });

  testWidgets('playlist resumes from first and finishes after actual sound', (
    tester,
  ) async {
    final voice = FakeVoiceProvider();
    await openPlaylist(tester, voice);
    expect(find.text('station'), findsOneWidget);
    expect(voice.requests, isEmpty);
    await tapLabel(tester, 'ฟังคำแรก');
    expect(voice.requests.single.text, 'station');
    await tapLabel(tester, 'ฟังคำถัดไป');
    expect(voice.requests.last.text, 'ticket');
    await tapLabel(tester, 'หยุดฟัง');
    expect(find.text('หยุดที่คำ 2 จาก 2'), findsOneWidget);
    expect(find.text('ticket'), findsOneWidget);
    expect(find.text('จบการฟังชุดนี้'), findsNothing);
    await tapLabel(tester, 'ฟังตั้งแต่คำแรก');
    expect(voice.requests.last.text, 'station');
    voice.finish(0);
    voice.finish(1);
    voice.finish(2);
    await tester.pumpAndSettle();
    expect(voice.requests.last.text, 'ticket');
    expect(find.text('จบการฟังชุดนี้'), findsNothing);
    voice.finish(3);
    await tester.pumpAndSettle();
    await tapLabel(tester, 'จบการฟังชุดนี้');
    expect(find.text('ฟังจบชุดแล้ว'), findsOneWidget);
    expect(find.text('station'), findsOneWidget);
    expect(find.text('ticket'), findsOneWidget);
    await tapLabel(tester, 'กลับไปดูชุดการเดินทาง');
    expect(find.text('ฟังคำในชุดนี้'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skipping an unfinished word omits it from the sound summary', (
    tester,
  ) async {
    final voice = FakeVoiceProvider();
    await openPlaylist(tester, voice);
    await tapLabel(tester, 'ฟังคำแรก');
    await tapLabel(tester, 'ฟังคำถัดไป');
    voice.finish(1);
    await tester.pumpAndSettle();
    await tapLabel(tester, 'จบการฟังชุดนี้');
    expect(find.text('จบรอบการฟังแล้ว'), findsOneWidget);
    expect(find.text('station'), findsNothing);
    expect(find.text('ticket'), findsOneWidget);
  });

  testWidgets('empty playlist has no playback or completion action', (
    tester,
  ) async {
    final voice = FakeVoiceProvider();
    await openPlaylist(tester, voice, wordList: []);
    expect(find.text('ชุดนี้ยังไม่มีคำให้ฟัง'), findsOneWidget);
    expect(find.text('ฟังคำแรก'), findsNothing);
    expect(find.text('จบการฟังชุดนี้'), findsNothing);
    expect(voice.requests, isEmpty);
  });

  testWidgets('audio failure stays at the current word and allows retry', (
    tester,
  ) async {
    final voice = FakeVoiceProvider();
    await openPlaylist(tester, voice);
    await tapLabel(tester, 'ฟังคำแรก');
    voice.playback.single.completeError(StateError('audio unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('เปิดเสียงไม่ได้'), findsOneWidget);
    expect(find.text('station'), findsOneWidget);
    expect(find.text('จบการฟังชุดนี้'), findsNothing);
    await tapLabel(tester, 'ฟังตั้งแต่คำแรก');
    expect(voice.requests.map((request) => request.text), [
      'station',
      'station',
    ]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(voice.stops, greaterThan(0));
    expect(find.text('ฟังคำในชุดนี้'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
