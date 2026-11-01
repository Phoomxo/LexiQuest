import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../data/local/app_database.dart';
import '../identity/data/drift_owner_write_coordinator.dart';
import 'application/billing_use_cases.dart';
import 'data/http_billing_repository.dart';
import 'data/play_billing_gateway.dart';
import 'domain/billing_contracts.dart';

final class BillingAuthIdentity {
  const BillingAuthIdentity({required this.uid, required this.isAnonymous});
  final String uid;
  final bool isAnonymous;
  @override
  bool operator ==(Object other) =>
      other is BillingAuthIdentity &&
      uid == other.uid &&
      isAnonymous == other.isAnonymous;
  @override
  int get hashCode => Object.hash(uid, isAnonymous);
}

final class DriftBillingAccountBinding {
  DriftBillingAccountBinding({
    required this.database,
    required this.currentIdentity,
    required Stream<void> authInvalidations,
  }) : _ownerWrites = DriftOwnerWriteCoordinator(
         database,
         nowUtc: () => DateTime.now().toUtc(),
       ) {
    _owners = database
        .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
        .listen(
          (_) => _changed(),
          onError: (Object _) => _observerUnavailable(),
          onDone: _observerUnavailable,
        );
    _flags = database
        .tableUpdates(TableUpdateQuery.onTable(database.runtimeFlags))
        .listen(
          (_) => _changed(),
          onError: (Object _) => _observerUnavailable(),
          onDone: _observerUnavailable,
        );
    _auth = authInvalidations.listen(
      (_) => _changed(),
      onError: (Object _) => _observerUnavailable(),
      onDone: _observerUnavailable,
    );
  }

  final AppDatabase database;
  final BillingAuthIdentity? Function() currentIdentity;
  final DriftOwnerWriteCoordinator _ownerWrites;
  final _changes = StreamController<BillingAccount?>.broadcast(sync: true);
  final _refreshes = <Future<void>>{};
  late final StreamSubscription<Object?> _owners;
  late final StreamSubscription<Object?> _flags;
  late final StreamSubscription<void> _auth;
  BillingAccount? _account;
  int _epoch = 0;
  bool _disposed = false;
  bool _observerRetired = false;

  BillingAccount? get currentAccount {
    final identity = currentIdentity();
    final account = _account;
    return !_disposed &&
            !_observerRetired &&
            account != null &&
            identity != null &&
            !identity.isAnonymous &&
            identity.uid == account.firebaseUid
        ? account
        : null;
  }

  Stream<BillingAccount?> get changes => _changes.stream;

  void _observerUnavailable() {
    _observerRetired = true;
    _retire();
  }

  void _retire() {
    if (_disposed) return;
    _epoch++;
    _account = null;
    _changes.add(null);
  }

  void _changed() {
    if (_disposed || _observerRetired) return;
    _retire();
    final task = _refresh(_epoch);
    _refreshes.add(task);
    unawaited(task.whenComplete(() => _refreshes.remove(task)));
  }

  Future<void> refresh() async {
    if (_disposed || _observerRetired) return;
    _retire();
    await _refresh(_epoch);
    while (_refreshes.isNotEmpty) {
      await Future.wait(_refreshes.toList());
    }
  }

  bool _current(int epoch, BillingAuthIdentity identity) =>
      !_disposed &&
      !_observerRetired &&
      epoch == _epoch &&
      identity == currentIdentity();

  Future<BillingAccount?> _read(int epoch) async {
    final identity = currentIdentity();
    if (identity == null ||
        identity.isAnonymous ||
        identity.uid.isEmpty ||
        !_current(epoch, identity)) {
      return null;
    }
    final owners = await database
        .customSelect(
          'SELECT id,firebase_uid,account_state FROM local_owners WHERE is_active=1 LIMIT 2',
        )
        .get();
    if (!_current(epoch, identity) || owners.length != 1) return null;
    final owner = owners.single.read<String>('id');
    if (owner.trim().isEmpty ||
        owner != owner.trim() ||
        owners.single.read<String>('account_state') != 'firebaseBound' ||
        owners.single.readNullable<String>('firebase_uid') != identity.uid) {
      return null;
    }
    return _ownerWrites.writeForActiveOwner(
      expectedOwnerId: owner,
      write: () async {
        if (!_current(epoch, identity)) return null;
        final current = await database
            .customSelect(
              'SELECT id,firebase_uid,account_state FROM local_owners WHERE is_active=1 LIMIT 2',
            )
            .get();
        if (!_current(epoch, identity) ||
            current.length != 1 ||
            current.single.read<String>('id') != owner ||
            current.single.read<String>('account_state') != 'firebaseBound' ||
            current.single.readNullable<String>('firebase_uid') !=
                identity.uid) {
          return null;
        }
        return BillingAccount(
          ownerId: owner,
          firebaseUid: identity.uid,
          isAnonymous: false,
        );
      },
    );
  }

  Future<void> _refresh(int epoch) async {
    try {
      final account = await _read(epoch);
      if (_disposed || epoch != _epoch) return;
      _account = account;
      _changes.add(account);
    } on Object {
      if (!_disposed && epoch == _epoch) {
        _account = null;
        _changes.add(null);
      }
    }
  }

  Future<void> requireCurrent(BillingAccount account) async {
    final epoch = _epoch;
    if (currentAccount != account) {
      throw const BillingException(BillingFailureCode.ownerChanged);
    }
    try {
      final observed = await _read(epoch);
      if (_disposed ||
          epoch != _epoch ||
          observed != account ||
          currentAccount != account) {
        throw const BillingException(BillingFailureCode.ownerChanged);
      }
    } on Object {
      _retire();
      throw const BillingException(BillingFailureCode.ownerChanged);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _retire();
    _disposed = true;
    await Future.wait([_owners.cancel(), _flags.cancel(), _auth.cancel()]);
    await Future.wait(_refreshes.toList());
    await _changes.close();
  }
}

final class BillingComposition {
  BillingComposition({
    required this.useCases,
    required Future<void> Function() dispose,
  }) : _disposeResources = dispose;
  final BillingUseCases useCases;
  final Future<void> Function() _disposeResources;
  Future<void>? _disposal;
  Future<void> dispose() => _disposal ??= _disposeResources();
}

Future<BillingComposition> createProductionBilling({
  required AppDatabase database,
  required Uri baseUri,
  required FirebaseAuth auth,
  http.Client? client,
}) async {
  final transport = client ?? http.Client();
  final clock = Stopwatch()..start();
  final binding = DriftBillingAccountBinding(
    database: database,
    currentIdentity: () {
      final user = auth.currentUser;
      return user == null
          ? null
          : BillingAuthIdentity(uid: user.uid, isAnonymous: user.isAnonymous);
    },
    authInvalidations: auth.authStateChanges().map<void>((_) {}),
  );
  try {
    await binding.refresh();
    final repository = HttpBillingRepository(
      client: transport,
      baseUri: baseUri,
      isCurrent: (account) => binding.currentAccount == account,
      loadIdToken: (account) async {
        await binding.requireCurrent(account);
        final user = auth.currentUser;
        if (user == null ||
            user.isAnonymous ||
            user.uid != account.firebaseUid) {
          return null;
        }
        final token = await user.getIdToken();
        await binding.requireCurrent(account);
        final current = auth.currentUser;
        return current?.uid == user.uid && current?.isAnonymous == false
            ? token
            : null;
      },
    );
    final useCases = BillingUseCases(
      repository: repository,
      store: PlayBillingGateway(),
      currentAccount: () => binding.currentAccount,
      accountChanges: binding.changes,
      generateRequestId: const Uuid().v4,
      elapsed: () => clock.elapsed,
    );
    return BillingComposition(
      useCases: useCases,
      dispose: () async {
        try {
          await binding.dispose();
        } finally {
          try {
            await useCases.dispose();
          } finally {
            transport.close();
            clock.stop();
          }
        }
      },
    );
  } on Object {
    await binding.dispose();
    transport.close();
    clock.stop();
    rethrow;
  }
}
