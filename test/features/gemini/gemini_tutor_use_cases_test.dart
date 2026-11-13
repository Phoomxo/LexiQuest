import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/application/gemini_tutor_use_cases.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';

void main() {
  test(
    'forwards typed mode without injecting it into the learner message',
    () async {
      final gateway = _FakeGateway();
      final tutor = GeminiTutorUseCases(
        store: _MemorySettingsStore()..key = 'synthetic-A',
        gateway: gateway,
        nowUtc: () => DateTime.utc(2026),
        readScope: () => _scopeA,
      );
      await _enable(tutor);
      await tutor.reply(
        scenario: 'Cafe',
        learnerMessage: 'Synthetic question',
        mode: GeminiTutorMode.direct,
      );
      expect(gateway.lastMode, GeminiTutorMode.direct);
      expect(gateway.lastMessage, 'Synthetic question');
      await tutor.dispose();
    },
  );
  test(
    'reentrant ABA cannot readmit revocation into a later epoch of A',
    () async {
      var scope = _scopeA;
      var switched = false;
      final store = _MemorySettingsStore()..key = 'synthetic-A';
      final tutor = GeminiTutorUseCases(
        store: store,
        gateway: _FakeGateway(),
        nowUtc: () => DateTime.utc(2026),
        readScope: () => scope,
      );
      await _enable(tutor);
      final subscription = tutor.invalidations.listen((_) {
        if (switched) return;
        switched = true;
        scope = _scopeB;
        tutor.invalidateScope();
        scope = _scopeA;
        tutor.invalidateScope();
      });
      await expectLater(
        tutor.removeKey(),
        throwsA(_code(GeminiFailureCode.cancelled)),
      );
      expect(store.key, 'synthetic-A');
      expect(store.writeEntered.isCompleted, isFalse);
      expect((await tutor.loadSettings()).providerConsent, isFalse);
      await subscription.cancel();
      await tutor.dispose();
    },
  );
  for (final command in ['configure', 'remove', 'consents']) {
    test(
      'unnotified scope change aborts original $command instead of adopting B',
      () async {
        var scope = _scopeA;
        final store = _MemorySettingsStore()..key = 'synthetic-A';
        store.records[_scopeB] = const GeminiConfiguration(key: 'synthetic-B');
        final gateway = _FakeGateway();
        final tutor = GeminiTutorUseCases(
          store: store,
          gateway: gateway,
          nowUtc: () => DateTime.utc(2026),
          readScope: () => scope,
        );
        await _enable(tutor);
        scope = _scopeB;
        final operation = switch (command) {
          'configure' => tutor.configure(
            key: 'synthetic-A-captured',
            providerConsent: true,
            shareLearningSummary: true,
          ),
          'remove' => tutor.removeKey(),
          _ => tutor.updateConsents(
            providerConsent: true,
            shareLearningSummary: true,
          ),
        };
        await expectLater(
          operation,
          throwsA(_code(GeminiFailureCode.cancelled)),
        );
        expect(store.records[_scopeB]!.key, 'synthetic-B');
        expect((await tutor.loadSettings()).providerConsent, isFalse);
        expect(gateway.generateCalls, 0);
        await tutor.dispose();
      },
    );
  }
  test(
    'revocation retains admission scope even when invalidation listeners switch owner',
    () async {
      var scope = _scopeA;
      final store = _MemorySettingsStore()..key = 'synthetic-A';
      store.records[_scopeB] = const GeminiConfiguration(key: 'synthetic-B');
      final tutor = GeminiTutorUseCases(
        store: store,
        gateway: _FakeGateway(),
        nowUtc: () => DateTime.utc(2026),
        readScope: () => scope,
      );
      await _enable(tutor);
      final subscription = tutor.invalidations.listen((_) {
        scope = _scopeB;
      });
      await expectLater(
        tutor.removeKey(),
        throwsA(_code(GeminiFailureCode.cancelled)),
      );
      expect(store.records[_scopeB]!.key, 'synthetic-B');
      await subscription.cancel();
      await tutor.dispose();
    },
  );
  test(
    'restart keeps credential only and requires explicit provider and summary activation',
    () async {
      final store = _MemorySettingsStore();
      final gateway = _FakeGateway();
      final tutor = _tutor(store, gateway);
      await tutor.configure(
        key: 'synthetic-persisted',
        providerConsent: true,
        shareLearningSummary: true,
      );
      expect((await tutor.loadSettings()).providerConsent, isTrue);
      final restarted = _tutor(store, gateway);
      final status = await restarted.loadSettings();
      expect(status.hasKey, isTrue);
      expect(status.providerConsent, isFalse);
      expect(status.shareLearningSummary, isFalse);
      await expectLater(
        restarted.reply(
          scenario: 'Cafe Ordering',
          learnerMessage: 'Do not send',
        ),
        throwsA(_code(GeminiFailureCode.consentRequired)),
      );
      expect(gateway.generatedKeys, isEmpty);
      await _enable(restarted);
      await restarted.reply(
        scenario: 'Cafe Ordering',
        learnerMessage: 'Explicit send',
      );
      expect(gateway.generatedKeys, ['synthetic-persisted']);
      expect(gateway.lastSummary, isNull);
      await tutor.dispose();
      await restarted.dispose();
    },
  );

  test(
    'uncertain canceled key save cannot restore consent even if compensation fails',
    () async {
      final gate = Completer<void>();
      final store = _MemorySettingsStore()
        ..writeGate = gate
        ..failCleanup = true;
      final gateway = _FakeGateway();
      final tutor = _tutor(store, gateway);
      final cancellation = GeminiCancellation();
      final pending = expectLater(
        tutor.configure(
          key: 'synthetic-uncertain',
          providerConsent: true,
          shareLearningSummary: true,
          cancellation: cancellation,
        ),
        throwsA(_code(GeminiFailureCode.secureStorage)),
      );
      await store.writeEntered.future;
      cancellation.cancel();
      gate.complete();
      await pending;
      final restarted = _tutor(store, gateway);
      final status = await restarted.loadSettings();
      expect(status.hasKey, isTrue);
      expect(status.providerConsent, isFalse);
      expect(status.shareLearningSummary, isFalse);
      await expectLater(
        restarted.reply(
          scenario: 'Cafe Ordering',
          learnerMessage: 'No activation',
        ),
        throwsA(_code(GeminiFailureCode.consentRequired)),
      );
      expect(gateway.generateCalls, 0);
      await tutor.dispose();
      await restarted.dispose();
    },
  );
  test(
    'cancellation at mutation return clears committed record before reporting cancelled',
    () async {
      var checksAfterWrite = 0;
      final cancellation = GeminiCancellation();
      final store = _MemorySettingsStore();
      final gateway = _FakeGateway();
      final tutor = GeminiTutorUseCases(
        store: store,
        gateway: gateway,
        nowUtc: () => DateTime.utc(2026),
        readScope: () {
          if (store.key == 'synthetic-new' && ++checksAfterWrite == 4) {
            cancellation.cancel();
          }
          return _scopeA;
        },
      );
      await expectLater(
        tutor.configure(
          key: 'synthetic-new',
          providerConsent: true,
          shareLearningSummary: true,
          cancellation: cancellation,
        ),
        throwsA(_code(GeminiFailureCode.cancelled)),
      );
      final restarted = _tutor(store, gateway);
      expect((await restarted.loadSettings()).hasKey, isFalse);
      await tutor.dispose();
      await restarted.dispose();
    },
  );
  test(
    'persistent verification failure emits one unavailable edge, not reload loop',
    () async {
      var checks = 0;
      var events = 0;
      final tutor = GeminiTutorUseCases(
        store: _MemorySettingsStore(),
        gateway: _FakeGateway(),
        nowUtc: () => DateTime.utc(2026),
        readScope: () => _scopeA,
        verifyScope: () async {
          checks += 1;
          throw StateError('synthetic-unavailable');
        },
      );
      final subscription = tutor.invalidations.listen((_) {
        events += 1;
        if (events < 4) {
          unawaited(tutor.loadSettings().then<void>((_) {}, onError: (_) {}));
        }
      });
      await expectLater(
        tutor.loadSettings(),
        throwsA(_code(GeminiFailureCode.cancelled)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, 1);
      expect(checks, 2);
      await subscription.cancel();
      await tutor.dispose();
    },
  );

  test(
    'throwing scope reader still invalidates pending generation synchronously',
    () async {
      var unavailable = false;
      final store = _MemorySettingsStore()
        ..key = 'synthetic-key'
        ..providerConsent = true;
      final gateway = _FakeGateway()..generationGate = Completer<String>();
      final tutor = GeminiTutorUseCases(
        store: store,
        gateway: gateway,
        nowUtc: () => DateTime.utc(2026),
        readScope: () {
          if (unavailable) throw StateError('synthetic-auth-down');
          return _scopeA;
        },
      );
      await _enable(tutor);
      final cancellation = GeminiCancellation();
      final pending = expectLater(
        tutor.reply(
          scenario: 'Cafe Ordering',
          learnerMessage: 'Hi',
          cancellation: cancellation,
        ),
        throwsA(_code(GeminiFailureCode.cancelled)),
      );
      await gateway.generationEntered.future;
      final before = tutor.epoch;
      unavailable = true;
      expect(tutor.invalidateScope, returnsNormally);
      expect(tutor.epoch, greaterThan(before));
      expect(cancellation.isCancelled, isTrue);
      gateway.generationGate!.complete('Late');
      await pending;
      await expectLater(
        tutor.loadSettings(),
        throwsA(_code(GeminiFailureCode.cancelled)),
      );
      await tutor.dispose();
    },
  );
  for (final boundary in ['generate', 'write']) {
    test(
      'scope invalidation in verifier return gap prevents $boundary admission',
      () async {
        var arm = false;
        var verification = 0;
        var scope = _scopeA;
        final store = _MemorySettingsStore()
          ..key = 'synthetic-key'
          ..providerConsent = true;
        final gateway = _FakeGateway();
        late GeminiTutorUseCases tutor;
        tutor = GeminiTutorUseCases(
          store: store,
          gateway: gateway,
          nowUtc: () => DateTime.utc(2026),
          readScope: () {
            if (arm) {
              arm = false;
              scheduleMicrotask(() {
                scope = _scopeB;
                tutor.invalidateScope();
              });
            }
            return scope;
          },
          verifyScope: () async {
            verification += 1;
            if (verification == 3) arm = true;
            return scope;
          },
        );
        await _enable(tutor);
        verification = 0;
        final operation = boundary == 'generate'
            ? tutor.reply(
                scenario: 'Cafe Ordering',
                learnerMessage: 'Synthetic',
              )
            : tutor.configure(
                key: 'synthetic-replacement',
                providerConsent: true,
                shareLearningSummary: false,
              );
        await expectLater(
          operation,
          throwsA(_code(GeminiFailureCode.cancelled)),
        );
        if (boundary == 'generate') {
          expect(gateway.generateCalls, 0);
        } else {
          expect(store.writeEntered.isCompleted, isFalse);
        }
        await tutor.dispose();
      },
    );
  }
  test(
    'owner auth verification errors fail AI closed with a typed error',
    () async {
      final tutor = GeminiTutorUseCases(
        store: _MemorySettingsStore(),
        gateway: _FakeGateway(),
        nowUtc: () => DateTime.utc(2026),
        readScope: () => _scopeA,
        verifyScope: () async => throw StateError('synthetic-auth-unavailable'),
      );
      await expectLater(
        tutor.loadSettings(),
        throwsA(_code(GeminiFailureCode.cancelled)),
      );
      await tutor.dispose();
    },
  );

  for (final transition in ['owner', 'logout', 'upgrade', 'ABA']) {
    test(
      '$transition invalidates delayed configuration and late provider return',
      () async {
        GeminiScope? scope = _scopeA;
        final store = _MemorySettingsStore()
          ..key = 'synthetic-A'
          ..providerConsent = true;
        final gateway = _FakeGateway()..generationGate = Completer<String>();
        final tutor = GeminiTutorUseCases(
          store: store,
          gateway: gateway,
          nowUtc: () => DateTime.utc(2026),
          readScope: () => scope,
        );
        await _enable(tutor);
        final reply = expectLater(
          tutor.reply(scenario: 'Cafe Ordering', learnerMessage: 'Hi'),
          throwsA(_code(GeminiFailureCode.cancelled)),
        );
        await gateway.generationEntered.future;
        scope = switch (transition) {
          'logout' => null,
          'upgrade' => const GeminiScope(
            ownerId: 'A',
            firebaseUid: 'uid-A',
            isAnonymous: true,
          ),
          _ => _scopeB,
        };
        tutor.invalidateScope();
        if (transition == 'ABA') {
          scope = _scopeA;
          tutor.invalidateScope();
        }
        gateway.generationGate!.complete('Late synthetic reply');
        await reply;
        gateway.validationGate = Completer<void>();
        scope = _scopeA;
        tutor.invalidateScope();
        final configure = expectLater(
          tutor.configure(
            key: 'synthetic-replacement',
            providerConsent: true,
            shareLearningSummary: true,
          ),
          throwsA(_code(GeminiFailureCode.cancelled)),
        );
        await gateway.validationEntered.future;
        scope = _scopeB;
        tutor.invalidateScope();
        gateway.validationGate!.complete();
        await configure;
        expect(store.key, 'synthetic-A');
        expect(store.records[_scopeB], isNull);
        await tutor.dispose();
      },
    );
  }

  test('two owners restore only their own coherent key and consents', () async {
    var scope = _scopeA;
    final store = _MemorySettingsStore();
    final gateway = _FakeGateway();
    final tutor = GeminiTutorUseCases(
      store: store,
      gateway: gateway,
      nowUtc: () => DateTime.utc(2026),
      readScope: () => scope,
    );
    await tutor.configure(
      key: 'synthetic-A',
      providerConsent: true,
      shareLearningSummary: true,
    );
    scope = _scopeB;
    tutor.invalidateScope();
    expect((await tutor.loadSettings()).hasKey, isFalse);
    await tutor.configure(
      key: 'synthetic-B',
      providerConsent: true,
      shareLearningSummary: false,
    );
    await tutor.reply(scenario: 'Cafe Ordering', learnerMessage: 'B');
    scope = _scopeA;
    tutor.invalidateScope();
    expect((await tutor.loadSettings()).shareLearningSummary, isFalse);
    await expectLater(
      tutor.reply(scenario: 'Cafe Ordering', learnerMessage: 'Not yet enabled'),
      throwsA(_code(GeminiFailureCode.consentRequired)),
    );
    await _enable(tutor, summary: true);
    await tutor.reply(scenario: 'Cafe Ordering', learnerMessage: 'A');
    expect(gateway.generatedKeys, ['synthetic-B', 'synthetic-A']);
    await tutor.dispose();
  });

  test(
    'command queued before scope transition never adopts its new owner',
    () async {
      var scope = _scopeA;
      final store = _MemorySettingsStore();
      final gateway = _FakeGateway()..validationGate = Completer<void>();
      final tutor = GeminiTutorUseCases(
        store: store,
        gateway: gateway,
        nowUtc: () => DateTime.utc(2026),
        readScope: () => scope,
      );
      final first = expectLater(
        tutor.configure(
          key: 'synthetic-first',
          providerConsent: true,
          shareLearningSummary: false,
        ),
        throwsA(_code(GeminiFailureCode.cancelled)),
      );
      await gateway.validationEntered.future;
      final second = expectLater(
        tutor.configure(
          key: 'synthetic-queued',
          providerConsent: true,
          shareLearningSummary: true,
        ),
        throwsA(_code(GeminiFailureCode.cancelled)),
      );
      scope = _scopeB;
      tutor.invalidateScope();
      gateway.validationGate!.complete();
      await Future.wait([first, second]);
      expect(store.records, isEmpty);
      await tutor.dispose();
    },
  );

  for (final failure in ['cancel', 'owner', 'storage']) {
    test(
      '$failure during secure write cannot restore pending config after restart',
      () async {
        var scope = _scopeA;
        final gate = Completer<void>();
        final store = _MemorySettingsStore()..writeGate = gate;
        final gateway = _FakeGateway();
        final tutor = GeminiTutorUseCases(
          store: store,
          gateway: gateway,
          nowUtc: () => DateTime.utc(2026),
          readScope: () => scope,
        );
        final cancellation = GeminiCancellation();
        final operation = expectLater(
          tutor.configure(
            key: 'synthetic-pending',
            providerConsent: true,
            shareLearningSummary: true,
            cancellation: cancellation,
          ),
          throwsA(
            _code(
              failure == 'storage'
                  ? GeminiFailureCode.secureStorage
                  : GeminiFailureCode.cancelled,
            ),
          ),
        );
        await store.writeEntered.future;
        if (failure == 'cancel') cancellation.cancel();
        if (failure == 'owner') {
          scope = _scopeB;
          tutor.invalidateScope();
        }
        if (failure == 'storage') store.failWriteOnce = true;
        gate.complete();
        await operation;
        final restarted = _tutor(store, gateway);
        final status = await restarted.loadSettings();
        expect(status.hasKey, isFalse);
        expect(status.providerConsent, isFalse);
        expect(status.shareLearningSummary, isFalse);
        expect(store.records[_scopeB], isNull);
        await tutor.dispose();
        await restarted.dispose();
      },
    );
  }

  test('cancelled validation cannot activate a configuration', () async {
    final gate = Completer<void>();
    final store = _MemorySettingsStore();
    final gateway = _FakeGateway()..validationGate = gate;
    final tutor = _tutor(store, gateway);
    final cancellation = GeminiCancellation();
    final operation = tutor.configure(
      key: 'synthetic-new-key',
      providerConsent: true,
      shareLearningSummary: true,
      cancellation: cancellation,
    );
    final result = expectLater(operation, throwsA(isA<GeminiException>()));
    await gateway.validationEntered.future;
    cancellation.cancel();
    gate.complete();
    await result;
    expect(store.key, isNull);
    expect(store.providerConsent, isFalse);
  });

  test('cancellation during summary load prevents provider dispatch', () async {
    final gate = Completer<ProgressSnapshot>();
    final entered = Completer<void>();
    final store = _MemorySettingsStore()
      ..key = 'synthetic-key'
      ..providerConsent = true
      ..summaryConsent = true;
    final gateway = _FakeGateway();
    final tutor = _tutor(
      store,
      gateway,
      loadProgress: () {
        entered.complete();
        return gate.future;
      },
    );
    await _enable(tutor, summary: true);
    final cancellation = GeminiCancellation();
    final operation = tutor.reply(
      scenario: 'Cafe Ordering',
      learnerMessage: 'Hi',
      cancellation: cancellation,
    );
    final result = expectLater(operation, throwsA(isA<GeminiException>()));
    await entered.future;
    cancellation.cancel();
    gate.complete(_progress());
    await result;
    expect(gateway.generateCalls, 0);
  });

  test(
    'second send is rejected instead of queued behind provider work',
    () async {
      final store = _MemorySettingsStore()
        ..key = 'synthetic-key'
        ..providerConsent = true;
      final gateway = _FakeGateway()..generationGate = Completer<String>();
      final tutor = _tutor(store, gateway);
      await _enable(tutor);
      final first = tutor.reply(
        scenario: 'Cafe Ordering',
        learnerMessage: 'First',
      );
      await gateway.generationEntered.future;
      final second = expectLater(
        tutor.reply(scenario: 'Cafe Ordering', learnerMessage: 'Second'),
        throwsA(isA<GeminiException>()),
      );
      gateway.generationGate!.complete('Synthetic response');
      await first;
      await second;
      expect(gateway.generateCalls, 1);
    },
  );

  test('validates replacement before overwriting existing key', () async {
    final store = _MemorySettingsStore()..key = 'existing-private-key';
    final gateway = _FakeGateway()
      ..validationFailure = const GeminiException(GeminiFailureCode.invalidKey);
    final tutor = _tutor(store, gateway);

    await expectLater(
      tutor.configure(
        key: 'invalid-replacement-key-that-is-long',
        providerConsent: true,
        shareLearningSummary: false,
      ),
      throwsA(isA<GeminiException>()),
    );

    expect(store.key, 'existing-private-key');
    expect(gateway.generatedKeys, isEmpty);
  });

  test('removing key prevents all future provider calls', () async {
    final store = _MemorySettingsStore()
      ..key = 'configured-private-key'
      ..providerConsent = true;
    final gateway = _FakeGateway();
    final tutor = _tutor(store, gateway);

    await tutor.removeKey();

    await expectLater(
      tutor.reply(scenario: 'Cafe Ordering', learnerMessage: 'A coffee please'),
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.consentRequired,
        ),
      ),
    );
    expect(gateway.generateCalls, 0);
  });

  test('sends bounded aggregate progress only after summary consent', () async {
    final store = _MemorySettingsStore()
      ..key = 'configured-private-key'
      ..providerConsent = true
      ..summaryConsent = true;
    final gateway = _FakeGateway();
    final tutor = _tutor(store, gateway, loadProgress: () async => _progress());
    await _enable(tutor, summary: true);

    final reply = await tutor.reply(
      scenario: 'Job Interview',
      learnerMessage: 'I learn quickly.',
    );

    expect(reply.text, 'Live provider reply');
    expect(reply.model, 'gemini-test');
    expect(gateway.lastSummary, contains('answers=10'));
    expect(gateway.lastSummary, contains('apple:50%(n=4)'));
    expect(gateway.lastSummary, isNot(contains('owner')));
  });

  test('does not read or send progress without summary consent', () async {
    var progressCalls = 0;
    final store = _MemorySettingsStore()
      ..key = 'configured-private-key'
      ..providerConsent = true;
    final gateway = _FakeGateway();
    final tutor = _tutor(
      store,
      gateway,
      loadProgress: () async {
        progressCalls += 1;
        return _progress();
      },
    );
    await _enable(tutor);
    await tutor.reply(
      scenario: 'Job Interview',
      learnerMessage: 'I learn quickly.',
    );

    expect(progressCalls, 0);
    expect(gateway.lastSummary, isNull);
  });

  test('removing key cancels and awaits active provider work', () async {
    final store = _MemorySettingsStore()
      ..key = 'configured-private-key'
      ..providerConsent = true;
    final gateway = _PendingGateway();
    final tutor = GeminiTutorUseCases(
      store: store,
      gateway: gateway,
      nowUtc: () => DateTime.utc(2026, 7, 30),
      readScope: () => _scopeA,
    );
    await _enable(tutor);
    final reply = tutor.reply(
      scenario: 'Job Interview',
      learnerMessage: 'I learn quickly.',
    );
    final replyExpectation = expectLater(
      reply,
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.cancelled,
        ),
      ),
    );
    await gateway.started.future;

    await tutor.removeKey();
    await replyExpectation;

    expect(store.key, isNull);
    expect(gateway.cancelled, isTrue);
  });

  test('removal is ordered before a reply started during revocation', () async {
    final store = _MemorySettingsStore()
      ..key = 'configured-private-key'
      ..providerConsent = true;
    final gateway = _PendingGateway();
    final tutor = GeminiTutorUseCases(
      store: store,
      gateway: gateway,
      nowUtc: () => DateTime.utc(2026, 7, 30),
      readScope: () => _scopeA,
    );
    await _enable(tutor);
    final first = tutor.reply(
      scenario: 'Job Interview',
      learnerMessage: 'First message',
    );
    final firstExpectation = expectLater(
      first,
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.cancelled,
        ),
      ),
    );
    await gateway.started.future;

    final removal = tutor.removeKey();
    final second = tutor.reply(
      scenario: 'Job Interview',
      learnerMessage: 'Second message',
    );
    final secondExpectation = expectLater(
      second,
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.consentRequired,
        ),
      ),
    );

    await Future.wait([removal, firstExpectation, secondExpectation]);
    expect(gateway.generateCalls, 1);
  });
}

GeminiTutorUseCases _tutor(
  _MemorySettingsStore store,
  _FakeGateway gateway, {
  LoadProgressSnapshot? loadProgress,
}) {
  return GeminiTutorUseCases(
    store: store,
    gateway: gateway,
    loadProgress: loadProgress,
    nowUtc: () => DateTime.utc(2026, 7, 30),
    readScope: () => _scopeA,
  );
}

ProgressSnapshot _progress() => ProgressSnapshot(
  sampleSize: 10,
  correctCount: 7,
  wrongCount: 3,
  accuracy: 0.7,
  totalXp: 70,
  completedSessions: 2,
  streakDays: 1,
  dueReviewCount: 3,
  masteredWordCount: 2,
  achievementCount: 1,
  gameLevel: 1,
  skills: const [],
  weaknesses: [
    WeaknessEvidence(
      wordId: 'word-1',
      spelling: 'apple',
      meaning: 'ผลไม้',
      sampleSize: 4,
      incorrectCount: 2,
      errorRate: 0.5,
      dueAtUtc: DateTime.utc(2026, 7, 31),
    ),
  ],
  recommendations: const [],
);

final class _MemorySettingsStore implements GeminiSettingsStore {
  final records = <GeminiScope, GeminiConfiguration>{};
  GeminiConfiguration get a => records[_scopeA] ?? const GeminiConfiguration();
  String? get key => a.key;
  set key(String? value) => records[_scopeA] = GeminiConfiguration(
    key: value,
    providerConsent: a.providerConsent,
    shareLearningSummary: a.shareLearningSummary,
  );
  bool get providerConsent => a.providerConsent;
  set providerConsent(bool value) => records[_scopeA] = GeminiConfiguration(
    key: a.key,
    providerConsent: value,
    shareLearningSummary: a.shareLearningSummary,
  );
  bool get summaryConsent => a.shareLearningSummary;
  set summaryConsent(bool value) => records[_scopeA] = GeminiConfiguration(
    key: a.key,
    providerConsent: a.providerConsent,
    shareLearningSummary: value,
  );
  Completer<void>? writeGate;
  final writeEntered = Completer<void>();
  bool failWriteOnce = false;
  bool failCleanup = false;
  @override
  Future<GeminiConfiguration> read(GeminiScope scope) async =>
      records[scope] ?? const GeminiConfiguration();
  @override
  Future<void> write(
    GeminiScope scope,
    GeminiConfiguration configuration,
  ) async {
    if (failCleanup && configuration.key == null) {
      throw const GeminiException(GeminiFailureCode.secureStorage);
    }
    if (!writeEntered.isCompleted) writeEntered.complete();
    final gate = writeGate;
    writeGate = null;
    await gate?.future;
    records[scope] = configuration;
    if (failWriteOnce) {
      failWriteOnce = false;
      throw const GeminiException(GeminiFailureCode.secureStorage);
    }
  }
}

const _scopeA = GeminiScope(
  ownerId: 'A',
  firebaseUid: 'uid-A',
  isAnonymous: false,
);
const _scopeB = GeminiScope(
  ownerId: 'B',
  firebaseUid: 'uid-B',
  isAnonymous: false,
);

Matcher _code(GeminiFailureCode code) =>
    isA<GeminiException>().having((e) => e.code, 'code', code);
Future<void> _enable(GeminiTutorUseCases tutor, {bool summary = false}) =>
    tutor.updateConsents(providerConsent: true, shareLearningSummary: summary);

final class _FakeGateway implements GeminiGateway {
  Completer<void>? validationGate;
  Completer<String>? generationGate;
  final validationEntered = Completer<void>();
  final generationEntered = Completer<void>();
  GeminiException? validationFailure;
  final List<String> generatedKeys = [];
  int generateCalls = 0;
  String? lastSummary;
  GeminiTutorMode? lastMode;
  String? lastMessage;

  @override
  String get model => 'gemini-test';

  @override
  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    GeminiTutorMode mode = GeminiTutorMode.guided,
    String? learningSummary,
    GeminiCancellation? cancellation,
  }) async {
    generateCalls += 1;
    lastMode = mode;
    lastMessage = learnerMessage;
    if (!generationEntered.isCompleted) generationEntered.complete();
    generatedKeys.add(key);
    lastSummary = learningSummary;
    return generationGate?.future ?? 'Live provider reply';
  }

  @override
  Future<void> validateKey(
    String key, {
    GeminiCancellation? cancellation,
  }) async {
    if (!validationEntered.isCompleted) validationEntered.complete();
    await validationGate?.future;
    final failure = validationFailure;
    if (failure != null) throw failure;
  }
}

final class _PendingGateway implements GeminiGateway {
  final Completer<void> started = Completer<void>();
  bool cancelled = false;
  int generateCalls = 0;

  @override
  String get model => 'gemini-test';

  @override
  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    GeminiTutorMode mode = GeminiTutorMode.guided,
    String? learningSummary,
    GeminiCancellation? cancellation,
  }) async {
    generateCalls += 1;
    started.complete();
    await cancellation!.whenCancelled;
    cancelled = true;
    throw const GeminiException(GeminiFailureCode.cancelled);
  }

  @override
  Future<void> validateKey(
    String key, {
    GeminiCancellation? cancellation,
  }) async {}
}
