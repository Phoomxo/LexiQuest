import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'motivation_presentation_io.dart';

void main() {
  testWidgets(
    'deadline retains the test scheduler across nested real IO and the next frame',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) => Scaffold(
              body: FilledButton(
                onPressed: () => update(() => taps++),
                child: Text('Synthetic taps: $taps'),
              ),
            ),
          ),
        ),
      );
      debugPrint('Deadline driver: before nested flow');
      await motivationPresentationDeadline(
        tester,
        'driver/nested-flow',
        () async {
          for (var frame = 0; frame < 2; frame++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1)),
            );
            await motivationPresentationDeadline(
              tester,
              'driver/nested-pump-$frame',
              () => tester.pump(),
            );
          }
        },
      );
      debugPrint('Deadline driver: before next frame');
      await motivationPresentationDeadline(
        tester,
        'driver/next-frame',
        () => tester.pump(),
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.text('Synthetic taps: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugPrint('Deadline driver: completed next frame and tap');
    },
  );

  testWidgets('deadline errors stay catchable in the caller test error zone', (
    tester,
  ) async {
    final failure = StateError('Synthetic operation failure');
    await expectLater(
      motivationPresentationDeadline<int>(
        tester,
        'driver/failure',
        () => Future<int>.error(failure),
      ),
      throwsA(same(failure)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'deadline replay of a completed future preserves the next tester pump',
    (tester) async {
      final completed = Completer<int>()..complete(7);
      await tester.pump();
      expect(await completed.future, 7);
      debugPrint('Deadline driver: before completed-future replay');
      expect(
        await motivationPresentationDeadline(
          tester,
          'driver/completed-replay',
          () => completed.future,
        ),
        7,
      );
      await tester.pumpWidget(
        const MaterialApp(home: Text('Synthetic replay ready')),
      );
      await tester.pump();
      expect(find.text('Synthetic replay ready'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugPrint('Deadline driver: completed replay and next pump');
    },
  );

  testWidgets(
    'deadline does not replace simulated animation time with wall time',
    (tester) async {
      var elapsed = false;
      final pending = Future<void>.delayed(const Duration(seconds: 2), () {
        elapsed = true;
      });
      await motivationPresentationDeadline(
        tester,
        'driver/simulated-time',
        () async {
          await tester.pump(const Duration(seconds: 1));
          expect(elapsed, isFalse);
          await tester.pump(const Duration(seconds: 1));
          await pending;
        },
      );
      expect(elapsed, isTrue);
      await tester.pump();
    },
  );
}
