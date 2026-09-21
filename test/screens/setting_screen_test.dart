import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/domain/research_consent.dart';
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
  testWidgets('MCP theme action persists and erasure only opens confirmation', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final controller = DisplayPreferencesController(
      LearnerPreferencesUseCases(
        repository: DriftLearnerPreferencesRepository(database),
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'settings-owner',
          nowUtc: () => DateTime.utc(2026, 9, 21),
        ),
        nowUtc: () => DateTime.utc(2026, 9, 21),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final eraser = _StaticLocalDataEraser();
    final consentRepository = _ConsentRepository();
    final account = AccountUseCases(
      gateway: const _StaticAccountGateway(
        AccountSession(
          uid: 'test-account',
          email: 'private@example.test',
          isAnonymous: false,
          emailVerified: true,
        ),
      ),
      owners: _StaticLocalOwners(),
      upgradeGuestOwner: UpgradeGuestOwner(_StaticOwnerUpgradeRepository()),
      entryState: _StaticAppEntryStateStore(),
    );
    String? activeOwner = 'local:settings-owner';
    final registry = MenuActionRegistry(currentOwner: () => activeOwner);
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: MaterialApp(
          home: SettingScreen(
            account: account,
            researchConsent: ResearchConsentUseCases(
              owners: _StaticLocalOwners(),
              repository: consentRepository,
              nowUtc: () => DateTime.utc(2026, 9, 21),
            ),
            displayPreferences: controller,
            localDataEraser: eraser,
            localOwners: _StaticLocalOwners(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final result = registry.execute(
      id: 'theme-dark',
      owner: 'local:settings-owner',
      revision: registry.snapshot()['revision'] as int,
      requestId: 'theme',
    );
    await tester.pumpAndSettle();
    expect((await result)['status'], 'invoked');
    expect(controller.themeMode, ThemeMode.dark);
    for (final mode in [ThemeMode.light, ThemeMode.system, ThemeMode.dark]) {
      final changed = await registry.execute(
        id: 'theme-${mode.name}',
        owner: 'local:settings-owner',
        revision: registry.snapshot()['revision'] as int,
        requestId: 'mode-${mode.name}',
      );
      await tester.pumpAndSettle();
      expect(changed['status'], 'invoked');
      expect(controller.themeMode, mode);
    }
    for (final enabled in [true, false]) {
      await registry.execute(
        id: 'reduced-motion-switch',
        owner: 'local:settings-owner',
        revision: registry.snapshot()['revision'] as int,
        requestId: 'motion-$enabled',
      );
      await tester.pumpAndSettle();
      expect(controller.reducedMotionEnabled, enabled);
    }
    final context = registry.snapshot()['context'] as List;
    expect(
      context.map((row) => row['id']),
      containsAll([
        'settings/display',
        'settings/account',
        'settings/cloud-status',
      ]),
    );
    expect(context.toString(), isNot(contains('private@example.test')));
    final cloud = jsonDecode(
      context.singleWhere(
            (dynamic row) => row['id'] == 'settings/cloud-status',
          )['value']
          as String,
    );
    expect(cloud['firebaseAvailability'], 'unknown');
    expect(cloud['syncEngineConfigured'], false);
    expect(cloud['syncCompletion'], 'not-observed');
    activeOwner = 'different-owner';
    final otherContext = registry.snapshot()['context'] as List;
    expect(
      otherContext.where((dynamic row) => row['id'] == 'settings/display'),
      isEmpty,
    );
    final forbidden = await registry.execute(
      id: 'theme-light',
      owner: activeOwner,
      revision: registry.snapshot()['revision'] as int,
      requestId: 'wrong-owner-theme',
    );
    expect(forbidden['status'], isNot('invoked'));
    expect(controller.themeMode, ThemeMode.dark);
    activeOwner = 'local:settings-owner';
    for (final id in [
      'settings/change-password',
      'settings/research-consent',
    ]) {
      final opened = await registry.execute(
        id: id,
        owner: 'local:settings-owner',
        revision: registry.snapshot()['revision'] as int,
        requestId: id.replaceAll('/', '-'),
      );
      await tester.pumpAndSettle();
      expect(opened['status'], 'invoked');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(registry.snapshot()['actions'], isEmpty);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      expect(consentRepository.accepted, isFalse);
    }
    final snapshot = registry.snapshot();
    expect(
      (snapshot['actions'] as List).any((a) => a['id'] == 'settings/logout'),
      isFalse,
    );
    final erased = await registry.execute(
      id: 'erase-local-data',
      owner: 'local:settings-owner',
      revision: snapshot['revision'] as int,
      requestId: 'erase',
    );
    await tester.pumpAndSettle();
    expect(erased['status'], 'invoked');
    expect(find.text('ลบข้อมูลในเครื่องทั้งหมดหรือไม่?'), findsOneWidget);
    expect(eraser.calls, 0);
    expect(
      (registry.snapshot()['actions'] as List).any(
        (a) => a['id'] == 'erase-local-data',
      ),
      isFalse,
    );
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(controller.themeMode, ThemeMode.dark);
    expect(tester.takeException(), isNull);
    expect(eraser.calls, 0);
  });

  for (final readable in [true, false]) {
    testWidgets('uncertain consent write reconciles readable=$readable', (
      tester,
    ) async {
      final repository = _ConsentRepository()
        ..failAfterCommit = true
        ..failReadAfterCommit = !readable;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingScreen(
            researchConsent: ResearchConsentUseCases(
              owners: _StaticLocalOwners(),
              repository: repository,
              nowUtc: () => DateTime.utc(2026, 9, 8),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final details = find.byKey(const ValueKey('research-consent-details'));
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-research-export-consent')),
      );
      await tester.pumpAndSettle();
      expect(repository.decisions, [true]);
      expect(
        find.textContaining(
          readable ? 'ยินยอมฉบับ 1' : 'อ่านสถานะความยินยอมไม่ได้',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final outcome in ['success', 'partial', 'unreadable']) {
    testWidgets('local erasure reconciles consent after $outcome', (
      tester,
    ) async {
      final repository = _ConsentRepository()..accepted = true;
      final eraser = _ConsentClearingEraser(repository, outcome);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingScreen(
            localOwners: _StaticLocalOwners(),
            localDataEraser: eraser,
            researchConsent: ResearchConsentUseCases(
              owners: _StaticLocalOwners(),
              repository: repository,
              nowUtc: () => DateTime.utc(2026, 9, 8),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('ยินยอมฉบับ 1'), findsOneWidget);
      final erase = find.byKey(const ValueKey('erase-local-data'));
      await tester.ensureVisible(erase);
      await tester.tap(erase);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-local-erasure')));
      await tester.pumpAndSettle();
      expect(eraser.ownerIds, ['settings-static-owner']);
      expect(repository.decisions, isEmpty);
      expect(find.textContaining('ยินยอมฉบับ 1'), findsNothing);
      expect(
        find.textContaining(
          outcome == 'unreadable'
              ? 'อ่านสถานะความยินยอมไม่ได้'
              : 'ยังไม่ยินยอมส่งออกชุดวิจัย',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'consent stays disabled while loading and while a decision is pending',
    (tester) async {
      final repository = _ConsentRepository();
      final read = Completer<ResearchConsentStatus>();
      repository.pendingRead = read.future;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingScreen(
            researchConsent: ResearchConsentUseCases(
              owners: _StaticLocalOwners(),
              repository: repository,
              nowUtc: () => DateTime.utc(2026, 9, 8),
            ),
          ),
        ),
      );
      await tester.pump();
      final details = find.byKey(const ValueKey('research-consent-details'));
      expect(tester.widget<TextButton>(details).onPressed, isNull);
      expect(find.textContaining('กำลังอ่านสถานะความยินยอม'), findsOneWidget);
      read.complete(const ResearchConsentStatus(version: 1, accepted: false));
      repository.pendingRead = null;
      await tester.pumpAndSettle();
      await tester.ensureVisible(details);
      final open = tester.widget<TextButton>(details).onPressed!;
      open();
      open();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final write = Completer<void>();
      repository.pendingWrite = write.future;
      await tester.tap(
        find.byKey(const ValueKey('confirm-research-export-consent')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.widget<TextButton>(details).onPressed, isNull);
      expect(repository.accepted, isFalse);
      write.complete();
      await tester.pumpAndSettle();
      expect(repository.decisions, [true]);
      expect(tester.widget<TextButton>(details).onPressed, isNotNull);
    },
  );

  testWidgets(
    'research export consent requires details and explicit confirmation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final repository = _ConsentRepository();
        await tester.pumpWidget(
          MaterialApp(
            home: SettingScreen(
              researchConsent: ResearchConsentUseCases(
                owners: _StaticLocalOwners(),
                repository: repository,
                nowUtc: () => DateTime.utc(2026, 9, 8),
                consentVersion: 3,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final action = find.bySemanticsLabel(
          NavigationGlossary.require(
            'settings/research-consent',
          ).semanticsLabel,
        );
        await tester.ensureVisible(action);
        final data = tester.getSemantics(action).getSemanticsData();
        expect(data.value, contains('ยังไม่ยินยอม'));
        tester.semantics.performAction(
          find.semantics.byLabel(
            NavigationGlossary.require(
              'settings/research-consent',
            ).semanticsLabel,
          ),
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        expect(repository.decisions, isEmpty);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining('ไม่ใช่การสมัครเข้าร่วม'), findsOneWidget);
        expect(
          find.textContaining('หยุดการเก็บและส่งข้อมูลวิจัย'),
          findsOneWidget,
        );
        await tester.tap(find.text('ยกเลิก'));
        await tester.pumpAndSettle();
        expect(repository.decisions, isEmpty);
        tester.semantics.performAction(
          find.semantics.byLabel(
            NavigationGlossary.require(
              'settings/research-consent',
            ).semanticsLabel,
          ),
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('confirm-research-export-consent')),
        );
        await tester.pumpAndSettle();
        expect(repository.decisions, [true]);
        final accepted = tester.getSemantics(action).getSemanticsData();
        expect(accepted.value, contains('ฉบับ 3'));
        expect(accepted.value, contains('ถอน'));
        tester.semantics.performAction(
          find.semantics.byLabel(
            NavigationGlossary.require(
              'settings/research-consent',
            ).semanticsLabel,
          ),
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('confirm-research-export-consent')),
        );
        await tester.pumpAndSettle();
        expect(repository.decisions, [true, false]);
        expect(
          tester.getSemantics(action).getSemanticsData().value,
          contains('ยังไม่ยินยอม'),
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'unreadable consent is unavailable until retry and failed write stays unaccepted',
    (tester) async {
      final repository = _ConsentRepository()..failRead = true;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingScreen(
            researchConsent: ResearchConsentUseCases(
              owners: _StaticLocalOwners(),
              repository: repository,
              nowUtc: () => DateTime.utc(2026, 9, 8),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('ยังไม่ยินยอม ข้อมูลจะไม่ถูกส่งออกเป็นชุดวิจัย'),
        findsNothing,
      );
      final retry = find.byKey(const ValueKey('research-consent-retry'));
      expect(retry, findsOneWidget);
      repository.failRead = false;
      final retryRead = Completer<ResearchConsentStatus>();
      repository.pendingRead = retryRead.future;
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pump();
      expect(find.textContaining('กำลังอ่านสถานะความยินยอม'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('research-consent-details')),
            )
            .onPressed,
        isNull,
      );
      retryRead.complete(
        const ResearchConsentStatus(version: 1, accepted: false),
      );
      repository.pendingRead = null;
      await tester.pumpAndSettle();
      repository.failWrite = true;
      final details = find.byKey(const ValueKey('research-consent-details'));
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm-research-export-consent')),
      );
      await tester.pumpAndSettle();
      expect(repository.accepted, isFalse);
      expect(
        find.textContaining('กำลังตรวจสอบสถานะความยินยอมล่าสุด'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('local erasure confirmation explains both actions in Thai', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingScreen(
          localDataEraser: _StaticLocalDataEraser(),
          localOwners: _StaticLocalOwners(),
        ),
      ),
    );
    final erase = find.byKey(const ValueKey<String>('erase-local-data'));
    await tester.ensureVisible(erase);
    await tester.tap(erase);
    await tester.pumpAndSettle();
    expect(find.text('ลบข้อมูลในเครื่องทั้งหมดหรือไม่?'), findsOneWidget);
    expect(find.text('ยกเลิก'), findsOneWidget);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

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
  int calls = 0;
  @override
  Future<int> eraseAll({required String ownerId}) async {
    calls++;
    return 0;
  }
}

final class _ConsentClearingEraser implements LocalDataEraser {
  _ConsentClearingEraser(this.repository, this.outcome);

  final _ConsentRepository repository;
  final String outcome;
  final ownerIds = <String>[];

  @override
  Future<int> eraseAll({required String ownerId}) async {
    ownerIds.add(ownerId);
    repository.accepted = false;
    repository.failRead = outcome == 'unreadable';
    if (outcome != 'success') throw StateError('synthetic partial erase');
    return 1;
  }
}

final class _ConsentRepository implements ResearchConsentRepository {
  bool accepted = false;
  bool failRead = false;
  bool failWrite = false;
  bool failAfterCommit = false;
  bool failReadAfterCommit = false;
  final decisions = <bool>[];
  Future<ResearchConsentStatus>? pendingRead;
  Future<void>? pendingWrite;

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) async {
    if (failRead) throw StateError('synthetic read failure');
    if (pendingRead != null) return pendingRead!;
    return ResearchConsentStatus(version: version, accepted: accepted);
  }

  @override
  Future<void> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) async {
    if (failWrite) throw StateError('synthetic write failure');
    await pendingWrite;
    decisions.add(accepted);
    this.accepted = accepted;
    if (failAfterCommit) {
      failRead = failReadAfterCommit;
      throw StateError('synthetic acknowledgement failure');
    }
  }
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
