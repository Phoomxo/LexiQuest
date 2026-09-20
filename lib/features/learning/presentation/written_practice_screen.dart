import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../navigation/app_routes.dart';
import '../../../runtime/app_dependencies.dart';
import '../../identity/application/owner_generation.dart';
import '../../learning_packs/domain/personal_sets.dart';
import '../application/written_practice_use_cases.dart';

class WrittenPracticeScreen extends StatefulWidget {
  const WrittenPracticeScreen({
    super.key,
    required this.useCases,
    required this.owner,
    required this.set,
  });
  final WrittenPracticeUseCases useCases;
  final OwnerGenerationToken owner;
  final PersonalSetRevision set;
  @override
  State<WrittenPracticeScreen> createState() => _WrittenPracticeScreenState();
}

class _WrittenPracticeScreenState extends State<WrittenPracticeScreen>
    with WidgetsBindingObserver, RouteAware {
  final _text = TextEditingController();
  WrittenPracticeTicket? _ticket;
  StreamSubscription<bool>? _watch;
  Listenable? _features;
  PageRoute<dynamic>? _route;
  int _epoch = 0, _index = 0;
  bool _busy = false, _editing = true;
  String? _error;
  ({String operation, String response, WrittenPracticeTicket ticket})? _pending;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watch = widget.useCases.sets.watchOwnerCurrent(widget.owner).listen((
      current,
    ) {
      if (!current && mounted) setState(_retire);
    });
    _load();
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
    _epoch++;
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
    final epoch = ++_epoch;
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
        activityId: 'written:${widget.set.payloadHash}:$_index',
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
      operation: const Uuid().v4(),
      response: _text.text,
      ticket: ticket,
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
    _retire();
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
      appBar: AppBar(title: const Text('Use the word')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Local reviewed rubric · Meaning / Use / Form\nScores describe this sentence only. No SRS, rewards or proficiency score.',
              ),
              const Text(
                'Other valid sentences may be outside this limited rubric and receive no score.',
              ),
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
                  TextField(
                    key: const Key('written-response'),
                    controller: _text,
                    enabled: !_busy && _pending == null,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Your sentence',
                    ),
                  ),
                  FilledButton(
                    key: const Key('written-submit'),
                    onPressed: _busy ? null : _submit,
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
                  Text(result.response),
                  if (result.scores != null)
                    Text(
                      'Meaning ${result.scores![0]}/2 · Use ${result.scores![1]}/2 · Form ${result.scores![2]}/2',
                    ),
                  Text(result.explanation),
                  for (final span in result.spans)
                    Text(
                      '“${result.response.substring(span.start, span.end)}” — ${span.explanation}',
                    ),
                  OutlinedButton(
                    key: const Key('written-revise'),
                    onPressed: _busy || ticket.results.length >= 20
                        ? null
                        : () {
                            setState(() {
                              _editing = true;
                              _text.text = result.response;
                            });
                          },
                    child: const Text('Revise sentence'),
                  ),
                  ExpansionTile(
                    title: const Text('Saved revisions'),
                    children: [
                      for (final prior in ticket.results)
                        ListTile(
                          title: Text(prior.response),
                          subtitle: Text(prior.status.name),
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
