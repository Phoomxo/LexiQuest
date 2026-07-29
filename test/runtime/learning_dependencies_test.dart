import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/learning/association_record.dart';
import 'package:vocab_learning_app/learning/association_prompt.dart';
import 'package:vocab_learning_app/learning/associative_memory.dart';
import 'package:vocab_learning_app/learning/learning_commit.dart';
import 'package:vocab_learning_app/learning/learning_repository.dart';
import 'package:vocab_learning_app/learning/memory_state.dart';
import 'package:vocab_learning_app/learning/reading_session.dart';
import 'package:vocab_learning_app/learning/secure_id_generator.dart';
import 'package:vocab_learning_app/learning/sync_outbox_entry.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/learning_dependencies.dart';
import 'package:vocab_learning_app/runtime/learning_feature_flags.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

class _StubGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async {
    return const GuestSessionFailed(GuestSessionFailure.unknown);
  }
}

class _StubLearningStore implements LearningRepository, LearningReader {
  @override
  Future<CommitResult> commit(LearningCommit commit) async {
    return CommitResult(
      commitId: commit.commitId,
      disposition: CommitDisposition.applied,
      writtenRecords: commit.recordCount,
    );
  }

  @override
  Future<List<AssociationRecord>> readAssociations({
    required String ownerId,
    required String wordKey,
  }) async {
    return const [];
  }

  @override
  Future<MemoryState?> readMemoryState({
    required String ownerId,
    required String wordKey,
  }) async {
    return null;
  }

  @override
  Future<List<SyncOutboxEntry>> readPendingOutbox({
    required String ownerId,
  }) async {
    return const [];
  }

  @override
  Future<ReadingSession?> readSession({
    required String ownerId,
    required String sessionId,
  }) async {
    return null;
  }
}

AppConfig _validConfig() => AppConfig.fromValues(
  voiceApiUrl: 'https://voice.example.com',
  isDebug: false,
);

AppBootstrap _bootstrap({
  required LearningFeatureFlags featureFlags,
  required LearningDependenciesLoader loadLearningDependencies,
}) {
  return AppBootstrap(
    initializeFirebase: () async {},
    initializeSupabase: () async {},
    loadConfig: _validConfig,
    guestSessionService: _StubGuestSessionService(),
    featureFlags: featureFlags,
    loadLearningDependencies: loadLearningDependencies,
  );
}

void main() {
  test('associative reading and research are closed by default', () {
    const flags = LearningFeatureFlags();

    expect(flags.associativeReadingEnabled, isFalse);
    expect(flags.researchModeEnabled, isFalse);
  });

  test('does not open durable storage while the feature is disabled', () async {
    var loaderCalls = 0;
    final dependencies = await _bootstrap(
      featureFlags: const LearningFeatureFlags(),
      loadLearningDependencies: () async {
        loaderCalls++;
        throw StateError('must not run');
      },
    ).initialize();

    expect(loaderCalls, 0);
    expect(dependencies.learningDependencies, isNull);
  });

  test('retains the learning ports when the feature is enabled', () async {
    final store = _StubLearningStore();
    final expected = LearningDependencies(
      repository: store,
      reader: store,
      associativeMemory: AssociativeMemory(
        repository: store,
        reader: store,
        promptCatalog: CuratedAssociationPromptCatalog(const {}),
        idGenerator: CryptographicIdGenerator(),
        clock: DateTime.now,
      ),
      close: () async {},
    );
    final dependencies = await _bootstrap(
      featureFlags: const LearningFeatureFlags(associativeReadingEnabled: true),
      loadLearningDependencies: () async => expected,
    ).initialize();

    expect(identical(dependencies.learningDependencies, expected), isTrue);
    expect(
      identical(dependencies.learningDependencies?.repository, store),
      isTrue,
    );
    expect(identical(dependencies.learningDependencies?.reader, store), isTrue);
  });

  test('fails closed when durable storage cannot open', () async {
    const sentinel = 'PRIVATE-STORAGE-PATH-7c9f3a';
    final dependencies = await _bootstrap(
      featureFlags: const LearningFeatureFlags(associativeReadingEnabled: true),
      loadLearningDependencies: () async => throw StateError(sentinel),
    ).initialize();

    expect(dependencies.learningDependencies, isNull);
    expect(dependencies.toString(), isNot(contains(sentinel)));
  });
}
