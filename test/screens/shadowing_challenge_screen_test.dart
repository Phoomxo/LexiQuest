import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/media_dependency_unavailable.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  testWidgets('uses real transcript provenance and never fabricates pitch', (
    tester,
  ) async {
    final voice = _FakeVoice();
    final speech = SpeechPracticeUseCases(_FakeSpeechGateway());
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Practice makes perfect',
          voice: VoiceUseCases(provider: voice, disposeProvider: () async {}),
          speechPractice: speech,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('shadowing-play-reference')));
    await tester.pumpAndSettle();
    expect(voice.requests.single.text, 'Practice makes perfect');

    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('ข้อความที่ได้ยิน: Practice makes perfect'),
      findsOneWidget,
    );
    expect(find.textContaining('ความเหมือนของข้อความ: 100%'), findsOneWidget);
    expect(
      find.textContaining('ไม่ได้ส่งข้อมูล pitch หรือ phoneme'),
      findsOneWidget,
    );
    expect(find.textContaining('Pitch Contour'), findsNothing);
  });

  testWidgets('cancels microphone when app leaves foreground', (tester) async {
    final gateway = _FakeSpeechGateway(
      emitFinal: false,
      cancelError: StateError('recognizer cancel failed'),
    );
    final speech = SpeechPracticeUseCases(gateway);
    final provider = _FakeVoice();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'Keep going',
            voice: voice,
            speechPractice: speech,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('shadowing-play-reference')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
      await tester.pump();
      expect(gateway.isListening, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.runAsync(
        () => provider.stopEntered.future.timeout(
          const Duration(milliseconds: 250),
        ),
      );

      expect(gateway.cancelCalls, 1);
      expect(provider.stopCalls, 1);
      expect(tester.takeException(), isNull);
    } finally {
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        await voice.dispose().timeout(const Duration(seconds: 1));
        try {
          await speech.dispose().timeout(const Duration(seconds: 1));
        } on Object {
          // The recognizer cleanup failure is deliberately injected.
        }
      });
    }
  });

  testWidgets('persists the actual assessment method in learning provenance', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 7, 30, 9);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => now,
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: owner.id,
            name: 'Practice',
            normalizedName: 'practice',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-1',
            ownerId: owner.id,
            categoryId: 'category-1',
            spelling: 'Practice makes perfect',
            normalizedSpelling: 'practice makes perfect',
            meaning: 'practice sentence',
            normalizedMeaning: 'practice sentence',
            partOfSpeech: 'phrase',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    var nextId = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => '${++nextId}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
          speechPractice: SpeechPracticeUseCases(_FakeSpeechGateway()),
          learning: learning,
          evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pumpAndSettle();

    final attempt = await database.select(database.answerAttempts).getSingle();
    expect(
      attempt.providerProvenance,
      'device-stt|en-US|transcript-edit-distance-v1',
    );
  });

  testWidgets('missing media dependencies cannot start a durable quiz', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 7, 30, 9);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => now,
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: owner.id,
            name: 'Practice',
            normalizedName: 'practice',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-1',
            ownerId: owner.id,
            categoryId: 'category-1',
            spelling: 'Keep going',
            normalizedSpelling: 'keep going',
            meaning: 'continue',
            normalizedMeaning: 'continue',
            partOfSpeech: 'phrase',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    var nextId = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => '${++nextId}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          learning: learning,
          evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.widget<MediaDependencyUnavailable>(
      find.byType(MediaDependencyUnavailable),
    );
    expect(state.reason, MediaDependencyUnavailableReason.voice);
    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  testWidgets('late microphone start cancels itself after route disposal', (
    tester,
  ) async {
    final gateway = _PendingSpeechGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Keep going',
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
          speechPractice: SpeechPracticeUseCases(gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 1);
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('shadowing-listen-button')),
          )
          .onPressed,
      isNull,
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(gateway.cancelCalls, 0);

    gateway.allowStart.complete();
    await tester.pump();
    await tester.pump();

    expect(gateway.isListening, isFalse);
    expect(gateway.cancelCalls, 1);
  });

  testWidgets('stale pending route cannot cancel replacement listening', (
    tester,
  ) async {
    final gateway = _TwoStartSpeechGateway();
    final speech = SpeechPracticeUseCases(gateway);
    final voice = VoiceUseCases(
      provider: _FakeVoice(),
      disposeProvider: () async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'First route',
          voice: voice,
          speechPractice: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 1);

    final context = tester.element(find.byType(ShadowingChallengeScreen));
    unawaited(
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => ShadowingChallengeScreen(
            referenceSentence: 'Second route',
            voice: voice,
            speechPractice: speech,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pump();

    expect(gateway.startCalls, 1);
    gateway.startCompletions.first.complete();
    await tester.pump();
    await tester.pump();
    expect(gateway.cancelCalls, 1);
    expect(gateway.startCalls, 2);

    gateway.startCompletions.last.complete();
    await tester.pump();
    await tester.pump();

    expect(gateway.isListening, isTrue);
    expect(gateway.cancelCalls, 1);
  });

  testWidgets('covered route reacquires speech after child pop', (
    tester,
  ) async {
    final gateway = _TwoStartSpeechGateway();
    final speech = SpeechPracticeUseCases(gateway);
    final voice = VoiceUseCases(
      provider: _FakeVoice(),
      disposeProvider: () async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Parent route',
          voice: voice,
          speechPractice: speech,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 1);

    final parentContext = tester.element(find.byType(ShadowingChallengeScreen));
    unawaited(
      Navigator.of(parentContext).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ShadowingChallengeScreen(
            referenceSentence: 'Child route',
            voice: voice,
            speechPractice: speech,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    gateway.startCompletions.first.complete();
    await tester.pump();
    await tester.pump();
    expect(gateway.cancelCalls, 1);

    Navigator.of(tester.element(find.byType(ShadowingChallengeScreen))).pop();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('shadowing-listen-button')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pump();
    expect(gateway.startCalls, 2);
    gateway.startCompletions.last.complete();
    await tester.pump();
    await tester.pump();
    expect(gateway.isListening, isTrue);
  });

  testWidgets(
    'first final freezes callbacks and leaves the completed attempt terminal',
    (tester) async {
      final repository = _RetryLearningRepository(failAnswerOnce: false);
      final learning = LearningUseCases(
        owners: _LearningOwnerRepository(),
        repository: repository,
        generateId: () => 'shadow-terminal',
        nowUtc: () => DateTime.utc(2026, 8, 14, 9),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      final gateway = _ManualSpeechGateway();
      final voice = VoiceUseCases(
        provider: _FakeVoice(),
        disposeProvider: () async {},
      );
      addTearDown(voice.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            voice: voice,
            speechPractice: SpeechPracticeUseCases(gateway),
            learning: learning,
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listen = find.byKey(
        const ValueKey<String>('shadowing-listen-button'),
      );
      final staleListenHandler = tester.widget<FilledButton>(listen).onPressed!;
      await tester.tap(listen);
      await tester.pump();
      gateway.emitFinal('Practice makes perfect');
      await tester.pumpAndSettle();

      expect(repository.commands, hasLength(1));
      expect(repository.finishCalls, hasLength(1));
      expect(
        find.text('ข้อความที่ได้ยิน: Practice makes perfect'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(listen).onPressed, isNull);

      gateway.emitPartial('late partial transcript');
      gateway.emitStatus('listening');
      gateway.emitFailure(SpeechFailureCode.noMatch);
      staleListenHandler();
      await tester.pump();

      expect(
        find.text('ข้อความที่ได้ยิน: Practice makes perfect'),
        findsOneWidget,
      );
      expect(
        find.text('ข้อความที่ได้ยิน: late partial transcript'),
        findsNothing,
      );
      expect(find.text('ไม่ได้ยินเสียงพูดที่ชัดเจน'), findsNothing);
      expect(find.text('หยุดบันทึก'), findsNothing);
      expect(tester.widget<FilledButton>(listen).onPressed, isNull);
      expect(
        gateway.startCalls,
        1,
        reason: 'a completed attempt cannot start an unrecordable utterance',
      );
      expect(repository.commands, hasLength(1));
    },
  );

  for (final throwsAfterFinal in <bool>[false, true]) {
    testWidgets(
      'accepted final fences ${throwsAfterFinal ? 'failed' : 'successful'} start continuation',
      (tester) async {
        final repository = _RetryLearningRepository(failAnswerOnce: false);
        final learning = LearningUseCases(
          owners: _LearningOwnerRepository(),
          repository: repository,
          generateId: () => 'shadow-final-before-return',
          nowUtc: () => DateTime.utc(2026, 8, 15, 10),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        );
        final gateway = _FinalBeforeReturnSpeechGateway(
          throwsAfterFinal: throwsAfterFinal,
        );
        final voice = VoiceUseCases(
          provider: _FakeVoice(),
          disposeProvider: () async {},
        );
        addTearDown(voice.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: ShadowingChallengeScreen(
              voice: voice,
              speechPractice: SpeechPracticeUseCases(gateway),
              learning: learning,
              evidenceAdapter: CurrentActivityEvidenceAdapter(
                learning: learning,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final listen = find.byKey(
          const ValueKey<String>('shadowing-listen-button'),
        );
        await tester.tap(listen);
        await tester.pumpAndSettle();

        expect(repository.commands, hasLength(1));
        expect(repository.finishCalls, hasLength(1));
        expect(
          find.text('ข้อความที่ได้ยิน: Practice makes perfect'),
          findsOneWidget,
        );
        expect(find.text('ไม่ได้ยินเสียงพูดที่ชัดเจน'), findsNothing);
        expect(find.text('ระบบรู้จำเสียงไม่พร้อมใช้งาน'), findsNothing);
        expect(find.text('หยุดบันทึก'), findsNothing);
        expect(tester.widget<FilledButton>(listen).onPressed, isNull);
        expect(gateway.stopCalls, 1);
      },
    );
  }

  testWidgets('retry reuses pending evidence identity', (tester) async {
    final repository = _RetryLearningRepository();
    var nextId = 0;
    final learning = LearningUseCases(
      owners: _LearningOwnerRepository(),
      repository: repository,
      generateId: () => 'shadow-${++nextId}',
      nowUtc: () => DateTime.utc(2026, 8, 14, 10, 0, nextId),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
    final voice = VoiceUseCases(
      provider: _FakeVoice(),
      disposeProvider: () async {},
    );
    addTearDown(voice.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          voice: voice,
          speechPractice: SpeechPracticeUseCases(_FakeSpeechGateway()),
          learning: learning,
          evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final listen = find.byKey(const ValueKey('shadowing-listen-button'));
    await tester.tap(listen);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(listen).onPressed, isNull);
    await tester.tap(
      find.byKey(const ValueKey<String>('current-evidence-retry')),
    );
    await tester.pumpAndSettle();

    expect(repository.commands, hasLength(2));
    final first = repository.commands.first;
    final retry = repository.commands.last;
    expect(retry.id, first.id);
    expect(retry.occurredAtUtc, first.occurredAtUtc);
    expect(retry.evidenceContext.toJson(), first.evidenceContext.toJson());
    expect(retry.evidenceContext.evidenceClass, EvidenceClass.pronunciation);
  });

  testWidgets(
    'session-close failure keeps one evidence write and a route-safe retry',
    (tester) async {
      final firstFinishRelease = Completer<void>();
      addTearDown(() {
        if (!firstFinishRelease.isCompleted) firstFinishRelease.complete();
      });
      final repository = _RetryLearningRepository(
        failAnswerOnce: false,
        failFinishOnce: true,
        firstFinishRelease: firstFinishRelease,
      );
      var nextId = 0;
      var clockTick = 0;
      final learning = LearningUseCases(
        owners: _LearningOwnerRepository(),
        repository: repository,
        generateId: () => 'shadow-close-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 8, 14, 11, 0, clockTick++),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      final voice = VoiceUseCases(
        provider: _FakeVoice(),
        disposeProvider: () async {},
      );
      final speechGateway = _FakeSpeechGateway();
      addTearDown(voice.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                key: const ValueKey<String>('open-shadowing-route'),
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ShadowingChallengeScreen(
                        voice: voice,
                        speechPractice: SpeechPracticeUseCases(speechGateway),
                        learning: learning,
                        evidenceAdapter: CurrentActivityEvidenceAdapter(
                          learning: learning,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open shadowing'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('open-shadowing-route')),
      );
      await tester.pumpAndSettle();

      final listen = find.byKey(
        const ValueKey<String>('shadowing-listen-button'),
      );
      final playReference = find.byKey(
        const ValueKey<String>('shadowing-play-reference'),
      );
      final staleListenHandler = tester.widget<FilledButton>(listen).onPressed!;
      await tester.tap(listen);
      await tester.pumpAndSettle();

      expect(repository.commands, hasLength(1));
      expect(repository.finishCalls, hasLength(1));
      expect(tester.widget<FilledButton>(listen).onPressed, isNull);
      expect(
        tester.widget<OutlinedButton>(playReference).onPressed,
        isNull,
        reason: 'reference playback must lock while session close is pending',
      );
      staleListenHandler();
      await tester.pump();
      expect(
        speechGateway.startCalls,
        1,
        reason: 'a stale listen callback must honor the persistence lock',
      );

      firstFinishRelease.complete();
      await tester.pumpAndSettle();
      final retry = find.byKey(
        const ValueKey<String>('current-evidence-retry'),
      );
      expect(
        retry,
        findsOneWidget,
        reason: 'committed evidence with a failed session close needs retry',
      );
      expect(
        tester.widget<OutlinedButton>(playReference).onPressed,
        isNull,
        reason: 'reference playback must lock while close retry is required',
      );
      expect(find.text('บันทึกคำตอบแล้วแต่ปิดเซสชันไม่สำเร็จ'), findsOneWidget);
      staleListenHandler();
      await tester.pump();
      expect(speechGateway.startCalls, 1);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byType(ShadowingChallengeScreen),
        findsOneWidget,
        reason: 'back must not discard a retry-required session close',
      );
      expect(repository.commands, hasLength(1));
      expect(repository.finishCalls, hasLength(1));

      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(repository.commands, hasLength(1));
      expect(repository.finishCalls, hasLength(2));
      expect(repository.finishCalls.last, repository.finishCalls.first);
      expect(retry, findsNothing);
      expect(tester.widget<FilledButton>(listen).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(playReference).onPressed, isNotNull);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ShadowingChallengeScreen), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('open-shadowing-route')),
        findsOneWidget,
      );
    },
  );
}

final class _LearningOwnerRepository implements LocalOwnerRepository {
  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'owner-1',
        createdAtUtc: DateTime.utc(2026, 8, 14),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RetryLearningRepository implements LearningRepository {
  _RetryLearningRepository({
    this.failAnswerOnce = true,
    this.failFinishOnce = false,
    this.firstFinishRelease,
  });

  final bool failAnswerOnce;
  final bool failFinishOnce;
  final Completer<void>? firstFinishRelease;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  final List<({String ownerId, String sessionId, DateTime endedAtUtc})>
  finishCalls = <({String ownerId, String sessionId, DateTime endedAtUtc})>[];
  var _answerFailed = false;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) async => const <QuizWord>[
    QuizWord(
      id: 'word-1',
      categoryId: 'category-1',
      spelling: 'Practice makes perfect',
      meaning: 'practice sentence',
      partOfSpeech: 'phrase',
    ),
  ];

  @override
  Future<void> startSession(LearningSessionDraft session) async {}

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (failAnswerOnce && !_answerFailed) {
      _answerFailed = true;
      throw StateError('simulated local failure');
    }
    return const AnswerRecordResult(inserted: true, srs: null);
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    finishCalls.add((
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    ));
    if (failFinishOnce && finishCalls.length == 1) {
      await firstFinishRelease?.future;
      throw StateError('simulated session-close failure');
    }
    return LearningSessionSummary(
      id: sessionId,
      ownerId: ownerId,
      activityType: 'quiz',
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

final class _FakeSpeechGateway implements SpeechRecognitionGateway {
  _FakeSpeechGateway({this.emitFinal = true, this.cancelError});

  final bool emitFinal;
  final Object? cancelError;
  int startCalls = 0;
  int cancelCalls = 0;
  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    isListening = false;
    final error = cancelError;
    if (error != null) throw error;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    startCalls += 1;
    isListening = true;
    if (!emitFinal) return;
    onEvent(
      SpeechRecognitionEvent(
        transcript: 'Practice makes perfect',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 7, 30),
        engine: 'device-stt',
        locale: locale,
      ),
    );
    isListening = false;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}

final class _ManualSpeechGateway implements SpeechRecognitionGateway {
  SpeechEventCallback? _onEvent;
  SpeechFailureCallback? _onFailure;
  void Function(String status)? _onStatus;
  String? _locale;
  int startCalls = 0;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    _onFailure = onFailure;
    _onStatus = onStatus;
  }

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    startCalls += 1;
    isListening = true;
    _locale = locale;
    _onEvent = onEvent;
  }

  void emitFinal(String transcript) {
    isListening = false;
    _emit(transcript, isFinal: true);
  }

  void emitPartial(String transcript) => _emit(transcript, isFinal: false);

  void emitFailure(SpeechFailureCode failure) => _onFailure!(failure);

  void emitStatus(String status) => _onStatus!(status);

  void _emit(String transcript, {required bool isFinal}) {
    _onEvent!(
      SpeechRecognitionEvent(
        transcript: transcript,
        isFinal: isFinal,
        recognizedAtUtc: DateTime.utc(2026, 8, 14),
        engine: 'device-stt',
        locale: _locale!,
      ),
    );
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}

final class _FinalBeforeReturnSpeechGateway
    implements SpeechRecognitionGateway {
  _FinalBeforeReturnSpeechGateway({required this.throwsAfterFinal});

  final bool throwsAfterFinal;
  SpeechFailureCallback? _onFailure;
  void Function(String status)? _onStatus;
  int stopCalls = 0;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    _onFailure = onFailure;
    _onStatus = onStatus;
  }

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    isListening = true;
    onEvent(
      SpeechRecognitionEvent(
        transcript: 'Practice makes perfect',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 8, 15),
        engine: 'device-stt',
        locale: locale,
      ),
    );
    _onStatus!('listening');
    _onFailure!(SpeechFailureCode.noMatch);
    if (throwsAfterFinal) {
      throw const SpeechPracticeException(SpeechFailureCode.engine);
    }
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    isListening = false;
  }
}

final class _FakeVoice implements VoiceProvider {
  final List<VoiceRequest> requests = [];
  final Completer<void> stopEntered = Completer<void>();
  int stopCalls = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    if (!stopEntered.isCompleted) stopEntered.complete();
  }
}

final class _PendingSpeechGateway implements SpeechRecognitionGateway {
  final Completer<void> allowStart = Completer<void>();
  int startCalls = 0;
  int cancelCalls = 0;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    startCalls += 1;
    await allowStart.future;
    isListening = true;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}

final class _TwoStartSpeechGateway implements SpeechRecognitionGateway {
  final List<Completer<void>> startCompletions = [
    Completer<void>(),
    Completer<void>(),
  ];
  int startCalls = 0;
  int cancelCalls = 0;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    final call = startCalls++;
    await startCompletions[call].future;
    isListening = true;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}
