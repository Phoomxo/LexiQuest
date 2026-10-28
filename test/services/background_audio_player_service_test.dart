import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/background_audio_player_service.dart';
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
  test(
    'BackgroundAudioPlayerService manages playlist playback state and stops',
    () async {
      final fakeVoice = FakeVoiceProvider();
      final service = BackgroundAudioPlayerService(fakeVoice);

      expect(service.isPlaying, false);
      final wordList = [
        {'word': 'apple', 'translation': 'แอปเปิ้ล'},
      ];

      service.startPlaylist(wordList: wordList, onWordChanged: (index) {});

      expect(service.isPlaying, true);
      service.stop();
      expect(service.isPlaying, false);
    },
  );
}
