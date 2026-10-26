import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_appearance_preferences.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

const _screenSize = Size(800, 600);
const _verticalHinge = DisplayFeature(
  bounds: Rect.fromLTRB(390, 0, 410, 600),
  type: DisplayFeatureType.hinge,
  state: DisplayFeatureState.unknown,
);
const _horizontalHinge = DisplayFeature(
  bounds: Rect.fromLTRB(0, 290, 800, 310),
  type: DisplayFeatureType.hinge,
  state: DisplayFeatureState.unknown,
);

void main() {
  testWidgets('vertical occluding hinge confines app content to one pane', (
    tester,
  ) async {
    _configureView(tester, const [_verticalHinge]);
    await tester.pumpWidget(MyApp(dependencies: _dependencies()));
    await tester.pumpAndSettle();

    expect(_appSurfaceRect(tester), const Rect.fromLTWH(0, 0, 390, 600));
  });

  testWidgets('horizontal occluding hinge confines app content to one pane', (
    tester,
  ) async {
    _configureView(tester, const [_horizontalHinge]);
    await tester.pumpWidget(MyApp(dependencies: _dependencies()));
    await tester.pumpAndSettle();

    expect(_appSurfaceRect(tester), const Rect.fromLTWH(0, 0, 800, 290));
  });

  testWidgets('no display feature preserves the current full width behavior', (
    tester,
  ) async {
    _configureView(tester, const []);
    await tester.pumpWidget(MyApp(dependencies: _dependencies()));
    await tester.pumpAndSettle();

    expect(_appSurfaceRect(tester), Offset.zero & _screenSize);
  });

  testWidgets(
    'display feature rebuild preserves navigation and appearance state',
    (tester) async {
      _configureView(tester, const []);
      final dependencies = _dependencies();
      final appearance = await AppAppearanceController.load(
        _AppearancePreferences(),
      );

      await tester.pumpWidget(
        MyApp(dependencies: dependencies, appearance: appearance),
      );
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('fold-navigation-marker')),
        ),
      );
      await tester.pumpAndSettle();
      expect(_materialApp(tester).themeMode, ThemeMode.light);

      tester.view.displayFeatures = const [_verticalHinge];
      await tester.pumpAndSettle();

      expect(find.text('fold-navigation-marker'), findsOneWidget);
      expect(_materialApp(tester).themeMode, ThemeMode.light);
      expect(_appSurfaceRect(tester), const Rect.fromLTWH(0, 0, 390, 600));

      expect(await appearance.apply(AppAppearanceMode.dark), isTrue);
      tester.view.displayFeatures = const [_horizontalHinge];
      await tester.pumpAndSettle();

      expect(find.text('fold-navigation-marker'), findsOneWidget);
      expect(_materialApp(tester).themeMode, ThemeMode.dark);
      expect(_appSurfaceRect(tester), const Rect.fromLTWH(0, 0, 800, 290));

      await tester.pumpWidget(const SizedBox.shrink());
      appearance.dispose();
    },
  );
}

void _configureView(WidgetTester tester, List<DisplayFeature> features) {
  tester.view
    ..physicalSize = _screenSize
    ..devicePixelRatio = 1
    ..displayFeatures = features;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetDisplayFeatures);
}

Rect _appSurfaceRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey<String>('adaptive-app-surface')));

MaterialApp _materialApp(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp));

AppDependencies _dependencies() => AppDependencies(
  runtimeStatus: const AppRuntimeStatus(
    localData: RuntimeAvailability.ready,
    firebase: RuntimeAvailability.unavailable,
    supabase: RuntimeAvailability.unavailable,
    backends: RuntimeAvailability.unavailable,
  ),
  config: null,
  guestSessionService: const _GuestSession(),
);

final class _AppearancePreferences implements AppAppearancePreferences {
  @override
  Future<AppAppearanceMode> load() async => AppAppearanceMode.light;

  @override
  Future<bool> save(AppAppearanceMode mode) async => true;
}

final class _GuestSession implements GuestSessionService {
  const _GuestSession();

  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'fold-test');
}
