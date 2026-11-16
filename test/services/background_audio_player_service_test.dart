import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/background_audio_player_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> requests = [];
  final List<Completer<VoicePlaybackResult>> completions = [];
  Completer<void>? pendingStop;
  int stops = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) {
    requests.add(request);
    final playback = Completer<VoicePlaybackResult>();
    completions.add(playback);
    return playback.future;
  }

  void finish(int request) {
    completions[request].complete(
      const VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: false,
      ),
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    await pendingStop?.future;
  }
}

const words = [
  {'word': 'station'},
  {'word': 'platform'},
  {'word': 'ticket'},
];

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'BackgroundAudioPlayerService manages playlist playback state and stops',
    () async {
      final fakeVoice = FakeVoiceProvider();
      final service = BackgroundAudioPlayerService(fakeVoice);

      expect(service.isPlaying, false);
      final wordList = [
        {'word': 'apple', 'translation': 'แอปเปิ้ล'},
      ];

      final run = service.startPlaylist(
        wordList: wordList,
        onWordChanged: (index) {},
      );

      expect(service.isPlaying, true);
      await service.stop();
      await run;
      expect(service.isPlaying, false);
      expect(fakeVoice.stops, 1);
    },
  );

  test(
    'advances only after playback ends and completes on the final word',
    () async {
      final voice = FakeVoiceProvider();
      final service = BackgroundAudioPlayerService(voice);
      final indices = <int>[];
      var ends = 0;
      final run = service.startPlaylist(
        wordList: words,
        onWordChanged: indices.add,
        onCompleted: () => ends++,
      );
      expect(indices, [0]);
      await flush();
      expect(indices, [0]);
      voice.finish(0);
      await flush();
      expect(indices, [0, 1]);
      expect(ends, 0);
      voice.finish(1);
      await flush();
      expect(indices, [0, 1, 2]);
      expect(ends, 0);
      voice.finish(2);
      await run;
      expect(voice.requests.map((request) => request.text), [
        'station',
        'platform',
        'ticket',
      ]);
      expect(ends, 1);
      expect(service.currentIndex, 2);
      expect(service.heardIndices, {0, 1, 2});
      expect(service.isPlaying, false);
    },
  );

  test('stopped playback cannot affect an immediate restart', () async {
    final voice = FakeVoiceProvider();
    final service = BackgroundAudioPlayerService(voice);
    final oldIndices = <int>[];
    final newIndices = <int>[];
    var oldEnds = 0;
    final original = service.startPlaylist(
      wordList: words,
      onWordChanged: oldIndices.add,
      onCompleted: () => oldEnds++,
    );
    voice.finish(0);
    await flush();
    voice.pendingStop = Completer<void>();
    final stop = service.stop();
    expect(service.currentIndex, 1);
    expect(service.isPlaying, false);
    final restarted = service.startPlaylist(
      wordList: words,
      onWordChanged: newIndices.add,
    );
    expect(voice.requests, hasLength(2));
    voice.pendingStop!.complete();
    await stop;
    await original;
    expect(newIndices, [0]);
    voice.finish(1);
    await flush();
    expect(oldIndices, [0, 1]);
    expect(newIndices, [0]);
    expect(oldEnds, 0);
    expect(service.isPlaying, true);
    expect(voice.requests.map((request) => request.text), [
      'station',
      'platform',
      'station',
    ]);
    await service.stop();
    await restarted;
  });

  test('Next interrupts once and ignores the old playback result', () async {
    final voice = FakeVoiceProvider();
    final service = BackgroundAudioPlayerService(voice);
    final indices = <int>[];
    final run = service.startPlaylist(
      wordList: words,
      onWordChanged: indices.add,
    );
    voice.pendingStop = Completer<void>();
    final next = service.next();
    await service.next();
    expect(voice.stops, 1);
    expect(indices, [0]);
    voice.pendingStop!.complete();
    await next;
    expect(indices, [0, 1]);
    voice.completions.first.completeError(StateError('old voice ended'));
    await flush();
    expect(indices, [0, 1]);
    expect(service.isPlaying, true);
    expect(service.heardIndices, isEmpty);
    await service.stop();
    await run;
  });

  test(
    'queued restart waits for stop and reports when stopping fails',
    () async {
      final voice = FakeVoiceProvider();
      final service = BackgroundAudioPlayerService(voice);
      var failures = 0;
      final original = service.startPlaylist(
        wordList: words,
        onWordChanged: (_) {},
      );
      voice.pendingStop = Completer<void>();
      final stop = service.stop();
      final restarted = service.startPlaylist(
        wordList: words,
        onWordChanged: (_) {},
        onAudioUnavailable: () => failures++,
      );
      voice.pendingStop!.completeError(StateError('failed to stop'));
      await Future.wait([stop, original, restarted]);
      expect(voice.requests, hasLength(1));
      expect(service.isPlaying, false);
      expect(failures, 1);

      voice.pendingStop = Completer<void>();
      final nextTry = service.startPlaylist(
        wordList: words,
        onWordChanged: (_) {},
      );
      expect(voice.requests, hasLength(1));
      voice.pendingStop!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(voice.requests, hasLength(2));
      await service.stop();
      await nextTry;
    },
  );

  test('failed audio reports unavailability and does not advance', () async {
    final voice = FakeVoiceProvider();
    final service = BackgroundAudioPlayerService(voice);
    final indices = <int>[];
    var failures = 0;
    var ends = 0;
    final run = service.startPlaylist(
      wordList: words,
      onWordChanged: indices.add,
      onCompleted: () => ends++,
      onAudioUnavailable: () => failures++,
    );
    voice.completions.first.completeError(StateError('device has no audio'));
    await run;
    expect(indices, [0]);
    expect(failures, 1);
    expect(ends, 0);
    expect(service.isPlaying, false);
  });

  testWidgets('timed-out stop still fences new playback until it settles', (
    tester,
  ) async {
    final voice = FakeVoiceProvider();
    final service = BackgroundAudioPlayerService(voice);
    unawaited(service.startPlaylist(wordList: words, onWordChanged: (_) {}));
    voice.pendingStop = Completer<void>();
    final stopping = service.stop();
    await tester.pump(const Duration(seconds: 6));
    await stopping;
    var unavailable = false;
    await service.startPlaylist(
      wordList: words,
      onWordChanged: (_) {},
      onAudioUnavailable: () => unavailable = true,
    );
    expect(unavailable, isTrue);
    expect(voice.requests, hasLength(1));

    voice.pendingStop!.complete();
    await tester.pump();
    unawaited(service.startPlaylist(wordList: words, onWordChanged: (_) {}));
    expect(voice.requests, hasLength(2));
    await service.stop();
  });
}
