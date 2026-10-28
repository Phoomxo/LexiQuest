import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/media_practice_contracts.dart';

abstract interface class CameraSession {
  bool get isInitialized;
  int get sensorOrientation;
  Widget buildPreview();
  Future<void> initialize();
  Future<XFile> takePicture();
  Future<void> dispose();
}

final class PluginCameraGateway implements CameraGateway {
  PluginCameraGateway({
    DateTime Function()? nowUtc,
    Future<List<CameraDescription>> Function()? discoverCameras,
    CameraSession Function(CameraDescription)? createSession,
  }) : _nowUtc = nowUtc ?? _systemNowUtc,
       _discoverCameras = discoverCameras ?? availableCameras,
       _createSession =
           createSession ??
           ((description) => _PluginCameraSession(description));

  final DateTime Function() _nowUtc;
  final Future<List<CameraDescription>> Function() _discoverCameras;
  final CameraSession Function(CameraDescription) _createSession;
  CameraSession? _session;
  CameraDescription? _selectedCamera;
  Future<void>? _initialization;
  int? _initializationGeneration;
  int _lifecycleGeneration = 0;
  bool _disposed = false;

  static DateTime _systemNowUtc() => DateTime.now().toUtc();

  @override
  bool get isInitialized => !_disposed && (_session?.isInitialized ?? false);

  @override
  Future<MediaPermissionState> requestPermission() async {
    final status = await Permission.camera.request();
    return _mapPermission(status);
  }

  @override
  Future<void> initialize() async {
    _checkNotDisposed();
    if (isInitialized) return;
    final inFlight = _initialization;
    final inFlightGeneration = _initializationGeneration;
    if (inFlight != null) {
      try {
        await inFlight;
      } on Object {
        if (inFlightGeneration == _lifecycleGeneration) rethrow;
      }
      _checkNotDisposed();
      if (isInitialized) return;
      return initialize();
    }

    final generation = _lifecycleGeneration;
    final operation = _initializeForGeneration(generation);
    _initialization = operation;
    _initializationGeneration = generation;
    try {
      await operation;
    } finally {
      if (identical(_initialization, operation)) {
        _initialization = null;
        _initializationGeneration = null;
      }
    }
  }

  Future<void> _initializeForGeneration(int generation) async {
    CameraSession? pendingSession;
    try {
      final cameras = await _discoverCameras();
      if (cameras.isEmpty) {
        throw const CameraPracticeException(CameraFailureCode.unavailable);
      }
      _selectedCamera ??= cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      pendingSession = _createSession(_selectedCamera!);
      await pendingSession.initialize();
      if (_disposed || generation != _lifecycleGeneration) {
        await pendingSession.dispose();
        return;
      }
      _session = pendingSession;
    } on CameraException catch (error) {
      await pendingSession?.dispose();
      final code = switch (error.code) {
        'CameraAccessDenied' => CameraFailureCode.permissionDenied,
        'CameraAccessDeniedWithoutPrompt' || 'CameraAccessRestricted' =>
          CameraFailureCode.permissionPermanentlyDenied,
        _ => CameraFailureCode.initializationFailed,
      };
      throw CameraPracticeException(code);
    }
  }

  @override
  Widget buildPreview() {
    final session = _session;
    if (session == null || !session.isInitialized) {
      return const SizedBox.shrink();
    }
    return session.buildPreview();
  }

  @override
  Future<CapturedImage> capture() async {
    final session = _session;
    if (session == null || !session.isInitialized) {
      throw const CameraPracticeException(CameraFailureCode.unavailable);
    }
    XFile? capture;
    try {
      capture = await session.takePicture();
      final bytes = Uint8List.fromList(await capture.readAsBytes());
      return CapturedImage(
        bytes: bytes,
        capturedAtUtc: _nowUtc(),
        rotationDegrees: session.sensorOrientation,
      );
    } on CameraException {
      throw const CameraPracticeException(CameraFailureCode.captureFailed);
    } finally {
      final path = capture?.path;
      if (path != null) {
        final temporaryCapture = File(path);
        if (await temporaryCapture.exists()) {
          await temporaryCapture.delete();
        }
      }
    }
  }

  @override
  Future<void> pause() async {
    _lifecycleGeneration += 1;
    final session = _session;
    final initialization = _initialization;
    _session = null;
    await session?.dispose();
    if (initialization != null) {
      try {
        await initialization;
      } on Object {
        // The initialize caller receives the original failure. Lifecycle cleanup
        // still completes without replacing it with a second unhandled error.
      }
    }
  }

  @override
  Future<void> resume() => initialize();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await pause();
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('PluginCameraGateway is disposed.');
  }

  static MediaPermissionState _mapPermission(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return MediaPermissionState.granted;
    }
    if (status.isPermanentlyDenied) {
      return MediaPermissionState.permanentlyDenied;
    }
    if (status.isRestricted) return MediaPermissionState.restricted;
    if (status.isDenied) return MediaPermissionState.denied;
    return MediaPermissionState.unavailable;
  }
}

final class _PluginCameraSession implements CameraSession {
  _PluginCameraSession(CameraDescription description)
    : _controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
      );

  final CameraController _controller;

  @override
  bool get isInitialized => _controller.value.isInitialized;

  @override
  int get sensorOrientation => _controller.description.sensorOrientation;

  @override
  Widget buildPreview() => CameraPreview(_controller);

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<XFile> takePicture() => _controller.takePicture();

  @override
  Future<void> dispose() => _controller.dispose();
}
