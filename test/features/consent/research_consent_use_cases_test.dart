import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/consent/domain/research_consent.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';

void main() {
  late db.AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late DriftResearchConsentRepository repository;
  late ResearchConsentUseCases consent;
  var nowUtc = DateTime.utc(2026, 7, 30, 12);

  setUp(() async {
    nowUtc = DateTime.utc(2026, 7, 30, 12);
    database = db.AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    repository = DriftResearchConsentRepository(database);
    consent = ResearchConsentUseCases(
      owners: owners,
      repository: repository,
      nowUtc: () => nowUtc,
    );
  });

  tearDown(() => database.close());

  test(
    'acceptance and withdrawal are versioned owner-scoped evidence',
    () async {
      expect((await consent.load()).accepted, isFalse);

      expect(await consent.accept(), isTrue);
      final accepted = await consent.load();
      expect(accepted.version, ResearchConsentUseCases.currentVersion);
      expect(accepted.accepted, isTrue);
      expect(accepted.decidedAtUtc, DateTime.utc(2026, 7, 30, 12));

      nowUtc = DateTime.utc(2026, 7, 30, 13);
      expect(await consent.withdraw(), isTrue);
      final withdrawn = await consent.load();
      expect(withdrawn.accepted, isFalse);
      expect(withdrawn.withdrawnAtUtc, DateTime.utc(2026, 7, 30, 13));

      nowUtc = DateTime.utc(2026, 7, 30, 14);
      expect(await consent.withdraw(), isFalse);
      final repeated = await consent.load();
      expect(repeated.decidedAtUtc, DateTime.utc(2026, 7, 30, 13));
      expect(repeated.withdrawnAtUtc, DateTime.utc(2026, 7, 30, 13));
      expect(
        await database.select(database.researchConsents).get(),
        hasLength(1),
      );
      expect(await database.select(database.eventsV2).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test('never-participant withdrawal creates no research artifacts', () async {
    expect(await consent.withdraw(), isFalse);
    expect(await consent.withdraw(), isFalse);

    final status = await consent.load();
    expect(status.accepted, isFalse);
    expect(status.decidedAtUtc, isNull);
    expect(status.withdrawnAtUtc, isNull);
    expect(await database.select(database.researchConsents).get(), isEmpty);
    expect(await database.select(database.eventsV2).get(), isEmpty);
    expect(await database.select(database.outboxOperations).get(), isEmpty);
  });

  test(
    'repeated acceptance is idempotent and keeps first decision time',
    () async {
      expect(await consent.accept(), isTrue);

      nowUtc = DateTime.utc(2026, 7, 30, 13);
      expect(await consent.accept(), isTrue);

      final status = await consent.load();
      expect(status.accepted, isTrue);
      expect(status.decidedAtUtc, DateTime.utc(2026, 7, 30, 12));
      expect(
        await database.select(database.researchConsents).get(),
        hasLength(1),
      );
      expect(await database.select(database.eventsV2).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'withdrawn consent cannot be accepted again at the same version',
    () async {
      expect(await consent.accept(), isTrue);
      nowUtc = DateTime.utc(2026, 7, 30, 13);
      expect(await consent.withdraw(), isTrue);

      nowUtc = DateTime.utc(2026, 7, 30, 14);
      expect(await consent.accept(), isFalse);

      final status = await consent.load();
      expect(status.accepted, isFalse);
      expect(status.decidedAtUtc, DateTime.utc(2026, 7, 30, 13));
      expect(status.withdrawnAtUtc, DateTime.utc(2026, 7, 30, 13));
      final rows = await database.select(database.researchConsents).get();
      expect(rows, hasLength(1));
      expect(rows.single.consentState, 'withdrawn');
      expect(await database.select(database.eventsV2).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'repository rejects decisions for inactive or undecided owners',
    () async {
      await consent.accept();
      await _activateOwner(database, 'local:b');

      expect(
        await repository.decide(
          ownerId: 'local:owner',
          version: ResearchConsentUseCases.currentVersion,
          accepted: true,
          decidedAtUtc: DateTime.utc(2026, 7, 30, 13),
        ),
        isFalse,
      );
      expect(
        await repository.decide(
          ownerId: 'local:b',
          version: ResearchConsentUseCases.currentVersion,
          accepted: false,
          decidedAtUtc: DateTime.utc(2026, 7, 30, 13),
        ),
        isFalse,
      );

      final rows = await database.select(database.researchConsents).get();
      expect(rows, hasLength(1));
      expect(rows.single.ownerId, 'local:owner');
      expect(rows.single.consentState, 'accepted');
    },
  );

  test('repository rejects a decision with multiple active owners', () async {
    await owners.getOrCreateActiveOwner();
    await database
        .into(database.localOwners)
        .insert(
          db.LocalOwnersCompanion.insert(
            id: 'local:b',
            createdAtUtcMs: DateTime.utc(2026, 7, 30).millisecondsSinceEpoch,
          ),
        );

    expect(
      await repository.decide(
        ownerId: 'local:owner',
        version: ResearchConsentUseCases.currentVersion,
        accepted: true,
        decidedAtUtc: DateTime.utc(2026, 7, 30, 13),
      ),
      isFalse,
    );
    expect(await database.select(database.researchConsents).get(), isEmpty);
  });

  test(
    'load rejects a result when the active owner changes in flight',
    () async {
      final delayed = _DelayedConsentRepository();
      final mutableOwners = _MutableOwners(_owner('owner-a'));
      final useCases = ResearchConsentUseCases(
        owners: mutableOwners,
        repository: delayed,
        nowUtc: () => nowUtc,
      );

      final pending = useCases.load();
      await delayed.started.future;
      mutableOwners.current = _owner('owner-b');
      delayed.result.complete(
        const ResearchConsentStatus(
          ownerId: 'owner-a',
          version: 1,
          accepted: true,
        ),
      );

      await expectLater(pending, throwsStateError);
    },
  );
}

Future<void> _activateOwner(db.AppDatabase database, String ownerId) {
  return database.transaction(() async {
    await database.customStatement(
      'UPDATE local_owners SET is_active = 0 WHERE is_active = 1',
    );
    await database
        .into(database.localOwners)
        .insert(
          db.LocalOwnersCompanion.insert(
            id: ownerId,
            createdAtUtcMs: DateTime.utc(2026, 7, 30).millisecondsSinceEpoch,
          ),
        );
  });
}

LocalOwner _owner(String id) =>
    LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 7, 30));

final class _MutableOwners implements LocalOwnerRepository {
  _MutableOwners(this.current);

  LocalOwner current;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => current;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _DelayedConsentRepository implements ResearchConsentRepository {
  final started = Completer<void>();
  final result = Completer<ResearchConsentStatus>();

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) {
    started.complete();
    return result.future;
  }

  @override
  Future<bool> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) => throw UnimplementedError();
}
