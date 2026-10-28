import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/ghost_shadow_duel_screen.dart';

void main() {
  testWidgets('fresh account shows zero evidence and no sample words', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GhostShadowDuelScreen(
          progressLoader: () async => _empty,
          learning: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('จำนวนหลักฐาน: 0'), findsOneWidget);
    expect(find.text('perseverance'), findsNothing);
  });
}

const _empty = ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);
