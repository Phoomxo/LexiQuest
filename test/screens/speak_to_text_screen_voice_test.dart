import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/screens/speak_to_text_screen.dart';
import 'package:vocab_learning_app/screens/device_permission_center_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> spokenRequests = [];
  int stopCalls = 0;
  VoicePlaybackResult? resultToReturn;
  Object? errorToThrow;
  Object? stopError;
  Completer<void>? stopGate;
  List<String>? log;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return resultToReturn ??
        const VoicePlaybackResult(
          requestedEngine: VoiceEngine.omniVoice,
          actualEngine: VoiceEngine.omniVoice,
          usedFallback: false,
          cacheHit: false,
          requestId: 'test-req-123',
          modelVersion: '0.2.1',
        );
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    log?.add('stop-tts');
    await stopGate?.future;
    if (stopError != null) throw stopError!;
  }
}

void main() {
  for (final correct in [true, false]) {
    testWidgets('source returns acknowledged typed result correct=$correct', (
      tester,
    ) async {
      final results = <LearningSessionSummary?>[];
      final repository = _RecordingLearningRepository()..finishFailures = 1;
      final gateway = _LifecycleSpeechGateway();
      await _openSource(
        tester,
        repository: repository,
        gateway: gateway,
        results: results,
      );
      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
      await tester.pumpAndSettle();
      gateway.emit(correct ? 'cat' : 'dog');
      await tester.pumpAndSettle();
      final finish = find.byKey(const ValueKey('source-voice-finish'));
      await tester.scrollUntilVisible(finish, 200);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(results, isEmpty);
      expect(find.byType(SpeakToTextScreen), findsOneWidget);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(results, hasLength(1));
      expect(results.single, isNotNull);
      expect(results.single!.id, 'synthetic-session');
      expect(results.single!.correctCount, correct ? 1 : 0);
      expect(results.single!.wrongCount, correct ? 0 : 1);
      expect(results.single!.score, correct ? 100 : 0);
      expect(repository.answers, hasLength(1));
      expect(repository.finishCalls, 2);
    });
  }

  for (final invalid in [
    const LearningSessionSummary(
      id: 'other',
      state: 'completed',
      correctCount: 1,
      wrongCount: 0,
      score: 100,
    ),
    const LearningSessionSummary(
      id: 'synthetic-session',
      state: 'active',
      correctCount: 1,
      wrongCount: 0,
      score: 100,
    ),
    const LearningSessionSummary(
      id: 'synthetic-session',
      state: 'completed',
      correctCount: 0,
      wrongCount: 0,
      score: 0,
    ),
    const LearningSessionSummary(
      id: 'synthetic-session',
      state: 'completed',
      correctCount: 1,
      wrongCount: 1,
      score: 50,
    ),
    const LearningSessionSummary(
      id: 'synthetic-session',
      state: 'completed',
      correctCount: 0,
      wrongCount: 1,
      score: 0,
    ),
    const LearningSessionSummary(
      id: 'synthetic-session',
      state: 'completed',
      correctCount: 1,
      wrongCount: 0,
      score: 75,
    ),
  ]) {
    testWidgets(
      'source rejects contradictory summary ${invalid.id}/${invalid.state}/${invalid.correctCount}/${invalid.wrongCount}/${invalid.score}',
      (tester) async {
        final results = <LearningSessionSummary?>[];
        final repository = _RecordingLearningRepository()..summary = invalid;
        final gateway = _LifecycleSpeechGateway();
        await _openSource(
          tester,
          repository: repository,
          gateway: gateway,
          results: results,
        );
        await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
        await tester.pumpAndSettle();
        gateway.emit('cat');
        await tester.pumpAndSettle();
        final finish = find.byKey(const ValueKey('source-voice-finish'));
        await tester.scrollUntilVisible(finish, 200);
        await tester.tap(finish);
        await tester.pumpAndSettle();
        expect(results, isEmpty);
        expect(find.byType(SpeakToTextScreen), findsOneWidget);
        expect(find.textContaining('ปิดการฝึกไม่สำเร็จ'), findsOneWidget);
        expect(repository.answers, hasLength(1));
      },
    );
  }

  testWidgets('source explicit stop accepts only one final assessment', (
    tester,
  ) async {
    final gateway = _LifecycleSpeechGateway()..emitOnStop = true;
    final repository = _RecordingLearningRepository();
    await _openSource(tester, repository: repository, gateway: gateway);
    final mic = find.byKey(const ValueKey('speech-listen-button'));
    await tester.tap(mic);
    await tester.pumpAndSettle();
    gateway.onEvent!(_event('partial', isFinal: false));
    await tester.pumpAndSettle();
    expect(repository.answers, isEmpty);
    await tester.tap(mic);
    await tester.pumpAndSettle();
    gateway.emit('contradictory final');
    await tester.pumpAndSettle();
    expect(repository.answers, hasLength(1));
    expect(repository.answers.single.isCorrect, isTrue);
    expect(repository.answers.single.occurredAtUtc.isUtc, isTrue);
    expect(repository.answers.single.responseTimeMs, greaterThanOrEqualTo(0));
    expect(
      repository.answers.single.providerProvenance,
      'synthetic-stt|en-US|transcript-edit-distance-v1',
    );
    expect(tester.widget<FilledButton>(mic).onPressed, isNull);
  });
  testWidgets(
    'source identity replacement cannot rebind an old microphone result',
    (tester) async {
      final repository = _RecordingLearningRepository();
      final learning = LearningUseCases(
        owners: _Owners(),
        repository: repository,
        generateId: () => 'identity',
        nowUtc: () => DateTime.utc(2026, 10, 23),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'I4d'),
      );
      final speechGateway = _LifecycleSpeechGateway();
      final speech = SpeechPracticeUseCases(speechGateway);
      final voice = VoiceUseCases(FakeVoiceProvider());
      Widget screen(String word, String session) => MaterialApp(
        home: SpeakToTextScreen(
          correctWord: word,
          sourceOwnerId: 'synthetic-owner',
          sessionId: session,
          wordId: 'word-$word',
          learning: learning,
          speechPractice: speech,
          voice: voice,
        ),
      );
      await tester.pumpWidget(screen('cat', 'session-a'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
      await tester.pumpAndSettle();
      final old = speechGateway.onEvent!;
      await tester.pumpWidget(screen('dog', 'session-b'));
      await tester.pumpAndSettle();
      old(_event('cat'));
      await tester.pumpAndSettle();
      expect(repository.answers, isEmpty);
      expect(find.textContaining('บัญชีผู้เรียนเปลี่ยน'), findsOneWidget);
    },
  );
  testWidgets(
    'source real Drift lost acknowledgements replay one frozen answer and finish',
    (tester) async {
      final results = <LearningSessionSummary?>[];
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'voice-owner',
        nowUtc: () => DateTime.utc(2026, 10, 23),
      );
      final repository = _LostAckRepository(DriftLearningRepository(db));
      var id = 0;
      final learning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'voice-${++id}',
        nowUtc: () => DateTime.utc(2026, 10, 23),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'I4d'),
      );
      late String ownerId;
      late QuizSession session;
      await tester.runAsync(() async {
        ownerId = (await owners.getOrCreateActiveOwner()).id;
        await db
            .into(db.vocabularyCategories)
            .insert(
              VocabularyCategoriesCompanion.insert(
                id: 'category',
                ownerId: ownerId,
                name: 'Words',
                normalizedName: 'words',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        await db
            .into(db.vocabularyWords)
            .insert(
              VocabularyWordsCompanion.insert(
                id: 'word-cat',
                ownerId: ownerId,
                categoryId: 'category',
                spelling: 'cat',
                normalizedSpelling: 'cat',
                meaning: 'แมว',
                normalizedMeaning: 'แมว',
                partOfSpeech: 'noun',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        session = await learning.startSourcePronunciationForWords(
          wordIds: ['word-cat'],
          limit: 1,
        );
      });
      final gateway = _LifecycleSpeechGateway();
      await _openSource(
        tester,
        results: results,
        learning: learning,
        gateway: gateway,
        ownerId: ownerId,
        sessionId: session.id,
        wordId: 'word-cat',
        contentRevision: session.questions.single.word.contentRevision,
      );
      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
      await _pumpUntilTest(tester, () => gateway.startCalls == 1);
      gateway.emit('CaT');
      await _pumpUntilTest(
        tester,
        () => find.byKey(const ValueKey('speech-error')).evaluate().isNotEmpty,
      );
      Future<Map<String, Object?>> snapshot() async => {
        'attempts': (await db.select(db.answerAttempts).get())
            .map((r) => r.toJson())
            .toList(),
        'srs': (await db.select(db.srsStates).get())
            .map((r) => r.toJson())
            .toList(),
        'xp': (await db.select(db.pointsLedgerEntries).get())
            .map((r) => r.toJson())
            .toList(),
        'coins': (await db.select(db.rewardTransactions).get())
            .map((r) => r.toJson())
            .toList(),
        'outbox': (await db.select(db.outboxOperations).get())
            .map((r) => r.toJson())
            .toList(),
      };
      final committed = await tester.runAsync(snapshot);
      expect(committed!['attempts'] as List, hasLength(1));
      expect(committed['srs'] as List, hasLength(1));
      expect(committed['xp'] as List, hasLength(1));
      expect(committed['coins'] as List, hasLength(1));
      final xp = await tester.runAsync(
        () => db.select(db.pointsLedgerEntries).getSingle(),
      );
      final coin = await tester.runAsync(
        () => db.select(db.rewardTransactions).getSingle(),
      );
      expect(xp!.amount, 1);
      expect(coin!.amount, 1);
      expect(coin.sourceEventId, repository.answers.single.id);
      expect(
        await tester.runAsync(() => db.select(db.researchConsents).get()),
        isEmpty,
      );
      expect(
        await tester.runAsync(() => db.select(db.eventsV2).get()),
        isEmpty,
      );
      expect(jsonEncode(committed), isNot(contains('CaT')));
      final operations = await tester.runAsync(
        () => db.select(db.outboxOperations).get(),
      );
      expect(operations!.where((r) => r.entityType == 'attempt'), hasLength(1));
      expect(operations.where((r) => r.entityType == 'srsState'), hasLength(1));
      expect(
        operations.where((r) => r.entityType == 'rewardTransaction'),
        isEmpty,
      );
      gateway.emit('contradictory raw transcript');
      final retry = find.byKey(const ValueKey('source-voice-retry-save'));
      await tester.scrollUntilVisible(retry, 200);
      await tester.tap(retry);
      await _pumpUntilTest(
        tester,
        () => find
            .byKey(const ValueKey('source-voice-saved'))
            .evaluate()
            .isNotEmpty,
      );
      expect(await tester.runAsync(snapshot), committed);
      expect(repository.answers, hasLength(2));
      expect(
        repository.answers.first.evidenceContext.evidenceClass.name,
        'pronunciation',
      );
      expect(
        repository.answers.first.evidenceContext.contentRevision,
        'local-vocabulary-v1:1',
      );
      expect(
        repository.answers.last.evidenceContext.toJson(),
        repository.answers.first.evidenceContext.toJson(),
      );
      expect(repository.answers.last.id, repository.answers.first.id);
      expect(
        repository.answers.last.occurredAtUtc,
        repository.answers.first.occurredAtUtc,
      );
      expect(
        repository.answers.last.responseTimeMs,
        repository.answers.first.responseTimeMs,
      );
      final finish = find.byKey(const ValueKey('source-voice-finish'));
      await tester.scrollUntilVisible(finish, 200);
      await tester.tap(finish);
      await _pumpUntilTest(
        tester,
        () => find.textContaining('ปิดการฝึกไม่สำเร็จ').evaluate().isNotEmpty,
      );
      final finished = await tester.runAsync(snapshot);
      expect(results, isEmpty);
      expect(finished!['attempts'], committed['attempts']);
      expect(finished['srs'], committed['srs']);
      expect(finished['xp'], committed['xp']);
      expect(finished['coins'], committed['coins']);
      final completed = await tester.runAsync(
        () => db.select(db.learningSessions).getSingle(),
      );
      expect(completed!.state, 'completed');
      expect(completed.correctCount, 1);
      expect(completed.wrongCount, 0);
      await tester.tap(finish);
      await _pumpUntilTest(
        tester,
        () => find.byType(SpeakToTextScreen).evaluate().isEmpty,
      );
      expect(await tester.runAsync(snapshot), finished);
      expect(
        (await tester.runAsync(
          () => db.select(db.learningSessions).getSingle(),
        ))!.endedAtUtcMs,
        completed.endedAtUtcMs,
      );
      expect(repository.answers, hasLength(2));
      expect(repository.finishCalls, 2);
      expect(results.single!.id, session.id);
      expect(results.single!.correctCount, 1);
      expect(results.single!.score, 100);
    },
  );

  for (final permission in [
    MediaPermissionState.denied,
    MediaPermissionState.permanentlyDenied,
    MediaPermissionState.unavailable,
  ]) {
    testWidgets(
      'source voice permission $permission cannot fabricate evidence',
      (tester) async {
        final repository = _RecordingLearningRepository();
        final gateway = _LifecycleSpeechGateway()..permission = permission;
        await _openSource(tester, repository: repository, gateway: gateway);
        await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
        await tester.pumpAndSettle();
        expect(gateway.startCalls, 0);
        expect(repository.answers, isEmpty);
        expect(find.byKey(const ValueKey('speech-error')), findsOneWidget);
        final error = find.byKey(const ValueKey('speech-error'));
        expect(
          find.ancestor(
            of: error,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.liveRegion == true,
            ),
          ),
          findsAtLeastNWidgets(1),
        );
        if (permission == MediaPermissionState.permanentlyDenied) {
          await tester.tap(find.text('เปิดศูนย์สิทธิ์อุปกรณ์'));
          await tester.pumpAndSettle();
          expect(find.byType(DevicePermissionCenterScreen), findsOneWidget);
          Navigator.of(
            tester.element(find.byType(DevicePermissionCenterScreen)),
          ).pop();
          await tester.pumpAndSettle();
        }
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('source-voice-finish')),
              )
              .onPressed,
          isNull,
        );
      },
    );
  }

  testWidgets('source noMatch empty cancel and late events never save', (
    tester,
  ) async {
    final gateway = _LifecycleSpeechGateway();
    final repository = _RecordingLearningRepository();
    await _openSource(tester, repository: repository, gateway: gateway);
    final mic = find.byKey(const ValueKey('speech-listen-button'));
    await tester.tap(mic);
    await tester.pumpAndSettle();
    gateway.emit(' ');
    await tester.pumpAndSettle();
    expect(repository.answers, isEmpty);
    expect(find.textContaining('ความเหมือนของข้อความ:'), findsNothing);
    await tester.tap(mic);
    await tester.pumpAndSettle();
    gateway.failure!(SpeechFailureCode.cancelled);
    await tester.pumpAndSettle();
    expect(repository.answers, isEmpty);
    await tester.tap(mic);
    await tester.pumpAndSettle();
    final old = gateway.onEvent!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    old(_event('cat'));
    await tester.pumpAndSettle();
    expect(repository.answers, isEmpty);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-voice-cancel')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('source-voice-cancel')));
    await tester.pumpAndSettle();
    old(_event('cat'));
    await tester.pumpAndSettle();
    expect(repository.answers, isEmpty);
    expect(repository.finishCalls, 0);
    expect(find.text('Synthetic source'), findsOneWidget);
  });

  for (final boundary in [
    'before-final',
    'save-await',
    'before-finish',
    'finish-await',
  ]) {
    testWidgets('source owner changes at $boundary fail closed', (
      tester,
    ) async {
      final owners = _Owners();
      final gateway = _LifecycleSpeechGateway();
      final repository = _RecordingLearningRepository();
      final gate = Completer<void>();
      if (boundary == 'save-await') repository.saveGate = gate;
      if (boundary == 'finish-await') repository.finishGate = gate;
      await _openSource(
        tester,
        repository: repository,
        owners: owners,
        gateway: gateway,
      );
      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
      await tester.pumpAndSettle();
      if (boundary == 'before-final') owners.ownerId = 'owner-b';
      gateway.emit('cat');
      if (boundary == 'save-await') {
        await _pumpUntilTest(tester, () => repository.answers.isNotEmpty);
      } else {
        await tester.pumpAndSettle();
      }
      if (boundary == 'save-await') {
        expect(repository.answers, hasLength(1));
        expect(repository.answers.single.ownerId, 'synthetic-owner');
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('speech-listen-button')),
              )
              .onPressed,
          isNull,
        );
        await tester.pageBack();
        await tester.pump();
        expect(find.byType(SpeakToTextScreen), findsOneWidget);
        owners.ownerId = 'owner-b';
        gate.complete();
        await tester.pumpAndSettle();
      }
      if (boundary.contains('finish')) {
        if (boundary == 'before-finish') owners.ownerId = 'owner-b';
        final finish = find.byKey(const ValueKey('source-voice-finish'));
        await tester.scrollUntilVisible(finish, 200);
        await tester.tap(finish);
        if (boundary == 'finish-await') {
          await _pumpUntilTest(tester, () => repository.finishCalls == 1);
        } else {
          await tester.pumpAndSettle();
        }
        if (boundary == 'finish-await') {
          expect(repository.finishCalls, 1);
          owners.ownerId = 'owner-b';
          gate.complete();
          await tester.pumpAndSettle();
        }
      }
      expect(find.byType(SpeakToTextScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('speech-error')),
        -200,
      );
      expect(find.textContaining('บัญชีผู้เรียนเปลี่ยน'), findsOneWidget);
      expect(find.byKey(const ValueKey('source-voice-saved')), findsNothing);
      expect(repository.answers.length, boundary == 'before-final' ? 0 : 1);
      expect(repository.finishCalls, boundary == 'finish-await' ? 1 : 0);
      owners.ownerId = 'synthetic-owner';
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('speech-listen-button')),
        200,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('speech-listen-button')),
            )
            .onPressed,
        isNull,
      );
    });
  }

  testWidgets(
    'source cleanup failure blocks mic save and cancel navigation honestly',
    (tester) async {
      final gateway = _LifecycleSpeechGateway();
      final voice = FakeVoiceProvider()
        ..stopError = StateError('synthetic TTS cleanup');
      final repository = _RecordingLearningRepository();
      await _openSource(
        tester,
        repository: repository,
        voice: voice,
        gateway: gateway,
      );
      final mic = find.byKey(const ValueKey('speech-listen-button'));
      await tester.tap(mic);
      await tester.pumpAndSettle();
      expect(gateway.startCalls, 0);
      expect(repository.answers, isEmpty);
      voice.stopError = null;
      await tester.tap(mic);
      await tester.pumpAndSettle();
      gateway.cancelError = StateError('synthetic mic cleanup');
      gateway.emit('cat');
      await tester.pumpAndSettle();
      expect(repository.answers, isEmpty);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('source-voice-cancel')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('source-voice-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(SpeakToTextScreen), findsOneWidget);
      gateway.cancelError = null;
      final retry = find.byKey(const ValueKey('source-voice-retry-save'));
      await tester.scrollUntilVisible(retry, -200);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(repository.answers, hasLength(1));
      expect(repository.finishCalls, 0);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('source-voice-cancel')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('source-voice-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(SpeakToTextScreen), findsNothing);
    },
  );

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    for (final brightness in Brightness.values) {
      testWidgets('source voice accessible 2x layout $size $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = _LifecycleSpeechGateway();
        await _openSource(
          tester,
          gateway: gateway,
          brightness: brightness,
          textScale: 2,
        );
        final mic = find.byKey(const ValueKey('speech-listen-button'));
        await tester.scrollUntilVisible(mic, 200);
        await tester.pumpAndSettle();
        expect(mic.hitTestable(), findsOneWidget);
        expect(tester.getSize(mic).height, greaterThanOrEqualTo(48));
        await tester.tap(mic);
        await tester.pumpAndSettle();
        gateway.emit('dog');
        await tester.pumpAndSettle();
        final finish = find.byKey(const ValueKey('source-voice-finish'));
        await tester.scrollUntilVisible(finish, 200);
        await tester.pumpAndSettle();
        expect(finish.hitTestable(), findsOneWidget);
        expect(tester.getSize(finish).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await tester.tap(finish);
        await tester.pumpAndSettle();
        expect(find.text('Synthetic source'), findsOneWidget);
      });
    }
  }
  for (final saved in [false, true]) {
    testWidgets('source leaving locks persistence actions saved=$saved', (
      tester,
    ) async {
      final repository = _RecordingLearningRepository()
        ..saveFailures = saved ? 0 : 1;
      final voice = FakeVoiceProvider();
      final gateway = _LifecycleSpeechGateway();
      await _openSource(
        tester,
        repository: repository,
        voice: voice,
        gateway: gateway,
      );
      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
      await tester.pumpAndSettle();
      gateway.emit('cat');
      await tester.pumpAndSettle();
      final stop = Completer<void>();
      voice.stopGate = stop;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('source-voice-cancel')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('source-voice-cancel')));
      await tester.pump();
      final persistence = find.byKey(
        ValueKey(saved ? 'source-voice-finish' : 'source-voice-retry-save'),
      );
      final button = tester.widget<ButtonStyleButton>(persistence);
      final disabled = button.onPressed == null;
      stop.complete();
      await tester.pumpAndSettle();
      expect(disabled, isTrue);
      expect(repository.answers, hasLength(1));
      expect(repository.finishCalls, 0);
    });
  }
  testWidgets(
    'source voice freezes failed save and explicitly retries finish',
    (tester) async {
      final repository = _RecordingLearningRepository()
        ..saveFailures = 1
        ..finishFailures = 1;
      final gateway = _LifecycleSpeechGateway();
      await _openSource(tester, repository: repository, gateway: gateway);
      expect(gateway.startCalls, 0);
      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
      await tester.pumpAndSettle();
      gateway.emit('cat');
      await tester.pumpAndSettle();
      expect(repository.answers, hasLength(1));
      expect(
        find.byKey(const ValueKey('source-voice-retry-save')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('speech-listen-button')),
            )
            .onPressed,
        isNull,
      );
      gateway.emit('dog');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('source-voice-retry-save')));
      await tester.pumpAndSettle();
      expect(repository.answers, hasLength(2));
      final first = repository.answers.first;
      final retry = repository.answers.last;
      expect(retry.id, first.id);
      expect(retry.occurredAtUtc, first.occurredAtUtc);
      expect(retry.responseTimeMs, first.responseTimeMs);
      expect(retry.isCorrect, first.isCorrect);
      expect(retry.providerProvenance, first.providerProvenance);
      expect(retry.promptMode, 'pronunciationTranscript');
      expect(first.isCorrect, isTrue);
      final finish = find.byKey(const ValueKey('source-voice-finish'));
      await tester.ensureVisible(finish);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(find.byType(SpeakToTextScreen), findsOneWidget);
      expect(find.textContaining('ปิดการฝึกไม่สำเร็จ'), findsOneWidget);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(find.byType(SpeakToTextScreen), findsNothing);
      expect(find.text('Synthetic source'), findsOneWidget);
      expect(repository.finishCalls, 2);
      expect(repository.answers, hasLength(2));
    },
  );

  testWidgets('source voice incorrect final can finish without Word Scramble', (
    tester,
  ) async {
    final repository = _RecordingLearningRepository();
    final gateway = _LifecycleSpeechGateway();
    await _openSource(tester, repository: repository, gateway: gateway);
    await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
    await tester.pumpAndSettle();
    gateway.emit('dog');
    await tester.pumpAndSettle();
    expect(repository.answers.single.isCorrect, isFalse);
    final finish = find.byKey(const ValueKey('source-voice-finish'));
    expect(finish, findsOneWidget);
    await tester.ensureVisible(finish);
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(find.byType(SpeakToTextScreen), findsNothing);
    expect(find.text('ไปเกมเรียงคำ'), findsNothing);
    expect(repository.finishCalls, 1);
  });

  testWidgets('source voice stops TTS before microphone permission', (
    tester,
  ) async {
    final log = <String>[];
    final voice = FakeVoiceProvider()..log = log;
    final gateway = _LifecycleSpeechGateway()..log = log;
    await _openSource(tester, gateway: gateway, voice: voice);
    await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
    await tester.pumpAndSettle();
    expect(log, containsAllInOrder(['stop-tts', 'permission', 'start-stt']));
  });

  testWidgets('source voice rejects owner change during TTS stop', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final stop = Completer<void>();
      final voice = FakeVoiceProvider()..stopGate = stop;
      final owners = _Owners();
      final gateway = _LifecycleSpeechGateway();
      await _openSource(tester, owners: owners, gateway: gateway, voice: voice);
      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
      await tester.pump();
      owners.ownerId = 'owner-b';
      stop.complete();
      await tester.pumpAndSettle();
      expect(gateway.startCalls, 0);
      expect(find.textContaining('บัญชีผู้เรียนเปลี่ยน'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('ฟังการออกเสียงคำว่า cat')),
        findsNothing,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'SpeakToTextScreen automatically speaks word on start using VoiceProvider',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: SpeakToTextScreen(
            correctWord: 'apple',
            voice: VoiceUseCases(fakeVoice),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeVoice.spokenRequests.length, 1);
      final req = fakeVoice.spokenRequests.first;
      expect(req.text, 'apple');
      expect(req.language, 'en');
      expect(req.mode, VoiceMode.practice);
      expect(req.contentId, 'apple');
      expect(req.contentType, 'vocabulary_word');
    },
  );

  testWidgets('Tapping audio button replays speech via VoiceProvider', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'banana',
          voice: VoiceUseCases(fakeVoice),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fakeVoice.spokenRequests.length, 1);

    // Find and tap speaker / audio replay button
    final speakerFinder = find.byIcon(Icons.volume_up);
    expect(speakerFinder, findsOneWidget);

    await tester.tap(speakerFinder);
    await tester.pumpAndSettle();

    expect(fakeVoice.spokenRequests.length, 2);
    expect(fakeVoice.spokenRequests[1].text, 'banana');
  });

  testWidgets('Disposing SpeakToTextScreen calls stop on VoiceProvider', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: VoiceUseCases(fakeVoice),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Replace widget to trigger dispose
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(fakeVoice.stopCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('cancels microphone when app leaves foreground', (tester) async {
    final gateway = _LifecycleSpeechGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: VoiceUseCases(FakeVoiceProvider()),
          speechPractice: SpeechPracticeUseCases(gateway),
        ),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();

    expect(gateway.cancelCalls, 1);
  });

  testWidgets(
    'pending startup locks the button and late cancellation does not replace current UI',
    (tester) async {
      final permission = Completer<void>();
      final gateway = _LifecycleSpeechGateway()..permissionGate = permission;
      await tester.pumpWidget(
        MaterialApp(
          home: SpeakToTextScreen(
            correctWord: 'cat',
            voice: VoiceUseCases(FakeVoiceProvider()),
            speechPractice: SpeechPracticeUseCases(gateway),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('speech-listen-button'));
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      permission.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(find.text('ยกเลิกการฟังแล้ว'), findsNothing);
      expect(gateway.startCalls, 0);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(gateway.startCalls, 1);
      gateway.emit('cat');
      await tester.pumpAndSettle();
      expect(find.text('ความเหมือนของข้อความ: 100%'), findsOneWidget);
      expect(find.textContaining('วิธีประเมิน:'), findsOneWidget);
      expect(
        find.textContaining('เปรียบเทียบข้อความที่ระบบได้ยิน'),
        findsOneWidget,
      );
      expect(find.textContaining('transcript-edit-distance-v1'), findsNothing);
      expect(
        find.textContaining('ยังไม่ได้วัดระดับเสียงหรือหน่วยเสียง'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'blank target reports noMatch without a score or unhandled callback',
    (tester) async {
      final gateway = _LifecycleSpeechGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: SpeakToTextScreen(
            correctWord: '',
            voice: VoiceUseCases(FakeVoiceProvider()),
            speechPractice: SpeechPracticeUseCases(gateway),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
      await tester.pumpAndSettle();
      gateway.emit('cat');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text('ไม่ได้ยินคำพูดที่ชัดเจน กรุณาลองอีกครั้ง'),
        findsOneWidget,
      );
      expect(find.textContaining('ความเหมือนของข้อความ:'), findsNothing);
    },
  );

  testWidgets(
    'screen exit cancels but keeps shared speech usable and rejects late callbacks',
    (tester) async {
      final gateway = _LifecycleSpeechGateway();
      final speech = SpeechPracticeUseCases(gateway);
      Widget screen() => MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: VoiceUseCases(FakeVoiceProvider()),
          speechPractice: speech,
        ),
      );
      await tester.pumpWidget(screen());
      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
      await tester.pumpAndSettle();
      final oldCallback = gateway.onEvent!;
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(screen());
      await tester.tap(find.byKey(const ValueKey('speech-listen-button')));
      await tester.pumpAndSettle();
      oldCallback(_event('stale'));
      gateway.emit('cat');
      gateway.emit('duplicate');
      await tester.pumpAndSettle();
      expect(find.text('cat'), findsNWidgets(2));
      expect(find.text('stale'), findsNothing);
      expect(find.text('duplicate'), findsNothing);
      expect(find.text('ความเหมือนของข้อความ: 100%'), findsOneWidget);
    },
  );

  testWidgets(
    'empty and cancelled final never record; explicit stop records once with provenance',
    (tester) async {
      final gateway = _LifecycleSpeechGateway();
      final repository = _RecordingLearningRepository();
      var id = 0;
      final learning = LearningUseCases(
        owners: _Owners(),
        repository: repository,
        generateId: () => 'synthetic-${++id}',
        nowUtc: () => DateTime.utc(2026, 10, 21),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'M1a'),
      );
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: AppDependencies(
            runtimeStatus: const AppRuntimeStatus(
              localData: RuntimeAvailability.ready,
              firebase: RuntimeAvailability.unavailable,
              supabase: RuntimeAvailability.unavailable,
              backends: RuntimeAvailability.unavailable,
            ),
            config: null,
            guestSessionService: _Guest(),
            learning: learning,
          ),
          child: MaterialApp(
            home: SpeakToTextScreen(
              correctWord: 'cat',
              sessionId: 'synthetic-session',
              wordId: 'synthetic-word',
              voice: VoiceUseCases(FakeVoiceProvider()),
              speechPractice: SpeechPracticeUseCases(gateway),
            ),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('speech-listen-button'));
      await tester.tap(button);
      await tester.pumpAndSettle();
      gateway.onEvent!(_event('dog', isFinal: false));
      await tester.pumpAndSettle();
      expect(find.text('ความเหมือนของข้อความ: 0%'), findsOneWidget);
      gateway.emit(' ');
      await tester.pumpAndSettle();
      expect(repository.answers, isEmpty);
      expect(find.textContaining('ความเหมือนของข้อความ:'), findsNothing);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final cancelled = gateway.onEvent!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      cancelled(_event('cat'));
      await tester.pumpAndSettle();
      expect(repository.answers, isEmpty);
      await tester.tap(button);
      await tester.pumpAndSettle();
      gateway.emitOnStop = true;
      await tester.tap(button);
      await tester.pumpAndSettle();
      gateway.emit('cat');
      await tester.pumpAndSettle();
      expect(repository.answers, hasLength(1));
      expect(repository.answers.single.isCorrect, isTrue);
      expect(
        repository.answers.single.providerProvenance,
        'synthetic-stt|en-US|transcript-edit-distance-v1',
      );
      expect(repository.answers.single.promptMode, 'pronunciationTranscript');
    },
  );

  testWidgets('final before start returns keeps the next recording available', (
    tester,
  ) async {
    final gateway = _LifecycleSpeechGateway()..emitDuringStart = true;
    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: VoiceUseCases(FakeVoiceProvider()),
          speechPractice: SpeechPracticeUseCases(gateway),
        ),
      ),
    );
    final button = find.byKey(const ValueKey('speech-listen-button'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(gateway.isListening, isTrue);
    expect(find.text('เริ่มพูด'), findsOneWidget);
    expect(find.text('หยุดฟัง'), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(gateway.startCalls, 2);
  });
}

SpeechRecognitionEvent _event(String text, {bool isFinal = true}) =>
    SpeechRecognitionEvent(
      transcript: text,
      isFinal: isFinal,
      recognizedAtUtc: DateTime.utc(2026, 10, 21),
      engine: 'synthetic-stt',
      locale: 'en-US',
    );

final class _LifecycleSpeechGateway implements SpeechRecognitionGateway {
  int cancelCalls = 0;
  int startCalls = 0;
  bool emitOnStop = false;
  bool emitDuringStart = false;
  Completer<void>? permissionGate;
  SpeechEventCallback? onEvent;
  List<String>? log;
  MediaPermissionState permission = MediaPermissionState.granted;
  SpeechFailureCallback? failure;
  Object? cancelError;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    isListening = false;
    if (cancelError != null) throw cancelError!;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    failure = onFailure;
  }

  @override
  Future<MediaPermissionState> requestPermission() async {
    log?.add('permission');
    await permissionGate?.future;
    return permission;
  }

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    startCalls += 1;
    log?.add('start-stt');
    isListening = true;
    this.onEvent = onEvent;
    if (emitDuringStart) emit('cat');
  }

  void emit(String text) => onEvent!(_event(text));

  @override
  Future<void> stop() async {
    if (emitOnStop) emit('cat');
    isListening = false;
  }
}

final class _Owners implements LocalOwnerRepository {
  String ownerId = 'synthetic-owner';
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: ownerId, createdAtUtc: DateTime.utc(2026));
  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-guest');
}

final class _RecordingLearningRepository implements LearningRepository {
  final answers = <RecordAnswerCommand>[];
  int saveFailures = 0;
  int finishFailures = 0;
  int finishCalls = 0;
  Completer<void>? saveGate;
  Completer<void>? finishGate;
  LearningSessionSummary? summary;
  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    answers.add(command);
    await saveGate?.future;
    if (saveFailures > 0) {
      saveFailures--;
      throw StateError('synthetic lost acknowledgement');
    }
    return const AnswerRecordResult(
      inserted: true,
      srs: SrsSnapshot(
        intervalDays: 1,
        repetitions: 1,
        lapses: 0,
        stability: 1,
        difficulty: 1,
        lastReviewAtUtc: null,
        dueAtUtc: null,
        algorithmVersion: 1,
      ),
    );
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    finishCalls++;
    await finishGate?.future;
    if (finishFailures > 0) {
      finishFailures--;
      throw StateError('synthetic finish failure');
    }
    return summary ??
        LearningSessionSummary(
          id: sessionId,
          state: 'completed',
          correctCount: answers.last.isCorrect ? 1 : 0,
          wrongCount: answers.last.isCorrect ? 0 : 1,
          score: answers.last.isCorrect ? 100 : 0,
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _openSource(
  WidgetTester tester, {
  _RecordingLearningRepository? repository,
  _Owners? owners,
  _LifecycleSpeechGateway? gateway,
  FakeVoiceProvider? voice,
  LearningUseCases? learning,
  String ownerId = 'synthetic-owner',
  String sessionId = 'synthetic-session',
  String wordId = 'synthetic-word',
  String? contentRevision,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  List<LearningSessionSummary?>? results,
}) async {
  var id = 0;
  final authority =
      learning ??
      LearningUseCases(
        owners: owners ?? _Owners(),
        repository: repository ?? _RecordingLearningRepository(),
        generateId: () => 'source-${++id}',
        nowUtc: () => DateTime.utc(2026, 10, 23),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'I4d'),
      );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              const Text('Synthetic source'),
              TextButton(
                onPressed: () async {
                  final result = await Navigator.of(context)
                      .push<LearningSessionSummary>(
                        MaterialPageRoute<LearningSessionSummary>(
                          builder: (_) => SpeakToTextScreen(
                            correctWord: 'cat',
                            sourceOwnerId: ownerId,
                            sessionId: sessionId,
                            wordId: wordId,
                            contentRevision: contentRevision,
                            learning: authority,
                            voice: VoiceUseCases(voice ?? FakeVoiceProvider()),
                            speechPractice: SpeechPracticeUseCases(
                              gateway ?? _LifecycleSpeechGateway(),
                            ),
                          ),
                        ),
                      );
                  results?.add(result);
                },
                child: const Text('Open source voice'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open source voice'));
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilTest(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Source speech did not reach the expected local state');
}

final class _LostAckRepository implements LearningRepository {
  _LostAckRepository(this.delegate);
  final LearningRepository delegate;
  final answers = <RecordAnswerCommand>[];
  int finishCalls = 0;
  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    answers.add(command);
    final result = await delegate.recordAnswer(command);
    if (answers.length == 1) throw StateError('synthetic post-commit lost ack');
    return result;
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    finishCalls++;
    final result = await delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
    if (finishCalls == 1) throw StateError('synthetic post-finish lost ack');
    return result;
  }

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    wordIds: wordIds,
    limit: limit,
  );
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
