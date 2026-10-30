import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/gemini/application/gemini_tutor_use_cases.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as domain;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/vocabulary/application/source_practice.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/screens/ai_tutor_screen.dart';
import 'package:vocab_learning_app/screens/source_practice_screen.dart';
import 'package:vocab_learning_app/screens/speak_to_text_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

final class _FakeVoiceProvider implements VoiceProvider {
  final requests = <VoiceRequest>[];
  int stopCalls = 0;
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async => stopCalls += 1;
}

void main() {
  setUpAll(() async {
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
  });
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late VocabularyUseCases vocabulary;
  late LearningUseCases learning;
  late String ownerId;
  late GeminiTutorUseCases tutor;
  late _SourceTutorGateway tutorGateway;
  late _FakeVoiceProvider voice;
  GeminiScope? tutorScope;
  var id = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner-a',
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );
    final owner = await owners.getOrCreateActiveOwner();
    ownerId = owner.id;
    tutorScope = GeminiScope(
      ownerId: ownerId,
      firebaseUid: null,
      isAnonymous: true,
    );
    tutorGateway = _SourceTutorGateway();
    voice = _FakeVoiceProvider();
    tutor = GeminiTutorUseCases(
      store: _SourceTutorStore(),
      gateway: tutorGateway,
      nowUtc: () => DateTime.utc(2026),
      readScope: () => tutorScope,
    );
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: ownerId,
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-station',
            ownerId: ownerId,
            categoryId: 'category-1',
            spelling: 'station',
            normalizedSpelling: 'station',
            meaning: 'สถานี',
            normalizedMeaning: 'สถานี',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'vocab-${++id}',
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'learning-${++id}',
      nowUtc: () => DateTime.utc(2026, 10, 21, 1),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
  });

  tearDown(() async {
    await tutor.dispose();
    await database.close();
  });

  SourcePracticeFilePicker picker({String? text}) => () async {
    final content =
        text ?? 'The station is quiet and ready for every learner today.';
    return SourcePracticeFile(
      name: 'lesson.txt',
      mimeType: 'text/plain',
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
  };

  Widget screen({
    String? text,
    double textScale = 1,
    bool withTutor = true,
    Size size = const Size(360, 800),
    double keyboardInset = 0,
    bool reducedMotion = false,
    SpeechPracticeUseCases? speech,
  }) => AppDependenciesScope(
    dependencies: AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _UnusedGuestSession(),
      geminiTutor: withTutor ? tutor : null,
      speechPractice: speech,
    ),
    child: MaterialApp(
      theme: ThemeData(fontFamily: 'NotoSansThai'),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'NotoSansThai',
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
          disableAnimations: reducedMotion,
        ),
        child: SourcePracticeScreen(
          categoryId: 'category-1',
          categoryName: 'Travel',
          vocabulary: vocabulary,
          learning: learning,
          filePicker: picker(text: text),
          voice: VoiceUseCases(voice),
        ),
      ),
    ),
  );

  testWidgets(
    'Ask Lexi requires confirmation and opens only an unsent word draft',
    (tester) async {
      await tester.pumpWidget(
        screen(
          text: 'Privatepassage station is ready for every learner today.',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('choose-source-file')));
      await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
      expect(find.byKey(const ValueKey('start-source-ask-lexi')), findsNothing);
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('confirm-source')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-source')));
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('start-source-flashcards')),
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -250));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('start-source-ask-lexi')),
        findsOneWidget,
      );
      expect(find.text('ถาม Lexi เรื่อง station'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
      await _pumpUntilFound(tester, find.byType(AiTutorScreen));
      await tester.pumpAndSettle();
      final draft = tester
          .widget<TextField>(find.byKey(const ValueKey('ai-tutor-input')))
          .controller!
          .text;
      expect(draft, 'Help me understand the English word "station".');
      for (final privateText in [
        'Privatepassage',
        'lesson.txt',
        'Travel',
        'สถานี',
        'local-source:',
      ]) {
        expect(draft, isNot(contains(privateText)));
      }
      expect(
        find.text('ไฟล์และข้อความต้นฉบับไม่ได้แนบ ตรวจแก้คำถามก่อนกดส่ง'),
        findsOneWidget,
      );
      expect(find.text('คำที่กำลังฝึก: station'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ai-tutor-data-disclosure')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ai-tutor-practice-target')),
        findsOneWidget,
      );
      expect(find.text('ลองส่งแล้ว 0/8 ครั้งในหน้านี้'), findsOneWidget);
      expect(tutorGateway.messages, isEmpty);
      expect(voice.requests, isEmpty);
      expect((await tutor.loadSettings()).providerConsent, isFalse);
      await _expectNoPracticeWrites(database);
      expect(await database.select(database.rewardTransactions).get(), isEmpty);
      expect(await database.select(database.researchConsents).get(), isEmpty);
      expect(await database.select(database.eventsV2).get(), isEmpty);
    },
  );

  _DelayedOwnerRepository useDelayedOwners() {
    final delayed = _DelayedOwnerRepository(owners);
    vocabulary = VocabularyUseCases(
      owners: delayed,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'vocab-${++id}',
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );
    learning = LearningUseCases(
      owners: delayed,
      repository: DriftLearningRepository(database),
      generateId: () => 'learning-${++id}',
      nowUtc: () => DateTime.utc(2026, 10, 21, 1),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
    return delayed;
  }

  Future<void> prepareAsk(
    WidgetTester tester, {
    String? text,
    bool withTutor = true,
    Size size = const Size(360, 800),
    double textScale = 1,
    double keyboardInset = 0,
    SpeechPracticeUseCases? speech,
  }) async {
    await tester.pumpWidget(
      screen(
        text: text,
        withTutor: withTutor,
        size: size,
        textScale: textScale,
        keyboardInset: keyboardInset,
        speech: speech,
      ),
    );
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('choose-source-file')),
    );
    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpAsyncWork(tester);
    await _scrollUntilFound(tester, find.byKey(const ValueKey('source-text')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('confirm-source')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-source')));
    await _pumpAsyncWork(tester);
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-ask-lexi')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Ask Lexi target opens one exact local source-practice session', (
    tester,
  ) async {
    await prepareAsk(tester);
    await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
    await _pumpUntilFound(tester, find.byType(AiTutorScreen));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai-tutor-data-disclosure')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('รหัสบัญชี รหัสคำศัพท์ และประวัติคำตอบไม่ได้ถูกส่ง'),
      findsOneWidget,
    );
    await tester.tap(find.text('ปิด'));
    await tester.pumpAndSettle();

    expect(tutorGateway.messages, isEmpty);
    await tester.tap(find.byKey(const ValueKey('ai-tutor-practice-target')));
    await _pumpUntilFound(tester, find.byType(QuizScreen));
    await tester.pumpAndSettle();

    expect(find.text('station'), findsOneWidget);
    final sessions = await database.select(database.learningSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.activityType, 'sourcePractice');
    expect(tutorGateway.messages, isEmpty);
  });

  testWidgets('rapid Ask Lexi target taps open one local Quiz session', (
    tester,
  ) async {
    await prepareAsk(tester);
    await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
    await _pumpUntilFound(tester, find.byType(AiTutorScreen));
    await tester.pumpAndSettle();
    final action = tester.widget<FilledButton>(
      find.byKey(const ValueKey('ai-tutor-practice-target')),
    );
    action.onPressed!();
    action.onPressed!();
    await _pumpUntilFound(tester, find.byType(QuizScreen));
    await tester.pumpAndSettle();

    expect(find.byType(QuizScreen, skipOffstage: false), findsOneWidget);
    expect(
      await database.select(database.learningSessions).get(),
      hasLength(1),
    );
  });

  testWidgets('Ask Lexi target stays local after provider failure', (
    tester,
  ) async {
    await tester.runAsync(
      () => tutor.updateConsents(
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
    tutorGateway.failure = const GeminiException(GeminiFailureCode.offline);
    await prepareAsk(tester);
    await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
    await _pumpUntilFound(tester, find.byType(AiTutorScreen));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ออฟไลน์'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-tutor-practice-target')));
    await _pumpUntilFound(tester, find.byType(QuizScreen));
    await tester.pumpAndSettle();
    expect(
      await database.select(database.learningSessions).get(),
      hasLength(1),
    );
    expect(tutorGateway.messages, hasLength(1));
  });

  testWidgets('Ask Lexi target cancels active AI and audio before Quiz', (
    tester,
  ) async {
    await tester.runAsync(
      () => tutor.updateConsents(
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
    final replyGate = Completer<void>();
    final speech = _SourceSpeechGateway();
    tutorGateway.replyGate = replyGate;
    await prepareAsk(tester, speech: SpeechPracticeUseCases(speech));
    await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
    await _pumpUntilFound(tester, find.byType(AiTutorScreen));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pump();
    expect(tutorGateway.cancellation?.isCancelled, isFalse);

    await tester.ensureVisible(
      find.byKey(const ValueKey('ai-tutor-practice-target')),
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-practice-target')));
    await _pumpUntilFound(tester, find.byType(QuizScreen));
    expect(tutorGateway.cancellation?.isCancelled, isTrue);
    expect(speech.cancelCalls, greaterThanOrEqualTo(2));
    expect(voice.stopCalls, greaterThanOrEqualTo(1));

    replyGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Synthetic word-only reply'), findsNothing);
  });

  testWidgets('Ask Lexi target blocks answer-history sharing to provider', (
    tester,
  ) async {
    await tester.runAsync(
      () => tutor.updateConsents(
        providerConsent: true,
        shareLearningSummary: true,
      ),
    );
    await prepareAsk(tester);
    await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
    await _pumpUntilFound(tester, find.byType(AiTutorScreen));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();

    expect(tutorGateway.messages, isEmpty);
    expect(find.textContaining('ปิดการแชร์สรุปผลเรียน'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-tutor-practice-target')),
      findsOneWidget,
    );
    await _expectNoPracticeWrites(database);
  });

  testWidgets('Ask Lexi invalidation clears target before local navigation', (
    tester,
  ) async {
    await prepareAsk(tester);
    await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
    await _pumpUntilFound(tester, find.byType(AiTutorScreen));
    await tester.pumpAndSettle();
    tutor.invalidateScope();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ai-tutor-practice-target')),
      findsNothing,
    );
    await _expectNoPracticeWrites(database);
  });

  for (final change in ['deleted', 'renamed']) {
    testWidgets('Ask Lexi rejects $change target before local navigation', (
      tester,
    ) async {
      await prepareAsk(tester);
      await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
      await _pumpUntilFound(tester, find.byType(AiTutorScreen));
      await tester.pumpAndSettle();
      await (database.update(
        database.vocabularyWords,
      )..where((row) => row.id.equals('word-station'))).write(
        change == 'deleted'
            ? const VocabularyWordsCompanion(isDeleted: Value(true))
            : const VocabularyWordsCompanion(
                spelling: Value('terminal'),
                normalizedSpelling: Value('terminal'),
              ),
      );

      await tester.tap(find.byKey(const ValueKey('ai-tutor-practice-target')));
      await _pumpAsyncWork(tester);
      expect(find.byType(QuizScreen), findsNothing);
      expect(
        find.byKey(const ValueKey('ai-tutor-practice-target')),
        findsNothing,
      );
      expect(find.textContaining('คำศัพท์เปลี่ยนแล้ว'), findsOneWidget);
      await _expectNoPracticeWrites(database);
    });
  }

  testWidgets('Voice launches only the confirmed first known word session', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    expect(find.byKey(const ValueKey('start-source-voice')), findsNothing);
    await _expectNoPracticeWrites(database);
    await prepareAsk(tester, text: 'Privatepassage station is ready today.');
    await _expectNoPracticeWrites(database);
    final action = find.byKey(const ValueKey('start-source-voice'));
    expect(action, findsOneWidget);
    await _scrollUntilFound(tester, action);
    expect(find.text('ฝึกพูดคำว่า station'), findsOneWidget);
    await tester.tap(action);
    await _pumpUntilFound(tester, find.byType(SpeakToTextScreen));
    await _pumpAsyncWork(tester);
    final page = tester.widget<SpeakToTextScreen>(
      find.byType(SpeakToTextScreen),
    );
    expect(page.correctWord, 'station');
    expect(page.wordId, 'word-station');
    final sessions = await database.select(database.learningSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.activityType, 'pronunciation');
    expect(page.sessionId, sessions.single.id);
    expect(await database.select(database.answerAttempts).get(), isEmpty);
    expect(await database.select(database.pointsLedgerEntries).get(), isEmpty);
    expect(await database.select(database.rewardTransactions).get(), isEmpty);
    expect(await database.select(database.outboxOperations).get(), isEmpty);
    expect(tutorGateway.messages, isEmpty);
    expect(voice.requests.map((request) => request.text), ['station']);
  });

  Future<void> prepareVoice(
    WidgetTester tester, {
    bool withTutor = true,
    SpeechPracticeUseCases? speech,
  }) async {
    await prepareAsk(tester, withTutor: withTutor, speech: speech);
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-voice')),
    );
    await tester.pumpAndSettle();
  }

  for (final correct in [true, false]) {
    testWidgets(
      'Voice without Gemini opens recorded Result and original Source correct=$correct',
      (tester) async {
        Map<String, Object?>? acknowledgedSnapshot;
        final repository = _SourceVoiceStartRepository(learning.repository)
          ..afterFinish = () async {
            acknowledgedSnapshot = await _voiceSnapshot(database);
          };
        learning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'learning-${++id}',
          nowUtc: () => DateTime.utc(2026, 10, 21, 1),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        );
        final gateway = _SourceSpeechGateway();
        await prepareVoice(
          tester,
          withTutor: false,
          speech: SpeechPracticeUseCases(gateway),
        );
        await tester.tap(find.byKey(const ValueKey('start-source-voice')));
        await _pumpUntilFound(tester, find.byType(SpeakToTextScreen));
        await _pumpAsyncWork(tester);
        expect(gateway.startCalls, 0);
        final mic = find.byKey(const ValueKey('speech-listen-button'));
        await _scrollUntilFound(tester, mic);
        await tester.tap(mic);
        await _pumpUntilCondition(tester, () => gateway.startCalls == 1);
        gateway.onEvent!(
          SpeechRecognitionEvent(
            transcript: correct ? 'station' : 'wrong',
            isFinal: true,
            recognizedAtUtc: DateTime.utc(2026, 10, 23),
            engine: 'synthetic-source-stt',
            locale: 'en-US',
          ),
        );
        await _pumpUntilFound(
          tester,
          find.byKey(const ValueKey('source-voice-saved')),
        );
        final finish = find.byKey(const ValueKey('source-voice-finish'));
        await _scrollUntilFound(tester, finish);
        await tester.tap(finish);
        await _pumpUntilCondition(
          tester,
          () => find.byType(SpeakToTextScreen).evaluate().isEmpty,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ScoreScreen), findsOneWidget);
        final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
        expect(score.correctAnswers, correct ? 1 : 0);
        expect(score.wrongAnswers, correct ? 0 : 1);
        expect(score.score, correct ? 100 : 0);
        expect(score.onPracticeMistakes, correct ? isNull : isNotNull);
        expect(
          score.mistakes.map((word) => word.id),
          correct ? isEmpty : ['word-station'],
        );
        if (!correct) {
          expect(score.mistakes.single.meaning, 'สถานี');
          expect(score.mistakes.single.categoryId, 'category-1');
        }
        expect(
          (await database.select(database.learningSessions).getSingle()).state,
          'completed',
        );
        final answer = await database
            .select(database.answerAttempts)
            .getSingle();
        expect(answer.wordId, 'word-station');
        expect(answer.promptMode, 'pronunciationTranscript');
        expect(answer.isCorrect, correct);
        expect(tutorGateway.messages, isEmpty);
        final snapshot = await tester.runAsync(() => _voiceSnapshot(database));
        expect(acknowledgedSnapshot, isNotNull);
        expect(snapshot, acknowledgedSnapshot);
        expect(repository.finishCalls, 1);
        await tester.tap(find.text('กลับไปเลือกกิจกรรม'));
        await tester.pumpAndSettle();
        expect(find.byType(SourcePracticeScreen), findsOneWidget);
        expect(await tester.runAsync(() => _voiceSnapshot(database)), snapshot);
        expect(repository.finishCalls, 1);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('start-source-voice')),
              )
              .onPressed,
          isNotNull,
        );
      },
    );
  }

  Future<void> changeVoiceTarget(String change) async {
    if (change == 'owner') {
      await _switchOwner(database, ownerId);
    } else if (change == 'deleted-category') {
      await (database.update(database.vocabularyCategories)
            ..where((r) => r.id.equals('category-1')))
          .write(const VocabularyCategoriesCompanion(isDeleted: Value(true)));
    } else if (change == 'category') {
      await database
          .into(database.vocabularyCategories)
          .insert(
            VocabularyCategoriesCompanion.insert(
              id: 'other-category',
              ownerId: ownerId,
              name: 'Other',
              normalizedName: 'other',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      await (database.update(
        database.vocabularyWords,
      )..where((r) => r.id.equals('word-station'))).write(
        const VocabularyWordsCompanion(categoryId: Value('other-category')),
      );
    } else {
      await (database.update(
        database.vocabularyWords,
      )..where((r) => r.id.equals('word-station'))).write(
        change == 'deleted'
            ? const VocabularyWordsCompanion(isDeleted: Value(true))
            : const VocabularyWordsCompanion(
                spelling: Value('ready'),
                normalizedSpelling: Value('ready'),
              ),
      );
    }
  }

  Future<void> openVoiceResult(
    WidgetTester tester, {
    bool correct = false,
  }) async {
    final gateway = _SourceSpeechGateway();
    await prepareVoice(
      tester,
      withTutor: false,
      speech: SpeechPracticeUseCases(gateway),
    );
    await tester.tap(find.byKey(const ValueKey('start-source-voice')));
    await _pumpUntilFound(tester, find.byType(SpeakToTextScreen));
    await tester.pumpAndSettle();
    final mic = find.byKey(const ValueKey('speech-listen-button'));
    await _scrollUntilFound(tester, mic);
    await tester.tap(mic);
    await _pumpUntilCondition(tester, () => gateway.startCalls == 1);
    gateway.onEvent!(
      SpeechRecognitionEvent(
        transcript: correct ? 'station' : 'wrong',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 10, 23),
        engine: 'synthetic',
        locale: 'en-US',
      ),
    );
    await _pumpAsyncWork(tester);
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('source-voice-saved')),
    );
    final finish = find.byKey(const ValueKey('source-voice-finish'));
    await _scrollUntilFound(tester, finish);
    await tester.tap(finish);
    await _pumpUntilFound(tester, find.byType(ScoreScreen));
    await tester.pumpAndSettle();
  }

  for (final completeRepair in [false, true]) {
    testWidgets(
      'Voice Result repair is explicit one-word Quiz and returns to same Source complete=$completeRepair',
      (tester) async {
        await database
            .into(database.vocabularyWords)
            .insert(
              VocabularyWordsCompanion.insert(
                id: 'word-other',
                ownerId: ownerId,
                categoryId: 'category-1',
                spelling: 'ready',
                normalizedSpelling: 'ready',
                meaning: 'พร้อม',
                normalizedMeaning: 'พร้อม',
                partOfSpeech: 'adjective',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        await openVoiceResult(tester);
        final sourceState = tester.state(
          find.byType(SourcePracticeScreen, skipOffstage: false),
        );
        final before = await tester.runAsync(() => _voiceSnapshot(database));
        expect(
          (await database.select(database.learningSessions).get()),
          hasLength(1),
        );
        final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
        final callback = score.onPracticeMistakes!;
        callback();
        callback();
        await _pumpUntilFound(tester, find.byType(QuizScreen));
        await _pumpAsyncWork(tester);
        final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
        expect(quiz.wordIds, ['word-station']);
        expect(quiz.selectionMode, QuizWordSelectionMode.weakness);
        expect(find.text('คำถาม 1 จาก 1'), findsOneWidget);
        expect(identical(quiz.learning, learning), isTrue);
        expect(
          await database.select(database.learningSessions).get(),
          hasLength(2),
        );
        final after = await tester.runAsync(() => _voiceSnapshot(database));
        for (final table in [
          'answer_attempts',
          'srs_states',
          'points_ledger_entries',
          'reward_transactions',
          'outbox_operations',
        ]) {
          expect(before, contains(table));
          expect(after![table], before![table], reason: table);
        }
        final quizContext = tester.element(find.byType(QuizScreen));
        final route = ModalRoute.of(quizContext)! as MaterialPageRoute<void>;
        if (completeRepair) {
          await tester.tap(find.text('สถานี'));
          await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
          await tester.ensureVisible(find.text('ดูผลการเรียน'));
          await tester.tap(find.text('ดูผลการเรียน'));
          await _pumpUntilFound(tester, find.byType(ScoreScreen));
          await tester.pumpAndSettle();
          expect(
            ModalRoute.of(
              tester.element(find.byType(ScoreScreen)),
            )!.settings.name,
            'learning/score',
          );
          final completedSnapshot = await tester.runAsync(
            () => _voiceSnapshot(database),
          );
          await tester.tap(find.text('กลับไปเลือกกิจกรรม'));
          await tester.pumpAndSettle();
          expect(
            await tester.runAsync(() => _voiceSnapshot(database)),
            completedSnapshot,
          );
        } else {
          Navigator.of(quizContext).pop();
        }
        await tester.pumpAndSettle();
        expect(find.byType(ScoreScreen), findsNothing);
        expect(
          tester.state(find.byType(SourcePracticeScreen)),
          same(sourceState),
        );
        final sourceContext = tester.element(find.byType(SourcePracticeScreen));
        final deferred =
            route.builder(sourceContext) as ValueListenableBuilder<int>;
        expect(
          deferred.builder(sourceContext, deferred.valueListenable.value, null),
          isNot(isA<QuizScreen>()),
        );
        callback();
        await _pumpAsyncWork(tester);
        expect(
          await database.select(database.learningSessions).get(),
          hasLength(2),
        );
      },
    );
  }

  for (final change in [
    'owner',
    'deleted',
    'category',
    'renamed',
    'deleted-category',
  ]) {
    testWidgets('Voice Result rejects $change before explicit repair', (
      tester,
    ) async {
      await openVoiceResult(tester);
      await changeVoiceTarget(change);
      final callback = tester
          .widget<ScoreScreen>(find.byType(ScoreScreen))
          .onPracticeMistakes!;
      callback();
      await _pumpAsyncWork(tester);
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsNothing);
      expect(find.byType(ScoreScreen), findsNothing);
      expect(
        await database.select(database.learningSessions).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      callback();
      await _pumpAsyncWork(tester);
      expect(
        await database.select(database.learningSessions).get(),
        hasLength(1),
      );
    });
  }

  testWidgets('Voice Result pending repair rejects owner change and Back', (
    tester,
  ) async {
    final delayed = useDelayedOwners();
    await openVoiceResult(tester);
    final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
    delayed.delayNextLookup();
    score.onPracticeMistakes!();
    await delayed.waitUntilDelayed;
    await _switchOwner(database, ownerId);
    await tester.tap(find.text('กลับไปเลือกกิจกรรม'));
    await tester.pumpAndSettle();
    delayed.release();
    await _pumpAsyncWork(tester);
    expect(find.byType(QuizScreen), findsNothing);
    expect(find.byType(ScoreScreen), findsNothing);
    expect(
      await database.select(database.learningSessions).get(),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  for (final repairActive in [
    'none',
    'quiz',
    'score',
    'nested',
    'nested-burst',
  ]) {
    testWidgets(
      'Voice Result hides recorded owner after known late Source invalidation repair=$repairActive',
      (tester) async {
        final delayed = useDelayedOwners();
        final gateway = _SourceSpeechGateway();
        await prepareVoice(tester, speech: SpeechPracticeUseCases(gateway));
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('review-source-text')),
          -200,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 20,
        );
        final review = tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('review-source-text')),
            )
            .onPressed!;
        final editor = tester.widget<TextField>(
          find.byKey(const ValueKey('source-text')),
        );
        await _scrollUntilFound(
          tester,
          find.byKey(const ValueKey('start-source-voice')),
        );
        delayed.delayNextLookup();
        review();
        await delayed.waitUntilDelayed;
        await tester.tap(find.byKey(const ValueKey('start-source-voice')));
        await _pumpUntilFound(tester, find.byType(SpeakToTextScreen));
        await tester.pumpAndSettle();
        final mic = find.byKey(const ValueKey('speech-listen-button'));
        await _scrollUntilFound(tester, mic);
        await tester.tap(mic);
        await _pumpUntilCondition(tester, () => gateway.startCalls == 1);
        gateway.onEvent!(
          SpeechRecognitionEvent(
            transcript: 'wrong',
            isFinal: true,
            recognizedAtUtc: DateTime.utc(2026, 10, 23),
            engine: 'synthetic',
            locale: 'en-US',
          ),
        );
        await _pumpUntilFound(
          tester,
          find.byKey(const ValueKey('source-voice-saved')),
        );
        final finish = find.byKey(const ValueKey('source-voice-finish'));
        await _scrollUntilFound(tester, finish);
        await tester.tap(finish);
        await _pumpUntilFound(tester, find.byType(ScoreScreen));
        await tester.pumpAndSettle();
        expect(find.text('station'), findsOneWidget);
        if (repairActive != 'none') {
          tester
              .widget<ScoreScreen>(find.byType(ScoreScreen))
              .onPracticeMistakes!();
          await _pumpUntilFound(tester, find.byType(QuizScreen));
          await _pumpAsyncWork(tester);
        }
        for (
          var round = 0;
          round <
              (repairActive.startsWith('nested')
                  ? 2
                  : repairActive == 'score'
                  ? 1
                  : 0);
          round++
        ) {
          if (round > 0) {
            await tester.tap(find.text('ฝึกคำที่ผิด (1)'));
            await _pumpUntilFound(tester, find.byType(QuizScreen));
            await _pumpAsyncWork(tester);
          }
          await tester.tap(find.text('เฉลยคำตอบ'));
          await _pumpUntilFound(tester, find.text('ดูผลการเรียน'));
          await tester.ensureVisible(find.text('ดูผลการเรียน'));
          await tester.tap(find.text('ดูผลการเรียน'));
          await _pumpUntilFound(tester, find.text('คำที่ควรฝึกต่อ'));
          await tester.pumpAndSettle();
          expect(
            ModalRoute.of(
              tester.element(find.byType(ScoreScreen)),
            )!.settings.name,
            'learning/score',
          );
        }
        if (repairActive == 'nested-burst') {
          for (var change = 0; change < 6; change++) {
            editor.onChanged!('changed $change');
          }
        }
        await _switchOwner(database, ownerId);
        delayed.release();
        await _pumpAsyncWork(tester);
        expect(find.byType(ScoreScreen), findsNothing);
        expect(find.byType(QuizScreen), findsNothing);
        expect(find.text('station'), findsNothing);
        expect(find.text('สถานี'), findsNothing);
        expect(find.byType(SourcePracticeScreen), findsOneWidget);
        expect(
          find.byKey(const ValueKey('choose-source-file')),
          findsOneWidget,
        );
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(
            repairActive.startsWith('nested')
                ? 3
                : repairActive == 'score'
                ? 2
                : 1,
          ),
        );
      },
    );
  }

  testWidgets('Voice Result hides after active parent dependency replacement', (
    tester,
  ) async {
    await openVoiceResult(tester);
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.byType(ScoreScreen), findsNothing);
    expect(find.text('station'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final invalid in [
    'null',
    'id',
    'state',
    'zero',
    'both',
    'negative',
    'score',
  ]) {
    testWidgets('Source rejects returned Voice summary $invalid', (
      tester,
    ) async {
      await prepareVoice(tester);
      await tester.tap(find.byKey(const ValueKey('start-source-voice')));
      await _pumpUntilFound(tester, find.byType(SpeakToTextScreen));
      final context = tester.element(find.byType(SpeakToTextScreen));
      final voice = tester.widget<SpeakToTextScreen>(
        find.byType(SpeakToTextScreen),
      );
      final summary = invalid == 'null'
          ? null
          : LearningSessionSummary(
              id: invalid == 'id' ? 'other' : voice.sessionId!,
              state: invalid == 'state' ? 'active' : 'completed',
              correctCount: invalid == 'zero'
                  ? 0
                  : invalid == 'negative'
                  ? -1
                  : 1,
              wrongCount: invalid == 'both' ? 1 : 0,
              score: invalid == 'score' ? 55 : 100,
            );
      Navigator.of(context).removeRoute(ModalRoute.of(context)!, summary);
      await _pumpAsyncWork(tester);
      expect(find.byType(ScoreScreen), findsNothing);
      expect(find.byType(SourcePracticeScreen), findsOneWidget);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(
        (await database.select(database.learningSessions).getSingle()).state,
        'active',
      );
    });
  }

  for (final change in [
    'owner',
    'edit',
    'reselection',
    'dependency',
    'dispose',
  ]) {
    testWidgets('Source result await rejects changed $change context', (
      tester,
    ) async {
      final delayed = useDelayedOwners();
      await prepareVoice(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('choose-source-file')),
        -200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      final select = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('choose-source-file')),
          )
          .onPressed!;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('source-text')),
        -200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      final editor = tester.widget<TextField>(
        find.byKey(const ValueKey('source-text')),
      );
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('start-source-voice')),
      );
      await tester.tap(find.byKey(const ValueKey('start-source-voice')));
      await _pumpUntilFound(tester, find.byType(SpeakToTextScreen));
      final context = tester.element(find.byType(SpeakToTextScreen));
      final voice = tester.widget<SpeakToTextScreen>(
        find.byType(SpeakToTextScreen),
      );
      delayed.delayNextLookup();
      Navigator.of(context).removeRoute(
        ModalRoute.of(context)!,
        LearningSessionSummary(
          id: voice.sessionId!,
          state: 'completed',
          correctCount: 1,
          wrongCount: 0,
          score: 100,
        ),
      );
      await _pumpUntilCondition(
        tester,
        () => find.byType(SpeakToTextScreen).evaluate().isEmpty,
      );
      await delayed.waitUntilDelayed;
      if (change == 'owner') await _switchOwner(database, ownerId);
      if (change == 'edit') {
        editor.controller!.text = 'station is changed for every learner today';
        editor.onChanged!(editor.controller!.text);
      }
      if (change == 'reselection') {
        select();
        await _pumpAsyncWork(tester);
      }
      if (change == 'dependency') await tester.pumpWidget(screen());
      if (change == 'dispose') {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      }
      delayed.release();
      await _pumpAsyncWork(tester);
      expect(find.byType(ScoreScreen), findsNothing);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    for (final brightness in Brightness.values) {
      testWidgets('Voice Result 2x readable controls $size $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        tester.view.viewInsets = const FakeViewPadding(bottom: 120);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final semantics = tester.ensureSemantics();
        try {
          await openVoiceResult(tester);
          final scoreContext = tester.element(find.byType(ScoreScreen));
          expect(Theme.of(scoreContext).brightness, brightness);
          expect(MediaQuery.textScalerOf(scoreContext).scale(16), 32);
          expect(MediaQuery.viewInsetsOf(scoreContext).bottom, 120);
          final repair = find.text('ฝึกคำที่ผิด (1)');
          await tester.ensureVisible(repair);
          await tester.pumpAndSettle();
          expect(repair.hitTestable(), findsOneWidget);
          expect(
            tester
                .getSize(
                  find.ancestor(
                    of: repair,
                    matching: find.byType(FilledButton),
                  ),
                )
                .height,
            greaterThanOrEqualTo(48),
          );
          expect(find.bySemanticsLabel(RegExp('ฝึกคำที่ผิด')), findsWidgets);
          final back = find.text('กลับไปเลือกกิจกรรม');
          await tester.ensureVisible(back);
          await tester.pumpAndSettle();
          expect(back.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(back);
          await tester.pumpAndSettle();
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets(
    'Voice route builder keeps its pinned owner after a late Source review',
    (tester) async {
      final delayed = useDelayedOwners();
      await prepareVoice(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('review-source-text')),
        -200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      final review = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('review-source-text')),
          )
          .onPressed!;
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('start-source-voice')),
      );
      await tester.pumpAndSettle();
      delayed.delayNextLookup();
      review();
      await delayed.waitUntilDelayed;
      await tester.tap(find.byKey(const ValueKey('start-source-voice')));
      await _pumpUntilFound(tester, find.byType(SpeakToTextScreen));
      await _pumpAsyncWork(tester);
      final context = tester.element(find.byType(SpeakToTextScreen));
      final route =
          ModalRoute.of(context)! as MaterialPageRoute<LearningSessionSummary>;
      expect(
        tester
            .widget<SpeakToTextScreen>(find.byType(SpeakToTextScreen))
            .sourceOwnerId,
        ownerId,
      );
      await _switchOwner(database, ownerId);
      delayed.release();
      await _pumpAsyncWork(tester);
      final rebuilt = route.builder(context) as SpeakToTextScreen;
      expect(rebuilt.sourceOwnerId, ownerId);
      expect(identical(rebuilt.learning, learning), isTrue);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
    },
  );

  _SourceVoiceStartRepository voiceStartRepository({
    Completer<void>? gate,
    List<QuizWord>? selected,
  }) {
    final repository = _SourceVoiceStartRepository(
      DriftLearningRepository(database),
      gate: gate,
      selected: selected,
    );
    learning = LearningUseCases(
      owners: owners,
      repository: repository,
      generateId: () => 'voice-${++id}',
      nowUtc: () => DateTime.utc(2026, 10, 23),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'I4d'),
    );
    return repository;
  }

  for (final change in ['owner', 'deleted', 'category', 'renamed']) {
    testWidgets('Voice rejects $change before session creation', (
      tester,
    ) async {
      await prepareVoice(tester);
      await changeVoiceTarget(change);
      await tester.tap(find.byKey(const ValueKey('start-source-voice')));
      await _pumpAsyncWork(tester);
      expect(find.byType(SpeakToTextScreen), findsNothing);
      await _expectNoPracticeWrites(database);
      expect(voice.requests, isEmpty);
    });
  }

  for (final change in ['owner', 'deleted', 'category', 'renamed', 'edit']) {
    testWidgets('Voice revalidates $change after awaited session start', (
      tester,
    ) async {
      final gate = Completer<void>();
      final repository = voiceStartRepository(gate: gate);
      await prepareVoice(tester);
      await tester.tap(find.byKey(const ValueKey('start-source-voice')));
      await _pumpUntilCondition(tester, () => repository.entered.isCompleted);
      if (change == 'edit') {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('source-text')),
          -200,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 20,
        );
        await tester.enterText(
          find.byKey(const ValueKey('source-text')),
          'The station is busy and ready today.',
        );
      } else {
        await changeVoiceTarget(change);
      }
      gate.complete();
      await _pumpAsyncWork(tester);
      expect(find.byType(SpeakToTextScreen), findsNothing);
      expect(
        await database.select(database.learningSessions).get(),
        hasLength(1),
      );
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        isEmpty,
      );
      expect(await database.select(database.rewardTransactions).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
      expect(voice.requests, isEmpty);
    });
  }

  for (final result in ['empty', 'wrong-target']) {
    testWidgets('Voice rejects $result session output', (tester) async {
      voiceStartRepository(
        selected: result == 'empty'
            ? []
            : const [
                QuizWord(
                  id: 'wrong-word',
                  categoryId: 'category-1',
                  spelling: 'wrong',
                  meaning: 'ผิด',
                  partOfSpeech: 'noun',
                ),
              ],
      );
      await prepareVoice(tester);
      await tester.tap(find.byKey(const ValueKey('start-source-voice')));
      await _pumpAsyncWork(tester);
      expect(find.byType(SpeakToTextScreen), findsNothing);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(voice.requests, isEmpty);
    });
  }

  testWidgets('Voice rapid taps create only one session', (tester) async {
    await prepareVoice(tester);
    final action = find.byKey(const ValueKey('start-source-voice'));
    await tester.tap(action);
    await tester.tap(action);
    await _pumpUntilFound(tester, find.byType(SpeakToTextScreen));
    await _pumpAsyncWork(tester);
    expect(find.byType(SpeakToTextScreen, skipOffstage: false), findsOneWidget);
    expect(
      await database.select(database.learningSessions).get(),
      hasLength(1),
    );
    expect(await database.select(database.answerAttempts).get(), isEmpty);
  });

  testWidgets('Voice edited pending validation creates no session', (
    tester,
  ) async {
    final delayed = useDelayedOwners();
    await prepareVoice(tester);
    delayed.delayNextLookup();
    await tester.tap(find.byKey(const ValueKey('start-source-voice')));
    await delayed.waitUntilDelayed;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-text')),
      -200,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
    await tester.enterText(
      find.byKey(const ValueKey('source-text')),
      'The station is busy and ready today.',
    );
    delayed.release();
    await _pumpAsyncWork(tester);
    expect(find.byType(SpeakToTextScreen), findsNothing);
    await _expectNoPracticeWrites(database);
  });

  testWidgets('Ask Lexi explicit Send forwards only the edited visible draft', (
    tester,
  ) async {
    await tester.runAsync(
      () => tutor.updateConsents(
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
    await prepareAsk(tester);
    await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
    await _pumpUntilFound(tester, find.byType(AiTutorScreen));
    await tester.pumpAndSettle();
    expect(tutorGateway.messages, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'Edited question about station only',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();
    expect(tutorGateway.messages, ['Edited question about station only']);
    expect(find.text('Synthetic word-only reply'), findsOneWidget);
    await _expectNoPracticeWrites(database);
    expect(await database.select(database.rewardTransactions).get(), isEmpty);
  });

  testWidgets('rapid Ask Lexi taps open only one draft and write no practice', (
    tester,
  ) async {
    await prepareAsk(tester);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('start-source-ask-lexi')),
    );
    button.onPressed!();
    button.onPressed!();
    await _pumpUntilFound(tester, find.byType(AiTutorScreen));
    await tester.pumpAndSettle();
    expect(find.byType(AiTutorScreen, skipOffstage: false), findsOneWidget);
    expect(tutorGateway.messages, isEmpty);
    await _expectNoPracticeWrites(database);
  });

  for (final unavailable in ['missing', 'mismatch']) {
    testWidgets('Ask Lexi $unavailable tutor leaves local practice usable', (
      tester,
    ) async {
      if (unavailable == 'mismatch') {
        tutorScope = const GeminiScope(
          ownerId: 'other-owner',
          firebaseUid: null,
          isAnonymous: true,
        );
      }
      await prepareAsk(tester, withTutor: unavailable != 'missing');
      await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
      await _pumpAsyncWork(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('source-practice-error')),
        -200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      expect(
        find.text('ผู้ช่วย AI ไม่พร้อมสำหรับบัญชีนี้ ยังฝึกในเครื่องได้'),
        findsOneWidget,
      );
      expect(find.byType(AiTutorScreen), findsNothing);
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('start-source-flashcards')),
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('start-source-flashcards')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tutorGateway.messages, isEmpty);
      await _expectNoPracticeWrites(database);
    });
  }

  for (final change in ['owner', 'deleted', 'category', 'renamed']) {
    testWidgets('Ask Lexi rejects $change after confirmation', (tester) async {
      await prepareAsk(tester);
      if (change == 'owner') {
        await _switchOwner(database, ownerId);
      } else if (change == 'category') {
        await database
            .into(database.vocabularyCategories)
            .insert(
              VocabularyCategoriesCompanion.insert(
                id: 'other-category',
                ownerId: ownerId,
                name: 'Other',
                normalizedName: 'other',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        await (database.update(
          database.vocabularyWords,
        )..where((row) => row.id.equals('word-station'))).write(
          const VocabularyWordsCompanion(categoryId: Value('other-category')),
        );
      } else {
        await (database.update(
          database.vocabularyWords,
        )..where((row) => row.id.equals('word-station'))).write(
          change == 'deleted'
              ? const VocabularyWordsCompanion(isDeleted: Value(true))
              : const VocabularyWordsCompanion(
                  spelling: Value('ready'),
                  normalizedSpelling: Value('ready'),
                ),
        );
      }
      await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
      await _pumpUntilFound(
        tester,
        find.byKey(const ValueKey('source-practice-error')),
      );
      expect(find.byType(AiTutorScreen), findsNothing);
      expect(tutorGateway.messages, isEmpty);
      await _expectNoPracticeWrites(database);
    });
  }

  testWidgets(
    'Ask Lexi rejects edited pending launch then accepts fresh reconfirmation',
    (tester) async {
      final delayed = useDelayedOwners();
      await prepareAsk(tester);
      delayed.delayNextLookup();
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('start-source-ask-lexi')),
          )
          .onPressed!();
      await delayed.waitUntilDelayed;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('source-text')),
        -200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      await tester.enterText(
        find.byKey(const ValueKey('source-text')),
        'The station is busy and ready for every learner today.',
      );
      delayed.release();
      await _pumpAsyncWork(tester);
      expect(find.byType(AiTutorScreen), findsNothing);
      expect(tutorGateway.messages, isEmpty);
      await _expectNoPracticeWrites(database);
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('review-source-text')),
          )
          .onPressed!();
      await _pumpAsyncWork(tester);
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('confirm-source')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-source')));
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('start-source-ask-lexi')),
      );
      await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
      await _pumpUntilFound(tester, find.byType(AiTutorScreen));
      await tester.pumpAndSettle();
      expect(find.byType(AiTutorScreen, skipOffstage: false), findsOneWidget);
      await _expectNoPracticeWrites(database);
    },
  );

  testWidgets('Ask Lexi rejects owner epoch change while launch awaits', (
    tester,
  ) async {
    final delayed = useDelayedOwners();
    await prepareAsk(tester);
    delayed.delayNextLookup();
    tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('start-source-ask-lexi')),
        )
        .onPressed!();
    await delayed.waitUntilDelayed;
    tutor.invalidateScope();
    delayed.release();
    await _pumpAsyncWork(tester);
    expect(find.byType(AiTutorScreen), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-practice-error')),
      -200,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
    expect(
      find.text('ผู้ช่วย AI ไม่พร้อมสำหรับบัญชีนี้ ยังฝึกในเครื่องได้'),
      findsOneWidget,
    );
    await _expectNoPracticeWrites(database);
  });

  testWidgets('Ask Lexi rejects overlong word without silently truncating it', (
    tester,
  ) async {
    final word = 'a' * 480;
    await (database.update(
      database.vocabularyWords,
    )..where((row) => row.id.equals('word-station'))).write(
      VocabularyWordsCompanion(
        spelling: Value(word),
        normalizedSpelling: Value(word),
      ),
    );
    await tester.pumpWidget(
      screen(text: '$word is ready for every learner today.'),
    );
    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
    final outer = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    for (
      var step = 0;
      step < 20 &&
          find.byKey(const ValueKey('confirm-source')).evaluate().isEmpty;
      step++
    ) {
      outer.jumpTo((outer.pixels + 240).clamp(0, outer.maxScrollExtent));
      await tester.pump();
    }
    final confirm = find.byKey(const ValueKey('confirm-source'));
    await Scrollable.ensureVisible(tester.element(confirm), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(confirm.hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-source')));
    await _pumpAsyncWork(tester);
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-ask-lexi')),
    );
    await tester.tap(find.byKey(const ValueKey('start-source-ask-lexi')));
    await _pumpAsyncWork(tester);
    expect(find.byType(AiTutorScreen), findsNothing);
    outer.jumpTo(0);
    await tester.pump();
    for (
      var step = 0;
      step < 20 &&
          find
              .byKey(const ValueKey('source-practice-error'))
              .evaluate()
              .isEmpty;
      step++
    ) {
      outer.jumpTo((outer.pixels + 240).clamp(0, outer.maxScrollExtent));
      await tester.pump();
    }
    await tester.ensureVisible(
      find.byKey(const ValueKey('source-practice-error')),
    );
    expect(find.textContaining('คำนี้ยาวเกินขอบเขตคำถาม 500'), findsOneWidget);
    expect(tutorGateway.messages, isEmpty);
    await _expectNoPracticeWrites(database);
  });

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    testWidgets(
      'Ask Lexi labelled action reachable at $size 200 percent and IME',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await prepareAsk(tester, size: size, textScale: 2, keyboardInset: 120);
        final action = find.byKey(const ValueKey('start-source-ask-lexi'));
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        expect(find.text('ถาม Lexi เรื่อง station'), findsOneWidget);
        final voiceAction = find.byKey(const ValueKey('start-source-voice'));
        await _scrollUntilFound(tester, voiceAction);
        await tester.pumpAndSettle();
        expect(voiceAction.hitTestable(), findsOneWidget);
        expect(tester.getSize(voiceAction).height, greaterThanOrEqualTo(48));
        expect(find.text('ฝึกพูดคำว่า station'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(tutorGateway.messages, isEmpty);
        await _expectNoPracticeWrites(database);
      },
    );
  }

  testWidgets('preview and confirmation write nothing before Quiz starts', (
    tester,
  ) async {
    await tester.pumpWidget(screen());

    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
    await _scrollUntilFound(
      tester,
      find.textContaining('คำที่ยังไม่อยู่ในหมวด'),
    );

    expect(find.textContaining('คำที่ยังไม่อยู่ในหมวด'), findsOneWidget);
    expect(find.textContaining('quiet'), findsWidgets);
    await _expectNoPracticeWrites(database);
    expect(await database.select(database.vocabularyWords).get(), hasLength(1));
    expect(await database.select(database.vocabularyImports).get(), isEmpty);

    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('confirm-source')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-source')));
    await tester.pump();
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-reading')),
    );
    expect(find.byKey(const ValueKey('start-source-reading')), findsOneWidget);
    expect(find.byKey(const ValueKey('start-source-quiz')), findsOneWidget);
    await _expectNoPracticeWrites(database);

    await tester.tap(find.byKey(const ValueKey('start-source-quiz')));
    await _pumpUntilFound(tester, find.text('แบบทดสอบจากเนื้อหานี้'));
    final session = await database
        .select(database.learningSessions)
        .getSingle();
    expect(session.activityType, 'sourcePractice');
    expect(await database.select(database.vocabularyWords).get(), hasLength(1));
    expect(await database.select(database.vocabularyImports).get(), isEmpty);
  });

  testWidgets('editing invalidates preview and recomputes matches', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));

    await tester.enterText(
      find.byKey(const ValueKey('source-text')),
      'The airport is quiet and ready for every learner today.',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('confirm-source')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('review-source-text')));
    await _pumpUntilFound(tester, find.text('ยังไม่พบคำศัพท์ในหมวดนี้'));

    await _scrollUntilFound(tester, find.text('ยังไม่พบคำศัพท์ในหมวดนี้'));
    expect(find.text('ยังไม่พบคำศัพท์ในหมวดนี้'), findsOneWidget);
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('confirm-source')),
    );
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirm-source')),
    );
    expect(confirm.onPressed, isNull);
    await _expectNoPracticeWrites(database);
  });

  testWidgets('confirmed Reading starts locally and writes only on progress', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('confirm-source')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-source')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-reading')),
    );
    await tester.tap(find.byKey(const ValueKey('start-source-reading')));
    await _pumpUntilFound(tester, find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'));

    expect(await database.select(database.readingEvents).get(), isEmpty);
    await tester.tap(find.text('เสร็จแล้ว ไปขั้นถัดไป'));
    await _pumpUntilFound(tester, find.text('ขั้นที่ 2: อ่านโดยลดตัวช่วย'));
    final event = await database.select(database.readingEvents).getSingle();
    expect(event.documentId, startsWith('local-source:'));
    expect(event.documentId, isNot(contains('lesson')));
    expect(event.documentRevision, greaterThan(0));
  });

  testWidgets(
    'confirmed Flashcards targets zero-due matches and saves real feedback',
    (tester) async {
      await tester.pumpWidget(screen());
      await tester.tap(find.byKey(const ValueKey('choose-source-file')));
      await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
      expect(await database.select(database.srsStates).get(), isEmpty);
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('confirm-source')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-source')));
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('start-source-flashcards')),
      );
      await tester.tap(find.byKey(const ValueKey('start-source-flashcards')));
      await _pumpUntilFound(tester, find.text('บัตรคำจากเนื้อหานี้'));

      expect(find.text('station').hitTestable(), findsOneWidget);
      final session = await database
          .select(database.learningSessions)
          .getSingle();
      expect(session.activityType, 'srsReview');
      await tester.ensureVisible(find.text('ดูคำแปล'));
      await tester.tap(find.text('ดูคำแปล'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('จำได้แล้ว'));
      await tester.tap(find.text('จำได้แล้ว'));
      await _pumpUntilFound(tester, find.text('บันทึกแล้ว'));

      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(await database.select(database.srsStates).get(), hasLength(1));
      final rewards = await database.select(database.rewardTransactions).get();
      expect(rewards, hasLength(1));
      expect(rewards.single.transactionType, 'creditQuizCorrectV1');
      expect(rewards.single.amount, 1);
      expect(find.text('จบการฝึก'), findsOneWidget);
      expect(await database.select(database.vocabularyImports).get(), isEmpty);
      await tester.tap(find.text('จบการฝึก'));
      await _pumpUntilFound(tester, find.byType(ScoreScreen));
      final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
      expect(score.correctAnswers, 1);
      expect(score.wrongAnswers, 0);
      expect(score.mistakes, isEmpty);
      expect(score.onPracticeMistakes, isNull);
    },
  );

  testWidgets(
    'Reading result maps unique current mistakes and opens explicit repair',
    (tester) async {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: 'word-airport',
              ownerId: ownerId,
              categoryId: 'category-1',
              spelling: 'airport',
              normalizedSpelling: 'airport',
              meaning: 'สนามบิน',
              normalizedMeaning: 'สนามบิน',
              partOfSpeech: 'noun',
              createdAtUtcMs: 2,
              updatedAtUtcMs: 2,
            ),
          );
      await tester.pumpWidget(
        screen(
          text: 'The station and airport are ready for every learner today.',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('choose-source-file')));
      await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('confirm-source')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-source')));
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('start-source-reading')),
      );
      await tester.tap(find.byKey(const ValueKey('start-source-reading')));
      await _pumpUntilFound(tester, find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'));
      final readingContext = tester.element(
        find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'),
      );
      Navigator.of(readingContext).removeRoute(
        ModalRoute.of(readingContext)!,
        LearningSessionResult(
          summary: const LearningSessionSummary(
            id: 'reading-result',
            state: 'completed',
            correctCount: 0,
            wrongCount: 2,
            score: 0,
          ),
          mistakeWordIds: const [
            'word-station',
            'word-airport',
            'word-station',
          ],
        ),
      );
      await _pumpUntilFound(tester, find.byType(ScoreScreen));

      final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
      expect(score.mistakes.map((word) => word.id), [
        'word-station',
        'word-airport',
      ]);
      score.onPracticeMistakes!();
      await _pumpUntilFound(tester, find.byType(QuizScreen));
      expect(tester.widget<QuizScreen>(find.byType(QuizScreen)).wordIds, [
        'word-station',
        'word-airport',
      ]);
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsNothing);
      expect(find.byType(ScoreScreen), findsNothing);
      expect(find.byType(SourcePracticeScreen), findsOneWidget);
    },
  );

  testWidgets('Source rejects a result whose counts do not match targets', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('confirm-source')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-source')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-reading')),
    );
    await tester.tap(find.byKey(const ValueKey('start-source-reading')));
    await _pumpUntilFound(tester, find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'));
    final readingContext = tester.element(
      find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'),
    );
    Navigator.of(readingContext).removeRoute(
      ModalRoute.of(readingContext)!,
      LearningSessionResult(
        summary: const LearningSessionSummary(
          id: 'reading-result',
          state: 'completed',
          correctCount: 1,
          wrongCount: 1,
          score: 50,
        ),
        mistakeWordIds: const ['word-station'],
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ScoreScreen), findsNothing);
    expect(find.byType(SourcePracticeScreen), findsOneWidget);
  });

  testWidgets('owner switch after confirmation blocks practice launch', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('confirm-source')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-source')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-reading')),
    );
    await _switchOwner(database, ownerId);

    await tester.tap(find.byKey(const ValueKey('start-source-reading')));
    await _pumpUntilFound(
      tester,
      find.text('บัญชีผู้เรียนเปลี่ยนแล้ว กรุณาเลือกไฟล์ใหม่'),
    );

    expect(find.text('ฝึกจากไฟล์ในเครื่อง'), findsOneWidget);
    expect(
      find.text('บัญชีผู้เรียนเปลี่ยนแล้ว กรุณาเลือกไฟล์ใหม่'),
      findsOneWidget,
    );
    await _expectNoPracticeWrites(database);
  });

  testWidgets('vocabulary change invalidates confirmation before launch', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('confirm-source')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-source')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-reading')),
    );
    await (database.update(database.vocabularyWords)
          ..where((row) => row.id.equals('word-station')))
        .write(const VocabularyWordsCompanion(isDeleted: Value(true)));

    await tester.tap(find.byKey(const ValueKey('start-source-reading')));
    await _pumpUntilFound(
      tester,
      find.text('คลังคำศัพท์เปลี่ยนแล้ว กรุณาตรวจและยืนยันอีกครั้ง'),
    );

    expect(find.text('ฝึกจากไฟล์ในเครื่อง'), findsOneWidget);
    expect(
      find.text('คลังคำศัพท์เปลี่ยนแล้ว กรุณาตรวจและยืนยันอีกครั้ง'),
      findsOneWidget,
    );
    await _expectNoPracticeWrites(database);
  });

  testWidgets('rapid Quiz taps create one source session', (tester) async {
    await tester.pumpWidget(screen());
    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('confirm-source')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-source')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-quiz')),
    );
    final start = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('start-source-quiz')),
    );

    start.onPressed!();
    start.onPressed!();
    await _pumpUntilFound(tester, find.text('แบบทดสอบจากเนื้อหานี้'));

    expect(
      await database.select(database.learningSessions).get(),
      hasLength(1),
    );
  });

  testWidgets('rapid Flashcards taps create one source session', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('confirm-source')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-source')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-flashcards')),
    );
    final start = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('start-source-flashcards')),
    );

    start.onPressed!();
    start.onPressed!();
    await _pumpUntilFound(tester, find.text('บัตรคำจากเนื้อหานี้'));

    expect(
      await database.select(database.learningSessions).get(),
      hasLength(1),
    );
  });

  testWidgets(
    'editing while Reading launch awaits requires fresh confirmation',
    (tester) async {
      final delayedOwners = useDelayedOwners();
      await tester.pumpWidget(screen());
      await tester.tap(find.byKey(const ValueKey('choose-source-file')));
      await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('confirm-source')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-source')));
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('start-source-reading')),
      );

      delayedOwners.delayNextLookup();
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('start-source-reading')),
          )
          .onPressed!();
      await delayedOwners.waitUntilDelayed;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('source-text')),
        -200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      await tester.enterText(
        find.byKey(const ValueKey('source-text')),
        'The station is busy and ready for every learner today.',
      );
      delayedOwners.release();
      await _pumpAsyncWork(tester);

      expect(find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'), findsNothing);
      expect(find.text('ฝึกจากไฟล์ในเครื่อง'), findsOneWidget);
      await _expectNoPracticeWrites(database);

      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('review-source-text')),
      );
      final readingReview = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('review-source-text')),
      );
      expect(readingReview.onPressed, isNotNull);
      readingReview.onPressed!();
      await _pumpAsyncWork(tester);
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('confirm-source')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-source')));
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('start-source-reading')),
      );
      await tester.tap(find.byKey(const ValueKey('start-source-reading')));
      await _pumpUntilFound(tester, find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'));

      expect(find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'), findsOneWidget);
    },
  );

  testWidgets('editing while Quiz launch awaits requires fresh confirmation', (
    tester,
  ) async {
    final delayedOwners = useDelayedOwners();
    await tester.pumpWidget(screen());
    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('confirm-source')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-source')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-quiz')),
    );

    delayedOwners.delayNextLookup();
    tester
        .widget<OutlinedButton>(find.byKey(const ValueKey('start-source-quiz')))
        .onPressed!();
    await delayedOwners.waitUntilDelayed;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-text')),
      -200,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
    await tester.enterText(
      find.byKey(const ValueKey('source-text')),
      'The station is busy and ready for every learner today.',
    );
    delayedOwners.release();
    await _pumpAsyncWork(tester);

    expect(find.text('แบบทดสอบจากเนื้อหานี้'), findsNothing);
    expect(find.text('ฝึกจากไฟล์ในเครื่อง'), findsOneWidget);
    await _expectNoPracticeWrites(database);

    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('review-source-text')),
    );
    final quizReview = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('review-source-text')),
    );
    expect(quizReview.onPressed, isNotNull);
    quizReview.onPressed!();
    await _pumpAsyncWork(tester);
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('confirm-source')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-source')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-quiz')),
    );
    await tester.tap(find.byKey(const ValueKey('start-source-quiz')));
    await _pumpUntilFound(tester, find.text('แบบทดสอบจากเนื้อหานี้'));

    expect(find.text('แบบทดสอบจากเนื้อหานี้'), findsOneWidget);
    expect(
      await database.select(database.learningSessions).get(),
      hasLength(1),
    );
  });

  testWidgets(
    'editing while Flashcards launch awaits requires fresh confirmation',
    (tester) async {
      final delayedOwners = useDelayedOwners();
      await tester.pumpWidget(screen());
      await tester.tap(find.byKey(const ValueKey('choose-source-file')));
      await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('confirm-source')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-source')));
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('start-source-flashcards')),
      );

      delayedOwners.delayNextLookup();
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('start-source-flashcards')),
          )
          .onPressed!();
      await delayedOwners.waitUntilDelayed;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('source-text')),
        -200,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      await tester.enterText(
        find.byKey(const ValueKey('source-text')),
        'The station is busy and ready for every learner today.',
      );
      delayedOwners.release();
      await _pumpAsyncWork(tester);

      expect(find.text('บัตรคำจากเนื้อหานี้'), findsNothing);
      expect(find.text('ฝึกจากไฟล์ในเครื่อง'), findsOneWidget);
      await _expectNoPracticeWrites(database);

      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('review-source-text')),
      );
      final review = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('review-source-text')),
      );
      expect(review.onPressed, isNotNull);
      review.onPressed!();
      await _pumpAsyncWork(tester);
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('confirm-source')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-source')));
      await _scrollUntilFound(
        tester,
        find.byKey(const ValueKey('start-source-flashcards')),
      );
      await tester.tap(find.byKey(const ValueKey('start-source-flashcards')));
      await _pumpUntilFound(tester, find.text('บัตรคำจากเนื้อหานี้'));

      expect(find.text('บัตรคำจากเนื้อหานี้'), findsOneWidget);
      expect(
        await database.select(database.learningSessions).get(),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'reduced-motion unknown-word sheet opens and closes without a timed transition',
    (tester) async {
      await tester.pumpWidget(screen(reducedMotion: true));
      await tester.tap(find.byKey(const ValueKey('choose-source-file')));
      await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
      final showUnknown = find.byKey(const ValueKey('show-all-unknown'));
      await tester.scrollUntilVisible(
        showUnknown,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(showUnknown);
      await tester.pump();

      final sheetContext = tester.element(find.byType(BottomSheet));
      final route = ModalRoute.of(sheetContext)!;
      expect(route.animation!.value, 1);
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      expect(find.text('quiet').hitTestable(), findsOneWidget);

      Navigator.of(sheetContext).pop();
      await tester.pump();
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      expect(showUnknown.hitTestable(), findsOneWidget);
    },
  );

  testWidgets('all unknown words remain inspectable after the summary', (
    tester,
  ) async {
    final unknown = List.generate(55, (index) {
      final first = String.fromCharCode(97 + (index ~/ 26));
      final second = String.fromCharCode(97 + (index % 26));
      return 'token$first$second';
    });
    await tester.pumpWidget(
      screen(text: 'The station ${unknown.join(' ')} is ready today.'),
    );
    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    var offset = 0.0;
    for (var attempt = 0; attempt < 30; attempt++) {
      if (find
          .byKey(const ValueKey('show-all-unknown'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      offset = (offset + 240).clamp(0, scrollable.position.maxScrollExtent);
      scrollable.position.jumpTo(offset);
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('show-all-unknown')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('show-all-unknown')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('show-all-unknown')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(unknown.last),
      160,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 80,
    );

    expect(find.text(unknown.last), findsOneWidget);
  });

  testWidgets('360x800 at 200 percent keeps confirmation reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(screen(textScale: 2));
    await tester.tap(find.byKey(const ValueKey('choose-source-file')));
    await _pumpUntilFound(tester, find.byKey(const ValueKey('source-text')));

    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('confirm-source')),
    );
    expect(find.byKey(const ValueKey('confirm-source')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-source')));
    await _scrollUntilFound(
      tester,
      find.byKey(const ValueKey('start-source-flashcards')),
    );
    expect(
      find.byKey(const ValueKey('start-source-flashcards')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _expectNoPracticeWrites(AppDatabase database) async {
  expect(await database.select(database.learningSessions).get(), isEmpty);
  expect(await database.select(database.answerAttempts).get(), isEmpty);
  expect(await database.select(database.readingEvents).get(), isEmpty);
  expect(await database.select(database.outboxOperations).get(), isEmpty);
}

Future<Map<String, Object?>> _voiceSnapshot(AppDatabase database) async => {
  for (final table in database.allTables)
    table.actualTableName:
        (await database
                .customSelect('SELECT * FROM "${table.actualTableName}"')
                .get())
            .map((row) => row.data)
            .toList(),
};

Future<void> _switchOwner(AppDatabase database, String previousOwnerId) async {
  await (database.update(database.localOwners)
        ..where((row) => row.id.equals(previousOwnerId)))
      .write(const LocalOwnersCompanion(isActive: Value(false)));
  await database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(id: 'local:owner-b', createdAtUtcMs: 2),
      );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Widget did not appear after bounded pumps: $finder');
}

Future<void> _pumpUntilCondition(
  WidgetTester tester,
  bool Function() ready,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Source voice operation did not reach its synthetic gate');
}

Future<void> _pumpAsyncWork(WidgetTester tester) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

Future<void> _scrollUntilFound(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 20,
  );
  await tester.pump();
}

final class _DelayedOwnerRepository implements LocalOwnerRepository {
  _DelayedOwnerRepository(this._delegate);

  final LocalOwnerRepository _delegate;
  Completer<void>? _entered;
  Completer<void>? _release;
  bool _delayNext = false;

  void delayNextLookup() {
    _entered = Completer<void>();
    _release = Completer<void>();
    _delayNext = true;
  }

  Future<void> get waitUntilDelayed => _entered!.future;

  void release() => _release!.complete();

  @override
  Future<domain.LocalOwner> getOrCreateActiveOwner() async {
    if (_delayNext) {
      _delayNext = false;
      _entered!.complete();
      await _release!.future;
    }
    return _delegate.getOrCreateActiveOwner();
  }

  @override
  Future<domain.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => _delegate.bindFirebaseUid(ownerId, firebaseUid);
}

final class _UnusedGuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      throw StateError('must not start Guest');
}

final class _SourceVoiceStartRepository implements LearningRepository {
  _SourceVoiceStartRepository(this.delegate, {this.gate, this.selected});
  final LearningRepository delegate;
  final Completer<void>? gate;
  final List<QuizWord>? selected;
  final entered = Completer<void>();
  Future<void> Function()? afterFinish;
  int finishCalls = 0;
  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    String? afterWordId,
    required int limit,
  }) => wordIds != null && selected != null
      ? Future.value(selected)
      : delegate.listQuizWords(
          ownerId: ownerId,
          categoryId: categoryId,
          wordIds: wordIds,
          afterWordId: afterWordId,
          limit: limit,
        );
  @override
  Future<void> startSession(LearningSessionDraft session) async {
    await delegate.startSession(session);
    entered.complete();
    await gate?.future;
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) =>
      delegate.recordAnswer(command);
  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    finishCalls++;
    final summary = await delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
    await afterFinish?.call();
    return summary;
  }

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) => delegate.listDueWords(ownerId: ownerId, nowUtc: nowUtc, limit: limit);
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

final class _SourceSpeechGateway implements SpeechRecognitionGateway {
  int startCalls = 0;
  int cancelCalls = 0;
  SpeechEventCallback? onEvent;
  @override
  bool isListening = false;
  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;
  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String) onStatus,
  }) async {}
  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    startCalls++;
    isListening = true;
    this.onEvent = onEvent;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    isListening = false;
  }
}

final class _SourceTutorStore implements GeminiSettingsStore {
  GeminiConfiguration value = const GeminiConfiguration(
    key: 'synthetic-key-not-production',
  );
  @override
  Future<GeminiConfiguration> read(GeminiScope scope) async => value;
  @override
  Future<void> write(
    GeminiScope scope,
    GeminiConfiguration configuration,
  ) async => value = configuration;
}

final class _SourceTutorGateway implements GeminiGateway {
  final messages = <String>[];
  GeminiException? failure;
  Completer<void>? replyGate;
  GeminiCancellation? cancellation;
  @override
  String get model => 'synthetic-tutor';
  @override
  Future<void> validateKey(
    String key, {
    GeminiCancellation? cancellation,
  }) async => throw StateError('must not validate key');
  @override
  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    GeminiTutorMode mode = GeminiTutorMode.guided,
    String? learningSummary,
    GeminiCancellation? cancellation,
  }) async {
    messages.add(learnerMessage);
    this.cancellation = cancellation;
    await replyGate?.future;
    final error = failure;
    if (error != null) throw error;
    return 'Synthetic word-only reply';
  }
}
