import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppAppearanceMode {
  system,
  light,
  dark;

  ThemeMode get themeMode => switch (this) {
    AppAppearanceMode.system => ThemeMode.system,
    AppAppearanceMode.light => ThemeMode.light,
    AppAppearanceMode.dark => ThemeMode.dark,
  };

  static AppAppearanceMode fromStored(String? value) => switch (value) {
    'light' => AppAppearanceMode.light,
    'dark' => AppAppearanceMode.dark,
    _ => AppAppearanceMode.system,
  };
}

typedef AppAppearanceSettings = ({AppAppearanceMode mode, bool reducedMotion});

abstract interface class AppAppearancePreferences {
  Future<AppAppearanceSettings> load();

  Future<bool> save(AppAppearanceMode mode, {required bool reducedMotion});
}

final class SharedPreferencesAppAppearancePreferences
    implements AppAppearancePreferences {
  SharedPreferencesAppAppearancePreferences(this._preferences);

  static const _legacyKey = 'app.appearance.mode';
  static const _key = 'app.appearance.preferences.v1';
  final SharedPreferences _preferences;

  @override
  Future<AppAppearanceSettings> load() async {
    await _preferences.reload();
    try {
      final decoded = jsonDecode(_preferences.getString(_key) ?? 'null');
      if (decoded is Map<String, dynamic> && decoded.length == 2) {
        final mode = decoded['mode'];
        final reducedMotion = decoded['reducedMotion'];
        if (mode is String &&
            AppAppearanceMode.values.any((value) => value.name == mode) &&
            reducedMotion is bool) {
          return (
            mode: AppAppearanceMode.fromStored(mode),
            reducedMotion: reducedMotion,
          );
        }
      }
    } on Object {
      // A damaged new record must not discard the previous theme preference.
    }
    return (
      mode: AppAppearanceMode.fromStored(_preferences.getString(_legacyKey)),
      reducedMotion: false,
    );
  }

  @override
  Future<bool> save(AppAppearanceMode mode, {required bool reducedMotion}) =>
      _preferences.setString(
        _key,
        jsonEncode({'mode': mode.name, 'reducedMotion': reducedMotion}),
      );
}

final class AppAppearanceController extends ChangeNotifier {
  AppAppearanceController._(this._preferences, this._settings);

  factory AppAppearanceController.system() => AppAppearanceController._(
    const _UnavailableAppearancePreferences(),
    (mode: AppAppearanceMode.system, reducedMotion: false),
  );

  static Future<AppAppearanceController> load(
    AppAppearancePreferences preferences,
  ) async {
    try {
      return AppAppearanceController._(preferences, await preferences.load());
    } catch (_) {
      return AppAppearanceController._(preferences, (
        mode: AppAppearanceMode.system,
        reducedMotion: false,
      ));
    }
  }

  final AppAppearancePreferences _preferences;
  AppAppearanceSettings _settings;

  AppAppearanceMode get mode => _settings.mode;
  ThemeMode get themeMode => _settings.mode.themeMode;
  bool get reducedMotion => _settings.reducedMotion;

  Future<bool> apply(AppAppearanceMode mode, {bool? reducedMotion}) async {
    final settings = (
      mode: mode,
      reducedMotion: reducedMotion ?? _settings.reducedMotion,
    );
    try {
      if (!await _preferences.save(
        settings.mode,
        reducedMotion: settings.reducedMotion,
      )) {
        return false;
      }
    } catch (_) {
      return false;
    }
    if (_settings != settings) {
      _settings = settings;
      notifyListeners();
    }
    return true;
  }
}

Future<AppAppearanceController> loadAppAppearanceController() async {
  try {
    return AppAppearanceController.load(
      SharedPreferencesAppAppearancePreferences(
        await SharedPreferences.getInstance(),
      ),
    );
  } catch (_) {
    return AppAppearanceController.system();
  }
}

final class AppAppearanceScope
    extends InheritedNotifier<AppAppearanceController> {
  const AppAppearanceScope({
    super.key,
    required AppAppearanceController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppAppearanceController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppAppearanceScope>()
      ?.notifier;

  static AppAppearanceController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'AppAppearanceScope was not found.');
    return controller!;
  }
}

final class _UnavailableAppearancePreferences
    implements AppAppearancePreferences {
  const _UnavailableAppearancePreferences();

  @override
  Future<AppAppearanceSettings> load() async =>
      (mode: AppAppearanceMode.system, reducedMotion: false);

  @override
  Future<bool> save(
    AppAppearanceMode mode, {
    required bool reducedMotion,
  }) async => false;
}
