import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';

import '../../support/cloze_session_harness.dart';

void main() {
  test(
    'production owner watch invalidates held generation across committed coalesced ABA',
    () async {
      final h = await ClozeSessionHarness.open();
      final probe = _OwnerSnapshotProbe();
      final generationEntered = Completer<void>();
      final releaseGeneration = Completer<void>();
      _WatchedOwner? scope;
      Future<Object?>? preparedOutcome;
      try {
        await h.database.runWithInterceptor(() async {
          scope = _WatchedOwner(_progress(h));
          await scope!.firstOwner.future.timeout(const Duration(seconds: 3));
          expect(scope!.ownerId, configuredOwnerId);
          final epoch = scope!.epoch;
          bool current() =>
              scope!.ownerId == configuredOwnerId && scope!.epoch == epoch;
          h.provider.beforeResponse = (_) async {
            generationEntered.complete();
            await releaseGeneration.future;
          };
          preparedOutcome = h.learning
              .prepareCloze(
                categoryId: configuredCategoryId,
                variant: ClozeVariant.typed,
                stillCurrent: current,
              )
              .then<Object?>(
                (value) => value,
                onError: (Object error) => error,
              );
          await generationEntered.future.timeout(const Duration(seconds: 3));
          expect(h.provider.transactionStates, [false]);
          expect(await h.storage.count('learning_sessions'), 0);

          probe.arm();
          await _commitOwner(h, configuredOtherOwnerId);
          await probe.held.future.timeout(const Duration(seconds: 3));
          expect(await _activeOwner(h), configuredOtherOwnerId);
          await _commitOwner(h, configuredOwnerId);
          expect(await _activeOwner(h), configuredOwnerId);
          probe.release();
          await probe.afterHeldRead.future.timeout(const Duration(seconds: 3));
          expect(probe.deferredOwnerId, configuredOwnerId);
          await Future<void>.delayed(Duration.zero);
          expect(
            scope!.observed,
            isNot(contains(configuredOtherOwnerId)),
            reason:
                'The executor seam must coalesce committed B before snapshot delivery',
          );
          releaseGeneration.complete();
          final outcome = await preparedOutcome!.timeout(
            const Duration(seconds: 3),
          );
          expect(
            outcome,
            isA<StateError>(),
            reason:
                'The original native launch must burn across committed ABA; actual delivered owner snapshots: ${scope!.observed}',
          );
          expect(await h.storage.count('learning_sessions'), 0);
          expect(await h.storage.count('answer_attempts'), 0);
        }, interceptor: probe);
      } finally {
        probe.release();
        if (!releaseGeneration.isCompleted) {
          releaseGeneration.complete();
        }
        if (preparedOutcome != null) {
          await preparedOutcome!.timeout(const Duration(seconds: 3));
        }
        await scope?.close();
        await h.close();
        await probe.closeReads();
      }
    },
  );

  test(
    'native coordinator no-op owner writes preserve normal launch answer and finish',
    () async {
      final h = await ClozeSessionHarness.open();
      final probe = _OwnerSnapshotProbe();
      _WatchedOwner? scope;
      try {
        await h.database.runWithInterceptor(() async {
          scope = _WatchedOwner(_progress(h));
          await scope!.firstOwner.future.timeout(const Duration(seconds: 3));
          final epoch = scope!.epoch;
          bool current() =>
              scope!.ownerId == configuredOwnerId && scope!.epoch == epoch;
          final prepared = (await h.learning.prepareCloze(
            categoryId: configuredCategoryId,
            variant: ClozeVariant.typed,
            stillCurrent: current,
          ))!;
          await _nativeNoOp(h);
          expect(await _activeOwner(h), configuredOwnerId);
          expect(current(), isTrue);
          final started = await h.learning.startNativeExercise(
            prepared,
            stillCurrent: current,
          );
          expect(identical(started, prepared), isTrue);
          await _nativeNoOp(h);
          expect(await _activeOwner(h), configuredOwnerId);
          expect(current(), isTrue);
          final answer = h.answer(prepared);
          await h.learning.commitNativeAnswer(
            prepared,
            answer,
            stillCurrent: current,
          );
          await _nativeNoOp(h);
          expect(await _activeOwner(h), configuredOwnerId);
          expect(current(), isTrue);
          final intent = h.learning.prepareNativeFinish(prepared, answer);
          final result = await h.learning.finishNativeExercise(
            intent,
            stillCurrent: current,
          );
          expect(result.state, 'completed');
          expect(result.correctCount, 1);
          expect(await h.storage.count('learning_sessions'), 1);
          expect(await h.storage.count('answer_attempts'), 1);
          expect(scope!.epoch, epoch);
        }, interceptor: probe);
      } finally {
        probe.release();
        await scope?.close();
        await h.close();
        await probe.closeReads();
      }
    },
  );
}

ProgressUseCases _progress(ClozeSessionHarness h) => ProgressUseCases(
  owners: h.storage.owners,
  queries: DriftProgressQueries(h.database),
  nowUtc: () => h.now,
);

Future<void> _nativeNoOp(ClozeSessionHarness h) =>
    h.storage.ownerWrites.writeForActiveOwner(
      expectedOwnerId: configuredOwnerId,
      write: () async {},
    );

Future<void> _commitOwner(ClozeSessionHarness h, String ownerId) =>
    h.database.transaction(() async {
      await h.database.customUpdate(
        'UPDATE local_owners SET is_active = (id = ?)',
        variables: [drift.Variable(ownerId)],
        updates: {h.database.localOwners},
      );
    });

Future<String> _activeOwner(ClozeSessionHarness h) async =>
    (await h.database
            .customSelect('SELECT id FROM local_owners WHERE is_active = 1')
            .getSingle())
        .read<String>('id');

final class _WatchedOwner {
  _WatchedOwner(ProgressUseCases progress) {
    subscription = progress.watchActiveOwnerId().listen(
      (value) {
        observed.add(value);
        if (value != ownerId) {
          epoch++;
          ownerId = value;
        }
        if (value != null && !firstOwner.isCompleted) {
          firstOwner.complete();
        }
      },
      onError: (Object _, StackTrace _) {
        epoch++;
        ownerId = null;
      },
      onDone: () {
        epoch++;
        ownerId = null;
      },
    );
  }
  late final StreamSubscription<String?> subscription;
  final firstOwner = Completer<void>();
  final observed = <String?>[];
  String? ownerId;
  int epoch = 0;
  Future<void> close() => subscription.cancel();
}

final class _OwnerSnapshotProbe extends drift.QueryInterceptor {
  final held = Completer<void>();
  final afterHeldRead = Completer<void>();
  final _release = Completer<void>();
  final _reads = StreamController<int>.broadcast(sync: true);
  bool armed = false;
  int readCount = 0;
  int? heldRead;
  String? deferredOwnerId;

  void arm() {
    armed = true;
  }

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  Future<void> closeReads() => _reads.close();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final sql = statement.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final ownerSnapshot =
        sql.contains('from "local_owners"') && sql.contains('limit 1');
    if (ownerSnapshot && armed && !_release.isCompleted) {
      if (heldRead == null) {
        heldRead = readCount + 1;
        held.complete();
      }
      await _release.future;
    }
    final rows = await executor.runSelect(statement, args);
    if (ownerSnapshot) {
      readCount++;
      if (armed && _release.isCompleted && !afterHeldRead.isCompleted) {
        deferredOwnerId = rows.isEmpty ? null : rows.single['id'] as String?;
        afterHeldRead.complete();
      }
      _reads.add(readCount);
    }
    return rows;
  }
}
