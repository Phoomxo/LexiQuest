import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
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

void main() {
  testWidgets('permanent microphone denial is announced and opens recovery', (
    tester,
  ) async {
    final gateway = _FakeSpeechGateway()
      ..permission = MediaPermissionState.permanentlyDenied;
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Keep going',
          voice: VoiceUseCases(_FakeVoice()),
          speechPractice: SpeechPracticeUseCases(gateway),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pumpAndSettle();

    final error = find.byKey(const ValueKey('shadowing-error'));
    expect(error, findsOneWidget);
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
    await tester.tap(find.text('เปิดศูนย์สิทธิ์อุปกรณ์'));
    await tester.pumpAndSettle();
    expect(find.byType(DevicePermissionCenterScreen), findsOneWidget);
  });

  testWidgets('uses real transcript provenance and never fabricates pitch', (
    tester,
  ) async {
    final voice = _FakeVoice();
    final speech = SpeechPracticeUseCases(_FakeSpeechGateway());
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Practice makes perfect',
          voice: VoiceUseCases(voice),
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
      find.textContaining('ยังไม่ได้วัดระดับเสียงหรือหน่วยเสียง'),
      findsOneWidget,
    );
    expect(
      find.text('เกณฑ์บันทึกคำตอบถูก: ความเหมือนของข้อความอย่างน้อย 80%'),
      findsOneWidget,
    );
    expect(find.textContaining('วิธีคำนวณรุ่น'), findsNothing);
    expect(
      find.text('ใช้ระบบรู้จำเสียงของอุปกรณ์ · ภาษาอังกฤษ (สหรัฐฯ)'),
      findsOneWidget,
    );
    expect(find.textContaining('synthetic-stt'), findsNothing);
    expect(find.textContaining('en-US'), findsNothing);
  });

  testWidgets('cancels microphone when app leaves foreground', (tester) async {
    final gateway = _FakeSpeechGateway();
    final speech = SpeechPracticeUseCases(gateway);
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Keep going',
          voice: VoiceUseCases(_FakeVoice()),
          speechPractice: speech,
        ),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(gateway.cancelCalls, 1);
  });

  testWidgets(
    'pending startup locks the button and background cancellation leaves no stale error',
    (tester) async {
      final permission = Completer<void>();
      final gateway = _FakeSpeechGateway()
        ..permissionGate = permission
        ..emitResult = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'cat',
            voice: VoiceUseCases(_FakeVoice()),
            speechPractice: SpeechPracticeUseCases(gateway),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('shadowing-listen-button'));
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      permission.complete();
      await tester.pumpAndSettle();
      expect(find.text('ยกเลิกการฟังแล้ว'), findsNothing);
      expect(gateway.startCalls, 0);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(gateway.startCalls, 1);
    },
  );

  testWidgets(
    'blank target reports unavailable without an unhandled assessment',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: '',
            voice: VoiceUseCases(_FakeVoice()),
            speechPractice: SpeechPracticeUseCases(_FakeSpeechGateway()),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ไม่ได้ยินเสียงพูดที่ชัดเจน'), findsOneWidget);
      expect(find.textContaining('ความเหมือนของข้อความ:'), findsNothing);
    },
  );

  testWidgets(
    'silence and cancelled final write nothing; stop records one valid final with provenance',
    (tester) async {
      final gateway = _FakeSpeechGateway()..emitResult = false;
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
        MaterialApp(
          home: ShadowingChallengeScreen(
            voice: VoiceUseCases(_FakeVoice()),
            speechPractice: SpeechPracticeUseCases(gateway),
            learning: learning,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('shadowing-listen-button'));
      await tester.tap(button);
      await tester.pumpAndSettle();
      gateway.onEvent!(_event('dog', isFinal: false));
      await tester.pumpAndSettle();
      expect(find.textContaining('ความเหมือนของข้อความ: 0%'), findsOneWidget);
      gateway.emit(' ');
      await tester.pumpAndSettle();
      expect(repository.answers, isEmpty);
      expect(find.textContaining('ความเหมือนของข้อความ:'), findsNothing);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final cancelledCallback = gateway.onEvent!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      cancelledCallback(_event('cat'));
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
      expect(repository.answers.single.promptMode, 'shadowing');
      expect(
        repository.answers.single.providerProvenance,
        'synthetic-stt:en-US:transcript-similarity-v1',
      );
      expect(repository.finishes, 1);
    },
  );

  testWidgets(
    'final during start does not restore a completed listening state',
    (tester) async {
      final gateway = _FakeSpeechGateway()..leaveListeningAfterFinal = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ShadowingChallengeScreen(
            referenceSentence: 'Practice makes perfect',
            voice: VoiceUseCases(_FakeVoice()),
            speechPractice: SpeechPracticeUseCases(gateway),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('shadowing-listen-button'));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(gateway.isListening, isTrue);
      expect(find.text('พูดตามประโยค'), findsOneWidget);
      expect(find.text('หยุดบันทึก'), findsNothing);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(gateway.startCalls, 2);
    },
  );

  for (final size in const [Size(360, 800), Size(800, 360)]) {
    testWidgets('route title stays readable with Back at 2x on $size', (
      tester,
    ) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ShadowingChallengeScreen(
                      referenceSentence: 'Practice makes perfect',
                      voice: VoiceUseCases(_FakeVoice()),
                      speechPractice: SpeechPracticeUseCases(
                        _FakeSpeechGateway(),
                      ),
                    ),
                  ),
                ),
                child: const Text('เปิดฝึกพูดตามเสียง'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('เปิดฝึกพูดตามเสียง'));
      await tester.pumpAndSettle();

      expect(find.byType(BackButton), findsOneWidget);
      final title = find.text('ฝึกพูดตามเสียง');
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
      );
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 96);
      expect(tester.takeException(), isNull);
    });
  }
}

SpeechRecognitionEvent _event(String text, {bool isFinal = true}) =>
    SpeechRecognitionEvent(
      transcript: text,
      isFinal: isFinal,
      recognizedAtUtc: DateTime.utc(2026, 10, 21),
      engine: 'synthetic-stt',
      locale: 'en-US',
    );

final class _Owners implements LocalOwnerRepository {
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: 'synthetic-owner', createdAtUtc: DateTime.utc(2026));
  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _RecordingLearningRepository implements LearningRepository {
  final answers = <RecordAnswerCommand>[];
  int finishes = 0;
  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    required int limit,
  }) async => const [
    QuizWord(
      id: 'synthetic-word',
      categoryId: 'synthetic-category',
      spelling: 'cat',
      meaning: 'แมว',
      partOfSpeech: 'noun',
    ),
  ];
  @override
  Future<void> startSession(LearningSessionDraft session) async {}
  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    answers.add(command);
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
    finishes += 1;
    return LearningSessionSummary(
      id: sessionId,
      state: 'completed',
      correctCount: 1,
      wrongCount: 0,
      score: 100,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeSpeechGateway implements SpeechRecognitionGateway {
  int cancelCalls = 0;
  int startCalls = 0;
  bool emitResult = true;
  bool emitOnStop = false;
  bool leaveListeningAfterFinal = false;
  Completer<void>? permissionGate;
  MediaPermissionState permission = MediaPermissionState.granted;
  SpeechEventCallback? onEvent;
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
  Future<MediaPermissionState> requestPermission() async {
    await permissionGate?.future;
    return permission;
  }

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    startCalls += 1;
    this.onEvent = onEvent;
    isListening = true;
    if (!emitResult) return;
    onEvent(
      SpeechRecognitionEvent(
        transcript: 'Practice makes perfect',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 7, 30),
        engine: 'device-stt',
        locale: locale,
      ),
    );
    if (!leaveListeningAfterFinal) isListening = false;
  }

  @override
  Future<void> stop() async {
    if (emitOnStop) emit('cat');
    isListening = false;
  }

  void emit(String text) => onEvent!(_event(text));
}

final class _FakeVoice implements VoiceProvider {
  final List<VoiceRequest> requests = [];

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
  Future<void> stop() async {}
}
