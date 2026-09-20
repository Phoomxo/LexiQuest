import 'dart:async';
import 'package:flutter/material.dart';
import '../../../navigation/app_routes.dart';
import '../../../runtime/app_dependencies.dart';
import '../../learning/domain/learning_models.dart';
import '../application/dialogue_mission_use_cases.dart';

class DialogueMissionScreen extends StatefulWidget {
  const DialogueMissionScreen({
    super.key,
    required this.useCases,
    required this.run,
    this.resultBuilder,
  });
  final DialogueMissionUseCases useCases;
  final DialogueRun run;
  final Widget Function(BuildContext, LearningSessionSummary)? resultBuilder;
  @override
  State<DialogueMissionScreen> createState() => _DialogueMissionScreenState();
}

class _DialogueMissionScreenState extends State<DialogueMissionScreen>
    with WidgetsBindingObserver, RouteAware {
  late DialogueRun _run;
  StreamSubscription<bool>? _watch;
  Listenable? _features;
  PageRoute<dynamic>? _route;
  bool _busy = false, _retired = false, _consequence = false;
  String? _error;
  final Stopwatch _choiceClock = Stopwatch()..start();
  int? _pendingResponseMs;
  bool _ending = false;
  ({String node, String choice, String operation})? _pending;
  @override
  void initState() {
    super.initState();
    _run = widget.run;
    WidgetsBinding.instance.addObserver(this);
    _consequence = _run.decisions.isNotEmpty && _run.summary == null;
    _watch = widget.useCases.sets.watchOwnerCurrent(_run.owner).listen((
      current,
    ) {
      if (!current) _retire();
    });
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
    final f = AppDependenciesScope.maybeOf(context)?.features;
    final changes = f is Listenable ? f as Listenable : null;
    if (!identical(changes, _features)) {
      _features?.removeListener(_changed);
      _features = changes;
      _features?.addListener(_changed);
    }
    if (!widget.useCases.isAvailable()) _retired = true;
  }

  void _changed() {
    if (!widget.useCases.isAvailable()) _retire();
  }

  void _retire() {
    if (_retired) return;
    widget.useCases.retire();
    if (mounted) {
      setState(() {
        _retired = true;
        _pending = null;
        _error = null;
      });
    }
  }

  @override
  void didPushNext() => _retire();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _retire();
  }

  @override
  void dispose() {
    _watch?.cancel();
    _features?.removeListener(_changed);
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    widget.useCases.retire();
    super.dispose();
  }

  Future<void> _choose(String choice) async {
    if (_busy || _retired) return;
    _pending ??= (
      node: _run.node.id,
      choice: choice,
      operation: '${_run.session.id}:decision:${_run.decisions.length + 1}',
    );
    _pendingResponseMs ??= _choiceClock.elapsedMilliseconds;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pending = _pending!;
      final next = await widget.useCases.choose(
        _run,
        nodeId: pending.node,
        choiceId: pending.choice,
        operationId: pending.operation,
        responseTimeMs: _pendingResponseMs!,
      );
      if (!mounted || _retired) return;
      setState(() {
        _run = next;
        _pending = null;
        _pendingResponseMs = null;
        _consequence = true;
      });
    } catch (_) {
      if (mounted && !_retired) {
        setState(
          () => _error =
              'Choice not confirmed. Retry the same choice to reconcile.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    if (_busy || _retired) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await widget.useCases.complete(_run);
      if (!mounted || _retired) return;
      setState(() => _run = done);
    } catch (_) {
      if (mounted && !_retired) {
        setState(
          () =>
              _error = 'Result not confirmed. Retry to reopen the same result.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _abandon() async {
    if (_busy || _retired) return;
    setState(() {
      _busy = true;
      _ending = true;
      _error = null;
    });
    try {
      await widget.useCases.abandon(_run.owner, _run.session.id);
      if (mounted && !_retired) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted && !_retired) {
        setState(
          () => _error =
              'Could not end this mission. Saved choices remain unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_retired && _run.summary != null && widget.resultBuilder != null) {
      return widget.resultBuilder!(context, _run.summary!);
    }
    final last = _run.decisions.isEmpty ? null : _run.decisions.last;
    final decision = last == null
        ? null
        : _run.mission
              .node(last['node'] as String)
              .choices
              .singleWhere((c) => c.id == last['choice']);
    return Scaffold(
      appBar: AppBar(title: const Text('Dialogue mission')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_retired)
              const Text(
                'Mission paused. Saved choices are preserved. Exit and reopen to continue.',
              )
            else ...[
              Text(
                _run.mission.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Choices saved: ${_run.decisions.length} / ${_run.mission.maximumTurns}. You can save and exit at any time.',
              ),
              if (_consequence && decision != null) ...[
                Semantics(liveRegion: true, child: Text(decision.consequence)),
                Text(
                  last!['assisted'] == true
                      ? 'Assisted repair — original choice retained.'
                      : 'Recognition choice — not independent recall.',
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _consequence = false;
                          _choiceClock.reset();
                        }),
                  child: const Text('Continue'),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Text(_run.node.scene),
                if (!_run.node.terminal) ...[
                  Text(_run.node.choices.first.objective),
                  Text(
                    _run.node.assisted
                        ? 'Assisted repair'
                        : 'Choose the word that fits',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _run.node.prompt,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final choice in _run.node.choices)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton(
                        key: ValueKey('dialogue-choice-${choice.id}'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: _busy || _pending != null || _ending
                            ? null
                            : () => _choose(choice.id),
                        child: Text(choice.text),
                      ),
                    ),
                ] else if (_run.summary == null)
                  FilledButton(
                    onPressed: _busy ? null : _complete,
                    child: const Text('Finish mission'),
                  )
                else
                  Text(
                    'Completed: ${_run.summary!.correctCount} correct, ${_run.summary!.wrongCount} to review. Results come from the saved learning session.',
                  ),
              ],
              if (_error != null) ...[
                Semantics(liveRegion: true, child: Text(_error!)),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : (_ending
                            ? _abandon
                            : _pending != null
                            ? () => _choose(_pending!.choice)
                            : _complete),
                  child: const Text('Retry same operation'),
                ),
              ],
              if (_busy)
                Semantics(
                  label: 'Saving choice',
                  child: LinearProgressIndicator(),
                ),
              if (_run.summary == null)
                TextButton(
                  onPressed: _busy ? null : _abandon,
                  child: const Text('End mission without completing'),
                ),
            ],
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Save and exit'),
            ),
          ],
        ),
      ),
    );
  }
}
