import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/progress/progress_repository.dart';

typedef ProgressClock = DateTime Function();

/// Offline-first [ProgressRepository] backed entirely by [SharedPreferences].
///
/// The aggregated [ProgressSnapshot] and the pending outbox of recorded but
/// unsynced sessions are persisted together as a single versioned JSON envelope
/// under one private key, so each accepted session is exactly one logical
/// write. Because every read and write flows through that envelope, a freshly
/// constructed instance over the same [SharedPreferences] restores the
/// previously persisted state without any separate in-memory cache.
class LocalProgressRepository implements ProgressRepository {
  /// Constructs a repository that reads and writes [prefs] directly.
  LocalProgressRepository(this._prefs, {ProgressClock? clock})
    : _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final ProgressClock _clock;

  /// Single private, namespaced, versioned key for the whole progress envelope.
  static const String _kProgressKey = 'lexiquest_local_progress_v1';

  /// Envelope schema version, stored alongside the payload so future readers
  /// can detect and fail closed on formats they cannot safely interpret.
  static const int _kEnvelopeVersion = 2;

  /// Reasonable upper bound on a recorded session id length.
  static const int _kMaxSessionIdLength = 128;

  /// Sane per-session ceiling on total answers. Real sessions are far smaller;
  /// this rejects obviously broken payloads (e.g. a million answers) while
  /// comfortably admitting any realistic session.
  static const int _kMaxAnswersPerSession = 100;

  /// Serializer gate: concurrent [recordSession] calls on one instance are
  /// queued here so their read-modify-write steps cannot interleave and lose
  /// updates.
  Future<void> _gate = Future<void>.value();

  @override
  Future<void> recordSession(ProgressSession session) =>
      _serialized(() => _recordSessionLocked(session));

  @override
  Future<ProgressSnapshot> readSnapshot() async {
    return _readState().snapshot;
  }

  @override
  Future<List<ProgressSession>> pendingSessions() async {
    return List<ProgressSession>.unmodifiable(_readState().pending);
  }

  @override
  Future<void> acknowledgeSession(String sessionId) {
    return _serialized(() async {
      final canonicalId = sessionId.trim();
      if (canonicalId.isEmpty ||
          canonicalId.length > _kMaxSessionIdLength ||
          canonicalId != sessionId) {
        throw ArgumentError.value(sessionId, 'sessionId', 'is invalid');
      }
      final state = _readState();
      if (!state.pending.any((session) => session.sessionId == canonicalId)) {
        return;
      }
      await _writeState(
        _ProgressState(
          snapshot: state.snapshot,
          pending: [
            for (final session in state.pending)
              if (session.sessionId != canonicalId) session,
          ],
        ),
      );
    });
  }

  /// Runs [task] only after any previously queued [recordSession] has settled,
  /// and extends [_gate] synchronously so back-to-back calls stay ordered. The
  /// gate is always released in [finally], even when [task] throws.
  Future<T> _serialized<T>(Future<T> Function() task) async {
    final previous = _gate;
    final completer = Completer<void>();
    _gate = completer.future;
    try {
      await previous;
      return await task();
    } finally {
      completer.complete();
    }
  }

  Future<void> _recordSessionLocked(ProgressSession session) async {
    final id = session.sessionId.trim();
    final state = _readState();

    // Idempotency short-circuits before the payload is compared: an already
    // recorded, non-empty id is a no-op even when the replayed counts differ.
    if (id.isNotEmpty && state.pending.any((s) => s.sessionId == id)) {
      return;
    }

    // Validate fully before any mutation; an invalid session leaves the stored
    // envelope untouched.
    _validateSession(session, id);

    // Canonicalize to the trimmed id before storing and aggregating so a later
    // replay of the canonical id dedupes against the accepted record.
    final canonical = ProgressSession(
      sessionId: id,
      correctAnswers: session.correctAnswers,
      wrongAnswers: session.wrongAnswers,
      eventIds: session.eventIds.isEmpty
          ? _defaultEventIds(id, session.correctAnswers + session.wrongAnswers)
          : List<String>.unmodifiable(session.eventIds),
      completedAtUtc: (session.completedAtUtc ?? _clock()).toUtc(),
    );
    await _writeState(_applySession(state, canonical));
  }

  void _validateSession(ProgressSession session, String trimmedId) {
    final violation = _sessionConstraintViolation(session, trimmedId);
    if (violation != null) {
      throw ArgumentError.value(session, 'session', violation);
    }
  }

  /// Returns a description of the first constraint [session] violates against
  /// its trimmed id [trimmedId], or null when it is valid.
  ///
  /// Shared by the new-input validator, which raises [ArgumentError], and the
  /// decoder, which raises [FormatException] so corruption surfaces as a
  /// [StateError] through [_readState].
  String? _sessionConstraintViolation(
    ProgressSession session,
    String trimmedId,
  ) {
    if (trimmedId.isEmpty || trimmedId.length > _kMaxSessionIdLength) {
      return 'must be a non-empty trimmed string of at most '
          '$_kMaxSessionIdLength characters';
    }
    if (session.correctAnswers < 0 || session.wrongAnswers < 0) {
      return 'answer counts must be non-negative';
    }
    if (session.correctAnswers + session.wrongAnswers >
        _kMaxAnswersPerSession) {
      return 'answers per session exceed the maximum of '
          '$_kMaxAnswersPerSession';
    }
    final eventIds = session.eventIds;
    if (eventIds.isNotEmpty) {
      if (eventIds.length > _kMaxAnswersPerSession ||
          session.correctAnswers > eventIds.length ||
          eventIds.toSet().length != eventIds.length ||
          eventIds.any(
            (eventId) =>
                eventId.isEmpty ||
                eventId.length > 128 ||
                !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(eventId),
          )) {
        return 'event identifiers are invalid';
      }
    }
    return null;
  }

  _ProgressState _applySession(_ProgressState state, ProgressSession session) {
    return _ProgressState(
      snapshot: ProgressSnapshot(
        totalPoints: state.snapshot.totalPoints + session.correctAnswers,
        totalCorrectAnswers:
            state.snapshot.totalCorrectAnswers + session.correctAnswers,
        totalWrongAnswers:
            state.snapshot.totalWrongAnswers + session.wrongAnswers,
        gamesPlayed: state.snapshot.gamesPlayed + 1,
      ),
      pending: [...state.pending, session],
    );
  }

  _ProgressState _readState() {
    final raw = _prefs.getString(_kProgressKey);
    if (raw == null || raw.isEmpty) {
      return _ProgressState(
        snapshot: _zeroSnapshot,
        pending: const <ProgressSession>[],
      );
    }
    // Fail closed: corrupt persisted research data must never be silently reset.
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('progress envelope must be a JSON object');
      }
      return _decodeState(decoded);
    } catch (error) {
      throw StateError('corrupt local progress state: $error');
    }
  }

  Future<void> _writeState(_ProgressState state) async {
    final accepted = await _prefs.setString(_kProgressKey, _encodeState(state));
    if (!accepted) {
      throw StateError('SharedPreferences rejected the progress write');
    }
  }

  _ProgressState _decodeState(Map<String, dynamic> json) {
    final envelopeVersion = json['v'];
    if (envelopeVersion != 1 && envelopeVersion != _kEnvelopeVersion) {
      throw FormatException(
        'unsupported progress envelope version: ${json['v']}',
      );
    }
    final snapshotJson = json['snapshot'];
    if (snapshotJson is! Map<String, dynamic>) {
      throw const FormatException('missing or invalid snapshot object');
    }
    final pendingJson = json['pending'];
    if (pendingJson is! List) {
      throw const FormatException('missing or invalid pending list');
    }
    final seenIds = <String>{};
    final pending = <ProgressSession>[
      for (final entry in pendingJson)
        _decodeSession(entry, seenIds, envelopeVersion as int),
    ];
    return _ProgressState(
      snapshot: _decodeSnapshot(snapshotJson),
      pending: pending,
    );
  }

  ProgressSnapshot _decodeSnapshot(Map<String, dynamic> json) {
    final totalPoints = _decodeInt(json['totalPoints'], 'totalPoints');
    final totalCorrectAnswers = _decodeInt(
      json['totalCorrectAnswers'],
      'totalCorrectAnswers',
    );
    final totalWrongAnswers = _decodeInt(
      json['totalWrongAnswers'],
      'totalWrongAnswers',
    );
    final gamesPlayed = _decodeInt(json['gamesPlayed'], 'gamesPlayed');

    if (totalPoints < 0 ||
        totalCorrectAnswers < 0 ||
        totalWrongAnswers < 0 ||
        gamesPlayed < 0) {
      throw const FormatException('snapshot counters must be non-negative');
    }
    // This store accrues exactly one point per correct answer, so points and
    // correct answers must stay in lockstep; divergence signals corruption.
    if (totalPoints != totalCorrectAnswers) {
      throw FormatException(
        'snapshot totalPoints ($totalPoints) must equal '
        'totalCorrectAnswers ($totalCorrectAnswers)',
      );
    }

    return ProgressSnapshot(
      totalPoints: totalPoints,
      totalCorrectAnswers: totalCorrectAnswers,
      totalWrongAnswers: totalWrongAnswers,
      gamesPlayed: gamesPlayed,
    );
  }

  ProgressSession _decodeSession(
    dynamic json,
    Set<String> seenIds,
    int envelopeVersion,
  ) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('invalid pending session entry');
    }
    final sessionId = _decodeString(json['sessionId'], 'sessionId');
    final correctAnswers = _decodeInt(json['correctAnswers'], 'correctAnswers');
    final wrongAnswers = _decodeInt(json['wrongAnswers'], 'wrongAnswers');
    final session = ProgressSession(
      sessionId: sessionId,
      correctAnswers: correctAnswers,
      wrongAnswers: wrongAnswers,
      eventIds: envelopeVersion == 1
          ? _defaultEventIds(sessionId, correctAnswers + wrongAnswers)
          : _decodeEventIds(json['eventIds']),
      completedAtUtc: envelopeVersion == 1
          ? _clock().toUtc()
          : _decodeUtc(json['completedAtUtc']),
    );
    // The writer always stores ids already trimmed, so surrounding whitespace
    // is a corruption signal rather than something to normalize on read.
    if (session.sessionId != session.sessionId.trim()) {
      throw const FormatException('persisted session id is not canonical');
    }
    final violation = _sessionConstraintViolation(session, session.sessionId);
    if (violation != null) {
      throw FormatException('persisted session is invalid: $violation');
    }
    if (!seenIds.add(session.sessionId)) {
      throw FormatException(
        'duplicate pending session id: ${session.sessionId}',
      );
    }
    return session;
  }

  int _decodeInt(dynamic value, String field) {
    if (value is! int) {
      throw FormatException('progress field "$field" must be an integer');
    }
    return value;
  }

  String _decodeString(dynamic value, String field) {
    if (value is! String) {
      throw FormatException('progress field "$field" must be a string');
    }
    return value;
  }

  List<String> _decodeEventIds(dynamic value) {
    if (value is! List || value.any((entry) => entry is! String)) {
      throw const FormatException('progress eventIds must be strings');
    }
    return List<String>.unmodifiable(value.cast<String>());
  }

  DateTime _decodeUtc(dynamic value) {
    if (value is! String) {
      throw const FormatException('completedAtUtc must be a string');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const FormatException('completedAtUtc must be an ISO timestamp');
    }
    return parsed.toUtc();
  }

  String _encodeState(_ProgressState state) {
    return jsonEncode({
      'v': _kEnvelopeVersion,
      'snapshot': {
        'totalPoints': state.snapshot.totalPoints,
        'totalCorrectAnswers': state.snapshot.totalCorrectAnswers,
        'totalWrongAnswers': state.snapshot.totalWrongAnswers,
        'gamesPlayed': state.snapshot.gamesPlayed,
      },
      'pending': [
        for (final session in state.pending)
          {
            'sessionId': session.sessionId,
            'correctAnswers': session.correctAnswers,
            'wrongAnswers': session.wrongAnswers,
            'eventIds': session.eventIds,
            'completedAtUtc': session.completedAtUtc!.toIso8601String(),
          },
      ],
    });
  }

  static const ProgressSnapshot _zeroSnapshot = ProgressSnapshot(
    totalPoints: 0,
    totalCorrectAnswers: 0,
    totalWrongAnswers: 0,
    gamesPlayed: 0,
  );

  List<String> _defaultEventIds(String sessionId, int answerCount) {
    final count = answerCount < 1 ? 1 : answerCount;
    return List<String>.unmodifiable([
      for (var index = 0; index < count; index++)
        sha256.convert(utf8.encode('$sessionId:$index')).toString(),
    ]);
  }
}

/// Private holder pairing the current snapshot with its pending outbox.
class _ProgressState {
  _ProgressState({required this.snapshot, required this.pending});

  final ProgressSnapshot snapshot;
  final List<ProgressSession> pending;
}
