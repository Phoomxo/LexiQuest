import 'package:flutter/services.dart';

enum StudyReminderPreset { weekdaysEvening, weekendMorning }

typedef StudyReminderStatus = ({bool allowed, StudyReminderPreset? preset});

final class StudyReminders {
  StudyReminders({
    required this.databasePath,
    required this._activeOwner,
    required this._requestPermission,
  });

  static const _channel = MethodChannel('com.lexiquest.app/study_reminder');
  final String databasePath;
  final Future<String?> Function() _activeOwner;
  final Future<void> Function() _requestPermission;
  bool _requestingPermission = false;
  int _scopeGeneration = 0;

  void invalidateScope() => _scopeGeneration++;

  Future<StudyReminderStatus> status({required String ownerId}) async {
    await _requireOwner(ownerId);
    await reconcile();
    return _read('status', ownerId);
  }

  Future<StudyReminderStatus> enable({
    required String ownerId,
    required StudyReminderPreset preset,
    required bool Function() isCurrent,
  }) async {
    final generation = _scopeGeneration;
    void requireScope() {
      if (generation != _scopeGeneration || !isCurrent()) {
        throw StateError('Reminder request is no longer available');
      }
    }

    requireScope();
    if (_requestingPermission) {
      throw StateError('Reminder request is no longer available');
    }
    _requestingPermission = true;
    try {
      await _requireOwner(ownerId);
      final initial = await _read('status', ownerId);
      await _requireOwner(ownerId);
      requireScope();
      if (!initial.allowed) {
        await _requestPermission();
        await _requireOwner(ownerId);
        requireScope();
        final current = await _read('status', ownerId);
        requireScope();
        if (!current.allowed) return current;
      }
      await _requireOwner(ownerId);
      requireScope();
      return await _read('enable', ownerId, preset: preset);
    } finally {
      _requestingPermission = false;
    }
  }

  Future<StudyReminderStatus> disable({required String ownerId}) async {
    await _requireOwner(ownerId);
    return _read('disable', ownerId);
  }

  Future<void> reconcile() =>
      _channel.invokeMethod<void>('reconcile', {'databasePath': databasePath});

  Future<void> _requireOwner(String ownerId) async {
    if (ownerId.isEmpty || await _activeOwner() != ownerId) {
      throw StateError('Reminder owner changed');
    }
  }

  Future<StudyReminderStatus> _read(
    String operation,
    String ownerId, {
    StudyReminderPreset? preset,
  }) async {
    final response = await _channel
        .invokeMapMethod<String, Object?>(operation, {
          'databasePath': databasePath,
          'ownerId': ownerId,
          if (preset != null) 'preset': preset.name,
        });
    final allowed = response?['allowed'];
    final rawPreset = response?['preset'];
    if (allowed is! bool) throw StateError('Reminder status unavailable');
    final savedPreset = switch (rawPreset) {
      null => null,
      'weekdaysEvening' => StudyReminderPreset.weekdaysEvening,
      'weekendMorning' => StudyReminderPreset.weekendMorning,
      _ => throw StateError('Reminder status unavailable'),
    };
    if ((operation == 'enable' && (!allowed || savedPreset != preset)) ||
        (operation == 'disable' && savedPreset != null)) {
      throw StateError('Reminder change unconfirmed');
    }
    await _requireOwner(ownerId);
    return (allowed: allowed, preset: savedPreset);
  }
}
