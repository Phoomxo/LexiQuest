import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../support/srs_review_ui_harness.dart' show srsRealIoStream;

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> spokenRequests = [];
  int stopCalls = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // SharedPreferences mock removed — SrsService dependency eliminated (Phase 0 W14-15).
  });

  testWidgets(
    'source Flashcards uses only zero-due targets with saved Again feedback at 2x',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      _closeDatabaseAfterUnmount(tester, db);
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'source',
        nowUtc: () => DateTime.utc(2026, 10, 21),
      );
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(db),
        generateId: () => 'source',
        nowUtc: () => DateTime.utc(2026, 10, 21),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      await tester.runAsync(
        () => _seedVocabularyWords(db, owners, ['apple', 'banana']),
      );
      expect(await db.select(db.srsStates).get(), isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SrsFlashcardsScreen(
            sourceWordIds: const ['banana'],
            learning: learning,
            ownerChanges: _watchOwner(db, owners),
            voice: VoiceUseCases(FakeVoiceProvider()),
          ),
        ),
      );
      await _pumpUntil(tester, find.text('บัตรคำจากเนื้อหานี้'));

      await _pumpUntil(tester, find.byKey(const Key('srs-card')));
      expect(find.text('banana'), findsOneWidget);
      expect(find.text('apple'), findsNothing);
      final session = await tester.runAsync(
        () => db.select(db.learningSessions).getSingle(),
      );
      expect(session!.activityType, 'srsReview');
      await tester.ensureVisible(find.text('ดูคำแปล'));
      await tester.tap(find.text('ดูคำแปล'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ยังจำไม่ได้'));
      await tester.tap(find.text('ยังจำไม่ได้'));
      await _pumpUntil(tester, find.text('บันทึกแล้ว'));

      expect(find.text('ผลที่คุณเลือก: จำไม่ได้'), findsOneWidget);
      expect(find.text('จบการฝึก'), findsOneWidget);
      expect(
        await tester.runAsync(() => db.select(db.answerAttempts).get()),
        hasLength(1),
      );
      expect(
        await tester.runAsync(() => db.select(db.srsStates).get()),
        hasLength(1),
      );
      expect(
        await tester.runAsync(() => db.select(db.rewardTransactions).get()),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('source Flashcards returns one immutable result after finish', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    _closeDatabaseAfterUnmount(tester, db);
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'source-result',
      nowUtc: () => DateTime.utc(2026, 10, 23),
    );
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(db),
      generateId: () => 'source-result',
      nowUtc: () => DateTime.utc(2026, 10, 23),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
    await tester.runAsync(
      () => _seedVocabularyWords(db, owners, ['apple', 'banana']),
    );
    LearningSessionResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await Navigator.of(context).push(
                MaterialPageRoute<LearningSessionResult>(
                  builder: (_) => SrsFlashcardsScreen(
                    sourceWordIds: const ['apple', 'banana'],
                    learning: learning,
                    ownerChanges: _watchOwner(db, owners),
                    voice: VoiceUseCases(FakeVoiceProvider()),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _pumpUntil(tester, find.text('apple'));
    await tester.tap(find.text('apple'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยังจำไม่ได้'));
    await _pumpUntil(tester, find.text('บันทึกแล้ว'));
    await tester.tap(find.text('คำถัดไป'));
    await _pumpUntil(tester, find.text('banana'));
    await tester.tap(find.text('banana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('จำได้แล้ว'));
    await _pumpUntil(tester, find.text('บันทึกแล้ว'));

    expect(result, isNull);
    await tester.tap(find.text('จบการฝึก'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.summary.state, 'completed');
    expect(result!.summary.correctCount, 1);
    expect(result!.summary.wrongCount, 1);
    expect(result!.mistakeWordIds, const ['apple']);
    expect(() => result!.mistakeWordIds.add('other'), throwsUnsupportedError);
  });

  testWidgets('source Flashcards load failure stays in the error UI', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    _closeDatabaseAfterUnmount(tester, db);
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'source-load-failure',
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );
    final learning = LearningUseCases(
      owners: owners,
      repository: _FailOnceRepository(
        DriftLearningRepository(db),
        afterCommit: false,
        failOnListQuizWords: true,
      ),
      generateId: () => 'source-load-failure',
      nowUtc: () => DateTime.utc(2026, 10, 21),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );

    await tester.runAsync(() => _seedVocabularyWords(db, owners, ['banana']));

    await tester.pumpWidget(
      MaterialApp(
        home: SrsFlashcardsScreen(
          sourceWordIds: const ['banana'],
          learning: learning,
          ownerChanges: _watchOwner(db, owners),
          voice: VoiceUseCases(FakeVoiceProvider()),
        ),
      ),
    );
    await _pumpUntil(tester, find.text('เปิดข้อมูลทบทวนในเครื่องไม่สำเร็จ'));

    expect(await db.select(db.learningSessions).get(), isEmpty);
    expect(await db.select(db.answerAttempts).get(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets('SRS long text at 2x can reach rating and saved Next $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      _closeDatabaseAfterUnmount(tester, db);
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'large',
        nowUtc: () => DateTime.utc(2026, 10, 21),
      );
      final learning = LearningUseCases(
        owners: owners,
        repository: _FailOnceRepository(
          DriftLearningRepository(db),
          afterCommit: false,
        ),
        generateId: () => 'large',
        nowUtc: () => DateTime.utc(2026, 10, 21),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      await tester.runAsync(
        () => _seedDueWords(db, owners, [
          'longsyntheticvocabularyforlargescreentext',
          'second',
        ]),
      );
      await db.customUpdate(
        "UPDATE vocabulary_words SET meaning = 'คำแปลสังเคราะห์ที่ยาวเพื่อทดสอบการเลื่อนและการขยายตัวอักษร'",
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: size.width > size.height
                ? Brightness.dark
                : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: SrsFlashcardsScreen(
            learning: learning,
            ownerChanges: _watchOwner(db, owners),
            voice: VoiceUseCases(FakeVoiceProvider()),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        find.text('longsyntheticvocabularyforlargescreentext'),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('ดูคำแปล'));
      await tester.tap(find.text('ดูคำแปล'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('จำได้แล้ว'));
      await tester.tap(find.text('จำได้แล้ว'));
      await _pumpUntil(
        tester,
        find.text('บันทึกผลทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง'),
      );
      expect(find.text('บันทึกแล้ว'), findsNothing);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('จำได้แล้ว'));
      await tester.tap(find.text('จำได้แล้ว'));
      await _pumpUntil(tester, find.text('บันทึกแล้ว'));
      await tester.ensureVisible(find.text('คำถัดไป'));
      expect(find.text('คำถัดไป').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'SRS double rating waits for acknowledgement and Next never writes',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      _closeDatabaseAfterUnmount(tester, db);
      final acknowledgement = Completer<void>();
      addTearDown(() {
        if (!acknowledgement.isCompleted) acknowledgement.complete();
      });
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'pending',
        nowUtc: () => DateTime.utc(2026, 10, 21),
      );
      final repository = _FailOnceRepository(
        DriftLearningRepository(db),
        afterCommit: false,
        acknowledgement: acknowledgement.future,
      );
      final learning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'pending',
        nowUtc: () => DateTime.utc(2026, 10, 21),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      await tester.runAsync(
        () => _seedDueWords(db, owners, ['apple', 'banana']),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SrsFlashcardsScreen(
            learning: learning,
            ownerChanges: _watchOwner(db, owners),
            voice: VoiceUseCases(FakeVoiceProvider()),
          ),
        ),
      );
      await _pumpUntil(tester, find.text('apple'));
      await tester.tap(find.text('apple'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('จำได้แล้ว'));
      await tester.tap(find.text('จำได้แล้ว'));
      await tester.pump();
      expect(repository.commands, hasLength(1));
      expect(find.text('บันทึกแล้ว'), findsNothing);
      expect(find.text('คำถัดไป'), findsNothing);
      acknowledgement.complete();
      await _pumpUntil(tester, find.text('บันทึกแล้ว'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('1/2'), findsOneWidget);
      final before = await tester.runAsync(
        () => db.select(db.outboxOperations).get(),
      );
      await tester.tap(find.text('คำถัดไป'));
      await _pumpUntil(tester, find.text('2/2'));
      expect(repository.commands, hasLength(1));
      expect(
        (await tester.runAsync(
          () => db.select(db.outboxOperations).get(),
        ))!.map((r) => r.toJson()),
        before!.map((r) => r.toJson()),
      );
      final credits = await tester.runAsync(
        () => db.select(db.rewardTransactions).get(),
      );
      expect(credits, hasLength(1));
      expect(credits!.single.transactionType, 'creditQuizCorrectV1');
      expect(credits.single.amount, 1);
    },
  );

  for (final (afterCommit, rating) in [
    (false, true),
    (true, true),
    (false, false),
    (true, false),
  ]) {
    testWidgets(
      'SRS retries $rating evidence after ${afterCommit ? 'lost ack' : 'failed write'}',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        _closeDatabaseAfterUnmount(tester, db);
        var sequence = 0;
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'srs-test',
          nowUtc: () => DateTime.utc(2026, 10, 20),
        );
        final delegate = DriftLearningRepository(db);
        final failing = _FailOnceRepository(delegate, afterCommit: afterCommit);
        final learning = LearningUseCases(
          owners: owners,
          repository: failing,
          generateId: () => '${sequence++}',
          nowUtc: () => DateTime.utc(2026, 10, 20, 12),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        );
        await tester.runAsync(
          () => _seedDueWords(db, owners, ['apple', 'banana']),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SrsFlashcardsScreen(
              voice: VoiceUseCases(FakeVoiceProvider()),
              learning: learning,
              ownerChanges: _watchOwner(db, owners),
            ),
          ),
        );
        await _pumpUntil(tester, find.text('apple'));
        await tester.tap(find.text('apple'));
        await tester.pumpAndSettle();
        final selectedText = rating ? 'จำได้แล้ว' : 'ยังจำไม่ได้';
        await tester.tap(find.text(selectedText));
        await _pumpUntil(
          tester,
          find.text('บันทึกผลทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง'),
        );
        final first = failing.commands.single;
        final storedAfterFailure = await tester.runAsync(
          () => (db.select(
            db.srsStates,
          )..where((r) => r.wordId.equals('apple'))).get(),
        );
        final outboxAfterFailure = await tester.runAsync(
          () => db.select(db.outboxOperations).get(),
        );
        final wrongRating = tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text(rating ? 'ยังจำไม่ได้' : 'จำได้แล้ว'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await _revealSrsAction(tester, find.text(selectedText));
        await tester.tap(find.text(selectedText));
        await _pumpUntil(tester, find.text('บันทึกแล้ว'));
        expect(find.text('1/2'), findsOneWidget);
        expect(
          find.text('ผลที่คุณเลือก: ${rating ? 'จำได้แล้ว' : 'จำไม่ได้'}'),
          findsOneWidget,
        );
        await tester.tap(find.text('คำถัดไป'));
        await _pumpUntil(tester, find.text('2/2'));
        final second = failing.commands.last;
        expect(identical(failing.intents[0], failing.intents[1]), isTrue);
        expect(second.id, first.id);
        expect(second.occurredAtUtc, first.occurredAtUtc);
        expect(second.responseTimeMs, first.responseTimeMs);
        expect(second.isCorrect, first.isCorrect);
        expect(second.wordId, first.wordId);
        expect(second.sessionId, first.sessionId);
        expect(second.promptMode, first.promptMode);
        expect(second.attemptNumber, first.attemptNumber);
        expect(second.providerProvenance, first.providerProvenance);
        expect(second.evidenceContext.toJson(), first.evidenceContext.toJson());
        expect(first.evidenceContext.evidenceClass.name, 'independentRecall');
        expect(first.evidenceContext.contentRevision, 'local-vocabulary-v1:1');
        expect(
          wrongRating.onPressed,
          isNull,
          reason: 'an uncertain write must keep its original rating',
        );
        final attempts = await tester.runAsync(
          () => db.select(db.answerAttempts).get(),
        );
        expect(attempts, hasLength(1));
        final srs = await tester.runAsync(
          () => (db.select(
            db.srsStates,
          )..where((r) => r.wordId.equals('apple'))).get(),
        );
        expect(srs, hasLength(1));
        expect(srs!.single.repetitions, rating ? 1 : 0);
        if (afterCommit) {
          expect(srs.single.toJson(), storedAfterFailure!.single.toJson());
        }
        expect(
          await tester.runAsync(() => db.select(db.pointsLedgerEntries).get()),
          hasLength(rating ? 1 : 0),
        );
        expect(
          await tester.runAsync(() => db.select(db.rewardTransactions).get()),
          hasLength(rating ? 1 : 0),
        );
        if (afterCommit) {
          final outbox = await tester.runAsync(
            () => db.select(db.outboxOperations).get(),
          );
          expect(
            outbox!.map((r) => r.toJson()),
            outboxAfterFailure!.map((r) => r.toJson()),
          );
        }
        await tester.runAsync(
          () => expectLater(
            delegate.recordAnswer(
              RecordAnswerCommand(
                id: first.id,
                ownerId: first.ownerId,
                sessionId: first.sessionId,
                wordId: first.wordId,
                promptMode: first.promptMode,
                isCorrect: !first.isCorrect,
                responseTimeMs: first.responseTimeMs,
                attemptNumber: first.attemptNumber,
                occurredAtUtc: first.occurredAtUtc,
              ),
            ),
            throwsStateError,
          ),
        );
        final original = failing.intents.first;
        await tester.runAsync(
          () => expectLater(
            delegate.commitSrsRating(
              SrsReviewAnswerIntent(
                review: original.review,
                cardIndex: original.cardIndex,
                command: RecordAnswerCommand(
                  id: first.id,
                  ownerId: first.ownerId,
                  sessionId: first.sessionId,
                  wordId: first.wordId,
                  promptMode: first.promptMode,
                  isCorrect: !first.isCorrect,
                  responseTimeMs: first.responseTimeMs,
                  attemptNumber: first.attemptNumber,
                  occurredAtUtc: first.occurredAtUtc,
                  providerProvenance: first.providerProvenance,
                  evidenceContext: first.evidenceContext,
                ),
              ),
              stillCurrent: () => true,
            ),
            throwsStateError,
          ),
        );
        await tester.tap(find.text('banana'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('จำได้แล้ว'));
        await _pumpUntil(tester, find.text('บันทึกแล้ว'));
        expect(find.text('2/2'), findsOneWidget);
        await tester.tap(find.text('จบการทบทวน'));
        await _pumpUntil(tester, find.text('ทบทวนคำศัพท์ที่ถึงกำหนดครบแล้ว'));
        expect(failing.commands.last.id, isNot(first.id));
        expect(
          await tester.runAsync(() => db.select(db.answerAttempts).get()),
          hasLength(2),
        );
        expect(
          await tester.runAsync(() => db.select(db.pointsLedgerEntries).get()),
          hasLength(rating ? 2 : 1),
        );
        final session = await tester.runAsync(
          () => db.select(db.learningSessions).getSingle(),
        );
        expect(session!.state, 'completed');
      },
    );
  }

  for (final afterCommit in [false, true]) {
    testWidgets(
      'SRS retains last attempt when finish ${afterCommit ? 'ack is lost' : 'fails'}',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        _closeDatabaseAfterUnmount(tester, db);
        var sequence = 0;
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'srs-finish',
          nowUtc: () => DateTime.utc(2026, 10, 20),
        );
        final failing = _FailOnceRepository(
          DriftLearningRepository(db),
          afterCommit: afterCommit,
          failOnFinish: true,
        );
        final learning = LearningUseCases(
          owners: owners,
          repository: failing,
          generateId: () => '${sequence++}',
          nowUtc: () => DateTime.utc(2026, 10, 20, 12),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        );
        await tester.runAsync(() => _seedDueWords(db, owners, ['apple']));
        await tester.pumpWidget(
          MaterialApp(
            home: SrsFlashcardsScreen(
              voice: VoiceUseCases(FakeVoiceProvider()),
              learning: learning,
              ownerChanges: _watchOwner(db, owners),
            ),
          ),
        );
        await _pumpUntil(tester, find.text('apple'));
        await tester.tap(find.text('apple'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('จำได้แล้ว'));
        await _pumpUntil(tester, find.text('บันทึกแล้ว'));
        await tester.tap(find.text('จบการทบทวน'));
        await _pumpUntil(
          tester,
          find.text('ปิดการทบทวนไม่สำเร็จ กรุณาลองอีกครั้ง'),
        );
        final before = await tester.runAsync(
          () => db.select(db.srsStates).getSingle(),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await _revealSrsAction(tester, find.byKey(const Key('srs-next')));
        await tester.tap(find.text('จบการทบทวน'));
        await _pumpUntil(tester, find.text('ทบทวนคำศัพท์ที่ถึงกำหนดครบแล้ว'));
        expect(failing.finishIntents, hasLength(2));
        expect(
          identical(failing.finishIntents[0], failing.finishIntents[1]),
          isTrue,
        );
        expect(
          failing.finishIntents[1].endedAtUtc,
          failing.finishIntents[0].endedAtUtc,
        );
        expect(failing.commands, hasLength(1));
        expect(failing.commands.last.id, failing.commands.first.id);
        expect(
          await tester.runAsync(() => db.select(db.answerAttempts).get()),
          hasLength(1),
        );
        expect(
          await tester.runAsync(() => db.select(db.pointsLedgerEntries).get()),
          hasLength(1),
        );
        final after = await tester.runAsync(
          () => db.select(db.srsStates).getSingle(),
        );
        expect(after!.toJson(), before!.toJson());
        final session = await tester.runAsync(
          () => db.select(db.learningSessions).getSingle(),
        );
        expect(session!.state, 'completed');
      },
    );
  }

  testWidgets('SrsFlashcardsScreen renders front side and auto-plays audio', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();
    final wordList = [
      {
        'word': 'apple',
        'translation': 'แอปเปิ้ล',
        'example': 'An apple a day.',
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: SrsFlashcardsScreen(
          wordList: wordList,
          voice: VoiceUseCases(fakeVoice),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsOneWidget);
    expect(fakeVoice.spokenRequests.length, 1);
  });

  testWidgets(
    'Tapping card flips to back side displaying translation and buttons',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();
      final wordList = [
        {
          'word': 'banana',
          'translation': 'กล้วย',
          'example': 'Monkeys eat bananas.',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SrsFlashcardsScreen(
            wordList: wordList,
            voice: VoiceUseCases(fakeVoice),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap card to flip
      await tester.tap(find.text('banana'));
      await tester.pumpAndSettle();

      expect(find.text('จำได้แล้ว'), findsOneWidget);
      expect(find.text('ยังจำไม่ได้'), findsOneWidget);

      // Tap Good — compatibility deck: no-op (SrsService removed Phase 0 W14-15)
      await _revealSrsAction(tester, find.byKey(const Key('srs-got')));
      await tester.tap(find.text('จำได้แล้ว'));
      await tester.pumpAndSettle();
      expect(find.text('ชุดตัวอย่างนี้ไม่บันทึกผล'), findsOneWidget);
      expect(find.text('บันทึกแล้ว'), findsNothing);
    },
  );
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _seedDueWords(
  AppDatabase db,
  DriftLocalOwnerRepository owners,
  List<String> words,
) async {
  _ownerIoZones[db] = Zone.current;
  final owner = await owners.getOrCreateActiveOwner();
  await db
      .into(db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category',
          ownerId: owner.id,
          name: 'Synthetic',
          normalizedName: 'synthetic',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  for (final id in words) {
    await db
        .into(db.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: id,
            ownerId: owner.id,
            categoryId: 'category',
            spelling: id,
            normalizedSpelling: id,
            meaning: 'meaning-$id',
            normalizedMeaning: 'meaning-$id',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await db
        .into(db.srsStates)
        .insert(
          SrsStatesCompanion.insert(
            id: 'srs-$id',
            ownerId: owner.id,
            wordId: id,
            dueAtUtcMs: id == 'apple' ? 1 : 2,
            algorithmVersion: 1,
          ),
        );
  }
}

Future<void> _seedVocabularyWords(
  AppDatabase db,
  DriftLocalOwnerRepository owners,
  List<String> words,
) async {
  _ownerIoZones[db] = Zone.current;
  final owner = await owners.getOrCreateActiveOwner();
  await db
      .into(db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'source-category',
          ownerId: owner.id,
          name: 'Source',
          normalizedName: 'source',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  for (final id in words) {
    await db
        .into(db.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: id,
            ownerId: owner.id,
            categoryId: 'source-category',
            spelling: id,
            normalizedSpelling: id,
            meaning: 'meaning-$id',
            normalizedMeaning: 'meaning-$id',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  }
}

class _FailOnceRepository implements LearningRepository, SrsReviewRepository {
  _FailOnceRepository(
    this.delegate, {
    required this.afterCommit,
    this.failOnFinish = false,
    this.failOnListQuizWords = false,
    this.acknowledgement,
  });
  final LearningRepository delegate;
  final bool afterCommit;
  final bool failOnFinish;
  final bool failOnListQuizWords;
  final Future<void>? acknowledgement;
  bool finishFailed = false;
  final commands = <RecordAnswerCommand>[];

  final intents = <SrsReviewAnswerIntent>[];
  final finishIntents = <SrsReviewFinishIntent>[];
  SrsReviewRepository get srs => delegate as SrsReviewRepository;

  @override
  Future<SrsReviewSession?> prepareSrsReview({
    required LearningSessionDraft session,
    required SrsReviewSelection selection,
    Iterable<String>? sourceWordIds,
    int limit = 20,
    required bool Function() stillCurrent,
  }) {
    if (failOnListQuizWords) {
      return Future.error(StateError('synthetic source load failure'));
    }
    return srs.prepareSrsReview(
      session: session,
      selection: selection,
      sourceWordIds: sourceWordIds,
      limit: limit,
      stillCurrent: stillCurrent,
    );
  }

  @override
  Future<SrsReviewStartResult> startSrsReview(
    SrsReviewSession review, {
    required bool Function() stillCurrent,
  }) => srs.startSrsReview(review, stillCurrent: stillCurrent);

  @override
  Future<AnswerRecordResult> commitSrsRating(
    SrsReviewAnswerIntent intent, {
    required bool Function() stillCurrent,
  }) async {
    intents.add(intent);
    commands.add(intent.command);
    if (commands.length == 1 && !failOnFinish && acknowledgement == null) {
      if (afterCommit) {
        await srs.commitSrsRating(intent, stillCurrent: stillCurrent);
      }
      throw StateError('synthetic acknowledgement/storage failure');
    }
    final result = await srs.commitSrsRating(
      intent,
      stillCurrent: stillCurrent,
    );
    await acknowledgement;
    return result;
  }

  @override
  Future<SrsReviewFinishResult> finishSrsReview(
    SrsReviewFinishIntent intent, {
    required bool Function() stillCurrent,
  }) async {
    finishIntents.add(intent);
    if (failOnFinish && !finishFailed) {
      finishFailed = true;
      if (afterCommit) {
        await srs.finishSrsReview(intent, stillCurrent: stillCurrent);
      }
      throw StateError('synthetic finish failure');
    }
    return srs.finishSrsReview(intent, stillCurrent: stillCurrent);
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) =>
      delegate.recordAnswer(command);

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    String? afterWordId,
    required int limit,
  }) {
    if (failOnListQuizWords) {
      return Future.error(StateError('synthetic source load failure'));
    }
    return delegate.listQuizWords(
      ownerId: ownerId,
      categoryId: categoryId,
      wordIds: wordIds,
      afterWordId: afterWordId,
      limit: limit,
    );
  }

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);
  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) => delegate.listDueWords(ownerId: ownerId, nowUtc: nowUtc, limit: limit);
  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) => delegate.finishSession(
    ownerId: ownerId,
    sessionId: sessionId,
    endedAtUtc: endedAtUtc,
  );

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) => delegate.readReadingProgress(
    ownerId: ownerId,
    documentId: documentId,
    documentRevision: documentRevision,
  );
  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) => delegate.saveReadingProgress(command);
}

final _ownerIoZones = Expando<Zone>();
final _ownerIoStreams = Expando<Stream<String?>>();

Stream<String?> _watchOwner(
  AppDatabase database,
  DriftLocalOwnerRepository owners,
) => _ownerIoStreams[database] ??= srsRealIoStream(
  ProgressUseCases(
    owners: owners,
    queries: DriftProgressQueries(database),
    nowUtc: () => DateTime.utc(2026, 10, 30),
  ).watchActiveOwnerId(),
  ioZone: _ownerIoZones[database]!,
);

void _closeDatabaseAfterUnmount(WidgetTester tester, AppDatabase database) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(database.close);
  });
}

Future<void> _revealSrsAction(WidgetTester tester, Finder target) async {
  await tester.pump();
  final outer = find
      .descendant(
        of: find.byType(SrsFlashcardsScreen),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: outer,
    maxScrolls: 40,
  );
  await tester.ensureVisible(target);
  await tester.pump();
  expect(target.hitTestable(), findsOneWidget);
}
