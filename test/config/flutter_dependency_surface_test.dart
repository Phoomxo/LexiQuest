import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory? _findRepoRoot(String start) {
  var directory = Directory(start);
  for (var depth = 0; depth < 16; depth++) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        Directory('${directory.path}/lib').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
  return null;
}

Directory _repositoryRoot() {
  for (final start in <String>[
    File(Platform.script.toFilePath()).parent.path,
    Directory.current.path,
  ]) {
    final found = _findRepoRoot(start);
    if (found != null) return found;
  }
  return Directory.current;
}

bool _declaresDirectDependency(String manifest, String name) {
  return RegExp(
    '^  ${RegExp.escape(name)}:',
    multiLine: true,
  ).hasMatch(manifest);
}

void main() {
  final manifest = File('${_repositoryRoot().path}/pubspec.yaml');
  final contents = manifest.existsSync() ? manifest.readAsStringSync() : '';

  test('unused direct dependencies are absent', () {
    const removed = <String>[
      'cupertino_icons',
      'firebase_storage',
      'provider',
      'image_picker',
      'fluttertoast',
      'confetti',
      'cached_network_image',
      'google_mlkit_image_labeling',
      'google_fonts',
    ];

    expect(manifest.existsSync(), isTrue);
    for (final name in removed) {
      expect(
        _declaresDirectDependency(contents, name),
        isFalse,
        reason: '$name should not be a direct dependency',
      );
    }
  });

  test('used direct dependencies remain', () {
    const retained = <String>[
      'firebase_core',
      'firebase_auth',
      'firebase_app_check',
      'cloud_firestore',
      'speech_to_text',
      'flutter_tts',
      'fl_chart',
      'http',
      'supabase_flutter',
      'shared_preferences',
      'flutter_speed_dial',
      'audioplayers',
      'camera',
      'permission_handler',
      'image',
      'flutter_secure_storage',
      'pdf',
      'file_selector',
    ];

    for (final name in retained) {
      expect(
        _declaresDirectDependency(contents, name),
        isTrue,
        reason: '$name must remain a direct dependency',
      );
    }
  });
}
