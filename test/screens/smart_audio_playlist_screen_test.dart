import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/media_dependency_unavailable.dart';
import 'package:vocab_learning_app/screens/smart_audio_playlist_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  FakeVoiceProvider({this.stopError});

  final Object? stopError;
  final List<VoiceRequest> requests = <VoiceRequest>[];

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
  Future<void> stop() async {
    final error = stopError;
    if (error != null) throw error;
  }
}

void main() {
  testWidgets(
    'SmartAudioPlaylistScreen renders word and toggles play/pause button',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();
      final wordList = [
        {'word': 'apple', 'translation': 'แอปเปิ้ล', 'example': 'Red apple'},
        {'word': 'banana', 'translation': 'กล้วย', 'example': 'Yellow banana'},
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SmartAudioPlaylistScreen(
            wordList: wordList,
            voice: VoiceUseCases(
              provider: fakeVoice,
              disposeProvider: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('apple'), findsOneWidget);
      expect(find.text('เริ่มเล่นต่อเนื่อง'), findsOneWidget);

      await tester.tap(find.text('เริ่มเล่นต่อเนื่อง'));
      await tester.pump();

      expect(find.text('หยุดเล่น'), findsOneWidget);

      // Stop to cancel timer
      await tester.tap(find.text('หยุดเล่น'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets('missing voice renders the typed unavailable route', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SmartAudioPlaylistScreen(
          wordList: <Map<String, String>>[
            <String, String>{'word': 'apple'},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MediaDependencyUnavailable), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('media-dependency-unavailable')),
      findsOneWidget,
    );
    expect(find.text('apple'), findsNothing);
  });

  testWidgets(
    'stop cleanup failure is consumed and rendered provider-neutrally',
    (tester) async {
      final voice = VoiceUseCases(
        provider: FakeVoiceProvider(
          stopError: StateError('plugin stop failed'),
        ),
        disposeProvider: () async {},
      );
      addTearDown(() async {
        try {
          await voice.dispose();
        } on VoiceFailure {
          // The test deliberately injects a cleanup failure.
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SmartAudioPlaylistScreen(
            wordList: const <Map<String, String>>[
              <String, String>{'word': 'apple'},
              <String, String>{'word': 'banana'},
            ],
            voice: voice,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('smart-audio-voice-error')),
        findsOneWidget,
      );
      expect(find.textContaining('could not be stopped'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('background cancels the playlist before its delayed next item', (
    tester,
  ) async {
    final provider = FakeVoiceProvider();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SmartAudioPlaylistScreen(
            wordList: const <Map<String, String>>[
              <String, String>{'word': 'apple'},
              <String, String>{'word': 'banana'},
            ],
            voice: voice,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(provider.requests.map((request) => request.text), <String>[
        'apple',
      ]);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(provider.requests.map((request) => request.text), <String>[
        'apple',
      ]);
      expect(tester.takeException(), isNull);
    } finally {
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () => voice.dispose().timeout(const Duration(seconds: 1)),
      );
    }
  });
}
