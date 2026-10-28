import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';

void main() {
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
  String activeId = 'owner-a';
  bool failLookup = false;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    if (failLookup) throw StateError('synthetic owner lookup failure');
    return LocalOwner(id: activeId, createdAtUtc: DateTime.utc(2026, 8, 9));
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}
