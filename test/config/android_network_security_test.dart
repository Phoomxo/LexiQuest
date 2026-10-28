import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory? _findRepoRoot(String start) {
  var directory = Directory(start);
  for (var depth = 0; depth < 16; depth++) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        Directory('${directory.path}/android').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
  return null;
}

Directory _resolveRepositoryRoot() {
  final searchRoots = <String>[
    File(Platform.script.toFilePath()).parent.path,
    Directory.current.path,
  ];
  for (final root in searchRoots) {
    final found = _findRepoRoot(root);
    if (found != null) return found;
  }
  return Directory.current;
}

String _readOrEmpty(File file) {
  return file.existsSync() ? file.readAsStringSync() : '';
}

void main() {
  final repoRoot = _resolveRepositoryRoot();
  final androidAppSrc = Directory('${repoRoot.path}/android/app/src');

  group('repository layout', () {
    test('resolves android/app/src from the repository root', () {
      expect(androidAppSrc.existsSync(), isTrue);
    });
  });

  group('main manifest keeps release HTTPS-only', () {
    test('main AndroidManifest.xml exists', () {
      final manifest = File('${androidAppSrc.path}/main/AndroidManifest.xml');
      expect(manifest.existsSync(), isTrue);
    });

    test('main manifest never globally permits cleartext', () {
      final manifest = File('${androidAppSrc.path}/main/AndroidManifest.xml');
      expect(
        _readOrEmpty(manifest),
        isNot(contains('usesCleartextTraffic="true"')),
      );
    });
  });

  group('debug Android outlet is narrowed by the Dart RFC 1918 allowlist', () {
    test('debug AndroidManifest.xml exists', () {
      final manifest = File('${androidAppSrc.path}/debug/AndroidManifest.xml');
      expect(manifest.existsSync(), isTrue);
    });

    test('debug application references its network security config', () {
      final manifest = File('${androidAppSrc.path}/debug/AndroidManifest.xml');
      expect(
        _readOrEmpty(manifest),
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ),
      );
    });

    test('debug manifest does not use a global cleartext flag', () {
      final manifest = File('${androidAppSrc.path}/debug/AndroidManifest.xml');
      expect(
        _readOrEmpty(manifest),
        isNot(contains('usesCleartextTraffic="true"')),
      );
    });

    test('debug network security config permits cleartext', () {
      final config = File(
        '${androidAppSrc.path}/debug/res/xml/network_security_config.xml',
      );
      expect(config.existsSync(), isTrue);
      expect(
        _readOrEmpty(config),
        contains('cleartextTrafficPermitted="true"'),
      );
    });

    test('debug overlay changes only application network policy', () {
      final content = _readOrEmpty(
        File('${androidAppSrc.path}/debug/AndroidManifest.xml'),
      );
      expect(
        content,
        isNot(contains('<activity')),
        reason: 'debug overlay must not duplicate MainActivity',
      );
      expect(
        content,
        isNot(contains('<uses-permission')),
        reason: 'debug overlay must not duplicate main permissions',
      );
      expect(
        content,
        contains('<application'),
        reason: 'debug overlay must carry the network policy',
      );
    });
  });

  group('non-debug source sets stay HTTPS-only', () {
    Iterable<File> xmlFilesUnder(String sourceSet) {
      final directory = Directory('${androidAppSrc.path}/$sourceSet');
      if (!directory.existsSync()) return const <File>[];
      return directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.xml'));
    }

    for (final sourceSet in ['main', 'profile', 'release']) {
      test('$sourceSet XML never permits cleartext', () {
        for (final xml in xmlFilesUnder(sourceSet)) {
          expect(
            _readOrEmpty(xml),
            isNot(contains('cleartextTrafficPermitted="true"')),
            reason: '$sourceSet must not permit cleartext: ${xml.path}',
          );
        }
      });

      test('$sourceSet manifest never globally permits cleartext', () {
        final manifest = File(
          '${androidAppSrc.path}/$sourceSet/AndroidManifest.xml',
        );
        expect(
          _readOrEmpty(manifest),
          isNot(contains('usesCleartextTraffic="true"')),
        );
      });
    }
  });
}
