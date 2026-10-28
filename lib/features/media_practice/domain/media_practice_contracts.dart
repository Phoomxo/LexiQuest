import 'dart:typed_data';

import 'package:flutter/widgets.dart';

enum MediaPermissionState {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  unavailable,
}

enum CameraFailureCode {
  permissionDenied,
  permissionPermanentlyDenied,
  unavailable,
  initializationFailed,
  captureFailed,
  modelUnavailable,
  invalidImage,
  cancelled,
}

final class CameraPracticeException implements Exception {
  const CameraPracticeException(this.code);

  final CameraFailureCode code;

  @override
  String toString() => 'CameraPracticeException(${code.name})';
}

final class CapturedImage {
  const CapturedImage({
    required this.bytes,
    required this.capturedAtUtc,
    required this.rotationDegrees,
  });

  final Uint8List bytes;
  final DateTime capturedAtUtc;
  final int rotationDegrees;
}

abstract interface class CameraGateway {
  bool get isInitialized;

  Future<MediaPermissionState> requestPermission();

  Future<void> initialize();

  Widget buildPreview();

  Future<CapturedImage> capture();

  Future<void> pause();

  Future<void> resume();

  Future<void> dispose();
}

enum SpeechFailureCode {
  permissionDenied,
  permissionPermanentlyDenied,
  unavailable,
  noMatch,
  cancelled,
  engine,
}

final class SpeechPracticeException implements Exception {
  const SpeechPracticeException(this.code);

  final SpeechFailureCode code;

  @override
  String toString() => 'SpeechPracticeException(${code.name})';
}

final class SpeechRecognitionEvent {
  const SpeechRecognitionEvent({
    required this.transcript,
    required this.isFinal,
    required this.recognizedAtUtc,
    required this.engine,
    required this.locale,
    this.recognitionConfidence,
  });

  final String transcript;
  final bool isFinal;
  final DateTime recognizedAtUtc;
  final String engine;
  final String locale;
  final double? recognitionConfidence;
}

typedef SpeechEventCallback = void Function(SpeechRecognitionEvent event);
typedef SpeechFailureCallback = void Function(SpeechFailureCode failure);

abstract interface class SpeechRecognitionGateway {
  bool get isListening;

  Future<MediaPermissionState> requestPermission();

  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  });

  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  });

  Future<void> stop();

  Future<void> cancel();
}

final class TranscriptPronunciationAssessment {
  const TranscriptPronunciationAssessment({
    required this.target,
    required this.transcript,
    required this.similarityPercent,
    required this.isExactMatch,
    required this.method,
    required this.engine,
    required this.locale,
    required this.occurredAtUtc,
  });

  final String target;
  final String transcript;
  final int similarityPercent;
  final bool isExactMatch;
  final String method;
  final String engine;
  final String locale;
  final DateTime occurredAtUtc;

  bool get hasAcousticPitchMeasurement => false;
  bool get hasPhonemeAlignment => false;
}
