import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'voice_mirror_gateway.dart';
import 'voice_models.dart';
import 'voice_synthesis_provider.dart';

const _consentMissingFailure = VoiceFailure(
  category: VoiceFailureCategory.consentMissing,
  message: 'Voice mirror consent is missing or was withdrawn.',
);
const _sessionExpiredFailure = VoiceFailure(
  category: VoiceFailureCategory.sessionExpired,
  message: 'The voice mirror session has expired.',
);
const _rateLimitedFailure = VoiceFailure(
  category: VoiceFailureCategory.rateLimited,
  message: 'Voice mirroring is busy. Please try again shortly.',
);
const _cleanupIncompleteFailure = VoiceFailure(
  category: VoiceFailureCategory.cleanupIncomplete,
  message: 'Voice mirror cleanup could not be completed.',
);

const int _backgroundThresholdSeconds = 5 * 60;

/// Read-only view of the mirror controller used by providers and the voice
/// policy source that need current consent/session state and the ability to
/// synthesize the current learning target. Keeps callers decoupled from the
/// full lifecycle surface.
abstract interface class VoiceMirrorSessionControllerView {
  bool get hasConsent;
  bool get isActive;

  Future<VoiceAudio> synthesize({
    required String contentId,
    required String text,
    required String language,
  });
}

/// Owns the client-side lifetime of a temporary participant voice-mirror
/// session: separate consent, active lease metadata, request/character quota,
/// and idempotent cleanup.
///
/// The controller relies on an injectable clock and an explicit
/// [renewLease] entry point so the renewable lease can be tested without real
/// timers. App lifecycle and activity changes are forwarded by the host.
class VoiceMirrorSessionController implements VoiceMirrorSessionControllerView {
  VoiceMirrorSessionController({
    required this._gateway,
    required this._now,
    this._maxRequests = 20,
    this._maxCharacters = 4000,
  });

  final VoiceMirrorClient _gateway;
  final DateTime Function() _now;
  final int _maxRequests;
  final int _maxCharacters;

  bool _hasConsent = false;
  VoiceMirrorLease? _session;
  int _requestCount = 0;
  int _characterCount = 0;
  DateTime? _backgroundedAt;
  bool _disposed = false;

  /// Whether the participant granted the separate voice-mirror consent.
  @override
  bool get hasConsent => _hasConsent;

  /// Whether a temporary session is currently active.
  @override
  bool get isActive => _session != null;

  /// Grants the separate voice-mirror consent.
  Future<void> grantConsent() async {
    _ensureNotDisposed();
    _hasConsent = true;
  }

  /// Withdraws consent and immediately ends any active session.
  Future<void> withdrawConsent() async {
    _hasConsent = false;
    await _endInternal();
  }

  /// Enrolls the participant voice and opens a temporary session.
  Future<void> start({required Uint8List enrollmentWav}) async {
    _ensureNotDisposed();
    if (!_hasConsent) {
      throw _consentMissingFailure;
    }
    if (_session != null) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.validation,
        message: 'A voice mirror session is already active.',
      );
    }
    final lease = await _gateway.enroll(wavBytes: enrollmentWav);
    _session = lease;
    _requestCount = 0;
    _characterCount = 0;
  }

  /// Forwards a renewable-lease heartbeat to the server before the lease
  /// expires. Bounded: a single failure does not loop.
  Future<void> renewLease() async {
    _ensureNotDisposed();
    final session = _session;
    if (session == null) {
      throw _sessionExpiredFailure;
    }
    final renewed = await _gateway.heartbeat(sessionId: session.sessionId);
    // The server never extends the absolute lifetime; keep the original cap.
    _session = VoiceMirrorLease(
      sessionId: renewed.sessionId,
      leaseExpiresAtEpochMs: renewed.leaseExpiresAtEpochMs,
      absoluteExpiresAtEpochMs: session.absoluteExpiresAtEpochMs,
    );
  }

  /// Synthesizes the approved target phrase in the mirrored voice.
  @override
  Future<VoiceAudio> synthesize({
    required String contentId,
    required String text,
    required String language,
  }) async {
    _ensureNotDisposed();
    if (!_hasConsent) {
      throw _consentMissingFailure;
    }
    final session = _session;
    if (session == null || _isExpired(session)) {
      await _endInternal();
      throw _sessionExpiredFailure;
    }
    final normalized = _normalize(text);
    if (_requestCount + 1 > _maxRequests ||
        _characterCount + normalized.length > _maxCharacters) {
      throw _rateLimitedFailure;
    }
    final audio = await _gateway.synthesize(
      sessionId: session.sessionId,
      contentId: contentId,
      text: normalized,
      language: language,
    );
    _requestCount += 1;
    _characterCount += normalized.length;
    return audio;
  }

  /// Ends the active session idempotently.
  ///
  /// A failed delete leaves no usable local session and is reported only as
  /// [VoiceFailureCategory.cleanupIncomplete].
  Future<void> end() async {
    _ensureNotDisposed();
    await _endInternal();
  }

  /// Notifies the controller that the host app lifecycle changed.
  void onAppLifecycleStateChanged(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        final now = _now();
        final backgroundedAt = _backgroundedAt ?? now;
        _backgroundedAt = backgroundedAt;
        final elapsed = now.difference(backgroundedAt).inSeconds;
        if (elapsed >= _backgroundThresholdSeconds) {
          _endInternal();
        }
      case AppLifecycleState.resumed:
        _backgroundedAt = null;
    }
  }

  /// Notifies the controller that the signed-in account changed.
  Future<void> onAccountChanged() async {
    _ensureNotDisposed();
    await _endInternal();
  }

  /// Notifies the controller that the participant left the mirror activity.
  Future<void> onActivityLeave() async {
    _ensureNotDisposed();
    await _endInternal();
  }

  /// Releases resources and ends any active session.
  Future<void> dispose() async {
    _disposed = true;
    await _endInternal();
  }

  Future<void> _endInternal() async {
    _backgroundedAt = null;
    final session = _session;
    _session = null;
    _requestCount = 0;
    _characterCount = 0;
    if (session == null) {
      return;
    }
    try {
      await _gateway.delete(sessionId: session.sessionId);
    } on VoiceFailure {
      // Local session metadata is already cleared; surface only the cleanup
      // category without leaking session identifiers or provider detail.
      throw _cleanupIncompleteFailure;
    }
  }

  bool _isExpired(VoiceMirrorLease session) {
    return _now().millisecondsSinceEpoch >= session.absoluteExpiresAtEpochMs;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('VoiceMirrorSessionController has been disposed.');
    }
  }

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
