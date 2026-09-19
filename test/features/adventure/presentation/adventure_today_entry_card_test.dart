import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_today_entry_card.dart';

void main() {
  testWidgets(
    'F03 failed Today entry is accessible and retryable with one opening',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var calls = 0;
        final pending = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdventureTodayEntryCard(
                onOpen: () async {
                  calls++;
                  if (calls == 1) {
                    await pending.future;
                    throw StateError('owner unavailable');
                  }
                },
              ),
            ),
          ),
        );
        final ink = find.byType(InkWell);
        final retainedTap = tester.widget<InkWell>(ink).onTap!;
        retainedTap();
        retainedTap();
        await tester.pump();
        expect(calls, 1);
        pending.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('เปิดภารกิจไม่ได้ในขณะนี้ แตะเพื่อลองอีกครั้ง'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('เปิดภารกิจไม่ได้ในขณะนี้')),
          findsOneWidget,
        );
        await tester.tap(ink);
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(
          find.text('เปิดภารกิจไม่ได้ในขณะนี้ แตะเพื่อลองอีกครั้ง'),
          findsNothing,
        );
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets('F03 pending Today entry can retire before failure', (
    tester,
  ) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdventureTodayEntryCard(onOpen: () => pending.future),
        ),
      ),
    );
    await tester.tap(find.byType(InkWell));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(StateError('late failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
