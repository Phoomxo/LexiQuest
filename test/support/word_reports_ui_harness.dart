import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/application/saved_words_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/application/word_report_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_saved_words_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_word_report_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import 'configured_quiz_harness.dart';
import 'saved_words_ui_harness.dart' show uiWord;

export 'configured_quiz_harness.dart';
export 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

final class WordReportsUiHarness {
  WordReportsUiHarness._(this.storage, {required bool real}) {
    vocabulary = VocabularyUseCases(
      owners: storage.owners,
      vocabulary: DriftVocabularyRepository(storage.database),
      generateId: () => 'synthetic-report-word-${++ids}',
      nowUtc: () => storage.now,
    );
    progress = ProgressUseCases(
      owners: storage.owners,
      queries: DriftProgressQueries(storage.database),
      nowUtc: () => storage.now,
    );
    repository = real
        ? DriftWordReportRepository(
            database: storage.database,
            ownerWriteCoordinator: storage.ownerWrites,
          )
        : WordReportsUiRepository();
    reports = WordReportUseCases(
      repository: repository,
      generateId: () {
        allocations++;
        return 'synthetic-report-${++ids}';
      },
      nowUtc: () {
        clockReads++;
        return storage.now;
      },
    );
    ownerChanges = real
        ? progress.watchActiveOwnerId()
        : Stream<String?>.multi((events) {
            events.add(ownerId);
            final subscription = owners.stream.listen(
              events.add,
              onError: events.addError,
              onDone: events.close,
            );
            events.onCancel = subscription.cancel;
          }, isBroadcast: true);
  }
  static Future<WordReportsUiHarness> open({
    bool real = false,
    File? file,
    bool seed = true,
  }) async => WordReportsUiHarness._(
    await ConfiguredQuizHarness.open(file: file, seed: seed),
    real: real,
  );
  final ConfiguredQuizHarness storage;
  final owners = StreamController<String?>.broadcast(sync: true);
  String? ownerId = configuredOwnerId;
  late final VocabularyUseCases vocabulary;
  late final ProgressUseCases progress;
  late final WordReportRepository repository;
  late final WordReportUseCases reports;
  late final Stream<String?> ownerChanges;
  int ids = 0;
  int allocations = 0;
  int clockReads = 0;
  WordReportsUiRepository get fake => repository as WordReportsUiRepository;
  WordReportTarget get target =>
      WordReportTarget.fromWord(uiWord(configuredWordIds.first, 'station'));
  AppDependencies dependencies({
    bool includeReports = true,
    bool includeSaved = false,
  }) => AppDependencies(
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
    vocabulary: vocabulary,
    progress: progress,
    wordReports: includeReports ? reports : null,
    savedWords: includeSaved
        ? SavedWordsUseCases(
            repository: DriftSavedWordsRepository(
              storage.database,
              ownerWrites: storage.ownerWrites,
            ),
            generateId: () => 'synthetic-report-save-${++ids}',
            nowUtc: () => storage.now,
          )
        : null,
  );
  void changeOwner(String? value) {
    ownerId = value;
    owners.add(value);
  }

  Future<void> close() async {
    if (repository is WordReportsUiRepository) {
      fake.release();
      await fake.changes.close();
    }
    await owners.close();
    await storage.close();
  }
}

final class WordReportsUiRepository implements WordReportRepository {
  final rows = <String, StoredWordReport>{};
  final commands = <WordReportCommand>[];
  final changes = StreamController<void>.broadcast(sync: true);
  Completer<void>? gate;
  bool loseNextAck = false;
  WordReportFailureCode? rejectNext;
  bool holdRead = false;
  int failedReads = 0;
  void release() {
    final pending = gate;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  @override
  Future<SubmitResult> submit(WordReportCommand command) async {
    commands.add(command);
    final rejection = rejectNext;
    rejectNext = null;
    if (rejection != null) {
      throw WordReportException(rejection);
    }
    final existing = rows[command.id];
    if (existing != null && !existing.matchesCommand(command)) {
      throw const WordReportException(WordReportFailureCode.collision);
    }
    final row =
        existing ??
        StoredWordReport(
          id: command.id,
          ownerId: command.expectedOwnerId,
          target: command.target,
          reason: command.reason,
          comment: command.comment,
          queuedAtUtc: command.queuedAtUtc,
        );
    rows[command.id] = row;
    changes.add(null);
    await gate?.future;
    if (loseNextAck) {
      loseNextAck = false;
      throw StateError('synthetic ACK loss');
    }
    return SubmitResult(
      status: existing == null ? SubmitStatus.queued : SubmitStatus.replayed,
      report: row,
    );
  }

  @override
  Stream<List<StoredWordReport>> watchOwner(String expectedOwnerId) async* {
    if (failedReads > 0) {
      failedReads--;
      throw StateError('synthetic read failure');
    }
    List<StoredWordReport> snapshot() =>
        rows.values.where((row) => row.ownerId == expectedOwnerId).toList()
          ..sort((a, b) {
            final time = a.queuedAtUtc.compareTo(b.queuedAtUtc);
            return time == 0 ? a.id.compareTo(b.id) : time;
          });
    if (!holdRead) {
      yield snapshot();
    }
    await for (final _ in changes.stream) {
      yield snapshot();
    }
  }
}

Future<void> reportsUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  fail('Report UI did not appear: $finder');
}

Future<void> closeReportsUi(WidgetTester tester, WordReportsUiHarness h) async {
  if (h.repository is WordReportsUiRepository) {
    h.fake.release();
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(h.close);
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-report-guest');
}
