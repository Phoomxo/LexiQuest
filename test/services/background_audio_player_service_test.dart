import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/services/background_audio_player_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  test('playlist uses one voice session and preserves item order', () async {
    final provider = _PlaylistProvider();
    final useCases = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    final session = useCases.acquireSession();
    final service = BackgroundAudioPlayerService(
      session,
      interItemDelay: Duration.zero,
    );
    final changed = <int>[];

    await service.startPlaylist(
      wordList: const <Map<String, String>>[
        <String, String>{'word': 'one'},
        <String, String>{'word': 'two'},
        <String, String>{'word': 'three'},
      ],
      onWordChanged: changed.add,
    );

    expect(provider.spoken, <String>['one', 'two', 'three']);
    expect(changed, <int>[0, 1, 2]);
    expect(session.isCurrent, isTrue);
    await service.dispose();
    await useCases.dispose();
  });

  test('stop interrupts inter-item delay and never starts next item', () async {
    final provider = _PlaylistProvider();
    final useCases = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    final service = BackgroundAudioPlayerService(
      useCases.acquireSession(),
      interItemDelay: const Duration(minutes: 1),
    );
    final firstChanged = Completer<void>();

    final running = service.startPlaylist(
      wordList: const <Map<String, String>>[
        <String, String>{'word': 'one'},
        <String, String>{'word': 'two'},
      ],
      onWordChanged: (_) {
        if (!firstChanged.isCompleted) firstChanged.complete();
      },
    );
    await firstChanged.future;
    await Future<void>.delayed(Duration.zero);

    await service.stop();
    await running;

    expect(provider.spoken, <String>['one']);
    expect(service.isPlaying, isFalse);
    await service.dispose();
    await useCases.dispose();
  });

  test(
    'cancelled playback ends silently and typed failures are reported',
    () async {
      final provider = _PlaylistProvider(
        failure: const VoiceFailure(
          category: VoiceFailureCategory.network,
          message: 'offline',
        ),
      );
      final useCases = VoiceUseCases(
        provider: provider,
        disposeProvider: () async {},
      );
      final service = BackgroundAudioPlayerService(
        useCases.acquireSession(),
        interItemDelay: Duration.zero,
      );
      final failures = <VoiceFailure>[];

      await service.startPlaylist(
        wordList: const <Map<String, String>>[
          <String, String>{'word': 'one'},
        ],
        onWordChanged: (_) {},
        onFailure: failures.add,
      );

      expect(failures, hasLength(1));
      expect(failures.single.category, VoiceFailureCategory.network);
      await service.dispose();
      await useCases.dispose();
    },
  );
}

final class _PlaylistProvider implements VoiceProvider {
  _PlaylistProvider({this.failure});

  final VoiceFailure? failure;
  final List<String> spoken = <String>[];

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spoken.add(request.text);
    final failure = this.failure;
    if (failure != null) throw failure;
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}
