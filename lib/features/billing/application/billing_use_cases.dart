import 'dart:async';

import '../domain/billing_contracts.dart';

final class BillingUseCases {
  BillingUseCases({
    required this.repository,
    required this.store,
    required this.currentAccount,
    required this.accountChanges,
    required this.generateRequestId,
    required this.elapsed,
  }) {
    _account = currentAccount();
    _accounts = accountChanges.listen(
      (account) {
        _epoch++;
        _account = account;
        _catalog = null;
        _offers = const [];
        _snapshot = null;
        _pendingPurchase = null;
        _notBefore = null;
        _verifications.clear();
        _deferred.clear();
        _publish(
          BillingPhase.unavailable,
          failure: _registered(account)
              ? BillingFailureCode.ownerChanged
              : BillingFailureCode.accountRequired,
        );
      },
      onError: (Object _) => _invalidate(),
      onDone: _invalidate,
    );
    _purchases = store.purchases.listen(
      (purchases) {
        final account = _account;
        if (!_registered(account) || _disposed) return;
        final capture = _Capture(account!, _epoch);
        for (final purchase in purchases) {
          if (_catalog == null) {
            if (_deferred.length < 32) {
              _deferred[purchase.storeIdentity] = (capture, purchase);
            }
          } else {
            unawaited(
              _enqueue(
                capture,
                () => _processPurchase(capture, purchase),
              ).catchError((Object _) {}),
            );
          }
        }
      },
      onError: (Object _) => _publish(
        BillingPhase.failed,
        failure: BillingFailureCode.unavailable,
      ),
    );
  }
  final BillingRepository repository;
  final BillingStoreGateway store;
  final BillingAccount? Function() currentAccount;
  final Stream<BillingAccount?> accountChanges;
  final String Function() generateRequestId;
  final Duration Function() elapsed;

  final _changes = StreamController<BillingView>.broadcast(sync: true);
  late final StreamSubscription<BillingAccount?> _accounts;
  late final StreamSubscription<List<BillingPurchase>> _purchases;
  final _verifications = <String, _Verification>{};
  final _deferred = <String, (_Capture, BillingPurchase)>{};
  Future<void> _work = Future.value();
  BillingView _view = BillingView(phase: BillingPhase.unavailable);
  BillingAccount? _account;
  BillingCatalog? _catalog;
  List<BillingOffer> _offers = const [];
  BillingSnapshot? _snapshot;
  String? _pendingPurchase;
  Duration? _receivedAt;
  Duration? _notBefore;
  Timer? _leaseTimer;
  int _epoch = 0;
  bool _disposed = false;

  BillingView get view => _view;
  Stream<BillingView> get changes => _changes.stream;

  bool hasAccess(String entitlement, {required String ownerId}) {
    final account = _account;
    final snapshot = _snapshot;
    final receivedAt = _receivedAt;
    if (_disposed ||
        !_registered(account) ||
        currentAccount() != account ||
        account!.ownerId != ownerId ||
        snapshot == null ||
        receivedAt == null) {
      return false;
    }
    final delta = elapsed() - receivedAt;
    if (delta.isNegative || delta > const Duration(minutes: 5)) return false;
    final now = snapshot.serverTimeUtc.add(delta);
    return snapshot.grants.any(
      (grant) =>
          grant.entitlement == entitlement &&
          !grant.checkedAtUtc.isAfter(now) &&
          now.difference(grant.checkedAtUtc) <= const Duration(minutes: 5) &&
          grant.expiresAtUtc.isAfter(now),
    );
  }

  Future<void> load() {
    final capture = _capture();
    return _enqueue(capture, () async {
      _catalog = null;
      _offers = const [];
      _publish(BillingPhase.loading);
      final catalog = await repository.loadCatalog(
        capture.account,
        stillCurrent: () => _isCurrent(capture),
      );
      _requireCurrent(capture);
      if (!await store.isAvailable()) {
        throw const BillingException(BillingFailureCode.unavailable);
      }
      _requireCurrent(capture);
      final offers = await store.loadOffers(catalog);
      _requireCurrent(capture);
      final snapshot = await repository.loadEntitlements(
        capture.account,
        stillCurrent: () => _isCurrent(capture),
      );
      _requireCurrent(capture);
      _catalog = catalog;
      _offers = List.unmodifiable(
        offers.where(
          (offer) => catalog.products.any(
            (product) =>
                product.productId == offer.productId &&
                product.basePlanId == offer.basePlanId,
          ),
        ),
      );
      _accept(snapshot);
      for (final deferred in _deferred.values.toList()) {
        if (_isCurrent(deferred.$1)) {
          await _processPurchase(deferred.$1, deferred.$2);
        }
      }
      _deferred.clear();
    });
  }

  Future<void> buy(BillingOffer offer, {bool Function()? stillCurrent}) {
    final capture = _capture(stillCurrent: stillCurrent);
    return _enqueue(capture, () async {
      final catalog = _catalog;
      if (catalog == null ||
          !_offers.any((value) => identical(value, offer)) ||
          !catalog.products.any(
            (product) =>
                product.productId == offer.productId &&
                product.basePlanId == offer.basePlanId,
          )) {
        throw const BillingException(BillingFailureCode.unavailable);
      }
      if (_pendingPurchase != null) {
        throw const BillingException(BillingFailureCode.pending);
      }
      _pendingPurchase = offer.offerKey;
      _publish(BillingPhase.launching);
      _requireCurrent(capture);
      final launched = await store.buy(
        offer,
        accountIdentifier: catalog.accountIdentifier,
      );
      _requireCurrent(capture);
      if (!launched) _pendingPurchase = null;
      _publish(
        launched ? BillingPhase.pending : BillingPhase.ready,
        failure: launched ? null : BillingFailureCode.cancelled,
      );
    });
  }

  Future<void> restore({bool Function()? stillCurrent}) {
    final capture = _capture(stillCurrent: stillCurrent);
    return _enqueue(capture, () async {
      final catalog = _catalog;
      if (catalog == null) {
        throw const BillingException(BillingFailureCode.unavailable);
      }
      _publish(BillingPhase.restoring);
      _requireCurrent(capture);
      for (final verification in _verifications.values) {
        verification.complete = false;
      }
      await store.restore(accountIdentifier: catalog.accountIdentifier);
      _requireCurrent(capture);
      for (final verification in _verifications.values.toList()) {
        await _verify(capture, verification);
      }
      final snapshot = await repository.loadEntitlements(
        capture.account,
        stillCurrent: () => _isCurrent(capture),
      );
      _requireCurrent(capture);
      _accept(snapshot);
    });
  }

  Future<void> retryVerification() {
    final capture = _capture();
    return _enqueue(capture, () async {
      final pending = _verifications.values
          .where((value) => !value.complete)
          .toList();
      if (pending.isEmpty) {
        throw const BillingException(BillingFailureCode.verificationRequired);
      }
      for (final verification in pending) {
        _requireCurrent(capture);
        await _verify(capture, verification);
      }
    });
  }

  Future<void> _processPurchase(
    _Capture capture,
    BillingPurchase purchase,
  ) async {
    _requireCurrent(capture);
    final catalog = _catalog;
    if (catalog == null ||
        !catalog.products.any(
          (product) => product.productId == purchase.productId,
        )) {
      return;
    }
    if (purchase.accountIdentifier != null &&
        purchase.accountIdentifier != catalog.accountIdentifier) {
      return;
    }
    switch (purchase.status) {
      case BillingPurchaseStatus.pending:
        if (purchase.accountIdentifier == null && _pendingPurchase == null) {
          return;
        }
        _pendingPurchase = purchase.storeIdentity;
        _publish(BillingPhase.pending);
      case BillingPurchaseStatus.cancelled:
        _pendingPurchase = null;
        _publish(BillingPhase.ready, failure: BillingFailureCode.cancelled);
      case BillingPurchaseStatus.failed:
        _pendingPurchase = null;
        _publish(BillingPhase.failed, failure: BillingFailureCode.unavailable);
      case BillingPurchaseStatus.purchased:
      case BillingPurchaseStatus.restored:
        final token = purchase.purchaseToken;
        if (token == null ||
            token.isEmpty ||
            token.length > 4096 ||
            purchase.accountIdentifier != catalog.accountIdentifier) {
          throw const BillingException(BillingFailureCode.purchaseDenied);
        }
        final verification = _verifications.putIfAbsent(
          purchase.storeIdentity,
          () => _Verification(
            purchase,
            BillingVerification(
              purchaseToken: token,
              requestId: generateRequestId(),
            ),
          ),
        );
        if (verification.command.purchaseToken != token) {
          throw const BillingException(BillingFailureCode.purchaseDenied);
        }
        if (!verification.complete) await _verify(capture, verification);
    }
  }

  Future<void> _verify(_Capture capture, _Verification verification) async {
    _publish(BillingPhase.verifying);
    _requireCurrent(capture);
    final snapshot = await repository.verify(
      capture.account,
      verification.command,
      stillCurrent: () => _isCurrent(capture),
    );
    _requireCurrent(capture);
    _accept(snapshot);
    if (snapshot.acknowledgementPending) {
      _publish(_view.phase, failure: BillingFailureCode.verificationRequired);
      return;
    }
    if (verification.purchase.pendingCompletion) {
      _requireCurrent(capture);
      await store.complete(verification.purchase);
      _requireCurrent(capture);
    }
    verification.complete = true;
    _pendingPurchase = null;
    _publish(_active(snapshot) ? BillingPhase.active : BillingPhase.ready);
  }

  void _accept(BillingSnapshot snapshot) {
    _snapshot = snapshot;
    _receivedAt = elapsed();
    _leaseTimer?.cancel();
    final epoch = _epoch;
    var remaining = Duration.zero;
    for (final grant in snapshot.grants) {
      final freshness =
          const Duration(minutes: 5) -
          snapshot.serverTimeUtc.difference(grant.checkedAtUtc);
      final expiry = grant.expiresAtUtc.difference(snapshot.serverTimeUtc);
      final valid = freshness < expiry ? freshness : expiry;
      if (valid > remaining) remaining = valid;
    }
    if (remaining > Duration.zero) {
      _leaseTimer = Timer(remaining, () {
        if (!_disposed && epoch == _epoch) {
          _publish(
            BillingPhase.ready,
            failure: BillingFailureCode.verificationRequired,
          );
        }
      });
    }
    _publish(_active(snapshot) ? BillingPhase.active : BillingPhase.ready);
  }

  bool _active(BillingSnapshot snapshot) => snapshot.grants.any(
    (grant) =>
        grant.expiresAtUtc.isAfter(snapshot.serverTimeUtc) &&
        !grant.checkedAtUtc.isAfter(snapshot.serverTimeUtc) &&
        snapshot.serverTimeUtc.difference(grant.checkedAtUtc) <=
            const Duration(minutes: 5),
  );

  _Capture _capture({bool Function()? stillCurrent}) {
    if (stillCurrent != null && !stillCurrent()) {
      throw const BillingException(BillingFailureCode.ownerChanged);
    }
    final account = currentAccount();
    if (_disposed || !_registered(account)) {
      _publish(
        BillingPhase.unavailable,
        failure: BillingFailureCode.accountRequired,
      );
      throw const BillingException(BillingFailureCode.accountRequired);
    }
    if (account != _account) {
      _invalidate();
      throw const BillingException(BillingFailureCode.ownerChanged);
    }
    return _Capture(account!, _epoch, stillCurrent);
  }

  bool _registered(BillingAccount? account) =>
      account != null &&
      !account.isAnonymous &&
      account.ownerId.isNotEmpty &&
      account.firebaseUid.isNotEmpty;
  bool _isCurrent(_Capture capture) =>
      !_disposed &&
      capture.epoch == _epoch &&
      capture.account == _account &&
      (capture.stillCurrent?.call() ?? true) &&
      capture.account == currentAccount();
  void _requireCurrent(_Capture capture) {
    if (!_isCurrent(capture)) {
      throw const BillingException(BillingFailureCode.ownerChanged);
    }
  }

  Future<void> _enqueue(_Capture capture, Future<void> Function() run) {
    final operation = _work.then((_) async {
      _requireCurrent(capture);
      try {
        final deadline = _notBefore;
        if (deadline != null && elapsed() < deadline) {
          throw BillingException(
            BillingFailureCode.retryLater,
            retryAfter: deadline - elapsed(),
          );
        }
        await run();
      } on BillingException catch (error) {
        if (_isCurrent(capture)) {
          final delay = error.retryAfter;
          if (delay != null) _notBefore = elapsed() + delay;
        }
        if (_isCurrent(capture)) {
          _publish(BillingPhase.failed, failure: error.code);
        }
        rethrow;
      } on Object {
        if (_isCurrent(capture)) {
          _publish(
            BillingPhase.failed,
            failure: BillingFailureCode.unavailable,
          );
        }
        throw const BillingException(BillingFailureCode.unavailable);
      }
    });
    _work = operation.catchError((Object _) {});
    return operation;
  }

  void _invalidate() {
    if (_disposed) return;
    _epoch++;
    _account = currentAccount();
    _catalog = null;
    _offers = const [];
    _snapshot = null;
    _pendingPurchase = null;
    _notBefore = null;
    _leaseTimer?.cancel();
    _deferred.clear();
    _verifications.clear();
    _publish(
      BillingPhase.unavailable,
      failure: BillingFailureCode.ownerChanged,
    );
  }

  void _publish(BillingPhase phase, {BillingFailureCode? failure}) {
    if (_disposed) return;
    _view = BillingView(
      phase: phase,
      account: _account,
      catalog: _catalog,
      offers: _offers,
      snapshot: _snapshot,
      failure: failure,
      verificationPending: _verifications.values.any(
        (value) => !value.complete,
      ),
    );
    _changes.add(_view);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _leaseTimer?.cancel();
    _epoch++;
    _snapshot = null;
    _verifications.clear();
    _deferred.clear();
    await _accounts.cancel();
    await _purchases.cancel();
    await _changes.close();
    await store.dispose();
  }
}

final class _Capture {
  const _Capture(this.account, this.epoch, [this.stillCurrent]);
  final BillingAccount account;
  final int epoch;
  final bool Function()? stillCurrent;
}

final class _Verification {
  _Verification(this.purchase, this.command);
  final BillingPurchase purchase;
  final BillingVerification command;
  bool complete = false;
}
