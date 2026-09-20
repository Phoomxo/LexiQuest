import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/managed_tutor_panel.dart';
import 'support.dart';

void main() {
  testWidgets('offline retains unsent draft until owner disconnect', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ManagedTutorPanel(controller: h.controller)),
      ),
    );
    Future<void> connect() async {
      final work = h.controller.connect(ownerId: h.owner, accountId: 'a');
      await tester.pump();
      h.transport.connections.last.complete();
      await tester.pump();
      await work;
    }

    await connect();
    await tester.enterText(find.byType(TextField), 'bottle draft');
    h.controller.setOffline();
    await tester.pump();
    await connect();
    expect(find.text('bottle draft'), findsOneWidget);
    h.controller.ownerChanged();
    await tester.pump();
    await connect();
    expect(find.text('bottle draft'), findsNothing);
  });
  testWidgets(
    'panel integrates pending cancel, in-app reply, owner clear and no login',
    (tester) async {
      final h = Harness();
      addTearDown(h.controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ManagedTutorPanel(controller: h.controller)),
        ),
      );
      expect(find.text('อารี'), findsOneWidget);
      expect(find.textContaining('เข้าสู่ระบบ'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      final pending = h.controller.connect(
        ownerId: h.owner,
        accountId: 'account-a',
      );
      await tester.pump();
      expect(find.text('กำลังเตรียมการเชื่อมต่อ'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pump();
      await pending;
      expect(find.text('ยกเลิกแล้ว'), findsOneWidget);
      final connect = h.controller.connect(
        ownerId: h.owner,
        accountId: 'account-a',
      );
      await tester.pump(const Duration(milliseconds: 50));
      h.transport.connections.last.complete();
      await tester.pump();
      await connect;
      await tester.enterText(find.byType(TextField), 'bottle');
      await tester.tap(find.text('ส่ง'));
      await tester.pump();
      h.transport.replies.single.complete(
        const AiGatewayReply(text: 'A bottle holds water.'),
      );
      await tester.pump();
      expect(find.text('A bottle holds water.'), findsOneWidget);
      h.controller.ownerChanged();
      await tester.pump();
      expect(find.text('A bottle holds water.'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('account-a'), findsNothing);
    },
  );
  testWidgets('quota and provider errors show only fixed safe messages', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ManagedTutorPanel(controller: h.controller)),
      ),
    );
    final connect = h.controller.connect(
      ownerId: h.owner,
      accountId: 'account-a',
    );
    await tester.pump();
    h.transport.connections.last.complete();
    await tester.pump();
    await connect;
    final request = h.controller.send('bottle');
    await tester.pump();
    h.transport.replies.single.completeError(
      const AiTutorException(AiFailureCode.quota),
    );
    await tester.pump();
    await request;
    expect(find.text('โควตาหมด กรุณารอรอบถัดไป'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(h.transport.replies.length, 1);
  });
  testWidgets('replacing controller clears typed text across owners', (
    tester,
  ) async {
    final a = Harness();
    final b = Harness();
    addTearDown(a.controller.dispose);
    addTearDown(b.controller.dispose);
    Future<void> show(Harness h) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ManagedTutorPanel(controller: h.controller)),
      ),
    );
    await show(a);
    final connect = a.controller.connect(ownerId: a.owner, accountId: 'a');
    await tester.pump();
    a.transport.connections.last.complete();
    await tester.pump();
    await connect;
    await tester.enterText(find.byType(TextField), 'private draft');
    await show(b);
    final next = b.controller.connect(ownerId: b.owner, accountId: 'b');
    await tester.pump();
    b.transport.connections.last.complete();
    await tester.pump();
    await next;
    expect(find.text('private draft'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    b.controller.setOffline();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
