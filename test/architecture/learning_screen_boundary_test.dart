import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'learning screens do not access cloud or persistence plugins directly',
    () {
      const paths = <String>[
        'lib/screens/choose_mode_screen.dart',
        'lib/screens/select_category_for_quiz.dart',
        'lib/screens/quiz_screen.dart',
        'lib/screens/score_screen.dart',
        'lib/screens/srs_flashcards_screen.dart',
      ];
      const forbidden = <String>[
        'cloud_firestore',
        'firebase_auth',
        'shared_preferences',
        'package:http',
        'package:drift',
      ];

      for (final path in paths) {
        final source = File(path).readAsStringSync();
        for (final package in forbidden) {
          expect(
            source,
            isNot(contains(package)),
            reason: '$path must use application dependencies, not $package',
          );
        }
      }
    },
  );
}
