import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../services/background_audio_player_service.dart';
import '../widgets/adaptive_content_pane.dart';

enum _PlaylistPhase { ready, playing, stopped, last, unavailable, summary }

class SmartAudioPlaylistScreen extends StatefulWidget {
  const SmartAudioPlaylistScreen({
    super.key,
    required this.wordList,
    this.voice,
    this.categoryName,
    this.returnLabel = 'กลับไปดูชุดคำ',
  });

  final List<Map<String, String>> wordList;
  final VoiceUseCases? voice;
  final String? categoryName;
  final String returnLabel;

  @override
  State<SmartAudioPlaylistScreen> createState() =>
      _SmartAudioPlaylistScreenState();
}

class _SmartAudioPlaylistScreenState extends State<SmartAudioPlaylistScreen> {
  VoiceUseCases? _voice;
  BackgroundAudioPlayerService? _player;
  _PlaylistPhase _phase = _PlaylistPhase.ready;
  int _index = 0;
  bool _leaving = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        if (_phase == _PlaylistPhase.playing) _stop();
      },
    );
  }

  void _start() {
    if (_leaving || ModalRoute.isCurrentOf(context) != true) return;
    final voice = _voice ??=
        widget.voice ?? VoiceUseCases.createOnDevice(awaitCompletion: true);
    final player = _player ??= BackgroundAudioPlayerService(voice.provider);
    setState(() {
      _index = 0;
      _phase = _PlaylistPhase.playing;
    });
    unawaited(
      player.startPlaylist(
        wordList: widget.wordList,
        onWordChanged: (index) {
          if (mounted && !_leaving) setState(() => _index = index);
        },
        onCompleted: () {
          if (mounted && !_leaving) _show(_PlaylistPhase.last);
        },
        onAudioUnavailable: () {
          if (mounted && !_leaving) _show(_PlaylistPhase.unavailable);
        },
      ),
    );
  }

  void _show(_PlaylistPhase phase) => setState(() => _phase = phase);

  void _stop() {
    final player = _player;
    if (player == null) return;
    unawaited(player.stop());
    _show(_PlaylistPhase.stopped);
  }

  void _markLeaving() {
    if (_leaving) return;
    _leaving = true;
    if (_player case final player?) unawaited(player.stop());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _markLeaving();
    _voice?.disposeIfOwned(widget.voice == null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.wordList;
    final heard = _player?.heardIndices ?? const <int>{};
    final title = switch (_phase) {
      _PlaylistPhase.ready => 'ฟังคำในชุด',
      _PlaylistPhase.playing => 'กำลังเล่นชุดคำ',
      _PlaylistPhase.stopped => 'หยุดฟังแล้ว',
      _PlaylistPhase.last => 'ฟังคำสุดท้าย',
      _PlaylistPhase.unavailable => 'เปิดเสียงไม่ได้',
      _PlaylistPhase.summary =>
        heard.length == words.length ? 'ฟังจบชุดแล้ว' : 'จบรอบการฟังแล้ว',
    };
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _markLeaving();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: M3Theme.appBarToolbarHeight(context),
          title: M3Theme.appBarTitle(context, title),
        ),
        body: AdaptiveContentPane(
          child: SafeArea(
            child: ListView(
              key: ValueKey(_phase),
              padding: const EdgeInsets.all(24),
              children: [
                if (widget.categoryName case final name?) ...[
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                ],
                if (words.isEmpty)
                  const Text('ชุดนี้ยังไม่มีคำให้ฟัง')
                else if (_phase == _PlaylistPhase.summary) ...[
                  Text(
                    'คำที่ฟังในชุดนี้',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (var index = 0; index < words.length; index++)
                    if (heard.contains(index)) _WordCard(item: words[index]),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _start,
                    child: const Text('ฟังอีกครั้ง'),
                  ),
                ] else ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _phase == _PlaylistPhase.stopped
                          ? 'หยุดที่คำ ${_index + 1} จาก ${words.length}'
                          : 'คำที่ ${_index + 1} จาก ${words.length}',
                    ),
                  ),
                  _WordCard(item: words[_index]),
                  const SizedBox(height: 16),
                  if (_phase == _PlaylistPhase.ready)
                    FilledButton(
                      onPressed: _start,
                      child: const Text('ฟังคำแรก'),
                    ),
                  if (_phase == _PlaylistPhase.playing) ...[
                    if (_index < words.length - 1)
                      FilledButton(
                        onPressed: () => unawaited(_player!.next()),
                        child: const Text('ฟังคำถัดไป'),
                      ),
                    OutlinedButton(
                      onPressed: _stop,
                      child: const Text('หยุดฟัง'),
                    ),
                  ],
                  if (_phase == _PlaylistPhase.unavailable)
                    Semantics(
                      liveRegion: true,
                      child: const Text(
                        'ลองตรวจเสียงในเครื่องแล้วเริ่มฟังอีกครั้ง',
                      ),
                    ),
                  if (_phase == _PlaylistPhase.last)
                    FilledButton(
                      onPressed: () => _show(_PlaylistPhase.summary),
                      child: const Text('จบการฟังชุดนี้'),
                    ),
                  if (_phase == _PlaylistPhase.stopped ||
                      _phase == _PlaylistPhase.last ||
                      _phase == _PlaylistPhase.unavailable)
                    OutlinedButton(
                      onPressed: _start,
                      child: const Text('ฟังตั้งแต่คำแรก'),
                    ),
                ],
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: Text(widget.returnLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WordCard extends StatelessWidget {
  const _WordCard({required this.item});

  final Map<String, String> item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final example = item['example'] ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item['word'] ?? '', style: theme.textTheme.headlineSmall),
            if (item['translation'] case final translation?)
              Text(translation, style: theme.textTheme.titleMedium),
            if (example.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(example),
            ],
          ],
        ),
      ),
    );
  }
}
