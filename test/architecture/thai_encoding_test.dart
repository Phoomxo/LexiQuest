import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory _repositoryRoot() {
  var directory = File(Platform.script.toFilePath()).parent;
  while (directory.parent.path != directory.path) {
    if (File('${directory.path}/pubspec.yaml').existsSync()) {
      return directory;
    }
    directory = directory.parent;
  }
  return Directory.current;
}

void main() {
  test(
    'participant source and documentation contain no invalid text encoding',
    () {
      final root = _repositoryRoot();
      final roots = <Directory>[
        Directory('${root.path}/lib'),
        Directory('${root.path}/test'),
        Directory('${root.path}/docs'),
      ];
      final failures = <String>[];

      for (final directory in roots.where((entry) => entry.existsSync())) {
        for (final entity in directory.listSync(recursive: true)) {
          if (entity is! File ||
              !const <String>{
                '.dart',
                '.md',
                '.json',
                '.yaml',
                '.yml',
              }.contains(_extension(entity.path))) {
            continue;
          }
          final text = entity.readAsStringSync();
          final hasReplacementCharacter = text.contains('\uFFFD');
          final hasC1Control = text.runes.any(
            (codePoint) => codePoint >= 0x80 && codePoint <= 0x9F,
          );
          if (hasReplacementCharacter || hasC1Control) {
            failures.add(entity.path.substring(root.path.length + 1));
          }
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            'Invalid or mojibake-prone Unicode found in: ${failures.join(', ')}',
      );
    },
  );
}

String _extension(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot).toLowerCase();
}
