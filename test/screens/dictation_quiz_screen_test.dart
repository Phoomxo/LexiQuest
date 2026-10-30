import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/native_tts_provider.dart';
import 'package:vocab_learning_app/voice/voice_audio_player.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import 'package:vocab_learning_app/voice/voice_service_factory.dart';

import '../support/dictation_session_harness.dart';

class FakeVoiceProvider implements VoiceProvider {
  final spokenRequests = <VoiceRequest>[];
  int stopCalls = 0;
  bool fail = false;
  Completer<void>? stopGate;
  Completer<void>? speakGate;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
    await speakGate?.future;
    if (fail) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.playback,
        message: 'Synthetic playback failure',
      );
    }
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: true,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await stopGate?.future;
  }
}

void main() {
  testWidgets('actual started target automatically requests normal playback', (
    tester,
  ) async {
    final f = await _Fixture.open(tester);
    try {
      await _mount(tester, f);
      final request = f.voice.spokenRequests.single;
      expect(request.text, f.session.word.spelling);
      expect(request.speed, 1.0);
      expect(request.mode, VoiceMode.practice);
      expect(request.contentType, 'dictation_quiz');
      expect(request.contentId, isNot(f.session.word.spelling));
      expect(await f.count(tester, 'learning_sessions'), 1);
      expect(await f.count(tester, 'answer_attempts'), 0);
      expect(find.byKey(const ValueKey('dictation-feedback')), findsNothing);
    } finally {
      await f.close(tester);
    }
  });

  testWidgets('failed slow playback remains assisted after normal replay', (
    tester,
  ) async {
    final f = await _Fixture.open(tester);
    try {
      await _mount(tester, f);
      f.voice.fail = true;
      await tester.tap(find.byKey(const ValueKey('dictation-slow')));
      await _until(tester, () => f.voice.spokenRequests.length == 2);
      expect(f.voice.spokenRequests.last.speed, .75);
      await tester.pump();
      f.voice.fail = false;
      await tester.tap(find.byKey(const ValueKey('dictation-normal')));
      await _ready(tester);
      await _save(tester, f.session.word.spelling);
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('dictation-feedback'))
            .evaluate()
            .isNotEmpty,
      );
      final command = f.repository.answers.single;
      expect(command.evidenceContext.evidenceClass.name, 'guidedPractice');
      expect(command.evidenceContext.hintLevel, 1);
      expect(await f.count(tester, 'srs_states'), 0);
      expect(await f.count(tester, 'points_ledger_entries'), 0);
    } finally {
      await f.close(tester);
    }
  });

  testWidgets('feedback and explicit completion follow actual saved ACKs', (
    tester,
  ) async {
    final f = await _Fixture.open(tester);
    try {
      await _mount(tester, f);
      f.repository.answerGate = Completer<void>();
      await _save(tester, '  ${f.session.word.spelling.toUpperCase()}  ');
      await _until(tester, () => f.repository.answers.isNotEmpty);
      expect(find.byKey(const ValueKey('dictation-feedback')), findsNothing);
      expect(await f.count(tester, 'answer_attempts'), 0);
      f.repository.answerGate!.complete();
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('dictation-finish'))
            .evaluate()
            .isNotEmpty,
      );
      expect(await f.count(tester, 'answer_attempts'), 1);
      expect(f.summary, isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('dictation-finish')),
      );
      await tester.tap(find.byKey(const ValueKey('dictation-finish')));
      await _until(tester, () => f.summary != null);
      expect(f.summary!.state, 'completed');
      expect(f.summary!.correctCount, 1);
      expect(f.summary!.wrongCount, 0);
      expect(f.summary!.score, 100);
      expect(await f.count(tester, 'points_ledger_entries'), 0);
    } finally {
      await f.close(tester);
    }
  });

  testWidgets('failed audio cannot silently score a text-only response', (
    tester,
  ) async {
    final f = await _Fixture.open(tester);
    try {
      f.voice.fail = true;
      await _mount(tester, f, ready: false);
      await _until(tester, () => f.voice.spokenRequests.isNotEmpty);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('dictation-save')))
            .onPressed,
        isNull,
      );
      expect(await f.count(tester, 'answer_attempts'), 0);
      expect(find.byKey(const ValueKey('dictation-feedback')), findsNothing);
    } finally {
      await f.close(tester);
    }
  });

  testWidgets(
    'finish retries after clock recovery without capturing invalid time',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        await _save(tester, f.session.word.spelling);
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('dictation-finish'))
              .evaluate()
              .isNotEmpty,
        );
        final answer = f.repository.answers.single;
        f.h.now = answer.occurredAtUtc.subtract(const Duration(seconds: 1));
        await tester.ensureVisible(
          find.byKey(const ValueKey('dictation-finish')),
        );
        await tester.tap(find.byKey(const ValueKey('dictation-finish')));
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('dictation-retry'))
              .evaluate()
              .isNotEmpty,
        );
        expect(f.repository.finishes, isEmpty);
        expect(f.summary, isNull);
        final stillActive = (await tester.runAsync(
          () => f.h.storage.session(f.session.id),
        ))!;
        expect(stillActive['state'], 'active');
        expect(stillActive['ended_at_utc_ms'], isNull);

        final recoveredTime = answer.occurredAtUtc.add(
          const Duration(minutes: 1),
        );
        f.h.now = recoveredTime;
        await tester.tap(find.byKey(const ValueKey('dictation-retry')));
        await _until(tester, () => f.summary != null);
        expect(f.repository.finishes, hasLength(1));
        final close = f.repository.finishes.single;
        expect(identical(close.answer, answer), isTrue);
        expect(close.endedAtUtc, recoveredTime);
        expect(f.summary!.state, 'completed');
        final completed = (await tester.runAsync(
          () => f.h.storage.session(f.session.id),
        ))!;
        expect(completed['state'], 'completed');
        expect(
          completed['ended_at_utc_ms'],
          recoveredTime.millisecondsSinceEpoch,
        );
        expect(await f.count(tester, 'learning_sessions'), 1);
        expect(await f.count(tester, 'answer_attempts'), 1);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets('lost start answer and finish ACKs reuse original identities', (
    tester,
  ) async {
    final f = await _Fixture.open(tester);
    try {
      f.repository.loseStart = true;
      await _mount(tester, f, ready: false);
      await _until(
        tester,
        () =>
            find.byKey(const ValueKey('dictation-retry')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('dictation-retry')));
      await _ready(tester);
      expect(f.repository.starts.length, 2);
      expect(
        identical(f.repository.starts.first, f.repository.starts.last),
        isTrue,
      );
      f.repository.loseAnswer = true;
      await _save(tester, 'wrong synthetic response');
      await _until(
        tester,
        () =>
            find.byKey(const ValueKey('dictation-retry')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('dictation-retry')));
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('dictation-finish'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        identical(f.repository.answers.first, f.repository.answers.last),
        isTrue,
      );
      f.repository.loseFinish = true;
      await tester.ensureVisible(
        find.byKey(const ValueKey('dictation-finish')),
      );
      await tester.tap(find.byKey(const ValueKey('dictation-finish')));
      await _until(
        tester,
        () =>
            find.byKey(const ValueKey('dictation-retry')).evaluate().isNotEmpty,
      );
      f.h.now = f.h.now.add(const Duration(minutes: 2));
      await tester.tap(find.byKey(const ValueKey('dictation-retry')));
      await _until(tester, () => f.summary != null);
      expect(
        identical(f.repository.finishes.first, f.repository.finishes.last),
        isTrue,
      );
      expect(f.summary!.wrongCount, 1);
      expect(await f.count(tester, 'answer_attempts'), 1);
      expect(await f.count(tester, 'learning_sessions'), 1);
      expect(
        (await tester.runAsync(
          () => f.h.storage.session(f.session.id),
        ))!['ended_at_utc_ms'],
        f.repository.finishes.first.endedAtUtc.millisecondsSinceEpoch,
      );
    } finally {
      await f.close(tester);
    }
  });

  testWidgets(
    'answer freezes before delayed audio stop and IME cannot duplicate',
    (tester) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        f.voice.stopGate = Completer<void>();
        final captured = f.h.now;
        await _save(tester, f.session.word.spelling);
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('dictation-response')),
              )
              .enabled,
          isFalse,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('dictation-slow')),
              )
              .onPressed,
          isNull,
        );
        f.h.now = f.h.now.add(const Duration(seconds: 4));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        f.voice.stopGate!.complete();
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('dictation-feedback'))
              .evaluate()
              .isNotEmpty,
        );
        expect(f.repository.answers, hasLength(1));
        expect(f.repository.answers.single.occurredAtUtc, captured);
        expect(await f.count(tester, 'answer_attempts'), 1);
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final invalidation in [
    'owner ABA',
    'owner error',
    'owner done',
    'covered',
    'paused',
    'disposed',
  ]) {
    testWidgets('pending actual answer is suppressed after $invalidation', (
      tester,
    ) async {
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f);
        f.repository.answerGate = Completer<void>();
        await _save(tester, f.session.word.spelling);
        await _until(tester, () => f.repository.answers.isNotEmpty);
        switch (invalidation) {
          case 'owner ABA':
            await tester.runAsync(
              () => f.h.storage.switchOwner(configuredOtherOwnerId),
            );
            f.owners.add(configuredOtherOwnerId);
            await tester.runAsync(
              () => f.h.storage.switchOwner(configuredOwnerId),
            );
            f.owners.add(configuredOwnerId);
          case 'owner error':
            f.owners.addError(StateError('synthetic owner error'));
          case 'owner done':
            unawaited(f.owners.close());
          case 'covered':
            unawaited(
              f.navigator.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Other activity')),
                ),
              ),
            );
          case 'paused':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.hidden,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            expect(tester.binding.lifecycleState, AppLifecycleState.paused);
            expect(tester.binding.framesEnabled, isFalse);
            tester.binding.scheduleForcedFrame();
          case 'disposed':
            await tester.pumpWidget(const SizedBox.shrink());
        }
        await tester.pump();
        f.repository.answerGate!.complete();
        await tester.runAsync(f.repository.settle);
        if (invalidation == 'paused') {
          tester.binding.scheduleForcedFrame();
        }
        await tester.pump();
        expect(
          await tester.runAsync(() => f.h.storage.count('answer_attempts')),
          0,
        );
        expect(f.summary, isNull);
        expect(find.byKey(const ValueKey('dictation-feedback')), findsNothing);
        if (invalidation != 'covered') {
          expect(
            find.byKey(const ValueKey('dictation-response')),
            findsNothing,
          );
        }
        expect(f.voice.stopCalls, greaterThan(0));
      } finally {
        await f.close(tester);
      }
    });
  }

  testWidgets(
    'shared managed voice remains usable after the screen is disposed',
    (tester) async {
      final f = await _Fixture.open(tester);
      final audio = _LifecycleAudio();
      final native = _LifecycleTts();
      final service = VoiceServiceFactory.create(
        nativeTtsAdapter: native,
        audioPlayerAdapter: audio,
      );
      try {
        await _mount(tester, f, voiceOverride: VoiceUseCases(service));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(audio.disposals, 0);
        final result = await service.speak(
          VoiceRequest.create(
            text: 'synthetic',
            language: 'en',
            voiceId: 'teacher_female',
            speed: 1,
            mode: VoiceMode.practice,
            contentId: 'synthetic-lifecycle',
            contentType: 'word',
          ),
        );
        expect(result.actualEngine, VoiceEngine.nativeTts);
        expect(native.stops, greaterThan(0));
      } finally {
        await service.dispose();
        expect(audio.disposals, 1);
        await f.close(tester);
      }
    },
  );

  testWidgets('default owned voice stops on screen removal', (tester) async {
    const channel = MethodChannel('flutter_tts');
    final methods = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      methods.add(call.method);
      return 1;
    });
    final f = await _Fixture.open(tester);
    try {
      await _mount(tester, f, useDefaultVoice: true);
      final before = methods.where((method) => method == 'stop').length;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _until(
        tester,
        () => methods.where((method) => method == 'stop').length > before,
      );
      expect(methods, contains('speak'));
    } finally {
      await f.close(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    }
  });

  testWidgets('replacement speech survives the old Dictation screen disposal', (
    tester,
  ) async {
    final f = await _Fixture.open(tester);
    final native = _LifecycleTts()
      ..heldText = 'synthetic replacement speech'
      ..speakStarted = Completer<void>()
      ..speakGate = Completer<void>();
    final audio = _LifecycleAudio();
    final service = VoiceServiceFactory.create(
      nativeTtsAdapter: native,
      audioPlayerAdapter: audio,
    );
    final voice = VoiceUseCases(service);
    final nextAllowed = Completer<void>();
    Object? nextResult;
    try {
      await _mount(tester, f, voiceOverride: voice);
      final initialStops = native.stops;
      unawaited(
        f.navigator.currentState!.pushReplacement<void, void>(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(seconds: 10),
            pageBuilder: (_, _, _) => _ReplacementSpeaker(
              voice: voice,
              allowed: nextAllowed.future,
              onResult: (value) => nextResult = value,
            ),
          ),
        ),
      );
      await tester.pump();
      await _until(tester, () => native.stops > initialStops);
      nextAllowed.complete();
      await _until(tester, () => native.speakStarted!.isCompleted);
      expect(
        find.byType(DictationQuizScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(native.active, native.heldText);
      final stopsBeforeOldDispose = native.stops;
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();
      expect(
        find.byType(DictationQuizScreen, skipOffstage: false),
        findsNothing,
      );
      expect(native.stops, stopsBeforeOldDispose);
      expect(native.active, native.heldText);
      native.speakGate!.complete();
      await _until(tester, () => nextResult != null);
      expect(nextResult, isA<VoicePlaybackResult>());
      expect(audio.disposals, 0);
    } finally {
      if (!nextAllowed.isCompleted) nextAllowed.complete();
      if (!native.speakGate!.isCompleted) native.speakGate!.complete();
      await f.close(tester);
      await tester.runAsync(service.dispose);
    }
  });

  testWidgets(
    'English 200 percent narrow keyboard flow reaches save and finish',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await _Fixture.open(tester);
      try {
        await _mount(tester, f, language: 'en', scale: 2);
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        await _save(tester, f.session.word.spelling);
        await _until(tester, () => f.repository.answers.isNotEmpty);
        await tester.runAsync(f.repository.settle);
        await tester.pump();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('dictation-finish')),
          120,
          scrollable: find.byType(Scrollable).last,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('dictation-finish')),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(const ValueKey('dictation-finish')));
        await _until(tester, () => f.summary != null);
        expect(tester.takeException(), isNull);
      } finally {
        tester.view.resetViewInsets();
        await f.close(tester);
      }
    },
  );
}

final class _Fixture {
  _Fixture(this.h, this.repository, this.learning, this.session);
  final DictationSessionHarness h;
  final _AckRepository repository;
  final LearningUseCases learning;
  final DictationSession session;
  final voice = FakeVoiceProvider();
  final owners = StreamController<String?>.broadcast(sync: true);
  final navigator = GlobalKey<NavigatorState>();
  LearningSessionSummary? summary;

  static Future<_Fixture> open(WidgetTester tester) async {
    final h = (await tester.runAsync(DictationSessionHarness.open))!;
    final repository = _AckRepository(h.repository);
    var nextId = 0;
    final learning = LearningUseCases(
      owners: h.storage.owners,
      repository: repository,
      generateId: () => 'dictation-ui-${++nextId}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'synthetic-ui'),
    );
    final session = await tester.runAsync(
      () => learning.prepareDictation(
        categoryId: configuredCategoryId,
        stillCurrent: () => true,
      ),
    );
    return _Fixture(h, repository, learning, session!);
  }

  Future<void> close(WidgetTester tester) async {
    for (final gate in [
      voice.stopGate,
      voice.speakGate,
      repository.answerGate,
    ]) {
      if (gate != null && !gate.isCompleted) {
        gate.complete();
      }
    }
    _resume(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(repository.settle);
    if (!owners.isClosed) {
      await tester.runAsync(owners.close);
    }
    await tester.runAsync(h.close);
  }

  Future<int> count(WidgetTester tester, String table) async =>
      (await tester.runAsync(() => h.storage.count(table)))!;
}

final class _AckRepository extends Fake
    implements LearningRepository, NativeExerciseRepository {
  _AckRepository(this.delegate);
  final NativeExerciseRepository delegate;
  final starts = <AcceptedNativeExercise>[];
  final answers = <RecordAnswerCommand>[];
  final finishes = <NativeFinishIntent>[];
  bool loseStart = false;
  bool loseAnswer = false;
  bool loseFinish = false;
  Completer<void>? answerGate;
  final _pending = <Future<void>>{};

  Future<T> _track<T>(Future<T> Function() operation) async {
    final done = Completer<void>();
    _pending.add(done.future);
    try {
      return await operation();
    } finally {
      _pending.remove(done.future);
      done.complete();
    }
  }

  Future<void> settle() async {
    await Future.wait(_pending.toList());
  }

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    required int limit,
  }) => (delegate as LearningRepository).listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    wordIds: wordIds,
    limit: limit,
  );

  @override
  Future<T> startNativeExercise<T extends AcceptedNativeExercise>(
    T session, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    starts.add(session);
    final result = await delegate.startNativeExercise(
      session,
      stillCurrent: stillCurrent,
    );
    if (loseStart) {
      loseStart = false;
      throw StateError('synthetic lost start ACK');
    }
    return result;
  });

  @override
  Future<AnswerRecordResult> commitNativeAnswer(
    AcceptedNativeExercise session,
    RecordAnswerCommand command, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    answers.add(command);
    await answerGate?.future;
    final result = await delegate.commitNativeAnswer(
      session,
      command,
      stillCurrent: stillCurrent,
    );
    if (loseAnswer) {
      loseAnswer = false;
      throw StateError('synthetic lost answer ACK');
    }
    return result;
  });

  @override
  Future<LearningSessionSummary> finishNativeExercise(
    NativeFinishIntent intent, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    finishes.add(intent);
    final result = await delegate.finishNativeExercise(
      intent,
      stillCurrent: stillCurrent,
    );
    if (loseFinish) {
      loseFinish = false;
      throw StateError('synthetic lost finish ACK');
    }
    return result;
  });
}

final class _LifecycleTts implements NativeTtsAdapter {
  int stops = 0;
  String? active;
  String? heldText;
  Completer<void>? speakStarted;
  Completer<void>? speakGate;
  @override
  Future<void> setLanguage(String language) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> speak(String text) async {
    active = text;
    if (text == heldText) {
      speakStarted!.complete();
      await speakGate!.future;
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    active = null;
  }
}

final class _ReplacementSpeaker extends StatefulWidget {
  const _ReplacementSpeaker({
    required this.voice,
    required this.allowed,
    required this.onResult,
  });
  final VoiceUseCases voice;
  final Future<void> allowed;
  final void Function(Object) onResult;
  @override
  State<_ReplacementSpeaker> createState() => _ReplacementSpeakerState();
}

final class _ReplacementSpeakerState extends State<_ReplacementSpeaker> {
  @override
  void initState() {
    super.initState();
    unawaited(_speak());
  }

  Future<void> _speak() async {
    await widget.allowed;
    if (!mounted) return;
    try {
      widget.onResult(
        await widget.voice.speak(
          VoiceRequest.create(
            text: 'synthetic replacement speech',
            language: 'en',
            voiceId: 'teacher_female',
            speed: 1,
            mode: VoiceMode.practice,
            contentId: 'synthetic-replacement',
            contentType: 'word',
          ),
        ),
      );
    } on Object catch (error) {
      widget.onResult(error);
    }
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('Next route'));
}

final class _LifecycleAudio implements AudioPlayerAdapter {
  int disposals = 0;
  @override
  Future<void> playBytes(Uint8List bytes) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture f, {
  bool ready = true,
  String language = 'th',
  double scale = 1,
  VoiceUseCases? voiceOverride,
  bool useDefaultVoice = false,
}) async {
  _resume(tester);
  final voice = useDefaultVoice
      ? null
      : voiceOverride ?? VoiceUseCases(f.voice);
  final owners = f.owners.stream;
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: f.navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              f.summary = await Navigator.of(context)
                  .push<LearningSessionSummary>(
                    MaterialPageRoute(
                      builder: (_) => DictationQuizScreen(
                        session: f.session,
                        learning: f.learning,
                        voice: voice,
                        ownerChanges: owners,
                        languageCode: language,
                      ),
                    ),
                  );
            },
            child: const Text('Open dictation'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open dictation'));
  await tester.pump();
  f.owners.add(configuredOwnerId);
  if (ready) {
    if (!useDefaultVoice && voiceOverride == null) {
      await _until(tester, () => f.voice.spokenRequests.isNotEmpty);
    }
    await _ready(tester);
  }
}

Future<void> _ready(WidgetTester tester) async {
  await _until(
    tester,
    () =>
        find.byType(DictationQuizScreen).evaluate().isNotEmpty &&
        find.byType(Scrollable).evaluate().isNotEmpty,
  );
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('dictation-response')),
    120,
    scrollable: find.byType(Scrollable).last,
  );
  await _until(tester, () {
    final fields = find.byKey(const ValueKey('dictation-response')).evaluate();
    return fields.isNotEmpty &&
        (fields.single.widget as TextField).enabled == true;
  });
}

Future<void> _save(WidgetTester tester, String response) async {
  await tester.enterText(
    find.byKey(const ValueKey('dictation-response')),
    response,
  );
  await tester.pump();
  await tester.ensureVisible(find.byKey(const ValueKey('dictation-save')));
  await tester.tap(find.byKey(const ValueKey('dictation-save')));
  await tester.pump();
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Synthetic operation did not reach expected UI state',
  );
}

void _resume(WidgetTester tester) {
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}
