import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/managed_tutor_controller.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/managed_tutor_runtime.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_generation.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'support.dart';

// Real file-backed SQLite and canonical gate/generation; only the remote
// transport is controlled. Reopen is host durability, not native process death.
void main() {
  test(
    'durable lease and owner fence survive reopen; stale token cannot release successor',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      var gate = DriftOwnerOperationGate(f.db);
      final now = DateTime.utc(2026, 9, 24);
      const duration = Duration(minutes: 1);
      expect(
        await gate.tryAcquire(
          token: 'old',
          nowUtc: now,
          leaseDuration: duration,
        ),
        isTrue,
      );
      await gate.beginOwnerFence(ownerId: 'owner-a', token: 'old', nowUtc: now);
      final held = await f.snapshot();
      await f.reopen();
      expect(await f.snapshot(), held);
      gate = DriftOwnerOperationGate(f.db);
      expect(await gate.isOwned(token: 'old', nowUtc: now), isTrue);
      expect(await gate.isOwnerFenced(ownerId: 'owner-a', nowUtc: now), isTrue);
      expect(
        await gate.isOwnerFenced(ownerId: 'owner-b', nowUtc: now),
        isFalse,
      );
      expect(
        await gate.tryAcquire(
          token: 'new',
          nowUtc: now,
          leaseDuration: duration,
        ),
        isFalse,
      );
      final expiry = now.add(duration);
      expect(await gate.isOwned(token: 'old', nowUtc: expiry), isFalse);
      expect(
        await gate.isOwnerFenced(ownerId: 'owner-a', nowUtc: expiry),
        isFalse,
      );
      expect(
        await gate.renew(token: 'old', nowUtc: expiry, leaseDuration: duration),
        isFalse,
      );
      expect(
        await gate.tryAcquire(
          token: 'new',
          nowUtc: expiry,
          leaseDuration: duration,
        ),
        isTrue,
      );
      expect(
        await gate.isOwnerFenced(ownerId: 'owner-a', nowUtc: expiry),
        isFalse,
      );
      await gate.beginOwnerFence(
        ownerId: 'owner-a',
        token: 'new',
        nowUtc: expiry,
      );
      await gate.release(token: 'old');
      await gate.endOwnerFence(ownerId: 'owner-a', token: 'old');
      expect(await gate.isOwned(token: 'new', nowUtc: expiry), isTrue);
      expect(
        await gate.isOwnerFenced(ownerId: 'owner-a', nowUtc: expiry),
        isTrue,
      );
      await gate.endOwnerFence(ownerId: 'owner-a', token: 'new');
      await gate.release(token: 'new');
      final released = await f.snapshot();
      await f.reopen();
      expect(await f.snapshot(), released);
      expect(
        await DriftOwnerOperationGate(
          f.db,
        ).isOwned(token: 'new', nowUtc: expiry),
        isFalse,
      );
    },
  );

  for (final phase in ['connect', 'reply']) {
    test(
      'durable canonical generation cancels delayed $phase and requires explicit recovery',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        await DriftOwnerGeneration(f.db).advance();
        final initialGeneration = await DriftOwnerGeneration(f.db).read();
        await f.start();
        if (phase == 'reply') await f.connect();
        final work = phase == 'connect'
            ? f.runtime!.host.connect()
            : f.runtime!.host.controller.send('old request');
        await _until(
          () => phase == 'connect'
              ? f.transport.connections.isNotEmpty
              : f.transport.replies.isNotEmpty,
        );
        expect(await f.gateRow(), isNotNull);
        await f.db.transaction(() => DriftOwnerGeneration(f.db).advance());
        final generation = await DriftOwnerGeneration(f.db).read();
        expect(generation, isNot(initialGeneration));
        await _until(
          () =>
              f.runtime!.host.controller.state ==
              ManagedTutorState.disconnected,
        );
        await work;
        expect(f.transport.cancellations.last.isCancelled, isTrue);
        if (phase == 'connect') {
          f.transport.connections.last.complete();
        } else {
          f.transport.replies.last.complete(
            const AiGatewayReply(text: 'stale reply'),
          );
        }
        await pumpEventQueue();
        await _untilAsync(() async => await f.gateRow() == null);
        expect(f.runtime!.host.controller.messages, isEmpty);
        expect(f.runtime!.host.controller.replyText, isNull);
        final requests = f.transport.connections.length;
        await pumpEventQueue();
        expect(f.transport.connections.length, requests);
        await f.connect();
        expect(f.transport.connections.length, requests + 1);
        final reply = f.runtime!.host.controller.send('fresh request');
        final replyCount = phase == 'reply' ? 2 : 1;
        await _until(() => f.transport.replies.length == replyCount);
        f.transport.replies.last.complete(
          const AiGatewayReply(text: 'fresh reply'),
        );
        await reply;
        expect(f.runtime!.host.controller.replyText, 'fresh reply');
        await _untilAsync(() async => await f.gateRow() == null);
        await f.stop();
        final beforeReopen = await f.snapshot();
        await f.reopen();
        expect(await f.snapshot(), beforeReopen);
        expect(await DriftOwnerGeneration(f.db).read(), generation);
        await f.start();
        expect(f.runtime!.identity.value?.ownerId, 'owner-a');
        expect(
          f.runtime!.host.controller.state,
          ManagedTutorState.disconnected,
        );
        expect(f.runtime!.host.controller.messages, isEmpty);
        expect(f.transport.connections, isEmpty);
        expect(f.transport.replies, isEmpty);
        await f.runtime!.host.controller.send('must not auto resume');
        expect(f.transport.replies, isEmpty);
        await f.connect();
        expect(f.transport.connections, hasLength(1));
        expect(f.transport.bindings.single.ownerId, 'owner-a');
        expect(await f.snapshot(), beforeReopen);
      },
    );
  }

  for (final transition in ['account', 'owner', 'ambiguous']) {
    test(
      'file-backed $transition transition discards old reply and binds only canonical identity after reopen',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        await f.start();
        await f.connect();
        final work = f.runtime!.host.controller.send('old owner request');
        await _until(() => f.transport.replies.isNotEmpty);
        await f.db.transaction(() async {
          if (transition == 'account') {
            await f.db.customUpdate(
              "UPDATE local_owners SET firebase_uid = 'account-new' WHERE id = 'owner-a'",
              updates: {f.db.localOwners},
            );
          } else {
            if (transition == 'owner') {
              await f.db.customUpdate(
                'UPDATE local_owners SET is_active = 0',
                updates: {f.db.localOwners},
              );
            }
            await f.db
                .into(f.db.localOwners)
                .insert(
                  LocalOwnersCompanion.insert(id: 'owner-b', createdAtUtcMs: 2),
                );
          }
          await DriftOwnerGeneration(f.db).advance();
        });
        await _until(
          () =>
              f.runtime!.host.controller.state ==
              ManagedTutorState.disconnected,
        );
        await work;
        f.transport.replies.single.complete(
          const AiGatewayReply(text: 'wrong identity reply'),
        );
        await pumpEventQueue();
        expect(f.runtime!.host.controller.messages, isEmpty);
        expect(f.transport.cancellations.last.isCancelled, isTrue);
        if (transition == 'ambiguous') {
          expect(f.runtime!.identity.value, isNull);
          await f.runtime!.host.connect();
          expect(f.transport.connections, hasLength(1));
          await f.db.transaction(() async {
            await f.db.customUpdate(
              "UPDATE local_owners SET is_active = 0 WHERE id = 'owner-a'",
              updates: {f.db.localOwners},
            );
            await DriftOwnerGeneration(f.db).advance();
          });
          await _until(() => f.runtime!.identity.value?.ownerId == 'owner-b');
        }
        await _untilAsync(() async => await f.gateRow() == null);
        await f.stop();
        final snapshot = await f.snapshot();
        await f.reopen();
        expect(await f.snapshot(), snapshot);
        await f.start();
        expect(f.transport.connections, isEmpty);
        await f.connect();
        final binding = f.transport.bindings.single;
        expect(
          binding.ownerId,
          transition == 'account' ? 'owner-a' : 'owner-b',
        );
        expect(
          binding.accountId,
          transition == 'account' ? 'account-new' : 'owner-b',
        );
        expect(f.runtime!.host.controller.replyText, isNull);
        expect(await f.snapshot(), snapshot);
      },
    );
  }
}

Future<void> _until(bool Function() predicate) =>
    _untilAsync(() async => predicate());
Future<void> _untilAsync(Future<bool> Function() predicate) async {
  for (var i = 0; i < 200; i++) {
    if (await predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Observable condition did not settle within one second');
}

class _Fixture {
  _Fixture(this.directory, this.db);
  final Directory directory;
  AppDatabase db;
  ManagedTutorRuntime? runtime;
  TestTransport transport = TestTransport();
  static Future<_Fixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'ari-durable-runtime-',
    );
    final db = AppDatabase(
      NativeDatabase(File('${directory.path}/runtime.sqlite')),
    );
    await db
        .into(db.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-a', createdAtUtcMs: 1));
    return _Fixture(directory, db);
  }

  Future<void> start() async {
    transport = TestTransport();
    runtime = ManagedTutorRuntime(
      database: db,
      transport: transport,
      network: const Stream.empty(),
      clearSession: () async {},
    );
    await _until(() => runtime!.identity.value != null);
    await pumpEventQueue();
  }

  Future<void> connect() async {
    final count = transport.connections.length;
    final work = runtime!.host.connect();
    await _until(() => transport.connections.length == count + 1);
    transport.connections.last.complete();
    await work;
    expect(runtime!.host.controller.state, ManagedTutorState.ready);
  }

  Future<Object?> gateRow() async =>
      (await db
              .customSelect(
                "SELECT * FROM runtime_flags WHERE key = '${DriftOwnerOperationGate.gateKey}'",
              )
              .getSingleOrNull())
          ?.data;
  Future<Map<String, Object?>> snapshot() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    return {
      for (final table in tables)
        table.read<String>(
          'name',
        ): (await db
                .customSelect(
                  'SELECT * FROM "${table.read<String>('name')}" ORDER BY rowid',
                )
                .get())
            .map((r) => r.data)
            .toList(),
    };
  }

  Future<void> stop() async {
    await runtime?.dispose();
    runtime = null;
    await pumpEventQueue();
    await _untilAsync(() async => await gateRow() == null);
  }

  Future<void> reopen() async {
    await db.close();
    db = AppDatabase(NativeDatabase(File('${directory.path}/runtime.sqlite')));
  }

  Future<void> dispose() async {
    await stop();
    await db.close();
    await directory.delete(recursive: true);
  }
}
