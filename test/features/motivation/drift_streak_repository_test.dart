import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/timezone_policy.dart';

const _createdMs = 1000;

void main() {
  late Directory directory;
  late File file;
  late AppDatabase database;
  late DriftStreakRepository repository;

  setUpAll(tz.initializeTimeZones);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'calendar-rule-authority-',
    );
    file = File('${directory.path}/synthetic.sqlite');
    database = _open(file);
    repository = DriftStreakRepository(database);
    await database.customStatement(
      'INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES (?,?,?),(?,?,?)',
      ['owner-a', _createdMs, 1, 'owner-b', _createdMs, 0],
    );
  });
  tearDown(() async {
    try {
      for (final table in [
        'learning_sessions',
        'answer_attempts',
        'streak_states',
        'learning_day_log',
        'points_ledger_entries',
        'reward_transactions',
        'quest_definitions',
        'quest_definition_revisions',
        'quest_instances',
        'quest_objective_progress',
        'quest_claim_receipts',
        'research_consents',
        'events_v2',
        'outbox_operations',
      ]) {
        expect(
          await database.customSelect('SELECT * FROM $table').get(),
          isEmpty,
          reason: 'calendar authority must not create $table rows',
        );
      }
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    } finally {
      await database.close();
      final root = Directory.systemTemp.absolute.path;
      expect(
        directory.absolute.path.startsWith('$root${Platform.pathSeparator}'),
        isTrue,
      );
      await directory.delete(recursive: true);
    }
  });

  test(
    'default UTC is durable once and starts at original owner creation',
    () async {
      final first = await repository.calendarRuleAt(
        ownerId: 'owner-a',
        occurredAtUtcMs: _createdMs,
      );
      expect(_value(first), (
        'calendar:utc-default:owner-a',
        'owner-a',
        'UTC',
        bundledTzdbRevision,
        _createdMs * 1000,
        null,
      ));
      final persisted = await _epochs(database);
      expect(persisted, hasLength(1));
      expect(persisted.single['owner_id'], 'owner-a');
      expect(persisted.single['is_selected'], 1);
      await database.close();
      database = _open(file);
      repository = DriftStreakRepository(database);
      final reopened = await repository.calendarRuleAt(
        ownerId: 'owner-a',
        occurredAtUtcMs: _createdMs + 100000,
      );
      expect(_value(reopened), _value(first));
      expect(await _epochs(database), persisted);
    },
  );

  test('concurrent default requests converge to one rule', () async {
    final rules = await Future.wait([
      repository.calendarRuleAt(
        ownerId: 'owner-a',
        occurredAtUtcMs: _createdMs,
      ),
      repository.calendarRuleAt(
        ownerId: 'owner-a',
        occurredAtUtcMs: _createdMs + 1,
      ),
    ]);
    expect(_value(rules[0]), _value(rules[1]));
    expect(await _epochs(database), hasLength(1));
  });

  test(
    'an outer rollback also removes a successfully resolved default',
    () async {
      await expectLater(
        database.transaction(() async {
          await repository.calendarRuleAt(
            ownerId: 'owner-a',
            occurredAtUtcMs: 1020,
          );
          expect(await _epochs(database), hasLength(1));
          throw StateError('synthetic answer rollback');
        }),
        throwsStateError,
      );
      expect(await _epochs(database), isEmpty);
    },
  );

  test(
    'a default provenance conflict leaves its outer transaction usable',
    () async {
      await database.transaction(() async {
        await _epoch(
          database,
          id: 'calendar:utc-default:owner-a',
          owner: 'owner-b',
          selected: false,
        );
        await expectLater(
          repository.calendarRuleAt(ownerId: 'owner-a', occurredAtUtcMs: 1020),
          throwsStateError,
        );
        await _epoch(
          database,
          id: 'valid-b',
          owner: 'owner-b',
          effectiveUs: _createdMs * 1000 + 1,
        );
      });
      final rows = await _epochs(database);
      expect(rows, hasLength(2));
      expect(rows.map((row) => row['owner_id']), everyElement('owner-b'));
    },
  );

  test(
    'selected rules stay owner-specific without replacing them with UTC',
    () async {
      await _epoch(database, id: 'bangkok-a', iana: 'Asia/Bangkok');
      await _epoch(database, id: 'utc-b', owner: 'owner-b');
      final before = await _epochs(database);
      final a = await repository.calendarRuleAt(
        ownerId: 'owner-a',
        occurredAtUtcMs: 1001,
      );
      final b = await repository.calendarRuleAt(
        ownerId: 'owner-b',
        occurredAtUtcMs: 1001,
      );
      expect(
        (a.ruleId, a.originOwnerId, a.ianaId),
        ('bangkok-a', 'owner-a', 'Asia/Bangkok'),
      );
      expect(
        (b.ruleId, b.originOwnerId, b.ianaId),
        ('utc-b', 'owner-b', 'UTC'),
      );
      expect(await _epochs(database), before);
    },
  );

  test(
    'stored milliseconds select across unrounded microsecond epoch bounds',
    () async {
      const boundaryUs = _createdMs * 1000 + 1500;
      await _epoch(database, id: 'before', expiresUs: boundaryUs);
      await _epoch(
        database,
        id: 'after',
        effectiveUs: boundaryUs,
        iana: 'Asia/Bangkok',
      );
      final before = await repository.calendarRuleAt(
        ownerId: 'owner-a',
        occurredAtUtcMs: 1001,
      );
      final after = await repository.calendarRuleAt(
        ownerId: 'owner-a',
        occurredAtUtcMs: 1002,
      );
      expect((before.ruleId, before.expiresUtcUs), ('before', boundaryUs));
      expect((after.ruleId, after.effectiveUtcUs), ('after', boundaryUs));
    },
  );

  test(
    'expiry is exclusive and the next effective instant is inclusive',
    () async {
      const boundaryMs = _createdMs + 10;
      await _epoch(database, id: 'before', expiresUs: boundaryMs * 1000);
      await _epoch(database, id: 'after', effectiveUs: boundaryMs * 1000);
      expect(
        (await repository.calendarRuleAt(
          ownerId: 'owner-a',
          occurredAtUtcMs: boundaryMs - 1,
        )).ruleId,
        'before',
      );
      expect(
        (await repository.calendarRuleAt(
          ownerId: 'owner-a',
          occurredAtUtcMs: boundaryMs,
        )).ruleId,
        'after',
      );
    },
  );

  for (final scenario in [
    'retired',
    'future',
    'gap',
    'overlap',
    'wrong-origin',
    'unknown-zone',
    'unsupported-tzdb',
  ]) {
    test(
      '$scenario authority fails closed without a default overlay',
      () async {
        switch (scenario) {
          case 'retired':
            await _epoch(database, id: 'retired', selected: false);
          case 'future':
            await _epoch(database, id: 'future', effectiveUs: 1050000);
          case 'gap':
            await _epoch(database, id: 'old', expiresUs: 1010000);
            await _epoch(database, id: 'future', effectiveUs: 1030000);
          case 'overlap':
            await _epoch(database, id: 'first', expiresUs: 1040000);
            await _epoch(database, id: 'second', effectiveUs: 1010000);
          case 'wrong-origin':
            await _epoch(
              database,
              id: 'wrong-origin',
              origin: 'synthetic-other-origin',
            );
          case 'unknown-zone':
            await _epoch(
              database,
              id: 'unknown-zone',
              iana: 'Synthetic/Unknown',
            );
          case 'unsupported-tzdb':
            await _epoch(
              database,
              id: 'old-tzdb',
              revision: 'synthetic-unavailable-tzdb',
            );
        }
        final before = await _epochs(database);
        await expectLater(
          repository.calendarRuleAt(ownerId: 'owner-a', occurredAtUtcMs: 1020),
          throwsStateError,
        );
        expect(await _epochs(database), before);
      },
    );
  }

  test(
    'merged target owns a new UTC rule while inherited guest rule stays inactive',
    () async {
      await _epoch(
        database,
        id: 'guest-history',
        origin: 'synthetic-former-guest',
        iana: 'Asia/Bangkok',
        selected: false,
      );
      final historical = (await _epochs(database)).single;
      final current = await repository.calendarRuleAt(
        ownerId: 'owner-a',
        occurredAtUtcMs: 1020,
      );
      expect(_value(current), (
        'calendar:utc-default:owner-a',
        'owner-a',
        'UTC',
        bundledTzdbRevision,
        _createdMs * 1000,
        null,
      ));
      final rows = await _epochs(database);
      expect(rows, hasLength(2));
      expect(
        rows.singleWhere((row) => row['rule_id'] == 'guest-history'),
        historical,
      );
    },
  );

  test('unknown owner cannot acquire a rule', () async {
    await expectLater(
      repository.calendarRuleAt(
        ownerId: 'missing-owner',
        occurredAtUtcMs: 1020,
      ),
      throwsStateError,
    );
    expect(await _epochs(database), isEmpty);
  });

  test(
    'a pre-creation occurrence cannot acquire retroactive default authority',
    () async {
      await expectLater(
        repository.calendarRuleAt(
          ownerId: 'owner-a',
          occurredAtUtcMs: _createdMs - 1,
        ),
        throwsStateError,
      );
      expect(await _epochs(database), isEmpty);
    },
  );
}

AppDatabase _open(File file) => AppDatabase(
  NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA foreign_keys = ON')),
);

(String, String, String, String, int, int?) _value(OwnerCalendarRule rule) => (
  rule.ruleId,
  rule.originOwnerId,
  rule.ianaId,
  rule.tzdbRevision,
  rule.effectiveUtcUs,
  rule.expiresUtcUs,
);

Future<List<Map<String, Object?>>> _epochs(AppDatabase database) async =>
    (await database
            .customSelect(
              'SELECT * FROM owner_calendar_epochs ORDER BY rule_id',
            )
            .get())
        .map((row) => row.data)
        .toList();

Future<void> _epoch(
  AppDatabase database, {
  required String id,
  String owner = 'owner-a',
  String? origin,
  int effectiveUs = _createdMs * 1000,
  int? expiresUs,
  String iana = 'UTC',
  String revision = bundledTzdbRevision,
  bool selected = true,
}) => database.customStatement(
  'INSERT INTO owner_calendar_epochs '
  '(rule_id,owner_id,origin_owner_id,effective_utc_us,expires_utc_us,iana_id,tzdb_revision,is_selected) '
  'VALUES (?,?,?,?,?,?,?,?)',
  [
    id,
    owner,
    origin ?? owner,
    effectiveUs,
    expiresUs,
    iana,
    revision,
    selected ? 1 : 0,
  ],
);
