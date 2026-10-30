import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';

import '../../support/saved_word_owner_fixture.dart';

final _now = DateTime.utc(2026, 10, 29, 12);
const _key = 'delete:00000000-0000-4000-8000-000000000001';

void main() {
  group('legacy owner upgrade constructor honors persistent deletion intent', () {
    late AppDatabase database;
    late DriftOwnerWriteCoordinator coordinator;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await _seed(database);
      coordinator = _coordinator(database);
    });

    tearDown(() => database.close());

    for (final phase in [
      DeletionIntentPhase.preparing,
      DeletionIntentPhase.pendingCloud,
      DeletionIntentPhase.cloudConfirmed,
    ]) {
      test('$phase rejects even an already-bound source upgrade', () async {
        await _begin(coordinator, phase: phase);
        await _rejectUnchanged(
          database,
          () => _repository(
            database,
          ).upgrade(activeOwnerId: 'owner-a', firebaseUid: 'uid-a'),
        );
      });
    }

    test(
      'a fenced source cannot bind into a different Firebase namespace',
      () async {
        await _begin(coordinator);
        await _rejectUnchanged(
          database,
          () => _repository(
            database,
          ).upgrade(activeOwnerId: 'owner-a', firebaseUid: 'uid-new'),
        );
      },
    );

    test('a fenced inactive target cannot receive a guest merge', () async {
      await _activate(database, 'owner-b');
      await _begin(coordinator, ownerId: 'owner-b', firebaseUid: 'uid-b');
      await _activate(database, 'guest-source');

      await _rejectUnchanged(
        database,
        () => _repository(
          database,
        ).upgrade(activeOwnerId: 'guest-source', firebaseUid: 'uid-b'),
      );
    });

    test(
      'logout cannot deactivate a fenced source or create another guest',
      () async {
        await _begin(coordinator);
        await _rejectUnchanged(
          database,
          () => _repository(database).createLocalGuestAfterLogout(),
        );
      },
    );

    test('logout checks every active owner it would deactivate', () async {
      await _begin(coordinator);
      await database.customStatement(
        "UPDATE local_owners SET is_active = 1 WHERE id = 'guest-source'",
      );
      await _rejectUnchanged(
        database,
        () => _repository(database).createLocalGuestAfterLogout(),
      );
    });

    test('merge cannot deactivate another active fenced owner', () async {
      await _begin(coordinator);
      await database.customStatement(
        "UPDATE local_owners SET is_active = 1 WHERE id = 'guest-source'",
      );
      await _rejectUnchanged(
        database,
        () => _repository(
          database,
        ).upgrade(activeOwnerId: 'guest-source', firebaseUid: 'uid-b'),
      );
    });

    test('rollback cannot reactivate a fenced previous owner', () async {
      await _begin(coordinator);
      await _activate(database, 'guest-source');
      await _rejectUnchanged(
        database,
        () => _repository(database).rollbackLocalGuestLogout(
          previousOwnerId: 'owner-a',
          guestOwnerId: 'guest-source',
        ),
      );
    });

    for (final action in ['upgrade', 'logout', 'rollback']) {
      test('cloud-confirmed replacement guest rejects $action', () async {
        final token = await _begin(
          coordinator,
          phase: DeletionIntentPhase.cloudConfirmed,
        );
        final local = await DriftLocalAccountDeletionGateway(
          database,
          nowUtc: () => _now,
          purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {},
        ).deleteAfterCloud(ownerId: 'owner-a', cloudReceipt: _cloud());
        expect(token.matchesOwner(local.newGuestOwnerId), isFalse);

        await _rejectUnchanged(
          database,
          () => _perform(
            _repository(database),
            action,
            activeOwnerId: local.newGuestOwnerId,
            previousOwnerId: 'owner-b',
          ),
        );
      });
    }

    test('logout cannot reserve the pending deletion replacement ID', () async {
      await _begin(coordinator, phase: DeletionIntentPhase.cloudConfirmed);
      await _activate(database, 'guest-source');
      final replacement = _replacementGuestOwnerId(_cloud());

      await _rejectUnchanged(
        database,
        () => _repository(
          database,
          generateOwnerId: () => replacement.substring('local:'.length),
        ).createLocalGuestAfterLogout(),
      );
    });

    for (final action in ['upgrade', 'logout', 'rollback']) {
      test(
        'corrupt persistent intent rejects $action before changing owners',
        () async {
          await _begin(coordinator);
          await _activate(database, 'guest-source');
          final row = await database.select(database.runtimeFlags).getSingle();
          await database.customStatement(
            'UPDATE runtime_flags SET source = ? WHERE key = ?',
            ['not-json', row.key],
          );

          await _rejectUnchanged(
            database,
            () => _perform(
              _repository(database),
              action,
              activeOwnerId: 'guest-source',
            ),
          );
        },
      );
    }

    test(
      'unbound recovery uncertainty rejects all owner mutation paths',
      () async {
        await _activate(database, 'guest-source');
        await coordinator.preserveRecoveryUncertainty();

        for (final action in ['upgrade', 'logout', 'rollback']) {
          await _rejectUnchanged(
            database,
            () => _perform(
              _repository(database),
              action,
              activeOwnerId: 'guest-source',
            ),
          );
        }
      },
    );

    test(
      'unrelated owners retain bind, logout, rollback and ordinary writes',
      () async {
        await _begin(coordinator);
        await _activate(database, 'guest-source');
        final repository = _repository(database);
        final bound = await repository.upgrade(
          activeOwnerId: 'guest-source',
          firebaseUid: 'uid-new',
        );
        expect(bound.mode, OwnerUpgradeMode.anonymousBound);
        final guest = await repository.createLocalGuestAfterLogout();
        await repository.rollbackLocalGuestLogout(
          previousOwnerId: bound.targetOwnerId,
          guestOwnerId: guest.targetOwnerId,
        );
        await database.customStatement(
          'INSERT INTO vocabulary_categories '
          '(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
          "VALUES ('ordinary-learning', 'owner-a', 'ordinary', 'ordinary', 1, 1)",
        );

        final active = await (database.select(
          database.localOwners,
        )..where((row) => row.isActive.equals(true))).getSingle();
        expect(active.id, 'guest-source');
        expect(active.firebaseUid, 'uid-new');
        expect(
          await (database.select(database.vocabularyCategories)
                ..where((row) => row.id.equals('ordinary-learning')))
              .getSingleOrNull(),
          isNotNull,
        );
        await expectLater(
          coordinator.requireOwnerUnfenced('owner-a'),
          throwsA(isA<AccountDeletionException>()),
        );
      },
    );
  });

  group('independent owner repositories', () {
    late _FileDatabases fixture;

    setUp(() async => fixture = await _FileDatabases.open());
    tearDown(() => fixture.close());

    test(
      'a reopened default repository honors another connection intent',
      () async {
        await _begin(_coordinator(fixture.first));
        await fixture.reopenFirst();
        await _rejectUnchanged(
          fixture.second,
          () => _repository(
            fixture.second,
          ).upgrade(activeOwnerId: 'owner-a', firebaseUid: 'uid-a'),
        );
        await _rejectUnchanged(
          fixture.first,
          () => _repository(fixture.first).createLocalGuestAfterLogout(),
        );
      },
    );

    test('a separate repository honors an inactive target intent', () async {
      await _activate(fixture.first, 'owner-b');
      await _begin(
        _coordinator(fixture.first),
        ownerId: 'owner-b',
        firebaseUid: 'uid-b',
      );
      await _activate(fixture.first, 'guest-source');
      await fixture.reopenFirst();

      await _rejectUnchanged(
        fixture.second,
        () => _repository(
          fixture.second,
        ).upgrade(activeOwnerId: 'guest-source', firebaseUid: 'uid-b'),
      );
    });

    test(
      'upgrade rechecks deletion after an independent transaction commits',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        final before = await _snapshot(fixture.second);
        final held = fixture.first.transaction(() async {
          await _begin(_coordinator(fixture.first));
          started.complete();
          await release.future;
        });

        try {
          await Future.any<void>([started.future, held]);
          fixture.interceptor.handoff = () async {
            release.complete();
            await held;
          };
          await expectLater(
            _repository(
              fixture.second,
            ).upgrade(activeOwnerId: 'owner-a', firebaseUid: 'uid-b'),
            throwsA(isA<AccountDeletionException>()),
          );
          expect(fixture.interceptor.didHandoff, isTrue);
          final after = await _snapshot(fixture.second);
          expect(after['local_owners'], before['local_owners']);
          for (final table in ownerUpgradeInventory) {
            expect(after[table], before[table], reason: table);
          }
        } finally {
          if (!release.isCompleted) release.complete();
          await held;
        }
      },
    );
  });
}

DriftOwnerUpgradeRepository _repository(
  AppDatabase database, {
  String Function()? generateOwnerId,
}) => DriftOwnerUpgradeRepository(
  database,
  nowUtc: () => _now,
  generateConflictId: () => 'synthetic-upgrade-conflict',
  generateOwnerId: generateOwnerId ?? () => 'synthetic-new-guest',
);

DriftOwnerWriteCoordinator _coordinator(AppDatabase database) =>
    DriftOwnerWriteCoordinator(database, nowUtc: () => _now);

Future<DeletionIntentToken> _begin(
  DriftOwnerWriteCoordinator coordinator, {
  String ownerId = 'owner-a',
  String firebaseUid = 'uid-a',
  DeletionIntentPhase phase = DeletionIntentPhase.pendingCloud,
}) async {
  final token = await coordinator.beginDeletion(
    ownerId: ownerId,
    firebaseUid: firebaseUid,
    idempotencyKey: _key,
  );
  if (phase != DeletionIntentPhase.preparing) {
    await coordinator.markPending(token);
  }
  if (phase == DeletionIntentPhase.cloudConfirmed) {
    await coordinator.markCloud(token, _cloud());
  }
  return token;
}

CloudDeletionReceipt _cloud() => CloudDeletionReceipt(
  receiptId: 'synthetic-cloud-receipt',
  ownerId: 'owner-a',
  firebaseUid: 'uid-a',
  idempotencyKey: durableAccountDeletionBinding(_key),
  completedAtUtc: _now,
);

String _replacementGuestOwnerId(CloudDeletionReceipt cloud) =>
    'local:deleted:${sha256.convert(utf8.encode(jsonEncode([cloud.ownerId, cloud.firebaseUid, cloud.idempotencyKey, cloud.receiptId])))}';

Future<void> _perform(
  DriftOwnerUpgradeRepository repository,
  String action, {
  required String activeOwnerId,
  String previousOwnerId = 'owner-a',
}) async {
  switch (action) {
    case 'upgrade':
      await repository.upgrade(
        activeOwnerId: activeOwnerId,
        firebaseUid: 'uid-b',
      );
    case 'logout':
      await repository.createLocalGuestAfterLogout();
    case 'rollback':
      await repository.rollbackLocalGuestLogout(
        previousOwnerId: previousOwnerId,
        guestOwnerId: activeOwnerId,
      );
    default:
      throw ArgumentError.value(action, 'action');
  }
}

Future<void> _rejectUnchanged(
  AppDatabase database,
  Future<dynamic> Function() operation,
) async {
  final before = await _snapshot(database);
  await expectLater(operation(), throwsA(isA<AccountDeletionException>()));
  expect(await _snapshot(database), before);
}

Future<Map<String, List<String>>> _snapshot(AppDatabase database) async {
  final result = <String, List<String>>{};
  for (final table in {
    ...ownerUpgradeInventory,
    'local_owners',
    'runtime_flags',
  }) {
    final rows = await database.customSelect('SELECT * FROM $table').get();
    result[table] = rows.map((row) => jsonEncode(row.data)).toList()..sort();
  }
  return result;
}

Future<void> _activate(AppDatabase database, String ownerId) => database
    .customStatement('UPDATE local_owners SET is_active = (id = ?)', [ownerId]);

Future<void> _seed(AppDatabase database) async {
  await database.customStatement('PRAGMA foreign_keys = ON');
  await database.customStatement(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, is_active, created_at_utc_ms) VALUES '
    "('owner-a', 'uid-a', 'firebaseBound', 1, 1), "
    "('owner-b', 'uid-b', 'firebaseBound', 0, 2), "
    "('guest-source', NULL, 'localGuest', 0, 3)",
  );
  for (final owner in ['owner-a', 'owner-b', 'guest-source']) {
    await database.customStatement(
      'INSERT INTO vocabulary_categories '
      '(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
      'VALUES (?, ?, ?, ?, 1, 1)',
      ['category-$owner', owner, owner, owner],
    );
    await database.customStatement(
      'INSERT INTO outbox_operations '
      '(operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms) '
      "VALUES (?, ?, 'category', ?, 'upsert', 1)",
      ['operation-$owner', owner, 'category-$owner'],
    );
    await insertOwnerSavedWord(
      database,
      owner,
      categoryId: 'category-$owner',
      isSaved: owner != 'guest-source',
    );
  }
}

final class _FileDatabases {
  _FileDatabases(
    this.directory,
    this.ownedPath,
    this.file,
    this.first,
    this.second,
    this.interceptor,
  );

  final Directory directory;
  final String ownedPath;
  final File file;
  AppDatabase first;
  final AppDatabase second;
  final _TransactionHandoff interceptor;

  static Future<_FileDatabases> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-upgrade-fence-',
    );
    final ownedPath = await directory.resolveSymbolicLinks();
    final file = File('${directory.path}${Platform.pathSeparator}test.sqlite');
    final first = _open(file);
    final interceptor = _TransactionHandoff();
    final second = _open(file, interceptor: interceptor);
    final result = _FileDatabases(
      directory,
      ownedPath,
      file,
      first,
      second,
      interceptor,
    );
    try {
      await _seed(first);
      await second
          .customSelect('SELECT COUNT(*) FROM local_owners')
          .getSingle();
      return result;
    } catch (_) {
      await result.close();
      rethrow;
    }
  }

  static AppDatabase _open(File file, {_TransactionHandoff? interceptor}) {
    final executor = NativeDatabase.createInBackground(
      file,
      setup: (database) {
        database.execute('PRAGMA foreign_keys = ON');
        database.execute('PRAGMA busy_timeout = 5000');
        database.execute('PRAGMA journal_mode = WAL');
      },
    );
    return AppDatabase(
      interceptor == null ? executor : executor.interceptWith(interceptor),
    );
  }

  Future<void> reopenFirst() async {
    await first.close();
    first = _open(file);
  }

  Future<void> close() async {
    await second.close();
    await first.close();
    if (!await directory.exists()) return;
    final target = await directory.resolveSymbolicLinks();
    final parent = await Directory.systemTemp.resolveSymbolicLinks();
    final separator = Platform.pathSeparator;
    final prefix =
        '$parent${parent.endsWith(separator) ? '' : separator}lexiquest-upgrade-fence-';
    if (target != ownedPath ||
        !target.startsWith(prefix) ||
        Directory(target).parent.path != parent) {
      throw StateError('refusing to remove an unowned temporary directory');
    }
    await Directory(target).delete(recursive: true);
  }
}

final class _TransactionHandoff extends drift.QueryInterceptor {
  Future<void> Function()? handoff;
  var didHandoff = false;

  @override
  Future<bool> ensureOpen(
    drift.QueryExecutor executor,
    drift.QueryExecutorUser user,
  ) async {
    final next = handoff;
    if (next == null || executor is! drift.TransactionExecutor) {
      return executor.ensureOpen(user);
    }
    handoff = null;
    final opening = executor.ensureOpen(user);
    didHandoff = true;
    final results = await Future.wait<bool>([
      opening,
      next().then((_) => true),
    ]);
    return results.first;
  }
}
