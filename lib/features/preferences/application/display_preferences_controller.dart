import 'package:flutter/material.dart';

import '../domain/learner_preferences.dart';
import '../domain/learner_preferences_repository.dart';
import 'learner_preferences_use_cases.dart';

/// The single presentation controller over the durable learner-preference row.
/// It owns no persistence and never mutates experiment or learning authority.
final class DisplayPreferencesController extends ChangeNotifier {
  DisplayPreferencesController(this._preferences);

  final LearnerPreferencesUseCases _preferences;
  LearnerDisplayPreferences _display = LearnerDisplayPreferences.defaults();
  Future<void> _serial = Future<void>.value();
  bool _isInitialized = false;
  String? _ownerId;

  static ThemeMode get fallbackThemeMode => ThemeMode.system;

  bool get isInitialized => _isInitialized;

  ThemeMode get themeMode => switch (_display.themeMode) {
    LearnerThemePreference.system => ThemeMode.system,
    LearnerThemePreference.light => ThemeMode.light,
    LearnerThemePreference.dark => ThemeMode.dark,
  };

  bool get reducedMotionEnabled =>
      _display.motionMode == LearnerMotionPreference.reduced;

  Future<void> initialize() => _enqueue(() async {
    final saved = await _preferences.read();
    _replace(saved.display, ownerId: saved.ownerId, initialized: true);
  });

  Future<void> refreshAfterOwnerTransition() => _enqueue(() async {
    try {
      final saved = await _preferences.read();
      _replace(saved.display, ownerId: saved.ownerId, initialized: true);
    } on Object {
      _replace(
        LearnerDisplayPreferences.defaults(),
        ownerId: null,
        initialized: true,
      );
    }
  });

  Future<void> selectThemeMode(ThemeMode mode) {
    final expectedOwnerId = _ownerId;
    return _enqueue(() async {
      if (expectedOwnerId == null) {
        throw const LearnerPreferencesMutationUnavailable();
      }
      final selected = switch (mode) {
        ThemeMode.system => LearnerThemePreference.system,
        ThemeMode.light => LearnerThemePreference.light,
        ThemeMode.dark => LearnerThemePreference.dark,
      };
      if (_isInitialized &&
          _ownerId == expectedOwnerId &&
          _display.themeMode == selected) {
        return;
      }
      final saved = await _preferences.saveDisplayPreferences(
        expectedOwnerId: expectedOwnerId,
        themeMode: selected,
        motionMode: _display.motionMode,
      );
      _replace(saved.display, ownerId: saved.ownerId, initialized: true);
    });
  }

  Future<void> setReducedMotion(bool enabled) {
    final expectedOwnerId = _ownerId;
    return _enqueue(() async {
      if (expectedOwnerId == null) {
        throw const LearnerPreferencesMutationUnavailable();
      }
      final selected = enabled
          ? LearnerMotionPreference.reduced
          : LearnerMotionPreference.system;
      if (_isInitialized &&
          _ownerId == expectedOwnerId &&
          _display.motionMode == selected) {
        return;
      }
      final saved = await _preferences.saveDisplayPreferences(
        expectedOwnerId: expectedOwnerId,
        themeMode: _display.themeMode,
        motionMode: selected,
      );
      _replace(saved.display, ownerId: saved.ownerId, initialized: true);
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _serial.then((_) => operation());
    _serial = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  void _replace(
    LearnerDisplayPreferences display, {
    required String? ownerId,
    required bool initialized,
  }) {
    final changed =
        _display != display ||
        _ownerId != ownerId ||
        _isInitialized != initialized;
    _display = display;
    _ownerId = ownerId;
    _isInitialized = initialized;
    if (changed) notifyListeners();
  }
}
