import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'score rendering and quiz completion contain no Firestore counter mutation',
    () {
      final scoreSource = File(
        'lib/screens/score_screen.dart',
      ).readAsStringSync();
      final quizSource = File(
        'lib/screens/quiz_screen.dart',
      ).readAsStringSync();

      expect(scoreSource, isNot(contains('FirebaseFirestore')));
      expect(scoreSource, isNot(contains('FieldValue.increment')));
      expect(quizSource, isNot(contains('_savePointsToFirestore')));
      expect(quizSource, isNot(contains('FieldValue.increment')));
    },
  );
}
