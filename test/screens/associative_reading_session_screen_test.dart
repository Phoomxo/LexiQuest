import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';

void main() {
  group('B3 Associative Reading Session Screen Tests', () {
    late AppDatabase database;
    late DriftLocalOwnerRepository owners;
    late LearningUseCases learning;
    late InMemoryAssociativeLearningAdapter associativeLearning;
    var id = 0;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'reading-owner',
        nowUtc: () => DateTime.utc(2026, 8, 9, 10),
      );
      await owners.getOrCreateActiveOwner();
      learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'reading-${++id}',
        nowUtc: () => DateTime.utc(2026, 8, 9, 10),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'associative-reading-screen-test',
        ),
      );
      associativeLearning = InMemoryAssociativeLearningAdapter();
    });

    tearDown(() => database.close());

    Widget session({
      List<String> targetWords = const ['ephemeral', 'resilient'],
      Map<String, String>? targetWordIds,
      AssociativeLearningPort? port,
      LearningUseCases? learningUseCases,
    }) {
      return MaterialApp(
        home: AssociativeReadingSessionScreen(
          cefrLevel: 'B2',
          targetWords: targetWords,
          targetWordIds: targetWordIds,
          passageText:
              'Life is filled with ephemeral moments that require a resilient spirit to appreciate.',
          learning: learningUseCases ?? learning,
          associativeLearning: port ?? associativeLearning,
        ),
      );
    }

    Future<void> pumpUntilFound(
      WidgetTester tester,
      Finder finder, {
      int maxPumps = 100,
    }) async {
      for (var index = 0; index < maxPumps; index++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (finder.evaluate().isNotEmpty) return;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      fail('Widget did not appear after $maxPumps bounded pumps: $finder');
    }

    testWidgets('Renders stages and progresses through 6 stages', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(session());
      await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));

      expect(find.text('Associative Reading (B2)'), findsOneWidget);
      expect(find.text('Stage 1: Supported Reading'), findsOneWidget);
      expect(find.textContaining('ephemeral moments'), findsOneWidget);

      for (var stage = 2; stage <= 6; stage++) {
        if (stage == 5) {
          for (var index = 0; index < 2; index++) {
            await tester.enterText(
              find.byType(TextField).at(index),
              'memory cue $index',
            );
          }
        }
        await tester.tap(find.text('Complete & Continue'));
        final title = 'Stage $stage: ${_stageName(stage)}';
        await pumpUntilFound(tester, find.text(title));
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Ready to finish'), findsOneWidget);
    });

    testWidgets('Stage 3 shows one TextField per target word', (tester) async {
      await tester.pumpWidget(session());
      await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Complete & Continue'));
        await pumpUntilFound(
          tester,
          find.text('Stage ${i + 2}: ${_stageName(i + 2)}'),
        );
      }

      expect(find.text('Stage 3: Active Recall'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Word 1'), findsOneWidget);
      expect(find.text('Word 2'), findsOneWidget);
    });

    testWidgets(
      'Stage 4 saves owner-scoped association and initial memory state',
      (tester) async {
        await tester.pumpWidget(
          session(
            targetWords: const ['banana'],
            targetWordIds: const {'banana': 'word-banana'},
          ),
        );
        await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));

        for (var i = 0; i < 3; i++) {
          await tester.tap(find.text('Complete & Continue'));
          await pumpUntilFound(
            tester,
            find.text('Stage ${i + 2}: ${_stageName(i + 2)}'),
          );
        }
        expect(find.text('Stage 4: Memory Association'), findsOneWidget);

        await tester.enterText(find.byType(TextField).first, 'yellow fruit');
        await tester.tap(find.text('Complete & Continue'));
        await pumpUntilFound(tester, find.text('Stage 5: Context Transfer'));
        expect(find.text('Stage 5: Context Transfer'), findsOneWidget);

        final owner = await owners.getOrCreateActiveOwner();
        final associations = await associativeLearning.getAssociationsForWord(
          owner.id,
          'word-banana',
        );
        final memory = await associativeLearning.getMemoryState(
          owner.id,
          'word-banana',
        );
        expect(associations, hasLength(1));
        expect(associations.single.content, 'yellow fruit');
        expect(associations.single.type, 'keyword');
        expect(memory, isNotNull);
        expect(memory!.ownerId, owner.id);
        expect(memory.wordKey, 'word-banana');
      },
    );

    testWidgets('renders typed unavailable state when learning is absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'A2',
            targetWords: const ['banana'],
            passageText: 'The banana is yellow.',
            associativeLearning: associativeLearning,
          ),
        ),
      );
      await tester.pump();

      final state = tester.widget<AssociativeReadingUnavailable>(
        find.byType(AssociativeReadingUnavailable),
      );
      expect(state.reason, AssociativeReadingUnavailableReason.learning);
    });

    testWidgets(
      'renders typed unavailable state when associative persistence is absent',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: AssociativeReadingSessionScreen(
              cefrLevel: 'A2',
              targetWords: const ['banana'],
              passageText: 'The banana is yellow.',
              learning: learning,
            ),
          ),
        );
        await tester.pump();

        final state = tester.widget<AssociativeReadingUnavailable>(
          find.byType(AssociativeReadingUnavailable),
        );
        expect(
          state.reason,
          AssociativeReadingUnavailableReason.associativeLearning,
        );
      },
    );

    testWidgets('retry reuses pending evidence identity', (tester) async {
      final repository = _RetryLearningRepository();
      var nextId = 0;
      final retryLearning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'associative-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 8, 14, 10, 0, nextId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AssociativeReadingSessionScreen(
            cefrLevel: 'A2',
            targetWords: const ['banana'],
            targetWordIds: const {'banana': 'word-banana'},
            passageText: 'The banana is yellow.',
            learning: retryLearning,
            associativeLearning: associativeLearning,
            sessionId: 'session-1',
          ),
        ),
      );
      await pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
      for (var stage = 2; stage <= 3; stage++) {
        await tester.tap(find.text('Complete & Continue'));
        await pumpUntilFound(
          tester,
          find.text('Stage $stage: ${_stageName(stage)}'),
        );
      }
      await tester.enterText(find.byType(TextField), 'banana');

      await tester.tap(find.text('Complete & Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Stage 3: Active Recall'), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(AssociativeReadingSessionScreen)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete & Continue'));
      await pumpUntilFound(tester, find.text('Stage 4: Memory Association'));

      expect(repository.commands, hasLength(2));
      final first = repository.commands.first;
      final retry = repository.commands.last;
      expect(retry.id, first.id);
      expect(retry.occurredAtUtc, first.occurredAtUtc);
      expect(retry.evidenceContext.toJson(), first.evidenceContext.toJson());
      expect(
        retry.evidenceContext.evidenceClass,
        EvidenceClass.independentRecall,
      );
      expect(retry.evidenceContext.skillId, 'associative-recall');
    });
  });
}

final class _RetryLearningRepository implements LearningRepository {
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  var _recordFailed = false;

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async => null;

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) async {
    return ReadingProgressSnapshot(
      documentId: command.documentId,
      documentRevision: command.documentRevision,
      lastPosition: command.position,
      isCompleted: command.isCompleted,
      updatedAtUtc: command.occurredAtUtc,
    );
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (!_recordFailed) {
      _recordFailed = true;
      throw StateError('simulated local failure');
    }
    return const AnswerRecordResult(inserted: true, srs: null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _stageName(int stage) => switch (stage) {
  2 => 'Cue Fading',
  3 => 'Active Recall',
  4 => 'Memory Association',
  5 => 'Context Transfer',
  6 => 'Finish',
  _ => throw ArgumentError.value(stage),
};
