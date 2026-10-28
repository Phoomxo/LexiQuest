import 'dart:async';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:vocab_learning_app/features/consent/domain/research_consent.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';

void main() {
  late AppDatabase database;
  late ResearchConsentUseCases consent;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    consent = ResearchConsentUseCases(
      owners: owners,
      repository: DriftResearchConsentRepository(database),
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
    );
  });

  tearDown(() => database.close());

  test(
    'withdraw and reaccept without a permit creates no denial outbox',
    () async {
      var clock = DateTime.utc(2026, 7, 30, 12);
      consent = ResearchConsentUseCases(
        owners: consent.owners,
        repository: consent.repository,
        nowUtc: () => clock,
      );
      await consent.accept();
      clock = clock.add(const Duration(seconds: 1));
      await consent.withdraw();
      expect((await consent.load()).accepted, isFalse);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
      clock = clock.add(const Duration(seconds: 1));
      await consent.accept();
      expect((await consent.load()).accepted, isTrue);
      expect(
        await database.select(database.researchParticipationPermits).get(),
        isEmpty,
      );
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'configured consent version and committed withdrawal notify sync without making a queue error a consent failure',
    () async {
      final states = <bool>[];
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'owner',
        nowUtc: () => DateTime.utc(2026, 7, 30),
      );
      final repository = DriftResearchConsentRepository(database);
      consent = ResearchConsentUseCases(
        owners: owners,
        repository: repository,
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
        consentVersion: 2,
        onLocalMutation: (ownerId) async {
          states.add(
            (await repository.load(ownerId: ownerId, version: 2)).accepted,
          );
          throw StateError('synthetic queue unavailable');
        },
      );
      await consent.accept();
      expect((await consent.load()).version, 2);
      await consent.withdraw();
      expect((await consent.load()).accepted, isFalse);
      expect(states, [true, false]);
      expect(
        (await database.select(database.researchConsents).get())
            .single
            .consentVersion,
        2,
      );
    },
  );

  test(
    'acceptance and withdrawal are versioned owner-scoped evidence',
    () async {
      expect((await consent.load()).accepted, isFalse);

      await consent.accept();
      final accepted = await consent.load();
      expect(accepted.version, ResearchConsentUseCases.currentVersion);
      expect(accepted.accepted, isTrue);
      expect(accepted.decidedAtUtc, DateTime.utc(2026, 7, 30, 12));

      await consent.withdraw();
      final withdrawn = await consent.load();
      expect(withdrawn.accepted, isFalse);
      expect(withdrawn.withdrawnAtUtc, DateTime.utc(2026, 7, 30, 12));
      expect(
        await database.select(database.researchConsents).get(),
        hasLength(1),
      );
    },
  );

  for (final accepted in [false, true]) {
    test('F05 stale consent owner is rejected accepted=$accepted', () async {
      final owner = await consent.owners.getOrCreateActiveOwner();
      final now = DateTime.utc(2026, 7, 30, 12);
      await consent.accept();
      await database.into(database.localOwners).insert(
        LocalOwnersCompanion.insert(id: 'other', isActive: const Value(false),
          createdAtUtcMs: now.millisecondsSinceEpoch));
      final deferred = _DeferredConsentRepository(consent.repository);
      var notified = false;
      final pendingConsent = ResearchConsentUseCases(
        owners: consent.owners, repository: deferred,
        nowUtc: () => now.add(const Duration(seconds: 1)),
        onLocalMutation: (_) async { notified = true; },
      );
      final pending = accepted ? pendingConsent.accept() : pendingConsent.withdraw();
      final rejected = expectLater(pending, throwsStateError);
      await deferred.entered.future;
      await database.transaction(() async {
        await database.customUpdate('UPDATE local_owners SET is_active = 0');
        await database.customUpdate("UPDATE local_owners SET is_active = 1 WHERE id = 'other'");
      });
      final before = await _consentSnapshot(database);
      deferred.release.complete();
      await rejected;
      expect(await _consentSnapshot(database), before);
      expect(notified, isFalse);
      expect((await consent.repository.load(ownerId: owner.id, version: 1)).accepted, isTrue);
      expect((await consent.repository.load(ownerId: 'other', version: 1)).decidedAtUtc, isNull);
      // A new explicit action resolves the new owner and remains available.
      await consent.withdraw();
      expect((await consent.repository.load(ownerId: 'other', version: 1)).accepted, isFalse);
      expect((await consent.repository.load(ownerId: owner.id, version: 1)).accepted, isTrue);
    });
  }

  test('withdrawal evidence fails closed for an accepted state', () async {
    await consent.accept();
    await database.customUpdate(
      'UPDATE research_consents SET withdrawn_at_utc_ms = 200 '
      "WHERE consent_state = 'accepted'",
    );

    final malformed = await consent.load();

    expect(malformed.accepted, isFalse);
    expect(
      malformed.withdrawnAtUtc,
      DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
    );
  });
}

Future<Map<String, Object?>> _consentSnapshot(AppDatabase database) async => {
  for (final table in ['local_owners', 'research_consents', 'outbox_operations',
      'research_participation_permits', 'motivation_measurement_runs',
      'measurement_opportunities'])
    table: [for (final row in await database.customSelect('SELECT * FROM $table').get()) row.data],
};

final class _DeferredConsentRepository implements ResearchConsentRepository {
  _DeferredConsentRepository(this.delegate);
  final ResearchConsentRepository delegate;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ResearchConsentStatus> load({required String ownerId, required int version}) =>
      delegate.load(ownerId: ownerId, version: version);
  @override
  Future<void> decide({required String ownerId, required int version,
      required bool accepted, required DateTime decidedAtUtc}) async {
    entered.complete();
    await release.future;
    await delegate.decide(ownerId: ownerId, version: version,
        accepted: accepted, decidedAtUtc: decidedAtUtc);
  }
}
