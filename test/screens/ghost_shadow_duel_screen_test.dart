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
  for (final missing in ['time', 'date']) {
    testWidgets('B06 Ghost missing $missing cannot fabricate history or start session', (tester) async {
      final repository = _RetryLearningRepository(failFirstAnswer: false);
      final learning = LearningUseCases(owners: _OwnerRepository(), repository: repository,
        generateId: () => 'missing-history', nowUtc: () => DateTime.utc(2026, 9, 13),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'));
      final progress = ProgressSnapshot(sampleSize: 1, correctCount: 0, wrongCount: 1,
        accuracy: 0, totalXp: 0, completedSessions: 0, streakDays: 0, dueReviewCount: 1,
        masteredWordCount: 0, achievementCount: 0, gameLevel: 1, skills: const [],
        weaknesses: _duelProgress.weaknesses, recommendations: const [],
        averageResponseTimeMs: missing == 'time' ? null : 1000,
        latestEvidenceAtUtc: missing == 'date' ? null : DateTime.utc(2026, 8, 14));
      await tester.pumpWidget(MaterialApp(home: GhostShadowDuelScreen(
        progressLoader: () async => progress, learning: learning,
        evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning))));
      await tester.pumpAndSettle();
      expect(repository.startedSessions, 0);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('ไม่สามารถอ่านประวัติการเรียนได้'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0, 840.0]) {
    testWidgets('B06 Ghost reachable response and result at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _RetryLearningRepository(failFirstAnswer: false);
      var id = 0;
      final learning = LearningUseCases(owners: _OwnerRepository(), repository: repository,
        generateId: () => 'layout-${++id}', nowUtc: () => DateTime.utc(2026, 9, 13),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'));
      await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(width == 320 ? 2 : 1), disableAnimations: true), child: child!),
        home: GhostShadowDuelScreen(progressLoader: () async => _duelProgress,
          learning: learning, evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning))));
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      if (width == 320) {
        // The large-text header places lazy ListView children below its cache.
        expect(find.byType(ListView), findsOneWidget);
        expect(field, findsNothing);
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pump();
        expect(field, findsOneWidget);
      }
      await tester.ensureVisible(field);
      await tester.enterText(field, 'durable');
      final submit = find.widgetWithText(FilledButton, 'ตอบ');
      await tester.scrollUntilVisible(submit, 100, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      expect(submit.hitTestable(), findsOneWidget);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repository.commands, hasLength(1));
      expect(repository.successfulFinishes, 1);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final retire in [false, true]) {
    testWidgets('B06 Ghost ${retire ? 'disposed callback' : 'IME composition'} cannot submit', (tester) async {
      final repository = _RetryLearningRepository(failFirstAnswer: false);
      var id = 0;
      final learning = LearningUseCases(owners: _OwnerRepository(), repository: repository,
        generateId: () => 'boundary-${++id}', nowUtc: () => DateTime.utc(2026, 9, 13),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'));
      await tester.pumpWidget(MaterialApp(home: GhostShadowDuelScreen(
        progressLoader: () async => _duelProgress, learning: learning,
        evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
      )));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.value = TextEditingValue(text: 'durable',
        composing: retire ? TextRange.empty : const TextRange(start: 0, end: 7));
      final submit = field.onSubmitted!;
      if (retire) await tester.pumpWidget(const SizedBox.shrink());
      submit('durable');
      await tester.pumpAndSettle();
      expect(repository.commands, isEmpty);
      expect(tester.takeException(), isNull);
      if (!retire) {
        field.controller!.value = const TextEditingValue(text: 'durable');
        submit('durable');
        await tester.pumpAndSettle();
        expect(repository.commands, hasLength(1));
      }
    });
  }

  testWidgets('B06 Ghost unavailable load can retire without async error', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GhostShadowDuelScreen(
      progressLoader: () async => throw StateError('unavailable'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('ไม่สามารถอ่านประวัติการเรียนได้'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

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

  testWidgets(
    'owner switch keeps Ghost evidence and terminal retry on the session owner',
    (tester) async {
      final owners = _OwnerRepository();
      final repository = _RetryLearningRepository(
        failFirstAnswer: false,
        failFirstFinish: true,
      );
      var nextId = 0;
      final learning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'ghost-owner-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 8, 28, 10, 0, nextId),
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
      owners.activeOwnerId = 'owner-2';
      await tester.enterText(find.byType(TextField), 'durable');
      await tester.tap(find.text('ตอบ'));
      await tester.pumpAndSettle();

      expect(repository.commands.single.ownerId, 'owner-1');
      expect(repository.finishOwnerIds, <String>['owner-1']);
      expect(repository.successfulFinishes, 0);
      expect(
        find.byKey(const ValueKey<String>('ghost-session-close-retry')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('ghost-session-close-retry')),
      );
      await tester.pumpAndSettle();
      expect(repository.finishOwnerIds, <String>['owner-1', 'owner-1']);
      expect(repository.successfulFinishes, 1);
      expect(
        repository.finishOwnerIds.where((ownerId) => ownerId == 'owner-2'),
        isEmpty,
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(repository.finishOwnerIds, <String>['owner-1', 'owner-1']);
      expect(repository.successfulFinishes, 1);
    },
  );
}

final class _OwnerRepository implements LocalOwnerRepository {
  String activeOwnerId = 'owner-1';

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: activeOwnerId, createdAtUtc: DateTime.utc(2026, 8, 14));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RetryLearningRepository implements LearningRepository {
  _RetryLearningRepository({
    this.firstAnswerRelease,
    this.failFirstAnswer = true,
    this.failFirstFinish = false,
  });

  final Completer<void>? firstAnswerRelease;
  final bool failFirstAnswer;
  final bool failFirstFinish;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  final List<String> finishOwnerIds = <String>[];
  var _answerFailed = false;
  var _finishFailed = false;
  int successfulFinishes = 0;
  int startedSessions = 0;

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
  Future<void> startSession(LearningSessionDraft session) async { startedSessions += 1; }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (failFirstAnswer && !_answerFailed) {
      _answerFailed = true;
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
  }) async {
    finishOwnerIds.add(ownerId);
    if (failFirstFinish && !_finishFailed) {
      _finishFailed = true;
      throw StateError('simulated terminal failure');
    }
    successfulFinishes += 1;
    return LearningSessionSummary(
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
  }

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
