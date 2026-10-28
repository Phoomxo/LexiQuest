// Synthetic host media/rendering only, no device evidence.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'dart:async';
import 'dart:ui' show SemanticsActionEvent;

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

import '../../test/support/inert_research_dependencies.dart';
import '../../test/support/test_quest_use_cases.dart';

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
    final app = RepaintBoundary(
      key: const ValueKey('media-capture'),
      child: MaterialApp(
        theme: M3Theme.lightTheme,
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

  for (final scale in [1.0, 2.0]) {
    panelTest('actual optional media visual scale $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fonts = FontLoader('NotoSansThai')
        ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'));
      await fonts.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      await pump(tester, scale: scale);
      await tester.pumpAndSettle();
      await _capture(tester, 'media-text${(scale * 100).toInt()}-ready');
      await tester.ensureVisible(find.byKey(speak));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(speak));
      await tester.pumpAndSettle();
      gateway.emit('The synthetic cat sits by the window.');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('ระบบได้ยินว่า'));
      await tester.pumpAndSettle();
      await _capture(tester, 'media-text${(scale * 100).toInt()}-transcript');
      await clean(tester);
    });
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('media-capture')),
  );
  await tester.runAsync(() async {
    final bitmap = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      final out = Directory(
        'build/verification/motivation-ui-20260908/visual/c1/contextual',
      );
      await out.create(recursive: true);
      await File(
        '${out.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    } finally {
      bitmap.dispose();
    }
  });
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
    isListening = true;
    event = onEvent;
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
