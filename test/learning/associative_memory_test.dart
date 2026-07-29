import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/association_prompt.dart';
import 'package:vocab_learning_app/learning/association_record.dart';
import 'package:vocab_learning_app/learning/associative_memory.dart';
import 'package:vocab_learning_app/learning/secure_id_generator.dart';
import 'package:vocab_learning_app/learning/storage/drift_learning_repository.dart';
import 'package:vocab_learning_app/learning/storage/learning_database.dart';

void main() {
  group('curated association prompts', () {
    test('keeps curated prompts separate and limits each word to three', () {
      final catalog = CuratedAssociationPromptCatalog({
        'resilient': [_prompt('p1'), _prompt('p2'), _prompt('p3')],
      });

      expect(catalog.forWord('resilient'), hasLength(3));
      expect(
        CuratedAssociationPromptCatalog.offlineDefaults().forWord('ephemeral'),
        hasLength(2),
      );
      expect(
        () => CuratedAssociationPromptCatalog({
          'resilient': [
            _prompt('p1'),
            _prompt('p2'),
            _prompt('p3'),
            _prompt('p4'),
          ],
        }),
        throwsArgumentError,
      );
    });
  });

  group('cue reveal policy', () {
    final policy = AssociationCuePolicy(
      lowConfidenceThreshold: 2,
      slowResponseThreshold: Duration(seconds: 4),
    );

    test('never reveals a cue before unaided recall completes', () {
      expect(
        policy.shouldReveal(
          CueRevealEvidence(
            unaidedRecallCompleted: false,
            answerWasCorrect: false,
            confidence: 1,
            responseTime: Duration(seconds: 10),
          ),
          sessionPolicyAllowsCue: true,
        ),
        isFalse,
      );
    });

    test(
      'reveals only for failure, low confidence, slow recall, or policy',
      () {
        final fluent = CueRevealEvidence(
          unaidedRecallCompleted: true,
          answerWasCorrect: true,
          confidence: 5,
          responseTime: Duration(seconds: 1),
        );

        expect(policy.shouldReveal(fluent), isFalse);
        expect(
          policy.shouldReveal(
            CueRevealEvidence(
              unaidedRecallCompleted: true,
              answerWasCorrect: false,
              confidence: 5,
              responseTime: Duration(seconds: 1),
            ),
          ),
          isTrue,
        );
        expect(
          policy.shouldReveal(
            CueRevealEvidence(
              unaidedRecallCompleted: true,
              answerWasCorrect: true,
              confidence: 2,
              responseTime: Duration(seconds: 1),
            ),
          ),
          isTrue,
        );
        expect(
          policy.shouldReveal(
            CueRevealEvidence(
              unaidedRecallCompleted: true,
              answerWasCorrect: true,
              confidence: 5,
              responseTime: Duration(seconds: 5),
            ),
          ),
          isTrue,
        );
        expect(
          policy.shouldReveal(fluent, sessionPolicyAllowsCue: true),
          isTrue,
        );
      },
    );
  });

  group('offline private association lifecycle', () {
    late LearningDatabase database;
    late DriftLearningRepository repository;
    late AssociativeMemory memory;

    setUp(() {
      database = LearningDatabase(NativeDatabase.memory());
      repository = DriftLearningRepository(database);
      memory = AssociativeMemory(
        repository: repository,
        reader: repository,
        promptCatalog: CuratedAssociationPromptCatalog({
          'resilient': [_prompt('curated-1')],
        }),
        idGenerator: _SequenceIdGenerator([
          'association-1',
          'commit-create',
          'commit-edit',
          'tombstone-1',
          'commit-delete',
        ]),
        clock: () => DateTime.utc(2026, 7, 29, 14),
      );
    });

    tearDown(() => database.close());

    test('creates, edits, selects, skips, and deletes without sync', () async {
      final created = await memory.create(
        ownerId: 'owner-a',
        wordKey: 'resilient',
        cueType: AssociationCueType.personalStory,
        cueText: 'I recovered after a difficult exam.',
      );
      final edited = await memory.edit(
        ownerId: 'owner-a',
        wordKey: 'resilient',
        associationId: created.associationId,
        cueType: AssociationCueType.sensory,
        cueText: 'A bamboo stem bends and rises again.',
      );
      final cues = await memory.cuesForRecall(
        ownerId: 'owner-a',
        wordKey: 'resilient',
        evidence: CueRevealEvidence(
          unaidedRecallCompleted: true,
          answerWasCorrect: false,
          confidence: 3,
          responseTime: Duration(seconds: 2),
        ),
      );
      final selected = memory.select(
        cueId: cues.privateAssociations.single.associationId,
        source: AssociationCueSource.privateAssociation,
      );
      final skipped = memory.skip();

      expect(edited.createdAtUtc, created.createdAtUtc);
      expect(cues.curatedPrompts, hasLength(1));
      expect(cues.privateAssociations.single.cueText, contains('bamboo'));
      expect(selected.countsAsCorrectAnswer, isFalse);
      expect(skipped.outcome, AssociationCueOutcome.skipped);
      expect(await repository.readPendingOutbox(ownerId: 'owner-a'), isEmpty);

      await memory.delete(
        ownerId: 'owner-a',
        wordKey: 'resilient',
        associationId: created.associationId,
      );

      expect(
        await repository.readAssociations(
          ownerId: 'owner-a',
          wordKey: 'resilient',
        ),
        isEmpty,
      );
      final tombstones = await database
          .select(database.deletionTombstones)
          .get();
      expect(tombstones, hasLength(1));
      expect(tombstones.single.entityId, created.associationId);
      expect(tombstones.single.toJson().toString(), isNot(contains('bamboo')));
      expect(await repository.readPendingOutbox(ownerId: 'owner-a'), isEmpty);
    });

    test('returns no cue before unaided recall evidence', () async {
      await memory.create(
        ownerId: 'owner-a',
        wordKey: 'resilient',
        cueType: AssociationCueType.keyword,
        cueText: 'bounce back',
      );

      final cues = await memory.cuesForRecall(
        ownerId: 'owner-a',
        wordKey: 'resilient',
        evidence: CueRevealEvidence(
          unaidedRecallCompleted: false,
          answerWasCorrect: false,
          confidence: 1,
          responseTime: Duration(seconds: 10),
        ),
        sessionPolicyAllowsCue: true,
      );

      expect(cues.isVisible, isFalse);
      expect(cues.curatedPrompts, isEmpty);
      expect(cues.privateAssociations, isEmpty);
    });
  });
}

AssociationPrompt _prompt(String id) {
  return AssociationPrompt(
    promptId: id,
    wordKey: 'resilient',
    cueType: AssociationCueType.sensory,
    cueText: 'Bamboo bends without breaking.',
    contentVersion: 'curated-v1',
  );
}

final class _SequenceIdGenerator implements SecureIdGenerator {
  _SequenceIdGenerator(this._ids);

  final List<String> _ids;
  var _index = 0;

  @override
  String nextId() => _ids[_index++];
}
