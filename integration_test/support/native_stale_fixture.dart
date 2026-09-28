import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/ordinary_meaning_recovery.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/features/session/data/shared_preferences_app_entry_state_store.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/features/adventure/data/adventure_catalog_download_adapter.dart';
import 'package:vocab_learning_app/features/offline_content/application/offline_content_manager.dart';
import 'package:vocab_learning_app/features/offline_content/data/drift_offline_content_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

const nativeStalePackage = 'com.lexiquest.app.nativeStaleCf';
String runIsolatedStalePackage(String runId) {
  if (RegExp(r'^cf-[a-z0-9-]{1,48}$').hasMatch(runId)) {
    return nativeStalePackage;
  }
  throw StateError('Invalid isolated draft run identity');
}

bool nativeStaleSandboxMatches({
  required String canonical,
  required String runId,
  required bool isAndroid,
}) {
  if (!isAndroid) return false;
  final package = runIsolatedStalePackage(runId);
  return {
    '/data/user/0/$package/files',
    '/data/data/$package/files',
  }.contains(canonical);
}

/// Only synthetic data in a fresh run directory; verify cannot seed or admit.
final class NativeStaleFixture {
  NativeStaleFixture._(this.directory, this.runId, this.seedMode)
    : database = AppDatabase(
        NativeDatabase(File('${directory.path}/resume.sqlite')),
      );
  final Directory directory;
  final String runId;
  final bool seedMode;
  final AppDatabase database;
  final network = RecoveryNoNetwork();
  late final AppDependencies dependencies;
  final HttpOverrides? previousNetwork = HttpOverrides.current;
  String get ownerId => 'local:synthetic-$runId-owner';
  late String sessionId;
  Map<String, Object?> _lastRows = {};
  LearningUseCases get learning => dependencies.learning!;

  static Future<NativeStaleFixture> open(
    Directory support,
    String runId, {
    required bool seed,
    bool requireAndroidSandbox = false,
  }) async {
    if (!RegExp(r'^cf-[a-z0-9-]{1,48}$').hasMatch(runId)) {
      throw ArgumentError('Invalid run');
    }
    final canonical = await support.resolveSymbolicLinks();
    if (requireAndroidSandbox &&
        !nativeStaleSandboxMatches(
          canonical: canonical,
          runId: runId,
          isAndroid: Platform.isAndroid,
        )) {
      throw StateError('Not isolated Android sandbox');
    }
    final dir = Directory('$canonical${Platform.pathSeparator}$runId');
    final type = await FileSystemEntity.type(dir.path, followLinks: false);
    if (seed && type != FileSystemEntityType.notFound) {
      throw StateError('Seed collision');
    }
    if (!seed &&
        (type != FileSystemEntityType.directory ||
            !await File('${dir.path}/sealed.json').exists() ||
            !await File('${dir.path}/resume.sqlite').exists())) {
      throw StateError('Verify requires sealed seed');
    }
    if (seed) await dir.create();
    if (await dir.resolveSymbolicLinks() != dir.path) {
      throw StateError('Sandbox escaped');
    }
    final fixture = NativeStaleFixture._(dir, runId, seed);
    final prefs = await SharedPreferences.getInstance();
    final entry = SharedPreferencesAppEntryStateStore(prefs);
    await prefs.reload();
    if (seed) {
      if (prefs.containsKey('cf-guest') ||
          await entry.read() == AppEntryMode.guest) {
        await fixture.database.close();
        throw StateError('Guest collision');
      }
      await prefs.setString('cf-guest', runId);
      await entry.markGuest();
      await DriftLocalOwnerRepository(
        fixture.database,
        generateId: () => 'synthetic-$runId-owner',
        nowUtc: () => DateTime.utc(2026, 9, 28),
      ).getOrCreateActiveOwner();
    } else {
      if (prefs.getString('cf-guest') != runId ||
          await entry.read() != AppEntryMode.guest) {
        await fixture.database.close();
        throw StateError('Guest identity changed');
      }
      final seal =
          jsonDecode(await File('${dir.path}/sealed.json').readAsString())
              as Map<String, dynamic>;
      if (seal['ownerId'] != fixture.ownerId) {
        throw StateError('Sealed owner mismatch');
      }
      fixture.sessionId = seal['sessionId'] as String;
    }
    HttpOverrides.global = fixture.network;
    try {
      fixture.dependencies = await AppBootstrap(
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: () => AppConfig.fromValues(
          voiceApiUrl: 'https://voice.example.com',
          aiApiUrl: 'https://ai.example.com',
          isDebug: false,
        ),
        guestSessionService: RecoveryNoLogin(),
        createDatabase: () => fixture.database,
        createEntryStateStore: () async => entry,
        applicationSupportDirectoryProvider: () async => dir,
        buildAiTutor: (_) async => throw StateError('CF no AI'),
        buildVoice: (_) async => throw StateError('CF no voice'),
        cloudSyncEnabled: false,
        // Keep packaged-only cache verification deterministic across boots.
        // The real verifier still checks bytes; no media/network adapter exists.
        offlineContentOverride: VerifiedOfflineContentManager(
          repository: DriftOfflineContentRepository(fixture.database),
          adapters: [const AdventureCatalogDownloadAdapter()],
          removalAuthority: DriftOfflineContentRemovalAuthority(
            fixture.database,
          ),
          rootDirectory: () async => Directory('${dir.path}/offline-content'),
          nowUtc: () => DateTime.utc(2026, 9, 28),
        ),
        learningPreviewEnabled: true,
      ).initialize();
      if (await fixture.dependencies.activeOwnerIdentities!
              .requireSingleActiveOwnerId() !=
          fixture.ownerId) {
        throw StateError('Bootstrap owner changed');
      }
      return fixture;
    } catch (_) {
      HttpOverrides.global = fixture.previousNetwork;
      rethrow;
    }
  }

  Future<QuizSession> seed() async {
    if (!seedMode) throw StateError('Verify-only forbids seed');
    if ((await database.select(database.learningSessions).get()).isNotEmpty) {
      throw StateError('No reseed');
    }
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'synthetic-cf-category',
            ownerId: ownerId,
            name: 'Synthetic CB',
            normalizedName: 'synthetic ca',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final word in [
      ('synthetic-cf-a', 'cat', 'แมว'),
      ('synthetic-cf-b', 'dog', 'สุนัข'),
    ]) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: word.$1,
              ownerId: ownerId,
              categoryId: 'synthetic-cf-category',
              spelling: word.$2,
              normalizedSpelling: word.$2,
              meaning: word.$3,
              normalizedMeaning: word.$3,
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
    final session = await learning.startQuiz(
      ordinaryMeaning: true,
      categoryId: 'synthetic-cf-category',
      limit: 1,
    );
    sessionId = session.id;
    if (session.ownerId != ownerId ||
        session.ordinaryMeaningPlan == null ||
        session.questions.length != 1) {
      throw StateError('Canonical admission mismatch');
    }
    return session;
  }

  Future<OrdinaryMeaningRecovery> recover() => OrdinaryMeaningRecovery.load(
    learning: learning,
    ownerId: ownerId,
    sessionId: sessionId,
  );

  Future<Map<String, Object?>> snapshot() async {
    await dependencies.learningReconciliation!.drain();
    final rows = <String, Object?>{};
    final counts = <String, int>{};
    final tables = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    var research = 0;
    for (final table in tables) {
      final name = table.read<String>('name');
      if (!RegExp(r'^[a-z0-9_]+$').hasMatch(name)) {
        throw StateError('Table rejected');
      }
      final values =
          (await database.customSelect('SELECT * FROM $name ORDER BY 1').get())
              .map((r) => r.data)
              .toList();
      rows[name] = values;
      counts[name] = values.length;
      if (RegExp(
        r'research|consent|assessment|measurement|motivation_response|experiment_assignment',
      ).hasMatch(name)) {
        research += values.length;
      }
    }
    final ordinaryOutbox = (rows['outbox_operations'] as List)
        .cast<Map<String, Object?>>();
    final attempts = (rows['answer_attempts'] as List)
        .cast<Map<String, Object?>>();
    final rewards = (rows['reward_transactions'] as List)
        .cast<Map<String, Object?>>();
    if (counts.length != 58 ||
        counts['learning_sessions'] != 1 ||
        (rows['learning_sessions'] as List).single['state'] != 'active' ||
        attempts.isNotEmpty ||
        rewards.isNotEmpty ||
        (rows['srs_states'] as List).isNotEmpty ||
        (rows['achievement_unlocks'] as List).isNotEmpty ||
        ordinaryOutbox.isNotEmpty ||
        research != 0 ||
        network.calls != 0) {
      throw StateError(
        'Draft must not create answer/evidence/score/SRS/reward/outbox/research/network writes',
      );
    }
    final events = (rows['events_v2'] as List).cast<Map<String, Object?>>();
    if (events.any((r) => r['experiment_context_json'] != null)) {
      throw StateError('Research event found');
    }
    final checkpoints = events
        .where((r) => r['event_type'] == 'LearningActivityCheckpoint')
        .toList();
    if (checkpoints.isEmpty) throw StateError('Missing draft checkpoint');
    final latest = checkpoints
        .map(
          (r) =>
              jsonDecode(r['payload_json'] as String) as Map<String, dynamic>,
        )
        .reduce(
          (a, b) => (a['revision'] as int) > (b['revision'] as int) ? a : b,
        );
    final p = OrdinaryMeaningProgress.decode(
      (latest['state'] as Map).cast<String, Object?>(),
    );
    final acknowledged = latest['terminalAcknowledged'] == true;
    if (p.index != 0 ||
        p.phase != 'awaitingAnswer' ||
        p.selected != p.plan.questions.first.correctOption ||
        p.evidence != null ||
        p.closeAt != null ||
        acknowledged ||
        p.plan.session.id != sessionId ||
        p.plan.session.ownerId != ownerId) {
      throw StateError('Draft selection was not durably frozen');
    }
    String digest(Object? value) =>
        sha256.convert(utf8.encode(jsonEncode(value))).toString();
    _lastRows = rows;
    return {
      'fixtureDigest': digest(rows),
      'tableDigests': {
        for (final entry in rows.entries) entry.key: digest(entry.value),
      },
      'planDigest': digest(p.plan.toJson()),
      'progressDigest': digest(p.toJson()),
      'operation': p.evidence?.toJson(),
      'selected': p.selected,
      'answerRows': attempts,
      'checkpointRows': checkpoints,
      'nonCheckpointEventsDigest': digest(
        events
            .where((r) => r['event_type'] != 'LearningActivityCheckpoint')
            .toList(),
      ),
      'ownerId': ownerId,
      'sessionId': sessionId,
      'index': p.index,
      'progressPhase': p.phase,
      'terminalAcknowledged': acknowledged,
      'tableCounts': counts,
      'externalCalls': network.calls,
      'researchRows': research,
      'outboxRows': ordinaryOutbox.length,
      'ordinaryLocalOutboxRows': ordinaryOutbox.length,
    };
  }

  Future<void> verifySealed({String seal = 'sealed'}) async {
    final expected = await File('${directory.path}/$seal.json').readAsString();
    if (jsonEncode(await snapshot()) != expected) {
      final prior =
          jsonDecode(
                await File('${directory.path}/$seal-rows.json').readAsString(),
              )
              as Map<String, dynamic>;
      final changed = <String, Object?>{};
      for (final entry in _lastRows.entries) {
        if (jsonEncode(entry.value) != jsonEncode(prior[entry.key])) {
          changed[entry.key] = {
            'before': prior[entry.key],
            'after': entry.value,
          };
        }
      }
      throw StateError(
        'Sealed synthetic canonical state changed: ${jsonEncode(changed)}',
      );
    }
  }

  Future<void> closeAndSealPhase(String phase) async {
    if (phase == 'resume') {
      await close();
      return;
    }
    if (phase != 'seed' || !seedMode) {
      throw StateError('Invalid seal transition');
    }
    final file = File('${directory.path}/sealed.json');
    if (await file.exists()) throw StateError('Immutable seal collision');
    final data = jsonEncode(await snapshot());
    await File(
      '${directory.path}/sealed-rows.json',
    ).writeAsString(jsonEncode(_lastRows), flush: true);
    await close();
    await file.writeAsString(data, flush: true);
  }

  Future<void> close() async {
    await dependencies.dispose();
    HttpOverrides.global = previousNetwork;
  }
}

class RecoveryNoLogin implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() => throw StateError('CF forbids login');
}

// HTTP clients may be constructed by offline composition; all operations fail.
class RecoveryNoNetwork extends HttpOverrides {
  int calls = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineClient(this);
}

class _OfflineClient implements HttpClient {
  _OfflineClient(this.network);
  final RecoveryNoNetwork network;
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) {
    network.calls++;
    throw StateError('CF forbids HTTP operations');
  }
}
