import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../../runtime/registries/feature_registry.dart';
import '../../../voice/voice_models.dart';
import '../../media_practice/application/speech_practice_use_cases.dart';
import '../../media_practice/domain/media_practice_contracts.dart';
import '../../voice/application/voice_use_cases.dart';
import '../../voice/presentation/route_voice_session_mixin.dart';
import 'unified_lesson_shell.dart';

/// Optional, in-memory rehearsal of an already answered sentence.
/// This widget has no learning, evidence, reward or persistence dependency.
class SentencePracticePanel extends StatefulWidget {
  const SentencePracticePanel({
    super.key,
    required this.identity,
    required this.text,
    required this.canInteract,
    this.voice,
    this.speechPractice,
  });
  final String identity;
  final String text;
  final bool Function() canInteract;
  final VoiceUseCases? voice;
  final SpeechPracticeUseCases? speechPractice;
  @override
  State<SentencePracticePanel> createState() => _SentencePracticePanelState();
}

class _SentencePracticePanelState extends State<SentencePracticePanel>
    with WidgetsBindingObserver, RouteVoiceSessionMixin<SentencePracticePanel>
    implements EphemeralLessonState {
  VoiceUseCases? _voice;
  SpeechPracticeUseCases? _speech;
  VoiceSession? _playback;
  SpeechPracticeSession? _recognition;
  Future<void>? _cleanupBarrier;
  UnifiedLessonSessionLifecycleScope? _scope;
  FeatureRegistry? _features;
  Listenable? _featureChanges;
  int _epoch = 0;
  bool _retired = false;
  bool _disposing = false;
  bool _playing = false;
  bool _recording = false;
  bool _attempted = false;
  String? _transcript;
  String? _status;

  bool get _accepts {
    if (!mounted || _disposing || _retired) return false;
    final state = WidgetsBinding.instance.lifecycleState;
    return (state == null || state == AppLifecycleState.resumed) &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        (_scope?.lifecycle?.acceptsOperations ?? true) &&
        widget.canInteract();
  }

  bool get _speechEnabled =>
      _features?.isEnabled(Feature.speechPractice) ?? true;

  @override
  VoiceUseCases? get routeVoiceUseCases => _retired ? null : _voice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = UnifiedLessonSessionLifecycleScope.maybeScopeOf(context);
    if (!identical(next, _scope)) {
      _scope?.unregisterEphemeralState(this);
      _scope = next;
      next?.registerEphemeralState(this);
    }
    _bindServices();
  }

  @override
  void didUpdateWidget(SentencePracticePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.text != widget.text) {
      _invalidate(notify: false).ignore();
      _retired = false;
      _attempted = false;
    }
    _bindServices();
    if (!_accepts) _invalidate(notify: false).ignore();
  }

  void _bindServices() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final voice = widget.voice ?? dependencies?.voice;
    final speech = widget.speechPractice ?? dependencies?.speechPractice;
    final features = dependencies?.features;
    if (!identical(voice, _voice) || !identical(speech, _speech)) {
      _invalidate(notify: false).ignore();
      _voice = voice;
      _speech = speech;
      refreshRouteVoiceSession();
    }
    if (!identical(features, _features)) {
      _featureChanges?.removeListener(_onFeaturesChanged);
      _features = features;
      _featureChanges = features is Listenable ? features as Listenable : null;
      _featureChanges?.addListener(_onFeaturesChanged);
      if (!_speechEnabled) _invalidate(notify: false).ignore();
    }
  }

  void _onFeaturesChanged() {
    if (!_speechEnabled) _invalidate().ignore();
    if (mounted && !_disposing) setState(() {});
  }

  void _redraw() {
    if (mounted && !_disposing) setState(() {});
  }

  /// Invalidate synchronously, before waiting for uninterruptible permissions.
  /// Only captured owned handles are released; shared facades are never stopped.
  Future<void> _invalidate({bool notify = true}) {
    _epoch++;
    _playing = false;
    _recording = false;
    _transcript = null;
    _status = null;
    final playback = _playback;
    final recognition = _recognition;
    _playback = null;
    _recognition = null;
    final drain = _retainCleanup([
      if (playback != null) playback.release(),
      if (recognition != null) recognition.release(),
    ]);
    if (notify) _redraw();
    return drain;
  }

  /// Every owned stop/release joins this barrier, including callbacks and
  /// failed starts. A native listening flag may clear before its operation
  /// finishes, so a later release alone cannot prove that cleanup has drained.
  Future<void> _retainCleanup(List<Future<void>> operations) {
    final drain = Future.wait<void>([?_cleanupBarrier, ...operations]);
    _cleanupBarrier = drain;
    return drain;
  }

  bool _current(
    int epoch, {
    SpeechPracticeSession? speech,
    VoiceSession? voice,
  }) {
    final valid =
        epoch == _epoch &&
        _accepts &&
        (speech == null ||
            (_speechEnabled &&
                identical(speech, _recognition) &&
                speech.isCurrent)) &&
        (voice == null || (identical(voice, _playback) && voice.isCurrent));
    if (!valid && epoch == _epoch) _invalidate().ignore();
    return valid;
  }

  @override
  void clearEphemeralState() {
    _retired = true;
    _invalidate().ignore();
    // Also releases an idle handle acquired by RouteVoiceSessionMixin.
    refreshRouteVoiceSession();
  }

  @override
  Future<void> onVoiceRouteCovered() => _invalidate(notify: false);

  @override
  Future<void> onVoiceAppBackgrounded() => _invalidate();

  Future<void> _listen() async {
    if (!_accepts) return;
    if (_playing) {
      await _invalidate().catchError((Object _) {});
      return;
    }
    final drain = _invalidate(notify: false);
    final epoch = _epoch;
    _playing = true;
    _redraw();
    try {
      await drain;
      if (!_current(epoch)) return;
      final session = routeVoiceSession;
      if (session == null) throw StateError('voice unavailable');
      _playback = session;
      await session.speakUntilCompleted(
        VoiceRequest.create(
          text: widget.text,
          language: 'en',
          voiceId: 'device-default',
          speed: 1,
          contentId: widget.identity,
          contentType: 'reviewed_sentence',
          mode: VoiceMode.practice,
        ),
      );
      if (!_current(epoch, voice: session)) return;
      _playing = false;
      _status = 'ฟังจบแล้ว จะลองพูดหรือไปข้อต่อไปก็ได้';
      _redraw();
    } on Object {
      if (!_current(epoch)) return;
      _playing = false;
      _status = 'ระบบอ่านออกเสียงไม่พร้อมใช้งาน ไปข้อต่อไปได้';
      _redraw();
    }
  }

  Future<void> _speak() async {
    if (!_accepts || !_speechEnabled) return;
    if (_recording) {
      final session = _recognition;
      _epoch++;
      _recording = false;
      _status = 'หยุดแล้ว ลองอีกครั้งหรือข้ามการพูดได้';
      _redraw();
      await _retainCleanup([
        if (session != null) session.stop(),
      ]).catchError((Object _) {});
      return;
    }
    final drain = _invalidate(notify: false);
    final epoch = _epoch;
    _attempted = true;
    _recording = true;
    _status = 'กำลังเตรียมไมโครโฟน…';
    _redraw();
    try {
      await drain;
      if (!_current(epoch) || !_speechEnabled) return;
      final service = _speech;
      if (service == null) throw StateError('speech unavailable');
      final session = service.acquireSession();
      _recognition = session;
      final started = await session.start(
        locale: 'en-US',
        onEvent: (event) {
          if (!_current(epoch, speech: session)) return;
          if (!event.isFinal) return;
          final text = event.transcript.trim();
          _finishSpeech(
            epoch,
            session,
            transcript: text.isEmpty ? null : text,
            status: text.isEmpty
                ? 'ยังไม่ได้ยินคำพูด ลองอีกครั้งหรือข้ามได้'
                : null,
          );
        },
        onFailure: (failure) {
          if (!_current(epoch, speech: session)) return;
          _finishSpeech(epoch, session, status: _failureMessage(failure));
        },
        onStatus: (status) {
          if (!_current(epoch, speech: session)) return;
          if (status == 'done' || status == 'notListening') {
            _finishSpeech(
              epoch,
              session,
              status: 'ยังไม่ได้ยินคำพูด ลองอีกครั้งหรือข้ามได้',
            );
          }
        },
      );
      if (!_current(epoch, speech: session)) return;
      if (!started) {
        _finishSpeech(
          epoch,
          session,
          status: 'ระบบรู้จำเสียงไม่พร้อมใช้งาน ไปข้อต่อไปได้',
        );
        return;
      }
      _status = 'พูดประโยคนี้ได้เลย…';
      _redraw();
    } on Object catch (error) {
      if (!_current(epoch)) return;
      _invalidate(notify: false).ignore();
      _status = error is SpeechPracticeException
          ? _failureMessage(error.code)
          : 'ระบบรู้จำเสียงไม่พร้อมใช้งาน ไปข้อต่อไปได้';
      _redraw();
    }
  }

  void _finishSpeech(
    int epoch,
    SpeechPracticeSession session, {
    String? transcript,
    String? status,
  }) {
    if (!_current(epoch, speech: session)) return;
    _epoch++;
    _recording = false;
    _transcript = transcript;
    _status = status;
    _retainCleanup([session.stop()]).ignore();
    _redraw();
  }

  String _failureMessage(SpeechFailureCode failure) => switch (failure) {
    SpeechFailureCode.permissionDenied ||
    SpeechFailureCode.permissionPermanentlyDenied =>
      'ยังไม่ได้รับสิทธิ์ใช้ไมโครโฟน ลองอีกครั้งหรือข้ามได้',
    SpeechFailureCode.noMatch => 'ยังไม่ได้ยินคำพูด ลองอีกครั้งหรือข้ามได้',
    SpeechFailureCode.cancelled => 'หยุดแล้ว ลองอีกครั้งหรือข้ามการพูดได้',
    _ => 'ระบบรู้จำเสียงไม่พร้อมใช้งาน ไปข้อต่อไปได้',
  };

  void _skip() {
    if (!_accepts) return;
    _invalidate().ignore();
    _attempted = true;
    _status = 'ข้ามการพูดแล้ว ไปข้อต่อไปได้';
    _redraw();
  }

  @override
  void dispose() {
    _disposing = true;
    _scope?.unregisterEphemeralState(this);
    _featureChanges?.removeListener(_onFeaturesChanged);
    _invalidate(notify: false).ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _accepts;
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ฟังและลองพูด',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'ฝึกเพิ่มเติมตามสมัครใจ ข้ามได้ ไม่บันทึกเสียงหรือผลการพูด และไม่มีคะแนน',
            ),
            const SizedBox(height: 12),
            Text(widget.text, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('sentence-practice-listen'),
                  style: buttonStyle,
                  onPressed: enabled && _voice != null ? _listen : null,
                  icon: Icon(_playing ? Icons.stop : Icons.volume_up_outlined),
                  label: Text(_playing ? 'หยุดเสียง' : 'ฟังประโยค'),
                ),
                OutlinedButton.icon(
                  key: const Key('sentence-practice-speak'),
                  style: buttonStyle,
                  onPressed: enabled && _speech != null && _speechEnabled
                      ? _speak
                      : null,
                  icon: Icon(_recording ? Icons.stop : Icons.mic_none),
                  label: Text(
                    _recording
                        ? 'หยุด'
                        : _attempted
                        ? 'ลองอีกครั้ง'
                        : 'ฝึกพูด',
                  ),
                ),
              ],
            ),
            if (_voice == null)
              const Text('ระบบอ่านออกเสียงไม่พร้อมใช้งาน ไปข้อต่อไปได้'),
            if (_speech == null || !_speechEnabled)
              const Text('ระบบรู้จำเสียงไม่พร้อมใช้งาน ข้ามการพูดได้'),
            if (_transcript != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text('ระบบได้ยินว่า… $_transcript'),
                ),
              ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(liveRegion: true, child: Text(_status!)),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('sentence-practice-skip'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: enabled ? _skip : null,
                child: const Text('ข้ามการพูด'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
