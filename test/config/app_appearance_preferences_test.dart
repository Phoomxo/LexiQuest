import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/config/app_appearance_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to the system theme and restores a saved mode', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesAppAppearancePreferences(
      await SharedPreferences.getInstance(),
    );

    expect(await preferences.load(), AppAppearanceMode.system);
    expect(await preferences.save(AppAppearanceMode.dark), isTrue);
    expect(await preferences.load(), AppAppearanceMode.dark);
  });

  test(
    'controller applies a mode only after persistence acknowledges it',
    () async {
      final preferences = _AppearancePreferences();
      final controller = await AppAppearanceController.load(preferences);
      addTearDown(controller.dispose);
      final pending = controller.apply(AppAppearanceMode.light);

      expect(controller.themeMode, ThemeMode.system);

      preferences.saveResult.complete(true);
      expect(await pending, isTrue);
      expect(controller.themeMode, ThemeMode.light);
    },
  );

  test('rejected and failed saves leave the applied mode unchanged', () async {
    for (final failure in [false, StateError('synthetic write failure')]) {
      final preferences = _AppearancePreferences(failure: failure);
      final controller = await AppAppearanceController.load(preferences);
      addTearDown(controller.dispose);

      expect(await controller.apply(AppAppearanceMode.dark), isFalse);
      expect(controller.themeMode, ThemeMode.system);
    }
  });
}

final class _AppearancePreferences implements AppAppearancePreferences {
  _AppearancePreferences({this.failure});

  final Object? failure;
  final saveResult = Completer<bool>();

  @override
  Future<AppAppearanceMode> load() async => AppAppearanceMode.system;

  @override
  Future<bool> save(AppAppearanceMode mode) {
    final failure = this.failure;
    if (failure is Error) throw failure;
    if (failure is bool) return Future<bool>.value(failure);
    return saveResult.future;
  }
}
