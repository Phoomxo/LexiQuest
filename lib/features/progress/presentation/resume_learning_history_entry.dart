import 'package:flutter/material.dart';

import '../../../navigation/app_routes.dart';
import '../../../runtime/app_dependencies.dart';
import '../../../screens/matching_quiz_screen.dart';
import '../../../screens/quiz_screen.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/presentation/native_exercise_resume_screen.dart';
import '../domain/learning_history_models.dart';

const nativeHistoryActivities = {
  'dictation',
  'wordScramble',
  'sentenceScramble',
  'cloze',
};

bool canOpenLearningHistoryEntry(LearningHistoryEntry entry) =>
    (entry.hasAcceptedMatching &&
        entry.activityType == 'matching' &&
        const {'active', 'completed'}.contains(entry.state)) ||
    (entry.hasAcceptedNative &&
        nativeHistoryActivities.contains(entry.activityType) &&
        const {'active', 'completed'}.contains(entry.state)) ||
    (entry.hasAcceptedQuiz &&
        entry.state == 'active' &&
        const {
          'quiz',
          'weaknessPractice',
          'sourcePractice',
        }.contains(entry.activityType));

String learningHistoryActivityName(String value) => switch (value) {
  'quiz' || 'meaningChoice' => 'แบบทดสอบ',
  'flashcard' || 'flashcards' => 'แฟลชการ์ด',
  'srsReview' => 'ทบทวนคำศัพท์',
  'listening' => 'ฝึกฟัง',
  'dictation' => 'เขียนตามเสียง',
  'cloze' => 'เติมคำในบริบท',
  'wordScramble' => 'เกมเรียงตัวอักษร',
  'sentenceScramble' => 'เกมเรียงประโยค',
  'matching' => 'เกมจับคู่คำศัพท์',
  'pronunciation' || 'pronunciationTranscript' => 'ฝึกออกเสียง',
  'shadowing' => 'ฝึกพูดตาม',
  'ghostSpelling' => 'ฝึกสะกดคำ',
  'associativeRecall' => 'ฝึกจำคำศัพท์',
  _ => 'ฝึกคำศัพท์',
};

Future<void> resumeLearningHistoryEntry(
  BuildContext context, {
  required LearningHistoryEntry entry,
  required String expectedOwnerId,
  required AppDependencies? dependencies,
  required Stream<String?>? ownerChanges,
  required bool Function() stillCurrent,
  String languageCode = 'th',
  String? resultBackLabel,
}) async {
  if (!stillCurrent() || !canOpenLearningHistoryEntry(entry)) {
    throw StateError('Learning history is unavailable');
  }
  final learning = dependencies?.learning;
  if (entry.hasAcceptedMatching) {
    final matching = dependencies?.matching;
    final owners = ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
    if (matching == null || owners == null) {
      throw StateError('Matching history is unavailable');
    }
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'learning/resume-matching',
        builder: (_) => MatchingQuizScreen(
          matching: matching,
          expectedOwnerId: expectedOwnerId,
          ownerChanges: owners,
          resumeSessionId: entry.sessionId,
          learning: learning,
          learningTime: dependencies?.learningTime,
          languageCode: languageCode,
          resultBackLabel: resultBackLabel,
        ),
      ),
    );
    return;
  }
  if (entry.hasAcceptedNative) {
    if (learning == null) throw StateError('Learning history is unavailable');
    Future<LearningSessionSummary?> openNative() =>
        AppNavigator.pushPage<LearningSessionSummary>(
          context,
          AppPage<LearningSessionSummary>(
            name: 'learning/resume-native',
            builder: (_) => NativeExerciseResumeScreen(
              sessionId: entry.sessionId,
              expectedOwnerId: expectedOwnerId,
              learning: learning,
              stillCurrent: stillCurrent,
              languageCode: languageCode,
              ownerChanges: ownerChanges,
              voice: dependencies?.voice,
              learningTime: dependencies?.learningTime,
              resultBackLabel: resultBackLabel,
            ),
          ),
        );
    final summary = await openNative();
    if (stillCurrent() &&
        summary?.id == entry.sessionId &&
        summary?.state == 'completed') {
      await openNative();
    }
    return;
  }
  await AppNavigator.pushPage<void>(
    context,
    AppPage<void>(
      name: 'learning/resume-quiz',
      builder: (_) => QuizScreen(
        resumeSessionId: entry.sessionId,
        expectedOwnerId: expectedOwnerId,
        learning: learning,
        ownerChanges: ownerChanges,
        resultBackLabel: resultBackLabel,
      ),
    ),
  );
}
