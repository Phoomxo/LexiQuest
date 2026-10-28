import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/presentation/sentence_practice_panel.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../../support/inert_research_dependencies.dart';
import '../../support/test_quest_use_cases.dart';

const sentence = 'The synthetic cat sits by the window.';
const listen = Key('sentence-practice-listen');
const speak = Key('sentence-practice-speak');
const skip = Key('sentence-practice-skip');

void main() {
  late _VoiceProvider provider;
  late VoiceUseCases voice;
  late _SpeechGateway gateway;
  late SpeechPracticeUseCases speech;
  late LessonEphemeralStateRegistry registry;
  AppDependencies? dependencies;
  var allowed = true;

  void panelTest(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      provider = _VoiceProvider();
      voice = VoiceUseCases(provider: provider, disposeProvider: () async {});
      gateway = _SpeechGateway();
      speech = SpeechPracticeUseCases(gateway);
      registry = LessonEphemeralStateRegistry();
      allowed = true;
      dependencies = null;
      await body(tester);
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    String identity = 'synthetic/item-1',
    String text = sentence,
    bool services = true,
    double scale = 1,
    GlobalKey<NavigatorState>? navigator,
  }) {
    final app = MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [appRouteObserver],
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: UnifiedLessonSessionLifecycleScope(
            ephemeralStates: registry,
            child: SingleChildScrollView(
              child: SentencePracticePanel(
                identity: identity,
                text: text,
                canInteract: () => allowed,
                voice: services ? voice : null,
                speechPractice: services ? speech : null,
              ),
            ),
          ),
        ),
      ),
    );
    return tester.pumpWidget(
      dependencies == null
          ? app
          : AppDependenciesScope(dependencies: dependencies!, child: app),
    );
  }

  Future<void> clean(WidgetTester tester) async {
    if (gateway.permission != null && !gateway.permission!.isCompleted) {
      gateway.permission!.complete(MediaPermissionState.granted);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await speech.dispose();
    await voice.dispose();
  }

  panelTest('listen waits for natural completion and can be stopped', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(listen));
    await tester.pumpAndSettle();
    expect(provider.requests.single.text, sentence);
    expect(find.text('หยุดเสียง'), findsOneWidget);
    provider.completions.last.complete();
    await tester.pumpAndSettle();
    expect(find.text('ฟังประโยค'), findsOneWidget);
    await tester.tap(find.byKey(listen));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(listen));
    await tester.pumpAndSettle();
    expect(provider.stops, greaterThan(0));
    expect(find.text('ฟังประโยค'), findsOneWidget);
    await clean(tester);
  });

  panelTest('microphone stops playback and replay cancels microphone', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(listen));
    await tester.pumpAndSettle();
    gateway.beforeStart = () => expect(provider.stops, greaterThan(0));
    await tester.tap(find.byKey(speak));
    await tester.pumpAndSettle();
    expect(gateway.starts, 1);
    provider.beforeSpeak = () => expect(gateway.cancels, greaterThan(0));
    await tester.tap(find.byKey(listen));
    await tester.pumpAndSettle();
    expect(provider.requests, hasLength(2));
    await clean(tester);
  });

  panelTest('only first final is displayed as unscored ephemeral transcript', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(speak));
    await tester.pumpAndSettle();
    gateway.emit('A synthetic answer');
    gateway.emit('duplicate must be ignored');
    gateway.failure!(SpeechFailureCode.engine);
    await tester.pumpAndSettle();
    expect(find.textContaining('ระบบได้ยินว่า'), findsOneWidget);
    expect(find.textContaining('A synthetic answer'), findsOneWidget);
    expect(find.textContaining('duplicate must be ignored'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('ไม่บันทึก'), findsOneWidget);
    expect(find.text(sentence), findsOneWidget);
    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
    expect(gateway.stops, 1);
    await clean(tester);
  });

  for (final ending in ['empty', 'silence', 'failure']) {
    panelTest('$ending leaves readable retry and skip available', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      if (ending == 'empty') {
        gateway.emit('   ');
      } else if (ending == 'silence') {
        gateway.status!('notListening');
      } else {
        gateway.failure!(SpeechFailureCode.engine);
      }
      await tester.pumpAndSettle();
      expect(find.text('ลองอีกครั้ง'), findsOneWidget);
      expect(find.textContaining('ระบบได้ยินว่า'), findsNothing);
      expect(tester.widget<TextButton>(find.byKey(skip)).onPressed, isNotNull);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      expect(gateway.starts, 2);
      await clean(tester);
    });
  }

  panelTest('stop discards late final and offers retry', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(speak));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(speak));
    gateway.emit('late after stop');
    await tester.pumpAndSettle();
    expect(gateway.stops, 1);
    expect(find.textContaining('late after stop'), findsNothing);
    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
    await clean(tester);
  });

  panelTest('skip clears transcript and cancels active resources', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(speak));
    await tester.pumpAndSettle();
    final late = gateway.event!;
    await tester.tap(find.byKey(skip));
    late(_event('late skipped answer'));
    await tester.pumpAndSettle();
    expect(gateway.cancels, 1);
    expect(find.textContaining('late skipped answer'), findsNothing);
    expect(find.text(sentence), findsOneWidget);
    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
    await clean(tester);
  });

  panelTest('item replacement fences old final and completion', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(speak));
    await tester.pumpAndSettle();
    final late = gateway.event!;
    await pump(tester, identity: 'synthetic/item-2', text: 'A new sentence.');
    late(_event('previous item'));
    await tester.pumpAndSettle();
    expect(find.textContaining('previous item'), findsNothing);
    expect(find.text('A new sentence.'), findsOneWidget);
    await tester.tap(find.byKey(listen));
    await tester.pumpAndSettle();
    final completion = provider.completions.last;
    await pump(tester, identity: 'synthetic/item-3', text: 'Third sentence.');
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.text('ฟังประโยค'), findsOneWidget);
    await clean(tester);
  });

  panelTest(
    'route cover cancels and fences callbacks then permits explicit retry',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await pump(tester, navigator: navigator);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      final late = gateway.event!;
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('cover')),
        ),
      );
      await tester.pumpAndSettle();
      late(_event('covered answer'));
      expect(gateway.cancels, 1);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.textContaining('covered answer'), findsNothing);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      expect(gateway.starts, 2);
      await clean(tester);
    },
  );

  panelTest('background clears raw speech and fences stale physical handler', (
    tester,
  ) async {
    await pump(tester);
    final stale = tester.widget<OutlinedButton>(find.byKey(speak)).onPressed!;
    await tester.tap(find.byKey(speak));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    stale();
    gateway.emit('background answer');
    await tester.pumpAndSettle();
    expect(gateway.starts, 1);
    expect(gateway.cancels, 1);
    expect(find.textContaining('background answer'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await clean(tester);
  });

  panelTest(
    'pending permission is synchronously invalidated by shell retirement',
    (tester) async {
      gateway.permission = Completer<MediaPermissionState>();
      await pump(tester);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      registry.clear();
      gateway.permission!.complete(MediaPermissionState.granted);
      await tester.pumpAndSettle();
      expect(gateway.starts, 0);
      expect(gateway.initializations, 0);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      expect(gateway.starts, 0);
      await clean(tester);
    },
  );

  panelTest(
    'predicate is checked by stale handlers and final callback without rebuild',
    (tester) async {
      await pump(tester);
      final staleListen = tester
          .widget<OutlinedButton>(find.byKey(listen))
          .onPressed!;
      final staleSpeak = tester
          .widget<OutlinedButton>(find.byKey(speak))
          .onPressed!;
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      allowed = false;
      gateway.emit('revoked answer');
      staleListen();
      staleSpeak();
      await tester.pumpAndSettle();
      expect(gateway.starts, 1);
      expect(provider.requests, isEmpty);
      expect(find.textContaining('revoked answer'), findsNothing);
      expect(gateway.isListening, isFalse);
      await clean(tester);
    },
  );

  panelTest(
    'service replacement clears feedback and cannot cancel a new owner',
    (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      final oldSpeech = speech;
      final oldVoice = voice;
      final oldGateway = gateway;
      final late = gateway.event!;
      gateway = _SpeechGateway();
      speech = SpeechPracticeUseCases(gateway);
      provider = _VoiceProvider();
      voice = VoiceUseCases(provider: provider, disposeProvider: () async {});
      await pump(tester);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      late(_event('old service answer'));
      await tester.pumpAndSettle();
      expect(oldGateway.cancels, 1);
      expect(gateway.isListening, isTrue);
      expect(gateway.cancels, 0);
      expect(find.textContaining('old service answer'), findsNothing);
      await clean(tester);
      await oldSpeech.dispose();
      await oldVoice.dispose();
    },
  );

  panelTest(
    'retirement does not release another consumer speech or voice handle',
    (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      final replacement = speech.acquireSession();
      await replacement.start(
        locale: 'en-US',
        onEvent: (_) {},
        onFailure: (_) {},
        onStatus: (_) {},
      );
      final replacementVoice = voice.acquireSession();
      final stops = gateway.cancels;
      registry.clear();
      await tester.pumpAndSettle();
      expect(replacement.isCurrent, isTrue);
      expect(replacementVoice.isCurrent, isTrue);
      expect(gateway.cancels, stops);
      await replacement.release();
      await replacementVoice.release();
      await clean(tester);
    },
  );

  panelTest('unavailable services do not hide sentence or skip', (
    tester,
  ) async {
    await pump(tester, services: false);
    expect(find.text(sentence), findsOneWidget);
    expect(find.textContaining('ไม่พร้อมใช้งาน'), findsWidgets);
    await tester.tap(find.byKey(skip));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await clean(tester);
  });

  for (final state in [
    FeatureState.hidden,
    FeatureState.disabled,
    FeatureState.emergencyOff,
  ]) {
    panelTest(
      'scoped $state gate prevents microphone even with wired services',
      (tester) async {
        final database = AppDatabase(NativeDatabase.memory());
        dependencies = _dependencies(
          database,
          BuildFeatureRegistry({Feature.speechPractice: state}),
          voice,
          speech,
        );
        await pump(tester, services: false);
        expect(
          tester.widget<OutlinedButton>(find.byKey(speak)).onPressed,
          isNull,
        );
        await tester.tap(find.byKey(listen));
        await tester.pumpAndSettle();
        expect(provider.requests, hasLength(1));
        expect(gateway.starts, 0);
        await clean(tester);
        await database.close();
      },
    );
  }

  panelTest(
    'runtime emergency-off cancels permission before gateway start and fences stale action',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      dependencies = _dependencies(database, features, voice, speech);
      gateway.permission = Completer<MediaPermissionState>();
      await pump(tester, services: false);
      final stale = tester.widget<OutlinedButton>(find.byKey(speak)).onPressed!;
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      features.emergencyOff(Feature.speechPractice);
      stale();
      gateway.permission!.complete(MediaPermissionState.granted);
      await tester.pumpAndSettle();
      expect(gateway.starts, 0);
      expect(gateway.initializations, 0);
      expect(tester.widget<TextButton>(find.byKey(skip)).onPressed, isNotNull);
      await clean(tester);
      features.dispose();
      await database.close();
    },
  );

  panelTest('non-listenable feature gate is rechecked at final callback', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final features = MutableFeatureRegistry()..enable(Feature.speechPractice);
    dependencies = _dependencies(database, features, voice, speech);
    await pump(tester, services: false);
    await tester.tap(find.byKey(speak));
    await tester.pumpAndSettle();
    features.disable(Feature.speechPractice);
    gateway.emit('disabled gate transcript');
    await tester.pumpAndSettle();
    expect(find.textContaining('disabled gate transcript'), findsNothing);
    expect(gateway.isListening, isFalse);
    await clean(tester);
    await database.close();
  });

  panelTest(
    'final emitted before start returns survives duplicate and late thrown failure',
    (tester) async {
      gateway.finalBeforeReturn = true;
      await pump(tester);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      expect(find.textContaining('first synchronous final'), findsOneWidget);
      expect(find.textContaining('duplicate synchronous final'), findsNothing);
      expect(find.textContaining('ระบบรู้จำเสียงไม่พร้อมใช้งาน'), findsNothing);
      expect(gateway.stops, 1);
      await clean(tester);
    },
  );

  panelTest(
    'failed playback cleanup cannot be forgotten by a subsequent microphone retry',
    (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(listen));
      await tester.pumpAndSettle();
      provider.failStop = true;
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      expect(gateway.starts, 0);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      expect(
        gateway.starts,
        0,
        reason: 'silence remains unconfirmed after failed cleanup',
      );
      expect(tester.widget<TextButton>(find.byKey(skip)).onPressed, isNotNull);
      provider.failStop = false;
      await clean(tester);
    },
  );

  panelTest(
    'failed recognition cleanup cannot be forgotten by subsequent playback retry',
    (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      gateway.failCancel = true;
      await tester.tap(find.byKey(listen));
      await tester.pumpAndSettle();
      expect(provider.requests, isEmpty);
      await tester.tap(find.byKey(listen));
      await tester.pumpAndSettle();
      expect(
        provider.requests,
        isEmpty,
        reason: 'microphone cancellation has not succeeded',
      );
      gateway.failCancel = false;
      await clean(tester);
    },
  );

  panelTest(
    'narrow 200 percent layout exposes usable physical and semantic actions',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await pump(tester, scale: 2);
      expect(tester.takeException(), isNull);
      for (final key in [listen, speak, skip]) {
        await tester.ensureVisible(find.byKey(key));
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester
              .getSemantics(find.byKey(key))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
      }
      await tester.ensureVisible(find.byKey(speak));
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      expect(gateway.starts, 1);
      await tester.ensureVisible(find.byKey(skip));
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          viewId: tester.view.viewId,
          nodeId: tester.getSemantics(find.byKey(skip)).id,
          type: SemanticsAction.tap,
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway.cancels, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await clean(tester);
    },
  );

  panelTest('start then throw retains pending cancel before playback', (
    tester,
  ) async {
    final cancelled = Completer<void>();
    gateway.throwAfterStart = true;
    gateway.cancelCompletion = cancelled;
    try {
      await pump(tester);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      expect(gateway.isListening, isTrue);
      expect(gateway.cancels, 1);
      await tester.tap(find.byKey(listen));
      await tester.pumpAndSettle();
      expect(
        provider.requests,
        isEmpty,
        reason: 'the native cancel is still pending',
      );
      cancelled.complete();
      await tester.pumpAndSettle();
      expect(gateway.isListening, isFalse);
      expect(provider.requests, hasLength(1));
    } finally {
      if (!cancelled.isCompleted) cancelled.complete();
      await clean(tester);
    }
  });

  panelTest('start then throw retains failed cancel across playback attempts', (
    tester,
  ) async {
    gateway.throwAfterStart = true;
    gateway.failCancel = true;
    try {
      await pump(tester);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      expect(gateway.cancels, 1);
      await tester.tap(find.byKey(listen));
      await tester.pumpAndSettle();
      expect(
        provider.requests,
        isEmpty,
        reason: 'failed cancel cannot establish silence',
      );
      await tester.tap(find.byKey(listen));
      await tester.pumpAndSettle();
      expect(provider.requests, isEmpty);
      expect(tester.widget<TextButton>(find.byKey(skip)).onPressed, isNotNull);
    } finally {
      gateway.failCancel = false;
      await clean(tester);
    }
  });

  panelTest('stop during delayed native start drains before playback', (
    tester,
  ) async {
    final started = Completer<void>();
    gateway.beforeListening = started;
    try {
      await pump(tester);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      expect(gateway.starts, 1);
      expect(gateway.isListening, isFalse);
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(listen));
      await tester.pumpAndSettle();
      expect(
        provider.requests,
        isEmpty,
        reason: 'stop is queued behind pending native start',
      );
      started.complete();
      await tester.pumpAndSettle();
      expect(gateway.stops, 1);
      expect(gateway.isListening, isFalse);
      expect(provider.requests, hasLength(1));
    } finally {
      if (!started.isCompleted) started.complete();
      await clean(tester);
    }
  });

  panelTest(
    'final callback retains queued stop even when native listening flag clears',
    (tester) async {
      final returned = Completer<void>();
      gateway.afterFinal = returned;
      try {
        await pump(tester);
        await tester.tap(find.byKey(speak));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('synthetic final before return'),
          findsOneWidget,
        );
        expect(gateway.isListening, isFalse);
        await tester.tap(find.byKey(listen));
        await tester.pumpAndSettle();
        expect(
          provider.requests,
          isEmpty,
          reason: 'accepted final has a pending native stop',
        );
        returned.complete();
        await tester.pumpAndSettle();
        expect(gateway.stops, 1);
        expect(provider.requests, hasLength(1));
      } finally {
        if (!returned.isCompleted) returned.complete();
        await clean(tester);
      }
    },
  );
}

SpeechRecognitionEvent _event(String transcript) => SpeechRecognitionEvent(
  transcript: transcript,
  isFinal: true,
  recognizedAtUtc: DateTime.utc(2026, 9, 8),
  engine: 'synthetic-test',
  locale: 'en-US',
  recognitionConfidence: 0.98,
);

class _SpeechGateway implements SpeechRecognitionGateway {
  Completer<MediaPermissionState>? permission;
  SpeechEventCallback? event;
  SpeechFailureCallback? failure;
  void Function(String)? status;
  void Function()? beforeStart;
  bool finalBeforeReturn = false;
  bool failCancel = false;
  bool throwAfterStart = false;
  Completer<void>? cancelCompletion;
  Completer<void>? beforeListening;
  Completer<void>? afterFinal;
  int starts = 0, stops = 0, cancels = 0, initializations = 0;
  @override
  bool isListening = false;
  @override
  Future<MediaPermissionState> requestPermission() async =>
      permission == null ? MediaPermissionState.granted : permission!.future;
  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String) onStatus,
  }) async {
    initializations++;
    failure = onFailure;
    status = onStatus;
  }

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    beforeStart?.call();
    starts++;
    await beforeListening?.future;
    isListening = true;
    event = onEvent;
    if (throwAfterStart) {
      throw const SpeechPracticeException(SpeechFailureCode.engine);
    }
    if (afterFinal != null) {
      emit('synthetic final before return');
      isListening = false;
      await afterFinal!.future;
    }
    if (finalBeforeReturn) {
      emit('first synchronous final');
      emit('duplicate synchronous final');
      throw const SpeechPracticeException(SpeechFailureCode.engine);
    }
  }

  void emit(String transcript) => event!(_event(transcript));
  @override
  Future<void> stop() async {
    stops++;
    isListening = false;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    await cancelCompletion?.future;
    if (failCancel) throw StateError('synthetic cancel failure');
    isListening = false;
  }
}

class _VoiceProvider implements VoiceProvider {
  final requests = <VoiceRequest>[];
  final completions = <Completer<void>>[];
  void Function()? beforeSpeak;
  int stops = 0;
  bool failStop = false;
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    beforeSpeak?.call();
    requests.add(request);
    final completion = Completer<void>();
    completions.add(completion);
    return VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
      playbackCompleted: completion.future,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    if (failStop) throw StateError('synthetic stop failure');
  }
}

AppDependencies _dependencies(
  AppDatabase database,
  FeatureRegistry features,
  VoiceUseCases voice,
  SpeechPracticeUseCases speech,
) {
  final research = InertResearchDependencies(database);
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.ready,
      supabase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    guestSessionService: _GuestSessionService(),
    quest: testQuestUseCases(),
    features: features,
    voice: voice,
    speechPractice: speech,
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
  );
}

class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-sentence-practice');
}
