import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  for (final stage in ['lookup', 'dialog', 'recheck']) {
    for (final change in ['eraser', 'owners', 'tab', 'route', 'lifecycle']) {
      testWidgets('BJ $change retires erasure during $stage', (tester) async {
        final nav = GlobalKey<NavigatorState>();
        final original = _FakeLocalDataEraser();
        final replacement = _FakeLocalDataEraser();
        var eraser = original;
        var owners = _FakeLocalOwners();
        var visible = true;
        Widget app() => MaterialApp(
          navigatorKey: nav,
          home: TickerMode(
            enabled: visible,
            child: SettingScreen(localDataEraser: eraser, localOwners: owners),
          ),
        );
        final pending = Completer<LocalOwner>();
        if (stage == 'lookup') owners.pending = pending;
        await tester.pumpWidget(app());
        await tester.tap(
          find.byKey(const ValueKey<String>('erase-local-data')),
        );
        await tester.pumpAndSettle();
        VoidCallback? confirm;
        if (stage != 'lookup') {
          confirm = tester
              .widget<FilledButton>(
                find.byKey(const ValueKey<String>('confirm-local-erasure')),
              )
              .onPressed!;
        }
        if (stage == 'recheck') {
          owners.pending = pending;
          confirm!();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
        switch (change) {
          case 'eraser':
            eraser = replacement;
          case 'owners':
            owners = _FakeLocalOwners();
          case 'tab':
            visible = false;
          case 'route':
            nav.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('other route')),
              ),
            );
          case 'lifecycle':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
        }
        await tester.pumpWidget(app());
        await tester.pump(const Duration(milliseconds: 300));
        // Retained callbacks must not pop a replacement route or authorize erasure.
        if (stage == 'dialog') confirm!();
        if (stage != 'dialog') {
          pending.complete(
            LocalOwner(id: 'owner-a', createdAtUtc: DateTime.utc(2026)),
          );
        }
        await tester.pump();
        if (change == 'lifecycle') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await tester.pumpAndSettle();
        expect(original.ownerIds, isEmpty);
        expect(replacement.ownerIds, isEmpty);
        expect(
          find.byKey(const ValueKey<String>('confirm-local-erasure')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        if (change == 'route') {
          expect(find.text('other route'), findsOneWidget);
          nav.currentState!.pop();
        }
        visible = true;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('erase-local-data')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm-local-erasure')),
        );
        await tester.pumpAndSettle();
        expect(eraser.ownerIds, ['owner-a']);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final failLookup in [false, true]) {
    testWidgets('erasure contains lookup failure or cancellation failLookup=$failLookup', (tester) async {
      final eraser = _FakeLocalDataEraser();
      final owners = _FakeLocalOwners()..failLookup = failLookup;
      await tester.pumpWidget(MaterialApp(home: SettingScreen(localDataEraser: eraser, localOwners: owners)));
      await tester.tap(find.byKey(const ValueKey<String>('erase-local-data')));
      await tester.pumpAndSettle();
      if (!failLookup) {
        await tester.tap(find.text('ยกเลิก'));
        await tester.pumpAndSettle();
      }
      expect(eraser.ownerIds, isEmpty);
      expect(tester.takeException(), isNull);
      // A cancelled/failed attempt does not leave the action permanently busy.
      owners.failLookup = false;
      await tester.tap(find.byKey(const ValueKey<String>('erase-local-data')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('confirm-local-erasure')), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
    });
  }

  for (final finish in ['cancel', 'confirm']) {
    testWidgets('BJ $finish retires callbacks before a fresh confirmation', (
      tester,
    ) async {
      final eraser = _FakeLocalDataEraser();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingScreen(
            localDataEraser: eraser,
            localOwners: _FakeLocalOwners(),
          ),
        ),
      );
      final oldEntry = tester
          .widget<ListTile>(
            find.byKey(const ValueKey<String>('erase-local-data')),
          )
          .onTap!;
      oldEntry();
      await tester.pumpAndSettle();
      final oldConfirm = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('confirm-local-erasure')),
          )
          .onPressed!;
      if (finish == 'cancel') {
        await tester.tap(find.text('ยกเลิก'));
      } else {
        oldConfirm();
      }
      await tester.pumpAndSettle();
      oldEntry();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('erase-local-data')));
      await tester.pumpAndSettle();
      oldConfirm();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(eraser.ownerIds.length, finish == 'cancel' ? 0 : 1);
      await tester.tap(
        find.byKey(const ValueKey<String>('confirm-local-erasure')),
      );
      await tester.pumpAndSettle();
      expect(eraser.ownerIds.length, finish == 'cancel' ? 1 : 2);
      expect(tester.takeException(), isNull);
    });
  }

  for (final stage in ['lookup', 'recheck']) {
    testWidgets('BJ disposal during $stage never dispatches erasure', (
      tester,
    ) async {
      final eraser = _FakeLocalDataEraser();
      final owners = _FakeLocalOwners();
      final pending = Completer<LocalOwner>();
      if (stage == 'lookup') owners.pending = pending;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingScreen(localDataEraser: eraser, localOwners: owners),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('erase-local-data')));
      await tester.pumpAndSettle();
      if (stage == 'recheck') {
        owners.pending = pending;
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm-local-erasure')),
        );
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox());
      pending.complete(
        LocalOwner(id: 'owner-a', createdAtUtc: DateTime.utc(2026)),
      );
      await tester.pumpAndSettle();
      expect(eraser.ownerIds, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stale confirmation never erases the replacement owner', (
    tester,
  ) async {
    final eraser = _FakeLocalDataEraser();
    final owners = _FakeLocalOwners();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingScreen(localDataEraser: eraser, localOwners: owners),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('erase-local-data')));
    await tester.pumpAndSettle();
    owners.activeId = 'owner-b';
    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-local-erasure')),
    );
    await tester.pumpAndSettle();
    expect(eraser.ownerIds, isEmpty);
    expect(tester.takeException(), isNull);
    expect(find.text('ลบข้อมูลในเครื่องแล้ว'), findsNothing);
  });
  testWidgets('confirmed local erasure uses the active owner', (tester) async {
    final eraser = _FakeLocalDataEraser();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingScreen(
          localDataEraser: eraser,
          localOwners: _FakeLocalOwners(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('erase-local-data')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-local-erasure')),
    );
    await tester.pumpAndSettle();

    expect(eraser.ownerIds, ['owner-a']);
    expect(find.text('ลบข้อมูลในเครื่องแล้ว'), findsOneWidget);
  });
}

final class _FakeLocalDataEraser implements LocalDataEraser {
  final List<String> ownerIds = [];

  @override
  Future<int> eraseAll({required String ownerId}) async {
    ownerIds.add(ownerId);
    return 7;
  }
}

final class _FakeLocalOwners implements LocalOwnerRepository {
  Completer<LocalOwner>? pending;
  String activeId = 'owner-a';
  bool failLookup = false;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    final wait = pending;
    pending = null;
    if (wait != null) return wait.future;
    if (failLookup) throw StateError('synthetic owner lookup failure');
    return LocalOwner(id: activeId, createdAtUtc: DateTime.utc(2026, 8, 9));
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}
