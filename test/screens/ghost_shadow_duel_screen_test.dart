import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/ghost_shadow_duel_screen.dart';

void main() {
  testWidgets('fresh account shows zero evidence and no sample words', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GhostShadowDuelScreen(
          progressLoader: () async => _empty,
          learning: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('จำนวนหลักฐาน: 0'), findsOneWidget);
    expect(find.text('perseverance'), findsNothing);
  });

  testWidgets('retry reuses pending evidence identity', (tester) async {
    final repository = _RetryLearningRepository();
    var nextId = 0;
    final learning = LearningUseCases(
      owners: _OwnerRepository(),
      repository: repository,
      generateId: () => 'ghost-${++nextId}',
      nowUtc: () => DateTime.utc(2026, 8, 14, 10, 0, nextId),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GhostShadowDuelScreen(
          progressLoader: () async => _duelProgress,
          learning: learning,
          evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'durable');
    await tester.tap(find.text('ตอบ'));
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(
      tester.element(find.byType(GhostShadowDuelScreen)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(
      find.byKey(const ValueKey<String>('current-evidence-retry')),
    );
    await tester.pumpAndSettle();

    expect(repository.commands, hasLength(2));
    final first = repository.commands.first;
    final retry = repository.commands.last;
    expect(retry.id, first.id);
    expect(retry.occurredAtUtc, first.occurredAtUtc);
    expect(retry.responseTimeMs, first.responseTimeMs);
    expect(retry.evidenceContext.toJson(), first.evidenceContext.toJson());
    expect(retry.evidenceContext.evidenceClass, EvidenceClass.recreational);
  });

  testWidgets(
    'system back cannot discard in-flight or retry-required Ghost evidence',
    (tester) async {
      final firstAnswerRelease = Completer<void>();
      addTearDown(() {
        if (!firstAnswerRelease.isCompleted) firstAnswerRelease.complete();
      });
      final repository = _RetryLearningRepository(
        firstAnswerRelease: firstAnswerRelease,
      );
      var nextId = 0;
      final learning = LearningUseCases(
        owners: _OwnerRepository(),
        repository: repository,
        generateId: () => 'ghost-route-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 8, 14, 11, 0, nextId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                key: const ValueKey<String>('open-ghost-route'),
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => GhostShadowDuelScreen(
                        progressLoader: () async => _duelProgress,
                        learning: learning,
                        evidenceAdapter: CurrentActivityEvidenceAdapter(
                          learning: learning,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open Ghost Duel'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('open-ghost-route')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'durable');
      await tester.tap(find.text('ตอบ'));
      await tester.pump();

      expect(repository.commands, hasLength(1));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byType(GhostShadowDuelScreen),
        findsOneWidget,
        reason: 'an in-flight immutable command must retain its owning route',
      );

      firstAnswerRelease.complete();
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(
        tester.element(find.byType(GhostShadowDuelScreen)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('current-evidence-retry')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byType(GhostShadowDuelScreen),
        findsOneWidget,
        reason: 'a retry-required immutable command must retain its route',
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('current-evidence-retry')),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(repository.commands, hasLength(2));
      expect(find.byType(GhostShadowDuelScreen), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('open-ghost-route')),
        findsOneWidget,
      );
    },
  );
}

final class _OwnerRepository implements LocalOwnerRepository {
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: 'owner-1', createdAtUtc: DateTime.utc(2026, 8, 14));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RetryLearningRepository implements LearningRepository {
  _RetryLearningRepository({this.firstAnswerRelease});

  final Completer<void>? firstAnswerRelease;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  var _failed = false;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) async => const <QuizWord>[
    QuizWord(
      id: 'word-1',
      categoryId: 'category-1',
      spelling: 'durable',
      meaning: 'lasting',
      partOfSpeech: 'adjective',
    ),
  ];

  @override
  Future<void> startSession(LearningSessionDraft session) async {}

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (!_failed) {
      _failed = true;
      await firstAnswerRelease?.future;
      throw StateError('simulated local failure');
    }
    return AnswerRecordResult(
      inserted: true,
      isCorrect: command.isCorrect,
      srs: null,
    );
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async => LearningSessionSummary(
    id: sessionId,
    ownerId: ownerId,
    activityType: 'ghostDuel',
    state: 'completed',
    startedAtUtc: endedAtUtc,
    endedAtUtc: endedAtUtc,
    correctCount: 1,
    wrongCount: 0,
    score: 1,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _empty = ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);

final _duelProgress = ProgressSnapshot(
  sampleSize: 1,
  correctCount: 0,
  wrongCount: 1,
  accuracy: 0,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 1,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: const [],
  weaknesses: const <WeaknessEvidence>[
    WeaknessEvidence(
      wordId: 'word-1',
      spelling: 'durable',
      meaning: 'lasting',
      sampleSize: 1,
      incorrectCount: 1,
      errorRate: 1,
      dueAtUtc: null,
    ),
  ],
  recommendations: const [],
  averageResponseTimeMs: 1000,
  latestEvidenceAtUtc: DateTime.utc(2026, 8, 14),
);
