import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/data/bundled_starter_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';

import '../../screens/learning_pack_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'starter 1.0.1 preserves installed 1.0.0 and its resumable typed quiz',
    () async {
      final h = await LearningPackUiHarness.open();
      addTearDown(h.close);
      final original = const LearningPackCodec().decode(
        File('test/fixtures/bundled-starter-1.0.0.lexipack').readAsBytesSync(),
      );
      await h.seed(original);
      final oldPack = await h.stored();
      final owner = (await h.packs.captureOwner(stillCurrent: () => true))!;
      final oldDetail = await h.packs.detail(owner, oldPack.id);
      final oldClose = oldDetail.bindings.singleWhere(
        (binding) => binding.entry.code == 'close',
      );
      expect(oldClose.entry.examples.single.text, 'Close the window, please.');

      var quiz = await h.learning.startConfiguredQuiz(
        await h.learning.prepareLexicalQuiz(
          expectedOwnerId: owner.ownerId,
          packVersionId: oldPack.id,
          entryCodes: const ['close'],
          input: LexicalQuizInput.definitionTyped,
          limit: 1,
          stillCurrent: () => true,
        ),
      );
      quiz = await h.learning.saveQuizTypedDraft(
        sessionId: quiz.sessionId,
        expectedOwnerId: owner.ownerId,
        expectedRevision: quiz.checkpointRevision,
        text: 'clo',
      );
      final acceptedPlan = quiz.plan.stableSerialization;
      final checkpoint = quiz.checkpoint.stableSerialization;
      final checkpointRevision = quiz.checkpointRevision;
      final before = <String, List<Map<String, Object?>>>{};
      for (final table in const [
        'learning_pack_versions',
        'vocabulary_categories',
        'vocabulary_words',
        'lexical_content_snapshots',
        'learning_sessions',
      ]) {
        before[table] =
            (await h.database
                    .customSelect('SELECT * FROM $table ORDER BY id')
                    .get())
                .map((row) => row.data)
                .toList();
      }

      final newPack = await h.packs.importPack(
        h.packs.prepareImport(scope: owner, pack: bundledStarterPack),
      );
      expect(newPack.id, isNot(oldPack.id));
      expect(newPack.categoryId, isNot(oldPack.categoryId));
      expect(await h.count('learning_pack_versions'), 2);
      expect(await h.count('vocabulary_words'), 24);
      expect(await h.count('lexical_content_snapshots'), 24);
      for (final entry in before.entries) {
        final ids = entry.value.map((row) => row['id']).toSet();
        final after = await h.database
            .customSelect('SELECT * FROM ${entry.key} ORDER BY id')
            .get();
        expect(
          after
              .map((row) => row.data)
              .where((row) => ids.contains(row['id']))
              .toList(),
          entry.value,
          reason: 'Installing the new version must preserve ${entry.key}.',
        );
      }
      final newDetail = await h.packs.detail(owner, newPack.id);
      final newClose = newDetail.bindings.singleWhere(
        (binding) => binding.entry.code == 'close',
      );
      expect(newClose.wordId, isNot(oldClose.wordId));
      expect(newClose.entry.examples.single.text, 'Close the door, please.');
      expect(newClose.entry.examples.single.translation, 'กรุณาปิดประตู');
      expect(
        (await h.packs.detail(owner, oldPack.id)).content!.entries
            .singleWhere((entry) => entry.code == 'close')
            .examples
            .single
            .text,
        'Close the window, please.',
      );

      quiz = await h.learning.resumeQuiz(
        sessionId: quiz.sessionId,
        expectedOwnerId: owner.ownerId,
      );
      expect(quiz.restored, isTrue);
      expect(quiz.plan.stableSerialization, acceptedPlan);
      expect(quiz.checkpoint.stableSerialization, checkpoint);
      expect(quiz.checkpointRevision, checkpointRevision);
      expect((quiz.checkpoint.lexical! as LexicalTypedLocalData).draft, 'clo');
      expect(quiz.plan.questions.single.word.id, oldClose.wordId);
      quiz = await h.learning.prepareQuizAnswer(
        sessionId: quiz.sessionId,
        expectedOwnerId: owner.ownerId,
        expectedRevision: quiz.checkpointRevision,
        typedResponse: 'close',
      );
      final result = await h.learning.commitQuizAnswer(
        sessionId: quiz.sessionId,
        expectedOwnerId: owner.ownerId,
        expectedRevision: quiz.checkpointRevision,
      );
      expect(result.state.checkpoint.answer!.isCorrect, isTrue);
      expect(await h.count('answer_attempts'), 1);
      expect(
        (await h.canonicalAnswer()).read<String>('word_id'),
        oldClose.wordId,
      );
      expect(result.state.plan.stableSerialization, acceptedPlan);
      for (final table in h.database.allTables.where(
        (table) => table.actualTableName.startsWith('research_'),
      )) {
        expect(
          await h.count(table.actualTableName),
          0,
          reason: table.actualTableName,
        );
      }
    },
  );
}
