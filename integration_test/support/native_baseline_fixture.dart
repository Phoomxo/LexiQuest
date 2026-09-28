import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/application/display_preferences_controller.dart';
import 'package:vocab_learning_app/features/preferences/data/drift_learner_preferences_repository.dart';
import 'package:vocab_learning_app/features/offline_content/application/offline_content_manager.dart';
import 'package:vocab_learning_app/features/offline_content/data/drift_offline_content_repository.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_state.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';

const nativeBaselinePackage = 'com.lexiquest.app.nativeBaselineBm';
const _content = 'SYNTHETIC BM LOCAL CACHE - NOT INSTRUCTIONAL CONTENT';
const baselineContentIdentity = ContentIdentity(
  type: ContentType.offlineArtifact,
  id: 'synthetic-bm-cache',
  revision: 1,
);

/// Blocks Dart HTTP construction before any transport is opened. Android also
/// removes INTERNET permission, covering plugin/native sockets independently.
final class BaselineNoNetwork extends HttpOverrides {
  int calls = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    calls++;
    throw StateError('Baseline external transport disabled');
  }
}

final class NativeBaselineFixture {
  NativeBaselineFixture._(this.directory, this.runId, this.seedMode)
    : database = AppDatabase(
        NativeDatabase(File('${directory.path}/baseline.sqlite')),
      );
  final Directory directory;
  final String runId;
  final bool seedMode;
  final AppDatabase database;
  final network = BaselineNoNetwork();
  int gatewayCalls = 0;
  int _nextId = 0;
  bool _closed = false;
  late final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'synthetic-$runId-owner',
    nowUtc: _now,
  );
  late final vocabulary = VocabularyUseCases(
    owners: owners,
    vocabulary: DriftVocabularyRepository(database),
    generateId: () => 'synthetic-$runId-${_nextId++}',
    nowUtc: _now,
  );
  late final preferences = LearnerPreferencesUseCases(
    repository: DriftLearnerPreferencesRepository(database),
    owners: owners,
    nowUtc: _now,
  );
  late final display = DisplayPreferencesController(preferences);
  late final offline = VerifiedOfflineContentManager(
    repository: DriftOfflineContentRepository(database),
    adapters: [_LocalBytes()],
    removalAuthority: DriftOfflineContentRemovalAuthority(database),
    rootDirectory: () async => Directory('${directory.path}/offline'),
    nowUtc: _now,
  );
  static DateTime _now() => DateTime.utc(2026, 9, 27);

  static Future<NativeBaselineFixture> open(
    Directory support,
    String runId, {
    required bool seed,
    bool requireAndroidSandbox = false,
  }) async {
    if (!RegExp(r'^bm-[a-z0-9-]{1,48}$').hasMatch(runId)) {
      throw ArgumentError('Invalid run identity');
    }
    final canonical = await support.resolveSymbolicLinks();
    if (requireAndroidSandbox &&
        (!Platform.isAndroid ||
            !(canonical == '/data/user/0/$nativeBaselinePackage/files' ||
                canonical == '/data/data/$nativeBaselinePackage/files'))) {
      throw StateError('Not the isolated Android files sandbox');
    }
    final directory = Directory('$canonical${Platform.pathSeparator}$runId');
    final exists = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (seed && exists != FileSystemEntityType.notFound) {
      throw StateError('Run collision; seed cannot replace data');
    }
    if (!seed &&
        (exists != FileSystemEntityType.directory ||
            !await File('${directory.path}/sealed.json').exists())) {
      throw StateError('Verify requires closed seed');
    }
    if (seed) await directory.create();
    if (await directory.resolveSymbolicLinks() != directory.path) {
      throw StateError('Fixture path escaped sandbox');
    }
    if (!seed && !await File('${directory.path}/baseline.sqlite').exists()) {
      throw StateError('Missing canonical database');
    }
    return NativeBaselineFixture._(directory, runId, seed);
  }

  Future<void> seed() async {
    if (!seedMode) throw StateError('Verify-only fixture forbids seed');
    await owners.getOrCreateActiveOwner();
    await vocabulary.createCategory('Synthetic BM');
    await database
        .into(database.contentManifests)
        .insert(
          ContentManifestsCompanion.insert(
            id: 'synthetic-bm-manifest',
            contentType: 'offlineArtifact',
            contentId: baselineContentIdentity.id,
            revision: 1,
            checksumSha256: sha256.convert(utf8.encode(_content)).toString(),
            byteLength: utf8.encode(_content).length,
            provenance: 'packaged',
            sourceUri: 'asset://synthetic-bm-fixture',
            reviewState: 'approved',
            publicationState: 'published',
            createdAtUtcMs: _now().millisecondsSinceEpoch,
            reviewedAtUtcMs: Value(_now().millisecondsSinceEpoch),
            publishedAtUtcMs: Value(_now().millisecondsSinceEpoch),
          ),
        ); // Synthetic lifecycle metadata; never represents actual content review.
    await offline.download(baselineContentIdentity);
    await display.initialize();
  }

  Future<void> changePreferenceAndCreateWord({
    bool changeDisplay = true,
  }) async {
    if (!seedMode) throw StateError('Verify-only fixture forbids mutations');
    if (changeDisplay) await display.selectThemeMode(ThemeMode.dark);
    final category =
        (await database.select(database.vocabularyCategories).get()).single;
    await vocabulary.createWord(
      CreateWordCommand(
        categoryId: category.id,
        spelling: 'synthetic',
        meaning: 'fixture only',
        partOfSpeech: 'adjective',
      ),
    );
  }

  Future<Map<String, Object?>> snapshot() async {
    final rows = <String, Object?>{};
    for (final table in [
      'local_owners',
      'vocabulary_categories',
      'vocabulary_words',
      'learner_preferences',
      'outbox_operations',
      'events_v2',
    ]) {
      rows[table] =
          (await database.customSelect('SELECT * FROM $table ORDER BY 1').get())
              .map((r) => r.data)
              .toList();
    }
    final cached = await DriftOfflineContentRepository(
      database,
    ).state(baselineContentIdentity);
    if (cached.status != OfflineContentStatus.verified ||
        !OfflineContentArtifactKey.isCanonicalPublishedName(
          cached.localPath ?? '',
        )) {
      throw StateError('Local content unavailable');
    }
    final cachedFile = File(
      '${directory.path}${Platform.pathSeparator}offline${Platform.pathSeparator}${cached.localPath!}',
    );
    if (await cachedFile.readAsString() != _content) {
      throw StateError('Local content bytes changed');
    }
    rows['cacheSha256'] = sha256
        .convert(await cachedFile.readAsBytes())
        .toString();
    final names =
        (await database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table'",
                )
                .get())
            .map((r) => r.read<String>('name'));
    var research = 0;
    final nonzero = <String, int>{};
    for (final name in names.where(
      (n) => RegExp(
        r'research|consent|assessment|measurement|motivation_response|experiment_assignment|answer_attempt|learning_session|srs_state|reward_transaction',
      ).hasMatch(n),
    )) {
      if (!RegExp(r'^[a-z0-9_]+$').hasMatch(name)) {
        throw StateError('Unexpected table name');
      }
      final count =
          (await database
                  .customSelect('SELECT COUNT(*) AS n FROM $name')
                  .getSingle())
              .read<int>('n');
      research += count;
      if (count != 0) nonzero[name] = count;
    }
    // The canonical repository always queues category/word changes. Preserve
    // those ordinary local rows, require no send attempts and reject every
    // other outbox type. Owner creation also emits its existing cutover event.
    final ordinary =
        (await database
                .customSelect(
                  "SELECT COUNT(*) AS n FROM outbox_operations WHERE entity_type IN ('category','word') AND attempt_count=0 AND state='pending'",
                )
                .getSingle())
            .read<int>('n');
    if (ordinary != 2) throw StateError('Canonical vocabulary outbox changed');
    final outbox =
        (await database
                .customSelect(
                  "SELECT COUNT(*) AS n FROM outbox_operations WHERE entity_type NOT IN ('category','word') OR attempt_count<>0 OR state<>'pending'",
                )
                .getSingle())
            .read<int>('n');
    final events = await database
        .customSelect(
          'SELECT event_type, experiment_context_json FROM events_v2',
        )
        .get();
    if (events.length != 1 ||
        events.single.read<String>('event_type') != 'StreakPolicyCutover' ||
        events.single.readNullable<String>('experiment_context_json') != null) {
      throw StateError('Unexpected baseline event');
    }
    if (research != 0 ||
        outbox != 0 ||
        network.calls != 0 ||
        gatewayCalls != 0) {
      throw StateError(
        'Baseline isolation violated: $nonzero outbox=$outbox network=${network.calls}',
      );
    }
    return {
      'fixtureDigest': sha256.convert(utf8.encode(jsonEncode(rows))).toString(),
      'ownerId': (rows['local_owners'] as List).single['id'],
      'wordId': (rows['vocabulary_words'] as List).single['id'],
      'externalCalls': network.calls + gatewayCalls,
      'researchRows': research,
      'outboxRows': outbox,
      'ordinaryVocabularyOutboxRows': ordinary,
    };
  }

  Future<String> verifySealed() async {
    final expected = jsonDecode(
      await File('${directory.path}/sealed.json').readAsString(),
    );
    final actual = await snapshot();
    if (jsonEncode(actual) != jsonEncode(expected)) {
      throw StateError('Persistent fixture mismatch');
    }
    return actual['fixtureDigest']! as String;
  }

  Future<void> closeAndSeal() async {
    final receipt = await snapshot();
    await close();
    await File(
      '${directory.path}/sealed.json',
    ).writeAsString(jsonEncode(receipt), flush: true);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await offline.dispose();
    display.dispose();
    await database.close();
  }
}

final class _LocalBytes implements OfflineContentDownloadAdapter {
  @override
  bool supports(ContentManifest manifest) =>
      manifest.identity == baselineContentIdentity;
  @override
  Future<void> stage(ContentManifest manifest, File temporaryFile) async =>
      temporaryFile.writeAsString(_content, flush: true);
  @override
  Future<void> requireInstalledValid(ContentManifest manifest) async {}
  @override
  Future<int> installedBytes(ContentManifest manifest) async => 0;
  @override
  Future<int> removeInstalled(ContentManifest manifest) async => 0;
}
