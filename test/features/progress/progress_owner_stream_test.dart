import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  test(
    'same broadcast owner stream replays initial state to late listeners and cancels independently',
    () async {
      final h = await ConfiguredQuizHarness.open();
      _Watch? first;
      _Watch? second;
      try {
        final before = await h.snapshot();
        final source = _progress(h).watchActiveOwnerId();
        expect(source.isBroadcast, isTrue);
        first = _Watch(source);
        await first.waitFor((events) => events.isNotEmpty);
        expect(first.events, [configuredOwnerId]);
        second = _Watch(source);
        await second.waitFor((events) => events.isNotEmpty);
        expect(second.events, [configuredOwnerId]);
        expect(await h.snapshot(), before);

        await _commitOwner(h, configuredOtherOwnerId);
        await Future.wait([
          first.waitFor((events) => events.last == configuredOtherOwnerId),
          second.waitFor((events) => events.last == configuredOtherOwnerId),
        ]);
        expect(first.events, [configuredOwnerId, null, configuredOtherOwnerId]);
        expect(second.events, first.events);
        await _commitOwner(h, configuredOwnerId);
        await Future.wait([
          first.waitFor((events) => events.last == configuredOwnerId),
          second.waitFor((events) => events.last == configuredOwnerId),
        ]);
        expect(first.events, [
          configuredOwnerId,
          null,
          configuredOtherOwnerId,
          null,
          configuredOwnerId,
        ]);
        expect(second.events, first.events);
        expect(await h.snapshot(), before);

        final firstBeforeCancel = List<String?>.of(first.events);
        await first.cancel().timeout(const Duration(seconds: 3));
        await _commitOwner(h, configuredOtherOwnerId);
        await second.waitFor((events) => events.last == configuredOtherOwnerId);
        expect(first.events, firstBeforeCancel);
        final secondBeforeCancel = List<String?>.of(second.events);
        await second.cancel().timeout(const Duration(seconds: 3));
        await _commitOwner(h, configuredOwnerId);
        await pumpEventQueue();
        expect(first.events, firstBeforeCancel);
        expect(second.events, secondBeforeCancel);
        expect(await h.snapshot(), before);
      } finally {
        await Future.wait([
          if (first != null) first.cancel(),
          if (second != null) second.cancel(),
        ]).timeout(const Duration(seconds: 3));
        await h.close().timeout(const Duration(seconds: 3));
      }
    },
  );

  test(
    'actual database close completes with active owner watchers and forwards done',
    () async {
      final h = await ConfiguredQuizHarness.open();
      final source = _progress(h).watchActiveOwnerId();
      final first = _Watch(source);
      final second = _Watch(source);
      try {
        await Future.wait([
          first.waitFor((events) => events.isNotEmpty),
          second.waitFor((events) => events.isNotEmpty),
        ]);
        await h.close().timeout(const Duration(seconds: 3));
        await Future.wait([
          first.done.future,
          second.done.future,
        ]).timeout(const Duration(seconds: 3));
        await expectLater(
          h.database.customSelect('SELECT 1').getSingle(),
          throwsA(isA<StateError>()),
        );
      } finally {
        await Future.wait([
          first.cancel(),
          second.cancel(),
        ]).timeout(const Duration(seconds: 3));
        await h.close().timeout(const Duration(seconds: 3));
      }
    },
  );

  test(
    'cancelling both live subscriptions completes before database cleanup',
    () async {
      final h = await ConfiguredQuizHarness.open();
      final before = await h.snapshot();
      final source = _progress(h).watchActiveOwnerId();
      final first = _Watch(source);
      final second = _Watch(source);
      try {
        await Future.wait([
          first.waitFor((events) => events.isNotEmpty),
          second.waitFor((events) => events.isNotEmpty),
        ]);
        await Future.wait([
          first.cancel(),
          second.cancel(),
        ]).timeout(const Duration(seconds: 3));
        expect(await h.snapshot(), before);
        await h.close().timeout(const Duration(seconds: 3));
      } finally {
        await Future.wait([
          first.cancel(),
          second.cancel(),
        ]).timeout(const Duration(seconds: 3));
        await h.close().timeout(const Duration(seconds: 3));
      }
    },
  );
}

ProgressUseCases _progress(ConfiguredQuizHarness h) => ProgressUseCases(
  owners: h.owners,
  queries: DriftProgressQueries(h.database),
  nowUtc: () => h.now,
);

Future<void> _commitOwner(ConfiguredQuizHarness h, String ownerId) =>
    h.database.transaction(() async {
      await h.database.customUpdate(
        'UPDATE local_owners SET is_active = (id = ?)',
        variables: [drift.Variable(ownerId)],
        updates: {h.database.localOwners},
      );
    });

final class _Watch {
  _Watch(Stream<String?> source) {
    subscription = source.listen(
      (value) {
        events.add(value);
        _notify();
      },
      onError: (Object error, StackTrace _) {
        failure = error;
        _notify();
      },
      onDone: () {
        done.complete();
        _notify();
      },
    );
  }
  late final StreamSubscription<String?> subscription;
  final events = <String?>[];
  final done = Completer<void>();
  Completer<void> _next = Completer<void>();
  Object? failure;

  void _notify() {
    final previous = _next;
    _next = Completer<void>();
    previous.complete();
  }

  Future<void> waitFor(bool Function(List<String?>) predicate) async {
    while (!predicate(events)) {
      if (failure case final error?) {
        throw error;
      }
      if (done.isCompleted) {
        fail('Owner stream ended before the expected real snapshot');
      }
      await _next.future.timeout(const Duration(seconds: 3));
    }
  }

  Future<void> cancel() => subscription.cancel();
}
