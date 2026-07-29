import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory? _findRepoRoot(String start) {
  var directory = Directory(start);
  for (var depth = 0; depth < 16; depth++) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        Directory('${directory.path}/supabase/migrations').existsSync()) {
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

void main() {
  final migration = File(
    '${_repositoryRoot().path}/supabase/migrations/'
    '20260727000000_image_bucket_public_readonly.sql',
  ).readAsStringSync();

  test('removes legacy broad storage policies during upgrade', () {
    for (final policy in <String>[
      'allow-delete-store-images 164ncr_0',
      'allow-insert-store-images 164ncr_0',
      'allow-select-store-images 164ncr_0',
      'allow-update-store-images 164ncr_0',
    ]) {
      expect(
        migration,
        contains('DROP POLICY IF EXISTS "$policy" ON storage.objects;'),
      );
    }
  });

  test('keeps every non-Image bucket private', () {
    expect(
      migration,
      contains(
        "UPDATE storage.buckets\n"
        "SET public = false\n"
        "WHERE id <> 'Image' AND public = true;",
      ),
    );
  });
}
