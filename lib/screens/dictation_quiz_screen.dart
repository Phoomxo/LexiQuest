import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../voice/voice_models.dart';
import '../widgets/adaptive_content_pane.dart';

enum _Step { listen, hint, write, miss, correct }

class DictationQuizScreen extends StatefulWidget {
  const DictationQuizScreen({
    super.key,
    required this.targetWord,
    this.meaning,
    this.partOfSpeech,
    this.categoryName,
    this.returnLabel = 'กลับไปดูคำเดิม',
    this.onReturn,
    this.autoPlay = true,
    this.voice,
  }) : _startWithHint = false;

  const DictationQuizScreen.withHint({
    super.key,
    required this.targetWord,
    required this.meaning,
    this.partOfSpeech,
    this.returnLabel = 'กลับไปดูคำเดิม',
  }) : categoryName = null,
       onReturn = null,
       autoPlay = false,
       voice = null,
       _startWithHint = true;

  final String targetWord;
  final String? meaning;
  final String? partOfSpeech;
  final String? categoryName;
  final String returnLabel;
  final VoidCallback? onReturn;
  final bool autoPlay;
  final VoiceUseCases? voice;
  final bool _startWithHint;

  @override
  State<DictationQuizScreen> createState() => _DictationQuizScreenState();
}

class _DictationQuizScreenState extends State<DictationQuizScreen> {
  final _answer = TextEditingController();
  VoiceUseCases? _localVoice;
  _Step _step = _Step.listen;
  double? _speed;
  double? _requestedSpeed;
  int _playGeneration = 0;
  bool _mayBePlaying = false;
  bool _audioUnavailable = false;
  bool _useHint = false;
  bool _emptyAnswer = false;
  String _submitted = '';

  String get _target => widget.targetWord.trim();
  bool get _station =>
      _target.toLowerCase() == 'station' && widget.meaning?.trim() == 'สถานี';
  bool get _missingStationI =>
      _target.toLowerCase() == 'station' &&
      _submitted.toLowerCase() == 'staton';
  VoiceUseCases? get _activeVoice => widget.voice ?? _localVoice;

  @override
  void initState() {
    super.initState();
    if (widget._startWithHint) {
      _useHint = true;
      _step = _Step.hint;
    }
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_play(1));
      });
    }
  }

  Future<void> _play(double speed) async {
    if (_speed != null || ModalRoute.isCurrentOf(context) != true) return;
    final generation = ++_playGeneration;
    setState(() {
      _speed = speed;
      _requestedSpeed = speed;
      _audioUnavailable = false;
      _mayBePlaying = true;
    });
    var failed = false;
    try {
      final voice =
          widget.voice ?? (_localVoice ??= VoiceUseCases.createOnDevice());
      await voice.speak(
        VoiceRequest.create(
          text: _target,
          language: 'en',
          voiceId: 'native-default',
          speed: speed,
          mode: VoiceMode.practice,
          contentId: _target,
          contentType: 'dictation_quiz',
        ),
      );
    } catch (_) {
      failed = true;
    }
    if (!mounted || generation != _playGeneration) return;
    setState(() {
      _speed = null;
      _audioUnavailable = failed;
    });
  }

  void _stopAudio() {
    _playGeneration++;
    _speed = null;
    if (!_mayBePlaying) return;
    _mayBePlaying = false;
    unawaited(_activeVoice?.stop().catchError((Object _) {}));
  }

  void _openHint() {
    _stopAudio();
    setState(() {
      _useHint = true;
      _step = _Step.hint;
    });
  }

  void _write() => setState(() => _step = _Step.write);

  void _submit() {
    if (_step != _Step.write || ModalRoute.isCurrentOf(context) != true) return;
    final answer = _answer.text.trim();
    if (answer.isEmpty) {
      setState(() => _emptyAnswer = true);
      return;
    }
    FocusScope.of(context).unfocus();
    _stopAudio();
    setState(() {
      _submitted = answer;
      _step = answer.toLowerCase() == _target.toLowerCase()
          ? _Step.correct
          : _Step.miss;
    });
  }

  void _restart() {
    _answer.clear();
    setState(() {
      _audioUnavailable = false;
      _requestedSpeed = null;
      _useHint = widget._startWithHint;
      _emptyAnswer = false;
      _submitted = '';
      _step = _useHint ? _Step.hint : _Step.listen;
    });
  }

  @override
  void dispose() {
    _stopAudio();
    _localVoice?.disposeIfOwned(true);
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _Step.listen => 'ฟังแล้วเขียน',
      _Step.hint => 'เขียนจากคำใบ้',
      _Step.write => 'เขียนคำตอบ',
      _Step.miss when _missingStationI => 'ยังขาดตัว i',
      _Step.miss => 'ลองตรวจตัวสะกดอีกครั้ง',
      _Step.correct => 'สะกดถูกแล้ว',
    };
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, title),
      ),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: SafeArea(
          child: ListView(
            key: ValueKey(_step),
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.categoryName case final name?) ...[
                Text('$name · 1 คำ'),
                const SizedBox(height: 12),
              ],
              ..._stepContent(context),
              const SizedBox(height: 16),
              TextButton(
                onPressed: widget.onReturn ?? () => Navigator.maybePop(context),
                child: Text(widget.returnLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stepContent(BuildContext context) {
    final heading = Theme.of(context).textTheme.headlineSmall;
    switch (_step) {
      case _Step.listen:
        return [
          const Text('ลองฟัง แล้วพิมพ์คำที่ได้ยิน'),
          const SizedBox(height: 12),
          ..._audioButtons(),
          FilledButton(
            onPressed: _write,
            child: const Text('ลองเขียนคำที่ได้ยิน'),
          ),
          TextButton(onPressed: _openHint, child: const Text('เปิดคำใบ้แทน')),
          if (widget.autoPlay) ..._answerForm(),
        ];
      case _Step.hint:
        return [
          const Text('ฝึกต่อโดยไม่เปิดเสียง'),
          const SizedBox(height: 12),
          if (widget.meaning case final meaning?) Text(meaning, style: heading),
          if (widget.partOfSpeech case final part?) Text(part),
          if (_target.characters.length > 1)
            Text('ขึ้นต้นด้วย ${_target.characters.take(_station ? 2 : 1)}'),
          if (_station) ...[
            const SizedBox(height: 12),
            const Text('Meet me at the ____.'),
          ],
          const SizedBox(height: 12),
          FilledButton(onPressed: _write, child: const Text('ลองเขียนคำ')),
        ];
      case _Step.write:
        return [
          if (!_useHint) ..._audioButtons(),
          ..._answerForm(),
          if (!_useHint)
            TextButton(onPressed: _openHint, child: const Text('เปิดคำใบ้แทน')),
        ];
      case _Step.miss:
        return [
          Text(_submitted, style: heading),
          Text(
            'เทียบกับ $_target${widget.meaning == null ? '' : ' · ${widget.meaning}'}',
          ),
          if (_missingStationI) const Text('คำว่า station ลงท้ายด้วย -tion'),
          const SizedBox(height: 12),
          FilledButton(onPressed: _write, child: const Text('แก้คำตอบ')),
        ];
      case _Step.correct:
        return [
          Text(_target, style: heading),
          if (widget.meaning case final meaning?) Text(meaning),
          if (_station) ...[
            const SizedBox(height: 12),
            const Text('Meet me at the station.'),
            const Text('มาเจอกันที่สถานีนะ'),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _restart,
            child: Text(
              widget._startWithHint
                  ? 'ลองเขียนอีกครั้ง'
                  : 'ลองฟังคำนี้อีกครั้ง',
            ),
          ),
        ];
    }
  }

  List<Widget> _audioButtons() => [
    OutlinedButton.icon(
      onPressed: _speed == null ? () => _play(1) : null,
      icon: const Icon(Icons.volume_up_outlined),
      label: const Text('ฟังด้วยความเร็วปกติ'),
    ),
    OutlinedButton.icon(
      onPressed: _speed == null ? () => _play(.75) : null,
      icon: const Icon(Icons.slow_motion_video),
      label: const Text('ฟังช้าลง'),
    ),
    if (_speed case final speed?)
      Semantics(
        liveRegion: true,
        child: Text(
          speed == .75 ? 'กำลังเปิดเสียง 0.75 เท่า' : 'กำลังเปิดเสียง',
        ),
      ),
    if (_audioUnavailable)
      Semantics(liveRegion: true, child: const Text('ตอนนี้ฟังเสียงไม่ได้'))
    else if (_speed == null && _requestedSpeed != null)
      Text(_requestedSpeed == .75 ? 'ความเร็ว 0.75 เท่า' : 'ความเร็วปกติ'),
  ];

  List<Widget> _answerForm() => [
    TextField(
      controller: _answer,
      maxLength: maxSpellingLength,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: 'คำตอบ',
        errorText: _emptyAnswer ? 'พิมพ์คำตอบก่อนตรวจ' : null,
      ),
      onChanged: (_) {
        if (_emptyAnswer) setState(() => _emptyAnswer = false);
      },
      onSubmitted: (_) => _checkFromForm(),
    ),
    FilledButton(onPressed: _checkFromForm, child: const Text('ตรวจคำตอบ')),
  ];

  void _checkFromForm() {
    if (_step == _Step.listen && widget.autoPlay) _write();
    _submit();
  }
}
