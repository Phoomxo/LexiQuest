import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../navigation/app_routes.dart';
import '../../../runtime/app_dependencies.dart';
import '../../identity/application/owner_generation.dart';
import '../../learning_packs/domain/personal_sets.dart';
import '../application/speaking_scenario_use_cases.dart';
import '../application/speaking_capture.dart';
import '../application/speech_practice_use_cases.dart';
import '../domain/speaking_scenario.dart';

class SpeakingScenarioScreen extends StatefulWidget {
  const SpeakingScenarioScreen({
    super.key,
    required this.useCases,
    required this.owner,
    required this.set,
    required this.speech,
  });
  final SpeakingScenarioUseCases useCases;
  final OwnerGenerationToken owner;
  final PersonalSetRevision set;
  final SpeechPracticeUseCases speech;
  @override
  State<SpeakingScenarioScreen> createState() => _SpeakingScenarioScreenState();
}

class _SpeakingScenarioScreenState extends State<SpeakingScenarioScreen>
    with WidgetsBindingObserver, RouteAware {
  final _text = TextEditingController();
  late final SpeakingCapture _capture;
  SpeakingIntent? _intent;
  bool _fallback = false, _retired = false;

  SpeakingScenarioTicket? _ticket;
  StreamSubscription<bool>? _watch;
  Listenable? _features;
  PageRoute<dynamic>? _route;
  int _epoch = 0, _index = 0;
  bool _busy = false, _editing = true;
  String? _error;
  ({
    String operation,
    String response,
    SpeakingScenarioTicket ticket,
    SpeakingInput input,
    bool confirmed,
    bool isFinal,
  })?
  _pending;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watch = widget.useCases.sets.watchOwnerCurrent(widget.owner).listen((
      current,
    ) {
      if (!current && mounted) setState(_retire);
    });
    _capture = SpeakingCapture(
      speech: widget.speech,
      requireCurrent: () async {
        if (_retired || _ticket == null || !widget.useCases.isAvailable()) {
          throw StateError('Speaking retired');
        }
        await widget.useCases.sets.ownerGeneration.requireCurrentAsync(
          widget.owner,
        );
      },
    )..addListener(_captureChanged);
  }

  void _captureChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
    final features = AppDependenciesScope.maybeOf(context)?.features;
    final changes = features is Listenable ? features as Listenable : null;
    if (!identical(changes, _features)) {
      _features?.removeListener(_featureChanged);
      _features = changes;
      _features?.addListener(_featureChanged);
    }
  }

  void _featureChanged() {
    if (!widget.useCases.isAvailable() && mounted) setState(_retire);
  }

  void _retire() {
    _retired = true;
    _epoch++;
    _capture.close().ignore();
    _ticket?.cancel();
    _ticket = null;
    _pending?.ticket.cancel();
    _pending = null;
    _text.clear();
    _busy = false;
    _error = 'Session closed. Return to your set to reopen saved results.';
  }

  @override
  void didPushNext() {
    if (mounted) setState(_retire);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) setState(_retire);
  }

  Future<void> _load() async {
    if (_retired) return;
    final epoch = ++_epoch;
    await _capture.cancel().catchError((Object _) {});
    if (!mounted || epoch != _epoch) return;
    _ticket?.cancel();
    _ticket = null;
    _text.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ticket = await widget.useCases.open(
        widget.owner,
        setId: widget.set.setId,
        setRevision: widget.set.revision,
        memberIndex: _index,
        activityId:
            'speaking:${widget.set.payloadHash}:$_index:${_intent!.name}',
        intent: _intent!,
      );
      if (!mounted || epoch != _epoch) {
        ticket.cancel();
        return;
      }
      setState(() {
        _ticket = ticket;
        _editing = ticket.results.isEmpty;
      });
    } on Object {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error =
              'This prompt or saved content is unavailable. Return to your set.',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final ticket = _ticket;
    if (ticket == null || _busy) return;
    final epoch = _epoch;
    _pending ??= (
      operation: _fallback
          ? const Uuid().v4()
          : (_capture.operationId ?? const Uuid().v4()),
      response: _fallback ? _text.text : (_capture.event?.transcript ?? ''),
      ticket: ticket,
      input: _fallback ? SpeakingInput.textFallback : SpeakingInput.speech,
      confirmed: !_fallback && _capture.confirmed,
      isFinal: _fallback || (_capture.event?.isFinal ?? false),
    );
    final pending = _pending!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.useCases.submit(
        pending.ticket,
        operationId: pending.operation,
        response: pending.response,
        input: pending.input,
        confirmed: pending.confirmed,
        isFinal: pending.isFinal,
      );
      if (!mounted || epoch != _epoch) {
        result.cancel();
        return;
      }
      setState(() {
        _ticket = result;
        _pending = null;
        _editing = false;
        _text.clear();
        _capture.cancel().ignore();
      });
    } on Object {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error =
              'Result not confirmed. Retry the same response or return to your set.',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _capture.removeListener(_captureChanged);
    _retire();
    _capture.dispose();
    _text.dispose();
    unawaited(_watch?.cancel());
    _features?.removeListener(_featureChanged);
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    final result = ticket == null || ticket.results.isEmpty
        ? null
        : ticket.results.last;
    return Scaffold(
      appBar: AppBar(title: const Text('Speak in a scenario')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Local lexical rubric · Meaning / Use / Grammar\nFeedback describes displayed words only. No pronunciation, SRS, rewards or proficiency score.',
              ),
              const Text(
                'Other valid sentences may be outside this limited rubric and receive no score.',
              ),
              if (_intent == null && !_retired) ...[
                const Text(
                  'Choose your intent. Assessment is personal practice, not a certified language test.',
                ),
                for (final intent in SpeakingIntent.values)
                  FilledButton(
                    onPressed: () {
                      setState(() => _intent = intent);
                      _load();
                    },
                    child: Text(
                      intent == SpeakingIntent.practice
                          ? 'Practice'
                          : 'Assessment',
                    ),
                  ),
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
              if (ticket != null) ...[
                Text(
                  '${_index + 1}/${widget.set.members.length} · ${ticket.target}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(ticket.prompt),
                if (_editing) ...[
                  Text(
                    _fallback
                        ? 'Text fallback · not an oral result'
                        : 'Spoken response · ${ticket.intent.name}',
                  ),
                  if (!_fallback) ...[
                    const Text(
                      'Your device recognizer may use a network service. Record one short sentence, then check the transcript.',
                    ),
                    if (_capture.failure != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          'Recognition: ${_capture.failure}. Check microphone settings, retry, or choose text fallback.',
                        ),
                      ),
                    FilledButton(
                      key: const Key('speaking-record'),
                      onPressed: _busy || _pending != null || _capture.listening
                          ? null
                          : _capture.start,
                      child: const Text('Record / repeat'),
                    ),
                    if (_capture.listening) ...[
                      const Text('Listening…'),
                      OutlinedButton(
                        onPressed: _capture.stop,
                        child: const Text('Finish recording'),
                      ),
                      OutlinedButton(
                        onPressed: _capture.cancel,
                        child: const Text('Cancel recording'),
                      ),
                    ],
                    if (_capture.event != null) ...[
                      Text('Transcript: ${_capture.event!.transcript}'),
                      Text(
                        'Recognizer: ${_capture.event!.engine}. Confidence: ${_capture.event!.recognitionConfidence?.toString() ?? "not supplied"}. This does not measure pronunciation.',
                      ),
                      OutlinedButton(
                        key: const Key('speaking-confirm'),
                        onPressed:
                            _capture.event!.isFinal &&
                                _capture.event!.transcript.trim().isNotEmpty &&
                                !_capture.confirmed
                            ? _capture.confirm
                            : null,
                        child: Text(
                          _capture.confirmed
                              ? 'Transcript confirmed'
                              : 'These are the words I said',
                        ),
                      ),
                    ],
                    TextButton(
                      onPressed: _busy || _pending != null
                          ? null
                          : () async {
                              await _capture.cancel();
                              if (mounted) setState(() => _fallback = true);
                            },
                      child: const Text('Use text fallback'),
                    ),
                  ] else ...[
                    TextField(
                      key: const Key('speaking-response'),
                      controller: _text,
                      enabled: !_busy && _pending == null,
                      maxLength: 1000,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Typed sentence (text fallback)',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy || _pending != null
                          ? null
                          : () {
                              _text.clear();
                              setState(() => _fallback = false);
                            },
                      child: const Text('Return to microphone'),
                    ),
                  ],
                  FilledButton(
                    key: const Key('speaking-submit'),
                    onPressed:
                        _busy ||
                            (!_fallback &&
                                !_capture.confirmed &&
                                _pending == null)
                        ? null
                        : _submit,
                    child: Text(
                      _pending == null ? 'Evaluate' : 'Retry same response',
                    ),
                  ),
                ] else if (result != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${result.status.name} · revision ${ticket.results.length}',
                    ),
                  ),
                  Text(
                    result.input == SpeakingInput.speech
                        ? '${result.confirmed ? "Confirmed" : "Unconfirmed"} spoken transcript · ${ticket.intent.name}'
                        : 'Text fallback · not an oral result · ${ticket.intent.name}',
                  ),
                  Text(result.response),
                  if (result.scores != null)
                    Text(
                      'Meaning ${result.scores![0]}/2 · Use ${result.scores![1]}/2 · Grammar ${result.scores![2]}/2',
                    ),
                  Text(result.explanation),
                  OutlinedButton(
                    key: const Key('speaking-revise'),
                    onPressed: _busy || ticket.results.length >= 6
                        ? null
                        : () {
                            setState(() {
                              _editing = true;
                              _text.clear();
                              _capture.cancel().ignore();
                            });
                          },
                    child: const Text('Try another turn (up to 6)'),
                  ),
                  ExpansionTile(
                    title: const Text('Saved revisions'),
                    children: [
                      for (final prior in ticket.results)
                        ListTile(
                          title: Text(prior.response),
                          subtitle: Text(
                            '${prior.input.name} · ${prior.status.name}',
                          ),
                        ),
                    ],
                  ),
                ],
                if (_index + 1 < widget.set.members.length)
                  TextButton(
                    onPressed: _busy || _pending != null
                        ? null
                        : () {
                            _index++;
                            _load();
                          },
                    child: const Text('Next word'),
                  ),
              ],
              TextButton(
                onPressed: () {
                  _retire();
                  Navigator.maybePop(context);
                },
                child: const Text('Finish'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
