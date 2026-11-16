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
  bool _disposed = false;
  int _pendingReads = 0;
  bool _readRequired = false;
  bool get isReading => _pendingReads > 0;
  bool get readRequired => _readRequired;
  bool get canEdit =>
      !_disposed &&
      _isInitialized &&
      !isReading &&
      !_readRequired &&
      _ownerId != null;
  String? _ownerId;

  static ThemeMode get fallbackThemeMode => ThemeMode.system;

  bool get isInitialized => _isInitialized;
  String? get ownerId => _ownerId;

  ThemeMode get themeMode => switch (_display.themeMode) {
    LearnerThemePreference.system => ThemeMode.system,
    LearnerThemePreference.light => ThemeMode.light,
    LearnerThemePreference.dark => ThemeMode.dark,
  };

  bool get reducedMotionEnabled =>
      _display.motionMode == LearnerMotionPreference.reduced;

  Future<void> initialize() {
    _pendingReads++;
    if (!_disposed && _isInitialized) notifyListeners();
    return _enqueue(() async {
      try {
        final saved = await _preferences.readDisplayPreferences();
        _readRequired = false;
        _replace(saved.display, ownerId: saved.ownerId, initialized: true);
      } on Object {
        _readRequired = true;
        rethrow;
      }
    }).whenComplete(() {
      _pendingReads--;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> refreshAfterOwnerTransition() async {
    try {
      await initialize();
    } on Object {
      _replace(
        LearnerDisplayPreferences.defaults(),
        ownerId: null,
        initialized: true,
      );
    }
  }

  Future<void> selectThemeMode(
    ThemeMode mode, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) {
    final expectedOwnerId = _ownerId;
    return _enqueue(() async {
      if (expectedOwnerId == null ||
          _readRequired ||
          !(mutationAllowed?.call() ?? true)) {
        throw const LearnerPreferencesMutationUnavailable();
      }
      final selected = switch (mode) {
        ThemeMode.system => LearnerThemePreference.system,
        ThemeMode.light => LearnerThemePreference.light,
        ThemeMode.dark => LearnerThemePreference.dark,
      };
      // A replacement controller may predate an acknowledged durable write.
      // Use the canonical companion field, and evaluate no-op against that row.
      final current = await _preferences.readDisplayPreferences(
        expectedOwnerId: expectedOwnerId,
      );
      if (_disposed || !(mutationAllowed?.call() ?? true)) {
        throw const LearnerPreferencesMutationUnavailable();
      }
      if (current.display.themeMode == selected) {
        _replace(current.display, ownerId: current.ownerId, initialized: true);
        return;
      }
      final saved = await _preferences.saveDisplayPreferences(
        expectedOwnerId: expectedOwnerId,
        themeMode: selected,
        motionMode: current.display.motionMode,
        mutationAllowed: () => !_disposed && (mutationAllowed?.call() ?? true),
      );
      _replace(saved.display, ownerId: saved.ownerId, initialized: true);
    });
  }

  Future<void> setReducedMotion(
    bool enabled, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) {
    final expectedOwnerId = _ownerId;
    return _enqueue(() async {
      if (expectedOwnerId == null ||
          _readRequired ||
          !(mutationAllowed?.call() ?? true)) {
        throw const LearnerPreferencesMutationUnavailable();
      }
      final selected = enabled
          ? LearnerMotionPreference.reduced
          : LearnerMotionPreference.system;
      final current = await _preferences.readDisplayPreferences(
        expectedOwnerId: expectedOwnerId,
      );
      if (_disposed || !(mutationAllowed?.call() ?? true)) {
        throw const LearnerPreferencesMutationUnavailable();
      }
      if (current.display.motionMode == selected) {
        _replace(current.display, ownerId: current.ownerId, initialized: true);
        return;
      }
      final saved = await _preferences.saveDisplayPreferences(
        expectedOwnerId: expectedOwnerId,
        themeMode: current.display.themeMode,
        motionMode: selected,
        mutationAllowed: () => !_disposed && (mutationAllowed?.call() ?? true),
      );
      _replace(saved.display, ownerId: saved.ownerId, initialized: true);
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    if (_disposed) {
      return Future<void>.error(StateError('Display preferences disposed.'));
    }
    final result = _serial.then((_) async {
      if (!_disposed) {
        try {
          await operation();
        } on Object {
          _readRequired = true;
          if (!_disposed) notifyListeners();
          rethrow;
        }
      }
    });
    _serial = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  void _replace(
    LearnerDisplayPreferences display, {
    required String? ownerId,
    required bool initialized,
  }) {
    if (_disposed) return;
    final changed =
        _display != display ||
        _ownerId != ownerId ||
        _isInitialized != initialized;
    _display = display;
    _ownerId = ownerId;
    _isInitialized = initialized;
    if (changed) notifyListeners();
  }

  /// Runtime shutdown must drain admitted storage work before closing the DB.
  Future<void> disposeAndDrain() {
    dispose();
    return _serial;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
