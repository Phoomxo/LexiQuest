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
    required this.readScope,
    this.verifyScope,
    this.loadProgress,
  }) {
    _observedScope = _currentScope();
  }

  final GeminiSettingsStore store;
  final GeminiGateway gateway;
  final GeminiUtcNow nowUtc;
  final LoadProgressSnapshot? loadProgress;
  final GeminiScope? Function() readScope;
  final Future<GeminiScope?> Function()? verifyScope;
  final _invalidations = StreamController<int>.broadcast(sync: true);
  GeminiConfiguration? _activation;
  GeminiCancellation? _activationCancellation;
  GeminiScope? _observedScope;
  int _epoch = 0;
  bool _replying = false;
  bool _verificationUnavailable = false;
  int _mutations = 0;
  bool _notifying = false;
  @override
  GeminiScope? get scope => _currentScope();
  @override
  int get epoch => _epoch;
  @override
  Stream<int> get invalidations => _invalidations.stream;

  void invalidateScope() {
    if (_disposed) return;
    _observedScope = _currentScope();
    _epoch += 1;
    _activation = null;
    _activationCancellation = null;
    _cancelActiveNow();
    _notifyInvalidation(_epoch);
  }

  void _notifyInvalidation(int epoch) {
    if (_disposed) return;
    if (_notifying) {
      scheduleMicrotask(() => _notifyInvalidation(epoch));
    } else {
      _notifying = true;
      try {
        _invalidations.add(epoch);
      } finally {
        _notifying = false;
      }
    }
  }

  final Set<GeminiCancellation> _activeCancellations = {};
  final Set<Future<Object?>> _activeOperations = {};
  final _transitionGate = _AsyncSerialGate();
  bool _disposed = false;

  @override
  Future<GeminiSettingsStatus> loadSettings() => _run((admission) async {
    final configuration = await _after(admission, store.read(admission.scope));
    return _effective(configuration).status;
  }, serial: true);

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    GeminiCancellation? cancellation,
  }) {
    if (!providerConsent) {
      return Future.error(
        const GeminiException(GeminiFailureCode.consentRequired),
      );
    }
    _cancelActiveNow();
    return _run(
      (admission) async {
        await _after(
          admission,
          gateway.validateKey(key, cancellation: admission.cancellation),
        );
        await _persist(
          admission,
          GeminiConfiguration(
            key: key.trim(),
            providerConsent: true,
            shareLearningSummary: shareLearningSummary,
          ),
        );
        _activation = GeminiConfiguration(
          key: key.trim(),
          providerConsent: true,
          shareLearningSummary: shareLearningSummary,
        );
        _activationCancellation = admission.cancellation;
      },
      cancellation: cancellation,
      serial: true,
      mutation: true,
    );
  }

  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) {
    if (!providerConsent) return _revoke(remove: false);
    _cancelActiveNow();
    return _run(
      (admission) async {
        final previous = await _after(admission, store.read(admission.scope));
        _check(admission);
        if (previous.key?.trim().isNotEmpty != true) {
          throw const GeminiException(GeminiFailureCode.missingKey);
        }
        _activation = GeminiConfiguration(
          key: previous.key,
          providerConsent: true,
          shareLearningSummary: shareLearningSummary,
        );
        _activationCancellation = admission.cancellation;
      },
      serial: true,
      mutation: true,
    );
  }

  @override
  Future<void> removeKey() => _revoke(remove: true);

  Future<void> _revoke({required bool remove}) {
    try {
      final original = _admit(null);
      invalidateScope();
      return _run(
        (admission) async {
          final previous = await _after(admission, store.read(admission.scope));
          await _persist(
            admission,
            GeminiConfiguration(key: remove ? null : previous.key),
          );
        },
        serial: true,
        mutation: true,
        admittedScope: original.scope,
        admittedEpoch: original.epoch + 1,
      );
    } on GeminiException catch (error) {
      return Future.error(error);
    }
  }

  @override
  Future<GeminiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    GeminiTutorMode mode = GeminiTutorMode.guided,
    GeminiCancellation? cancellation,
  }) {
    if (_mutations > 0) {
      return Future.error(
        const GeminiException(GeminiFailureCode.consentRequired),
      );
    }
    if (_replying) {
      return Future.error(const GeminiException(GeminiFailureCode.cancelled));
    }
    _replying = true;
    return _run(
      (admission) => _reply(
        admission,
        scenario: scenario,
        learnerMessage: learnerMessage,
        mode: mode,
      ),
      cancellation: cancellation,
    ).whenComplete(() => _replying = false);
  }

  Future<GeminiTutorReply> _reply(
    _Admission admission, {
    required String scenario,
    required String learnerMessage,
    required GeminiTutorMode mode,
  }) async {
    final settings = _effective(
      await _after(admission, store.read(admission.scope)),
    );
    if (!settings.providerConsent) {
      throw const GeminiException(GeminiFailureCode.consentRequired);
    }
    final key = settings.key;
    if (key == null || key.trim().isEmpty) {
      throw const GeminiException(GeminiFailureCode.missingKey);
    }
    String? summary;
    if (settings.shareLearningSummary && loadProgress != null) {
      _check(admission);
      summary = _progressSummary(await _after(admission, loadProgress!()));
    }
    await _verify(admission);
    _check(admission);
    final text = await _after(
      admission,
      gateway.generateTutorReply(
        key: key,
        scenario: scenario,
        learnerMessage: learnerMessage,
        mode: mode,
        learningSummary: summary,
        cancellation: admission.cancellation,
      ),
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

  GeminiConfiguration _effective(GeminiConfiguration stored) {
    final activation = _activation;
    return GeminiConfiguration(
      key: stored.key,
      providerConsent:
          activation?.key == stored.key &&
          _activationCancellation?.isCancelled == false &&
          activation?.providerConsent == true,
      shareLearningSummary: activation?.shareLearningSummary == true,
    );
  }

  Future<void> _persist(
    _Admission admission,
    GeminiConfiguration configuration,
  ) async {
    await _verify(admission);
    _check(admission);
    admission.writeAttempted = true;
    await _after(admission, store.write(admission.scope, configuration));
  }

  _Admission _admit(GeminiCancellation? cancellation) {
    _checkNotDisposed();
    final scope = _currentScope();
    if (_observedScope != scope) {
      invalidateScope();
      throw const GeminiException(GeminiFailureCode.cancelled);
    }
    if (scope == null || scope.ownerId.trim().isEmpty) {
      throw const GeminiException(GeminiFailureCode.cancelled);
    }
    final admission = _Admission(
      scope,
      _epoch,
      cancellation ?? GeminiCancellation(),
    );
    _check(admission);
    return admission;
  }

  void _check(_Admission admission) {
    _checkNotDisposed();
    final scope = _currentScope();
    if (scope != _observedScope) invalidateScope();
    if (admission.epoch != _epoch ||
        scope != admission.scope ||
        admission.cancellation.isCancelled) {
      throw const GeminiException(GeminiFailureCode.cancelled);
    }
  }

  Future<void> _verify(_Admission admission) async {
    _check(admission);
    if (verifyScope != null) {
      GeminiScope? verified;
      try {
        verified = await verifyScope!();
      } on Object {
        _failVerification();
        throw const GeminiException(GeminiFailureCode.cancelled);
      }
      _check(admission);
      if (verified != admission.scope) {
        _failVerification();
        throw const GeminiException(GeminiFailureCode.cancelled);
      }
      _verificationUnavailable = false;
    }
    // Drain invalidations queued by the asynchronous owner/auth snapshot.
    await Future<void>.value();
    _check(admission);
  }

  void _failVerification() {
    if (_verificationUnavailable) return;
    _verificationUnavailable = true;
    invalidateScope();
  }

  GeminiScope? _currentScope() {
    try {
      return readScope();
    } on Object {
      return null;
    }
  }

  Future<T> _after<T>(_Admission admission, Future<T> operation) async {
    final result = await operation;
    await _verify(admission);
    _check(admission);
    return result;
  }

  Future<T> _run<T>(
    Future<T> Function(_Admission) action, {
    GeminiCancellation? cancellation,
    bool serial = false,
    bool mutation = false,
    GeminiScope? admittedScope,
    int? admittedEpoch,
  }) {
    try {
      final admission = _admit(cancellation);
      if (admittedScope != null && admittedScope != admission.scope) {
        throw const GeminiException(GeminiFailureCode.cancelled);
      }
      if (admittedEpoch != null && admittedEpoch != admission.epoch) {
        throw const GeminiException(GeminiFailureCode.cancelled);
      }
      if (mutation) _mutations += 1;
      Future<T> execute() async {
        try {
          await _verify(admission);
          _check(admission);
          final result = await action(admission);
          _check(admission);
          return result;
        } on Object {
          if (mutation) {
            _activation = null;
            _activationCancellation = null;
          }
          if (mutation && admission.writeAttempted) {
            await store.write(admission.scope, const GeminiConfiguration());
          }
          rethrow;
        }
      }

      final operation = serial ? _transitionGate.run(execute) : execute();
      return _track(admission.cancellation, operation).whenComplete(() {
        if (mutation) _mutations -= 1;
      });
    } on GeminiException catch (error) {
      return Future.error(error);
    }
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
    await _invalidations.close();
  }

  Future<void> _cancelActiveOperations() async {
    _cancelActiveNow();
    final active = _activeOperations.toList(growable: false);
    if (active.isNotEmpty) {
      await Future.wait(
        active.map(
          (operation) => operation.then<void>((_) {}, onError: (_) {}),
        ),
      );
    }
  }

  void _cancelActiveNow() {
    for (final cancellation in _activeCancellations.toList()) {
      cancellation.cancel();
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw const GeminiException(GeminiFailureCode.cancelled);
    }
  }
}

final class _Admission {
  _Admission(this.scope, this.epoch, this.cancellation);
  final GeminiScope scope;
  final int epoch;
  final GeminiCancellation cancellation;
  bool writeAttempted = false;
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
