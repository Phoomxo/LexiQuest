import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

/// Typed failure code for ephemeral voice-mirror enrollment capture.
enum VoiceMirrorRecorderFailureCode {
  permissionDenied,
  permissionPermanentlyDenied,
  emptyRecording,
  tooLarge,
  startFailed,
  readFailed,
  cancelled,
  unknown,
}

/// Privacy-safe recorder failure: carries only a typed code, never audio,
/// paths, or participant identifiers.
final class VoiceMirrorRecorderFailure implements Exception {
  const VoiceMirrorRecorderFailure(this.code);

  final VoiceMirrorRecorderFailureCode code;

  @override
  String toString() => 'VoiceMirrorRecorderFailure(${code.name})';
}

/// Abstracts the platform recorder so unit tests can capture WAV bytes without
/// invoking the real [AudioRecorder] plugin.
abstract interface class RecordSession {
  Future<void> start({required String path});
  Future<String?> stop();
  Future<void> dispose();
}

/// Default [RecordSession] wrapping the [AudioRecorder] plugin.
class _PluginRecordSession implements RecordSession {
  _PluginRecordSession(this._recorder);

  final AudioRecorder _recorder;

  static const _config = RecordConfig(
    encoder: AudioEncoder.wav,
    bitRate: 256000,
    sampleRate: 16000,
    numChannels: 1,
    autoGain: false,
    echoCancel: false,
    noiseSuppress: false,
  );

  @override
  Future<void> start({required String path}) =>
      _recorder.start(_config, path: path);

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// Captures a temporary, bounded enrollment WAV for the participant voice
/// mirror and erases it on every termination path.
///
/// The enrollment file lives only in a dedicated cache subdirectory
/// (`voice_mirror_enrollment`). It is never written to Firebase, Drift,
/// research export, media storage, or backup. [stop] reads the bounded bytes
/// and deletes the file before returning; [cancel], [dispose], and an
/// unexpected error do the same. [purgeStaleFiles] cleans files left behind
/// by a previous crash at startup.
class VoiceMirrorRecorder {
  VoiceMirrorRecorder({
    Future<PermissionStatus> Function()? requestMicrophonePermission,
    RecordSession Function()? createRecordSession,
    Future<Directory> Function()? enrollmentDirectory,
    String Function()? generateFileName,
    this._maxBytes = 2 * 1024 * 1024,
    this._maxDuration = const Duration(seconds: 10),
  }) : _requestMicrophonePermission =
           requestMicrophonePermission ?? _defaultRequestMicrophonePermission,
       _createRecordSession =
           createRecordSession ?? _defaultCreateRecordSession,
       _enrollmentDirectory =
           enrollmentDirectory ?? _defaultEnrollmentDirectory,
       _generateFileName = generateFileName ?? _defaultGenerateFileName;

  final Future<PermissionStatus> Function() _requestMicrophonePermission;
  final RecordSession Function() _createRecordSession;
  final Future<Directory> Function() _enrollmentDirectory;
  final String Function() _generateFileName;
  final int _maxBytes;
  final Duration _maxDuration;

  RecordSession? _session;
  String? _currentFilePath;
  Timer? _autoStopTimer;
  bool _disposed = false;

  /// The path of the temporary file currently being recorded, if any.
  String? get currentFilePath => _currentFilePath;

  /// Whether a recording is in progress.
  bool get isRecording => _session != null && !_disposed;

  /// Requests microphone permission and starts recording to a randomized
  /// file inside the enrollment cache directory.
  Future<void> start() async {
    _checkNotDisposed();
    if (_session != null) {
      throw StateError('A voice mirror recording is already in progress.');
    }

    final status = await _requestMicrophonePermission();
    if (status.isPermanentlyDenied) {
      throw const VoiceMirrorRecorderFailure(
        VoiceMirrorRecorderFailureCode.permissionPermanentlyDenied,
      );
    }
    if (!status.isGranted && !status.isLimited) {
      throw const VoiceMirrorRecorderFailure(
        VoiceMirrorRecorderFailureCode.permissionDenied,
      );
    }

    final directory = await _enrollmentDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final path =
        '${directory.path}${Platform.pathSeparator}${_generateFileName()}';

    final session = _createRecordSession();
    try {
      await session.start(path: path);
    } on Object {
      await _safeDisposeSession(session);
      await _deleteFile(path);
      throw const VoiceMirrorRecorderFailure(
        VoiceMirrorRecorderFailureCode.startFailed,
      );
    }

    _session = session;
    _currentFilePath = path;
    _autoStopTimer = Timer(_maxDuration, _autoStop);
  }

  /// Stops recording, reads the bounded WAV bytes, and deletes the file
  /// before returning.
  Future<Uint8List> stop() async {
    final session = _session;
    final path = _currentFilePath;
    if (session == null || path == null) {
      return Uint8List(0);
    }
    _cancelTimer();
    _session = null;
    _currentFilePath = null;

    try {
      await session.stop();
    } on Object {
      await _safeDisposeSession(session);
      await _deleteFile(path);
      throw const VoiceMirrorRecorderFailure(
        VoiceMirrorRecorderFailureCode.readFailed,
      );
    }
    await _safeDisposeSession(session);

    final file = File(path);
    final Uint8List bytes;
    try {
      if (!await file.exists()) {
        throw const VoiceMirrorRecorderFailure(
          VoiceMirrorRecorderFailureCode.readFailed,
        );
      }
      bytes = await file.readAsBytes();
    } on VoiceMirrorRecorderFailure {
      rethrow;
    } on Object {
      throw const VoiceMirrorRecorderFailure(
        VoiceMirrorRecorderFailureCode.readFailed,
      );
    } finally {
      await _deleteFile(path);
    }

    if (bytes.isEmpty) {
      throw const VoiceMirrorRecorderFailure(
        VoiceMirrorRecorderFailureCode.emptyRecording,
      );
    }
    if (bytes.length > _maxBytes) {
      throw const VoiceMirrorRecorderFailure(
        VoiceMirrorRecorderFailureCode.tooLarge,
      );
    }
    return bytes;
  }

  /// Cancels the in-flight recording and deletes the partial file.
  Future<void> cancel() async {
    final session = _session;
    final path = _currentFilePath;
    _cancelTimer();
    _session = null;
    _currentFilePath = null;
    if (session == null) return;
    try {
      await session.stop();
    } on Object {
      // Cancellation must still clean up the file below.
    }
    await _safeDisposeSession(session);
    if (path != null) {
      await _deleteFile(path);
    }
  }

  /// Releases the recorder and deletes any in-flight file. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelTimer();
    await cancel();
  }

  /// Deletes every file left inside the enrollment directory. Used at startup
  /// to erase files from a previous crash. Missing file is success.
  Future<void> purgeStaleFiles() async {
    _checkNotDisposed();
    final directory = await _enrollmentDirectory();
    if (!await directory.exists()) return;
    try {
      await for (final entity in directory.list()) {
        try {
          await entity.delete(recursive: true);
        } on FileSystemException {
          // A per-file failure is recorded without path or content; purge is
          // idempotent and bounded.
        }
      }
    } on FileSystemException {
      // The directory vanished between checks; nothing to purge.
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('VoiceMirrorRecorder is disposed.');
    }
  }

  void _cancelTimer() {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
  }

  Future<void> _autoStop() async {
    try {
      await stop();
    } on VoiceMirrorRecorderFailure {
      // The bounded-duration auto stop reports the same way as an explicit one.
    }
  }

  Future<void> _safeDisposeSession(RecordSession session) async {
    try {
      await session.dispose();
    } on Object {
      // Dispose is best-effort; the file cleanup is the privacy boundary.
    }
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Missing file is success; a failed delete is bounded by purge at next
      // startup.
    }
  }

  static Future<PermissionStatus> _defaultRequestMicrophonePermission() =>
      Permission.microphone.request();

  static RecordSession _defaultCreateRecordSession() =>
      _PluginRecordSession(AudioRecorder());

  static Future<Directory> _defaultEnrollmentDirectory() async {
    final cache = await getTemporaryDirectory();
    return Directory(
      '${cache.path}${Platform.pathSeparator}voice_mirror_enrollment',
    );
  }

  static String _defaultGenerateFileName() => '${const Uuid().v4()}.wav';
}
