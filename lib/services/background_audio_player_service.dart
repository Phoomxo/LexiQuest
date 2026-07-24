import 'dart:async';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';

class BackgroundAudioPlayerService {
  final VoiceProvider _voiceProvider;
  bool _isPlaying = false;
  int _currentIndex = 0;
  Timer? _playbackTimer;

  BackgroundAudioPlayerService(this._voiceProvider);

  bool get isPlaying => _isPlaying;
  int get currentIndex => _currentIndex;

  Future<void> startPlaylist({
    required List<Map<String, String>> wordList,
    required void Function(int index) onWordChanged,
  }) async {
    if (wordList.isEmpty || _isPlaying) return;
    _isPlaying = true;
    _currentIndex = 0;

    await _playSequence(wordList, onWordChanged);
  }

  Future<void> _playSequence(
    List<Map<String, String>> wordList,
    void Function(int index) onWordChanged,
  ) async {
    while (_isPlaying && _currentIndex < wordList.length) {
      onWordChanged(_currentIndex);
      final item = wordList[_currentIndex];
      final word = item['word'] ?? '';

      if (word.isNotEmpty) {
        try {
          await _voiceProvider.speak(
            VoiceRequest.create(
              text: word,
              language: 'en',
              voiceId: 'teacher_female',
              speed: 1.0,
              mode: VoiceMode.practice,
              contentId: word,
              contentType: 'background_playlist',
            ),
          );
        } catch (_) {}
      }

      await Future.delayed(const Duration(seconds: 2));
      if (!_isPlaying) break;
      _currentIndex++;
    }

    _isPlaying = false;
  }

  void stop() {
    _isPlaying = false;
    _playbackTimer?.cancel();
    _voiceProvider.stop();
  }
}
