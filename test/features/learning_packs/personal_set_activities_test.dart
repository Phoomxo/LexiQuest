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
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/personal_sets_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/application/personal_set_activities.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_personal_set_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/packaged_sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/personal_sets.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/packaged_starter_catalog.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  late AppDatabase db;
  late Directory directory;
  late File databaseFile;
  late PersonalSetsUseCases sets;
  late PersonalSetActivities activities;
  late LearningUseCases learning;
  late PersonalSetRevision original;
  var enabled = true;
  var missing = false;
  Future<void> Function()? duringAdmission;
  final now = DateTime.utc(2026, 9, 20);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('personal-set-activity-');
    databaseFile = File('${directory.path}/data.sqlite');
    db = AppDatabase(NativeDatabase(databaseFile));
    await db.customStatement(
      "INSERT INTO local_owners (id, created_at_utc_ms, is_active) VALUES ('a', 1, 1)",
    );
    enabled = true;
    missing = false;
    duringAdmission = null;
    Future<Uint8List?> load(ContentIdentity identity) async {
      if (missing) return null;
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
    var serial = 0;
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(
        db,
        lexicalVocabulary: DriftVocabularyRepository(
          db,
          contentManifests: manifests,
        ),
      ),
      generateId: () => 'quiz-${serial++}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      beforeSessionStart: (_) async {
        await duringAdmission?.call();
      },
    );
    activities = PersonalSetActivities(
      sets: sets,
      learning: learning,
      isAvailable: () => enabled,
    );
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
  Future<int> sessionCount() async =>
      (await db.select(db.learningSessions).get()).length;

  test(
    'canonical quiz pins exact saved revision and linkage survives later edit',
    () async {
      final owner = await sets.begin();
      final launch = await activities.start(
        owner,
        setId: 'set',
        revision: 1,
        operationId: 'launch',
      );
      final session = launch.session;
      expect(launch.revision.payloadHash, original.payloadHash);
      expect(
        launch.items.map((i) => i.identity.id),
        original.members.map((r) => r.wordId),
      );
      expect(
        session.questions.map((q) => q.word.id),
        original.members.map((r) => r.wordId),
      );
      expect(await sessionCount(), 1);
      final checkpoint = await learning.loadExactActivityRecovery(
        ownerId: 'a',
        sessionId: session.id,
        activityType: 'personalSetMeaningQuiz',
      );
      expect(
        checkpoint!.checkpoint!.state['personalSetRevision'],
        original.toJson(),
      );
      await sets.save(
        owner,
        PersonalSetRevision.create(
          setId: 'set',
          operationId: 'edit',
          expectedPriorRevision: 1,
          createdAtUtcMs: now.millisecondsSinceEpoch,
          title: 'Changed',
          crosswalkPin: original.crosswalkPin,
          members: (await sets.candidates(
            owner,
            original.crosswalkPin,
          )).entries.take(3).map((e) => e.ref).toList(),
        ),
      );
      final retained = await learning.loadExactActivityRecovery(
        ownerId: 'a',
        sessionId: session.id,
        activityType: 'personalSetMeaningQuiz',
      );
      expect(
        retained!.checkpoint!.state['personalSetRevision'],
        original.toJson(),
      );
      await db.close();
      db = AppDatabase(NativeDatabase(databaseFile));
      final rows = await db
          .customSelect(
            "SELECT owner_id, privacy_classification, payload_json FROM events_v2 WHERE event_type = 'LearningActivityCheckpoint'",
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('owner_id'), 'a');
      expect(rows.single.read<String>('privacy_classification'), 'ownerOnly');
      final payload =
          jsonDecode(rows.single.read<String>('payload_json')) as Map;
      expect(
        (payload['state'] as Map)['personalSetRevision'],
        original.toJson(),
      );
    },
  );
  test('disabled or missing exact content starts no session', () async {
    final owner = await sets.begin();
    enabled = false;
    await expectLater(
      activities.start(owner, setId: 'set', revision: 1, operationId: 'launch'),
      throwsA(isA<StateError>()),
    );
    enabled = true;
    missing = true;
    await expectLater(
      activities.start(owner, setId: 'set', revision: 1, operationId: 'launch'),
      throwsA(isA<Exception>()),
    );
    expect(await sessionCount(), 0);
  });
  test('current publication revoked after save cannot be scored', () async {
    await db.customStatement(
      "UPDATE vocabulary_words SET content_publication_state = 'retired' WHERE id = 'word:starter-book'",
    );
    await expectLater(
      activities.start(
        await sets.begin(),
        setId: 'set',
        revision: 1,
        operationId: 'launch',
      ),
      throwsA(isA<Exception>()),
    );
    expect(await sessionCount(), 0);
  });
  test(
    'generation change inside canonical admission rolls back session and checkpoint',
    () async {
      final owner = await sets.begin();
      duringAdmission = () =>
          sets.ownerGeneration.duringTransition(() async {});
      await expectLater(
        activities.start(
          owner,
          setId: 'set',
          revision: 1,
          operationId: 'launch',
        ),
        throwsA(isA<StateError>()),
      );
      expect(await sessionCount(), 0);
      expect(
        await db
            .customSelect(
              "SELECT event_id FROM events_v2 WHERE event_type = 'LearningActivityCheckpoint'",
            )
            .get(),
        isEmpty,
      );
    },
  );
  test(
    'lost launch acknowledgement replays the same session with no additional writes',
    () async {
      final owner = await sets.begin();
      final first = await activities.start(
        owner,
        setId: 'set',
        revision: 1,
        operationId: 'lost-ack',
      );
      final eventsBefore = (await db.select(db.eventsV2).get()).length;
      final retry = await activities.start(
        owner,
        setId: 'set',
        revision: 1,
        operationId: 'lost-ack',
      );
      expect(retry.session.id, first.session.id);
      expect(await sessionCount(), 1);
      expect((await db.select(db.eventsV2).get()).length, eventsBefore);
      await sets.save(
        owner,
        PersonalSetRevision.create(
          setId: 'set',
          operationId: 'edit-collision',
          expectedPriorRevision: 1,
          createdAtUtcMs: now.millisecondsSinceEpoch,
          title: 'Changed',
          crosswalkPin: original.crosswalkPin,
          members: original.members.reversed.toList(),
        ),
      );
      await expectLater(
        activities.start(
          owner,
          setId: 'set',
          revision: 2,
          operationId: 'lost-ack',
        ),
        throwsStateError,
      );
      expect(await sessionCount(), 1);
    },
  );
  test('disabled during admission rolls back canonical evidence', () async {
    duringAdmission = () async {
      enabled = false;
    };
    await expectLater(
      activities.start(
        await sets.begin(),
        setId: 'set',
        revision: 1,
        operationId: 'late-disabled',
      ),
      throwsStateError,
    );
    expect(await sessionCount(), 0);
    expect(
      await db
          .customSelect(
            "SELECT event_id FROM events_v2 WHERE event_type = 'LearningActivityCheckpoint'",
          )
          .get(),
      isEmpty,
    );
  });
  test(
    'terminal launch operation cannot create a replacement session',
    () async {
      final owner = await sets.begin();
      final launch = await activities.start(
        owner,
        setId: 'set',
        revision: 1,
        operationId: 'terminal',
      );
      await learning.abandonSession(
        ownerId: 'a',
        sessionId: launch.session.id,
        abandonedAtUtc: now,
      );
      await expectLater(
        activities.start(
          owner,
          setId: 'set',
          revision: 1,
          operationId: 'terminal',
        ),
        throwsStateError,
      );
      expect(await sessionCount(), 1);
    },
  );
}
