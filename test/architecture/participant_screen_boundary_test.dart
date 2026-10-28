import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('participant screens use application ports and typed navigation', () {
    final forbiddenImports = RegExp(
      r"package:(cloud_firestore|firebase_auth|firebase_core|http|"
      r"shared_preferences|drift|camera|speech_to_text|flutter_tts|"
      r"permission_handler|file_selector|flutter_secure_storage|"
      r"supabase_flutter)",
    );
    final directRoutes = RegExp(
      r'MaterialPageRoute|pushNamed\(|pushReplacementNamed\(|'
      r'pushAndRemoveUntil\(|(?<!App)Navigator\.push',
    );
    final failures = <String>[];
    for (final file
        in Directory('lib/screens').listSync().whereType<File>().where(
          (file) => file.path.endsWith('.dart'),
        )) {
      final source = file.readAsStringSync();
      if (forbiddenImports.hasMatch(source)) {
        failures.add('${file.path}: imports infrastructure directly');
      }
      if (directRoutes.hasMatch(source)) {
        failures.add('${file.path}: bypasses typed AppNavigator');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
