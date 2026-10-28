import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_participation_repository.dart';
import 'package:vocab_learning_app/features/research/domain/research_participant_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

import '../../support/research_participation_harness.dart';

void main() {
  group('signed participation cache', () {
    late ParticipationFixture fixture;
    setUp(() async => fixture = await ParticipationFixture.open());
    tearDown(() => fixture.database.close());

    test(
      'imports all twenty signed fields and returns fresh canonical context',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        final stored = await fixture.stored();
        expect(stored.keys.toSet(), participationColumns);
        expect(stored['id'], fixture.current.id);
        expect(stored['owner_id'], 'owner-a');
        expect(stored['assignment_id'], participationAssignmentId());
        expect(stored['participant_class'], 'adult');
        expect(stored['age_band_code'], fixture.current.ageBandCode);
        expect(stored['assigned_treatment'], 'standard');
        expect(stored['consent_receipt_id'], fixture.current.consentReceiptId);
        expect(stored['guardian_permission_receipt_ref'], isNull);
        expect(stored['learner_assent_receipt_ref'], isNull);
        expect(stored['protocol_id'], fixture.current.protocolId);
        expect(stored['protocol_version'], fixture.current.protocolVersion);
        expect(
          stored['issued_at_utc_ms'],
          fixture.current.issuedAtUtc.millisecondsSinceEpoch,
        );
        expect(
          stored['expires_at_utc_ms'],
          fixture.current.expiresAtUtc.millisecondsSinceEpoch,
        );
        expect(stored['revoked_at_utc_ms'], isNull);
        expect(stored['issuer_key_id'], fixture.current.issuerKeyId);
        expect(stored['payload_sha256'], fixture.current.payloadSha256);
        expect(stored['signature'], fixture.current.signature);
        expect(stored['local_revision'], fixture.current.localRevision);
        expect(stored['cloud_revision'], fixture.current.cloudRevision);
        expect(stored['is_deleted'], 0);

        final snapshot = await fixture.participant();
        expect(snapshot, isNotNull);
        expect(
          snapshot!.permit.canonicalPayload(),
          fixture.current.canonicalPayload(),
        );
        expect(snapshot.assignment.id, participationAssignmentId());
        expect(snapshot.assignment.assignedAtUtc, participationStart);
        expect(
          snapshot.assignment.assignedAtUtc.isAfter(
            fixture.current.issuedAtUtc,
          ),
          isTrue,
        );
        expect(snapshot.consent.ownerId, 'owner-a');
        expect(snapshot.consent.version, participationConsentVersion);
        expect(snapshot.consent.accepted, isTrue);
        expect(snapshot.consent.withdrawnAtUtc, isNull);
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    test(
      'exact replay preserves signed revisions and the original assignment',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        final before = await fixture.stored();
        fixture.clock.now = participationStart.add(const Duration(minutes: 1));
        expect(await fixture.importCurrent(), isTrue);
        expect(await fixture.stored(), before);
        final context = await fixture.participant();
        expect(context!.assignment.assignedAtUtc, participationStart);
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    test(
      'wrong owner document cannot create either research artifact',
      () async {
        fixture.use(participationPermit(ownerId: 'owner-b'));
        expect(await fixture.importCurrent(), isFalse);
        await expectParticipationArtifacts(fixture.database);
      },
    );

    test(
      'a forged P256 document cannot create either research artifact',
      () async {
        fixture.use(participationPermit(corruptSignature: true));
        expect(await fixture.importCurrent(), isFalse);
        await expectParticipationArtifacts(fixture.database);
      },
    );

    for (final invalid in ['malformed', 'unknown-key']) {
      test('strict document decoding rejects $invalid input', () async {
        final document = invalid == 'malformed'
            ? '{invalid'
            : jsonEncode({
                ...(jsonDecode(participationDocument(fixture.current))
                    as Map<String, dynamic>),
                'unrecognized': true,
              });
        expect(
          await fixture.repository.importDocument(
            ownerId: 'owner-a',
            document: document,
          ),
          isFalse,
        );
        await expectParticipationArtifacts(fixture.database);
      });
    }

    test(
      'unavailable current issuer source cannot be replaced by submitted input',
      () async {
        fixture.documents.available = false;
        expect(await fixture.importCurrent(), isFalse);
        await expectParticipationArtifacts(fixture.database);
      },
    );

    test(
      'equal caller local/cloud revisions do not override a newer issuer document',
      () async {
        expect(fixture.current.localRevision, fixture.current.cloudRevision);
        fixture.documents.current[fixture.current.id] = participationPermit(
          revision: 2,
        );
        expect(await fixture.importCurrent(), isFalse);
        await expectParticipationArtifacts(fixture.database);
      },
    );

    for (final denied in [
      'expired',
      'withdrawn',
      'minor-receipt',
      'trusted-time',
      'operation-signature',
    ]) {
      test('active import fails closed for $denied eligibility', () async {
        switch (denied) {
          case 'expired':
            fixture.clock.now = participationStart.add(
              const Duration(hours: 2),
            );
          case 'withdrawn':
            await fixture.withdraw();
          case 'minor-receipt':
            fixture.use(participationPermit(minor: true));
            fixture.receipts.inactive.add(
              ResearchReceiptKind.guardianPermission,
            );
          case 'trusted-time':
            fixture.clock.stale = true;
          case 'operation-signature':
            fixture.operations.current = participationOperation(
              corruptSignature: true,
            );
        }
        expect(await fixture.importCurrent(), isFalse);
        await expectParticipationArtifacts(fixture.database);
      });
    }

    test(
      'minor participation with current guardian permission and assent can be imported',
      () async {
        fixture.use(participationPermit(minor: true));
        expect(await fixture.importCurrent(), isTrue);
        expect(
          (await fixture.participant())!.permit.participantClass,
          ResearchParticipantClass.minor,
        );
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    test('missing permit lookup does not create an assignment', () async {
      expect(await fixture.participant(), isNull);
      await expectParticipationArtifacts(fixture.database);
    });

    test(
      'missing assignment lookup never repairs the signed cache context',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        await fixture.database.customStatement('PRAGMA foreign_keys = OFF');
        await fixture.database.customStatement(
          'DELETE FROM experiment_assignments',
        );
        await fixture.database.customStatement('PRAGMA foreign_keys = ON');

        expect(await fixture.participant(), isNull);
        await expectParticipationArtifacts(fixture.database, permits: 1);
      },
    );

    test(
      'cached valid bytes do not grant context when current issuer state is unavailable',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        final before = await fixture.stored();
        fixture.documents.available = false;
        expect(await fixture.participant(), isNull);
        expect(await fixture.stored(), before);
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    test(
      'presentation lookup ignores a future caller timestamp while trusted time is valid',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        final presentation = await fixture.repository.readActivePermit(
          ownerId: 'owner-a',
          evaluatedAtUtc: DateTime.utc(2099),
        );
        expect(presentation, isNotNull);
        expect(
          presentation!.assignedPresentation,
          TodayExperiencePresentation.standard,
        );
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    test(
      'an old caller timestamp cannot grant expired participation',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        fixture.clock.now = participationStart.add(const Duration(hours: 2));
        expect(
          await fixture.repository.readActivePermit(
            ownerId: 'owner-a',
            evaluatedAtUtc: participationStart,
          ),
          isNull,
        );
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    test(
      'same revision with different signed payload is an immutable conflict',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        final before = await fixture.stored();
        fixture.use(
          participationPermit(
            expiresAtUtc: participationStart.add(const Duration(hours: 2)),
          ),
        );
        await expectLater(
          fixture.importCurrent(),
          throwsA(isA<ResearchParticipationConflict>()),
        );
        expect(await fixture.stored(), before);
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    test(
      'lower signed revision cannot replace current cached history',
      () async {
        fixture.use(participationPermit(revision: 2));
        expect(await fixture.importCurrent(), isTrue);
        final before = await fixture.stored();
        fixture.use(participationPermit(revision: 1));
        await expectLater(
          fixture.importCurrent(),
          throwsA(isA<ResearchParticipationConflict>()),
        );
        expect(await fixture.stored(), before);
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    for (final pin in ['age-band', 'treatment', 'issued-at']) {
      test('a new revision cannot rewrite immutable $pin', () async {
        expect(await fixture.importCurrent(), isTrue);
        final before = await fixture.stored();
        fixture.use(switch (pin) {
          'age-band' => participationPermit(
            revision: 2,
            ageBandCode: 'another-age-band',
          ),
          'treatment' => participationPermit(
            revision: 2,
            treatment: TodayExperiencePresentation.adventure,
          ),
          'issued-at' => participationPermit(
            revision: 2,
            issuedAtUtc: participationStart.subtract(
              const Duration(minutes: 4),
            ),
          ),
          _ => throw StateError('unknown fixture'),
        });
        await expectLater(
          fixture.importCurrent(),
          throwsA(isA<ResearchParticipationConflict>()),
        );
        expect(await fixture.stored(), before);
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      });
    }

    test(
      'a new signed revision can renew expiry and a configured issuer key',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        fixture.clock.now = participationStart.add(const Duration(minutes: 30));
        fixture.use(
          participationPermit(
            revision: 2,
            issuerKeyId: participationRotatedKeyId,
            expiresAtUtc: participationStart.add(const Duration(hours: 3)),
          ),
        );
        expect(await fixture.importCurrent(), isTrue);
        final context = await fixture.participant();
        expect(context, isNotNull);
        expect(context!.permit.issuerKeyId, participationRotatedKeyId);
        expect(context.permit.localRevision, 2);
        expect(context.permit.cloudRevision, 2);
        expect(context.assignment.assignedAtUtc, participationStart);
        expect(
          (await fixture.stored())['expires_at_utc_ms'],
          fixture.current.expiresAtUtc.millisecondsSinceEpoch,
        );
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    test(
      'an unknown issuer key cannot replace an existing cache row',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        final before = await fixture.stored();
        fixture.use(
          participationPermit(
            revision: 2,
            issuerKeyId: 'unconfigured-issuer-key',
          ),
        );
        expect(await fixture.importCurrent(), isFalse);
        expect(await fixture.stored(), before);
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    test(
      'a second currently eligible permit ID conflicts without creating history',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        fixture.use(participationPermit(id: 'another-active-permit'));
        await expectLater(
          fixture.importCurrent(),
          throwsA(isA<ResearchParticipationConflict>()),
        );
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    test(
      'an expired prior permit is retained while a newly issued ID is admitted',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        final firstId = fixture.current.id;
        fixture.clock.now = participationStart.add(const Duration(hours: 2));
        final issuedAt = participationStart.add(const Duration(minutes: 90));
        fixture.operations.current = participationOperation(
          revision: 2,
          issuedAtUtc: issuedAt,
        );
        fixture.states.revision = 2;
        fixture.use(
          participationPermit(
            id: 'new-participation-id',
            issuedAtUtc: issuedAt,
            expiresAtUtc: participationStart.add(const Duration(hours: 3)),
          ),
        );
        expect(await fixture.importCurrent(), isTrue);
        final current = await fixture.participant();
        expect(current, isNotNull);
        expect(current!.assignment.assignedAtUtc, participationStart);
        expect(
          current.assignment.assignedAtUtc.isBefore(current.permit.issuedAtUtc),
          isTrue,
        );
        expect(await fixture.participant(permitId: firstId), isNull);
        expect((await fixture.stored(firstId))['local_revision'], 1);
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 2,
        );
      },
    );

    for (final narrowing in ['revocation', 'deletion']) {
      test(
        'signed $narrowing imports after expiry and withdrawal without collect authority',
        () async {
          expect(await fixture.importCurrent(), isTrue);
          fixture.clock.now = participationStart.add(const Duration(hours: 2));
          await fixture.withdraw();
          fixture.operations.available = false;
          fixture.receipts.inactive.addAll(ResearchReceiptKind.values);
          fixture.use(
            participationPermit(
              revision: 2,
              deleted: narrowing == 'deletion',
              revokedAtUtc: narrowing == 'revocation'
                  ? participationStart.add(const Duration(minutes: 30))
                  : null,
            ),
          );
          final operationsBefore = fixture.operations.calls;
          final receiptsBefore = fixture.receipts.calls;

          expect(await fixture.importCurrent(), isTrue);
          expect(fixture.operations.calls, operationsBefore);
          expect(fixture.receipts.calls, receiptsBefore);
          final stored = await fixture.stored();
          expect(stored['local_revision'], 2);
          expect(stored['cloud_revision'], 2);
          expect(await fixture.participant(), isNull);
          await expectParticipationArtifacts(
            fixture.database,
            assignments: 1,
            permits: 1,
          );
        },
      );
    }

    test(
      'signed inactivity cannot create a first participation or assignment',
      () async {
        fixture.use(participationPermit(revokedAtUtc: participationStart));
        expect(await fixture.importCurrent(), isFalse);
        await expectParticipationArtifacts(fixture.database);
      },
    );

    test(
      'future revocation cannot bypass withdrawn consent as a narrowing update',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        final before = await fixture.stored();
        await fixture.withdraw();
        fixture.use(
          participationPermit(
            revision: 2,
            revokedAtUtc: participationStart.add(const Duration(minutes: 30)),
            expiresAtUtc: participationStart.add(const Duration(hours: 2)),
          ),
        );
        expect(await fixture.importCurrent(), isFalse);
        expect(await fixture.stored(), before);
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    for (final narrowed in ['revoked', 'deleted']) {
      test(
        '$narrowed cached participation cannot be resurrected by a later issuer revision',
        () async {
          expect(await fixture.importCurrent(), isTrue);
          fixture.use(
            participationPermit(
              revision: 2,
              deleted: narrowed == 'deleted',
              revokedAtUtc: narrowed == 'revoked' ? participationStart : null,
            ),
          );
          expect(await fixture.importCurrent(), isTrue);
          final before = await fixture.stored();
          fixture.use(participationPermit(revision: 3));
          await expectLater(
            fixture.importCurrent(),
            throwsA(isA<ResearchParticipationConflict>()),
          );
          expect(await fixture.stored(), before);
          await expectParticipationArtifacts(
            fixture.database,
            assignments: 1,
            permits: 1,
          );
        },
      );
    }

    test('an existing revocation timestamp cannot be postponed', () async {
      expect(await fixture.importCurrent(), isTrue);
      fixture.use(
        participationPermit(revision: 2, revokedAtUtc: participationStart),
      );
      expect(await fixture.importCurrent(), isTrue);
      final before = await fixture.stored();
      fixture.use(
        participationPermit(
          revision: 3,
          revokedAtUtc: participationStart.add(const Duration(seconds: 1)),
        ),
      );
      await expectLater(
        fixture.importCurrent(),
        throwsA(isA<ResearchParticipationConflict>()),
      );
      expect(await fixture.stored(), before);
      await expectParticipationArtifacts(
        fixture.database,
        assignments: 1,
        permits: 1,
      );
    });

    test(
      'a permit insert failure rolls back the assignment created by admission',
      () async {
        await fixture.database.customStatement('''
        CREATE TRIGGER synthetic_permit_insert_failure
        BEFORE INSERT ON research_participation_permits
        BEGIN
          SELECT RAISE(ABORT, 'synthetic permit insert failure');
        END
      ''');
        expect(await fixture.importCurrent(), isFalse);
        await expectParticipationArtifacts(fixture.database);
      },
    );

    test(
      'an owner deletion intent prevents first import without research writes',
      () async {
        await fixture.ownerWrites.beginDeletion(
          ownerId: 'owner-a',
          firebaseUid: 'uid-a',
          idempotencyKey: 'delete:00000000-0000-4000-8000-000000000001',
        );
        expect(await fixture.importCurrent(), isFalse);
        await expectParticipationArtifacts(fixture.database);
      },
    );

    test(
      'requireParticipant rejects a row changed during authority awaits',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        fixture.states.calls = 0;
        fixture.states.onRead = (call) async {
          if (call == 1) {
            await fixture.database.customStatement(
              'UPDATE research_participation_permits SET local_revision = 2, cloud_revision = 2',
            );
          }
        };
        expect(await fixture.participant(), isNull);
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    test(
      'forged cached fields are denied without being repaired from current authority',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        await fixture.database.customStatement(
          'UPDATE research_participation_permits SET payload_sha256 = ?',
          ['0' * 64],
        );
        expect(await fixture.participant(), isNull);
        expect((await fixture.stored())['payload_sha256'], '0' * 64);
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );

    test(
      'constructor rejects an assignment repository bound to another database',
      () async {
        final other = await ParticipationFixture.open();
        addTearDown(other.database.close);
        await fixture.ownerWrites.beginDeletion(
          ownerId: 'owner-a',
          firebaseUid: 'uid-a',
          idempotencyKey: 'delete:00000000-0000-4000-8000-000000000001',
        );
        await fixture.database.customStatement(
          "UPDATE local_owners SET is_active = (id = 'owner-b')",
        );
        expect(
          () => DriftResearchParticipationRepository(
            fixture.database,
            assignments: other.assignments,
          ),
          throwsArgumentError,
        );
        expect(fixture.documents.calls, 0);
        expect(other.documents.calls, 0);
        await expectParticipationArtifacts(fixture.database);
        await expectParticipationArtifacts(other.database);
      },
    );

    test(
      'an expired exact replay is stored history without a fresh active admission',
      () async {
        expect(await fixture.importCurrent(), isTrue);
        final before = await fixture.stored();
        fixture.clock.now = participationStart.add(const Duration(hours: 2));
        expect(await fixture.importCurrent(), isFalse);
        expect(await fixture.stored(), before);
        expect(await fixture.participant(), isNull);
        await expectParticipationArtifacts(
          fixture.database,
          assignments: 1,
          permits: 1,
        );
      },
    );
  });

  for (final failed in ['expiry', 'current-authority']) {
    test(
      'a post-write $failed failure rolls back both new cache and assignment',
      () async {
        final observer = AfterParticipationWrite();
        final fixture = await ParticipationFixture.open(
          database: AppDatabase(
            NativeDatabase.memory().interceptWith(observer),
          ),
        );
        addTearDown(fixture.database.close);
        fixture.use(
          participationPermit(
            expiresAtUtc: participationStart.add(const Duration(seconds: 1)),
          ),
        );
        observer.afterWrite = () async {
          if (failed == 'expiry') {
            fixture.clock.now = participationStart.add(
              const Duration(seconds: 2),
            );
          } else {
            fixture.documents.available = false;
          }
        };
        expect(await fixture.importCurrent(), isFalse);
        expect(observer.didFire, isTrue);
        await expectParticipationArtifacts(fixture.database);
      },
    );
  }

  test(
    'Ed collect expiry after post-authorization cache read rolls back first import',
    () async {
      final observer = AfterAuthorizedParticipationRead(armAfterInsert: true);
      final fixture = await ParticipationFixture.open(
        database: AppDatabase(NativeDatabase.memory().interceptWith(observer)),
      );
      addTearDown(fixture.database.close);
      final edExpiry = participationStart.add(const Duration(seconds: 1));
      fixture.operations.current = participationOperation(
        expiresAtUtc: edExpiry,
      );
      observer.afterRead = () => fixture.clock.now = edExpiry;

      final imported = await fixture.importCurrent();

      expect(observer.didInsert, isTrue);
      expect(observer.didFire, isTrue);
      expect(fixture.clock.now, edExpiry);
      expect(fixture.current.expiresAtUtc.isAfter(fixture.clock.now), isTrue);
      expect(imported, isFalse);
      await expectParticipationArtifacts(fixture.database);
    },
  );

  test(
    'Ed collect expiry after post-authorization cache read denies participant context',
    () async {
      final observer = AfterAuthorizedParticipationRead();
      final fixture = await ParticipationFixture.open(
        database: AppDatabase(NativeDatabase.memory().interceptWith(observer)),
      );
      addTearDown(fixture.database.close);
      final edExpiry = participationStart.add(const Duration(seconds: 1));
      fixture.operations.current = participationOperation(
        expiresAtUtc: edExpiry,
      );
      expect(await fixture.importCurrent(), isTrue);
      final beforePermit = await fixture.stored();
      final beforeAssignment =
          (await fixture.database
                  .customSelect('SELECT * FROM experiment_assignments')
                  .getSingle())
              .data;
      observer.afterRead = () => fixture.clock.now = edExpiry;
      fixture.states.onRead = (_) async {
        observer.armed = true;
      };

      final context = await fixture.participant();

      expect(observer.didFire, isTrue);
      expect(fixture.clock.now, edExpiry);
      expect(fixture.current.expiresAtUtc.isAfter(fixture.clock.now), isTrue);
      expect(await fixture.stored(), beforePermit);
      expect(
        (await fixture.database
                .customSelect('SELECT * FROM experiment_assignments')
                .getSingle())
            .data,
        beforeAssignment,
      );
      await expectParticipationArtifacts(
        fixture.database,
        assignments: 1,
        permits: 1,
      );
      expect(context, isNull);
    },
  );

  test(
    'a post-write owner change cannot leave an imported permit or assignment',
    () async {
      final observer = AfterParticipationWrite();
      final fixture = await ParticipationFixture.open(
        database: AppDatabase(NativeDatabase.memory().interceptWith(observer)),
      );
      addTearDown(fixture.database.close);
      observer.afterWrite = () => fixture.database.customStatement(
        "UPDATE local_owners SET is_active = (id = 'owner-b')",
      );

      expect(await fixture.importCurrent(), isFalse);
      expect(observer.didFire, isTrue);
      await expectParticipationArtifacts(fixture.database);
      final active = await (fixture.database.select(
        fixture.database.localOwners,
      )..where((row) => row.isActive.equals(true))).getSingle();
      expect(active.id, 'owner-a');
    },
  );

  test(
    'a reopened file cache still requires independent current issuer authority',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-participation-restart-',
      );
      final ownedPath = await directory.resolveSymbolicLinks();
      final file = File(
        '${directory.path}${Platform.pathSeparator}test.sqlite',
      );
      AppDatabase? first;
      AppDatabase? reopened;
      try {
        first = AppDatabase(NativeDatabase(file));
        final fixture = await ParticipationFixture.open(database: first);
        expect(await fixture.importCurrent(), isTrue);
        final stored = await fixture.stored();
        await first.close();
        first = null;
        reopened = AppDatabase(NativeDatabase(file));
        final restored = await ParticipationFixture.open(
          database: reopened,
          seed: false,
        );

        expect(await restored.stored(), stored);
        expect(await restored.participant(), isNotNull);
        restored.documents.available = false;
        expect(await restored.participant(), isNull);
        expect(await restored.stored(), stored);
        await expectParticipationArtifacts(
          reopened,
          assignments: 1,
          permits: 1,
        );
      } finally {
        await reopened?.close();
        await first?.close();
        if (await directory.exists()) {
          final target = await directory.resolveSymbolicLinks();
          final parent = await Directory.systemTemp.resolveSymbolicLinks();
          final separator = Platform.pathSeparator;
          final prefix =
              '$parent${parent.endsWith(separator) ? '' : separator}lexiquest-participation-restart-';
          if (target != ownedPath ||
              !target.startsWith(prefix) ||
              Directory(target).parent.path != parent) {
            throw StateError(
              'refusing to remove an unowned temporary directory',
            );
          }
          await Directory(target).delete(recursive: true);
        }
      }
    },
  );
}
