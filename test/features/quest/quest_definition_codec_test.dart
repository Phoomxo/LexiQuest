import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_definition_codec.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';

void main() {
  test('encode and decode enforce the same positive duration ceiling', () {
    const maximumMilliseconds = 8640000000000000;
    final excessive = QuestDefinitionSnapshot(
      definition: definition(
        expiresIn: const Duration(milliseconds: maximumMilliseconds + 1),
      ),
      origin: QuestDefinitionSnapshotOrigin.capturedAssignment,
    );
    expect(() => QuestDefinitionCodec.encode(excessive), throwsFormatException);

    final largest = QuestDefinitionSnapshot(
      definition: definition(
        expiresIn: const Duration(milliseconds: maximumMilliseconds),
      ),
      origin: QuestDefinitionSnapshotOrigin.capturedAssignment,
    );
    final encoded = QuestDefinitionCodec.encode(largest);
    final decoded = QuestDefinitionCodec.decode(encoded);
    expect(decoded.definition.expiresIn!.inMilliseconds, maximumMilliseconds);
    final invalid = jsonDecode(encoded) as Map<String, dynamic>;
    (invalid['definition'] as Map<String, dynamic>)['expiresInMs'] =
        maximumMilliseconds + 1;
    expect(
      () => QuestDefinitionCodec.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
  });

  test(
    'snapshot round trip preserves the full pinned definition and origin',
    () {
      final original = definition();
      for (final origin in QuestDefinitionSnapshotOrigin.values) {
        final encoded = QuestDefinitionCodec.encode(
          QuestDefinitionSnapshot(definition: original, origin: origin),
        );
        final decoded = QuestDefinitionCodec.decode(encoded);
        expect(decoded.origin, origin);
        expect(decoded.definition.questId, original.questId);
        expect(decoded.definition.catalogVersion, 3);
        expect(decoded.definition.title, original.title);
        expect(decoded.definition.description, original.description);
        expect(decoded.definition.type, QuestType.weekly);
        expect(decoded.definition.reward.xpAmount, 75);
        expect(decoded.definition.reward.rewardItemId, 'synthetic-hat');
        expect(decoded.definition.expiresIn, const Duration(hours: 2));
        expect(decoded.definition.tags, ['synthetic', 'history']);
        final objective = decoded.definition.objectives.single;
        expect(objective.objectiveId, 'answer');
        expect(objective.description, 'Answer correctly');
        expect(objective.targetCount, 4);
        expect(objective.criteria.eventType, 'QuizCompleted');
        expect(objective.criteria.filters, {'correct': true, 'attempt': 1});
        expect(QuestDefinitionCodec.encode(decoded), encoded);
      }
    },
  );

  test(
    'strict codec rejects malformed unknown-version and unexpected fields',
    () {
      final encoded = QuestDefinitionCodec.encode(
        QuestDefinitionSnapshot(
          definition: definition(),
          origin: QuestDefinitionSnapshotOrigin.capturedAssignment,
        ),
      );
      final valid = jsonDecode(encoded) as Map<String, dynamic>;
      for (final invalid in <String>[
        '{',
        '[]',
        'null',
        jsonEncode({...valid, 'version': 999}),
        jsonEncode({...valid, 'unexpected': true}),
        jsonEncode({...valid, 'origin': 'fabricatedOriginal'}),
      ]) {
        expect(
          () => QuestDefinitionCodec.decode(invalid),
          throwsFormatException,
        );
      }
    },
  );

  test('size limit counts UTF-8 bytes and fails closed', () {
    expect(
      () => QuestDefinitionCodec.encode(
        QuestDefinitionSnapshot(
          definition: definition(title: 'ก' * 23000),
          origin: QuestDefinitionSnapshotOrigin.capturedAssignment,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => QuestDefinitionCodec.decode(' ' * 65537),
      throwsFormatException,
    );
  });

  test(
    'snapshot validates objectives instead of accepting duplicate authority',
    () {
      final source = definition();
      final invalid = QuestDefinition(
        questId: source.questId,
        catalogVersion: source.catalogVersion,
        title: source.title,
        description: source.description,
        type: source.type,
        objectives: [source.objectives.single, source.objectives.single],
        reward: source.reward,
      );
      expect(
        () => QuestDefinitionCodec.encode(
          QuestDefinitionSnapshot(
            definition: invalid,
            origin: QuestDefinitionSnapshotOrigin.capturedAssignment,
          ),
        ),
        throwsFormatException,
      );
    },
  );
}

QuestDefinition definition({
  String title = 'ชื่อเดิม',
  Duration expiresIn = const Duration(hours: 2),
}) => QuestDefinition(
  questId: 'synthetic-history',
  catalogVersion: 3,
  title: title,
  description: 'Original description',
  type: QuestType.weekly,
  objectives: const [
    QuestObjective(
      objectiveId: 'answer',
      description: 'Answer correctly',
      targetCount: 4,
      criteria: ObjectiveCriteria(
        eventType: 'QuizCompleted',
        filters: {'correct': true, 'attempt': 1},
      ),
    ),
  ],
  reward: const RewardSpec(xpAmount: 75, rewardItemId: 'synthetic-hat'),
  expiresIn: expiresIn,
  tags: const ['synthetic', 'history'],
);
