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

const nativeTodayPackage = 'com.lexiquest.app.nativeTodayBy';

/// Only synthetic data in a fresh run directory; verify cannot seed or admit.
final class NativeTodayFixture {
  NativeTodayFixture._(this.directory, this.runId, this.seedMode)
    : database = AppDatabase(
        NativeDatabase(File('${directory.path}/resume.sqlite')),
      );
  final Directory directory;
  final String runId;
  final bool seedMode;
  final AppDatabase database;
  final network = TodayNoNetwork();
  late final AppDependencies dependencies;
  final HttpOverrides? previousNetwork = HttpOverrides.current;
  String get ownerId => 'local:synthetic-$runId-owner';
  late String sessionId;
  Map<String, Object?> _lastRows = {};
  LearningUseCases get learning => dependencies.learning!;

  static Future<NativeTodayFixture> open(
    Directory support,
    String runId, {
    required bool seed,
    bool requireAndroidSandbox = false,
  }) async {
    if (!RegExp(r'^by-[a-z0-9-]{1,48}$').hasMatch(runId)) {
      throw ArgumentError('Invalid run');
    }
    final canonical = await support.resolveSymbolicLinks();
    if (requireAndroidSandbox &&
        (!Platform.isAndroid ||
            ![
              '/data/user/0/$nativeTodayPackage/files',
              '/data/data/$nativeTodayPackage/files',
            ].contains(canonical))) {
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
    final fixture = NativeTodayFixture._(dir, runId, seed);
    final prefs = await SharedPreferences.getInstance();
    final entry = SharedPreferencesAppEntryStateStore(prefs);
    await prefs.reload();
    if (seed) {
      if (prefs.containsKey('by-guest') ||
          await entry.read() == AppEntryMode.guest) {
        await fixture.database.close();
        throw StateError('Guest collision');
      }
      await prefs.setString('by-guest', runId);
      await entry.markGuest();
      await DriftLocalOwnerRepository(
        fixture.database,
        generateId: () => 'synthetic-$runId-owner',
        nowUtc: () => DateTime.utc(2026, 9, 28),
      ).getOrCreateActiveOwner();
    } else {
      if (prefs.getString('by-guest') != runId ||
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
        guestSessionService: TodayNoLogin(),
        createDatabase: () => fixture.database,
        createEntryStateStore: () async => entry,
        applicationSupportDirectoryProvider: () async => dir,
        buildAiTutor: (_) async => throw StateError('BY no AI'),
        buildVoice: (_) async => throw StateError('BY no voice'),
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
            id: 'synthetic-by-category',
            ownerId: ownerId,
            name: 'Synthetic BY',
            normalizedName: 'synthetic bw',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final word in [
      ('synthetic-by-a', 'cat', 'แมว'),
      ('synthetic-by-b', 'dog', 'สุนัข'),
    ]) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: word.$1,
              ownerId: ownerId,
              categoryId: 'synthetic-by-category',
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
      categoryId: 'synthetic-by-category',
      limit: 2,
    );
    sessionId = session.id;
    if (session.ownerId != ownerId ||
        session.ordinaryMeaningPlan == null ||
        session.questions.length != 2) {
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
    // Actual bootstrap also applies one canonical coin projection.
    // Preserve these ordinary local rows, requiring no upload/lease/attempt.
    final ordinaryOutbox = (rows['outbox_operations'] as List)
        .cast<Map<String, Object?>>();
    final attempts = (rows['answer_attempts'] as List)
        .cast<Map<String, Object?>>();
    final rewards = (rows['reward_transactions'] as List)
        .cast<Map<String, Object?>>();
    if (attempts.length != 1 || rewards.length != 1) {
      throw StateError('Expected one answer and one canonical coin grant');
    }
    if (rewards.single['owner_id'] != ownerId ||
        rewards.single['transaction_type'] != 'coinGrant' ||
        rewards.single['amount'] != 1 ||
        rewards.single['source_event_id'] != attempts.single['id']) {
      throw StateError('Canonical coin grant identity changed');
    }
    final expectedIds = {
      'attempt:${attempts.single['id']}:1',
      'achievementUnlock:achievement:$ownerId:first_answer:1:1',
      'achievementUnlock:achievement:$ownerId:first_correct:1:1',
      'rewardTransaction:${rewards.single['id']}:1',
    };
    if (ordinaryOutbox.length != 4 ||
        ordinaryOutbox.any(
          (r) =>
              !expectedIds.contains(r['operation_id']) ||
              r['owner_id'] != ownerId ||
              ![
                'attempt',
                'achievementUnlock',
                'rewardTransaction',
              ].contains(r['entity_type']) ||
              r['state'] != 'pending' ||
              r['attempt_count'] != 0 ||
              r['last_attempt_at_utc_ms'] != null ||
              r['lease_token'] != null ||
              r['acknowledged_at_utc_ms'] != null,
        )) {
      throw StateError(
        'Unexpected synthetic ordinary outbox: ${jsonEncode(ordinaryOutbox)}',
      );
    }
    const outbox =
        0; // Non-allowlisted or attempted outbox; ordinary rows counted separately.
    if (research != 0 || network.calls != 0) {
      throw StateError('Research or network isolation violated');
    }
    final events = (rows['events_v2'] as List).cast<Map<String, Object?>>();
    if (events.any((r) => r['experiment_context_json'] != null)) {
      throw StateError('Research event found');
    }
    if (counts['learning_sessions'] != 1 || counts['answer_attempts'] != 1) {
      throw StateError('Expected one canonical answer/session');
    }
    final recovery = await recover();
    final p = recovery.progress;
    if (p.index != 0 ||
        p.phase != 'answered' ||
        p.selected != p.plan.questions.first.correctOption ||
        p.evidence == null) {
      throw StateError('Feedback not durably frozen');
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
      'ownerId': ownerId,
      'sessionId': sessionId,
      'index': p.index,
      'progressPhase': p.phase,
      'tableCounts': counts,
      'externalCalls': network.calls,
      'researchRows': research,
      'outboxRows': outbox,
      'ordinaryLocalOutboxRows': ordinaryOutbox.length,
    };
  }

  Future<void> verifySealed() async {
    final expected = await File('${directory.path}/sealed.json').readAsString();
    if (jsonEncode(await snapshot()) != expected) {
      final prior =
          jsonDecode(
                await File('${directory.path}/sealed-rows.json').readAsString(),
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

  Future<void> closeAndSeal() async {
    if (!seedMode) throw StateError('Verify cannot reseal');
    final data = jsonEncode(await snapshot());
    await File(
      '${directory.path}/sealed-rows.json',
    ).writeAsString(jsonEncode(_lastRows), flush: true);
    await close();
    await File(
      '${directory.path}/sealed.json',
    ).writeAsString(data, flush: true);
  }

  Future<void> close() async {
    await dependencies.dispose();
    HttpOverrides.global = previousNetwork;
  }
}

class TodayNoLogin implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() => throw StateError('BY forbids login');
}

// HTTP clients may be constructed by offline composition; all operations fail.
class TodayNoNetwork extends HttpOverrides {
  int calls = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineClient(this);
}

class _OfflineClient implements HttpClient {
  _OfflineClient(this.network);
  final TodayNoNetwork network;
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) {
    network.calls++;
    throw StateError('BY forbids HTTP operations');
  }
}
