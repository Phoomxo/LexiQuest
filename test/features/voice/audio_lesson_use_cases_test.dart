import 'dart:async';
import 'package:vocab_learning_app/features/voice/application/audio_lesson_use_cases.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/features/voice/domain/audio_lesson.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
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
  late AudioLessonUseCases service;
  late AudioProvider provider;
  late VoiceUseCases voice;
  setUp(() {
    provider = AudioProvider();
    voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
      operationTimeout: const Duration(seconds: 1),
    );
    service = AudioLessonUseCases(
      sets: sets,
      voice: voice,
      isAvailable: () => enabled,
    );
  });
  tearDown(() async {
    await service.dispose();
    await voice.dispose();
  });
  Future<AudioLessonTicket> open({
    String id = 'audio',
    AudioLessonFormat format = AudioLessonFormat.wordAndExample,
  }) => sets.begin().then(
    (owner) => service.open(
      owner,
      setId: 'set',
      setRevision: 1,
      activityId: id,
      format: format,
    ),
  );
  test('immutable initial pin, duplicate open and format collision', () async {
    final t = await open();
    expect(t.completedSegments, 0);
    expect(t.segments, hasLength(4));
    expect((await open()).pin, t.pin);
    expect(await db.select(db.audioLessonCheckpoints).get(), hasLength(1));
    await expectLater(
      open(format: AudioLessonFormat.shortScenario),
      throwsStateError,
    );
  });
  test(
    'exact completion advances once; text and untagged callbacks cannot',
    () async {
      final t = await open();
      final player = service.player(t);
      provider.tagged = false;
      await player.playNext();
      expect(player.ticket.completedSegments, 0);
      expect(player.state, AudioLessonPlaybackState.textOnly);
      provider.tagged = true;
      await player.playNext();
      expect(player.ticket.completedSegments, 1);
      expect((await open()).completedSegments, 1);
      expect(await db.select(db.answerAttempts).get(), isEmpty);
      expect(await db.select(db.srsStates).get(), isEmpty);
      expect(await db.select(db.pointsLedgerEntries).get(), isEmpty);
      expect(await db.select(db.eventsV2).get(), isEmpty);
      await player.close();
    },
  );
  test(
    'pause drains then resumes incomplete segment without accepting late end',
    () async {
      provider.autoComplete = false;
      final player = service.player(await open());
      final play = player.playNext();
      await provider.waitForStarts(1);
      final old = provider.completions.single;
      provider.stopBarrier = Completer<void>();
      final stop = player.pause();
      expect(player.state, AudioLessonPlaybackState.draining);
      final retry = player.playNext();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(provider.requests, hasLength(1));
      old.complete();
      provider.stopBarrier!.complete();
      await stop;
      await play;
      await retry;
      expect(player.ticket.completedSegments, 0);
      provider.stopBarrier = null;
      final resumed = player.playNext();
      await provider.waitForStarts(2);
      expect(
        provider.requests.last.contentId,
        provider.requests.first.contentId,
      );
      provider.completions.last.complete();
      await resumed;
      expect(player.ticket.completedSegments, 1);
      await player.close();
    },
  );
  test('owner A B A rejects late completion and cache generation', () async {
    provider.autoComplete = false;
    final player = service.player(await open());
    final play = player.playNext();
    await provider.waitForStarts(1);
    await sets.ownerGeneration.duringTransition(() async {});
    provider.completions.single.complete();
    await play;
    expect((await open()).completedSegments, 0);
    expect(player.state, isNot(AudioLessonPlaybackState.ready));
    await player.close();
  });
  test(
    'content withdrawal and flag retirement cannot commit playback',
    () async {
      final player = service.player(await open());
      missing = true;
      await player.playNext();
      expect(provider.requests, isEmpty);
      missing = false;
      enabled = false;
      await player.playNext();
      expect(provider.requests, isEmpty);
      await player.close();
    },
  );
  test(
    'durable restart retains exact transcript and segment boundary',
    () async {
      final player = service.player(await open());
      await player.playNext();
      final pin = player.ticket.pin;
      await player.close();
      await service.dispose();
      await db.close();
      db = AppDatabase(NativeDatabase(databaseFile));
      await wire();
      service = AudioLessonUseCases(
        sets: sets,
        voice: voice,
        isAvailable: () => enabled,
      );
      final reopened = await open();
      expect(reopened.completedSegments, 1);
      expect(reopened.pin, pin);
    },
  );
  test(
    'backup keeps immutable exposure, works with rollout off and rejects corruption',
    () async {
      final player = service.player(await open());
      await player.playNext();
      await player.close();
      final owner = await sets.begin();
      final backup = await service.exportArchive(owner);
      enabled = false;
      await db.delete(db.audioLessonCheckpoints).go();
      await service.restoreArchive(owner, backup);
      await service.restoreArchive(owner, backup);
      expect(await service.exportArchive(owner), backup);
      await expectLater(
        service.restoreArchive(owner, {...backup, 'schemaVersion': 99}),
        throwsFormatException,
      );
      await expectLater(
        service.restoreArchive(owner, {...backup, 'ownerId': 'b'}),
        throwsFormatException,
      );
      enabled = true;
      expect((await open()).completedSegments, 1);
    },
  );
  test(
    'guest merge preserves pins; privacy export counts only; delete erases checkpoints',
    () async {
      final player = service.player(await open());
      await player.playNext();
      await player.close();
      final before = (await db.select(db.audioLessonCheckpoints).get())
          .map((r) => r.payloadJson)
          .toList();
      await db.customStatement(
        "INSERT INTO local_owners(id,firebase_uid,account_state,created_at_utc_ms,is_active) VALUES('account','audio-user','firebaseBound',1,0)",
      );
      await DriftOwnerUpgradeRepository(
        db,
        nowUtc: () => now,
        generateConflictId: () => 'conflict-${serial++}',
        generateOwnerId: () => 'unused',
        generateOwnerOperationToken: () => 'merge-${serial++}',
        deleteOwnerSecrets: (_) async {},
      ).upgrade(activeOwnerId: 'a', firebaseUid: 'audio-user');
      final rows = await db.select(db.audioLessonCheckpoints).get();
      expect(rows.every((r) => r.ownerId == 'account'), isTrue);
      expect(rows.map((r) => r.payloadJson), before);
      final archive = await OwnerLifecycleArchiveExporter(
        database: db,
        nowUtc: () => now,
      ).prepareActive();
      expect(utf8.decode(archive.bytes), contains('audioLessonCheckpoints'));
      expect(utf8.decode(archive.bytes), isNot(contains('Listen to the word')));
      await LocalDataDeletion(
        db,
        deleteOwnerSecrets: (_) async {},
      ).eraseAll(ownerId: 'account');
      expect(await db.select(db.audioLessonCheckpoints).get(), isEmpty);
    },
  );
  test('immutable checkpoint rejects SQL replacement and mutation', () async {
    await open();
    await expectLater(
      db.customStatement(
        "UPDATE audio_lesson_checkpoints SET payload_json='{}'",
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        'INSERT OR REPLACE INTO audio_lesson_checkpoints SELECT * FROM audio_lesson_checkpoints',
      ),
      throwsA(anything),
    );
    expect((await open()).completedSegments, 0);
  });

  test(
    'replay preserves immutable completed checkpoints and original transcript',
    () async {
      final player = service.player(await open());
      for (var i = 0; i < 4; i++) {
        await player.playNext();
      }
      final before = await service.exportArchive(await sets.begin());
      await player.replay();
      await player.playNext();
      expect(
        provider.requests.last.contentId,
        provider.requests.first.contentId,
      );
      expect(player.ticket.completedSegments, 4);
      expect(await service.exportArchive(await sets.begin()), before);
      await player.close();
    },
  );
  test(
    'failed cleanup blocks playback until a successful owned drain retry',
    () async {
      provider.autoComplete = false;
      final player = service.player(await open());
      final play = player.playNext();
      await provider.waitForStarts(1);
      provider.stopFails = true;
      await expectLater(player.pause(), throwsA(anything));
      await play;
      await player.playNext();
      expect(provider.requests, hasLength(1));
      provider.stopFails = false;
      await player.retryCleanup();
      provider.autoComplete = true;
      await player.playNext();
      expect(player.ticket.completedSegments, 1);
      await player.close();
    },
  );
  test(
    'retirement during admission cannot write a completed segment',
    () async {
      provider.autoComplete = false;
      final player = service.player(await open());
      final play = player.playNext();
      await provider.waitForStarts(1);
      duringAdmission = () async {
        player.ticket.cancel();
      };
      provider.completions.single.complete();
      await play;
      duringAdmission = null;
      expect((await open()).completedSegments, 0);
      await player.close();
    },
  );
}

class AudioProvider implements VoiceProvider {
  bool tagged = true, autoComplete = true, stopFails = false;
  Completer<void>? stopBarrier;
  final requests = <VoiceRequest>[];
  final completions = <Completer<void>>[];
  Future<void> waitForStarts(int count) async {
    for (var i = 0; i < 500 && requests.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(requests.length, count);
  }

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    final done = Completer<void>();
    completions.add(done);
    if (autoComplete) done.complete();
    return VoicePlaybackResult(
      requestedEngine: VoiceEngine.offlinePack,
      actualEngine: VoiceEngine.offlinePack,
      usedFallback: false,
      cacheHit: false,
      modelVersion: 'fixture-v1',
      playbackCompleted: tagged ? done.future : null,
    );
  }

  @override
  Future<void> stop() async {
    if (stopFails) throw StateError('fixture stop failed');
    await stopBarrier?.future;
  }
}
