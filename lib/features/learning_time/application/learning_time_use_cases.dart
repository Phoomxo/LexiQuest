library;

import 'dart:async';
import 'dart:convert';

import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_time_admission.dart';

part '../domain/learning_time_models.dart';
part '../domain/learning_time_repository.dart';

/// One foreground collector. Persistence failures affect only time capture;
/// callers continue their ordinary learning operation independently.
final class LearningTimeUseCases {
  LearningTimeUseCases({
    required this._repository,
    required Stream<String?> ownerChanges,
    required this._monotonicMicros,
    required this._nowUtc,
    required this._generateId,
  }) {
    _ownerSubscription = ownerChanges.listen(
      _acceptOwner,
      onError: (Object _, StackTrace _) => _acceptOwner(null, force: true),
      onDone: () => _acceptOwner(null, force: true),
    );
  }

  final LearningTimeRepository _repository;
  final int Function() _monotonicMicros;
  final DateTime Function() _nowUtc;
  final String Function() _generateId;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  late final StreamSubscription<String?> _ownerSubscription;
  StreamSubscription<LearningTimePreference?>? _preferenceSubscription;
  String? _ownerId;
  LearningTimePreference? _preference;
  int _preferenceRevisionFloor = 0;
  int _ownerEpoch = 0;
  int _captureEpoch = 0;
  int _attachRevision = 0;
  bool _disposed = false;
  LiveTimeLease? _live;
  ClosedTimeSegmentIntent? _pendingSegment;
  LiveTimeLease? _pendingSegmentLease;
  TimeSessionLinkIntent? _pendingLink;
  LiveTimeLease? _pendingLinkLease;
  LearningTimePreferenceIntent? _pendingPreference;
  Future<void>? _dispatch;

  Stream<void> get changes => _changes.stream;
  String? get ownerId => _ownerId;
  int get ownerGeneration => _ownerEpoch;
  int get captureGeneration => _captureEpoch;
  LearningTimePreference? get preference => _preference;
  LiveTimeLease? get liveLease => _live;
  ClosedTimeSegmentIntent? get pendingSegmentIntent => _pendingSegment;
  TimeSessionLinkIntent? get pendingSessionLinkIntent => _pendingLink;
  LearningTimePreferenceIntent? get pendingPreferenceIntent =>
      _pendingPreference;
  bool get captureEnabled =>
      !_disposed && _ownerId != null && _preference?.enabled == true;
  bool get hasPending =>
      _pendingPreference != null ||
      _pendingSegment != null ||
      _pendingLink != null;
  LearningTimePendingState get pendingState {
    if (_pendingPreference != null) return LearningTimePendingState.preference;
    if (_pendingSegment != null) return LearningTimePendingState.segment;
    if (_pendingLink != null) return LearningTimePendingState.sessionLink;
    return LearningTimePendingState.none;
  }

  void _changed() {
    if (!_disposed) _changes.add(null);
  }

  void _acceptOwner(String? next, {bool force = false}) {
    if (_disposed || (!force && next == _ownerId)) return;
    _ownerEpoch++;
    _retireCapture();
    _pendingPreference = null;
    _ownerId = next;
    _preference = null;
    _preferenceRevisionFloor = 0;
    final previous = _preferenceSubscription;
    _preferenceSubscription = null;
    if (previous != null) unawaited(previous.cancel());
    if (next != null) {
      final epoch = _ownerEpoch;
      _preferenceSubscription = _repository
          .watchPreference(next)
          .listen(
            (value) {
              if (_ownerCurrent(next, epoch)) _acceptPreference(value);
            },
            onError: (Object _, StackTrace _) {
              if (_ownerCurrent(next, epoch)) {
                _acceptPreference(null, force: true);
              }
            },
            onDone: () {
              if (_ownerCurrent(next, epoch)) {
                _acceptPreference(null, force: true);
              }
            },
          );
    }
    _changed();
  }

  bool _ownerCurrent(String owner, int epoch) =>
      !_disposed && _ownerId == owner && _ownerEpoch == epoch;

  void _acceptPreference(LearningTimePreference? value, {bool force = false}) {
    if (value != null &&
        (value.ownerId != _ownerId ||
            value.revision < 0 ||
            value.revision > 9007199254740991 ||
            value.updatedAtUtcMs < 0 ||
            value.updatedAtUtcMs > 8640000000000000 ||
            (value.revision == 0 &&
                (value.enabled || value.updatedAtUtcMs != 0)))) {
      value = null;
    }
    if (value != null) {
      if (value.revision < _preferenceRevisionFloor) return;
      _preferenceRevisionFloor = value.revision;
    }
    final pending = _pendingPreference;
    if (pending != null) {
      final unchangedBase =
          value != null &&
          value.revision == pending.expectedRevision &&
          value.enabled != pending.enabled;
      final exactReceipt =
          value != null &&
          value.revision == pending.expectedRevision + 1 &&
          value.enabled == pending.enabled &&
          value.updatedAtUtcMs == pending.updatedAtUtcMs;
      if (!unchangedBase && !exactReceipt) _pendingPreference = null;
    }
    if (!force &&
        ((value == null && _preference == null) ||
            (value != null && _preference?.sameAs(value) == true))) {
      return;
    }
    _retireCapture();
    _preference = value;
    _changed();
  }

  void _retireCapture() {
    _captureEpoch++;
    _attachRevision++;
    final lease = _live;
    if (lease != null) {
      lease._detached = true;
      lease._ready = false;
      lease._readyRevision++;
      _clearWindow(lease);
    }
    _live = null;
    _pendingSegment = null;
    _pendingSegmentLease = null;
    _pendingLink = null;
    _pendingLinkLease = null;
  }

  /// A replacement repository/database/owner fence cannot revive old work.
  void retireDependencies() => _acceptOwner(_ownerId, force: true);

  void retireLeaseDependencies(LiveTimeLease lease) {
    if (!identical(lease._issuer, this) || lease._dependenciesRetired) return;
    lease._dependenciesRetired = true;
    if (identical(_pendingSegmentLease, lease)) {
      _pendingSegment = null;
      _pendingSegmentLease = null;
    }
    if (identical(_pendingLinkLease, lease)) {
      _pendingLink = null;
      _pendingLinkLease = null;
    }
    if (identical(_live, lease)) {
      detach(lease);
    } else {
      lease._ready = false;
      lease._readyRevision++;
      _clearWindow(lease);
      _changed();
    }
  }

  bool _permissionCurrent(LiveTimeLease lease) =>
      identical(lease._issuer, this) &&
      !lease._dependenciesRetired &&
      _ownerCurrent(lease.scope.ownerId, lease._ownerEpoch) &&
      lease._captureEpoch == _captureEpoch &&
      captureEnabled;

  bool acceptsInteraction(LiveTimeLease lease) =>
      _liveCurrent(lease) && lease._ready && !hasPending;

  bool _liveCurrent(LiveTimeLease lease) =>
      identical(_live, lease) &&
      !lease._detached &&
      _permissionCurrent(lease) &&
      lease._stillCurrent();

  Future<LiveTimeLease?> attach(
    TimeSource source, {
    required bool Function() stillCurrent,
  }) async {
    if (!captureEnabled ||
        _pendingPreference != null ||
        !stillCurrent() ||
        source.callerContext != LearningTimeCallerContext.ordinary) {
      return null;
    }
    final old = _live;
    if (old != null) detach(old);
    final request = ++_attachRevision;
    final owner = _ownerId!;
    final ownerEpoch = _ownerEpoch;
    final captureEpoch = _captureEpoch;
    bool current() =>
        _ownerCurrent(owner, ownerEpoch) &&
        _captureEpoch == captureEpoch &&
        captureEnabled &&
        _pendingPreference == null &&
        request == _attachRevision &&
        stillCurrent();
    try {
      final admission = await _repository.admitSource(
        source: source,
        expectedOwnerId: owner,
        isCurrent: current,
      );
      if (!current()) return null;
      _validateAdmission(admission, owner);
      final scope = LearningTimeScope(
        id: 'time-scope:${_generateId()}',
        ownerId: owner,
        sourceKind: admission.sourceKind,
        sourceBindingJson: admission.sourceBindingJson,
        createdAtUtcMs: _utcMs(),
        linkedSessionId: admission.linkedSessionId,
        sessionLinkBindingJson: admission.sessionLinkBindingJson,
      );
      final lease = LiveTimeLease._(
        scope: scope,
        admission: admission,
        issuer: this,
        source: source,
        ownerEpoch: ownerEpoch,
        captureEpoch: captureEpoch,
        stillCurrent: stillCurrent,
      );
      _live = lease;
      _changed();
      return lease;
    } on Object {
      return null;
    }
  }

  /// Re-admit after actual waiting/context transitions; merely becoming
  /// foreground is insufficient. No row is created by an unconfirmed anchor.
  Future<bool> ready(LiveTimeLease lease, {TimeSource? source}) async {
    if (!_liveCurrent(lease) || hasPending) return false;
    suspend(lease);
    if (!_liveCurrent(lease) || hasPending) return false;
    final request = ++lease._readyRevision;
    final nextSource = source ?? lease._source;
    if (nextSource.callerContext != LearningTimeCallerContext.ordinary) {
      return false;
    }
    bool current() =>
        _liveCurrent(lease) && request == lease._readyRevision && !hasPending;
    try {
      final admission = await _repository.admitSource(
        source: nextSource,
        expectedOwnerId: lease.scope.ownerId,
        isCurrent: current,
      );
      if (!current()) return false;
      _validateAdmission(admission, lease.scope.ownerId);
      if (admission.sourceKind != lease.scope.sourceKind ||
          admission.sourceBindingJson != lease.scope.sourceBindingJson) {
        return false;
      }
      lease._source = nextSource;
      lease._admission = admission;
      lease._ready = true;
      lease._anchorUs = _monotonicMicros();
      lease._anchorUtcMs = _utcMs();
      _changed();
      return true;
    } on Object {
      return false;
    }
  }

  /// Call only from accepted semantic/user-edit paths. Programmatic changes,
  /// provider replies and automatic scroll never call this method.
  void interacted(LiveTimeLease lease) {
    if (!_liveCurrent(lease) || !lease._ready || hasPending) return;
    final nowUs = _monotonicMicros();
    final nowUtcMs = _utcMs();
    final anchorUs = lease._anchorUs;
    final anchorUtcMs = lease._anchorUtcMs;
    if (anchorUs == null || anchorUtcMs == null) {
      lease._anchorUs = nowUs;
      lease._anchorUtcMs = nowUtcMs;
      return;
    }
    final gap = nowUs - anchorUs;
    if (gap <= 0 || gap > learningTimeMaximumInputGapUs) {
      _seal(lease);
      if (!hasPending) {
        lease._anchorUs = nowUs;
        lease._anchorUtcMs = nowUtcMs;
      }
      return;
    }
    lease._startedAtUtcMs ??= anchorUtcMs;
    lease._endedAtUtcMs = nowUtcMs;
    lease._confirmedUs += gap;
    lease._anchorUs = nowUs;
    lease._anchorUtcMs = nowUtcMs;
    if (lease._confirmedUs >= learningTimeCheckpointUs) _seal(lease);
  }

  /// Seal confirmed pairs only; the unfinished terminal gap is discarded.
  void suspend(LiveTimeLease lease) {
    if (!identical(lease._issuer, this)) return;
    lease._ready = false;
    lease._readyRevision++;
    if (_permissionCurrent(lease)) _seal(lease);
    _clearWindow(lease);
  }

  void detach(LiveTimeLease lease) {
    if (!identical(lease._issuer, this)) return;
    suspend(lease);
    lease._detached = true;
    if (identical(_live, lease)) _live = null;
    _changed();
  }

  void _clearWindow(LiveTimeLease lease) {
    lease._anchorUs = null;
    lease._anchorUtcMs = null;
    lease._confirmedUs = 0;
    lease._startedAtUtcMs = null;
    lease._endedAtUtcMs = null;
  }

  void _seal(LiveTimeLease lease) {
    if (lease._confirmedUs <= 0) {
      _clearWindow(lease);
      return;
    }
    if (!_permissionCurrent(lease) || hasPending) {
      _clearWindow(lease);
      return;
    }
    final duration = lease._confirmedUs;
    if (duration >= learningTimeMaximumSegmentUs) {
      _clearWindow(lease);
      return;
    }
    final ownerEpoch = _ownerEpoch;
    final captureEpoch = _captureEpoch;
    final revision = _preference!.revision;
    late final ClosedTimeSegmentIntent intent;
    intent = ClosedTimeSegmentIntent._(
      repository: _repository,
      scope: lease.scope,
      id: 'time-segment:${_generateId()}',
      ordinal: lease._nextOrdinal,
      eligibilityContextJson: lease.admission.contextBindingJson,
      startedAtUtcMs: lease._startedAtUtcMs!,
      endedAtUtcMs: lease._endedAtUtcMs!,
      activeDurationUs: duration,
      preferenceRevision: revision,
      admission: lease.admission,
      sessionLinkAdmission: lease._link,
      isCurrent: () =>
          _ownerCurrent(lease.scope.ownerId, ownerEpoch) &&
          _captureEpoch == captureEpoch &&
          _preference?.enabled == true &&
          _preference?.revision == revision &&
          !lease._dependenciesRetired &&
          identical(_pendingSegment, intent),
    );
    _pendingSegment = intent;
    _pendingSegmentLease = lease;
    _clearWindow(lease);
    _changed();
    unawaited(retryPending());
  }

  Future<TimeSessionLinkAdmission?> prepareSessionLink(
    LiveTimeLease lease,
    CanonicalLearningTimeSessionLinkReceipt proof,
  ) async {
    if (!_permissionCurrent(lease) || _pendingPreference != null) return null;
    bool current() => _permissionCurrent(lease) && _pendingPreference == null;
    try {
      final admission = await _repository.prepareSessionLink(
        scope: lease.scope,
        proof: proof,
        expectedOwnerId: lease.scope.ownerId,
        isCurrent: current,
      );
      if (!current() ||
          admission.scopeId != lease.scope.id ||
          admission.ownerId != lease.scope.ownerId ||
          admission.linkedSessionId != proof.sessionId) {
        return null;
      }
      final link = parseTimeSessionLinkBindingJson(
        admission.sessionLinkBindingJson,
      );
      if (link['sessionId'] != admission.linkedSessionId) return null;
      lease._preparedLink = admission;
      return admission;
    } on Object {
      return null;
    }
  }

  bool acknowledgeSessionLink(
    LiveTimeLease lease,
    TimeSessionLinkAdmission admission,
  ) {
    if (!_permissionCurrent(lease) ||
        (!identical(lease._preparedLink, admission) &&
            !identical(lease._link, admission)) ||
        admission.scopeId != lease.scope.id ||
        admission.ownerId != lease.scope.ownerId ||
        _pendingPreference != null) {
      return false;
    }
    final existing = lease._link;
    if (existing != null &&
        (existing.linkedSessionId != admission.linkedSessionId ||
            existing.sessionLinkBindingJson !=
                admission.sessionLinkBindingJson)) {
      return false;
    }
    if (lease.scope.linkedSessionId != null &&
        (lease.scope.linkedSessionId != admission.linkedSessionId ||
            lease.scope.sessionLinkBindingJson !=
                admission.sessionLinkBindingJson)) {
      return false;
    }
    final segment = _pendingSegment;
    if (segment != null && segment.scope.id != lease.scope.id) return false;
    if (_pendingLink != null) {
      return _pendingLink!.scope.id == lease.scope.id &&
          _pendingLink!.linkedSessionId == admission.linkedSessionId &&
          _pendingLink!.sessionLinkBindingJson ==
              admission.sessionLinkBindingJson;
    }
    lease._link = admission;
    if (lease.scope.linkedSessionId != null) return true;
    if (!lease._materialized && segment == null) {
      lease._scope = lease.scope._withLink(admission);
      return true;
    }
    final live = _live;
    if (live != null) suspend(live);
    if (_pendingSegment != null &&
        _pendingSegment!.scope.id != lease.scope.id) {
      return false;
    }
    final ownerEpoch = _ownerEpoch;
    final captureEpoch = _captureEpoch;
    final revision = _preference!.revision;
    late final TimeSessionLinkIntent intent;
    intent = TimeSessionLinkIntent._(
      repository: _repository,
      scope: lease.scope,
      admission: admission,
      preferenceRevision: revision,
      isCurrent: () =>
          _ownerCurrent(lease.scope.ownerId, ownerEpoch) &&
          _captureEpoch == captureEpoch &&
          _preference?.enabled == true &&
          _preference?.revision == revision &&
          !lease._dependenciesRetired &&
          identical(_pendingLink, intent),
    );
    _pendingLink = intent;
    _pendingLinkLease = lease;
    _changed();
    unawaited(retryPending());
    return true;
  }

  Future<LearningTimePreference?> setEnabled(
    bool enabled, {
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async {
    if (_disposed ||
        _ownerId != expectedOwnerId ||
        !stillCurrent() ||
        _preference == null) {
      return null;
    }
    final pending = _pendingPreference;
    if (pending != null) {
      if (pending.ownerId != expectedOwnerId || pending.enabled != enabled) {
        return null;
      }
      final epoch = _ownerEpoch;
      await retryPending();
      if (pending.isCurrent) await _dispatch;
      return _pendingPreference == null &&
              _ownerCurrent(expectedOwnerId, epoch) &&
              _preference?.enabled == enabled &&
              _preference?.revision == pending.expectedRevision + 1 &&
              _preference?.updatedAtUtcMs == pending.updatedAtUtcMs
          ? _preference
          : null;
    }
    if (_preference!.enabled == enabled) return _preference;
    final revision = _preference!.revision;
    final epoch = _ownerEpoch;
    _retireCapture();
    late final LearningTimePreferenceIntent intent;
    intent = LearningTimePreferenceIntent._(
      repository: _repository,
      ownerId: expectedOwnerId,
      expectedRevision: revision,
      enabled: enabled,
      updatedAtUtcMs: _utcMs(),
      isCurrent: () =>
          _ownerCurrent(expectedOwnerId, epoch) &&
          identical(_pendingPreference, intent),
    );
    _pendingPreference = intent;
    _changed();
    await retryPending();
    if (intent.isCurrent) await _dispatch;
    return _pendingPreference == null &&
            _ownerCurrent(expectedOwnerId, epoch) &&
            _preference?.enabled == enabled &&
            _preference?.revision == intent.expectedRevision + 1 &&
            _preference?.updatedAtUtcMs == intent.updatedAtUtcMs
        ? _preference
        : null;
  }

  /// Every retry submits the exact original object, IDs, CAS and timestamps.
  Future<void> retryPending() {
    final running = _dispatch;
    if (running != null) return running;
    if (_disposed || !hasPending) return Future<void>.value();
    final completer = Completer<void>();
    final attempted = <Object>[];
    _dispatch = completer.future;
    unawaited(() async {
      try {
        await _dispatchPending(attempted);
      } on Object {
        // Retain the exact intent for explicit retry; learning continues.
      } finally {
        _dispatch = null;
        completer.complete();
        _changed();
        final pendingNow = [
          _pendingPreference,
          _pendingSegment,
          _pendingLink,
        ].whereType<Object>();
        if (pendingNow.isNotEmpty &&
            !pendingNow.any(
              (pending) => attempted.any((value) => identical(value, pending)),
            )) {
          unawaited(retryPending());
        }
      }
    }());
    return completer.future;
  }

  Future<void> _dispatchPending(List<Object> attempted) async {
    final preferenceIntent = _pendingPreference;
    if (preferenceIntent != null) {
      if (!preferenceIntent.isCurrent) return;
      attempted.add(preferenceIntent);
      final result = await _repository.commitPreference(preferenceIntent);
      if (!preferenceIntent.isCurrent) return;
      if (result.ownerId != preferenceIntent.ownerId ||
          result.enabled != preferenceIntent.enabled ||
          result.revision != preferenceIntent.expectedRevision + 1 ||
          result.updatedAtUtcMs != preferenceIntent.updatedAtUtcMs) {
        throw StateError('Learning-time preference acknowledgement changed');
      }
      _pendingPreference = null;
      _acceptPreference(result);
    }
    final segment = _pendingSegment;
    if (segment != null) {
      if (!segment.isCurrent) return;
      attempted.add(segment);
      final lease = _pendingSegmentLease!;
      await _repository.commitSegment(segment);
      if (!segment.isCurrent) return;
      _pendingSegment = null;
      _pendingSegmentLease = null;
      lease._materialized = true;
      lease._nextOrdinal = segment.ordinal + 1;
    }
    final link = _pendingLink;
    if (link != null) {
      if (!link.isCurrent) return;
      attempted.add(link);
      final lease = _pendingLinkLease!;
      await _repository.commitSessionLink(link);
      if (!link.isCurrent) return;
      _pendingLink = null;
      _pendingLinkLease = null;
      lease._scope = lease.scope._withLink(link.admission);
    }
  }

  Future<RecordedTimeRead> read(TimeReadTarget target) async {
    final owner = _ownerId;
    if (owner == null) return const RecordedTimeRead.unavailable();
    return readForOwner(
      target,
      expectedOwnerId: owner,
      stillCurrent: () => true,
    );
  }

  Future<RecordedTimeRead> readForOwner(
    TimeReadTarget target, {
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async {
    final owner = _ownerId;
    final epoch = _ownerEpoch;
    if (owner == null || owner != expectedOwnerId || _disposed) {
      return const RecordedTimeRead.unavailable();
    }
    bool current() => _ownerCurrent(owner, epoch) && stillCurrent();
    try {
      final result = await _repository.read(
        target: target,
        expectedOwnerId: owner,
        isCurrent: current,
      );
      return current() ? result : const RecordedTimeRead.unavailable();
    } on Object {
      return const RecordedTimeRead.unavailable();
    }
  }

  int _utcMs() {
    final value = _nowUtc().toUtc().millisecondsSinceEpoch;
    if (value < 0 || value > 8640000000000000) {
      throw StateError('Learning-time UTC observation is unavailable');
    }
    return value;
  }

  void _validateAdmission(TimeSourceAdmission admission, String owner) {
    if (admission.ownerId != owner ||
        (admission.linkedSessionId == null) !=
            (admission.sessionLinkBindingJson == null)) {
      throw StateError('Learning-time source owner/link changed');
    }
    parseTimeBindingJson(
      admission.sourceBindingJson,
      sourceKind: admission.sourceKind,
      isContext: false,
    );
    parseTimeBindingJson(
      admission.contextBindingJson,
      sourceKind: admission.sourceKind,
      isContext: true,
    );
    final linkJson = admission.sessionLinkBindingJson;
    if (linkJson != null &&
        parseTimeSessionLinkBindingJson(linkJson)['sessionId'] !=
            admission.linkedSessionId) {
      throw StateError('Learning-time source session link changed');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _retireCapture();
    _pendingPreference = null;
    _ownerEpoch++;
    _disposed = true;
    await _ownerSubscription.cancel();
    await _preferenceSubscription?.cancel();
    await _changes.close();
  }
}
