import 'dart:async';
import 'package:flutter/material.dart';
import '../../../navigation/app_routes.dart';
import '../../../runtime/app_dependencies.dart';
import '../../identity/application/owner_generation.dart';
import '../application/transfer_probe_use_cases.dart';

/// ORIGINAL DESIGN: a bounded spelling-recall probe, not a general use rubric.
class TransferProbeScreen extends StatefulWidget {
  const TransferProbeScreen({
    super.key,
    required this.useCases,
    required this.run,
  });
  final TransferProbeUseCases useCases;
  final TransferProbeRun run;
  @override
  State<TransferProbeScreen> createState() => _TransferProbeScreenState();
}

class _TransferProbeScreenState extends State<TransferProbeScreen>
    with WidgetsBindingObserver, RouteAware {
  late TransferProbeRun _run;
  final _answer = TextEditingController();
  StreamSubscription<bool>? _ownerWatch;
  Listenable? _features;
  PageRoute<dynamic>? _route;
  bool _busy = false, _retired = false, _ending = false;
  String? _error, _pendingAnswer;
  @override
  void initState() {
    super.initState();
    _run = widget.run;
    WidgetsBinding.instance.addObserver(this);
    _ownerWatch = widget.useCases.sets.watchOwnerCurrent(_run.owner).listen((
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
    final features = AppDependenciesScope.maybeOf(context)?.features;
    final changes = features is Listenable ? features as Listenable : null;
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
    _answer.clear();
    if (mounted) {
      setState(() {
        _retired = true;
        _pendingAnswer = null;
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
    _ownerWatch?.cancel();
    _features?.removeListener(_changed);
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _answer.dispose();
    widget.useCases.retire();
    super.dispose();
  }

  Future<void> _act(Future<TransferProbeRun> Function() action) async {
    if (_busy || _retired || _ending) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = await action();
      if (!mounted || _retired) return;
      setState(() {
        _run = next;
        _pendingAnswer = null;
      });
    } catch (_) {
      if (mounted && !_retired) {
        setState(
          () => _error =
              'Not confirmed. Retry the same action, or keep this saved practice and exit.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _retired || _ending) return;
    if (_pendingAnswer == null && _answer.text.trim().isEmpty) {
      setState(() => _error = 'Enter an English word before checking.');
      return;
    }
    _pendingAnswer ??= _answer.text;
    await _act(
      () => widget.useCases.answer(
        _run,
        answer: _pendingAnswer!,
        operationId: '${_run.session.id}:answer',
      ),
    );
  }

  Future<void> _abandon() async {
    if (_busy || _retired) return;
    setState(() {
      _busy = true;
      _ending = true;
    });
    try {
      await widget.useCases.abandon(_run.owner, _run.session.id);
      if (mounted && !_retired) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted && !_retired) {
        setState(
          () => _error = 'Could not end practice. Your saved work is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ลองจำในบริบทใหม่')),
    body: SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_retired)
                const Text(
                  'Practice paused. Exit and reopen to continue saved work.',
                )
              else ...[
                const Text(
                  'Timing unverified — personal practice using this device’s clock.',
                ),
                Text('Earlier learning: ${_run.offer.originUtc.toLocal()}'),
                if (_run.result == null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Recall the English word for this meaning in a new sentence.',
                  ),
                  Text(_run.session.questions.single.word.meaning),
                  Text(
                    _run.item.prompt,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_run.assisted)
                    Text(
                      'Assisted practice · First letter: ${_run.item.answer[0]}',
                    ),
                  TextField(
                    key: const ValueKey('probe-answer'),
                    controller: _answer,
                    enabled: !_busy && !_ending && _pendingAnswer == null,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'English word',
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) {
                      if (!_busy) _submit();
                    },
                  ),
                  FilledButton(
                    key: const ValueKey('probe-submit'),
                    onPressed: _busy || _ending ? null : _submit,
                    child: Text(
                      _pendingAnswer == null
                          ? 'Check answer'
                          : 'Retry same answer',
                    ),
                  ),
                  if (!_run.assisted && _pendingAnswer == null)
                    OutlinedButton(
                      onPressed: _busy || _ending
                          ? null
                          : () => _act(() => widget.useCases.hint(_run)),
                      child: const Text('Show a hint · assisted practice'),
                    ),
                  TextButton(
                    onPressed: _busy ? null : _abandon,
                    child: Text(
                      _ending
                          ? 'Retry ending practice'
                          : 'End without completing',
                    ),
                  ),
                ] else ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(_run.correct! ? 'Correct' : 'Keep practising'),
                  ),
                  Text(_run.item.sentence),
                  Text(
                    _run.assisted
                        ? 'Assisted spelling practice'
                        : 'Independent spelling recall',
                  ),
                  const Text(
                    'This checks one word in context, not general writing ability or proven long-term transfer.',
                  ),
                  Text(
                    'Saved learning result · ${_run.summary!.correctCount} correct',
                  ),
                ],
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                if (_busy)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Saving practice',
                  ),
              ],
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(
                  _run.summary == null
                      ? 'Keep saved and return to Review'
                      : 'Return to Review',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class TransferProbeReviewPanel extends StatefulWidget {
  const TransferProbeReviewPanel({
    super.key,
    required this.useCases,
    this.onReturned,
  });
  final TransferProbeUseCases useCases;
  final VoidCallback? onReturned;
  @override
  State<TransferProbeReviewPanel> createState() =>
      _TransferProbeReviewPanelState();
}

class _TransferProbeReviewPanelState extends State<TransferProbeReviewPanel> {
  OwnerGenerationToken? _owner;
  List<TransferProbeOffer> _offers = [];
  TransferProbeRun? _saved;
  String? _unavailableSession;
  bool _loading = true, _opening = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final owner = await widget.useCases.sets.begin();
      final recovery = await widget.useCases.learning.loadActivityRecovery(
        ownerId: owner.ownerId,
        activityType: transferProbeActivityType,
      );
      _unavailableSession = recovery?.session.state == 'active'
          ? recovery!.session.id
          : null;
      final saved = _unavailableSession == null
          ? null
          : await widget.useCases.resume(owner, _unavailableSession!);
      final offers = await widget.useCases.offers(owner);
      await widget.useCases.sets.ownerGeneration.requireCurrentAsync(owner);
      if (mounted) {
        setState(() {
          _owner = owner;
          _saved = saved;
          _offers = offers;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _offers = [];
          _saved = null;
          _error =
              'Practice unavailable: the original learning, reviewed content, or timing could not be verified.';
        });
      }
    }
  }

  Future<void> _open(TransferProbeOffer? offer) async {
    if (_opening || _owner == null) return;
    setState(() => _opening = true);
    try {
      final run = offer == null
          ? await widget.useCases.resume(_owner!, _saved!.session.id)
          : await widget.useCases.start(
              _owner!,
              offer: offer,
              operationId: 'probe:${offer.originAttemptId}:${offer.item.id}:v1',
            );
      if (!mounted) return;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'home/today/review/probe',
          builder: (_) =>
              TransferProbeScreen(useCases: widget.useCases, run: run),
        ),
      );
      await _load();
      if (mounted) widget.onReturned?.call();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open practice. Retry to reconcile saved work.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _endUnavailable() async {
    if (_opening || _unavailableSession == null) return;
    setState(() => _opening = true);
    try {
      final owner = await widget.useCases.sets.begin();
      await widget.useCases.abandon(owner, _unavailableSession!);
      _unavailableSession = null;
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Saved work remains unavailable; it has not been erased.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.useCases.isAvailable()) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ลองจำในบริบทใหม่',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null) ...[
              Text(_error!),
              OutlinedButton(
                onPressed: _opening ? null : _load,
                child: const Text('Check again'),
              ),
              if (_unavailableSession != null)
                TextButton(
                  onPressed: _opening ? null : _endUnavailable,
                  child: const Text('End unavailable saved practice'),
                ),
            ] else if (_saved != null)
              FilledButton(
                key: const ValueKey('probe-resume'),
                onPressed: _opening ? null : () => _open(null),
                child: const Text('Resume saved practice'),
              )
            else if (_offers.isEmpty)
              const Text(
                'No suitable new context yet. Complete context practice, allow at least 24 hours, and check again. Your due reviews remain available.',
              )
            else ...[
              const Text(
                'New contexts from earlier learning · Timing unverified',
              ),
              for (final (i, offer) in _offers.indexed)
                OutlinedButton(
                  key: ValueKey('probe-offer-$i'),
                  onPressed: _opening ? null : () => _open(offer),
                  child: Text('Try a new context ${i + 1}'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
