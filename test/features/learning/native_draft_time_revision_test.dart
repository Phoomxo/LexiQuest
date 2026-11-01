import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning_time/application/learning_time_use_cases.dart';

import '../../support/dictation_session_harness.dart';

void main() {
  test(
    'plain native draft ACK retires old LIVE admission while preserving CLOSED proof',
    () async {
      final h = await DictationSessionHarness.open();
      addTearDown(h.close);
      final exercise = await h.ready();
      final initial = await h.learning.readNativeExerciseState(
        exercise,
        stillCurrent: () => h.current,
      );
      final proof = await h.repository.admitCanonicalLearningTime(
        NativeLearningTimeAdmission(
          exercise,
          hintLevel: 0,
          callerContext: LearningTimeCallerContext.ordinary,
        ),
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => h.current,
      );
      final saved = await h.learning.saveNativeDraft(
        state: initial,
        draft: NativeExerciseDraft(
          text: 'synthetic acknowledged plain draft',
          responseTimeMs: 321,
        ),
        stillCurrent: () => h.current,
      );
      final before = await h.storage.snapshot();
      await expectLater(
        h.repository.requireLiveCanonicalLearningTimeAdmission(
          proof,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => h.current,
        ),
        throwsStateError,
      );
      await h.repository.requireCanonicalLearningTimeAdmission(
        proof,
        expectedOwnerId: configuredOwnerId,
        ownerStillCurrent: () => h.current,
      );
      final current = await h.repository.admitCanonicalLearningTime(
        NativeLearningTimeAdmission(
          exercise,
          hintLevel: 0,
          callerContext: LearningTimeCallerContext.ordinary,
        ),
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => h.current,
      );
      final context = jsonDecode(current.contextBindingJson) as Map;
      expect(context['schemaVersion'], 2);
      expect(context['checkpointRevision'], saved.checkpointRevision);
      expect(current.sourceBindingJson, proof.sourceBindingJson);
      expect(current.contextBindingJson, isNot(proof.contextBindingJson));
      expect(await h.storage.snapshot(), before);
      expect(await h.storage.count('learning_time_segments'), 0);
      expect((await h.storage.researchCounts()).values, everyElement(0));
    },
  );

  test(
    'native time parser keeps exact historical v1 and adds only exact native v2',
    () async {
      final h = await DictationSessionHarness.open();
      addTearDown(h.close);
      final exercise = await h.ready();
      final legacy = <String, Object?>{
        'schemaVersion': 1,
        'wordId': exercise.word.id,
        'promptMode': 'dictation',
        'evidenceContext': h.answer(exercise).evidenceContext.toJson(),
      };
      expect(
        parseTimeBindingJson(
          jsonEncode(legacy),
          sourceKind: TimeSourceKind.dictation,
          isContext: true,
        ),
        legacy,
      );
      final current = <String, Object?>{
        ...legacy,
        'schemaVersion': 2,
        'checkpointRevision': 2,
      };
      expect(
        parseTimeBindingJson(
          jsonEncode(current),
          sourceKind: TimeSourceKind.dictation,
          isContext: true,
        ),
        current,
      );
      for (final body in [
        {...current, 'unknown': 'synthetic unsupported field'},
        {...legacy, 'checkpointRevision': 2},
        {...current, 'checkpointRevision': -1},
        {...current, 'checkpointRevision': 1.5},
        {...current, 'schemaVersion': 3},
      ]) {
        expect(
          () => parseTimeBindingJson(
            jsonEncode(body),
            sourceKind: TimeSourceKind.dictation,
            isContext: true,
          ),
          throwsFormatException,
        );
      }
      for (final source in [
        TimeSourceKind.configuredQuiz,
        TimeSourceKind.ownedSrs,
        TimeSourceKind.voicePractice,
      ]) {
        expect(
          () => parseTimeBindingJson(
            jsonEncode(current),
            sourceKind: source,
            isContext: true,
          ),
          throwsFormatException,
        );
      }
    },
  );
}
