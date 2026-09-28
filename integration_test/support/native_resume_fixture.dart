import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/ordinary_meaning_recovery.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'native_baseline_fixture.dart' show BaselineNoNetwork;

const nativeResumePackage = 'com.lexiquest.app.nativeResumeBw';

/// Only synthetic data in a fresh run directory; verify cannot seed or admit.
final class NativeResumeFixture {
  NativeResumeFixture._(this.directory, this.runId, this.seedMode)
    : database = AppDatabase(
        NativeDatabase(File('${directory.path}/resume.sqlite')),
      );
  final Directory directory;
  final String runId;
  final bool seedMode;
  final AppDatabase database;
  final network = BaselineNoNetwork();
  String get ownerId => 'local:synthetic-$runId-owner';
  String get sessionId => 'session:synthetic-$runId-session';
  static DateTime now() => DateTime.utc(2026, 9, 28);
  late final owners = DriftLocalOwnerRepository(
    database,
    generateId: () {
      if (!seedMode) throw StateError('Verify cannot create owner');
      return 'synthetic-$runId-owner';
    },
    nowUtc: now,
  );
  late final learning = LearningUseCases(
    owners: owners,
    repository: DriftLearningRepository(database),
    generateId: () {
      if (!seedMode) throw StateError('Verify cannot admit');
      return 'synthetic-$runId-session';
    },
    nowUtc: now,
    buildInfo: const AppBuildInfo(version: 'bw-test', buildId: 'synthetic'),
    eventContextProvider: const BaselineLearningEventContextProvider(),
  );

  static Future<NativeResumeFixture> open(
    Directory support,
    String runId, {
    required bool seed,
    bool requireAndroidSandbox = false,
  }) async {
    if (!RegExp(r'^bw-[a-z0-9-]{1,48}$').hasMatch(runId)) {
      throw ArgumentError('Invalid run');
    }
    final canonical = await support.resolveSymbolicLinks();
    if (requireAndroidSandbox &&
        (!Platform.isAndroid ||
            ![
              '/data/user/0/$nativeResumePackage/files',
              '/data/data/$nativeResumePackage/files',
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
    return NativeResumeFixture._(dir, runId, seed);
  }

  Future<QuizSession> seed() async {
    if (!seedMode) throw StateError('Verify-only forbids seed');
    final existing = await database.select(database.localOwners).get();
    if (existing.isNotEmpty) throw StateError('No reseed');
    final owner = await owners.getOrCreateActiveOwner();
    if (owner.id != ownerId) throw StateError('Owner mismatch');
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'synthetic-bw-category',
            ownerId: ownerId,
            name: 'Synthetic BW',
            normalizedName: 'synthetic bw',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final word in [
      ('synthetic-bw-a', 'cat', 'แมว'),
      ('synthetic-bw-b', 'dog', 'สุนัข'),
    ]) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: word.$1,
              ownerId: ownerId,
              categoryId: 'synthetic-bw-category',
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
      categoryId: 'synthetic-bw-category',
      limit: 2,
    );
    if (session.id != sessionId ||
        session.ownerId != ownerId ||
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
    // Canonical first correct answer queues one attempt and two achievements.
    // Preserve these ordinary local rows, requiring no upload/lease/attempt.
    final ordinaryOutbox = (rows['outbox_operations'] as List)
        .cast<Map<String, Object?>>();
    final expectedIds = {
      'attempt:attempt:synthetic-$runId-session:1',
      'achievementUnlock:achievement:$ownerId:first_answer:1:1',
      'achievementUnlock:achievement:$ownerId:first_correct:1:1',
    };
    if (ordinaryOutbox.length != 3 ||
        ordinaryOutbox.any(
          (r) =>
              !expectedIds.contains(r['operation_id']) ||
              r['owner_id'] != ownerId ||
              !['attempt', 'achievementUnlock'].contains(r['entity_type']) ||
              r['state'] != 'pending' ||
              r['attempt_count'] != 0 ||
              r['last_attempt_at_utc_ms'] != null ||
              r['lease_token'] != null ||
              r['acknowledged_at_utc_ms'] != null,
        )) {
      throw StateError('Unexpected ordinary outbox');
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
    return {
      'fixtureDigest': digest(rows),
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
      throw StateError('Sealed canonical state changed');
    }
  }

  Future<void> closeAndSeal() async {
    if (!seedMode) throw StateError('Verify cannot reseal');
    final data = jsonEncode(await snapshot());
    await close();
    await File(
      '${directory.path}/sealed.json',
    ).writeAsString(data, flush: true);
  }

  Future<void> close() => database.close();
}
