import 'package:flutter/material.dart';
import '../services/background_audio_player_service.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';

class SmartAudioPlaylistScreen extends StatefulWidget {
  final List<Map<String, String>> wordList;
  final VoiceProvider? voiceProvider;

  const SmartAudioPlaylistScreen({
    super.key,
    required this.wordList,
    this.voiceProvider,
  });

  @override
  State<SmartAudioPlaylistScreen> createState() =>
      _SmartAudioPlaylistScreenState();
}

class _SmartAudioPlaylistScreenState extends State<SmartAudioPlaylistScreen> {
  late final VoiceProvider _voiceProvider;
  late final BackgroundAudioPlayerService _playerService;
  bool _ownsVoiceProvider = false;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.voiceProvider != null) {
      _voiceProvider = widget.voiceProvider!;
      _ownsVoiceProvider = false;
    } else {
      _voiceProvider = VoiceServiceFactory.create();
      _ownsVoiceProvider = true;
    }
    _playerService = BackgroundAudioPlayerService(_voiceProvider);
  }

  void _togglePlaylist() {
    if (_playerService.isPlaying) {
      _playerService.stop();
      setState(() {});
    } else {
      _playerService.startPlaylist(
        wordList: widget.wordList,
        onWordChanged: (index) {
          if (mounted) {
            setState(() {
              _currentIndex = index;
            });
          }
        },
      );
      setState(() {});
    }
  }

  @override
  void dispose() {
    _playerService.stop();
    if (_ownsVoiceProvider && _voiceProvider is ManagedVoiceService) {
      _voiceProvider.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentItem =
        widget.wordList.isNotEmpty && _currentIndex < widget.wordList.length
        ? widget.wordList[_currentIndex]
        : {'word': '', 'translation': '', 'example': ''};

    final word = currentItem['word'] ?? '';
    final translation = currentItem['translation'] ?? '';
    final example = currentItem['example'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'เครื่องเล่นเสียงทบทวนคำศัพท์',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.deepPurple,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.headphones, size: 80, color: Colors.deepPurple),
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
              onPressed: _togglePlaylist,
              icon: Icon(
                _playerService.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
              label: Text(
                _playerService.isPlaying ? 'หยุดเล่น' : 'เริ่มเล่นต่อเนื่อง',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _playerService.isPlaying
                    ? Colors.red
                    : Colors.deepPurple,
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
