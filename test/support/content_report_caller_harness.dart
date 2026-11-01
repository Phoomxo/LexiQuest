import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/ai/content_provider.dart';
import 'package:vocab_learning_app/features/content_reports/application/content_report_use_cases.dart';
import 'package:vocab_learning_app/features/content_reports/data/drift_content_report_queue.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/application/word_report_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_word_report_repository.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../screens/learning_pack_test_support.dart' show LearningPackUiVoice;
import 'configured_quiz_harness.dart';

final class ContentReportCallerHarness {
  ContentReportCallerHarness._(this.storage) {
    queue = DriftContentReportQueue(
      database: storage.database,
      ownerWrites: storage.ownerWrites,
    );
    reports = ContentReportUseCases(
      queue: queue,
      generateId: _id,
      nowUtc: () => storage.now,
      ordinarySessionGuard: queue.requireOrdinarySession,
    );
    wordReports = WordReportUseCases(
      repository: DriftWordReportRepository(
        database: storage.database,
        ownerWriteCoordinator: storage.ownerWrites,
        contentReports: queue,
      ),
      generateId: _id,
      nowUtc: () => storage.now,
    );
    final packReader = DriftLearningPackRepository(
      database: storage.database,
      ownerWrites: storage.ownerWrites,
    );
    packs = LearningPackUseCases(
      repository: packReader,
      nowUtc: () => storage.now,
      generateId: _id,
    );
    learning = LearningUseCases(
      owners: storage.owners,
      repository: DriftLearningRepository(
        storage.database,
        ownerWrites: storage.ownerWrites,
        lexicalContent: packReader,
      ),
      generateId: _id,
      nowUtc: () => storage.now,
      buildInfo: const AppBuildInfo(
        version: 'synthetic',
        buildId: 'synthetic-report-callers',
      ),
      contentProvider: const _Generated(),
    );
    progress = ProgressUseCases(
      owners: storage.owners,
      queries: DriftProgressQueries(storage.database),
      nowUtc: () => storage.now,
    );
    vocabulary = VocabularyUseCases(
      owners: storage.owners,
      vocabulary: DriftVocabularyRepository(storage.database),
      generateId: _id,
      nowUtc: () => storage.now,
    );
  }
  static Future<ContentReportCallerHarness> open() async =>
      ContentReportCallerHarness._(await ConfiguredQuizHarness.open());
  final ConfiguredQuizHarness storage;
  late final DriftContentReportQueue queue;
  late final ContentReportUseCases reports;
  late final WordReportUseCases wordReports;
  late final LearningUseCases learning;
  late final LearningPackUseCases packs;
  late final ProgressUseCases progress;
  late final VocabularyUseCases vocabulary;
  final voice = LearningPackUiVoice();
  int _sequence = 0;
  String _id() => 'synthetic-report-caller-${++_sequence}';

  AppDependencies dependencies({GeminiTutorController? tutor}) =>
      AppDependencies(
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: _Guest(),
        database: storage.database,
        localOwners: storage.owners,
        learning: learning,
        vocabulary: vocabulary,
        learningPacks: packs,
        progress: progress,
        wordReports: wordReports,
        contentReports: reports,
        geminiTutor: tutor,
        voice: VoiceUseCases(voice),
      );
  Widget app(
    Widget screen, {
    GeminiTutorController? tutor,
    ValueNotifier<AppDependencies>? dependencies,
  }) => dependencies == null
      ? AppDependenciesScope(
          dependencies: this.dependencies(tutor: tutor),
          child: MaterialApp(home: screen),
        )
      : ValueListenableBuilder<AppDependencies>(
          valueListenable: dependencies,
          builder: (_, value, _) => AppDependenciesScope(
            dependencies: value,
            child: MaterialApp(home: screen),
          ),
        );
  Future<void> close() async {
    await packs.dispose();
    await storage.close();
  }
}

final class _Generated implements ContentProvider {
  const _Generated();
  @override
  Future<ContentResponse> generate(ContentRequest request) async =>
      ContentResponse(
        text: 'The ${request.text} is useful.',
        kind: request.kind,
        cefr: request.cefr,
        language: request.language,
        modelVersion: 'synthetic-accepted-model',
        cached: true,
      );
}

final class ReportCallerTutor implements GeminiTutorController {
  @override
  GeminiScope? scope = const GeminiScope(
    ownerId: configuredOwnerId,
    firebaseUid: configuredFirebaseUid,
    isAnonymous: false,
  );
  @override
  int epoch = 0;
  final _invalidations = StreamController<int>.broadcast(sync: true);
  @override
  Stream<int> get invalidations => _invalidations.stream;
  String replyText = 'Only the synthetic assistant reply.';
  int calls = 0;
  @override
  Future<GeminiSettingsStatus> loadSettings() async =>
      const GeminiSettingsStatus(
        hasKey: true,
        providerConsent: true,
        shareLearningSummary: false,
      );
  @override
  Future<GeminiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    GeminiTutorMode mode = GeminiTutorMode.guided,
    GeminiCancellation? cancellation,
  }) async {
    calls++;
    return GeminiTutorReply(
      text: replyText,
      model: 'synthetic-tutor-model',
      generatedAtUtc: DateTime.utc(2026, 11, 1),
    );
  }

  void retire() {
    scope = null;
    epoch++;
    _invalidations.add(epoch);
  }

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    GeminiCancellation? cancellation,
  }) async => throw StateError('Unexpected configuration');
  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) async => throw StateError('Unexpected consent change');
  @override
  Future<void> removeKey() async => throw StateError('Unexpected key removal');
  @override
  Future<void> dispose() async {
    await _invalidations.close();
  }
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('Reports cannot create an owner');
}
