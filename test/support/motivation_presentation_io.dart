import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Keep Flutter's fake microtask/error zones; only the deadline timer uses real time.
Future<T> motivationPresentationDeadline<T>(
  WidgetTester tester,
  String stage,
  Future<T> Function() operation,
) {
  final pending = operation();
  final deadlineZone = Zone.current.fork(
    specification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) =>
          Zone.root.createTimer(duration, callback),
    ),
  );
  return deadlineZone.run(
    () => pending.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        throw TimeoutException('M1 real deadline: $stage');
      },
    ),
  );
}

Future<T> motivationPresentationIo<T>(
  WidgetTester tester,
  Future<T> Function() operation, {
  String stage = 'motivation-io',
}) async {
  var done = false;
  T? value;
  Object? failure;
  StackTrace? stack;
  await motivationPresentationDeadline(
    tester,
    '$stage/dispatch',
    () => tester.runAsync(() async {
      unawaited(
        Future<T>.sync(operation).then<void>(
          (result) {
            value = result;
            done = true;
          },
          onError: (Object error, StackTrace trace) {
            failure = error;
            stack = trace;
            done = true;
          },
        ),
      );
    }),
  );
  for (var frame = 0; frame < 240 && !done; frame++) {
    await motivationPresentationDeadline(
      tester,
      '$stage/pump-$frame',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
    await motivationPresentationDeadline(
      tester,
      '$stage/io-$frame',
      () => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      ),
    );
  }
  if (!done) {
    fail('Motivation presentation IO did not finish within bounded frames');
  }
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
  return value as T;
}

Future<void> closeMotivationPresentation(
  WidgetTester tester,
  Future<void> Function() close,
) async {
  await motivationPresentationDeadline(
    tester,
    'close/unmount',
    () => tester.pumpWidget(const SizedBox.shrink()),
  );
  await motivationPresentationDeadline(
    tester,
    'close/drain-before',
    () => tester.pump(const Duration(milliseconds: 16)),
  );
  await motivationPresentationIo(tester, close, stage: 'close-resources');
  await motivationPresentationDeadline(
    tester,
    'close/drain-after',
    () => tester.pump(const Duration(milliseconds: 16)),
  );
}
