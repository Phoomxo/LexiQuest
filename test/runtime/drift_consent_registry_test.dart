import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/consent/domain/research_consent.dart';
import 'package:vocab_learning_app/runtime/registries/consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';

void main() {
  late AppDatabase database;
  late DriftResearchConsentRepository repository;
  late ConsentRegistry registry;
  final decision = DateTime.utc(2026, 10, 28, 12);
  final withdrawal = DateTime.utc(2026, 10, 28, 13);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftResearchConsentRepository(database);
    registry = DriftConsentRegistry(repository);
  });
  tearDown(() => database.close());

  Future<void> seedOwners() async {
    await database.customStatement(
      'INSERT INTO local_owners (id, created_at_utc_ms, is_active) '
      "VALUES ('owner-a', 1, 1), ('owner-b', 2, 0)",
    );
  }

  Future<ConsentSnapshot> read({
    ConsentPurpose purpose = ConsentPurpose.researchDataUpload,
    String ownerId = 'owner-a',
    int version = 1,
  }) => registry.snapshot(
    purpose: purpose,
    ownerId: ownerId,
    consentVersion: version,
  );

  Future<Map<String, List<Map<String, Object?>>>> rows() async {
    final tables =
        database.allTables.map((table) => table.actualTableName).toList()
          ..sort();
    return {
      for (final table in tables)
        table: [
          for (final row
              in await database.customSelect('SELECT * FROM "$table"').get())
            Map<String, Object?>.from(row.data),
        ],
    };
  }

  test(
    'missing consent stays unknown and reads create no owner or research rows',
    () async {
      final before = await rows();
      final snapshot = await read();
      expect(snapshot.purpose, ConsentPurpose.researchDataUpload);
      expect(snapshot.ownerId, 'owner-a');
      expect(snapshot.consentVersion, 1);
      expect(snapshot.state, ConsentState.unknown);
      expect(snapshot.decisionUtc, isNull);
      expect(snapshot.withdrawalUtc, isNull);
      expect(await rows(), before);
      expect(await database.select(database.localOwners).get(), isEmpty);
    },
  );

  test(
    'snapshot delegates exact owner and positive version to the existing consent repository',
    () async {
      await seedOwners();
      expect(
        await repository.decide(
          ownerId: 'owner-a',
          version: 2,
          accepted: true,
          decidedAtUtc: decision,
        ),
        isTrue,
      );
      final before = await rows();
      final granted = await read(version: 2);
      expect(granted.purpose, ConsentPurpose.researchDataUpload);
      expect(granted.ownerId, 'owner-a');
      expect(granted.consentVersion, 2);
      expect(granted.state, ConsentState.granted);
      expect(granted.decisionUtc, decision);
      expect(granted.decisionUtc!.isUtc, isTrue);
      expect(granted.withdrawalUtc, isNull);
      expect((await read(version: 1)).state, ConsentState.unknown);
      expect(
        (await read(ownerId: 'owner-b', version: 2)).state,
        ConsentState.unknown,
      );
      expect(await rows(), before);
    },
  );

  test(
    'withdrawal retains existing idempotent and no-reaccept semantics',
    () async {
      await seedOwners();
      expect(
        await repository.decide(
          ownerId: 'owner-a',
          version: 1,
          accepted: true,
          decidedAtUtc: decision,
        ),
        isTrue,
      );
      expect(
        await repository.decide(
          ownerId: 'owner-a',
          version: 1,
          accepted: false,
          decidedAtUtc: withdrawal,
        ),
        isTrue,
      );
      expect(
        await repository.decide(
          ownerId: 'owner-a',
          version: 1,
          accepted: false,
          decidedAtUtc: withdrawal.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
      expect(
        await repository.decide(
          ownerId: 'owner-a',
          version: 1,
          accepted: true,
          decidedAtUtc: withdrawal.add(const Duration(hours: 2)),
        ),
        isFalse,
      );
      final before = await rows();
      final snapshot = await read();
      expect(snapshot.state, ConsentState.denied);
      expect(snapshot.decisionUtc, withdrawal);
      expect(snapshot.withdrawalUtc, withdrawal);
      expect(await rows(), before);
      expect(
        await database.select(database.researchConsents).get(),
        hasLength(1),
      );
      expect(await database.select(database.eventsV2).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'an accepted row with a withdrawal is never projected as granted',
    () async {
      await seedOwners();
      await repository.decide(
        ownerId: 'owner-a',
        version: 1,
        accepted: true,
        decidedAtUtc: decision,
      );
      await database.customStatement(
        'UPDATE research_consents SET withdrawn_at_utc_ms = ?',
        [withdrawal.millisecondsSinceEpoch],
      );
      final before = await rows();
      final snapshot = await read();
      expect(snapshot.state, ConsentState.denied);
      expect(snapshot.decisionUtc, decision);
      expect(snapshot.withdrawalUtc, withdrawal);
      expect(await rows(), before);
    },
  );

  test(
    'purposes without storage remain unknown even when research was accepted',
    () async {
      await seedOwners();
      await repository.decide(
        ownerId: 'owner-a',
        version: 1,
        accepted: true,
        decidedAtUtc: decision,
      );
      final before = await rows();
      for (final purpose in [
        ConsentPurpose.aiProviderDataSharing,
        ConsentPurpose.personalDataExport,
      ]) {
        final snapshot = await read(purpose: purpose);
        expect(snapshot.purpose, purpose);
        expect(snapshot.state, ConsentState.unknown);
        expect(snapshot.decisionUtc, isNull);
        expect(snapshot.withdrawalUtc, isNull);
      }
      expect(await rows(), before);
    },
  );

  test(
    'invalid identity, version and unsupported purposes do not query the repository',
    () async {
      final stub = _RepositoryStub()..unavailable = true;
      registry = DriftConsentRegistry(stub);
      for (final owner in ['', ' owner-a', 'owner-a ', 'x' * 257]) {
        expect((await read(ownerId: owner)).state, ConsentState.unknown);
      }
      for (final version in [0, -1]) {
        expect((await read(version: version)).state, ConsentState.unknown);
      }
      for (final purpose in [
        ConsentPurpose.aiProviderDataSharing,
        ConsentPurpose.personalDataExport,
      ]) {
        expect((await read(purpose: purpose)).state, ConsentState.unknown);
      }
      expect(stub.reads, 0);
    },
  );

  test(
    'unavailable consent repository fails closed to an unknown snapshot',
    () async {
      final stub = _RepositoryStub()..unavailable = true;
      registry = DriftConsentRegistry(stub);
      final snapshot = await read();
      expect(stub.reads, 1);
      expect(snapshot.ownerId, 'owner-a');
      expect(snapshot.consentVersion, 1);
      expect(snapshot.state, ConsentState.unknown);
      expect(snapshot.decisionUtc, isNull);
      expect(snapshot.withdrawalUtc, isNull);
    },
  );

  for (final (name, status) in [
    (
      'owner mismatch',
      ResearchConsentStatus(
        ownerId: 'owner-b',
        version: 1,
        accepted: true,
        decidedAtUtc: decision,
      ),
    ),
    (
      'version mismatch',
      ResearchConsentStatus(
        ownerId: 'owner-a',
        version: 2,
        accepted: true,
        decidedAtUtc: decision,
      ),
    ),
    (
      'missing decision',
      const ResearchConsentStatus(
        ownerId: 'owner-a',
        version: 1,
        accepted: true,
      ),
    ),
    (
      'non-UTC decision',
      ResearchConsentStatus(
        ownerId: 'owner-a',
        version: 1,
        accepted: true,
        decidedAtUtc: DateTime(2026, 10, 28),
      ),
    ),
    (
      'negative decision',
      ResearchConsentStatus(
        ownerId: 'owner-a',
        version: 1,
        accepted: true,
        decidedAtUtc: DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true),
      ),
    ),
    (
      'submillisecond decision',
      ResearchConsentStatus(
        ownerId: 'owner-a',
        version: 1,
        accepted: true,
        decidedAtUtc: decision.add(const Duration(microseconds: 1)),
      ),
    ),
    (
      'withdrawal before decision',
      ResearchConsentStatus(
        ownerId: 'owner-a',
        version: 1,
        accepted: false,
        decidedAtUtc: decision,
        withdrawnAtUtc: decision.subtract(const Duration(milliseconds: 1)),
      ),
    ),
    (
      'non-UTC withdrawal',
      ResearchConsentStatus(
        ownerId: 'owner-a',
        version: 1,
        accepted: false,
        decidedAtUtc: decision,
        withdrawnAtUtc: DateTime(2026, 10, 29),
      ),
    ),
    (
      'submillisecond withdrawal',
      ResearchConsentStatus(
        ownerId: 'owner-a',
        version: 1,
        accepted: false,
        decidedAtUtc: decision,
        withdrawnAtUtc: withdrawal.add(const Duration(microseconds: 1)),
      ),
    ),
  ]) {
    test('malformed repository response stays unknown: $name', () async {
      registry = DriftConsentRegistry(_RepositoryStub()..response = status);
      final snapshot = await read();
      expect(snapshot.ownerId, 'owner-a');
      expect(snapshot.consentVersion, 1);
      expect(snapshot.state, ConsentState.unknown);
      expect(snapshot.decisionUtc, isNull);
      expect(snapshot.withdrawalUtc, isNull);
    });
  }

  test(
    'NoOp snapshots preserve the requested identity and never grant any purpose',
    () async {
      const unknown = NoOpConsentRegistry();
      for (final purpose in ConsentPurpose.values) {
        for (final version in [1, 2]) {
          final snapshot = await unknown.snapshot(
            purpose: purpose,
            ownerId: 'owner-a',
            consentVersion: version,
          );
          expect(snapshot.purpose, purpose);
          expect(snapshot.ownerId, 'owner-a');
          expect(snapshot.consentVersion, version);
          expect(snapshot.state, ConsentState.unknown);
          expect(snapshot.decisionUtc, isNull);
          expect(snapshot.withdrawalUtc, isNull);
        }
      }
    },
  );
}

final class _RepositoryStub implements ResearchConsentRepository {
  int reads = 0;
  bool unavailable = false;
  ResearchConsentStatus? response;

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) async {
    reads++;
    if (unavailable) throw StateError('synthetic repository unavailable');
    return response!;
  }

  @override
  Future<bool> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) => throw StateError('Consent snapshots must never write a decision.');
}
