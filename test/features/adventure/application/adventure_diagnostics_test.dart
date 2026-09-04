import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_diagnostics.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_session_plan.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/offline_content/application/offline_content_manager.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_state.dart';

void main() {
  test('exposes only closed reason codes with saturating counters', () {
    final diagnostics = AdventureDiagnostics(maxCountPerCode: 2);
    const codes = <AdventureDiagnosticReasonCode>[
      AdventureDiagnosticReasonCode.entryFallbackCatalogUnavailable,
      AdventureDiagnosticReasonCode.compositionUnresolvedContent,
      AdventureDiagnosticReasonCode.evidenceRetry,
      AdventureDiagnosticReasonCode.projectionRetry,
      AdventureDiagnosticReasonCode.assetChecksumMismatch,
    ];

    for (final code in codes) {
      diagnostics.record(code);
    }
    diagnostics
      ..record(AdventureDiagnosticReasonCode.assetChecksumMismatch)
      ..record(AdventureDiagnosticReasonCode.assetChecksumMismatch);

    expect(diagnostics.snapshot().toJson(), <String, Object>{
      'schemaVersion': 1,
      'counters': <String, int>{
        'entryFallbackCatalogUnavailable': 1,
        'compositionUnresolvedContent': 1,
        'evidenceRetry': 1,
        'projectionRetry': 1,
        'assetChecksumMismatch': 2,
      },
    });
  });

  test('rejects raw payloads, story text, and direct identifiers', () {
    const forbiddenFields = <String>[
      'answer',
      'answerPayload',
      'response',
      'researchResponse',
      'story',
      'storyText',
      'ownerId',
      'entryAttemptId',
      'sessionId',
      'evidenceId',
    ];
    for (final field in forbiddenFields) {
      expect(
        () => AdventureDiagnosticSnapshot.decode(<String, Object?>{
          'schemaVersion': 1,
          'counters': const <String, int>{'evidenceRetry': 1},
          field: 'private-value-must-not-be-echoed',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'redacted message',
            isNot(contains('private-value-must-not-be-echoed')),
          ),
        ),
      );
    }

    expect(
      () => AdventureDiagnosticSnapshot.decode(<String, Object?>{
        'schemaVersion': 1,
        'counters': const <String, int>{'unknownReason': 1},
      }),
      throwsFormatException,
    );
    expect(
      () => AdventureDiagnosticSnapshot.decode(<String, Object?>{
        'schemaVersion': 1,
        'counters': const <String, int>{'evidenceRetry': 1000001},
      }),
      throwsFormatException,
    );
  });

  test('maps existing bounded domain failures without accepting payloads', () {
    final diagnostics = AdventureDiagnostics();

    for (final destination in AdventureEntryDestination.values) {
      diagnostics.recordEntry(destination);
    }
    for (final reason in AdventureFallbackReason.values) {
      diagnostics.recordEntryFallback(reason);
    }
    for (final reason in AdventureSessionPlanFailure.values) {
      diagnostics.recordCompositionFailure(reason);
    }
    diagnostics
      ..recordEvidenceRetry()
      ..recordEvidenceRetry(exhausted: true)
      ..recordProjectionRetry()
      ..recordProjectionRetry(exhausted: true);
    for (final reason in OfflineContentFailureCode.values) {
      diagnostics.recordAssetFailure(reason);
    }

    final counters = diagnostics.snapshot().toJson()['counters'];
    expect(counters, isA<Map<String, int>>());
    expect(counters, containsPair('entryAdventure', 1));
    expect(counters, containsPair('entryStandard', 1));
    expect(counters, containsPair('entryLearn', 1));
    expect(counters, containsPair('entryFallbackDependencyUnavailable', 1));
    expect(counters, isNot(contains('entryFallbackNone')));
    expect(counters, containsPair('compositionOwnerMismatch', 1));
    expect(counters, containsPair('compositionStaleSource', 1));
    expect(counters, containsPair('evidenceRetryExhausted', 1));
    expect(counters, containsPair('projectionRetryExhausted', 1));
    expect(counters, containsPair('assetMissingArtifact', 1));
    expect(counters, containsPair('assetInterrupted', 1));
    expect(counters, containsPair('assetInvalidState', 1));
  });

  test(
    'corrupt repeated verifies quarantine once and never retry-loop',
    () async {
      final manager = _OfflineManager(
        state: _offlineState(OfflineContentStatus.verified),
        verifyError: const OfflineContentFailure(
          OfflineContentFailureCode.checksumMismatch,
        ),
      );
      final diagnostics = AdventureDiagnostics();
      final operations = AdventureCatalogRecoveryOperations(
        manager: manager,
        diagnostics: diagnostics,
        delay: (_) async {},
      );

      final first = operations.verify(_identity);
      final concurrent = operations.verify(_identity);
      final results = await Future.wait(
        <Future<AdventureCatalogRecoveryResult>>[first, concurrent],
      );
      final repeated = await operations.verify(_identity);

      expect(
        results.map((result) => result.status),
        everyElement(AdventureCatalogRecoveryStatus.quarantined),
      );
      expect(repeated.status, AdventureCatalogRecoveryStatus.quarantined);
      expect(manager.verifyCalls, 1);
      expect(manager.catalogCalls, 0);
      expect(
        diagnostics.snapshot().counters,
        <AdventureDiagnosticReasonCode, int>{
          AdventureDiagnosticReasonCode.assetChecksumMismatch: 1,
        },
      );
    },
  );

  test('repair uses at most three attempts with bounded backoff', () async {
    final manager = _OfflineManager(
      state: _offlineState(
        OfflineContentStatus.interrupted,
        failureCode: OfflineContentFailureCode.interrupted,
      ),
      repairOutcomes: <Object?>[
        TimeoutException('network flap'),
        const OfflineContentFailure(OfflineContentFailureCode.interrupted),
        null,
      ],
    );
    final delays = <Duration>[];
    final diagnostics = AdventureDiagnostics();
    final operations = AdventureCatalogRecoveryOperations(
      manager: manager,
      diagnostics: diagnostics,
      maxAttempts: 3,
      baseBackoff: const Duration(milliseconds: 10),
      delay: (duration) async => delays.add(duration),
    );

    final result = await operations.repair(_identity);

    expect(result.status, AdventureCatalogRecoveryStatus.repaired);
    expect(result.attempts, 3);
    expect(manager.repairCalls, 3);
    expect(delays, const <Duration>[
      Duration(milliseconds: 10),
      Duration(milliseconds: 20),
    ]);
    expect(
      diagnostics.snapshot().counters,
      <AdventureDiagnosticReasonCode, int>{
        AdventureDiagnosticReasonCode.assetInterrupted: 2,
      },
    );
  });

  test('verify retries transient I/O within the same bounded policy', () async {
    final manager = _OfflineManager(
      state: _offlineState(OfflineContentStatus.verified),
      verifyOutcomes: <Object?>[TimeoutException('temporary I/O'), null],
    );
    final delays = <Duration>[];
    final diagnostics = AdventureDiagnostics();
    final operations = AdventureCatalogRecoveryOperations(
      manager: manager,
      diagnostics: diagnostics,
      maxAttempts: 3,
      baseBackoff: const Duration(milliseconds: 10),
      delay: (duration) async => delays.add(duration),
    );

    final result = await operations.verify(_identity);

    expect(result.status, AdventureCatalogRecoveryStatus.verified);
    expect(result.attempts, 2);
    expect(manager.verifyCalls, 2);
    expect(delays, const <Duration>[Duration(milliseconds: 10)]);
    expect(
      diagnostics.snapshot().counters,
      <AdventureDiagnosticReasonCode, int>{
        AdventureDiagnosticReasonCode.assetInterrupted: 1,
      },
    );
  });

  test(
    'repair retries an error persisted by its authority as interrupted',
    () async {
      final manager = _OfflineManager(
        state: _offlineState(
          OfflineContentStatus.interrupted,
          failureCode: OfflineContentFailureCode.interrupted,
        ),
        repairOutcomes: <Object?>[StateError('adapter disconnected'), null],
      );
      final diagnostics = AdventureDiagnostics();
      final operations = AdventureCatalogRecoveryOperations(
        manager: manager,
        diagnostics: diagnostics,
        maxAttempts: 2,
        baseBackoff: Duration.zero,
        delay: (_) async {},
      );

      final result = await operations.repair(_identity);

      expect(result.status, AdventureCatalogRecoveryStatus.repaired);
      expect(result.attempts, 2);
      expect(manager.repairCalls, 2);
      expect(
        diagnostics.snapshot().counters,
        <AdventureDiagnosticReasonCode, int>{
          AdventureDiagnosticReasonCode.assetInterrupted: 1,
        },
      );
    },
  );

  test('concurrent repair requests share one bounded operation', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final manager = _OfflineManager(
      state: _offlineState(
        OfflineContentStatus.interrupted,
        failureCode: OfflineContentFailureCode.interrupted,
      ),
      repairStarted: started,
      repairRelease: release,
    );
    final operations = AdventureCatalogRecoveryOperations(
      manager: manager,
      diagnostics: AdventureDiagnostics(),
      delay: (_) async {},
    );

    final first = operations.repair(_identity);
    await started.future;
    final concurrent = operations.repair(_identity);

    expect(identical(first, concurrent), isTrue);
    release.complete();
    expect((await first).status, AdventureCatalogRecoveryStatus.repaired);
    expect(manager.repairCalls, 1);
  });

  test(
    'recovery rejects identities outside the packaged Adventure catalog',
    () {
      const foreignIdentity = ContentIdentity(
        type: ContentType.offlineArtifact,
        id: 'foreign-catalog',
        revision: 1,
      );
      final manager = _OfflineManager(
        state: _offlineState(OfflineContentStatus.verified),
      );
      final operations = AdventureCatalogRecoveryOperations(
        manager: manager,
        diagnostics: AdventureDiagnostics(),
      );

      expect(() => operations.verify(foreignIdentity), throwsArgumentError);
      expect(() => operations.repair(foreignIdentity), throwsArgumentError);
      expect(() => operations.remove(foreignIdentity), throwsArgumentError);
      expect(manager.verifyCalls, 0);
      expect(manager.repairCalls, 0);
      expect(manager.removeCalls, 0);
    },
  );

  test(
    'times out a pending manager attempt and dispose stays bounded',
    () async {
      final never = Completer<OfflineContentState>();
      final manager = _CallbackOfflineManager(
        inspect: (_) async => _offlineState(OfflineContentStatus.verified),
        verify: (_) => never.future,
      );
      final operations = AdventureCatalogRecoveryOperations(
        manager: manager,
        diagnostics: AdventureDiagnostics(),
        maxAttempts: 3,
        operationTimeout: const Duration(milliseconds: 10),
        disposeTimeout: const Duration(milliseconds: 30),
        delay: (_) async {},
      );

      final result = await operations.verify(_identity);
      final blockedRemove = await operations.remove(_identity);

      expect(manager.verifyCalls, 1);
      expect(manager.removeCalls, 0);
      expect(blockedRemove.status, AdventureCatalogRecoveryStatus.unavailable);
      expect(blockedRemove.attempts, 0);
      never.complete(_offlineState(OfflineContentStatus.verified));
      await Future<void>.delayed(Duration.zero);
      final removal = await operations.remove(_identity);
      await operations.dispose();

      expect(result.status, AdventureCatalogRecoveryStatus.unavailable);
      expect(result.failureCode, OfflineContentFailureCode.interrupted);
      expect(result.attempts, 1);
      expect(removal.status, AdventureCatalogRecoveryStatus.removed);
      expect(manager.removeCalls, 1);
      expect(manager.disposeCalls, 0, reason: 'shared manager is not owned');
    },
  );

  test(
    'deadline fences an operation queued before the timed out source settles',
    () async {
      final never = Completer<OfflineContentState>();
      final manager = _CallbackOfflineManager(
        inspect: (_) async => _offlineState(OfflineContentStatus.verified),
        verify: (_) => never.future,
      );
      final operations = AdventureCatalogRecoveryOperations(
        manager: manager,
        diagnostics: AdventureDiagnostics(),
        operationTimeout: const Duration(milliseconds: 10),
        disposeTimeout: const Duration(milliseconds: 30),
        delay: (_) async {},
      );

      final verify = operations.verify(_identity);
      final queuedRepair = operations.repair(_identity);
      final results = await Future.wait(
        <Future<AdventureCatalogRecoveryResult>>[verify, queuedRepair],
      );

      expect(
        results.map((result) => result.status),
        everyElement(AdventureCatalogRecoveryStatus.unavailable),
      );
      expect(manager.verifyCalls, 1);
      expect(manager.repairCalls, 0);

      never.complete(_offlineState(OfflineContentStatus.verified));
      await Future<void>.delayed(Duration.zero);
      expect(
        (await operations.repair(_identity)).status,
        AdventureCatalogRecoveryStatus.repaired,
      );
      expect(manager.repairCalls, 1);
      await operations.dispose();
    },
  );

  test(
    'inspect errors become a closed result without leaking raw detail',
    () async {
      const privateDetail = r'C:\private\learner\catalog.db';
      final manager = _CallbackOfflineManager(
        inspect: (_) async => throw StateError(privateDetail),
      );
      final diagnostics = AdventureDiagnostics();
      final operations = AdventureCatalogRecoveryOperations(
        manager: manager,
        diagnostics: diagnostics,
        operationTimeout: const Duration(milliseconds: 20),
        delay: (_) async {},
      );

      final result = await operations.verify(_identity);

      expect(result.status, AdventureCatalogRecoveryStatus.unavailable);
      expect(result.failureCode, OfflineContentFailureCode.invalidState);
      expect(result.attempts, 0);
      expect(result.toString(), isNot(contains(privateDetail)));
      expect(
        diagnostics.snapshot().counters,
        <AdventureDiagnosticReasonCode, int>{
          AdventureDiagnosticReasonCode.assetInvalidState: 1,
        },
      );
    },
  );

  test('durable quarantine is rechecked after an external repair', () async {
    final manager = _OfflineManager(
      state: _offlineState(OfflineContentStatus.verified),
      verifyError: const OfflineContentFailure(
        OfflineContentFailureCode.checksumMismatch,
      ),
    );
    final operations = AdventureCatalogRecoveryOperations(
      manager: manager,
      diagnostics: AdventureDiagnostics(),
      delay: (_) async {},
    );

    expect(
      (await operations.verify(_identity)).status,
      AdventureCatalogRecoveryStatus.quarantined,
    );
    manager
      ..state = _offlineState(OfflineContentStatus.verified)
      ..verifyError = null;

    expect(
      (await operations.verify(_identity)).status,
      AdventureCatalogRecoveryStatus.verified,
    );
    expect(manager.verifyCalls, 2);
  });

  test(
    'manager ownership defaults shared and owned disposal is opt-in',
    () async {
      final shared = _OfflineManager(
        state: _offlineState(OfflineContentStatus.verified),
      );
      final owned = _OfflineManager(
        state: _offlineState(OfflineContentStatus.verified),
      );
      final sharedOperations = AdventureCatalogRecoveryOperations(
        manager: shared,
        diagnostics: AdventureDiagnostics(),
      );
      final ownedOperations = AdventureCatalogRecoveryOperations(
        manager: owned,
        diagnostics: AdventureDiagnostics(),
        managerOwnership: AdventureCatalogManagerOwnership.owned,
      );

      await sharedOperations.dispose();
      await ownedOperations.dispose();

      expect(shared.disposeCalls, 0);
      expect(owned.disposeCalls, 1);
    },
  );

  test('owned disposal bounds a stalled manager drain contract', () async {
    final release = Completer<void>();
    final diagnostics = AdventureDiagnostics();
    final manager = _CallbackOfflineManager(dispose: () => release.future);
    final operations = AdventureCatalogRecoveryOperations(
      manager: manager,
      diagnostics: diagnostics,
      managerOwnership: AdventureCatalogManagerOwnership.owned,
      disposeTimeout: const Duration(milliseconds: 10),
    );

    var completed = false;
    final disposal = operations.dispose().whenComplete(() => completed = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(completed, isTrue);
    expect(manager.disposeCalls, 1);
    expect(
      diagnostics.snapshot().counters,
      <AdventureDiagnosticReasonCode, int>{
        AdventureDiagnosticReasonCode.assetInterrupted: 1,
      },
    );
    await disposal;
    release.complete();
  });

  test(
    'verify and repair reject no-throw states that are not verified',
    () async {
      final verifyManager = _CallbackOfflineManager(
        inspect: (_) async => _offlineState(OfflineContentStatus.notDownloaded),
        verify: (_) async => _offlineState(
          OfflineContentStatus.interrupted,
          failureCode: OfflineContentFailureCode.interrupted,
        ),
      );
      final repairManager = _CallbackOfflineManager(
        inspect: (_) async => _offlineState(
          OfflineContentStatus.interrupted,
          failureCode: OfflineContentFailureCode.interrupted,
        ),
        repair: (_) async => _offlineState(
          OfflineContentStatus.quarantined,
          failureCode: OfflineContentFailureCode.checksumMismatch,
        ),
      );

      final verified = await AdventureCatalogRecoveryOperations(
        manager: verifyManager,
        diagnostics: AdventureDiagnostics(),
        maxAttempts: 2,
        baseBackoff: Duration.zero,
        delay: (_) async {},
      ).verify(_identity);
      final repaired = await AdventureCatalogRecoveryOperations(
        manager: repairManager,
        diagnostics: AdventureDiagnostics(),
        maxAttempts: 1,
        delay: (_) async {},
      ).repair(_identity);

      expect(verified.status, AdventureCatalogRecoveryStatus.unavailable);
      expect(verified.failureCode, OfflineContentFailureCode.interrupted);
      expect(verified.attempts, 2);
      expect(repaired.status, AdventureCatalogRecoveryStatus.quarantined);
      expect(repaired.failureCode, OfflineContentFailureCode.checksumMismatch);
    },
  );

  test(
    'repair fallback rejects state from a different content identity',
    () async {
      const foreignIdentity = ContentIdentity(
        type: ContentType.offlineArtifact,
        id: 'foreign-world-v1',
        revision: 1,
      );
      final manager = _CallbackOfflineManager(
        inspect: (_) async => OfflineContentState(
          manifestId: 'manifest:foreign-world-v1',
          identity: foreignIdentity,
          status: OfflineContentStatus.quarantined,
          localPath: null,
          downloadedBytes: 0,
          verifiedChecksumSha256: null,
          failureCode: OfflineContentFailureCode.checksumMismatch,
          updatedAtUtc: DateTime.utc(2026, 9, 4, 9),
        ),
        repair: (_) async => throw StateError('foreign failure'),
      );
      final diagnostics = AdventureDiagnostics();

      final result = await AdventureCatalogRecoveryOperations(
        manager: manager,
        diagnostics: diagnostics,
        maxAttempts: 1,
        delay: (_) async {},
      ).repair(_identity);

      expect(result.failureCode, OfflineContentFailureCode.invalidState);
      expect(
        diagnostics.snapshot().counters,
        <AdventureDiagnosticReasonCode, int>{
          AdventureDiagnosticReasonCode.assetInvalidState: 1,
        },
      );
    },
  );

  test('verify repair and remove are serialized for one identity', () async {
    final verifyStarted = Completer<void>();
    final releaseVerify = Completer<void>();
    final calls = <String>[];
    final manager = _CallbackOfflineManager(
      inspect: (_) async => _offlineState(OfflineContentStatus.notDownloaded),
      verify: (_) async {
        calls.add('verify');
        verifyStarted.complete();
        await releaseVerify.future;
        return _offlineState(OfflineContentStatus.verified);
      },
      repair: (_) async {
        calls.add('repair');
        return _offlineState(OfflineContentStatus.verified);
      },
      remove: (_) async {
        calls.add('remove');
        return 4;
      },
    );
    final operations = AdventureCatalogRecoveryOperations(
      manager: manager,
      diagnostics: AdventureDiagnostics(),
      operationTimeout: const Duration(seconds: 1),
      delay: (_) async {},
    );

    final verify = operations.verify(_identity);
    await verifyStarted.future;
    final repair = operations.repair(_identity);
    final remove = operations.remove(_identity);
    await Future<void>.delayed(Duration.zero);
    expect(calls, <String>['verify']);

    releaseVerify.complete();
    await Future.wait(<Future<AdventureCatalogRecoveryResult>>[
      verify,
      repair,
      remove,
    ]);
    expect(calls, <String>['verify', 'repair', 'remove']);
  });

  test(
    'dispose interrupts a pending backoff and returns a closed result',
    () async {
      final backoffStarted = Completer<void>();
      final never = Completer<void>();
      final manager = _CallbackOfflineManager(
        inspect: (_) async => _offlineState(OfflineContentStatus.notDownloaded),
        verify: (_) async => throw TimeoutException('transient'),
      );
      final operations = AdventureCatalogRecoveryOperations(
        manager: manager,
        diagnostics: AdventureDiagnostics(),
        baseBackoff: const Duration(milliseconds: 20),
        operationTimeout: const Duration(milliseconds: 20),
        disposeTimeout: const Duration(milliseconds: 50),
        delay: (_) {
          backoffStarted.complete();
          return never.future;
        },
      );

      final verification = operations.verify(_identity);
      await backoffStarted.future;
      await operations.dispose();
      final result = await verification;

      expect(result.status, AdventureCatalogRecoveryStatus.unavailable);
      expect(result.failureCode, OfflineContentFailureCode.interrupted);
      expect(manager.verifyCalls, 1);
    },
  );

  test(
    'remove delegates once and owned dispose closes resources once',
    () async {
      final manager = _OfflineManager(
        state: _offlineState(OfflineContentStatus.verified),
        removedBytes: 4096,
      );
      final operations = AdventureCatalogRecoveryOperations(
        manager: manager,
        diagnostics: AdventureDiagnostics(),
        managerOwnership: AdventureCatalogManagerOwnership.owned,
        delay: (_) async {},
      );

      final result = await operations.remove(_identity);
      await operations.dispose();
      await operations.dispose();

      expect(result.status, AdventureCatalogRecoveryStatus.removed);
      expect(result.removedBytes, 4096);
      expect(manager.removeCalls, 1);
      expect(manager.disposeCalls, 1);
      expect(() => operations.verify(_identity), throwsStateError);
      expect(() => operations.repair(_identity), throwsStateError);
      expect(() => operations.remove(_identity), throwsStateError);
    },
  );
}

typedef _StateOperation =
    Future<OfflineContentState> Function(ContentIdentity identity);
typedef _RemoveOperation = Future<int> Function(ContentIdentity identity);

final class _CallbackOfflineManager
    implements OfflineContentManager, OfflineContentStateInspector {
  _CallbackOfflineManager({
    _StateOperation? inspect,
    _StateOperation? verify,
    _StateOperation? repair,
    _RemoveOperation? remove,
    Future<void> Function()? dispose,
  }) : _inspect =
           inspect ??
           ((_) async => _offlineState(OfflineContentStatus.notDownloaded)),
       _verify =
           verify ??
           ((_) async => _offlineState(OfflineContentStatus.verified)),
       _repair =
           repair ??
           ((_) async => _offlineState(OfflineContentStatus.verified)),
       _remove = remove ?? ((_) async => 0),
       _dispose = dispose ?? (() async {});

  final _StateOperation _inspect;
  final _StateOperation _verify;
  final _StateOperation _repair;
  final _RemoveOperation _remove;
  final Future<void> Function() _dispose;
  int verifyCalls = 0;
  int repairCalls = 0;
  int removeCalls = 0;
  int disposeCalls = 0;

  @override
  Future<OfflineContentState> inspect(ContentIdentity identity) =>
      _inspect(identity);

  @override
  Future<OfflineContentState> verify(ContentIdentity identity) {
    verifyCalls += 1;
    return _verify(identity);
  }

  @override
  Future<OfflineContentState> repair(ContentIdentity identity) {
    repairCalls += 1;
    return _repair(identity);
  }

  @override
  Future<int> removeBytes(ContentIdentity identity) {
    removeCalls += 1;
    return _remove(identity);
  }

  @override
  Future<List<OfflineContentState>> catalog() async => const [];

  @override
  Future<OfflineContentState> download(ContentIdentity identity) =>
      _verify(identity);

  @override
  Future<bool> canRemove(ContentIdentity identity) async => true;

  @override
  Future<int> cleanupForDiskPressure({required int bytesToFree}) async => 0;

  @override
  Future<void> reconcile() async {}

  @override
  Future<void> dispose() {
    disposeCalls += 1;
    return _dispose();
  }
}

const _identity = ContentIdentity(
  type: ContentType.offlineArtifact,
  id: 'lexiquest.adventure.world-v1',
  revision: 1,
);

OfflineContentState _offlineState(
  OfflineContentStatus status, {
  OfflineContentFailureCode? failureCode,
}) => OfflineContentState(
  manifestId: 'manifest:lexiquest.adventure.world-v1',
  identity: _identity,
  status: status,
  localPath: status == OfflineContentStatus.verified
      ? '${'a' * 64}.content'
      : null,
  downloadedBytes: status == OfflineContentStatus.verified ? 4 : 0,
  verifiedChecksumSha256: status == OfflineContentStatus.verified
      ? 'b' * 64
      : null,
  failureCode: failureCode,
  updatedAtUtc: DateTime.utc(2026, 9, 4, 9),
);

final class _OfflineManager
    implements OfflineContentManager, OfflineContentStateInspector {
  _OfflineManager({
    required this.state,
    this.verifyError,
    List<Object?> verifyOutcomes = const <Object?>[],
    List<Object?> repairOutcomes = const <Object?>[],
    this.removedBytes = 0,
    this.repairStarted,
    this.repairRelease,
  }) : verifyOutcomes = List<Object?>.of(verifyOutcomes),
       repairOutcomes = List<Object?>.of(repairOutcomes);

  OfflineContentState state;
  Object? verifyError;
  final List<Object?> verifyOutcomes;
  final List<Object?> repairOutcomes;
  final int removedBytes;
  final Completer<void>? repairStarted;
  final Completer<void>? repairRelease;
  int verifyCalls = 0;
  int catalogCalls = 0;
  int repairCalls = 0;
  int removeCalls = 0;
  int disposeCalls = 0;

  @override
  Future<List<OfflineContentState>> catalog() async {
    catalogCalls += 1;
    return <OfflineContentState>[state];
  }

  @override
  Future<OfflineContentState> inspect(ContentIdentity identity) async => state;

  @override
  Future<OfflineContentState> verify(ContentIdentity identity) async {
    verifyCalls += 1;
    final error = verifyOutcomes.isEmpty
        ? verifyError
        : verifyOutcomes.removeAt(0);
    if (error != null) {
      if (error is OfflineContentFailure) {
        state = _offlineState(
          OfflineContentStatus.quarantined,
          failureCode: error.code,
        );
      }
      throw error;
    }
    return state;
  }

  @override
  Future<OfflineContentState> download(ContentIdentity identity) async => state;

  @override
  Future<OfflineContentState> repair(ContentIdentity identity) async {
    repairCalls += 1;
    if (!(repairStarted?.isCompleted ?? true)) repairStarted!.complete();
    await repairRelease?.future;
    final outcome = repairOutcomes.isEmpty ? null : repairOutcomes.removeAt(0);
    if (outcome != null) throw outcome;
    state = _offlineState(OfflineContentStatus.verified);
    return state;
  }

  @override
  Future<bool> canRemove(ContentIdentity identity) async => true;

  @override
  Future<int> removeBytes(ContentIdentity identity) async {
    removeCalls += 1;
    state = _offlineState(OfflineContentStatus.notDownloaded);
    return removedBytes;
  }

  @override
  Future<int> cleanupForDiskPressure({required int bytesToFree}) async => 0;

  @override
  Future<void> reconcile() async {}

  @override
  Future<void> dispose() async => disposeCalls += 1;
}
