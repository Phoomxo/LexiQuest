import 'dart:async';

import '../../consent/domain/research_consent.dart';
import '../domain/research_authority_snapshot.dart';
import '../domain/research_transport_contracts.dart';

final class ResearchTransportConsentCoordinator
    implements ResearchConsentRemoteDecisions {
  ResearchTransportConsentCoordinator({
    required this.repository,
    required this.gateway,
    required this.currentBinding,
    required this.invalidateAuthority,
    required this.generateRequestId,
    required this.version,
    this.bindingChanges,
  }) {
    if (version < 1) {
      throw ArgumentError('A positive consent version is required');
    }
    _lastBinding = currentBinding();
    _bindings = bindingChanges?.listen(
      (binding) {
        if (binding == _lastBinding || _disposed) return;
        _lastBinding = binding;
        invalidate();
      },
      onError: (Object _) => invalidate(),
      onDone: invalidate,
    );
  }

  @override
  final AuthoritativeResearchConsentRepository repository;
  final ResearchEnrollmentGateway gateway;
  final ResearchAuthorityBinding? Function() currentBinding;
  final void Function() invalidateAuthority;
  final String Function() generateRequestId;
  final int version;
  final Stream<ResearchAuthorityBinding?>? bindingChanges;
  StreamSubscription<ResearchAuthorityBinding?>? _bindings;
  ResearchAuthorityBinding? _lastBinding;
  final _requests = <(ResearchAuthorityBinding, bool), String>{};
  int _epoch = 0;
  bool _disposed = false;

  Future<ResearchEnrollmentContext> loadEnrollment({
    bool Function()? stillCurrent,
  }) async {
    final capture = _capture(stillCurrent: stillCurrent);
    return _enrollment(capture);
  }

  Future<ResearchConsentStatus> loadLocalStatus({
    bool Function()? stillCurrent,
  }) async {
    final capture = _capture(stillCurrent: stillCurrent);
    final result = await repository.load(
      ownerId: capture.binding.ownerId,
      version: version,
    );
    _requireCurrent(capture);
    return result;
  }

  @override
  Future<bool> accept(
    ResearchConsentStatus expected, {
    bool Function()? stillCurrent,
  }) async {
    invalidateAuthority();
    final capture = _capture(retireEarlier: true, stillCurrent: stillCurrent);
    if (expected.ownerId != capture.binding.ownerId ||
        expected.version != version ||
        expected.withdrawnAtUtc != null) {
      return false;
    }
    final context = await _enrollment(capture);
    final acknowledgement = await gateway.decideConsent(
      binding: capture.binding,
      enrollment: context,
      accepted: true,
      requestId: _requestId(capture.binding, true),
      stillCurrent: () => _current(capture),
    );
    _requireCurrent(capture);
    final mirrored = await repository.mirrorAcknowledgement(
      expected: expected,
      acknowledged: acknowledgement.status,
      authSubjectId: capture.binding.authSubjectId,
      stillCurrent: () => _current(capture),
    );
    _requireCurrent(capture);
    return mirrored && acknowledgement.accepted;
  }

  @override
  Future<bool> withdraw(
    ResearchConsentStatus expected,
    DateTime withdrawnAtUtc, {
    bool Function()? stillCurrent,
  }) async {
    invalidateAuthority();
    final capture = _capture(retireEarlier: true, stillCurrent: stillCurrent);
    if (expected.ownerId != capture.binding.ownerId ||
        expected.version != version) {
      return false;
    }
    ResearchEnrollmentContext? context;
    if (!expected.accepted && expected.withdrawnAtUtc == null) {
      context = await _enrollment(capture);
    }
    final persisted = await repository.withdrawLocally(
      expected: expected,
      withdrawnAtUtc: withdrawnAtUtc,
      authSubjectId: capture.binding.authSubjectId,
      stillCurrent: () => _current(capture),
    );
    _requireCurrent(capture);
    if (!persisted) return false;
    try {
      context ??= await _enrollment(capture);
      final local = await repository.load(
        ownerId: expected.ownerId,
        version: version,
      );
      _requireCurrent(capture);
      final acknowledgement = await gateway.decideConsent(
        binding: capture.binding,
        enrollment: context,
        accepted: false,
        requestId: _requestId(capture.binding, false),
        stillCurrent: () => _current(capture),
      );
      _requireCurrent(capture);
      if (acknowledgement.accepted || acknowledgement.withdrawnAtUtc == null) {
        throw const ResearchTransportException(
          ResearchTransportFailureCode.invalidResponse,
        );
      }
      return repository.mirrorAcknowledgement(
        expected: local,
        acknowledged: acknowledgement.status,
        authSubjectId: capture.binding.authSubjectId,
        stillCurrent: () => _current(capture),
      );
    } on Object {
      _requireCurrent(capture);
      throw const ResearchTransportException(
        ResearchTransportFailureCode.withdrawalPending,
      );
    }
  }

  Future<bool> reconcileBeforeRefresh() async {
    final local = await loadLocalStatus();
    if (local.withdrawnAtUtc != null) {
      await withdraw(local, local.withdrawnAtUtc!);
      return false;
    }
    return local.accepted;
  }

  void invalidate() {
    _epoch++;
    invalidateAuthority();
  }

  void retirePending() => _epoch++;

  void dispose() {
    _disposed = true;
    _epoch++;
    _requests.clear();
    unawaited(_bindings?.cancel());
    invalidateAuthority();
  }

  ({ResearchAuthorityBinding binding, int epoch, bool Function() stillCurrent})
  _capture({bool retireEarlier = false, bool Function()? stillCurrent}) {
    if (retireEarlier) _epoch++;
    final binding = currentBinding();
    if (_disposed || binding == null) {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.accountRequired,
      );
    }
    return (
      binding: binding,
      epoch: _epoch,
      stillCurrent: stillCurrent ?? () => true,
    );
  }

  bool _current(
    ({
      ResearchAuthorityBinding binding,
      int epoch,
      bool Function() stillCurrent,
    })
    capture,
  ) =>
      !_disposed &&
      _epoch == capture.epoch &&
      currentBinding() == capture.binding &&
      capture.stillCurrent();

  void _requireCurrent(
    ({
      ResearchAuthorityBinding binding,
      int epoch,
      bool Function() stillCurrent,
    })
    capture,
  ) {
    if (!_current(capture)) {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.ownerChanged,
      );
    }
  }

  Future<ResearchEnrollmentContext> _enrollment(
    ({
      ResearchAuthorityBinding binding,
      int epoch,
      bool Function() stillCurrent,
    })
    capture,
  ) async {
    _requireCurrent(capture);
    final value = await gateway.loadEnrollment(
      capture.binding,
      stillCurrent: () => _current(capture),
    );
    _requireCurrent(capture);
    if (value.ownerId != capture.binding.ownerId ||
        value.authSubjectId != capture.binding.authSubjectId ||
        value.consentVersion != version) {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.denied,
      );
    }
    return value;
  }

  String _requestId(ResearchAuthorityBinding binding, bool accepted) =>
      _requests.putIfAbsent((binding, accepted), generateRequestId);
}
