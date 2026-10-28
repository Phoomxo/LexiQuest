import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/config/app_appearance_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy theme is retained and combined settings survive reopening',
    () async {
      SharedPreferences.setMockInitialValues({'app.appearance.mode': 'dark'});
      final shared = await SharedPreferences.getInstance();
      final controller = await AppAppearanceController.load(
        SharedPreferencesAppAppearancePreferences(shared),
      );
      addTearDown(controller.dispose);
      expect(controller.mode, AppAppearanceMode.dark);
      expect(controller.reducedMotion, isFalse);

      expect(
        await controller.apply(AppAppearanceMode.light, reducedMotion: true),
        isTrue,
      );
      final reopened = await AppAppearanceController.load(
        SharedPreferencesAppAppearancePreferences(shared),
      );
      addTearDown(reopened.dispose);
      expect(reopened.mode, AppAppearanceMode.light);
      expect(reopened.reducedMotion, isTrue);

      expect(await reopened.apply(AppAppearanceMode.dark), isTrue);
      expect(
        reopened.reducedMotion,
        isTrue,
        reason: 'Changing only the theme keeps the motion preference.',
      );
    },
  );

  test(
    'theme and motion apply together only after persistence acknowledges both',
    () async {
      final preferences = _Preferences();
      final controller = await AppAppearanceController.load(preferences);
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final pending = controller.apply(
        AppAppearanceMode.dark,
        reducedMotion: true,
      );
      expect(controller.mode, AppAppearanceMode.system);
      expect(controller.reducedMotion, isFalse);
      expect(notifications, 0);

      preferences.result.complete(true);
      expect(await pending, isTrue);
      expect(controller.mode, AppAppearanceMode.dark);
      expect(controller.reducedMotion, isTrue);
      expect(notifications, 1);
    },
  );

  for (final failure in [
    false,
    StateError('synthetic appearance write failure'),
  ]) {
    test(
      'failed combined save retains the complete applied settings: $failure',
      () async {
        final controller = await AppAppearanceController.load(
          _Preferences(failure: failure),
        );
        addTearDown(controller.dispose);
        expect(
          await controller.apply(AppAppearanceMode.dark, reducedMotion: true),
          isFalse,
        );
        expect(controller.mode, AppAppearanceMode.system);
        expect(controller.reducedMotion, isFalse);
      },
    );
  }

  test(
    'invalid combined record falls back to the legacy theme without enabling motion',
    () async {
      for (final invalid in [
        '{',
        '[]',
        '{"mode":"dark","reducedMotion":"yes"}',
      ]) {
        SharedPreferences.setMockInitialValues({
          'app.appearance.mode': 'light',
          'app.appearance.preferences.v1': invalid,
        });
        final controller = await AppAppearanceController.load(
          SharedPreferencesAppAppearancePreferences(
            await SharedPreferences.getInstance(),
          ),
        );
        expect(controller.mode, AppAppearanceMode.light);
        expect(controller.reducedMotion, isFalse);
        controller.dispose();
      }
    },
  );
}

final class _Preferences implements AppAppearancePreferences {
  _Preferences({this.failure});

  final Object? failure;
  final result = Completer<bool>();

  @override
  Future<({AppAppearanceMode mode, bool reducedMotion})> load() async =>
      (mode: AppAppearanceMode.system, reducedMotion: false);

  @override
  Future<bool> save(AppAppearanceMode mode, {required bool reducedMotion}) {
    final failure = this.failure;
    if (failure is Error) throw failure;
    if (failure is bool) return Future.value(failure);
    return result.future;
  }
}
