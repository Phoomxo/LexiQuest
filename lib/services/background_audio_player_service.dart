import 'dart:async';

import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';

class BackgroundAudioPlayerService {
  BackgroundAudioPlayerService(this._voiceProvider);

  final VoiceProvider _voiceProvider;
  final Set<int> _heardIndices = {};
  _PlaylistRun? _run;
  Future<bool>? _pendingStop;
  bool _needsStop = false;
  int _generation = 0;
  int _currentIndex = 0;

  bool get isPlaying => _run != null;
  int get currentIndex => _currentIndex;
  Set<int> get heardIndices => Set.unmodifiable(_heardIndices);

  Future<void> startPlaylist({
    required List<Map<String, String>> wordList,
    required void Function(int index) onWordChanged,
    void Function()? onCompleted,
    void Function()? onAudioUnavailable,
  }) {
    if (wordList.isEmpty || isPlaying) return Future<void>.value();
    final run = _PlaylistRun(
      words: [for (final entry in wordList) entry['word'] ?? ''],
      onWordChanged: onWordChanged,
      onCompleted: onCompleted,
      onAudioUnavailable: onAudioUnavailable,
    );
    _run = run;
    _currentIndex = 0;
    _heardIndices.clear();
    final generation = ++_generation;
    final pendingStop = _pendingStop ?? (_needsStop ? _stopVoice() : null);
    unawaited(
      pendingStop == null
          ? _playSequence(run, generation)
          : _startAfterStop(run, generation, pendingStop),
    );
    return run.done.future;
  }

  Future<void> _startAfterStop(
    _PlaylistRun run,
    int generation,
    Future<bool> pendingStop,
  ) async {
    final stopped = await pendingStop;
    if (!_isCurrent(run, generation)) return;
    if (stopped) {
      await _playSequence(run, generation);
    } else {
      _finish(run, unavailable: true);
    }
  }

  bool _isCurrent(_PlaylistRun run, int generation) =>
      identical(_run, run) && generation == _generation;

  Future<void> _playSequence(_PlaylistRun run, int generation) async {
    while (_isCurrent(run, generation)) {
      final index = _currentIndex;
      final word = run.words[index];
      try {
        run.onWordChanged(index);
        if (!_isCurrent(run, generation)) return;
        await _voiceProvider.speak(
          VoiceRequest.create(
            text: word,
            language: 'en',
            voiceId: 'native-default',
            speed: 1,
            mode: VoiceMode.practice,
            contentId: word,
            contentType: 'background_playlist',
          ),
        );
      } catch (_) {
        if (_isCurrent(run, generation)) _finish(run, unavailable: true);
        return;
      }
      if (!_isCurrent(run, generation)) return;
      _heardIndices.add(index);
      if (index == run.words.length - 1) {
        _finish(run, unavailable: false);
        return;
      }
      _currentIndex++;
    }
  }

  Future<void> next() async {
    final run = _run;
    if (run == null ||
        _pendingStop != null ||
        _currentIndex == run.words.length - 1) {
      return;
    }
    final generation = ++_generation;
    final stopped = await _stopVoice();
    if (!_isCurrent(run, generation)) return;
    if (!stopped) {
      _finish(run, unavailable: true);
      return;
    }
    _currentIndex++;
    unawaited(_playSequence(run, generation));
  }

  Future<void> stop() async {
    final run = _run;
    if (run == null) {
      await _pendingStop;
      return;
    }
    _generation++;
    _run = null;
    run.done.complete();
    await _stopVoice();
  }

  Future<bool> _stopVoice() {
    if (_pendingStop case final pending?) return pending;
    final stopped = Completer<bool>();
    final pending = stopped.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
    _pendingStop = pending;
    unawaited(_stopProvider(stopped));
    return pending;
  }

  Future<void> _stopProvider(Completer<bool> stopped) async {
    var succeeded = false;
    try {
      await _voiceProvider.stop();
      succeeded = true;
    } catch (_) {
      // A new word cannot start until the previous request is stopped.
    } finally {
      _needsStop = !succeeded;
      _pendingStop = null;
      stopped.complete(succeeded);
    }
  }

  void _finish(_PlaylistRun run, {required bool unavailable}) {
    _run = null;
    run.done.complete();
    if (unavailable) {
      run.onAudioUnavailable?.call();
    } else {
      run.onCompleted?.call();
    }
  }
}

final class _PlaylistRun {
  _PlaylistRun({
    required this.words,
    required this.onWordChanged,
    this.onCompleted,
    this.onAudioUnavailable,
  });

  final List<String> words;
  final void Function(int) onWordChanged;
  final void Function()? onCompleted;
  final void Function()? onAudioUnavailable;
  final done = Completer<void>();
}
