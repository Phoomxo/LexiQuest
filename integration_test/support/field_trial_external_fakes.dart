import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';

final class HostFakeExportStore implements ExportArtifactStore {
  ExportArtifact? artifact;

  @override
  Future<ExportSaveResult> save(
    ExportArtifact value, {
    required ExportCancellation cancellation,
  }) async {
    cancellation.throwIfCancelled();
    artifact = value;
    return ExportSaveResult(
      path: 'host-fake-export',
      bytesWritten: value.bytes.length,
    );
  }
}

final class HostFakeCameraGateway implements CameraGateway {
  @override
  bool isInitialized = false;

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<CapturedImage> capture() async => CapturedImage(
    bytes: Uint8List(0),
    capturedAtUtc: DateTime.utc(2026, 8, 13),
    rotationDegrees: 0,
  );

  @override
  Future<void> dispose() async => isInitialized = false;

  @override
  Future<void> initialize() async => isInitialized = true;

  @override
  Future<void> pause() async => isInitialized = false;

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.unavailable;

  @override
  Future<void> resume() async => isInitialized = true;
}

final class HostFakeSpeechRecognitionGateway
    implements SpeechRecognitionGateway {
  @override
  bool isListening = false;

  @override
  Future<void> cancel() async => isListening = false;

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.unavailable;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async => isListening = true;

  @override
  Future<void> stop() async => isListening = false;
}
