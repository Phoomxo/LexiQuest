import 'dart:async';

import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../data/local/app_database.dart' as db;
import '../features/identity/data/drift_owner_write_coordinator.dart';
import '../features/identity/domain/local_owner_repository.dart';
import '../features/learning_profile/domain/learning_timezone.dart';
import '../features/motivation/application/streak_use_cases.dart';
import '../features/motivation/data/drift_motivation_scope.dart';
import '../features/motivation/data/drift_streak_repository.dart';
import '../features/motivation/domain/motivation_snapshot.dart';
import '../features/quest/application/quest_catalog_provider.dart';
import '../features/quest/application/quest_use_cases.dart';
import '../features/quest/data/drift_quest_repository.dart';
import '../features/quest/domain/quest_models.dart';

final class MotivationLease {
  const MotivationLease._(
    this.ownerId,
    this._readCurrent,
    this._writeCurrent,
    this._issuer,
  );
  final String ownerId;
  final bool Function() _readCurrent, _writeCurrent;
  final MotivationRuntime _issuer;
  bool get isCurrent => _writeCurrent();
}

final class MotivationView {
  MotivationView._({
    required this.lease,
    required this.motivation,
    required List<QuestInstance> history,
    required this.evaluatedAtUtc,
  }) : history = List.unmodifiable(history);
  final MotivationLease lease;
  final MotivationSnapshot motivation;
  final List<QuestInstance> history;
  final DateTime evaluatedAtUtc;
  String get ownerId => lease.ownerId;
  String? get protectableDay {
    if (motivation.state.freezeCount < 1) return null;
    final local = timezone.TZDateTime.from(
      evaluatedAtUtc,
      timezone.getLocation(motivation.timezoneId),
    );
    final yesterday = DateTime.utc(
      local.year,
      local.month,
      local.day,
    ).subtract(const Duration(days: 1));
    final label = motivationDayLabel(yesterday);
    final previous = motivationDayLabel(
      yesterday.subtract(const Duration(days: 1)),
    );
    if (motivation.protectedDays.contains(label) ||
        motivation.learningDays.any((day) => day.learningDay == label) ||
        !motivation.learningDays.any(
          (day) =>
              day.learningDay == previous &&
              day.timezoneId == motivation.timezoneId,
        )) {
      return null;
    }
    return label;
  }
}

final class MotivationProtection {
  const MotivationProtection._(this.intent, this.lease, this._issuer);
  final FreezeProtectionIntent intent;
  final MotivationLease lease;
  final MotivationRuntime _issuer;
}

final class MotivationRuntime {
  MotivationRuntime({
    required this.database,
    required this.ownerWrites,
    required LocalOwnerRepository owners,
    required this.nowUtc,
    required this.generateId,
    Stream<String?>? ownerChanges,
    this.onLocalMutation,
  }) {
    if (!identical(database, ownerWrites.database)) {
      throw ArgumentError('Motivation requires the canonical owner database');
    }
    questRepository = DriftQuestRepository(
      database,
      ownerWrites: ownerWrites,
      nowUtc: _now,
    );
    quest = QuestUseCases(
      repository: questRepository,
      owners: owners,
      generateId: generateId,
      nowUtc: _now,
      timezoneId: 'UTC',
      resolveTimezoneId: (ownerId) async {
        final profile = await (database.select(
          database.learningProfiles,
        )..where((row) => row.ownerId.equals(ownerId))).getSingleOrNull();
        return requireLearningTimezone(profile?.learningTimezoneId ?? 'UTC');
      },
    );
    streakRepository = DriftStreakRepository(
      database,
      ownerWrites: ownerWrites,
      quests: questRepository,
      nowUtc: _now,
    );
    streak = StreakUseCases(
      repository: streakRepository,
      nowUtc: _now,
      generateId: generateId,
    );
    _ownerSubscription = (ownerChanges ?? _watchOwners(database)).listen(
      _ownerObserved,
      onError: (Object _) => _retire(),
      onDone: _retire,
    );
    _dataSubscription = database
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            database.questDefinitions,
            database.questInstances,
            database.questObjectiveProgress,
            database.rewardTransactions,
            database.learningDayLog,
          ]),
        )
        .listen(
          (_) {
            if (_disposed) return;
            _dataGeneration++;
            if (!_writing) _notify();
          },
          onError: (Object _) => _retire(),
          onDone: _retire,
        );
    if (_retired) {
      unawaited(_ownerSubscription?.cancel());
      unawaited(_dataSubscription?.cancel());
    }
  }

  final db.AppDatabase database;
  final DriftOwnerWriteCoordinator ownerWrites;
  final DateTime Function() nowUtc;
  final String Function() generateId;
  final void Function()? onLocalMutation;
  late final DriftQuestRepository questRepository;
  late final QuestUseCases quest;
  late final DriftStreakRepository streakRepository;
  late final StreakUseCases streak;

  final _ownerReady = Completer<void>();
  final _changes = StreamController<void>.broadcast(sync: true);
  final _actions =
      <({String ownerId, int epoch, bool seed}), _MotivationAction>{};
  StreamSubscription<String?>? _ownerSubscription;
  StreamSubscription<dynamic>? _dataSubscription;
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposeFuture;
  String? _ownerId;
  MotivationFailureCode? _activationFailure;
  var _epoch = 0;
  var _dataGeneration = 0;
  var _foreground = false;
  var _retired = false;
  var _disposed = false;
  var _writing = false;

  bool get isForeground => _foreground;
  bool get isRetired => _retired || _disposed;
  String? get currentOwnerId => _ownerId;
  MotivationFailureCode? get activationFailure => _activationFailure;
  bool get isActivating =>
      _actions.values.any((action) => action.epoch == _epoch);
  Stream<void> watchChanges() => _changes.stream;

  void _ownerObserved(String? ownerId) {
    if (isRetired) return;
    _ownerId = ownerId;
    _epoch++;
    _activationFailure = null;
    if (!_ownerReady.isCompleted) _ownerReady.complete();
    _notify();
    if (_foreground && ownerId != null) _activateObservedOwner(ownerId, _epoch);
  }

  void setForeground(bool value) {
    if (isRetired || _foreground == value) return;
    _foreground = value;
    _epoch++;
    _activationFailure = null;
    _notify();
    if (value && _ownerId != null) _activateObservedOwner(_ownerId!, _epoch);
  }

  void _activateObservedOwner(String ownerId, int epoch) {
    unawaited(
      activate(
        ownerId: ownerId,
        stillCurrent: () =>
            !isRetired && _foreground && epoch == _epoch && _ownerId == ownerId,
      ).then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (isRetired || epoch != _epoch) return;
          _activationFailure = MotivationFailureCode.unavailable;
          _notify();
        },
      ),
    );
  }

  void _retire() {
    if (isRetired) return;
    _retired = true;
    _epoch++;
    _ownerId = null;
    _activationFailure = MotivationFailureCode.unavailable;
    if (!_ownerReady.isCompleted) _ownerReady.complete();
    _notify();
    unawaited(_ownerSubscription?.cancel());
    unawaited(_dataSubscription?.cancel());
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<MotivationLease> captureOwner({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async {
    if (isRetired || !stillCurrent()) _unavailable();
    await _ownerReady.future.timeout(
      const Duration(seconds: 2),
      onTimeout: _unavailable,
    );
    final epoch = _epoch;
    bool readable() =>
        !isRetired &&
        epoch == _epoch &&
        _ownerId == expectedOwnerId &&
        stillCurrent();
    if (!readable()) _ownerChanged();
    await requireMotivationOwner(
      database,
      ownerWrites,
      expectedOwnerId,
      readable,
    );
    if (!readable()) _ownerChanged();
    return MotivationLease._(
      expectedOwnerId,
      readable,
      () => readable() && _foreground,
      this,
    );
  }

  void _requireLease(MotivationLease lease, {bool writing = true}) {
    if (!identical(lease._issuer, this) ||
        !(writing ? lease.isCurrent : lease._readCurrent())) {
      _ownerChanged();
    }
  }

  Future<MotivationView> load({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async {
    final lease = await captureOwner(
      expectedOwnerId: expectedOwnerId,
      stillCurrent: stillCurrent,
    );
    return _load(lease);
  }

  Future<MotivationView> _load(MotivationLease lease) async {
    _requireLease(lease, writing: false);
    final at = _now();
    final value = await database.transaction(() async {
      final history = await questRepository.getAllInstances(lease.ownerId);
      final motivation = await streakRepository.read(
        expectedOwnerId: lease.ownerId,
        nowUtc: at,
        stillCurrent: lease._readCurrent,
      );
      return MotivationView._(
        lease: lease,
        motivation: motivation,
        history: history,
        evaluatedAtUtc: at,
      );
    });
    await requireMotivationOwner(
      database,
      ownerWrites,
      lease.ownerId,
      lease._readCurrent,
    );
    _requireLease(lease, writing: false);
    return value;
  }

  Future<void> activate({
    required String ownerId,
    required bool Function() stillCurrent,
  }) => _request(ownerId: ownerId, stillCurrent: stillCurrent, seed: true);

  Future<void> beforeLearningAnswer({
    required String ownerId,
    required String sessionId,
    required bool Function() stillCurrent,
  }) async {
    if (!await _ordinarySession(ownerId, sessionId)) return;
    await _request(
      ownerId: ownerId,
      stillCurrent: stillCurrent,
      seed: true,
      sessionId: sessionId,
    );
  }

  Future<void> afterLearningAnswer({
    required String ownerId,
    required String sessionId,
    required bool Function() stillCurrent,
  }) async {
    if (!await _ordinarySession(ownerId, sessionId)) return;
    await _request(
      ownerId: ownerId,
      stillCurrent: stillCurrent,
      seed: false,
      sessionId: sessionId,
    );
  }

  Future<bool> _ordinarySession(String ownerId, String sessionId) async {
    if (isRetired || !_foreground || await ownerWrites.hasAmbientTransaction()) {
      return false;
    }
    final session = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals(sessionId))).getSingleOrNull();
    if (session == null ||
        session.ownerId != ownerId ||
        session.activityType.trim().isEmpty ||
        session.activityType == 'assessment' ||
        !{'active', 'completed'}.contains(session.state)) {
      return false;
    }
    final controlled = await database
        .customSelect(
          'SELECT 1 AS controlled FROM assessment_runs WHERE learning_session_id=? '
          'UNION ALL SELECT 1 AS controlled FROM measurement_opportunities '
          'WHERE learning_session_id=? LIMIT 1',
          variables: [Variable<String>(sessionId), Variable<String>(sessionId)],
        )
        .getSingleOrNull();
    return controlled == null;
  }

  Future<void> _request({
    required String ownerId,
    required bool Function() stillCurrent,
    required bool seed,
    String? sessionId,
  }) async {
    if (await ownerWrites.hasAmbientTransaction()) _unavailable();
    final lease = await captureOwner(
      expectedOwnerId: ownerId,
      stillCurrent: stillCurrent,
    );
    _requireLease(lease);
    final key = (ownerId: ownerId, epoch: _epoch, seed: seed);
    if (sessionId != null && !await _ordinarySession(ownerId, sessionId)) {
      return;
    }
    _requireLease(lease);
    final request = _MotivationRequest(lease, sessionId);
    var action = _actions[key];
    if (action == null || !action.accepting) {
      action = _MotivationAction(ownerId, _epoch, seed);
      action.requests.add(request);
      _actions[key] = action;
      final issued = action;
      action.completion = _enqueue(() => _execute(issued));
      unawaited(
        action.completion.then<void>(
          (_) {
            if (identical(_actions[key], issued)) _actions.remove(key);
          },
          onError: (Object _, StackTrace _) {
            if (identical(_actions[key], issued)) _actions.remove(key);
          },
        ),
      );
    } else {
      action.requests.add(request);
    }
    await action.completion;
    _requireLease(lease);
  }

  Future<void> _execute(_MotivationAction action) async {
    try {
      while (true) {
        final requested = action.requests.length;
        await _executePass(action);
        if (requested == action.requests.length) return;
      }
    } finally {
      action.accepting = false;
    }
  }

  Future<void> _executePass(_MotivationAction action) async {
    if (isRetired || !_foreground || action.epoch != _epoch) _ownerChanged();
    for (var index = 0; index < action.requests.length; index++) {
      final request = action.requests[index];
      if (!request.lease.isCurrent) continue;
      request.admitted =
          request.sessionId == null ||
          await _ordinarySession(action.ownerId, request.sessionId!);
    }
    bool current() =>
        !isRetired &&
        _foreground &&
        action.epoch == _epoch &&
        action.requests.any(
          (request) => request.admitted && request.lease.isCurrent,
        );
    if (!current()) return;
    await requireMotivationOwner(
      database,
      ownerWrites,
      action.ownerId,
      current,
    );
    if (action.seed) {
      for (final definition in QuestCatalogProvider.allQuests) {
        if (!current()) _ownerChanged();
        await quest.startQuest(
          definition,
          expectedOwnerId: action.ownerId,
          stillCurrent: current,
        );
      }
    } else if ((await questRepository.getAllInstances(
      action.ownerId,
    )).isEmpty) {
      return;
    }
    if (!current()) _ownerChanged();
    await quest.reconcile(
      expectedOwnerId: action.ownerId,
      catalog: QuestCatalogProvider.allQuests,
      stillCurrent: current,
    );
    await streak.reconcileRewards(
      expectedOwnerId: action.ownerId,
      stillCurrent: current,
    );
    await requireMotivationOwner(
      database,
      ownerWrites,
      action.ownerId,
      current,
    );
    _activationFailure = null;
  }

  Future<void> _enqueue(
    Future<void> Function() operation, {
    bool notifyAlways = false,
  }) {
    final next = _tail.then((_) async {
      if (isRetired) _unavailable();
      final before = _dataGeneration;
      _writing = true;
      try {
        await operation();
        if (notifyAlways || _dataGeneration != before) onLocalMutation?.call();
      } finally {
        _writing = false;
        if (!isRetired) _notify();
      }
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  MotivationProtection prepareProtection({
    required MotivationView view,
    required String protectedDay,
    required bool Function() stillCurrent,
  }) {
    _requireLease(view.lease);
    final intent = streak.prepareProtection(
      snapshot: view.motivation,
      protectedDay: protectedDay,
      stillCurrent: () => view.lease.isCurrent && stillCurrent(),
    );
    return MotivationProtection._(intent, view.lease, this);
  }

  Future<MotivationView> protect(MotivationProtection protection) async {
    if (!identical(protection._issuer, this)) _ownerChanged();
    _requireLease(protection.lease);
    if (!protection.intent.stillCurrent() ||
        await ownerWrites.hasAmbientTransaction()) {
      _unavailable();
    }
    await _enqueue(() async {
      _requireLease(protection.lease);
      if (!protection.intent.stillCurrent()) _ownerChanged();
      await streak.protect(protection.intent);
      _requireLease(protection.lease);
    }, notifyAlways: true);
    return _load(protection.lease);
  }

  DateTime _now() {
    final at = nowUtc();
    if (!at.isUtc || at.millisecondsSinceEpoch < 0) {
      throw const MotivationException(MotivationFailureCode.invalid);
    }
    return DateTime.fromMillisecondsSinceEpoch(
      at.millisecondsSinceEpoch,
      isUtc: true,
    );
  }

  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    _disposed = true;
    _epoch++;
    if (!_ownerReady.isCompleted) _ownerReady.complete();
    _notify();
    return _disposeFuture = _close();
  }

  Future<void> _close() async {
    await _ownerSubscription?.cancel();
    await _dataSubscription?.cancel();
    await _tail;
    await _changes.close();
  }

  Never _ownerChanged() =>
      throw const MotivationException(MotivationFailureCode.ownerChanged);
  Never _unavailable() =>
      throw const MotivationException(MotivationFailureCode.unavailable);
}

final class _MotivationRequest {
  _MotivationRequest(this.lease, this.sessionId);
  final MotivationLease lease;
  final String? sessionId;
  var admitted = true;
}

final class _MotivationAction {
  _MotivationAction(this.ownerId, this.epoch, this.seed);
  final String ownerId;
  final int epoch;
  final bool seed;
  var accepting = true;
  final requests = <_MotivationRequest>[];
  late final Future<void> completion;
}

Stream<String?> _watchOwners(db.AppDatabase database) =>
    Stream<String?>.multi((events) {
      final invalidations = database
          .tableUpdates(
            TableUpdateQuery.onAllTables([
              database.localOwners,
              database.runtimeFlags,
              database.learningProfiles,
            ]),
          )
          .listen((_) => events.add(null), onError: events.addError);
      final rows = database
          .customSelect(
            'SELECT id FROM local_owners WHERE is_active=1 LIMIT 2',
            readsFrom: {
              database.localOwners,
              database.runtimeFlags,
              database.learningProfiles,
            },
          )
          .watch()
          .listen(
            (rows) => events.add(
              rows.length == 1 ? rows.single.read<String>('id') : null,
            ),
            onError: events.addError,
            onDone: events.close,
          );
      events.onCancel = () async {
        await invalidations.cancel();
        await rows.cancel();
      };
    }, isBroadcast: true);
