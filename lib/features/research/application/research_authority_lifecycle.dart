import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/local_research_authority_cache.dart';
import '../domain/research_authority_snapshot.dart';

final class ResearchAuthorityLifecycle with WidgetsBindingObserver {
  ResearchAuthorityLifecycle({
    required Iterable<LocalResearchAuthorityCache> caches,
    required this.readGate,
    Iterable<Stream<Object?>> invalidations = const [],
    this.reconcileBeforeRefresh,
    this.onUnprovenInterval,
    bool? initiallyForeground,
  }) : caches = List.unmodifiable(caches),
       _foreground =
           initiallyForeground ??
           WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed {
    if (this.caches.length != 2 ||
        identical(this.caches[0], this.caches[1]) ||
        !identical(this.caches[0].ownerWrites, this.caches[1].ownerWrites) ||
        this.caches.any((cache) => !identical(cache.readGate, readGate))) {
      throw ArgumentError(
        'Research lifecycle requires both actual instrument caches',
      );
    }
    WidgetsBinding.instance.addObserver(this);
    for (final stream in invalidations) {
      _subscriptions.add(
        stream.listen(
          (_) => invalidate(),
          onError: (Object _) => invalidate(),
          onDone: invalidate,
        ),
      );
    }
    invalidate();
  }

  final List<LocalResearchAuthorityCache> caches;
  final ResearchAuthorityReadGate readGate;
  final Future<bool> Function()? reconcileBeforeRefresh;
  final void Function()? onUnprovenInterval;
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _foreground;
  bool _disposed = false;
  int _generation = 0;

  int get generation => _generation;

  void invalidate() {
    readGate.close();
    _generation++;
    for (final cache in caches) {
      if (_foreground && !_disposed) {
        cache.resume();
      } else {
        cache.suspend();
      }
    }
  }

  Future<bool> refresh({required bool Function() stillCurrent}) async {
    invalidate();
    final generation = _generation;
    bool current() =>
        !_disposed &&
        _foreground &&
        generation == _generation &&
        stillCurrent() &&
        _sameScopePair();
    try {
      if (!current()) return false;
      if (reconcileBeforeRefresh != null && !await reconcileBeforeRefresh!()) {
        return false;
      }
      if (!current()) return false;
      for (final cache in caches) {
        if (!await cache.refresh() || !current()) {
          invalidate();
          return false;
        }
      }
      if (!current() || caches.any((cache) => !cache.hasFreshSnapshot)) {
        invalidate();
        return false;
      }
      readGate.open(
        stillCurrent: () =>
            !_disposed &&
            _foreground &&
            generation == _generation &&
            _sameScopePair() &&
            caches.every((cache) => cache.hasFreshSnapshot),
      );
      return true;
    } on Object {
      invalidate();
      return false;
    }
  }

  bool _sameScopePair() {
    final first = caches.first.currentScope();
    final second = caches.last.currentScope();
    if (first == null || second == null) return false;
    final a = first.requirements;
    final b = second.requirements;
    return first.binding == second.binding &&
        first.protocolVersion == second.protocolVersion &&
        first.consentVersion == second.consentVersion &&
        a.assignmentId == b.assignmentId &&
        a.assignmentRevision == b.assignmentRevision &&
        a.protocolId == b.protocolId &&
        a.protocolRevision == b.protocolRevision &&
        a.instrumentId != b.instrumentId;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onUnprovenInterval?.call();
    _foreground = state == AppLifecycleState.resumed;
    invalidate();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    onUnprovenInterval?.call();
    invalidate();
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    for (final cache in caches) {
      cache.dispose();
    }
  }
}
