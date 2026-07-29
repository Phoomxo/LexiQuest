import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/supabase_client_config.dart';

const _acceptedKeys = <String>[
  'sb_publishable_VGhpc19hX3Rlc3Rfc3VmZml4',
  'sb_publishable_Aa1-_7Z9',
];

const _rejectedKeys = <String>[
  '',
  '   ',
  'sb_publishable_',
  'sb_publishable',
  'sb_secret_VGhpc19hX3NlY3JldA',
  'sb_publishable_bad!chars',
  'sb_publishable_with space',
  'ey'
      'JhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.c2lnbmF0dXJl',
  ' sb_publishable_VGhpc19hX3Rlc3Rfc3VmZml4',
  'sb_publishable_VGhpc19hX3Rlc3Rfc3VmZml4 ',
];

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

void main() {
  group('requireSupabasePublishableKey', () {
    for (final key in _acceptedKeys) {
      test('returns a valid publishable key unchanged', () {
        expect(requireSupabasePublishableKey(key), key);
      });
    }

    for (final value in _rejectedKeys) {
      test('rejects an invalid key without leaking it', () {
        Object? captured;
        try {
          requireSupabasePublishableKey(value);
          fail('Expected SupabaseConfigurationException.');
        } on SupabaseConfigurationException catch (error) {
          captured = error;
        }

        expect(captured, isA<SupabaseConfigurationException>());
        if (value.isNotEmpty) {
          expect(captured.toString(), isNot(contains(value)));
        }
      });
    }
  });

  group('app_bootstrap.dart publishable-key sourcing', () {
    final source = File(
      '${_repositoryRoot().path}/lib/runtime/app_bootstrap.dart',
    ).readAsStringSync();

    test('declares the publishable key environment variable', () {
      expect(source, contains('LEXIQUEST_SUPABASE_PUBLISHABLE_KEY'));
    });

    test('does not bake a default into the publishable-key block', () {
      final block = RegExp(
        r"LEXIQUEST_SUPABASE_PUBLISHABLE_KEY.*?\)",
        dotAll: true,
      ).firstMatch(source);

      expect(block, isNotNull);
      expect(block!.group(0), isNot(contains('defaultValue')));
    });

    test('ships no legacy Supabase anon JWT literal', () {
      expect(source, isNot(contains('eyJ')));
    });

    test('targets the controlled production project', () {
      expect(source, isNot(contains('anyiuoqnuimtjlbjhwuf')));
      expect(source, contains('https://jkiyfnlegmhodyxpfwpc.supabase.co'));
    });
  });
}
