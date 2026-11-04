import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

void main() {
  // Captured by executing the archived d03d8eaf source, not the new serializers.
  final bytes = File(
    'test/fixtures/legacy-plan-d03d8eaf.json',
  ).readAsBytesSync();
  final fixture = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

  test('legacy fixtures retain the independently captured baseline bytes', () {
    expect(
      sha256.convert(bytes).toString(),
      'a14b213b2e4ed8ba9d7d203f16154f730d2a9240744ce8b1873f0b16b2643622',
    );
    expect(fixture['sourceCommit'], 'd03d8eaf63b53a73f03cb4405e5874205a17c953');
  });

  for (final entry in (fixture['quizzes'] as Map<String, dynamic>).entries) {
    test(
      'old ${entry.key} accepted plan and checkpoint remain byte-identical',
      () {
        final value = entry.value as Map<String, dynamic>;
        final plan = AcceptedQuizPlan.parse(
          id: value['id'] as String,
          json: value['json'] as String,
        );
        expect(plan.stableSerialization, value['json']);
        final rebuilt = AcceptedQuizPlan.create(
          configuration: plan.configuration,
          questions: plan.questions,
        );
        expect(rebuilt.id, value['id']);
        expect(rebuilt.stableSerialization, value['json']);
        expect(
          QuizCheckpoint.parse(
            value['checkpoint'] as String,
            plan: plan,
          ).stableSerialization,
          value['checkpoint'],
        );
        expect(
          QuizCheckpoint.initial(rebuilt).stableSerialization,
          value['checkpoint'],
        );
      },
    );
  }

  for (final entry in (fixture['native'] as Map<String, dynamic>).entries) {
    test(
      'old ${entry.key} native plan and evidence keep their exact identities',
      () {
        final value = entry.value as Map<String, dynamic>;
        final plan = AcceptedNativePlan.parse(
          id: value['id'] as String,
          json: value['json'] as String,
        );
        expect(plan.id, value['id']);
        expect(plan.stableSerialization, value['json']);
        expect(
          plan.exercise.evidenceContentRevision,
          value['evidenceContentRevision'],
        );
        final provenance = switch (plan.exercise) {
          ClozeSession(:final providerProvenance) => providerProvenance,
          SentenceScrambleSession(:final providerProvenance) =>
            providerProvenance,
          _ => throw StateError('Unexpected legacy fixture'),
        };
        expect(provenance, value['providerProvenance']);
      },
    );
  }
}
