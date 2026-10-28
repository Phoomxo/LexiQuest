import 'dart:async';

import '../../progress/domain/progress_models.dart';
import '../domain/gemini_contracts.dart';

typedef LoadProgressSnapshot = Future<ProgressSnapshot> Function();
typedef GeminiUtcNow = DateTime Function();

final class GeminiTutorUseCases implements GeminiTutorController {
  GeminiTutorUseCases({
    required this.store,
    required this.gateway,
    required this.nowUtc,
    this.loadProgress,
  });

  final GeminiSettingsStore store;
  final GeminiGateway gateway;
  final GeminiUtcNow nowUtc;
  final LoadProgressSnapshot? loadProgress;
  final Set<GeminiCancellation> _activeCancellations = {};
  final Set<Future<Object?>> _activeOperations = {};
  final _transitionGate = _AsyncSerialGate();
  bool _disposed = false;

  @override
  Future<GeminiSettingsStatus> loadSettings() {
    _checkNotDisposed();
    return _transitionGate.run(_loadSettingsUnlocked);
  }

  Future<GeminiSettingsStatus> _loadSettingsUnlocked() async {
    final values = await Future.wait<Object?>([
      store.readKey(),
      store.readProviderConsent(),
      store.readLearningSummaryConsent(),
    ]);
    final key = values[0] as String?;
    final providerConsent = values[1] as bool;
    return GeminiSettingsStatus(
      hasKey: key != null && key.trim().isNotEmpty,
      providerConsent: providerConsent,
      shareLearningSummary: providerConsent && values[2] as bool,
    );
  }

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    GeminiCancellation? cancellation,
  }) {
    _checkNotDisposed();
    if (!providerConsent) {
      throw const GeminiException(GeminiFailureCode.consentRequired);
    }
    final effectiveCancellation = cancellation ?? GeminiCancellation();
    return _track(
      effectiveCancellation,
      _transitionGate.run(
        () => _configure(
          key: key,
          shareLearningSummary: shareLearningSummary,
          cancellation: effectiveCancellation,
        ),
      ),
    );
  }

  Future<void> _configure({
    required String key,
    required bool shareLearningSummary,
    required GeminiCancellation cancellation,
  }) async {
    await gateway.validateKey(key, cancellation: cancellation);
    await store.writeProviderConsent(true);
    await store.writeLearningSummaryConsent(shareLearningSummary);
    await store.writeKey(key.trim());
  }

  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) async {
    _checkNotDisposed();
    final effectiveSummaryConsent = providerConsent && shareLearningSummary;
    final transition = _transitionGate.run(() async {
      await store.writeProviderConsent(providerConsent);
      await store.writeLearningSummaryConsent(effectiveSummaryConsent);
    });
    if (!providerConsent) {
      await _cancelActiveOperations();
    }
    await transition;
  }

  @override
  Future<void> removeKey() async {
    _checkNotDisposed();
    final transition = _transitionGate.run(() async {
      await store.deleteKey();
      await store.writeProviderConsent(false);
      await store.writeLearningSummaryConsent(false);
    });
    await _cancelActiveOperations();
    await transition;
  }

  @override
  Future<GeminiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    GeminiCancellation? cancellation,
  }) {
    _checkNotDisposed();
    final effectiveCancellation = cancellation ?? GeminiCancellation();
    return _track(
      effectiveCancellation,
      _transitionGate.run(
        () => _reply(
          scenario: scenario,
          learnerMessage: learnerMessage,
          cancellation: effectiveCancellation,
        ),
      ),
    );
  }

  Future<GeminiTutorReply> _reply({
    required String scenario,
    required String learnerMessage,
    required GeminiCancellation cancellation,
  }) async {
    final settings = await _loadSettingsUnlocked();
    if (!settings.providerConsent) {
      throw const GeminiException(GeminiFailureCode.consentRequired);
    }
    final key = await store.readKey();
    if (key == null || key.trim().isEmpty) {
      throw const GeminiException(GeminiFailureCode.missingKey);
    }
    String? summary;
    if (settings.shareLearningSummary && loadProgress != null) {
      summary = _progressSummary(await loadProgress!());
    }
    final text = await gateway.generateTutorReply(
      key: key,
      scenario: scenario,
      learnerMessage: learnerMessage,
      learningSummary: summary,
      cancellation: cancellation,
    );
    final generatedAtUtc = nowUtc();
    if (!generatedAtUtc.isUtc) {
      throw ArgumentError.value(generatedAtUtc, 'nowUtc', 'must return UTC');
    }
    return GeminiTutorReply(
      text: text,
      model: gateway.model,
      generatedAtUtc: generatedAtUtc,
    );
  }

  String _progressSummary(ProgressSnapshot progress) {
    final accuracy = progress.accuracy == null
        ? 'none'
        : '${(progress.accuracy! * 100).round()}%';
    final weaknesses = progress.weaknesses
        .take(3)
        .map(
          (item) =>
              '${item.spelling}:${(item.errorRate * 100).round()}%'
              '(n=${item.sampleSize})',
        )
        .join(',');
    return 'answers=${progress.sampleSize};accuracy=$accuracy;'
        'due=${progress.dueReviewCount};mastered=${progress.masteredWordCount};'
        'weaknesses=${weaknesses.isEmpty ? 'none' : weaknesses}';
  }

  Future<T> _track<T>(GeminiCancellation cancellation, Future<T> operation) {
    _activeCancellations.add(cancellation);
    late Future<T> tracked;
    tracked = operation.whenComplete(() {
      _activeCancellations.remove(cancellation);
      _activeOperations.remove(tracked);
    });
    _activeOperations.add(tracked);
    return tracked;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _cancelActiveOperations();
  }

  Future<void> _cancelActiveOperations() async {
    for (final cancellation in _activeCancellations.toList()) {
      cancellation.cancel();
    }
    final active = _activeOperations.toList(growable: false);
    if (active.isNotEmpty) {
      await Future.wait(
        active.map(
          (operation) => operation.then<void>((_) {}, onError: (_) {}),
        ),
      );
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw const GeminiException(GeminiFailureCode.cancelled);
    }
  }
}

final class _AsyncSerialGate {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        release.complete();
      }
    }();
  }
}
