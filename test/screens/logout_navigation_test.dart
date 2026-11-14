import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  for (final failure in [false, true]) {
    testWidgets(
      failure
          ? 'failed logout restores A after Back during the provider wait'
          : 'successful logout clears visible A after Back during the provider wait',
      (tester) async {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var stage = 'create fixture';
        void mark(String next) {
          stage = next;
        }

        mark(stage);
        final fixture = await _real(tester, stage, _Fixture.create);
        try {
          mark('snapshot A before UI');
          final before = await _real(tester, stage, fixture.snapshotA);
          mark('pump app');
          await tester.pumpWidget(MyApp(dependencies: fixture.dependencies));
          mark('select library');
          await tester.tap(
            find.widgetWithText(NavigationDestination, 'คลังคำศัพท์'),
          );
          await _pumpUntil(
            tester,
            () => find.text('private set A').evaluate().isNotEmpty,
          );
          mark('library ready');
          final shell = tester.element(find.byType(MainNavigationScreen));
          expect(AppDependenciesScope.of(shell), same(fixture.dependencies));

          await tester.tap(
            find.byKey(const ValueKey<String>('shell-drawer-button')),
          );
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 3),
          );
          await tester.scrollUntilVisible(
            find.text('ตั้งค่า'),
            200,
            scrollable: find.descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            ),
          );
          mark('open settings');
          await tester.tap(find.text('ตั้งค่า'));
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 3),
          );
          await tester.scrollUntilVisible(
            find.text('ออกจากระบบ'),
            250,
            scrollable: find
                .descendant(
                  of: find.byType(SettingScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          mark('start logout');
          await tester.tap(find.text('ออกจากระบบ'));
          await _pumpUntil(tester, () => fixture.gateway.started.isCompleted);
          mark('provider started after guest commit');
          final guest = await _real(tester, stage, fixture.activeOwner);
          final guestId = guest['id']! as String;
          expect(guestId, isNot(fixture.ownerA));
          expect(guest['firebase_uid'], isNull);

          mark('Back while provider pending');
          await tester.binding.handlePopRoute();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(AppDependenciesScope.of(shell), same(fixture.dependencies));
          mark('finish provider');
          fixture.gateway.finish(failure: failure);
          if (failure) {
            mark('wait for rollback SQL snapshot');
            var restored = false;
            for (var attempt = 0; attempt < 50; attempt++) {
              await tester.pump(const Duration(milliseconds: 20));
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await tester.pump();
              final owner = await _real(tester, stage, fixture.activeOwner);
              if (owner['id'] == fixture.ownerA) {
                restored = true;
                break;
              }
            }
            expect(restored, isTrue, reason: 'Failed logout must restore A');
          } else {
            mark('wait for actual login');
            await _pumpUntil(
              tester,
              () => find.byType(LoginScreen).evaluate().isNotEmpty,
            );
          }
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 3),
          );

          mark('snapshot A after provider');
          final after = await _real(tester, stage, fixture.snapshotA);
          expect(after, before);
          await _real(tester, 'guest data has no writes', () async {
            await fixture.expectNoGuestWrites(guestId);
            return true;
          });
          if (failure) {
            expect(
              (await _real(
                tester,
                'read restored owner',
                fixture.activeOwner,
              ))['id'],
              fixture.ownerA,
            );
            expect(
              await _real(
                tester,
                'read deleted guest',
                () => fixture.ownerRows(guestId),
              ),
              0,
            );
            if (find.byType(SettingScreen).evaluate().isNotEmpty) {
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle(
                const Duration(milliseconds: 100),
                EnginePhase.sendSemanticsUpdate,
                const Duration(seconds: 3),
              );
            }
            expect(find.byType(LoginScreen), findsNothing);
            expect(find.text('private set A'), findsOneWidget);
          } else {
            expect(
              (await _real(
                tester,
                'read current guest',
                fixture.activeOwner,
              ))['id'],
              guestId,
            );
            mark('assert logout navigation');
            expect(find.text('private set A'), findsNothing);
            expect(find.textContaining('private-word-a'), findsNothing);
            expect(find.byType(LoginScreen), findsOneWidget);
            expect(
              find.byType(MainNavigationScreen, skipOffstage: false),
              findsNothing,
            );
            expect(
              tester
                  .state<NavigatorState>(find.byType(Navigator).first)
                  .canPop(),
              isFalse,
            );
          }
          expect(tester.takeException(), isNull);
        } catch (error) {
          debugPrint('logout fixture primary failure at $stage: $error');
          rethrow;
        } finally {
          mark('cleanup drain UI');
          fixture.gateway.finish(failure: false);
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          mark('cleanup close database');
          var closed = false;
          Object? closeError;
          final closing = fixture.database.close();
          unawaited(
            closing.then<void>(
              (_) => closed = true,
              onError: (Object error, StackTrace _) {
                closeError = error;
                closed = true;
              },
            ),
          );
          for (var attempt = 0; attempt < 100 && !closed; attempt++) {
            await tester.pump();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(
            closed,
            isTrue,
            reason: 'Database close must finish after UI drain',
          );
          if (closeError != null) {
            debugPrint('logout fixture database close error: $closeError');
          }
          await closing;
          mark('cleanup done');
        }
      },
    );
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('Timed out waiting for the synthetic production logout journey');
}

Future<T> _real<T>(
  WidgetTester tester,
  String stage,
  Future<T> Function() operation,
) async {
  final result = await tester.runAsync(() async {
    try {
      return (value: await operation().timeout(const Duration(seconds: 3)));
    } catch (error) {
      debugPrint('logout fixture real-zone failure at $stage: $error');
      rethrow;
    }
  });
  if (result == null) throw StateError('Real-zone operation failed at $stage');
  return result.value;
}

final class _Fixture {
  _Fixture(
    this.database,
    this.owners,
    this.gateway,
    this.dependencies,
    this.ownerA,
  );
  final AppDatabase database;
  final DriftLocalOwnerRepository owners;
  final _Gateway gateway;
  final AppDependencies dependencies;
  final String ownerA;

  static Future<_Fixture> create() async {
    final database = AppDatabase(NativeDatabase.memory());
    var sequence = 0;
    final now = DateTime.utc(2026, 11, 14);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-owner-${++sequence}',
      nowUtc: () => now,
    );
    final owner = await owners.getOrCreateActiveOwner();
    await owners.bindFirebaseUid(owner.id, 'synthetic-uid-a');
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'synthetic-vocabulary-${++sequence}',
      nowUtc: () => now,
    );
    final category = await vocabulary.createCategory('private set A');
    await vocabulary.createWord(
      CreateWordCommand(
        categoryId: category.id,
        spelling: 'private-word-a',
        meaning: 'คำสังเคราะห์ของ A',
        partOfSpeech: 'noun',
      ),
    );
    final gateway = _Gateway();
    final account = AccountUseCases(
      gateway: gateway,
      owners: owners,
      upgradeGuestOwner: UpgradeGuestOwner(
        DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => now,
          generateConflictId: () => 'synthetic-conflict-${++sequence}',
          generateOwnerId: () => 'synthetic-guest-${++sequence}',
        ),
      ),
    );
    final dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.ready,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _Guest(),
      database: database,
      localOwners: owners,
      vocabulary: vocabulary,
      account: account,
    );
    return _Fixture(database, owners, gateway, dependencies, owner.id);
  }

  Future<Map<String, Object>> snapshotA() async => {
    for (final table in [
      'vocabulary_categories',
      'vocabulary_words',
      'outbox_operations',
    ])
      table: [
        for (final row
            in await database
                .customSelect(
                  'SELECT * FROM $table WHERE owner_id = ?',
                  variables: [Variable<String>(ownerA)],
                )
                .get())
          row.data,
      ],
  };

  Future<void> expectNoGuestWrites(String guestId) async {
    for (final table in [
      'vocabulary_categories',
      'vocabulary_words',
      'learning_sessions',
      'answer_attempts',
      'outbox_operations',
    ]) {
      final row = await database
          .customSelect(
            'SELECT COUNT(*) AS n FROM $table WHERE owner_id = ?',
            variables: [Variable<String>(guestId)],
          )
          .getSingle();
      expect(
        row.read<int>('n'),
        0,
        reason: 'No synthetic guest write in $table',
      );
    }
  }

  Future<Map<String, dynamic>> activeOwner() async =>
      (await database
              .customSelect(
                'SELECT id, firebase_uid FROM local_owners WHERE is_active = 1',
              )
              .getSingle())
          .data;

  Future<int> ownerRows(String id) async =>
      (await database
              .customSelect(
                'SELECT COUNT(*) AS n FROM local_owners WHERE id = ?',
                variables: [Variable<String>(id)],
              )
              .getSingle())
          .read<int>('n');
}

final class _Gateway extends Fake implements AccountGateway {
  @override
  AccountSession? currentSession = const AccountSession(
    uid: 'synthetic-uid-a',
    email: 'a@example.test',
    isAnonymous: false,
    emailVerified: true,
  );
  final started = Completer<void>();
  final _release = Completer<void>();

  @override
  Future<void> signOut() async {
    started.complete();
    await _release.future;
    currentSession = null;
  }

  void finish({required bool failure}) {
    if (_release.isCompleted) return;
    if (failure) {
      _release.completeError(
        const AccountException(AccountFailureCode.network),
      );
    } else {
      _release.complete();
    }
  }
}

final class _Guest extends Fake implements GuestSessionService {}
