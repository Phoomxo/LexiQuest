import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/features/voice/presentation/route_voice_session_mixin.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  testWidgets(
    'a delayed cover hook cannot release the freshly resumed session',
    (tester) async {
      final provider = _RecordingProvider();
      final voice = VoiceUseCases(
        provider: provider,
        disposeProvider: () async {},
      );
      final covered = Completer<void>();
      final key = GlobalKey<_RouteVoiceHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _RouteVoiceHarness(key: key, voice: voice, covered: covered),
        ),
      );
      await tester.pump();
      try {
        final state = key.currentState!;
        final initial = state.resumedSession!;

        state.didPushNext();
        await tester.pump();
        state.didPopNext();
        await tester.pump();
        final resumed = state.resumedSession!;

        expect(identical(initial, resumed), isFalse);
        expect(resumed.isCurrent, isTrue);

        covered.complete();
        await tester.pump();
        await resumed.speak(_request('fresh session'));

        expect(resumed.isCurrent, isTrue);
        expect(provider.spoken, <String>['fresh session']);
      } finally {
        if (!covered.isCompleted) covered.complete();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await voice.dispose().timeout(const Duration(seconds: 1));
      }
    },
  );

  testWidgets(
    'facade rebind consumes old cleanup failure and keeps new session usable',
    (tester) async {
      final oldProvider = _RecordingProvider(
        stopFailure: StateError('old stop'),
      );
      final newProvider = _RecordingProvider();
      final oldVoice = VoiceUseCases(
        provider: oldProvider,
        disposeProvider: () async {},
      );
      final newVoice = VoiceUseCases(
        provider: newProvider,
        disposeProvider: () async {},
      );
      final key = GlobalKey<_ScopedRouteVoiceHarnessState>();
      Future<void> pump(VoiceUseCases voice) => tester.pumpWidget(
        MaterialApp(
          home: _VoiceScope(
            voice: voice,
            child: _ScopedRouteVoiceHarness(key: key),
          ),
        ),
      );

      await pump(oldVoice);
      await tester.pump();
      try {
        await key.currentState!.resumedSession!.speak(_request('old'));
        await pump(newVoice);
        await tester.pump();
        await key.currentState!.resumedSession!.speak(_request('new'));
        await tester.pump();

        expect(oldProvider.stopCalls, 1);
        expect(newProvider.spoken, <String>['new']);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await oldVoice.dispose().timeout(const Duration(seconds: 1));
        await newVoice.dispose().timeout(const Duration(seconds: 1));
      }
    },
  );

  testWidgets('app background stops playback owned by every route session', (
    tester,
  ) async {
    final provider = _RecordingProvider();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    final covered = Completer<void>()..complete();
    final key = GlobalKey<_RouteVoiceHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: _RouteVoiceHarness(key: key, voice: voice, covered: covered),
      ),
    );
    await tester.pump();
    try {
      await key.currentState!.resumedSession!.speak(_request('playing'));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.runAsync(
        () => provider.stopEntered.future.timeout(
          const Duration(milliseconds: 250),
        ),
      );

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
      await tester.runAsync(
        () => voice.dispose().timeout(const Duration(seconds: 1)),
      );
    }
  });

  testWidgets('background denies deferred acquisition until resume', (
    tester,
  ) async {
    final provider = _RecordingProvider();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    final covered = Completer<void>()..complete();
    final key = GlobalKey<_RouteVoiceHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: _RouteVoiceHarness(key: key, voice: voice, covered: covered),
      ),
    );
    await tester.pump();
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      final deferred = key.currentState!.currentSession;
      if (deferred != null) await deferred.speak(_request('late'));

      expect(deferred, isNull);
      expect(provider.spoken, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(key.currentState!.currentSession, isNotNull);
    } finally {
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () => voice.dispose().timeout(const Duration(seconds: 1)),
      );
    }
  });

  testWidgets('current route reacquires after cover-pop while inactive', (
    tester,
  ) async {
    final provider = _RecordingProvider();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    final covered = Completer<void>()..complete();
    final key = GlobalKey<_RouteVoiceHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: _RouteVoiceHarness(key: key, voice: voice, covered: covered),
      ),
    );
    await tester.pump();
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      key.currentState!
        ..didPushNext()
        ..didPopNext();
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final resumed = key.currentState!.currentSession;
      await resumed?.speak(_request('reacquired'));

      expect(resumed, isNotNull);
      expect(provider.spoken, <String>['reacquired']);
    } finally {
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () => voice.dispose().timeout(const Duration(seconds: 1)),
      );
    }
  });
}

final class _RouteVoiceHarness extends StatefulWidget {
  const _RouteVoiceHarness({
    super.key,
    required this.voice,
    required this.covered,
  });

  final VoiceUseCases voice;
  final Completer<void> covered;

  @override
  State<_RouteVoiceHarness> createState() => _RouteVoiceHarnessState();
}

final class _RouteVoiceHarnessState extends State<_RouteVoiceHarness>
    with WidgetsBindingObserver, RouteVoiceSessionMixin<_RouteVoiceHarness> {
  VoiceSession? resumedSession;

  VoiceSession? get currentSession => routeVoiceSession;

  @override
  VoiceUseCases get routeVoiceUseCases => widget.voice;

  @override
  Future<void> onVoiceRouteCovered() => widget.covered.future;

  @override
  void onVoiceRouteResumed() {
    resumedSession = routeVoiceSession;
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

final class _VoiceScope extends InheritedWidget {
  const _VoiceScope({required this.voice, required super.child});

  final VoiceUseCases voice;

  static VoiceUseCases of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_VoiceScope>()!.voice;

  @override
  bool updateShouldNotify(_VoiceScope oldWidget) =>
      !identical(voice, oldWidget.voice);
}

final class _ScopedRouteVoiceHarness extends StatefulWidget {
  const _ScopedRouteVoiceHarness({super.key});

  @override
  State<_ScopedRouteVoiceHarness> createState() =>
      _ScopedRouteVoiceHarnessState();
}

final class _ScopedRouteVoiceHarnessState
    extends State<_ScopedRouteVoiceHarness>
    with
        WidgetsBindingObserver,
        RouteVoiceSessionMixin<_ScopedRouteVoiceHarness> {
  VoiceSession? resumedSession;

  @override
  VoiceUseCases get routeVoiceUseCases => _VoiceScope.of(context);

  @override
  void onVoiceRouteResumed() {
    resumedSession = routeVoiceSession;
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

final class _RecordingProvider implements VoiceProvider {
  _RecordingProvider({this.stopFailure});

  final List<String> spoken = <String>[];
  final Object? stopFailure;
  final Completer<void> stopEntered = Completer<void>();
  int stopCalls = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spoken.add(request.text);
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
    if (stopFailure case final failure?) throw failure;
  }
}

VoiceRequest _request(String text) => VoiceRequest.create(
  text: text,
  language: 'en',
  voiceId: 'route-test',
  speed: 1,
  mode: VoiceMode.practice,
  contentId: text,
  contentType: 'route-test',
);
