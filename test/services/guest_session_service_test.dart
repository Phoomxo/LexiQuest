import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

class _FakeAnonymousAuthGateway implements AnonymousAuthGateway {
  _FakeAnonymousAuthGateway({this.uid, this.error});

  final String? uid;
  final Object? error;

  @override
  Future<String?> signInAnonymously() async {
    final captured = error;
    if (captured != null) throw captured;
    return uid;
  }
}

void main() {
  group('FirebaseGuestSessionService.start', () {
    test('starts a guest session with the exact gateway uid', () async {
      final service = FirebaseGuestSessionService(
        _FakeAnonymousAuthGateway(uid: 'guest-uid-123'),
      );

      final result = await service.start();

      expect(
        result,
        isA<GuestSessionStarted>().having(
          (started) => started.uid,
          'uid',
          'guest-uid-123',
        ),
      );
    });

    for (final invalidUid in <String?>[null, '', '   ']) {
      test('maps invalid uid "$invalidUid" to unknown', () async {
        final service = FirebaseGuestSessionService(
          _FakeAnonymousAuthGateway(uid: invalidUid),
        );

        final result = await service.start();

        expect(
          result,
          isA<GuestSessionFailed>().having(
            (failed) => failed.reason,
            'reason',
            GuestSessionFailure.unknown,
          ),
        );
      });
    }

    test('maps operation-not-allowed to providerDisabled', () async {
      final service = FirebaseGuestSessionService(
        _FakeAnonymousAuthGateway(
          error: FirebaseAuthException(
            code: 'operation-not-allowed',
            message: 'Anonymous sign-in is disabled.',
          ),
        ),
      );

      final result = await service.start();

      expect(
        result,
        isA<GuestSessionFailed>().having(
          (failed) => failed.reason,
          'reason',
          GuestSessionFailure.providerDisabled,
        ),
      );
    });

    test('maps network-request-failed to network', () async {
      final service = FirebaseGuestSessionService(
        _FakeAnonymousAuthGateway(
          error: FirebaseAuthException(
            code: 'network-request-failed',
            message: 'Network unavailable.',
          ),
        ),
      );

      final result = await service.start();

      expect(
        result,
        isA<GuestSessionFailed>().having(
          (failed) => failed.reason,
          'reason',
          GuestSessionFailure.network,
        ),
      );
    });

    test('maps a missing Firebase app to firebaseUnavailable', () async {
      final service = FirebaseGuestSessionService(
        _FakeAnonymousAuthGateway(
          error: FirebaseException(
            plugin: 'core',
            code: 'no-app',
            message: 'No Firebase app.',
          ),
        ),
      );

      final result = await service.start();

      expect(
        result,
        isA<GuestSessionFailed>().having(
          (failed) => failed.reason,
          'reason',
          GuestSessionFailure.firebaseUnavailable,
        ),
      );
    });

    test('maps an unexpected exception to unknown', () async {
      final service = FirebaseGuestSessionService(
        _FakeAnonymousAuthGateway(error: StateError('unexpected failure')),
      );

      final result = await service.start();

      expect(
        result,
        isA<GuestSessionFailed>().having(
          (failed) => failed.reason,
          'reason',
          GuestSessionFailure.unknown,
        ),
      );
    });

    test('failure exposes only the enum and never provider messages', () async {
      const sentinel = 'SECRET_PROVIDER_RESPONSE_42';
      final service = FirebaseGuestSessionService(
        _FakeAnonymousAuthGateway(
          error: FirebaseAuthException(
            code: 'operation-not-allowed',
            message: sentinel,
          ),
        ),
      );

      final result = await service.start();
      final failed = result as GuestSessionFailed;

      expect(failed.reason, GuestSessionFailure.providerDisabled);
      expect(result.toString(), isNot(contains(sentinel)));
      expect(failed.reason.toString(), isNot(contains(sentinel)));
    });
  });

  group('OwnerBindingGuestSessionService', () {
    test(
      'starts the local guest without waiting for anonymous Firebase',
      () async {
        final entryState = _MemoryAppEntryStateStore();
        final service = OwnerBindingGuestSessionService(
          delegate: _PendingGuestSessionService(),
          localOwners: _FakeLocalOwnerRepository(),
          upgradeGuestOwner: UpgradeGuestOwner(_FakeOwnerUpgradeRepository()),
          entryState: entryState,
        );

        final result = await service.start().timeout(
          const Duration(milliseconds: 100),
        );

        expect(
          result,
          isA<GuestSessionStarted>().having(
            (started) => started.uid,
            'local owner id',
            'local-owner',
          ),
        );
        expect(entryState.mode, AppEntryMode.guest);
      },
    );

    test(
      'binds the active local owner in the background when online',
      () async {
        final upgrades = _FakeOwnerUpgradeRepository();
        final service = OwnerBindingGuestSessionService(
          delegate: FirebaseGuestSessionService(
            _FakeAnonymousAuthGateway(uid: 'anonymous-firebase-uid'),
          ),
          localOwners: _FakeLocalOwnerRepository(),
          upgradeGuestOwner: UpgradeGuestOwner(upgrades),
          entryState: _MemoryAppEntryStateStore(),
        );

        final result = await service.start();
        await upgrades.upgraded.future;

        expect(result, isA<GuestSessionStarted>());
        expect(upgrades.ownerId, 'local-owner');
        expect(upgrades.firebaseUid, 'anonymous-firebase-uid');
      },
    );

    test(
      'retries transient cloud binding without blocking local use',
      () async {
        final upgrades = _FakeOwnerUpgradeRepository();
        final delegate = _SequencedGuestSessionService(<GuestSessionResult>[
          const GuestSessionFailed(GuestSessionFailure.network),
          const GuestSessionStarted(uid: 'anonymous-after-reconnect'),
        ]);
        final delays = <Duration>[];
        final service = OwnerBindingGuestSessionService(
          delegate: delegate,
          localOwners: _FakeLocalOwnerRepository(),
          upgradeGuestOwner: UpgradeGuestOwner(upgrades),
          entryState: _MemoryAppEntryStateStore(),
          retryDelay: (delay) async {
            delays.add(delay);
          },
          maxCloudBindingAttempts: 2,
        );

        final result = await service.start();
        await upgrades.upgraded.future;

        expect(result, isA<GuestSessionStarted>());
        expect(delegate.startCalls, 2);
        expect(delays, const <Duration>[Duration(seconds: 15)]);
        expect(upgrades.firebaseUid, 'anonymous-after-reconnect');
      },
    );

    test(
      'default maxCloudBindingAttempts is 5 and caps transient failures',
      () async {
        // Regression guard for the lowered default (was 8 → now 5). Every
        // queued result is a transient network failure, so the service must
        // stop after exactly five attempts and record four 15-second backoffs.
        final delegate = _SequencedGuestSessionService(
          List<GuestSessionResult>.filled(
            5,
            const GuestSessionFailed(GuestSessionFailure.network),
          ),
        );
        final delays = <Duration>[];
        final service = OwnerBindingGuestSessionService(
          delegate: delegate,
          localOwners: _FakeLocalOwnerRepository(),
          upgradeGuestOwner: UpgradeGuestOwner(_FakeOwnerUpgradeRepository()),
          entryState: _MemoryAppEntryStateStore(),
          retryDelay: (delay) async {
            delays.add(delay);
          },
        );

        final result = await service.start();
        // Give the unawaited background binding loop room to exhaust retries.
        await Future<void>.delayed(Duration.zero);

        expect(result, isA<GuestSessionStarted>());
        expect(delegate.startCalls, 5);
        expect(delays, const <Duration>[
          Duration(seconds: 15),
          Duration(seconds: 15),
          Duration(seconds: 15),
          Duration(seconds: 15),
        ]);
      },
    );

    test(
      'stops retrying immediately on a permanent firebaseUnavailable failure',
      () async {
        // firebaseUnavailable is a configuration error (Firebase not
        // initialized), not a transient outage — retrying would only burn
        // ~75s of startup and mask the misconfiguration. The loop must stop
        // after exactly one attempt with no backoff.
        final delegate = _SequencedGuestSessionService(const [
          GuestSessionFailed(GuestSessionFailure.firebaseUnavailable),
        ]);
        final delays = <Duration>[];
        final service = OwnerBindingGuestSessionService(
          delegate: delegate,
          localOwners: _FakeLocalOwnerRepository(),
          upgradeGuestOwner: UpgradeGuestOwner(_FakeOwnerUpgradeRepository()),
          entryState: _MemoryAppEntryStateStore(),
          retryDelay: (delay) async {
            delays.add(delay);
          },
          maxCloudBindingAttempts: 5,
        );

        await service.start();
        await Future<void>.delayed(Duration.zero);

        expect(delegate.startCalls, 1);
        expect(delays, isEmpty);
      },
    );

    test(
      'retries on an unknown failure (Play Integrity cold-start can be transient)',
      () async {
        // `unknown` can surface on the first attempt while App Check / Play
        // Integrity is still minting a token on cold start; the prior field
        // session succeeded only because `unknown` was retried. So the loop
        // must keep retrying `unknown` up to the attempt cap, not hard-stop.
        final delegate = _SequencedGuestSessionService(
          List<GuestSessionResult>.filled(
            5,
            const GuestSessionFailed(GuestSessionFailure.unknown),
          ),
        );
        final delays = <Duration>[];
        final service = OwnerBindingGuestSessionService(
          delegate: delegate,
          localOwners: _FakeLocalOwnerRepository(),
          upgradeGuestOwner: UpgradeGuestOwner(_FakeOwnerUpgradeRepository()),
          entryState: _MemoryAppEntryStateStore(),
          retryDelay: (delay) async {
            delays.add(delay);
          },
        );

        await service.start();
        await Future<void>.delayed(Duration.zero);

        expect(delegate.startCalls, 5);
        expect(delays, const <Duration>[
          Duration(seconds: 15),
          Duration(seconds: 15),
          Duration(seconds: 15),
          Duration(seconds: 15),
        ]);
      },
    );

    test('fails closed when local ownership cannot be bound', () async {
      final service = OwnerBindingGuestSessionService(
        delegate: FirebaseGuestSessionService(
          _FakeAnonymousAuthGateway(uid: 'anonymous-firebase-uid'),
        ),
        localOwners: _FakeLocalOwnerRepository(error: StateError('db failed')),
        upgradeGuestOwner: UpgradeGuestOwner(_FakeOwnerUpgradeRepository()),
        entryState: _MemoryAppEntryStateStore(),
      );

      final result = await service.start();

      expect(
        result,
        isA<GuestSessionFailed>().having(
          (failed) => failed.reason,
          'reason',
          GuestSessionFailure.unknown,
        ),
      );
      expect(result.toString(), isNot(contains('db failed')));
    });

    test(
      'does not report guest success when the choice cannot persist',
      () async {
        final service = OwnerBindingGuestSessionService(
          delegate: _PendingGuestSessionService(),
          localOwners: _FakeLocalOwnerRepository(),
          upgradeGuestOwner: UpgradeGuestOwner(_FakeOwnerUpgradeRepository()),
          entryState: _MemoryAppEntryStateStore(
            markFailure: StateError('preferences unavailable'),
          ),
        );

        final result = await service.start();

        expect(result, isA<GuestSessionFailed>());
      },
    );

    test(
      'dispose cancels a pending provider bind and suppresses callbacks',
      () async {
        final delegate = _ControllableGuestSessionService();
        final upgrades = _FakeOwnerUpgradeRepository();
        var callbacks = 0;
        final service = OwnerBindingGuestSessionService(
          delegate: delegate,
          localOwners: _FakeLocalOwnerRepository(),
          upgradeGuestOwner: UpgradeGuestOwner(upgrades),
          entryState: _MemoryAppEntryStateStore(),
          onOwnerBound: () => callbacks += 1,
        );

        await service.start();
        await service.dispose().timeout(const Duration(milliseconds: 100));
        delegate.complete(
          const GuestSessionStarted(uid: 'late-anonymous-provider'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(delegate.startCalls, 1);
        expect(upgrades.upgradeCalls, 0);
        expect(callbacks, 0);
      },
    );

    test(
      'dispose cancels a pending retry and prevents remaining attempts',
      () async {
        final delayStarted = Completer<void>();
        final releaseDelay = Completer<void>();
        final delegate = _SequencedGuestSessionService(const [
          GuestSessionFailed(GuestSessionFailure.network),
          GuestSessionStarted(uid: 'must-not-bind'),
        ]);
        final upgrades = _FakeOwnerUpgradeRepository();
        var callbacks = 0;
        final service = OwnerBindingGuestSessionService(
          delegate: delegate,
          localOwners: _FakeLocalOwnerRepository(),
          upgradeGuestOwner: UpgradeGuestOwner(upgrades),
          entryState: _MemoryAppEntryStateStore(),
          retryDelay: (_) {
            delayStarted.complete();
            return releaseDelay.future;
          },
          maxCloudBindingAttempts: 2,
          onOwnerBound: () => callbacks += 1,
        );

        await service.start();
        await delayStarted.future;
        await service.dispose().timeout(const Duration(milliseconds: 100));
        releaseDelay.complete();
        await Future<void>.delayed(Duration.zero);

        expect(delegate.startCalls, 1);
        expect(upgrades.upgradeCalls, 0);
        expect(callbacks, 0);
      },
    );

    test(
      'dispose drains an in-flight upgrade and suppresses its callback',
      () async {
        final upgrades = _ControllableOwnerUpgradeRepository();
        var callbacks = 0;
        final service = OwnerBindingGuestSessionService(
          delegate: _SequencedGuestSessionService(const [
            GuestSessionStarted(uid: 'anonymous-in-flight'),
          ]),
          localOwners: _FakeLocalOwnerRepository(),
          upgradeGuestOwner: UpgradeGuestOwner(upgrades),
          entryState: _MemoryAppEntryStateStore(),
          onOwnerBound: () => callbacks += 1,
        );

        await service.start();
        await upgrades.started.future;
        var disposed = false;
        final disposing = service.dispose().then((_) => disposed = true);
        await Future<void>.delayed(Duration.zero);

        expect(disposed, isFalse);
        expect(callbacks, 0);

        upgrades.release.complete();
        await disposing;

        expect(disposed, isTrue);
        expect(callbacks, 0);
      },
    );
  });
}

final class _MemoryAppEntryStateStore implements AppEntryStateStore {
  _MemoryAppEntryStateStore({this.markFailure});

  final Object? markFailure;
  AppEntryMode mode = AppEntryMode.signedOut;

  @override
  Future<void> clear() async {
    mode = AppEntryMode.signedOut;
  }

  @override
  Future<void> markGuest() async {
    if (markFailure case final failure?) throw failure;
    mode = AppEntryMode.guest;
  }

  @override
  Future<AppEntryMode> read() async => mode;
}

final class _PendingGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() => Completer<GuestSessionResult>().future;
}

final class _ControllableGuestSessionService implements GuestSessionService {
  final Completer<GuestSessionResult> _result = Completer<GuestSessionResult>();
  int startCalls = 0;

  @override
  Future<GuestSessionResult> start() {
    startCalls += 1;
    return _result.future;
  }

  void complete(GuestSessionResult result) => _result.complete(result);
}

final class _SequencedGuestSessionService implements GuestSessionService {
  _SequencedGuestSessionService(this.results);

  final List<GuestSessionResult> results;
  int startCalls = 0;

  @override
  Future<GuestSessionResult> start() async {
    final index = startCalls++;
    return results[index];
  }
}

final class _FakeLocalOwnerRepository implements LocalOwnerRepository {
  _FakeLocalOwnerRepository({this.error});

  final Object? error;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) {
    throw UnimplementedError();
  }

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    final captured = error;
    if (captured != null) throw captured;
    return LocalOwner(
      id: 'local-owner',
      createdAtUtc: DateTime.utc(2026, 7, 30),
    );
  }
}

final class _FakeOwnerUpgradeRepository implements OwnerUpgradeRepository {
  String? ownerId;
  String? firebaseUid;
  int upgradeCalls = 0;
  final Completer<void> upgraded = Completer<void>();

  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() {
    throw UnimplementedError();
  }

  @override
  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  }) async {
    upgradeCalls += 1;
    ownerId = activeOwnerId;
    this.firebaseUid = firebaseUid;
    if (!upgraded.isCompleted) {
      upgraded.complete();
    }
    return OwnerUpgradeResult(
      targetOwnerId: activeOwnerId,
      mode: OwnerUpgradeMode.anonymousBound,
      conflictCount: 0,
    );
  }
}

final class _ControllableOwnerUpgradeRepository
    implements OwnerUpgradeRepository {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  }) async {
    started.complete();
    await release.future;
    return OwnerUpgradeResult(
      targetOwnerId: activeOwnerId,
      mode: OwnerUpgradeMode.anonymousBound,
      conflictCount: 0,
    );
  }

  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() {
    throw UnimplementedError();
  }

  @override
  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) {
    throw UnimplementedError();
  }
}
