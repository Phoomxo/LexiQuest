import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../navigation/app_routes.dart';
import '../voice/voice_models.dart';
import '../widgets/adaptive_content_pane.dart';
import 'cefr_station_exercise_screen.dart';

class CefrArticleReaderScreen extends StatefulWidget {
  const CefrArticleReaderScreen({
    super.key,
    required this.title,
    required this.content,
    required this.cefrLevel,
    this.voice,
    this.returnLabel,
    this.showStationExercise = false,
    this.onOpenNext,
    this.onReturnHome,
  });

  final String title;
  final String content;
  final String cefrLevel;
  final VoiceUseCases? voice;
  final String? returnLabel;
  final bool showStationExercise;
  final ValueChanged<BuildContext>? onOpenNext;
  final VoidCallback? onReturnHome;

  @override
  State<CefrArticleReaderScreen> createState() =>
      _CefrArticleReaderScreenState();
}

class _CefrArticleReaderScreenState extends State<CefrArticleReaderScreen> {
  VoiceUseCases? _localVoice;
  String? _selected;
  bool _speaking = false;
  bool _voiceFailed = false;

  Future<bool> _speak(String text) async {
    if (_speaking) return false;
    setState(() {
      _speaking = true;
      _voiceFailed = false;
    });
    final voice =
        widget.voice ?? (_localVoice ??= VoiceUseCases.createOnDevice());
    var failed = false;
    try {
      await voice.speak(
        VoiceRequest.create(
          text: text,
          language: 'en',
          voiceId: 'native-default',
          speed: 1,
          mode: VoiceMode.practice,
          contentId: widget.cefrLevel,
          contentType: 'article_reader',
        ),
      );
    } on Object {
      failed = true;
    } finally {
      if (mounted) {
        setState(() {
          _speaking = false;
          _voiceFailed = failed;
        });
      }
    }
    return !failed;
  }

  void _tapWord(String word, String line) {
    if (widget.showStationExercise && word.toLowerCase() == 'platform') {
      _openPlatform(line);
      return;
    }
    if (_speaking) return;
    setState(() => _selected = word);
    unawaited(_speak(word));
  }

  void _openPlatform([String line = 'They meet on the platform.']) {
    if (_speaking || ModalRoute.of(context)?.isCurrent != true) return;
    setState(() => _selected = 'platform');
    unawaited(
      AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/cefr/station-word',
          builder: (_) => _PlatformInContext(line: line, speak: _speak),
        ),
      ),
    );
  }

  Future<void> _openExercise() async {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final exit = await AppNavigator.pushPage<CefrStationExit>(
      context,
      AppPage<CefrStationExit>(
        name: 'learning/cefr/station-practice',
        builder: (_) => CefrStationExerciseScreen(
          returnLabel: widget.returnLabel,
          canReturnHome: widget.onReturnHome != null,
        ),
      ),
    );
    if (!mounted) return;
    switch (exit) {
      case CefrStationExit.origin:
        await Navigator.maybePop(context);
      case CefrStationExit.home:
        widget.onReturnHome?.call();
      case null:
        break;
    }
  }

  @override
  void dispose() {
    final voice = widget.voice ?? _localVoice;
    if (voice != null) {
      unawaited(voice.stop().catchError((Object _) {}));
      voice.disposeIfOwned(widget.voice == null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'บทอ่าน ${widget.cefrLevel}'),
      ),
      body: AdaptiveContentPane(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(widget.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                widget.showStationExercise
                    ? 'แตะคำเพื่อฟัง หรือเปิดความหมายของ platform'
                    : 'แตะคำเพื่อฟังเสียงอ่าน',
              ),
              for (final line in widget.content.split('\n'))
                if (line.trim().isEmpty)
                  const SizedBox(height: 14)
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final token in line.split(RegExp(r'\s+')))
                          if (token.isNotEmpty) _wordTile(token, line),
                      ],
                    ),
                  ),
              if (_selected case final word?)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text('คำที่เลือก $word'),
                ),
              if (_voiceFailed)
                Semantics(
                  liveRegion: true,
                  child: const Text('เปิดเสียงไม่ได้ อ่านต่อจากข้อความได้'),
                ),
              const SizedBox(height: 16),
              if (widget.showStationExercise) ...[
                OutlinedButton(
                  onPressed: _speaking ? null : _openPlatform,
                  child: const Text('ดูความหมายของ platform'),
                ),
                FilledButton(
                  onPressed: _openExercise,
                  child: const Text('ฝึกคำจากเรื่องนี้'),
                ),
              ],
              if (widget.onOpenNext case final open?)
                OutlinedButton(
                  onPressed: () => open(context),
                  child: const Text('อ่านเรื่องนัดกันที่สถานี'),
                ),
              if (widget.returnLabel case final label?)
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: Text(label),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wordTile(String token, String line) {
    final word = token.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    final selected = word == _selected;
    return TextButton(
      onPressed: word.isEmpty || _speaking ? null : () => _tapWord(word, line),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        backgroundColor: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      child: Text(token, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

class _PlatformInContext extends StatefulWidget {
  const _PlatformInContext({required this.line, required this.speak});

  final String line;
  final Future<bool> Function(String) speak;

  @override
  State<_PlatformInContext> createState() => _PlatformInContextState();
}

class _PlatformInContextState extends State<_PlatformInContext> {
  bool _showPronunciation = false;
  bool _busy = false;
  bool _voiceFailed = false;

  Future<void> _play() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _voiceFailed = false;
    });
    final played = await widget.speak(widget.line);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _voiceFailed = !played;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: M3Theme.appBarToolbarHeight(context),
      title: M3Theme.appBarTitle(context, 'คำในบทอ่าน'),
    ),
    body: AdaptiveContentPane(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('platform', style: Theme.of(context).textTheme.headlineSmall),
            const Text('คำนาม · ชานชาลา'),
            const SizedBox(height: 16),
            Text(widget.line),
            Text(
              widget.line == 'Her friend is on platform two.'
                  ? 'เพื่อนของมินารออยู่ที่ชานชาลาสอง'
                  : 'ทั้งสองคนเจอกันที่ชานชาลา',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _play,
              icon: const Icon(Icons.volume_up_outlined),
              label: Text(_busy ? 'กำลังเปิดเสียง' : 'ฟังคำในประโยค'),
            ),
            TextButton(
              onPressed: () => setState(() => _showPronunciation = true),
              child: const Text('ดูคำอ่านแทน'),
            ),
            if (_voiceFailed)
              Semantics(
                liveRegion: true,
                child: const Text('เปิดเสียงไม่ได้ อ่านคำอ่านด้านล่างได้'),
              ),
            if (_showPronunciation || _voiceFailed)
              Semantics(
                liveRegion: true,
                child: const Text('แพลตฟอร์ม · เน้นพยางค์แรก'),
              ),
            OutlinedButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('อ่านต่อที่เดิม'),
            ),
          ],
        ),
      ),
    ),
  );
}
