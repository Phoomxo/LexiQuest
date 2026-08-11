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
