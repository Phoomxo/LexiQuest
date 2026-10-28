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
