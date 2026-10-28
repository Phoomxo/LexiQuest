import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/preferences/application/display_preferences_controller.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/data/drift_learner_preferences_repository.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';

void main() {
  testWidgets('Thai glossary settings controls persist their exact actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final controller = DisplayPreferencesController(
        LearnerPreferencesUseCases(
          repository: DriftLearnerPreferencesRepository(database),
          owners: DriftLocalOwnerRepository(
            database,
            generateId: () => 'settings-owner',
            nowUtc: () => DateTime.utc(2026, 8, 30),
          ),
          nowUtc: () => DateTime.utc(2026, 8, 30, 12),
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingScreen(
            displayPreferences: controller,
            localDataEraser: _StaticLocalDataEraser(),
            localOwners: _StaticLocalOwners(),
          ),
        ),
      );

      expect(find.text('การแสดงผล'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('theme-system')),
        findsOneWidget,
      );
      expect(find.text('ระบบ'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('theme-light')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('theme-dark')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('reduced-motion-switch')),
        findsOneWidget,
      );
      expect(find.text('ลดการเคลื่อนไหว'), findsOneWidget);
      final eraseLocalData = find.byKey(
        const ValueKey<String>('erase-local-data'),
      );
      expect(eraseLocalData, findsOneWidget);
      expect(
        find.descendant(
          of: eraseLocalData,
          matching: find.byIcon(Icons.delete_forever_outlined),
        ),
        findsOneWidget,
      );
      expect(find.text('ลบข้อมูลในเครื่องทั้งหมด'), findsOneWidget);
      expect(find.text('Erase all local data'), findsNothing);
      expect(find.text('สถานะการเชื่อมต่อระบบออนไลน์'), findsOneWidget);
      expect(find.text('Cloud ไม่พร้อม'), findsNothing);
      expect(find.text('โหมดใช้งานในเครื่อง'), findsOneWidget);
      expect(find.textContaining('Guest'), findsNothing);
      for (final entryId in <String>[
        'theme-system',
        'theme-light',
        'theme-dark',
        'reduced-motion-switch',
        'erase-local-data',
      ]) {
        _expectSingleThaiGlossaryAction(
          action: find.byKey(ValueKey<String>(entryId)),
          entryId: entryId,
        );
      }

      await tester.tap(find.byKey(const ValueKey<String>('theme-dark')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('reduced-motion-switch')),
      );
      await tester.pumpAndSettle();

      expect(controller.themeMode, ThemeMode.dark);
      expect(controller.reducedMotionEnabled, isTrue);
      final row = await database
          .customSelect(
            'SELECT theme_mode, motion_mode FROM learner_preferences',
          )
          .getSingle();
      expect(row.read<String>('theme_mode'), 'dark');
      expect(row.read<String>('motion_mode'), 'reduced');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('f39 unavailable display authority fails closed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingScreen()));

    expect(find.byKey(const ValueKey<String>('theme-system')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('reduced-motion-switch')),
      findsNothing,
    );
  });

  testWidgets('Thai glossary authenticated logout copy has no Guest fallback', (
    tester,
  ) async {
    final account = AccountUseCases(
      gateway: _StaticAccountGateway(
        const AccountSession(
          uid: 'firebase-settings-owner',
          email: 'learner@example.com',
          isAnonymous: false,
          emailVerified: true,
        ),
      ),
      owners: _StaticLocalOwners(),
      upgradeGuestOwner: UpgradeGuestOwner(_StaticOwnerUpgradeRepository()),
      entryState: _StaticAppEntryStateStore(),
    );

    await tester.pumpWidget(MaterialApp(home: SettingScreen(account: account)));

    expect(find.text('learner@example.com'), findsOneWidget);
    expect(
      find.text('สร้างพื้นที่ใช้งานในเครื่องใหม่โดยไม่ลบข้อมูลบัญชี'),
      findsOneWidget,
    );
    expect(find.textContaining('Guest'), findsNothing);
  });
}

void _expectSingleThaiGlossaryAction({
  required Finder action,
  required String entryId,
}) {
  final entry = NavigationGlossary.require(entryId);
  final tooltip = find.ancestor(
    of: action,
    matching: find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.message == entry.tooltip,
    ),
  );
  expect(tooltip, findsOneWidget);
  expect(
    find.descendant(of: tooltip, matching: find.text(entry.fullThaiLabel)),
    findsOneWidget,
  );
  final semanticActions = find
      .ancestor(of: action, matching: find.byType(Semantics))
      .evaluate()
      .map((element) => element.widget)
      .whereType<Semantics>()
      .where(
        (semantics) =>
            semantics.properties.label == entry.semanticsLabel &&
            semantics.properties.onTap != null &&
            semantics.excludeSemantics,
      )
      .toList(growable: false);
  expect(semanticActions, hasLength(1));
}

final class _StaticLocalDataEraser implements LocalDataEraser {
  @override
  Future<int> eraseAll({required String ownerId}) async => 0;
}

final class _StaticLocalOwners implements LocalOwnerRepository {
  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'settings-static-owner',
        createdAtUtc: DateTime.utc(2026),
      );

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => throw UnimplementedError();
}

final class _StaticAccountGateway implements AccountGateway {
  const _StaticAccountGateway(this.currentSession);

  @override
  final AccountSession currentSession;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _StaticOwnerUpgradeRepository implements OwnerUpgradeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _StaticAppEntryStateStore implements AppEntryStateStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
