import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import 'sentence_scramble_native_harness.dart';

export 'sentence_scramble_native_harness.dart';

final class SentenceScrambleUiFixture {
  SentenceScrambleUiFixture._(
    this.core,
    this.repository,
    this.learning,
    this.session,
  ) {
    dependencies = ValueNotifier(createDependencies());
  }
  final SentenceScrambleNativeHarness core;
  final SentenceUiAckRepository repository;
  final LearningUseCases learning;
  final SentenceScrambleSession session;
  final owners = StreamController<String?>.broadcast(sync: true);
  final navigator = GlobalKey<NavigatorState>();
  final language = ValueNotifier('th');
  final rebuild = ValueNotifier(0);
  final voice = SentenceUiVoiceProvider();
  late final ValueNotifier<AppDependencies> dependencies;
  VoidCallback? onRebuild;
  LearningSessionSummary? summary;
  List<String> get bank => [
    for (final index in session.tokenOrder) session.content.tokens[index],
  ];

  static Future<SentenceScrambleUiFixture> open(
    WidgetTester tester, {
    String? sentence,
    String meaning = 'synthetic owned vocabulary meaning',
  }) async {
    final core = (await tester.runAsync(SentenceScrambleNativeHarness.open))!;
    await tester.runAsync(() async {
      await core.database.customStatement(
        "UPDATE vocabulary_words SET spelling = 'school', normalized_spelling = 'school', meaning = ? WHERE id = ?",
        [meaning, configuredWordIds.first],
      );
    });
    core.provider.response = (request) => ContentResponse(
      text: sentence ?? 'We visit the ${request.text} today.',
      kind: ContentKind.sentence,
      cefr: CefrLevel.unknown,
      language: 'en',
      modelVersion: 'synthetic-sentence-ui-provider',
      cached: false,
    );
    final repository = SentenceUiAckRepository(core.repository);
    var sequence = 0;
    final learning = LearningUseCases(
      owners: core.storage.owners,
      repository: repository,
      generateId: () => 'synthetic-sentence-ui-${++sequence}',
      nowUtc: () => core.now,
      buildInfo: core.learning.buildInfo,
      contentProvider: core.provider,
    );
    final prepared = await tester.runAsync(
      () => learning.prepareSentenceScramble(
        categoryId: configuredCategoryId,
        stillCurrent: () => true,
      ),
    );
    return SentenceScrambleUiFixture._(core, repository, learning, prepared!);
  }

  AppDependencies createDependencies() => AppDependencies(
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _Guest(),
    database: core.database,
    localOwners: core.storage.owners,
    learning: learning,
  );

  Future<int> count(WidgetTester tester, String table) async =>
      (await tester.runAsync(() => core.storage.count(table)))!;

  Future<void> close(WidgetTester tester) async {
    repository.release();
    voice.release();
    sentenceResume(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(repository.settle);
    if (!owners.isClosed) {
      await tester.runAsync(owners.close);
    }
    language.dispose();
    rebuild.dispose();
    dependencies.dispose();
    await tester.runAsync(core.close);
  }
}

final class SentenceUiAckRepository extends Fake
    implements LearningRepository, NativeExerciseRepository {
  SentenceUiAckRepository(this.delegate);
  final NativeExerciseRepository delegate;
  final starts = <AcceptedNativeExercise>[];
  final answers = <RecordAnswerCommand>[];
  final finishes = <NativeFinishIntent>[];
  final pending = <Future<void>>{};
  bool loseStart = false;
  bool loseAnswer = false;
  bool loseFinish = false;
  Completer<void>? startGate;
  Completer<void>? answerGate;
  Completer<void>? finishGate;
  void release() {
    for (final gate in [startGate, answerGate, finishGate]) {
      if (gate != null && !gate.isCompleted) {
        gate.complete();
      }
    }
  }

  Future<T> _track<T>(Future<T> Function() operation) async {
    final done = Completer<void>();
    pending.add(done.future);
    try {
      return await operation();
    } finally {
      pending.remove(done.future);
      done.complete();
    }
  }

  Future<void> settle() async {
    await Future.wait(pending.toList());
  }

  @override
  Future<bool> hasAmbientTransaction() => delegate.hasAmbientTransaction();
  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    String? afterWordId,
    required int limit,
  }) => (delegate as LearningRepository).listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    wordIds: wordIds,
    afterWordId: afterWordId,
    limit: limit,
  );
  @override
  Future<T> startNativeExercise<T extends AcceptedNativeExercise>(
    T exercise, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    starts.add(exercise);
    await startGate?.future;
    final result = await delegate.startNativeExercise(
      exercise,
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
    AcceptedNativeExercise exercise,
    RecordAnswerCommand command, {
    required bool Function() stillCurrent,
  }) => _track(() async {
    answers.add(command);
    await answerGate?.future;
    final result = await delegate.commitNativeAnswer(
      exercise,
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
    await finishGate?.future;
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

final class SentenceUiVoiceProvider implements VoiceProvider {
  final spokenRequests = <VoiceRequest>[];
  int stops = 0;
  Completer<VoicePlaybackResult>? gate;
  Completer<void>? stopGate;
  bool rejectNext = false;
  void release() {
    if (gate case final pending? when !pending.isCompleted) {
      pending.complete(_played);
    }
    if (stopGate case final pending? when !pending.isCompleted) {
      pending.complete();
    }
  }

  static const _played = VoicePlaybackResult(
    requestedEngine: VoiceEngine.nativeTts,
    actualEngine: VoiceEngine.nativeTts,
    usedFallback: false,
    cacheHit: false,
  );
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
    if (rejectNext) {
      rejectNext = false;
      throw const VoiceFailure(
        category: VoiceFailureCategory.synthesis,
        message: 'SYNTHETIC_PRIVATE_VOICE',
      );
    }
    return await gate?.future ?? _played;
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopGate?.future;
  }
}

Future<void> mountSentenceUi(
  WidgetTester tester,
  SentenceScrambleUiFixture f, {
  bool ready = true,
  bool emitOwner = true,
  bool includeVoice = true,
  VoiceUseCases? voice,
  String language = 'th',
  double scale = 1,
  bool reducedMotion = false,
}) async {
  sentenceResume(tester);
  final owners = f.owners.stream;
  final resolvedVoice = includeVoice ? voice ?? VoiceUseCases(f.voice) : null;
  f.language.value = language;
  await tester.pumpWidget(
    ValueListenableBuilder<int>(
      valueListenable: f.rebuild,
      builder: (_, value, child) {
        final hook = f.onRebuild;
        f.onRebuild = null;
        hook?.call();
        return child!;
      },
      child: ValueListenableBuilder<AppDependencies>(
        valueListenable: f.dependencies,
        builder: (_, dependencies, _) => AppDependenciesScope(
          dependencies: dependencies,
          child: MaterialApp(
            navigatorKey: f.navigator,
            theme: M3Theme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: reducedMotion,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    f.summary = await Navigator.of(context)
                        .push<LearningSessionSummary>(
                          MaterialPageRoute(
                            builder: (_) => ValueListenableBuilder<String>(
                              valueListenable: f.language,
                              builder: (_, code, _) => SentenceScrambleScreen(
                                session: f.session,
                                learning: f.learning,
                                ownerChanges: owners,
                                voice: resolvedVoice,
                                languageCode: code,
                              ),
                            ),
                          ),
                        );
                  },
                  child: const Text('Open Sentence Scramble'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Sentence Scramble'));
  await tester.pump();
  if (emitOwner) {
    f.owners.add(configuredOwnerId);
  }
  if (ready) {
    await sentenceReady(tester, f);
  }
}

Future<void> sentenceReady(
  WidgetTester tester,
  SentenceScrambleUiFixture f,
) async {
  await sentenceUntil(tester, () => f.repository.starts.isNotEmpty);
  await tester.runAsync(f.repository.settle);
  await tester.pump();
  final input = find.byKey(const ValueKey('sentence-response'));
  await sentenceReveal(tester, input);
  expect(tester.widget<TextField>(input).enabled, isTrue);
}

Future<void> sentenceReveal(WidgetTester tester, Finder target) async {
  // A selected long piece can change the layout before the next scroll.
  await tester.pump();
  if (target.evaluate().isEmpty) {
    final scrollable = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.minScrollExtent);
    await tester.pump();
    for (var index = 0; index < 200 && target.evaluate().isEmpty; index++) {
      final bounds = tester.getRect(scrollable);
      // List padding keeps a focused text field from taking the drag.
      await tester.dragFrom(
        Offset(bounds.left + 8, bounds.center.dy),
        const Offset(0, -120),
      );
      position.jumpTo(position.pixels);
      await tester.pump();
    }
    expect(target, findsOneWidget);
    await tester.ensureVisible(target);
  } else {
    await tester.ensureVisible(target);
  }
  await tester.pumpAndSettle();
}

Future<void> sentenceTap(WidgetTester tester, Key key) async {
  final target = find.byKey(key);
  await sentenceReveal(tester, target);
  await tester.tap(target.hitTestable());
  await tester.pump();
}

Future<void> sentenceType(WidgetTester tester, String response) async {
  final target = find.byKey(const ValueKey('sentence-response'));
  await sentenceReveal(tester, target);
  await tester.enterText(target, response);
  await tester.pump();
}

Future<void> sentenceSaved(
  WidgetTester tester,
  SentenceScrambleUiFixture f,
) async {
  await tester.runAsync(f.repository.settle);
  await tester.pump();
  await sentenceReveal(tester, find.byKey(const ValueKey('sentence-finish')));
}

Future<void> sentenceRetry(
  WidgetTester tester,
  SentenceScrambleUiFixture f,
) async {
  await tester.runAsync(f.repository.settle);
  await tester.pump();
  await sentenceUntil(
    tester,
    () => find.byKey(const ValueKey('sentence-retry')).evaluate().isNotEmpty,
  );
  await sentenceReveal(tester, find.byKey(const ValueKey('sentence-retry')));
}

Future<void> sentenceUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Sentence UI did not reach the expected observable state',
  );
}

void sentenceResume(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-sentence-guest');
}
