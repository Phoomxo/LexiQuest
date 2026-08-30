import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/achievements/application/achievement_share_card_use_cases.dart';
import 'package:vocab_learning_app/features/achievements/presentation/achievement_share_card.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';

void main() {
  testWidgets(
    'renders a static accessible local preview with reviewed achievement metadata',
    (tester) async {
      final artifact = await _artifact();
      await tester.pumpWidget(
        MaterialApp(
          home: TickerMode(
            enabled: false,
            child: Scaffold(body: AchievementShareCard(artifact: artifact)),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('การ์ดความสำเร็จ: เรียนจบเซสชันแรก'),
        findsOneWidget,
      );
      expect(find.text('เรียนจบเซสชันแรก'), findsOneWidget);
      expect(find.text('นิยาม v7'), findsOneWidget);
      expect(find.text('ปลดล็อกเมื่อ 30/08/2026'), findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(find.textContaining('owner-1'), findsNothing);
      expect(find.textContaining('session-evidence-1'), findsNothing);
    },
  );

  testWidgets('does not claim a saved destination as part of the local card', (
    tester,
  ) async {
    final artifact = await _artifact();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AchievementShareCard(artifact: artifact)),
      ),
    );

    expect(find.textContaining('content://'), findsNothing);
    expect(find.textContaining('บันทึกแล้ว'), findsNothing);
    expect(find.byType(Card), findsOneWidget);
  });
}

Future<AchievementShareCardArtifact> _artifact() async {
  final result = await AchievementShareCardUseCases(store: _PreviewStore())
      .share(
        progress: ProgressSnapshot(
          sampleSize: 1,
          correctCount: 1,
          wrongCount: 0,
          accuracy: 1,
          totalXp: 1,
          completedSessions: 1,
          streakDays: 1,
          dueReviewCount: 0,
          masteredWordCount: 0,
          achievementCount: 1,
          gameLevel: 1,
          skills: const [],
          weaknesses: const [],
          recommendations: const [],
          achievements: <AchievementEvidence>[
            AchievementEvidence(
              id: 'first_session',
              definitionVersion: 7,
              sourceEventId: 'session-evidence-1',
              unlockedAtUtc: DateTime.utc(2026, 8, 30),
            ),
          ],
        ),
        achievementId: 'first_session',
        definitionVersion: 7,
        confirmed: true,
      );
  return result.artifact;
}

final class _PreviewStore implements AchievementShareCardStore {
  @override
  Future<AchievementShareCardStoreResult> selectDestinationAndSave(
    AchievementShareCardArtifact artifact,
  ) async => const AchievementShareCardStoreResult.saved(
    destination: 'memory://preview.svg',
  );
}
