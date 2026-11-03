import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../data/local/app_database.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../data/drift_study_reminder_repository.dart';
import '../domain/study_reminder.dart';

final class StudyReminderLease {
  const StudyReminderLease._(this.ownerId, this._current, this._invalidated);
  final String ownerId;
  final bool Function() _current;
  final Future<void> _invalidated;
  bool get isCurrent => _current();
}

final class StudyReminderView {
  const StudyReminderView({
    required this.lease,
    required this.setting,
    required this.platform,
    this.requestAck,
  });
  final StudyReminderLease lease;
  final StudyReminderSetting setting;
  final StudyReminderPlatformStatus platform;
  final StudyReminderRequestAck? requestAck;
}

final class StudyReminderChangeIntent {
  const StudyReminderChangeIntent._(
    this._issuer,
    this.lease,
    this.baseRevision,
    this.choice,
    this.updatedAtUtc,
  );
  final StudyReminderRuntime _issuer;
  final StudyReminderLease lease;
  final int baseRevision;
  final StudyReminderChoice choice;
  final DateTime updatedAtUtc;
}

final class StudyReminderRuntime {
  StudyReminderRuntime({
    required AppDatabase database,
    required DriftOwnerWriteCoordinator ownerWrites,
    required Stream<String?> ownerChanges,
    required this.platform,
    required this.nowUtc,
  }) : repository = DriftStudyReminderRepository(database, ownerWrites) {
    _owners = ownerChanges.listen(
      _observed,
      onError: (Object _) => _retire(),
      onDone: _retire,
    );
  }
  final DriftStudyReminderRepository repository;
  final StudyReminderPlatform platform;
  final DateTime Function() nowUtc;
  final _ready = Completer<void>();
  final _changes = StreamController<void>.broadcast(sync: true);
  StreamSubscription<String?>? _owners;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  String? _ownerId, _scopeToken, _scopeOwner, _ackOwner;
  StudyReminderRequestAck? _ack;
  var _generation = 0;
  var _foreground = false;
  var _permissionPending = false;
  Completer<void>? _permissionResumed;
  var _retired = false;
  var _invalidated = Completer<void>();

  Stream<void> watchChanges() => _changes.stream;
  bool get isRetired => _retired;
  String? get currentOwnerId => _ownerId;
  bool get isForeground => _foreground;
  bool get isRequestingPermission => _permissionPending;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _invalidateLeases() {
    if (!_invalidated.isCompleted) _invalidated.complete();
    _invalidated = Completer<void>();
    _generation++;
  }

  void _observed(String? owner) {
    if (_retired) return;
    final previous = _scopeToken;
    _ownerId = owner;
    _scopeToken = null;
    _scopeOwner = null;
    _ack = null;
    _ackOwner = null;
    _invalidateLeases();
    if (!_ready.isCompleted) _ready.complete();
    _notify();
    _background(() async {
      await platform.retire(scopeToken: previous);
    });
    if (_foreground && owner != null) _background(reconcileForeground);
  }

  void _retire() {
    if (_retired) return;
    final token = _scopeToken;
    _retired = true;
    _invalidateLeases();
    if (!_ready.isCompleted) _ready.complete();
    _notify();
    unawaited(platform.retire(scopeToken: token).catchError((Object _) {}));
  }

  void setForeground(bool value) {
    if (_retired || value == _foreground) return;
    _foreground = value;
    if (!_permissionPending) _invalidateLeases();
    if (value && _permissionResumed != null) {
      _permissionResumed!.complete();
      _permissionResumed = null;
    }
    _notify();
    if (value && !_permissionPending) _background(reconcileForeground);
  }

  void _background(Future<void> Function() operation) {
    unawaited(
      Future<void>.sync(operation).catchError((Object _) {
        if (!_retired) _notify();
      }),
    );
  }

  Future<StudyReminderLease> _capture(
    String owner,
    bool Function() callerCurrent,
  ) async {
    await _ready.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        throw const StudyReminderException(
          StudyReminderFailureCode.unavailable,
        );
      },
    );
    final generation = _generation;
    final invalidated = _invalidated.future;
    if (!_foreground) {
      throw const StudyReminderException(StudyReminderFailureCode.ownerChanged);
    }
    bool current() =>
        !_retired &&
        (_foreground || _permissionPending) &&
        generation == _generation &&
        owner == _ownerId &&
        callerCurrent();
    if (!current()) {
      throw const StudyReminderException(StudyReminderFailureCode.ownerChanged);
    }
    await repository.readForOwner(ownerId: owner, stillCurrent: current);
    return StudyReminderLease._(owner, current, invalidated);
  }

  void _require(StudyReminderLease lease) {
    if (!lease.isCurrent) {
      throw const StudyReminderException(StudyReminderFailureCode.ownerChanged);
    }
  }

  Future<StudyReminderPlatformStatus> _requestOwnedPermission(
    StudyReminderLease lease,
  ) async {
    _permissionPending = true;
    _notify();
    final cancelled = lease._invalidated.then<StudyReminderPlatformStatus>(
      (_) => throw const StudyReminderException(
        StudyReminderFailureCode.ownerChanged,
      ),
    );
    try {
      final status = await Future.any([
        platform.requestPermission(),
        cancelled,
      ]);
      if (!_foreground) {
        _permissionResumed ??= Completer<void>();
        await Future.any([
          _permissionResumed!.future,
          lease._invalidated.then<void>(
            (_) => throw const StudyReminderException(
              StudyReminderFailureCode.ownerChanged,
            ),
          ),
        ]);
      }
      _require(lease);
      return status;
    } finally {
      _permissionPending = false;
      _permissionResumed = null;
      _notify();
    }
  }

  Future<StudyReminderView> load({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async {
    final lease = await _capture(expectedOwnerId, stillCurrent);
    final setting = await repository.readForOwner(
      ownerId: expectedOwnerId,
      stillCurrent: () => lease.isCurrent,
    );
    final status = await platform.inspect();
    _require(lease);
    return StudyReminderView(
      lease: lease,
      setting: setting,
      platform: status,
      requestAck:
          _ackOwner == expectedOwnerId && _ack?.revision == setting.revision
          ? _ack
          : null,
    );
  }

  Future<StudyReminderChangeIntent> prepareChange({
    required String expectedOwnerId,
    required StudyReminderChoice choice,
    required bool Function() stillCurrent,
  }) async {
    choice.validate();
    await repository.requireCommittedBoundary();
    final lease = await _capture(expectedOwnerId, stillCurrent);
    final setting = await repository.readForOwner(
      ownerId: expectedOwnerId,
      stillCurrent: () => lease.isCurrent,
    );
    final now = nowUtc();
    if (!now.isUtc || now.millisecondsSinceEpoch < 0) {
      throw const StudyReminderException(StudyReminderFailureCode.unavailable);
    }
    _require(lease);
    return StudyReminderChangeIntent._(
      this,
      lease,
      setting.revision,
      choice,
      DateTime.fromMillisecondsSinceEpoch(
        now.millisecondsSinceEpoch,
        isUtc: true,
      ),
    );
  }

  Future<String> _scope(StudyReminderLease lease) async {
    _require(lease);
    if (_scopeToken != null && _scopeOwner == lease.ownerId) {
      return _scopeToken!;
    }
    debugPrint('LexiQuestReminder scope nativeDatabasePath');
    final path = await repository.nativeDatabasePath(
      ownerId: lease.ownerId,
      stillCurrent: () => lease.isCurrent,
    );
    _require(lease);
    if (path == null) {
      debugPrint('LexiQuestReminder scope nativeDatabasePath unavailable');
      throw const StudyReminderException(
        StudyReminderFailureCode.platformUnavailable,
      );
    }
    debugPrint('LexiQuestReminder scope bindScope');
    final token = await platform.bindScope(
      databasePath: path,
      ownerId: lease.ownerId,
    );
    debugPrint('LexiQuestReminder scope bound');
    if (!lease.isCurrent) {
      await platform.retire(scopeToken: token);
      _require(lease);
    }
    _scopeToken = token;
    _scopeOwner = lease.ownerId;
    return token;
  }

  Future<StudyReminderView> apply(
    StudyReminderChangeIntent intent,
  ) => _enqueue(() async {
    if (!identical(intent._issuer, this)) {
      throw const StudyReminderException(StudyReminderFailureCode.ownerChanged);
    }
    _require(intent.lease);
    await repository.requireCommittedBoundary();
    var status = await platform.inspect();
    _require(intent.lease);
    if (intent.choice.enabled) {
      if (!status.supported) {
        throw const StudyReminderException(
          StudyReminderFailureCode.platformUnavailable,
        );
      }
      if (!status.notificationsAllowed) {
        status = await _requestOwnedPermission(intent.lease);
      }
      _require(intent.lease);
      if (!status.notificationsAllowed) {
        throw const StudyReminderException(
          StudyReminderFailureCode.permissionDenied,
        );
      }
    }
    final saved = await repository.writeForOwner(
      ownerId: intent.lease.ownerId,
      baseRevision: intent.baseRevision,
      choice: intent.choice,
      updatedAtUtc: intent.updatedAtUtc,
      stillCurrent: () => intent.lease.isCurrent,
    );
    _require(intent.lease);
    var stage = 'scope';
    try {
      final token = await _scope(intent.lease);
      stage = saved.enabled ? 'schedule' : 'cancel';
      final ack = saved.enabled
          ? await platform.schedule(scopeToken: token, revision: saved.revision)
          : await platform.cancel(scopeToken: token, revision: saved.revision);
      stage = 'ack';
      _require(intent.lease);
      if (ack.revision != saved.revision) {
        throw const StudyReminderException(
          StudyReminderFailureCode.requestUnconfirmed,
        );
      }
      _ack = ack;
      _ackOwner = saved.ownerId;
      return StudyReminderView(
        lease: intent.lease,
        setting: saved,
        platform: status,
        requestAck: ack,
      );
    } on StudyReminderException catch (error) {
      debugPrint(
        'LexiQuestReminder apply $stage rejected ${error.code.name}',
      );
      if (error.code == StudyReminderFailureCode.ownerChanged) rethrow;
      throw const StudyReminderException(
        StudyReminderFailureCode.requestUnconfirmed,
      );
    } on Object catch (error) {
      debugPrint('LexiQuestReminder apply $stage failed ${error.runtimeType}');
      throw const StudyReminderException(
        StudyReminderFailureCode.requestUnconfirmed,
      );
    }
  });

  Future<void> reconcileForeground() async {
    if (_retired || !_foreground || _ownerId == null) return;
    final owner = _ownerId!;
    final lease = await _capture(owner, () => true);
    await _enqueue(() async {
      _require(lease);
      final setting = await repository.readForOwner(
        ownerId: owner,
        stillCurrent: () => lease.isCurrent,
      );
      final status = await platform.inspect();
      _require(lease);
      if (!setting.enabled || setting.revision == 0 || !status.supported) {
        await platform.retire(scopeToken: _scopeToken);
        _scopeToken = null;
        _scopeOwner = null;
        return;
      }
      final token = await _scope(lease);
      final ack = status.notificationsAllowed
          ? await platform.schedule(
              scopeToken: token,
              revision: setting.revision,
            )
          : await platform.cancel(
              scopeToken: token,
              revision: setting.revision,
            );
      _require(lease);
      _ack = ack;
      _ackOwner = owner;
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    unawaited(
      result.then<void>(
        (_) => _notify(),
        onError: (Object _, StackTrace _) => _notify(),
      ),
    );
    return result;
  }

  Future<void> dispose() {
    if (_closing != null) return _closing!;
    _retired = true;
    _invalidateLeases();
    if (!_ready.isCompleted) _ready.complete();
    _notify();
    return _closing = _close();
  }

  Future<void> _close() async {
    await _owners?.cancel();
    await _tail;
    await _changes.close();
  }
}
