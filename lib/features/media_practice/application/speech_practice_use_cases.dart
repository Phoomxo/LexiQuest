import 'dart:math' as math;

import '../domain/media_practice_contracts.dart';

final class SpeechPracticeUseCases {
  const SpeechPracticeUseCases(this.gateway);

  final SpeechRecognitionGateway gateway;

  bool get isListening => gateway.isListening;

  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    final permission = await gateway.requestPermission();
    switch (permission) {
      case MediaPermissionState.granted:
        break;
      case MediaPermissionState.permanentlyDenied:
        throw const SpeechPracticeException(
          SpeechFailureCode.permissionPermanentlyDenied,
        );
      case MediaPermissionState.denied:
      case MediaPermissionState.restricted:
        throw const SpeechPracticeException(SpeechFailureCode.permissionDenied);
      case MediaPermissionState.unavailable:
        throw const SpeechPracticeException(SpeechFailureCode.unavailable);
    }
    await gateway.initialize(onFailure: onFailure, onStatus: onStatus);
    await gateway.start(locale: locale, onEvent: onEvent);
  }

  Future<void> stop() => gateway.stop();

  Future<void> cancel() => gateway.cancel();

  Future<void> dispose() async {
    if (gateway.isListening) {
      await gateway.cancel();
    }
  }

  TranscriptPronunciationAssessment assess({
    required String target,
    required SpeechRecognitionEvent event,
  }) {
    final canonicalTarget = _canonical(target);
    final canonicalTranscript = _canonical(event.transcript);
    if (canonicalTarget.isEmpty || canonicalTranscript.isEmpty) {
      return TranscriptPronunciationAssessment(
        target: target,
        transcript: event.transcript,
        similarityPercent: 0,
        isExactMatch: false,
        method: 'transcript-edit-distance-v1',
        engine: event.engine,
        locale: event.locale,
        occurredAtUtc: event.recognizedAtUtc,
      );
    }
    final distance = _levenshtein(canonicalTarget, canonicalTranscript);
    final denominator = math.max(
      canonicalTarget.runes.length,
      canonicalTranscript.runes.length,
    );
    final score = ((1 - (distance / denominator)) * 100).clamp(0, 100).round();
    return TranscriptPronunciationAssessment(
      target: target,
      transcript: event.transcript,
      similarityPercent: score,
      isExactMatch: canonicalTarget == canonicalTranscript,
      method: 'transcript-edit-distance-v1',
      engine: event.engine,
      locale: event.locale,
      occurredAtUtc: event.recognizedAtUtc,
    );
  }

  static String _canonical(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static int _levenshtein(String left, String right) {
    final a = left.runes.toList(growable: false);
    final b = right.runes.toList(growable: false);
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var row = 0; row < a.length; row += 1) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = row + 1;
      for (var column = 0; column < b.length; column += 1) {
        final substitution = previous[column] + (a[row] == b[column] ? 0 : 1);
        current[column + 1] = math.min(
          math.min(current[column] + 1, previous[column + 1] + 1),
          substitution,
        );
      }
      previous = current;
    }
    return previous.last;
  }
}
