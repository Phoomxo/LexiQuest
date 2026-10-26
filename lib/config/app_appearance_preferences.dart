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

abstract interface class AppAppearancePreferences {
  Future<AppAppearanceMode> load();

  Future<bool> save(AppAppearanceMode mode);
}

final class SharedPreferencesAppAppearancePreferences
    implements AppAppearancePreferences {
  SharedPreferencesAppAppearancePreferences(this._preferences);

  static const _key = 'app.appearance.mode';
  final SharedPreferences _preferences;

  @override
  Future<AppAppearanceMode> load() async =>
      AppAppearanceMode.fromStored(_preferences.getString(_key));

  @override
  Future<bool> save(AppAppearanceMode mode) =>
      _preferences.setString(_key, mode.name);
}

final class AppAppearanceController extends ChangeNotifier {
  AppAppearanceController._(this._preferences, this._mode);

  factory AppAppearanceController.system() => AppAppearanceController._(
    const _UnavailableAppearancePreferences(),
    AppAppearanceMode.system,
  );

  static Future<AppAppearanceController> load(
    AppAppearancePreferences preferences,
  ) async {
    try {
      return AppAppearanceController._(preferences, await preferences.load());
    } catch (_) {
      return AppAppearanceController._(preferences, AppAppearanceMode.system);
    }
  }

  final AppAppearancePreferences _preferences;
  AppAppearanceMode _mode;

  AppAppearanceMode get mode => _mode;
  ThemeMode get themeMode => _mode.themeMode;

  Future<bool> apply(AppAppearanceMode mode) async {
    try {
      if (!await _preferences.save(mode)) return false;
    } catch (_) {
      return false;
    }
    if (_mode != mode) {
      _mode = mode;
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
  Future<AppAppearanceMode> load() async => AppAppearanceMode.system;

  @override
  Future<bool> save(AppAppearanceMode mode) async => false;
}
