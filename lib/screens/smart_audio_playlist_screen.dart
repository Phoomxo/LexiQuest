import 'dart:async';

import 'package:flutter/material.dart';

import '../features/voice/application/voice_use_cases.dart';
import '../features/voice/presentation/route_voice_session_mixin.dart';
import '../runtime/app_dependencies.dart';
import '../services/background_audio_player_service.dart';
import '../voice/voice_models.dart';
import 'media_dependency_unavailable.dart';

class SmartAudioPlaylistScreen extends StatefulWidget {
  const SmartAudioPlaylistScreen({
    super.key,
    required this.wordList,
    this.voice,
  });

  final List<Map<String, String>> wordList;
  final VoiceUseCases? voice;

  @override
  State<SmartAudioPlaylistScreen> createState() =>
      _SmartAudioPlaylistScreenState();
}

class _SmartAudioPlaylistScreenState extends State<SmartAudioPlaylistScreen>
    with
        WidgetsBindingObserver,
        RouteVoiceSessionMixin<SmartAudioPlaylistScreen> {
  VoiceUseCases? _voice;
  VoiceSession? _playerSession;
  BackgroundAudioPlayerService? _playerService;
  int _currentIndex = 0;
  VoiceFailure? _voiceFailure;

  @override
  VoiceUseCases? get routeVoiceUseCases => _voice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _voice = widget.voice ?? AppDependenciesScope.maybeOf(context)?.voice;
    refreshRouteVoiceSession();
  }

  @override
  void didUpdateWidget(covariant SmartAudioPlaylistScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.voice, widget.voice)) {
      _voice = widget.voice ?? AppDependenciesScope.maybeOf(context)?.voice;
      refreshRouteVoiceSession();
    }
  }

  @override
  void onVoiceRouteResumed() {
    final session = routeVoiceSession;
    if (session == null || identical(session, _playerSession)) return;
    final previous = _playerService;
    _playerSession = session;
    _playerService = BackgroundAudioPlayerService(session);
    if (previous != null) _observe(previous.dispose());
  }

  @override
  Future<void> onVoiceRouteCovered() async {
    final player = _playerService;
    _playerService = null;
    _playerSession = null;
    if (player == null) return;
    try {
      await player.dispose();
    } on Object catch (error) {
      _showFailure(error, player: player);
    }
  }

  @override
  Future<void> onVoiceAppBackgrounded() async {
    final player = _playerService;
    if (player == null) return;
    try {
      await player.stop();
    } on Object catch (error) {
      _showFailure(error, player: player);
    }
    if (mounted && identical(player, _playerService)) setState(() {});
  }

  void _observe(
    Future<void> operation, {
    BackgroundAudioPlayerService? player,
  }) {
    unawaited(
      operation.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          _showFailure(error, player: player);
        },
      ),
    );
  }

  void _showFailure(Object error, {BackgroundAudioPlayerService? player}) {
    if (!mounted || (player != null && !identical(player, _playerService))) {
      return;
    }
    final failure = error is VoiceFailure ? error : _unknownVoiceFailure;
    if (failure.category == VoiceFailureCategory.cancelled) return;
    setState(() => _voiceFailure = failure);
  }

  void _togglePlaylist() {
    final player = _playerService;
    if (player == null) return;
    if (player.isPlaying) {
      _observe(player.stop(), player: player);
      setState(() {});
      return;
    }
    setState(() => _voiceFailure = null);
    final running = player.startPlaylist(
      wordList: widget.wordList,
      onWordChanged: (index) {
        if (mounted && identical(player, _playerService)) {
          setState(() => _currentIndex = index);
        }
      },
      onFailure: (failure) => _showFailure(failure, player: player),
    );
    unawaited(
      running.then<void>(
        (_) {
          if (mounted && identical(player, _playerService)) setState(() {});
        },
        onError: (Object error, StackTrace _) {
          _showFailure(error, player: player);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_voice == null) {
      return const MediaDependencyUnavailable(
        reason: MediaDependencyUnavailableReason.voice,
      );
    }
    final isPlaying = _playerService?.isPlaying ?? false;
    final currentItem =
        widget.wordList.isNotEmpty && _currentIndex < widget.wordList.length
        ? widget.wordList[_currentIndex]
        : <String, String>{'word': '', 'translation': '', 'example': ''};
    final word = currentItem['word'] ?? '';
    final translation = currentItem['translation'] ?? '';
    final example = currentItem['example'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Smart audio vocabulary playlist',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.deepPurple,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.headphones, size: 80, color: Colors.deepPurple),
            if (_voiceFailure case final failure?) ...[
              const SizedBox(height: 16),
              Text(
                _failureText(failure.category),
                key: const ValueKey<String>('smart-audio-voice-error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 30),
            Text(
              word,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              translation,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.deepOrange,
              ),
            ),
            const SizedBox(height: 20),
            if (example.isNotEmpty)
              Text(
                'Ex: "$example"',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  color: Colors.black87,
                ),
              ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _playerService == null ? null : _togglePlaylist,
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(isPlaying ? 'หยุดเล่น' : 'เริ่มเล่นต่อเนื่อง'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isPlaying ? Colors.red : Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _failureText(VoiceFailureCategory category) => switch (category) {
  VoiceFailureCategory.cleanupIncomplete =>
    'Voice playback could not be stopped. Try again.',
  VoiceFailureCategory.network =>
    'Voice playback is offline. Check your connection and try again.',
  VoiceFailureCategory.timeout => 'Voice playback timed out. Try again.',
  _ => 'Voice playback is unavailable right now.',
};

const _unknownVoiceFailure = VoiceFailure(
  category: VoiceFailureCategory.unknown,
  message: 'Voice playback is unavailable.',
);
