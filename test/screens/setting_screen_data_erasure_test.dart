import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';

void main() {
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
    expect(find.text('Local data erased.'), findsOneWidget);
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
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: 'owner-a', createdAtUtc: DateTime.utc(2026, 8, 9));

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}
