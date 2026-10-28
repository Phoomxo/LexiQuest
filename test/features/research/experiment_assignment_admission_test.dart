import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/research/application/research_participation_permit_validator.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment_admission.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_study_protocol.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/research/domain/research_trusted_time.dart';

import '../../support/research_admission_signing.dart';

final _start = DateTime.utc(2026, 10, 29, 12);
const _experiment = 'synthetic-experiment';
const _experimentVersion = 2;
const _protocol = 'synthetic-protocol';
const _protocolVersion = 'protocol-string-v7';
const _consentVersion = 4;
const _assignmentRevision = 11;
const _protocolRevision = 5;
const _instrumentRevision = 9;

void main() {
  test('canonical assignment ID preserves the archived SHA256 JSON tuple', () {
    expect(
      _id(),
      'experiment-assignment:6c6cfe12cdfd73e00763dbbdd552f6448f1987ba5e76932a87708809ce89c8dc',
    );
    expect(
      experimentAssignmentId(
        ownerId: 'a:b',
        experimentId: 'c',
        experimentVersion: 1,
      ),
      isNot(
        experimentAssignmentId(
          ownerId: 'a',
          experimentId: 'b:c',
          experimentVersion: 1,
        ),
      ),
    );
  });

  group('signed local assignment admission', () {
    late _Harness harness;

    setUp(() async => harness = await _Harness.open());
    tearDown(() => harness.database.close());

    test(
      'uses signed treatment and the first local trusted timestamp',
      () async {
        harness.clock.now = _start.add(const Duration(microseconds: 123));
        final result = await harness.admit();

        expect(result, isNotNull);
        expect(result!.id, _id());
        expect(result.ownerId, 'owner-a');
        expect(result.experimentId, _experiment);
        expect(result.experimentVersion, _experimentVersion);
        expect(result.cohort, 'standard');
        expect(result.protocolVersion, _protocolVersion);
        expect(result.assignedAtUtc, _start);
        expect(result.assignedAtUtc, isNot(harness.participation.issuedAtUtc));
        await _expectArtifacts(harness.database, assignments: 1);
      },
    );

    test('a valid repeat keeps the original time and fact', () async {
      final first = await harness.admit();
      harness.clock.now = _start.add(const Duration(minutes: 1));
      final second = await harness.admit();

      expect(second, first);
      expect(second!.assignedAtUtc, _start);
      await _expectArtifacts(harness.database, assignments: 1);
    });

    test(
      'reauthorization preserves a fact older than the new permits',
      () async {
        final original = await harness.admit();
        final newIssuedAt = _start.add(const Duration(minutes: 1));
        harness.clock.now = _start.add(const Duration(minutes: 2));
        harness.participation = _participation(
          revision: 2,
          issuedAtUtc: newIssuedAt,
        );
        harness.documents.current = harness.participation;
        harness.operations.current = _operation(
          revision: 2,
          issuedAtUtc: newIssuedAt,
        );
        harness.states.revision = 2;

        expect(await harness.admit(), original);
        expect(original!.assignedAtUtc.isBefore(newIssuedAt), isTrue);
        await _expectArtifacts(harness.database, assignments: 1);
      },
    );

    test(
      'concurrent admissions commit one assignment without events or outbox',
      () async {
        final results = await Future.wait([harness.admit(), harness.admit()]);
        expect(results.first, isNotNull);
        expect(results.last, results.first);
        await _expectArtifacts(harness.database, assignments: 1);
      },
    );

    test('wrong scoped owner is rejected before authority lookup', () async {
      final other = _participation(ownerId: 'owner-b');
      final result = await harness.repository.admit(
        ownerId: 'owner-b',
        participationPermit: other,
      );
      expect(result, isNull);
      expect(harness.documents.calls, 0);
      expect(harness.operations.calls, 0);
      await _expectArtifacts(harness.database);
    });

    test('wrong canonical assignment ID is rejected before lookup', () async {
      harness.participation = _participation(assignmentId: 'wrong-assignment');
      harness.documents.current = harness.participation;
      expect(await harness.admit(), isNull);
      expect(harness.documents.calls, 0);
      expect(harness.operations.calls, 0);
      await _expectArtifacts(harness.database);
    });

    for (final unavailable in ['null', 'exception']) {
      test('current participation source $unavailable fails closed', () async {
        harness.documents.available = false;
        harness.documents.fail = unavailable == 'exception';
        expect(await harness.admit(), isNull);
        await _expectArtifacts(harness.database);
      });
    }

    test(
      'matching caller local/cloud revisions do not replace current authority',
      () async {
        expect(
          harness.participation.localRevision,
          harness.participation.cloudRevision,
        );
        harness.documents.current = _participation(revision: 2);
        expect(await harness.admit(), isNull);
        await _expectArtifacts(harness.database);
      },
    );

    test(
      'a changed current signature cannot be substituted for the supplied document',
      () async {
        harness.documents.current = _participation(corruptSignature: true);
        expect(await harness.admit(), isNull);
        await _expectArtifacts(harness.database);
      },
    );

    for (final invalid in [
      'signature',
      'hash',
      'protocol',
      'revoked',
      'deleted',
    ]) {
      test(
        'P256 participation $invalid is rejected by real validation',
        () async {
          harness.participation = switch (invalid) {
            'signature' => _participation(corruptSignature: true),
            'hash' => _participation().copyWith(payloadSha256: '0' * 64),
            'protocol' => _participation(
              protocolVersion: 'another-protocol-version',
            ),
            'revoked' => _participation(revokedAtUtc: _start),
            'deleted' => _participation(isDeleted: true),
            _ => throw StateError('unknown fixture'),
          };
          harness.documents.current = harness.participation;
          expect(await harness.admit(), isNull);
          await _expectArtifacts(harness.database);
        },
      );
    }

    for (final invalid in [
      'signature',
      'assignment',
      'protocol',
      'instrument',
      'operation',
    ]) {
      test('Ed25519 operation $invalid cannot admit an assignment', () async {
        harness.operations.current = switch (invalid) {
          'signature' => _operation(corruptSignature: true),
          'assignment' => _operation(assignmentId: 'wrong-assignment'),
          'protocol' => _operation(protocolRevision: _protocolRevision + 1),
          'instrument' => _operation(
            instrumentRevision: _instrumentRevision + 1,
          ),
          'operation' => _operation(operation: ResearchOperation.upload),
          _ => throw StateError('unknown fixture'),
        };
        expect(await harness.admit(), isNull);
        await _expectArtifacts(harness.database);
      });
    }

    for (final invalid in ['unavailable', 'revoked', 'revision']) {
      test('current operation state $invalid fails closed', () async {
        harness.states.available = invalid != 'unavailable';
        harness.states.revoked = invalid == 'revoked';
        if (invalid == 'revision') harness.states.revision = 2;
        expect(await harness.admit(), isNull);
        await _expectArtifacts(harness.database);
      });
    }

    for (final invalid in ['unavailable', 'stale']) {
      test('trusted time $invalid fails closed', () async {
        harness.clock.available = invalid != 'unavailable';
        harness.clock.stale = invalid == 'stale';
        expect(await harness.admit(), isNull);
        await _expectArtifacts(harness.database);
      });
    }

    for (final invalid in [
      'missing',
      'version',
      'withdrawn',
      'withdrawn-marker',
      'future',
    ]) {
      test('local consent $invalid cannot create an assignment', () async {
        switch (invalid) {
          case 'missing':
            await harness.database.customStatement(
              'DELETE FROM research_consents',
            );
          case 'version':
            await harness.database.customStatement(
              'UPDATE research_consents SET consent_version = ?',
              [_consentVersion - 1],
            );
          case 'withdrawn':
            await harness.consent.decide(
              ownerId: 'owner-a',
              version: _consentVersion,
              accepted: false,
              decidedAtUtc: _start,
            );
          case 'withdrawn-marker':
            await harness.database.customStatement(
              'UPDATE research_consents SET withdrawn_at_utc_ms = ?',
              [_start.millisecondsSinceEpoch],
            );
          case 'future':
            await harness.database.customStatement(
              'UPDATE research_consents SET decided_at_utc_ms = ?',
              [_start.add(const Duration(days: 1)).millisecondsSinceEpoch],
            );
        }
        expect(await harness.admit(), isNull);
        await _expectArtifacts(harness.database);
      });
    }

    test(
      'minor participation requires live guardian permission and assent',
      () async {
        harness.participation = _participation(minor: true);
        harness.documents.current = harness.participation;
        harness.receipts.inactive.add(ResearchReceiptKind.guardianPermission);
        expect(await harness.admit(), isNull);
        await _expectArtifacts(harness.database);
      },
    );

    test(
      'minor participation with all current receipts can be admitted',
      () async {
        harness.participation = _participation(minor: true);
        harness.documents.current = harness.participation;
        expect(await harness.admit(), isNotNull);
        await _expectArtifacts(harness.database, assignments: 1);
      },
    );

    test('an unknown consent receipt cannot authorize participation', () async {
      harness.participation = _participation(
        consentReceiptId: 'unknown-receipt',
      );
      harness.documents.current = harness.participation;
      expect(await harness.admit(), isNull);
      await _expectArtifacts(harness.database);
    });

    test(
      'participation expiry during receipt awaits uses the full final clock',
      () async {
        harness.participation = _participation(
          expiresAtUtc: _start.add(const Duration(seconds: 1)),
        );
        harness.documents.current = harness.participation;
        harness.receipts.onRead = (_) async {
          harness.clock.now = _start.add(
            const Duration(seconds: 1, microseconds: 1),
          );
        };
        expect(await harness.admit(), isNull);
        await _expectArtifacts(harness.database);
      },
    );

    test('final authority awaits recheck local withdrawal', () async {
      harness.states.onRead = (call) async {
        if (call == 2) {
          await harness.consent.decide(
            ownerId: 'owner-a',
            version: _consentVersion,
            accepted: false,
            decidedAtUtc: harness.clock.now,
          );
        }
      };
      expect(await harness.admit(), isNull);
      final consent = await harness.consent.load(
        ownerId: 'owner-a',
        version: _consentVersion,
      );
      expect(consent.withdrawnAtUtc, isNotNull);
      await _expectArtifacts(harness.database);
    });

    test(
      'a current document revoked during final operation checks is rejected',
      () async {
        harness.states.onRead = (call) async {
          if (call == 2) {
            harness.documents.current = _participation(
              revision: 2,
              revokedAtUtc: _start,
            );
          }
        };
        expect(await harness.admit(), isNull);
        await _expectArtifacts(harness.database);
      },
    );

    for (final change in ['unavailable', 'revision']) {
      test('current P256 $change after preflight is rejected', () async {
        harness.states.onRead = (call) async {
          if (call == 2) {
            if (change == 'unavailable') {
              harness.documents.available = false;
            } else {
              harness.documents.current = _participation(revision: 2);
            }
          }
        };
        expect(await harness.admit(), isNull);
        await _expectArtifacts(harness.database);
      });
    }

    test(
      'operation state is rechecked after preflight authorization',
      () async {
        harness.states.onRead = (call) async {
          if (call == 2) harness.states.revoked = true;
        };
        expect(await harness.admit(), isNull);
        await _expectArtifacts(harness.database);
      },
    );

    test(
      'a changed signed cohort conflicts without replacing the first fact',
      () async {
        final original = await harness.admit();
        harness.participation = _participation(
          treatment: TodayExperiencePresentation.adventure,
          revision: 2,
        );
        harness.documents.current = harness.participation;

        await expectLater(
          harness.admit(),
          throwsA(isA<ExperimentAssignmentConflict>()),
        );
        final row = await harness.database
            .customSelect('SELECT * FROM experiment_assignments')
            .getSingle();
        expect(row.read<String>('cohort'), original!.cohort);
        expect(
          row.read<int>('assigned_at_utc_ms'),
          original.assignedAtUtc.millisecondsSinceEpoch,
        );
        await _expectArtifacts(harness.database, assignments: 1);
      },
    );

    for (final invalid in ['protocol', 'canonical-id', 'global-id-collision']) {
      test(
        'stored $invalid is an immutable conflict with no replacement',
        () async {
          await harness.database.customStatement(
            'INSERT INTO experiment_assignments '
            '(id, owner_id, experiment_id, experiment_version, cohort, protocol_version, assigned_at_utc_ms) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              invalid == 'canonical-id' ? 'noncanonical-id' : _id(),
              invalid == 'global-id-collision' ? 'owner-b' : 'owner-a',
              _experiment,
              _experimentVersion,
              'standard',
              invalid == 'protocol' ? 'old-protocol-version' : _protocolVersion,
              _start.millisecondsSinceEpoch,
            ],
          );
          final before =
              (await harness.database
                      .customSelect('SELECT * FROM experiment_assignments')
                      .getSingle())
                  .data;
          await expectLater(
            harness.admit(),
            throwsA(isA<ExperimentAssignmentConflict>()),
          );
          expect(
            (await harness.database
                    .customSelect('SELECT * FROM experiment_assignments')
                    .getSingle())
                .data,
            before,
          );
          await _expectArtifacts(harness.database, assignments: 1);
        },
      );
    }

    for (final invalid in ['future', 'before-consent']) {
      test('stored $invalid assignment time is an immutable conflict', () async {
        final assignedAt = invalid == 'future'
            ? _start.add(const Duration(milliseconds: 1))
            : _start.subtract(const Duration(hours: 1, milliseconds: 1));
        await harness.database.customStatement(
          'INSERT INTO experiment_assignments '
          '(id, owner_id, experiment_id, experiment_version, cohort, protocol_version, assigned_at_utc_ms) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            _id(),
            'owner-a',
            _experiment,
            _experimentVersion,
            'standard',
            _protocolVersion,
            assignedAt.millisecondsSinceEpoch,
          ],
        );
        final before =
            (await harness.database
                    .customSelect('SELECT * FROM experiment_assignments')
                    .getSingle())
                .data;

        await expectLater(
          harness.admit(),
          throwsA(isA<ExperimentAssignmentConflict>()),
        );
        expect(
          (await harness.database
                  .customSelect('SELECT * FROM experiment_assignments')
                  .getSingle())
              .data,
          before,
        );
        await _expectArtifacts(harness.database, assignments: 1);
      });
    }

    test(
      'constructor rejects a coordinator bound to another database',
      () async {
        final other = await _Harness.open();
        addTearDown(other.database.close);
        await harness.ownerWrites.beginDeletion(
          ownerId: 'owner-a',
          firebaseUid: 'uid-a',
          idempotencyKey: 'delete:00000000-0000-4000-8000-000000000001',
        );
        await harness.database.customStatement(
          "UPDATE local_owners SET is_active = (id = 'owner-b')",
        );

        expect(
          () => harness.repositoryWith(ownerWrites: other.ownerWrites),
          throwsArgumentError,
        );
        expect(harness.documents.calls, 0);
        expect(harness.operations.calls, 0);
        expect(other.documents.calls, 0);
        expect(other.operations.calls, 0);
        await _expectArtifacts(harness.database);
        await _expectArtifacts(other.database);
      },
    );

    test(
      'constructor rejects wall-clock fallback and different trusted-time instances',
      () {
        expect(
          () => harness.repositoryWith(trustedTime: _Clock()),
          throwsArgumentError,
        );
        final wallClockAuthorizer = SignedPermitResearchOperationAuthorizer(
          permits: harness.operations,
          states: harness.states,
          verifier: admissionEd25519Verifier(),
          requirements: _requirements(),
          nowUtc: () => _start,
        );
        expect(
          () => harness.repositoryWith(authorizer: wallClockAuthorizer),
          throwsArgumentError,
        );
      },
    );
  });

  test('expiry after the last assignment read prevents the insert', () async {
    final interceptor = _AfterAssignmentRead();
    final harness = await _Harness.open(
      database: AppDatabase(NativeDatabase.memory().interceptWith(interceptor)),
    );
    addTearDown(harness.database.close);
    harness.operations.current = _operation(
      expiresAtUtc: _start.add(const Duration(seconds: 1)),
    );
    interceptor.afterSecondRead = () {
      harness.clock.now = _start.add(
        const Duration(seconds: 1, microseconds: 1),
      );
    };

    expect(await harness.admit(), isNull);
    expect(interceptor.didAdvance, isTrue);
    await _expectArtifacts(harness.database);
  });

  group('admission after an independent SQLite writer', () {
    late _FileDatabases fixture;
    late _Harness harness;

    setUp(() async {
      fixture = await _FileDatabases.open();
      harness = await _Harness.open(database: fixture.second);
      await fixture.first
          .customSelect('SELECT COUNT(*) FROM local_owners')
          .getSingle();
    });
    tearDown(() => fixture.close());

    for (final change in ['expiry', 'withdrawal', 'owner', 'deletion']) {
      test('$change committed while waiting prevents admission', () async {
        if (change == 'expiry') {
          harness.operations.current = _operation(
            expiresAtUtc: _start.add(const Duration(seconds: 1)),
          );
        }
        final started = Completer<void>();
        final release = Completer<void>();
        final held = fixture.first.transaction(() async {
          await fixture.first.customUpdate(
            'UPDATE local_owners SET is_active = is_active',
          );
          switch (change) {
            case 'withdrawal':
              await fixture.first.customStatement(
                "UPDATE research_consents SET consent_state = 'withdrawn', withdrawn_at_utc_ms = ?",
                [_start.millisecondsSinceEpoch],
              );
            case 'owner':
              await fixture.first.customStatement(
                "UPDATE local_owners SET is_active = (id = 'owner-b')",
              );
            case 'deletion':
              await DriftOwnerWriteCoordinator(
                fixture.first,
                nowUtc: () => _start,
              ).beginDeletion(
                ownerId: 'owner-a',
                firebaseUid: 'uid-a',
                idempotencyKey: 'delete:00000000-0000-4000-8000-000000000001',
              );
          }
          started.complete();
          await release.future;
        });
        try {
          await Future.any<void>([started.future, held]);
          fixture.interceptor.handoff = () async {
            if (change == 'expiry') {
              harness.clock.now = _start.add(const Duration(seconds: 2));
            }
            release.complete();
            await held;
          };

          expect(await harness.admit(), isNull);
          expect(fixture.interceptor.didHandoff, isTrue);
          await _expectArtifacts(fixture.second);
        } finally {
          if (!release.isCompleted) release.complete();
          await held;
        }
      });
    }

    test(
      'two connections admit one fact with the same original timestamp',
      () async {
        final other = await _Harness.open(database: fixture.first, seed: false);
        final results = await Future.wait([harness.admit(), other.admit()]);
        expect(results.first, isNotNull);
        expect(results.last, results.first);
        await _expectArtifacts(fixture.first, assignments: 1);
      },
    );
  });
}

String _id([String ownerId = 'owner-a']) => experimentAssignmentId(
  ownerId: ownerId,
  experimentId: _experiment,
  experimentVersion: _experimentVersion,
);

final class _Harness {
  _Harness(this.database);
  final AppDatabase database;
  final clock = _Clock();
  final documents = _Documents();
  final operations = _Operations();
  final states = _States();
  final receipts = _Receipts();
  late ResearchParticipationPermit participation;
  late ExperimentAssignmentAdmissionBinding binding;
  late DriftResearchConsentRepository consent;
  late DriftOwnerWriteCoordinator ownerWrites;
  late ResearchParticipationPermitValidator validator;
  late SignedPermitResearchOperationAuthorizer authorizer;
  late DriftExperimentAssignmentRepository repository;

  static Future<_Harness> open({
    AppDatabase? database,
    bool seed = true,
  }) async {
    final result = _Harness(database ?? AppDatabase(NativeDatabase.memory()));
    if (seed) {
      await result.database.customStatement('PRAGMA foreign_keys = ON');
      await result.database.customStatement(
        'INSERT INTO local_owners (id, firebase_uid, account_state, is_active, created_at_utc_ms) VALUES '
        "('owner-a', 'uid-a', 'firebaseBound', 1, 1), ('owner-b', 'uid-b', 'firebaseBound', 0, 2)",
      );
      await result.database.customStatement(
        'INSERT INTO research_consents (id, owner_id, consent_version, consent_state, decided_at_utc_ms) '
        "VALUES ('synthetic-local-consent', 'owner-a', ?, 'accepted', ?)",
        [
          _consentVersion,
          _start.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        ],
      );
    }
    result.participation = _participation();
    result.documents.current = result.participation;
    result.operations.current = _operation();
    result.binding = _binding();
    result.consent = DriftResearchConsentRepository(result.database);
    result.ownerWrites = DriftOwnerWriteCoordinator(
      result.database,
      nowUtc: () => result.clock.now,
    );
    result.validator = ResearchParticipationPermitValidator(
      protocolId: _protocol,
      protocolVersion: _protocolVersion,
      signatures: admissionP256Verifier(),
      receipts: result.receipts,
    );
    result.authorizer = SignedPermitResearchOperationAuthorizer(
      permits: result.operations,
      states: result.states,
      verifier: admissionEd25519Verifier(),
      requirements: _requirements(),
      trustedTime: result.clock,
    );
    result.repository = result.repositoryWith();
    return result;
  }

  DriftExperimentAssignmentRepository repositoryWith({
    SignedPermitResearchOperationAuthorizer? authorizer,
    ResearchTrustedTimeSource? trustedTime,
    DriftOwnerWriteCoordinator? ownerWrites,
  }) => DriftExperimentAssignmentRepository(
    database,
    binding: binding,
    authorizer: authorizer ?? this.authorizer,
    trustedTime: trustedTime ?? clock,
    participationDocuments: documents,
    participationValidator: validator,
    consent: consent,
    ownerWrites: ownerWrites ?? this.ownerWrites,
  );

  Future<ExperimentAssignment?> admit() =>
      repository.admit(ownerId: 'owner-a', participationPermit: participation);
}

ExperimentAssignmentAdmissionBinding _binding() {
  final instrument = MotivationInstrument(
    instrumentId: 'synthetic-instrument',
    instrumentVersion: 'instrument-string-v3',
    formId: 'synthetic-form',
    formVersion: 'form-v1',
    itemCatalogVersion: 'catalog-v1',
    items: [
      for (final point in MotivationTimepoint.values)
        MotivationItem(
          id: 'synthetic-${point.name}',
          timepoint: point,
          prompts: const {'th': 'ข้อมูลสังเคราะห์', 'en': 'Synthetic item'},
          options: [
            MotivationResponseOption(
              code: 'low',
              ordinalValue: 0,
              labels: const {'th': 'ต่ำ', 'en': 'Low'},
            ),
            MotivationResponseOption(
              code: 'high',
              ordinalValue: 1,
              labels: const {'th': 'สูง', 'en': 'High'},
            ),
          ],
        ),
    ],
  );
  return ExperimentAssignmentAdmissionBinding(
    study: MotivationStudyProtocol(
      protocolId: _protocol,
      protocolVersion: _protocolVersion,
      consentVersion: _consentVersion,
      experimentId: _experiment,
      experimentVersion: _experimentVersion,
      instrument: instrument,
      approvedInstrumentChecksum: instrument.checksumSha256,
      appVersion: 'synthetic-app',
      buildId: 'synthetic-build',
      contentRevision: 'content-v1',
      evidencePolicyVersion: 'evidence-v1',
      catalogVersion: 'catalog-v1',
    ),
    assignmentRevision: _assignmentRevision,
    protocolRevision: _protocolRevision,
    instrumentRevision: _instrumentRevision,
  );
}

ResearchPermitRequirements _requirements() => ResearchPermitRequirements(
  supportedFormatVersion: 1,
  trustedIssuerId: 'synthetic-issuer',
  trustedIssuerKeyId: syntheticAdmissionEd25519KeyId,
  signatureAlgorithm: 'EdDSA',
  assignmentId: _id(),
  assignmentRevision: _assignmentRevision,
  protocolId: _protocol,
  protocolRevision: _protocolRevision,
  instrumentId: 'synthetic-instrument',
  instrumentRevision: _instrumentRevision,
);

ResearchParticipationPermit _participation({
  String ownerId = 'owner-a',
  String? assignmentId,
  TodayExperiencePresentation treatment = TodayExperiencePresentation.standard,
  String protocolVersion = _protocolVersion,
  String consentReceiptId = 'synthetic-consent-receipt',
  int revision = 1,
  bool isDeleted = false,
  bool minor = false,
  bool corruptSignature = false,
  DateTime? revokedAtUtc,
  DateTime? issuedAtUtc,
  DateTime? expiresAtUtc,
}) => signAdmissionParticipation(
  ResearchParticipationPermit(
    id: 'synthetic-participation',
    ownerId: ownerId,
    participantClass: minor
        ? ResearchParticipantClass.minor
        : ResearchParticipantClass.adult,
    ageBandCode: minor ? 'synthetic-minor' : 'synthetic-adult',
    assignmentId: assignmentId ?? _id(ownerId),
    assignedTreatment: treatment,
    consentReceiptId: consentReceiptId,
    guardianPermissionReceiptRef: minor ? 'synthetic-guardian-receipt' : null,
    learnerAssentReceiptRef: minor ? 'synthetic-assent-receipt' : null,
    protocolId: _protocol,
    protocolVersion: protocolVersion,
    issuedAtUtc: issuedAtUtc ?? _start.subtract(const Duration(minutes: 5)),
    expiresAtUtc: expiresAtUtc ?? _start.add(const Duration(hours: 1)),
    revokedAtUtc: revokedAtUtc,
    issuerKeyId: syntheticAdmissionP256KeyId,
    payloadSha256: '0' * 64,
    signature: 'unsigned',
    localRevision: revision,
    cloudRevision: revision,
    isDeleted: isDeleted,
  ),
  corruptSignature: corruptSignature,
);

ResearchPermit _operation({
  String? assignmentId,
  int protocolRevision = _protocolRevision,
  int instrumentRevision = _instrumentRevision,
  int revision = 1,
  ResearchOperation operation = ResearchOperation.collect,
  DateTime? expiresAtUtc,
  DateTime? issuedAtUtc,
  bool corruptSignature = false,
}) => signAdmissionOperation(
  ResearchPermit(
    formatVersion: 1,
    permitId: 'synthetic-operation-permit',
    issuerId: 'synthetic-issuer',
    issuerKeyId: syntheticAdmissionEd25519KeyId,
    signatureAlgorithm: 'EdDSA',
    ownerId: 'owner-a',
    operation: operation,
    assignmentId: assignmentId ?? _id(),
    assignmentRevision: _assignmentRevision,
    protocolId: _protocol,
    protocolRevision: protocolRevision,
    instrumentId: 'synthetic-instrument',
    instrumentRevision: instrumentRevision,
    revision: revision,
    issuedAtUtc: issuedAtUtc ?? _start.subtract(const Duration(minutes: 5)),
    expiresAtUtc: expiresAtUtc ?? _start.add(const Duration(hours: 1)),
    signature: const [1],
  ),
  corruptSignature: corruptSignature,
);

final class _Clock implements ResearchTrustedTimeSource {
  DateTime now = _start;
  var available = true;
  var stale = false;
  @override
  Future<ResearchTrustedTime?> read() async => available
      ? ResearchTrustedTime(
          anchorUtc: now,
          validUntilUtc: now.add(const Duration(hours: 2)),
          age: stale ? const Duration(minutes: 2) : Duration.zero,
          maximumAge: const Duration(minutes: 1),
        )
      : null;
}

final class _Documents implements ResearchParticipationDocumentSource {
  ResearchParticipationPermit? current;
  var available = true;
  var fail = false;
  var calls = 0;
  @override
  Future<ResearchParticipationPermit?> loadCurrent({
    required String ownerId,
    required String permitId,
  }) async {
    calls++;
    if (fail) throw StateError('synthetic unavailable authority');
    return available && current?.ownerId == ownerId && current?.id == permitId
        ? current
        : null;
  }
}

final class _Operations implements ResearchPermitSource {
  ResearchPermit? current;
  var calls = 0;
  @override
  Future<ResearchPermit?> loadPermit({
    required String ownerId,
    required ResearchOperation operation,
  }) async {
    calls++;
    return current;
  }
}

final class _States implements ResearchPermitStateSource {
  var available = true;
  var revoked = false;
  var revision = 1;
  var calls = 0;
  Future<void> Function(int)? onRead;
  @override
  Future<ResearchPermitState?> loadState({required String permitId}) async {
    calls++;
    await onRead?.call(calls);
    return available
        ? ResearchPermitState(currentRevision: revision, revoked: revoked)
        : null;
  }
}

final class _Receipts implements ResearchReceiptAuthority {
  final inactive = <ResearchReceiptKind>{};
  Future<void> Function(ResearchReceiptKind)? onRead;
  @override
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  }) async {
    await onRead?.call(kind);
    final expected = switch (kind) {
      ResearchReceiptKind.consent => 'synthetic-consent-receipt',
      ResearchReceiptKind.guardianPermission => 'synthetic-guardian-receipt',
      ResearchReceiptKind.learnerAssent => 'synthetic-assent-receipt',
    };
    return ownerId == 'owner-a' &&
        receiptId == expected &&
        !inactive.contains(kind);
  }
}

Future<void> _expectArtifacts(
  AppDatabase database, {
  int assignments = 0,
}) async {
  for (final expected in {
    'experiment_assignments': assignments,
    'events_v2': 0,
    'outbox_operations': 0,
  }.entries) {
    final row = await database
        .customSelect('SELECT COUNT(*) AS count FROM ${expected.key}')
        .getSingle();
    expect(row.read<int>('count'), expected.value, reason: expected.key);
  }
}

final class _AfterAssignmentRead extends drift.QueryInterceptor {
  void Function()? afterSecondRead;
  var reads = 0;
  var didAdvance = false;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    if (statement.contains('experiment_assignments') &&
        ++reads == 2 &&
        afterSecondRead != null) {
      didAdvance = true;
      afterSecondRead!();
    }
    return result;
  }
}

final class _FileDatabases {
  _FileDatabases(
    this.directory,
    this.ownedPath,
    this.first,
    this.second,
    this.interceptor,
  );
  final Directory directory;
  final String ownedPath;
  final AppDatabase first;
  final AppDatabase second;
  final _TransactionHandoff interceptor;
  static Future<_FileDatabases> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-assignment-admission-',
    );
    final ownedPath = await directory.resolveSymbolicLinks();
    final file = File('${directory.path}${Platform.pathSeparator}test.sqlite');
    final first = _open(file);
    final interceptor = _TransactionHandoff();
    final second = _open(file, interceptor: interceptor);
    return _FileDatabases(directory, ownedPath, first, second, interceptor);
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

  Future<void> close() async {
    await second.close();
    await first.close();
    if (!await directory.exists()) return;
    final target = await directory.resolveSymbolicLinks();
    final parent = await Directory.systemTemp.resolveSymbolicLinks();
    final separator = Platform.pathSeparator;
    final prefix =
        '$parent${parent.endsWith(separator) ? '' : separator}lexiquest-assignment-admission-';
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
