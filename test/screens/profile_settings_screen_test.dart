import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';

void main() {
  testWidgets('profile renders only evidence-derived progress', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileSettingsScreen(loader: () async => _progress)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ผู้เรียน Guest'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('7 วัน'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.textContaining('อัลกอริทึม v1'), findsOneWidget);
    expect(find.textContaining('Khun Phet'), findsNothing);
  });
}

const _progress = ProgressSnapshot(
  sampleSize: 10,
  correctCount: 8,
  wrongCount: 2,
  accuracy: .8,
  totalXp: 42,
  completedSessions: 2,
  streakDays: 7,
  dueReviewCount: 1,
  masteredWordCount: 2,
  achievementCount: 1,
  gameLevel: 3,
  skills: [],
  weaknesses: [],
  recommendations: [],
);
