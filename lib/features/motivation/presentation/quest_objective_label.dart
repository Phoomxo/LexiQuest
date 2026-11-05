import '../../quest/domain/quest_models.dart';

String? questObjectiveLabel(QuestDefinition? definition, String objectiveId) {
  final description = definition?.objectives
      .where((row) => row.objectiveId == objectiveId)
      .firstOrNull
      ?.description;
  return switch ((
    definition?.questId,
    definition?.catalogVersion,
    objectiveId,
    description,
  )) {
    ('daily-correct-5-v1', 1, 'obj-daily-correct', 'Correct answers') =>
      'ตอบถูกวันนี้',
    (
      'weekly-correct-20-v1',
      1,
      'obj-weekly-correct',
      'Correct answers this week',
    ) =>
      'ตอบถูกสัปดาห์นี้',
    _ => description,
  };
}
