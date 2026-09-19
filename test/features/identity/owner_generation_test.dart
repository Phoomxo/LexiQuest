import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/application/owner_generation.dart';

void main() {
  test(
    'A to B to A invalidates a draft captured before any lease acquisition',
    () async {
      var owner = 'a';
      final generation = OwnerGeneration(activeOwnerId: () async => owner);
      final draft = await generation.capture();
      await generation.duringTransition(() async {
        owner = 'b';
      });
      await generation.duringTransition(() async {
        owner = 'a';
      });
      expect(() => generation.requireCurrent(draft), throwsStateError);
      generation.requireCurrent(await generation.capture());
    },
  );
  test(
    'capture across a transition is rejected even if final owner is unchanged',
    () async {
      final ownerRead = Completer<String>();
      final generation = OwnerGeneration(activeOwnerId: () => ownerRead.future);
      final capture = generation.capture();
      final rejected = expectLater(capture, throwsStateError);
      await generation.duringTransition(() async {});
      ownerRead.complete('a');
      await rejected;
    },
  );
  test(
    'failed transition invalidates earlier tokens and blocks capture until drained',
    () async {
      final generation = OwnerGeneration(activeOwnerId: () async => 'a');
      final before = await generation.capture();
      await expectLater(
        generation.duringTransition(() async {
          await expectLater(generation.capture(), throwsStateError);
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(() => generation.requireCurrent(before), throwsStateError);
      generation.requireCurrent(await generation.capture());
    },
  );
  test(
    'tokens from another runtime cannot authorize a restarted runtime',
    () async {
      final first = OwnerGeneration(activeOwnerId: () async => 'a');
      final second = OwnerGeneration(activeOwnerId: () async => 'a');
      final token = await first.capture();
      expect(() => second.requireCurrent(token), throwsStateError);
    },
  );
  test(
    'lifecycle adapter invalidates before running canonical owner transition',
    () async {
      final generation = OwnerGeneration(activeOwnerId: () async => 'a');
      final token = await generation.capture();
      final result = await generation.run(
        sourceOwnerId: 'a',
        operationToken: 'lease',
        operation: () async {
          expect(() => generation.requireCurrent(token), throwsStateError);
          return 'b';
        },
        targetOwnerId: (r) => r,
      );
      expect(result, 'b');
    },
  );
}
