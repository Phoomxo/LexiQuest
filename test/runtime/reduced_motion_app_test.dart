import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/config/app_appearance_preferences.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets(
    'saved motion preference reaches the app and keeps the current route',
    (tester) async {
      final appearance = await _appearance();
      addTearDown(appearance.dispose);
      await tester.pumpWidget(
        MyApp(dependencies: _dependencies(), appearance: appearance),
      );
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('existing-route')),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        await appearance.apply(AppAppearanceMode.dark, reducedMotion: true),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(find.text('existing-route'), findsOneWidget);
      expect(MediaQuery.disableAnimationsOf(_surfaceContext(tester)), isTrue);
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .themeAnimationDuration,
        Duration.zero,
      );
    },
  );

  testWidgets(
    'reduced motion completes normal push and pop without a timed transition',
    (tester) async {
      final appearance = await _appearance();
      addTearDown(appearance.dispose);
      await appearance.apply(AppAppearanceMode.system, reducedMotion: true);
      await tester.pumpWidget(
        MyApp(dependencies: _dependencies(), appearance: appearance),
      );
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final route = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('instant-route')),
      );
      navigator.push(route);
      await tester.pump();
      expect(route.transitionDuration, Duration.zero);
      expect(route.animation!.value, 1);
      expect(find.text('instant-route').hitTestable(), findsOneWidget);
      expect(route.reverseTransitionDuration, Duration.zero);
      navigator.pop();
      await tester.pump();
      expect(find.text('instant-route'), findsNothing);
    },
  );

  for (final (label, features) in [
    (
      'disableAnimations',
      const FakeAccessibilityFeatures(disableAnimations: true),
    ),
    ('reduceMotion', const FakeAccessibilityFeatures(reduceMotion: true)),
  ]) {
    testWidgets(
      'system $label still reduces motion when the app preference is off',
      (tester) async {
        final appearance = await _appearance();
        addTearDown(appearance.dispose);
        await tester.pumpWidget(
          MyApp(dependencies: _dependencies(), appearance: appearance),
        );
        await tester.pumpAndSettle();
        expect(appearance.reducedMotion, isFalse);

        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            features;
        addTearDown(
          tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pump();
        expect(MediaQuery.disableAnimationsOf(_surfaceContext(tester)), isTrue);
        expect(
          tester
              .widget<MaterialApp>(find.byType(MaterialApp))
              .themeAnimationDuration,
          Duration.zero,
        );

        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures();
        await tester.pump();
        expect(
          MediaQuery.disableAnimationsOf(_surfaceContext(tester)),
          isFalse,
        );
      },
    );
  }
}

BuildContext _surfaceContext(WidgetTester tester) =>
    tester.element(find.byKey(const ValueKey<String>('adaptive-app-surface')));

Future<AppAppearanceController> _appearance() async {
  SharedPreferences.setMockInitialValues({});
  return AppAppearanceController.load(
    SharedPreferencesAppAppearancePreferences(
      await SharedPreferences.getInstance(),
    ),
  );
}

AppDependencies _dependencies() => AppDependencies(
  runtimeStatus: const AppRuntimeStatus(
    localData: RuntimeAvailability.ready,
    firebase: RuntimeAvailability.unavailable,
    supabase: RuntimeAvailability.unavailable,
    backends: RuntimeAvailability.unavailable,
  ),
  config: null,
  guestSessionService: const _Guest(),
);

final class _Guest implements GuestSessionService {
  const _Guest();

  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-motion');
}
