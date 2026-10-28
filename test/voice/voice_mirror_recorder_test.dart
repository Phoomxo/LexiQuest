import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vocab_learning_app/voice/voice_mirror_recorder.dart';

Matcher _failure(VoiceMirrorRecorderFailureCode code) {
  return isA<VoiceMirrorRecorderFailure>().having(
    (failure) => failure.code,
    'code',
    code,
  );
}

/// Fake [RecordSession] that writes a WAV-like file to the requested path and
/// records lifecycle calls.
final class _FakeRecordSession implements RecordSession {
  _FakeRecordSession({Uint8List? bytes}) : bytes = bytes ?? _validWav;

  final Uint8List bytes;

  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> start({required String path}) async {
    startCalls += 1;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<String?> stop() async {
    stopCalls += 1;
    return null;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}

final Uint8List _validWav = Uint8List.fromList([
  0x52, 0x49, 0x46, 0x46, // RIFF
  0x24, 0x00, 0x00, 0x00, // size
  0x57, 0x41, 0x56, 0x45, // WAVE
  0x66, 0x6d, 0x74, 0x20, // fmt chunk
]);

Future<Directory> _tempEnrollmentDir() async {
  final tmp = await Directory.systemTemp.createTemp('voice_mirror_enroll_test');
  final dir = Directory(
    '${tmp.path}${Platform.pathSeparator}voice_mirror_enrollment',
  );
  return dir;
}

void main() {
  group('permission', () {
    test('does not start recording when permission is not granted', () async {
      final dir = await _tempEnrollmentDir();
      final recorder = VoiceMirrorRecorder(
        requestMicrophonePermission: () async => PermissionStatus.denied,
        createRecordSession: () => _FakeRecordSession(),
        enrollmentDirectory: () async => dir,
        generateFileName: _fixedName,
      );

      await expectLater(
        recorder.start(),
        throwsA(_failure(VoiceMirrorRecorderFailureCode.permissionDenied)),
      );
      expect(recorder.isRecording, isFalse);
      addTearDown(() => tmpDirCleanup(dir));
    });

    test('starts recording when permission is granted', () async {
      final dir = await _tempEnrollmentDir();
      final session = _FakeRecordSession();
      final recorder = VoiceMirrorRecorder(
        requestMicrophonePermission: () async => PermissionStatus.granted,
        createRecordSession: () => session,
        enrollmentDirectory: () async => dir,
        generateFileName: _fixedName,
      );

      await recorder.start();

      expect(session.startCalls, 1);
      expect(recorder.isRecording, isTrue);
      await recorder.dispose();
      addTearDown(() => tmpDirCleanup(dir));
    });
  });

  group('stop', () {
    test('returns WAV bytes and deletes the file', () async {
      final dir = await _tempEnrollmentDir();
      final session = _FakeRecordSession();
      final recorder = VoiceMirrorRecorder(
        requestMicrophonePermission: () async => PermissionStatus.granted,
        createRecordSession: () => session,
        enrollmentDirectory: () async => dir,
        generateFileName: _fixedName,
      );

      await recorder.start();
      final filePath = recorder.currentFilePath;
      expect(filePath, isNotNull);
      expect(await File(filePath!).exists(), isTrue);

      final bytes = await recorder.stop();

      expect(bytes, _validWav);
      expect(session.stopCalls, 1);
      expect(await File(filePath).exists(), isFalse);
      expect(recorder.isRecording, isFalse);
      await recorder.dispose();
      addTearDown(() => tmpDirCleanup(dir));
    });

    test('rejects an empty file', () async {
      final dir = await _tempEnrollmentDir();
      final session = _FakeRecordSession(bytes: Uint8List(0));
      final recorder = VoiceMirrorRecorder(
        requestMicrophonePermission: () async => PermissionStatus.granted,
        createRecordSession: () => session,
        enrollmentDirectory: () async => dir,
        generateFileName: _fixedName,
      );

      await recorder.start();
      await expectLater(
        recorder.stop(),
        throwsA(_failure(VoiceMirrorRecorderFailureCode.emptyRecording)),
      );
      addTearDown(() => tmpDirCleanup(dir));
    });

    test('rejects a file larger than the byte limit', () async {
      final dir = await _tempEnrollmentDir();
      final huge = Uint8List.fromList(List<int>.filled(11, 0x42));
      final session = _FakeRecordSession(bytes: huge);
      final recorder = VoiceMirrorRecorder(
        requestMicrophonePermission: () async => PermissionStatus.granted,
        createRecordSession: () => session,
        enrollmentDirectory: () async => dir,
        generateFileName: _fixedName,
        maxBytes: 10,
      );

      await recorder.start();
      await expectLater(
        recorder.stop(),
        throwsA(_failure(VoiceMirrorRecorderFailureCode.tooLarge)),
      );
      addTearDown(() => tmpDirCleanup(dir));
    });
  });

  group('cancel and lifecycle cleanup', () {
    test('cancel deletes the partial file', () async {
      final dir = await _tempEnrollmentDir();
      final session = _FakeRecordSession();
      final recorder = VoiceMirrorRecorder(
        requestMicrophonePermission: () async => PermissionStatus.granted,
        createRecordSession: () => session,
        enrollmentDirectory: () async => dir,
        generateFileName: _fixedName,
      );

      await recorder.start();
      final filePath = recorder.currentFilePath!;
      expect(await File(filePath).exists(), isTrue);

      await recorder.cancel();

      // Cancel stops the in-flight recording so the plugin releases resources,
      // then deletes the partial file.
      expect(session.stopCalls, 1);
      expect(await File(filePath).exists(), isFalse);
      expect(recorder.isRecording, isFalse);
      await recorder.dispose();
      addTearDown(() => tmpDirCleanup(dir));
    });

    test('dispose deletes the partial file and the session', () async {
      final dir = await _tempEnrollmentDir();
      final session = _FakeRecordSession();
      final recorder = VoiceMirrorRecorder(
        requestMicrophonePermission: () async => PermissionStatus.granted,
        createRecordSession: () => session,
        enrollmentDirectory: () async => dir,
        generateFileName: _fixedName,
      );

      await recorder.start();
      final filePath = recorder.currentFilePath!;

      await recorder.dispose();

      expect(session.disposeCalls, 1);
      expect(await File(filePath).exists(), isFalse);
      expect(recorder.isRecording, isFalse);
    });

    test('repeated stop/cancel/dispose do not throw', () async {
      final dir = await _tempEnrollmentDir();
      final recorder = VoiceMirrorRecorder(
        requestMicrophonePermission: () async => PermissionStatus.granted,
        createRecordSession: () => _FakeRecordSession(),
        enrollmentDirectory: () async => dir,
        generateFileName: _fixedName,
      );

      await recorder.start();
      await recorder.stop();
      await recorder.stop();
      await recorder.cancel();
      await recorder.cancel();
      await recorder.dispose();
      await recorder.dispose();
      addTearDown(() => tmpDirCleanup(dir));
    });
  });

  group('startup purge', () {
    test(
      'deletes only stale files inside the voice mirror directory',
      () async {
        final dir = await _tempEnrollmentDir();
        await dir.create(recursive: true);
        final staleFile = File('${dir.path}${Platform.pathSeparator}stale.wav');
        await staleFile.writeAsBytes(_validWav);
        expect(await staleFile.exists(), isTrue);

        final recorder = VoiceMirrorRecorder(
          requestMicrophonePermission: () async => PermissionStatus.granted,
          createRecordSession: () => _FakeRecordSession(),
          enrollmentDirectory: () async => dir,
          generateFileName: _fixedName,
        );

        await recorder.purgeStaleFiles();

        expect(await staleFile.exists(), isFalse);
        expect(await dir.exists(), isTrue);
        await recorder.dispose();
        addTearDown(() => tmpDirCleanup(dir));
      },
    );

    test('purge is a no-op when the directory does not exist', () async {
      final dir = await _tempEnrollmentDir();
      final recorder = VoiceMirrorRecorder(
        requestMicrophonePermission: () async => PermissionStatus.granted,
        createRecordSession: () => _FakeRecordSession(),
        enrollmentDirectory: () async => dir,
        generateFileName: _fixedName,
      );

      await recorder.purgeStaleFiles();
      expect(await dir.exists(), isFalse);
      await recorder.dispose();
      addTearDown(() => tmpDirCleanup(dir));
    });
  });
}

String _fixedName() => 'enrollment.wav';

Future<void> tmpDirCleanup(Directory dir) async {
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}
