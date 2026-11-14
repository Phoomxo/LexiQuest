import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';

void main() {
  test('validates identifiers before delegating one upgrade', () async {
    final repository = _FakeOwnerUpgradeRepository();
    final upgrade = UpgradeGuestOwner(repository);

    expect(
      () => upgrade(activeOwnerId: ' ', firebaseUid: 'firebase-user'),
      throwsArgumentError,
    );
    expect(
      () => upgrade(activeOwnerId: 'guest-owner', firebaseUid: ' '),
      throwsArgumentError,
    );
    final result = await upgrade(
      activeOwnerId: ' guest-owner ',
      firebaseUid: ' firebase-user ',
    );

    expect(result.targetOwnerId, 'guest-owner');
    expect(repository.calls, 1);
    expect(repository.lastOwnerId, 'guest-owner');
    expect(repository.lastFirebaseUid, 'firebase-user');
  });

  group('v11 guest rehome', () {
    late AppDatabase db;
    late UpgradeGuestOwner upgrade;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      var sequence = 0;
      upgrade = UpgradeGuestOwner(
        DriftOwnerUpgradeRepository(
          db,
          nowUtc: () => _day.add(const Duration(days: 2)),
          generateConflictId: () => 'synthetic-merge-${sequence++}',
          generateOwnerId: () => 'replacement',
        ),
      );
      await db.customStatement(
        'INSERT INTO local_owners(id,firebase_uid,account_state,created_at_utc_ms,is_active) '
        "VALUES ('guest',NULL,'localGuest',1,1),('target','bound-uid','firebaseBound',1,0),"
        "('other','other-uid','firebaseBound',1,0)",
      );
    });
    tearDown(() => db.close());

    test(
      'two previously paid compatible periods retain both grants and freeze assets',
      () async {
        const definition =
            '{"cadence":"daily","criteria":{"correct":true},"target":5,"xpAmount":50}';
        final digest = sha256.convert(utf8.encode(definition)).toString();
        await db.customStatement(
          'INSERT INTO quest_definitions(quest_id,catalog_version,title,description,type,objectives_json,reward_json) '
          "VALUES ('synthetic-daily',1,'Synthetic','Five correct','daily','[]','{\"xpAmount\":50}')",
        );
        await db.customStatement(
          'INSERT INTO quest_definition_revisions VALUES (?,?,?,?)',
          ['synthetic-daily', 1, digest, definition],
        );
        for (final owner in ['guest', 'target']) {
          await _seedPaidPeriod(db, owner, digest);
        }
        await db.customStatement(
          "INSERT INTO points_ledger_entries VALUES ('other-points','other','other-source','learning',17,NULL,1)",
        );
        final before = await _state(db);
        final result = await upgrade(
          activeOwnerId: 'guest',
          firebaseUid: 'bound-uid',
        );
        expect(result.mode, OwnerUpgradeMode.mergedExisting);
        expect(result.targetOwnerId, 'target');
        final after = await _state(db);

        for (final (table, selector) in [
          ('owner_calendar_epochs', 'is_selected'),
          ('streak_baselines', 'controls_continuity'),
        ]) {
          expect(after[table], [
            for (final row in before[table]!)
              {
                ...row,
                'owner_id': 'target',
                selector: row['origin_owner_id'] == 'target' ? 1 : 0,
              },
          ], reason: table);
        }
        for (final table in [
          'answer_attempts',
          'quest_claim_receipts',
          'points_ledger_entries',
          'reward_transactions',
          'streak_token_adjustments',
        ]) {
          expect(after[table], [
            for (final row in before[table]!)
              {...row, if (row['owner_id'] == 'guest') 'owner_id': 'target'},
          ], reason: table);
        }
        expect(after['quest_instances'], [
          for (final row in before['quest_instances']!)
            {
              ...row,
              'owner_id': 'target',
              if (row['owner_id'] == 'guest') ...{
                'record_kind': 'alias',
                'canonical_instance_id': 'instance-target',
              },
            },
        ]);
        expect(
          after['quest_objective_progress'],
          before['quest_objective_progress'],
        );
        expect(
          after['quest_definition_revisions'],
          before['quest_definition_revisions'],
        );
        expect(after['quest_definitions'], before['quest_definitions']);
        // Exact pre-merge rows remain recoverable in the local conflict history.
        final archived = [
          for (final row in after['sync_conflicts']!)
            for (final key in ['local_snapshot_json', 'cloud_snapshot_json'])
              if (row[key] case final String json) jsonDecode(json),
        ];
        for (final table in ['learning_day_log', 'streak_states']) {
          for (final prior in before[table]!) {
            expect(
              [
                ...after[table]!,
                ...archived,
              ].any((entry) => _containsRawRow(entry, prior)),
              isTrue,
              reason: 'Lost raw $table row $prior',
            );
          }
          expect(after[table]!.map((r) => r['owner_id']), ['target']);
        }
        expect(
          after['points_ledger_entries']!
              .where((r) => r['owner_id'] == 'target')
              .fold<int>(0, (sum, row) => sum + (row['amount'] as int)),
          110,
        );
        expect((await DriftRewardRepository(db).load('target')).balance, 10);
        expect(after['events_v2'], isEmpty);
        expect(after['research_consents'], isEmpty);
        expect(
          after['outbox_operations']!.map((row) => row['entity_type']),
          everyElement(
            isIn([
              'category',
              'word',
              'attempt',
              'srsState',
              'achievementUnlock',
            ]),
          ),
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect(
          after['local_owners']!.singleWhere((r) => r['id'] == 'other'),
          before['local_owners']!.singleWhere((r) => r['id'] == 'other'),
        );

        final settled = await _state(db);
        final replay = await upgrade(
          activeOwnerId: 'target',
          firebaseUid: 'bound-uid',
        );
        expect(replay.mode, OwnerUpgradeMode.alreadyBound);
        expect(await _state(db), settled);
      },
    );

    test('conflicting Quest XP provenance aborts the whole merge', () async {
      // Isolate the invalid credit collision from valid calendar/period collisions.
      for (final owner in ['guest', 'target']) {
        await db.customStatement(
          'INSERT INTO points_ledger_entries '
          '(id,owner_id,idempotency_key,entry_type,amount,source_event_id,occurred_at_utc_ms) '
          "VALUES (?,?,?,'questClaimXpV1',?,?,?)",
          [
            'xp-$owner',
            owner,
            'quest-claim:one-key',
            owner == 'guest' ? 50 : 200,
            'receipt-$owner',
            _day.millisecondsSinceEpoch,
          ],
        );
      }
      final before = await _state(db);
      await expectLater(
        upgrade(activeOwnerId: 'guest', firebaseUid: 'bound-uid'),
        throwsA(isA<StateError>()),
      );
      expect(await _state(db), before);
    });

    test(
      'fresh target starts continuity without losing guest assets or history',
      () async {
        final digest = await _seedSyntheticDefinition(db);
        await _seedPaidPeriod(db, 'guest', digest);
        final before = await _state(db);
        expect(
          before['streak_states']!.where((row) => row['owner_id'] == 'target'),
          isEmpty,
        );
        await upgrade(activeOwnerId: 'guest', firebaseUid: 'bound-uid');
        final after = await _state(db);
        final state = after['streak_states']!.single;
        expect(state['owner_id'], 'target');
        expect(state['current_streak_days'], 0);
        expect(state['last_learned_at_utc_ms'], isNull);
        expect(state['longest_streak_days'], 9);
        final sourceBaseline = after['streak_baselines']!.singleWhere(
          (row) => row['origin_owner_id'] == 'guest',
        );
        expect(sourceBaseline, {
          ...before['streak_baselines']!.single,
          'owner_id': 'target',
          'controls_continuity': 0,
        });
        expect(after['owner_calendar_epochs'], [
          {
            ...before['owner_calendar_epochs']!.single,
            'owner_id': 'target',
            'is_selected': 0,
          },
        ]);
        for (final table in [
          'answer_attempts',
          'quest_claim_receipts',
          'points_ledger_entries',
          'reward_transactions',
          'streak_token_adjustments',
        ]) {
          expect(after[table], [
            for (final row in before[table]!) {...row, 'owner_id': 'target'},
          ], reason: table);
        }
        expect(
          after['quest_objective_progress'],
          before['quest_objective_progress'],
        );
        expect(
          after['quest_definition_revisions'],
          before['quest_definition_revisions'],
        );
        expect(after['quest_definitions'], before['quest_definitions']);
        expect(after['learning_day_log'], [
          {...before['learning_day_log']!.single, 'owner_id': 'target'},
        ]);
        expect((await DriftRewardRepository(db).load('target')).balance, 5);
        expect(after['events_v2'], isEmpty);
        expect(after['research_consents'], isEmpty);
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        final settled = await _state(db);
        expect(
          (await upgrade(
            activeOwnerId: 'target',
            firebaseUid: 'bound-uid',
          )).mode,
          OwnerUpgradeMode.alreadyBound,
        );
        expect(await _state(db), settled);
      },
    );

    test(
      'same-owner alias with different period pins rolls back the whole merge',
      () async {
        final digest = await _seedSyntheticDefinition(db);
        for (final owner in ['guest', 'target']) {
          await _seedPaidPeriod(db, owner, digest);
        }
        final nextDay = _day.add(const Duration(days: 1));
        await db.customStatement(
          'INSERT INTO quest_instances '
          '(instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,'
          'origin_owner_id,period_key,calendar_rule_id,civil_label,segments_json,'
          'definition_digest,canonical_instance_id,record_kind) '
          "SELECT 'bad-alias',quest_id,owner_id,catalog_version,?,'completed',"
          "origin_owner_id,'synthetic-wrong-day',calendar_rule_id,'2027-01-05',?,"
          "definition_digest,instance_id,'alias' FROM quest_instances "
          "WHERE instance_id='instance-guest'",
          [
            nextDay.millisecondsSinceEpoch,
            jsonEncode([
              [
                nextDay.microsecondsSinceEpoch,
                nextDay.add(const Duration(days: 1)).microsecondsSinceEpoch,
              ],
            ]),
          ],
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        final before = await _state(db);
        await expectLater(
          upgrade(activeOwnerId: 'guest', firebaseUid: 'bound-uid'),
          throwsA(isA<StateError>()),
        );
        expect(await _state(db), before);
      },
    );
  });
}

final _day = DateTime.utc(2027, 1, 4);

Future<String> _seedSyntheticDefinition(AppDatabase db) async {
  const definition =
      '{"cadence":"daily","criteria":{"correct":true},"target":5,"xpAmount":50}';
  final digest = sha256.convert(utf8.encode(definition)).toString();
  await db.customStatement(
    'INSERT INTO quest_definitions(quest_id,catalog_version,title,description,type,objectives_json,reward_json) '
    "VALUES ('synthetic-daily',1,'Synthetic','Five correct','daily','[]','{\"xpAmount\":50}')",
  );
  await db.customStatement(
    'INSERT INTO quest_definition_revisions VALUES (?,?,?,?)',
    ['synthetic-daily', 1, digest, definition],
  );
  return digest;
}

Future<Map<String, List<Map<String, Object?>>>> _state(AppDatabase db) async =>
    {
      for (final table in db.allTables)
        table.actualTableName: [
          for (final row
              in await db
                  .customSelect(
                    'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
                  )
                  .get())
            row.data,
        ],
    };

bool _containsRawRow(Object? entry, Map<String, Object?> row) {
  if (entry is Map) {
    if (row.entries.every(
      (field) =>
          entry.containsKey(field.key) && entry[field.key] == field.value,
    )) {
      return true;
    }
    return entry.values.any((value) => _containsRawRow(value, row));
  }
  return entry is List && entry.any((value) => _containsRawRow(value, row));
}

Future<void> _seedPaidPeriod(
  AppDatabase db,
  String owner,
  String digest,
) async {
  final at = _day.millisecondsSinceEpoch;
  final atUs = _day.microsecondsSinceEpoch;
  final segments = jsonEncode([
    [atUs, _day.add(const Duration(days: 1)).microsecondsSinceEpoch],
  ]);
  final first = at + (owner == 'guest' ? 100 : 200);
  final current = owner == 'guest' ? 6 : 3;
  final longest = owner == 'guest' ? 9 : 7;
  final tokens = owner == 'guest' ? 4 : 2;
  final period = '$owner:rule-$owner:daily:2027-01-04:synthetic-daily';
  await db.customStatement(
    'INSERT INTO owner_calendar_epochs(rule_id,owner_id,origin_owner_id,effective_utc_us,iana_id,tzdb_revision,is_selected) '
    "VALUES (?,?,?,?,'UTC','synthetic-release',1)",
    ['rule-$owner', owner, owner, atUs],
  );
  await db.customStatement('INSERT INTO streak_states VALUES (?,?,?,?,?,?)', [
    owner,
    current,
    longest,
    tokens,
    first,
    first,
  ]);
  await db.customStatement(
    'INSERT INTO streak_baselines VALUES (?,?,?,?,?,?,?,?,?)',
    [owner, owner, at + 1000, current, longest, tokens, first, first, 1],
  );
  await db.customStatement(
    "INSERT INTO learning_day_log VALUES (?,?, '2027-01-04',?)",
    ['day-$owner', owner, first],
  );
  await db.customStatement(
    "INSERT INTO streak_token_adjustments VALUES (?,?,?,?,?,'autoProtect',-1,'2027-01-05')",
    [
      'debit-$owner',
      owner,
      owner,
      'protect:2027-01-05',
      at + 2 * Duration.millisecondsPerDay,
    ],
  );

  await db.customStatement(
    'INSERT INTO vocabulary_categories(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) '
    'VALUES (?,?,?,?,?,?)',
    ['cat-$owner', owner, owner, owner, at, at],
  );
  await db.customStatement(
    'INSERT INTO vocabulary_words(id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) '
    "VALUES (?,?,?,?,?,'sample','sample','noun',?,?)",
    ['word-$owner', owner, 'cat-$owner', owner, owner, at, at],
  );
  await db.customStatement(
    'INSERT INTO learning_sessions(id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) '
    "VALUES (?,?,'quiz','active',?,'test','synthetic')",
    ['session-$owner', owner, at],
  );
  final evidence = <String>[];
  final learning = DriftLearningRepository(db);
  for (var i = 0; i < 5; i++) {
    final id = 'answer-$owner-$i';
    evidence.add(id);
    await learning.recordAnswer(
      RecordAnswerCommand(
        id: id,
        ownerId: owner,
        sessionId: 'session-$owner',
        wordId: 'word-$owner',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 10,
        attemptNumber: i + 1,
        occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
          first + i,
          isUtc: true,
        ),
      ),
    );
  }
  final json = jsonEncode(evidence);
  await db.customStatement(
    'INSERT INTO quest_instances(instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,'
    'completed_at_utc_ms,origin_owner_id,period_key,calendar_rule_id,civil_label,segments_json,definition_digest,record_kind) '
    "VALUES (?,'synthetic-daily',?,1,?,'completed',?,?,?,?,'2027-01-04',?,?,'canonical')",
    [
      'instance-$owner',
      owner,
      at,
      first + 4,
      owner,
      period,
      'rule-$owner',
      segments,
      digest,
    ],
  );
  await db.customStatement(
    "INSERT INTO quest_objective_progress VALUES (?,?,'correct',5,5,?)",
    ['objective-$owner', 'instance-$owner', json],
  );
  await db.customStatement(
    'INSERT INTO quest_claim_receipts VALUES (?,?,?,?,?,?,?,?)',
    [
      'receipt-$owner',
      owner,
      owner,
      'instance-$owner',
      first + 5,
      first + 4,
      50,
      json,
    ],
  );
  await db.customStatement(
    "INSERT INTO points_ledger_entries VALUES (?,?,?,'questClaimXpV1',50,?,?)",
    [
      'xp-$owner',
      owner,
      'quest-claim:receipt-$owner',
      'receipt-$owner',
      first + 5,
    ],
  );
}

final class _FakeOwnerUpgradeRepository implements OwnerUpgradeRepository {
  int calls = 0;
  String? lastOwnerId;
  String? lastFirebaseUid;

  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() {
    throw UnimplementedError();
  }

  @override
  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  }) async {
    calls += 1;
    lastOwnerId = activeOwnerId;
    lastFirebaseUid = firebaseUid;
    return OwnerUpgradeResult(
      targetOwnerId: activeOwnerId,
      mode: OwnerUpgradeMode.anonymousBound,
      conflictCount: 0,
    );
  }
}
