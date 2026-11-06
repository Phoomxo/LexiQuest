import 'package:flutter/material.dart';

import '../../../navigation/app_routes.dart';
import '../../../runtime/app_dependencies.dart';
import '../../../runtime/field_feature.dart';
import '../../../runtime/registries/feature.dart';
import '../../../screens/matching_quiz_screen.dart';
import '../../../screens/quiz_screen.dart';
import '../../../screens/srs_flashcards_screen.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/presentation/native_exercise_resume_screen.dart';
import '../domain/learning_history_models.dart';

const nativeHistoryActivities = {
  'dictation',
  'wordScramble',
  'sentenceScramble',
  'cloze',
};

const srsRestartHint =
    'รอบนี้ไม่มีตำแหน่งบัตรที่บันทึกไว้ เริ่มรอบใหม่จากแพ็กหรือศูนย์ทบทวน';

String learningHistoryDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String learningHistoryDateTime(DateTime utc) {
  final value = utc.toLocal();
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${learningHistoryDate(value)} $hour:$minute';
}

bool canOpenLearningHistoryEntry(
  LearningHistoryEntry entry, {
  AppDependencies? dependencies,
}) =>
    (entry.activityType == 'srsReview' &&
        entry.state == 'active' &&
        entry.hasAcceptedSrs &&
        dependencies?.learning != null &&
        dependencies!.fieldFeatures.isVisible(FieldFeature.srs) &&
        dependencies.features.isVisible(Feature.srs)) ||
    (entry.hasAcceptedMatching &&
        entry.activityType == 'matching' &&
        const {'active', 'completed'}.contains(entry.state)) ||
    (entry.hasAcceptedNative &&
        nativeHistoryActivities.contains(entry.activityType) &&
        const {'active', 'completed'}.contains(entry.state)) ||
    (entry.hasAcceptedQuiz &&
        const {'active', 'completed'}.contains(entry.state) &&
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
  if (!stillCurrent() ||
      !canOpenLearningHistoryEntry(entry, dependencies: dependencies)) {
    throw StateError('Learning history is unavailable');
  }
  final learning = dependencies?.learning;
  if (entry.activityType == 'srsReview') {
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'learning/resume-srs',
        builder: (_) => SrsFlashcardsScreen(
          resumeSessionId: entry.sessionId,
          expectedOwnerId: expectedOwnerId,
          ownerChanges:
              ownerChanges ?? dependencies?.progress?.watchActiveOwnerId(),
          learning: learning,
          voice: dependencies?.voice,
          learningTime: dependencies?.learningTime,
          languageCode: languageCode,
        ),
      ),
    );
    return;
  }
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
