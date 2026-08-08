import 'voice_capability.dart';
import 'voice_models.dart';

/// Privacy-by-construction outcome reported for one voice playback attempt.
/// The cancelled value is reserved for user/system cancellation; every other
/// terminal state is either succeeded or failed.
enum VoiceTelemetryOutcome { succeeded, failed, cancelled }

/// Schema version stamped onto every emitted voice telemetry event.
const String _kVoiceTelemetrySchemaVersion = 'voice_telemetry_v2';

/// Immutable, privacy-safe telemetry record for a single voice playback
/// lifecycle.
///
/// Factories read [VoiceRequest], [VoicePlaybackResult], and [VoiceFailure]
/// to extract only the allowlisted scalar/enum/date/duration fields. The event
/// never retains those source objects and never stores spoken text, language,
/// voice id, speed, failure messages, credentials, identifiers beyond
/// [contentId]/[contentType]/[requestId]/[modelVersion], or audio bytes.
final class VoiceTelemetryEvent {
  const VoiceTelemetryEvent._({
    required this.schemaVersion,
    required this.outcome,
    required this.mode,
    required this.capability,
    required this.privacyScope,
    required this.requestedEngine,
    required this.actualEngine,
    required this.usedFallback,
    required this.fallbackReason,
    required this.failureCategory,
    required this.cacheHit,
    required this.contentId,
    required this.contentType,
    required this.requestId,
    required this.modelVersion,
    required this.latency,
    required this.occurredAtUtc,
  });

  /// Reports a successful playback outcome.
  ///
  /// [fallbackReason] must be supplied when, and only when,
  /// [VoicePlaybackResult.usedFallback] is true, otherwise an [ArgumentError]
  /// is thrown. [latency] must not be negative.
  factory VoiceTelemetryEvent.succeeded({
    required VoiceRequest request,
    required VoicePlaybackResult result,
    VoiceFailureCategory? fallbackReason,
    required Duration latency,
    required DateTime occurredAtUtc,
  }) {
    _requireNonNegativeLatency(latency);
    if (result.usedFallback != (fallbackReason != null)) {
      throw ArgumentError.value(
        fallbackReason,
        'fallbackReason',
        'usedFallback and fallbackReason must agree',
      );
    }

    return VoiceTelemetryEvent._(
      schemaVersion: _kVoiceTelemetrySchemaVersion,
      outcome: VoiceTelemetryOutcome.succeeded,
      mode: request.mode,
      capability: request.capability,
      privacyScope: request.privacyScope,
      requestedEngine: result.requestedEngine,
      actualEngine: result.actualEngine,
      usedFallback: result.usedFallback,
      fallbackReason: fallbackReason,
      failureCategory: null,
      cacheHit: result.cacheHit,
      contentId: request.contentId,
      contentType: request.contentType,
      requestId: result.requestId,
      modelVersion: result.modelVersion,
      latency: latency,
      occurredAtUtc: occurredAtUtc.toUtc(),
    );
  }

  /// Reports a failed playback outcome. A [VoiceFailureCategory.cancelled]
  /// failure maps to [VoiceTelemetryOutcome.cancelled]; every other category
  /// maps to [VoiceTelemetryOutcome.failed]. The actual engine, fallback
  /// state, cache state, and provenance are unknown on failure and are left
  /// null/false. [latency] must not be negative.
  factory VoiceTelemetryEvent.failed({
    required VoiceRequest request,
    required VoiceEngine requestedEngine,
    required VoiceFailure failure,
    required Duration latency,
    required DateTime occurredAtUtc,
  }) {
    _requireNonNegativeLatency(latency);
    final outcome = failure.category == VoiceFailureCategory.cancelled
        ? VoiceTelemetryOutcome.cancelled
        : VoiceTelemetryOutcome.failed;

    return VoiceTelemetryEvent._(
      schemaVersion: _kVoiceTelemetrySchemaVersion,
      outcome: outcome,
      mode: request.mode,
      capability: request.capability,
      privacyScope: request.privacyScope,
      requestedEngine: requestedEngine,
      actualEngine: null,
      usedFallback: false,
      fallbackReason: null,
      failureCategory: failure.category,
      cacheHit: false,
      contentId: request.contentId,
      contentType: request.contentType,
      requestId: null,
      modelVersion: null,
      latency: latency,
      occurredAtUtc: occurredAtUtc.toUtc(),
    );
  }

  final String schemaVersion;
  final VoiceTelemetryOutcome outcome;
  final VoiceMode mode;
  final VoiceCapability capability;
  final VoicePrivacyScope privacyScope;
  final VoiceEngine requestedEngine;
  final VoiceEngine? actualEngine;
  final bool usedFallback;
  final VoiceFailureCategory? fallbackReason;
  final VoiceFailureCategory? failureCategory;
  final bool cacheHit;
  final String contentId;
  final String contentType;
  final String? requestId;
  final String? modelVersion;
  final Duration latency;
  final DateTime occurredAtUtc;

  /// Returns a fresh, mutable serialization of this event containing exactly
  /// the allowlisted telemetry keys. Enums serialize to their names, the
  /// timestamp to an ISO-8601 UTC string, and the latency to integer
  /// milliseconds.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'outcome': outcome.name,
      'mode': mode.name,
      'capability': capability.name,
      'privacyScope': privacyScope.name,
      'requestedEngine': requestedEngine.name,
      'actualEngine': actualEngine?.name,
      'usedFallback': usedFallback,
      'fallbackReason': fallbackReason?.name,
      'failureCategory': failureCategory?.name,
      'cacheHit': cacheHit,
      'latencyMs': latency.inMilliseconds,
      'contentId': contentId,
      'contentType': contentType,
      'requestId': requestId,
      'modelVersion': modelVersion,
      'occurredAtUtc': occurredAtUtc.toIso8601String(),
    };
  }
}

void _requireNonNegativeLatency(Duration latency) {
  if (latency.isNegative) {
    throw ArgumentError.value(latency, 'latency', 'must not be negative');
  }
}

/// Sink that accepts telemetry events for downstream emission.
abstract interface class VoiceTelemetrySink {
  Future<void> record(VoiceTelemetryEvent event);
}

/// [VoiceTelemetrySink] that discards events, used when telemetry is off.
final class NoopVoiceTelemetrySink implements VoiceTelemetrySink {
  const NoopVoiceTelemetrySink();

  @override
  Future<void> record(VoiceTelemetryEvent event) async {}
}
