import 'dart:async';

typedef MenuAction = FutureOr<void> Function();

/// Explicit application callbacks only; no arbitrary routes, scripts or fields.
final class MenuActionRegistry {
  MenuActionRegistry({required this.currentOwner});
  final String? Function() currentOwner;
  final _actions = <String, List<_Action>>{};
  final _receipts =
      <String, ({String id, int revision, Map<String, Object?> result})>{};
  int _revision = 0;
  int _sessionEpoch = 0;
  String? _owner;
  bool _busy = false;
  final _context =
      <
        Object,
        ({
          String id,
          String label,
          String owner,
          bool Function() available,
          String Function() value,
        })
      >{};

  void Function() registerContext({
    required String id,
    required String label,
    required bool Function() available,
    required String Function() value,
  }) {
    _refreshOwner();
    if (id.isEmpty || id.length > 160 || label.isEmpty || label.length > 200) {
      throw ArgumentError('Invalid context descriptor');
    }
    final key = Object();
    final owner = currentOwner();
    if (owner != null) {
      _context[key] = (
        id: id,
        label: label,
        owner: owner,
        available: available,
        value: value,
      );
    }
    return () => _context.remove(key);
  }

  void invalidateSession({bool preserveContext = false}) {
    _sessionEpoch++;
    _revision++;
    if (!preserveContext) _context.clear();
    _receipts.clear();
  }

  void _refreshOwner() {
    final next = currentOwner();
    if (_owner != next) {
      _owner = next;
      _sessionEpoch++;
      _revision++;
      _receipts.clear();
      _context.clear();
    }
  }

  void Function() register({
    required String id,
    required String label,
    required bool Function() available,
    required MenuAction invoke,
    bool dispatchOnly = false,
  }) {
    if (id.isEmpty || id.length > 160 || label.isEmpty || label.length > 200) {
      throw ArgumentError('Invalid action descriptor');
    }
    final action = _Action(label, available, invoke, dispatchOnly);
    _actions.putIfAbsent(id, () => []).add(action);
    _revision++;
    return () {
      if (_actions[id]?.remove(action) == true) {
        if (_actions[id]!.isEmpty) _actions.remove(id);
        _revision++;
      }
    };
  }

  Map<String, Object?> snapshot() {
    _refreshOwner();
    return {
      'revision': _revision,
      'recentActions': _receipts.values
          .map((r) => r.result)
          .toList()
          .reversed
          .take(8)
          .toList(),
      'context': [
        for (final entry in _context.values)
          if (_owner != null && entry.owner == _owner && entry.available())
            {
              'id': entry.id,
              'label': entry.label,
              'value': _bounded(entry.value()),
            },
      ],
      'actions': [
        if (_owner != null)
          for (final entry in _actions.entries)
            if (_available(entry.value) case final action?)
              {'id': entry.key, 'label': action.label},
      ],
    };
  }

  Future<Map<String, Object?>> execute({
    required String id,
    required String owner,
    required int revision,
    required String requestId,
  }) async {
    _refreshOwner();
    Map<String, Object?> receipt(String status) => {'status': status, 'id': id};
    if (owner != _owner || _owner == null) return receipt('stale');
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(requestId)) {
      return receipt('invalid');
    }
    final previous = _receipts[requestId];
    if (previous != null) {
      return previous.id == id && previous.revision == revision
          ? previous.result
          : receipt('conflict');
    }
    if (_busy) return receipt('busy');
    if (revision != _revision) return receipt('stale');
    final action = _available(_actions[id] ?? []);
    if (action == null) return receipt('unavailable');
    // Refuse a new session after its finite replay window fills; never evict a
    // receipt and accidentally execute a previously completed request again.
    if (_receipts.length >= 128) return receipt('session_limit');
    _busy = true;
    final epoch = _sessionEpoch;
    Map<String, Object?> result;
    try {
      final completion = action.invoke();
      if (action.dispatchOnly && completion is Future<void>) {
        // UI navigation futures often complete only when the opened page is
        // closed. Acknowledge dispatch, and preserve late errors for the next
        // status read/replay without blocking the learner's next command.
        unawaited(
          completion.then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              _refreshOwner();
              if (_sessionEpoch == epoch && _owner == owner) {
                _receipts[requestId] = (
                  id: id,
                  revision: revision,
                  result: Map.unmodifiable(receipt('failed')),
                );
              }
            },
          ),
        );
      } else {
        await completion;
      }
      result = receipt(currentOwner() == owner ? 'invoked' : 'stale');
    } on Object {
      result = receipt(
        'failed',
      ); // No private exception messages in model data.
    } finally {
      _busy = false;
    }
    _refreshOwner();
    if (_owner == owner && _sessionEpoch == epoch) {
      _receipts[requestId] = (
        id: id,
        revision: revision,
        result: Map.unmodifiable(result),
      );
    }
    return result;
  }

  _Action? _available(List<_Action> actions) {
    for (final action in actions.reversed) {
      if (action.available()) return action;
    }
    return null;
  }

  String _bounded(String value) =>
      value.length > 1000 ? value.substring(0, 1000) : value;
}

final class _Action {
  _Action(this.label, this.available, this.invoke, this.dispatchOnly);
  final String label;
  final bool Function() available;
  final MenuAction invoke;
  final bool dispatchOnly;
}
