import 'package:vocab_learning_app/features/learning/application/written_practice_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/written_rubric.dart';
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/features/learning/presentation/written_practice_screen.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'dart:io';
import 'dart:convert';

import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/identity/application/owner_generation.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_generation.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/personal_sets_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_personal_set_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/packaged_sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/personal_sets.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/vocabulary/data/packaged_starter_catalog.dart';

void main() {
  late AppDatabase db;
  late Directory directory;
  late File databaseFile;
  late PersonalSetsUseCases sets;

  late PersonalSetRevision original;
  var enabled = true;
  var missing = false;
  String? missingId;
  Future<void> Function()? duringAdmission;
  var serial = 0;
  final now = DateTime.utc(2026, 9, 20);
  Future<void> wire() async {
    Future<Uint8List?> load(ContentIdentity identity) async {
      await duringAdmission?.call();
      if (missing || identity.id == missingId) return null;
      if (identity == PackagedSenseCrosswalk.identity) {
        return File(PackagedSenseCrosswalk.assetPath).readAsBytes();
      }
      return File(
        'assets/content/lexical_metadata/${identity.id.substring(5)}/r${identity.revision}.json',
      ).readAsBytes();
    }

    final manifests = DriftContentManifestRepository(
      db,
      loadArtifactBytes: load,
    );
    await PackagedStarterCatalog.provision(db, manifests, load);
    await manifests.provisionPackagedArtifact(
      PackagedSenseCrosswalk.verify(
        (await load(PackagedSenseCrosswalk.identity))!,
      ),
    );
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'unused',
      nowUtc: () => now,
    );
    Future<String> activeOwner() async =>
        (await owners.getOrCreateActiveOwner()).id;
    sets = PersonalSetsUseCases(
      repository: DriftPersonalSetRepository(
        db,
        SenseCrosswalkRepository(manifests),
        nowUtc: () => now,
      ),
      ownerGeneration: OwnerGeneration(
        activeOwnerId: activeOwner,
        readDurableStamp: DriftOwnerGeneration(db).read,
      ),
      ownerOperations: OwnerOperationCoordinator(
        gate: DriftOwnerOperationGate(db),
        activeOwnerId: activeOwner,
        nowUtc: () => now,
      ),
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('personal-set-activity-');
    databaseFile = File('${directory.path}/data.sqlite');
    db = AppDatabase(NativeDatabase(databaseFile));
    await db.customStatement(
      "INSERT INTO local_owners (id, created_at_utc_ms, is_active) VALUES ('a', 1, 1)",
    );
    enabled = true;
    missing = false;
    missingId = null;
    duringAdmission = null;
    await wire();
    final owner = await sets.begin();
    final pin = SenseCrosswalkPin.fromJson({
      'corpusManifestHash': PackagedSenseCrosswalk.corpusManifestHash,
      'revision': 1,
      'artifactHash': PackagedSenseCrosswalk.artifactHash,
    });
    final crosswalk = await sets.candidates(owner, pin);
    original = PersonalSetRevision.create(
      setId: 'set',
      operationId: 'create',
      expectedPriorRevision: 0,
      createdAtUtcMs: now.millisecondsSinceEpoch,
      title: 'Objects',
      crosswalkPin: pin,
      members: crosswalk.entries.take(2).map((e) => e.ref).toList(),
    );
    await sets.save(owner, original);
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  WrittenPracticeUseCases app() =>
      WrittenPracticeUseCases(sets: sets, isAvailable: () => enabled);
  Future<WrittenPracticeTicket> open() async => app().open(
    await sets.begin(),
    setId: 'set',
    setRevision: 1,
    memberIndex: 0,
    activityId: 'writing',
  );
  test(
    'assessed result and revision survive SQLite restart without canonical writes',
    () async {
      final service = app();
      final ticket = await open();
      expect(ticket.target, 'book');
      final first = await service.submit(
        ticket,
        operationId: 'answer1',
        response: 'I read a book.',
      );
      expect(first.results.single.status, RubricStatus.assessed);
      final revised = await service.submit(
        first,
        operationId: 'answer2',
        response: 'She reads a book.',
      );
      expect(revised.results.length, 2);
      await db.close();
      db = AppDatabase(NativeDatabase(databaseFile));
      await wire();
      final resumed = await open();
      expect(resumed.results.map((r) => r.response), [
        'I read a book.',
        'She reads a book.',
      ]);
      expect(await db.select(db.answerAttempts).get(), isEmpty);
      expect(await db.select(db.srsStates).get(), isEmpty);
      expect(await db.select(db.eventsV2).get(), isEmpty);
      expect(await db.select(db.pointsLedgerEntries).get(), isEmpty);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    },
  );
  test(
    'same operation replays; changed payload and stale revision cannot append',
    () async {
      final service = app();
      final ticket = await open();
      await service.submit(
        ticket,
        operationId: 'one',
        response: 'I read a book.',
      );
      expect(
        (await service.submit(
          ticket,
          operationId: 'one',
          response: 'I read a book.',
        )).results.length,
        1,
      );
      await expectLater(
        service.submit(
          ticket,
          operationId: 'one',
          response: 'She reads a book.',
        ),
        throwsStateError,
      );
      await expectLater(
        service.submit(
          ticket,
          operationId: 'two',
          response: 'She reads a book.',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'cancel, feature retirement and content withdrawal reject late results',
    () async {
      final service = app();
      final ticket = await open();
      ticket.cancel();
      await expectLater(
        service.submit(
          ticket,
          operationId: 'cancel',
          response: 'I read a book.',
        ),
        throwsStateError,
      );
      final next = await open();
      enabled = false;
      await expectLater(
        service.submit(next, operationId: 'off', response: 'I read a book.'),
        throwsStateError,
      );
      enabled = true;
      missing = true;
      await expectLater(
        service.submit(
          next,
          operationId: 'missing',
          response: 'I read a book.',
        ),
        throwsA(anything),
      );
      missing = false;
      expect((await open()).results, isEmpty);
    },
  );
  test('owner A B A generation does not resurrect an old ticket', () async {
    final ticket = await open();
    await db.customStatement(
      "INSERT INTO local_owners (id, created_at_utc_ms, is_active) VALUES ('b', 1, 0)",
    );
    await db.customStatement("UPDATE local_owners SET is_active = (id = 'b')");
    await DriftOwnerGeneration(db).advance();
    await db.customStatement("UPDATE local_owners SET is_active = (id = 'a')");
    await DriftOwnerGeneration(db).advance();
    await expectLater(
      app().submit(ticket, operationId: 'stale', response: 'I read a book.'),
      throwsStateError,
    );
  });
  test(
    'guest merge preserves rubric payload; export redacts text; deletion erases it',
    () async {
      await app().submit(
        await open(),
        operationId: 'answer',
        response: 'I read a book.',
      );
      final payload =
          (await db.select(db.writtenPracticeResults).get()).single.payloadJson;
      await db.customStatement(
        "INSERT INTO local_owners(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES('account','writing-user','firebaseBound',1,0)",
      );
      await DriftOwnerUpgradeRepository(
        db,
        nowUtc: () => now,
        generateConflictId: () => 'conflict-${serial++}',
        generateOwnerId: () => 'unused',
        generateOwnerOperationToken: () => 'merge-${serial++}',
        deleteOwnerSecrets: (_) async {},
      ).upgrade(activeOwnerId: 'a', firebaseUid: 'writing-user');
      final row = (await db.select(db.writtenPracticeResults).get()).single;
      expect(row.ownerId, 'account');
      expect(row.payloadJson, payload);
      final archive = await OwnerLifecycleArchiveExporter(
        database: db,
        nowUtc: () => now,
      ).prepareActive();
      expect(utf8.decode(archive.bytes), isNot(contains('I read a book.')));
      expect(utf8.decode(archive.bytes), contains('writtenPracticeResults'));
      await LocalDataDeletion(
        db,
        deleteOwnerSecrets: (_) async {},
      ).eraseAll(ownerId: 'account');
      expect(await db.select(db.writtenPracticeResults).get(), isEmpty);
    },
  );
  test(
    'cancel during content read rolls back the entire pending result',
    () async {
      final ticket = await open();
      duringAdmission = () async {
        ticket.cancel();
      };
      await expectLater(
        app().submit(ticket, operationId: 'late', response: 'I read a book.'),
        throwsStateError,
      );
      duringAdmission = null;
      expect((await open()).results, isEmpty);
    },
  );
  test(
    'backup restores exact revisions idempotently and rejects future/cross-owner data',
    () async {
      final owner = await sets.begin();
      await app().submit(
        await open(),
        operationId: 'backup-result',
        response: 'I read a book.',
      );
      final archive = await app().exportArchive(owner);
      enabled = false;
      expect(await app().exportArchive(owner), archive);
      await db.delete(db.writtenPracticeResults).go();
      await app().restoreArchive(owner, archive);
      await app().restoreArchive(owner, archive);
      enabled = true;
      expect((await open()).results.single.response, 'I read a book.');
      await expectLater(
        app().restoreArchive(owner, {...archive, 'schemaVersion': 999}),
        throwsFormatException,
      );
      await expectLater(
        app().restoreArchive(owner, {...archive, 'ownerId': 'b'}),
        throwsFormatException,
      );
      expect((await open()).results.length, 1);
    },
  );
  test('immutable rows reject replacement and direct rubric mutation', () async {
    await app().submit(
      await open(),
      operationId: 'immutable',
      response: 'I read a book.',
    );
    await expectLater(
      db.customStatement(
        "UPDATE written_practice_results SET payload_json='{}'",
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        'INSERT OR REPLACE INTO written_practice_results SELECT * FROM written_practice_results',
      ),
      throwsA(anything),
    );
    expect((await open()).results.single.scores, [2, 2, 2]);
  });
  test(
    'cancellation after insertion rolls back rather than leaving a late row',
    () async {
      final ticket = await open();
      var sawPendingRow = false;
      duringAdmission = () async {
        if ((await db.select(db.writtenPracticeResults).get()).isNotEmpty) {
          sawPendingRow = true;
          ticket.cancel();
        }
      };
      await expectLater(
        app().submit(
          ticket,
          operationId: 'late-insert',
          response: 'I read a book.',
        ),
        throwsStateError,
      );
      duringAdmission = null;
      expect(sawPendingRow, isTrue);
      expect((await open()).results, isEmpty);
    },
  );

  testWidgets('write assess revise and retire at narrow layout', (
    tester,
  ) async {
    Future<void> settle() async {
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
      }
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
    }

    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final owner = (await tester.runAsync(sets.begin))!;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: WrittenPracticeScreen(
          useCases: app(),
          owner: owner,
          set: original,
        ),
      ),
    );
    await settle();
    await tester.enterText(
      find.byKey(const Key('written-response')),
      'I read a book.',
    );
    await tester.ensureVisible(find.byKey(const Key('written-submit')));
    await tester.tap(find.byKey(const Key('written-submit')));
    await settle();
    expect(find.textContaining('Meaning 2/2'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('written-revise')));
    await tester.tap(find.byKey(const Key('written-revise')));
    await settle();
    await tester.enterText(
      find.byKey(const Key('written-response')),
      'My aunt borrowed a book.',
    );
    await tester.ensureVisible(find.byKey(const Key('written-submit')));
    await tester.tap(find.byKey(const Key('written-submit')));
    await settle();
    expect(find.textContaining('uncertain'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.textContaining('My aunt'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await settle();
  });
}
