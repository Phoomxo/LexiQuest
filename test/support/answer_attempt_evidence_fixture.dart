import 'dart:convert';

import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';

EvidenceContext legacyAnswerEvidence() => EvidenceContext.legacyCompatibility(
  evidenceClass: EvidenceClass.independentRecall,
  skillId: 'legacy-unspecified',
  hintLevel: 0,
  contentRevision: 'legacy-unknown',
  engagementAllowed: true,
);

EvidenceContext ordinaryAnswerEvidence({String skillId = 'word-meaning'}) =>
    EvidenceContext.forNewEvidence(
      evidenceClass: EvidenceClass.recognition,
      skillId: skillId,
      hintLevel: 0,
      contentRevision: 'synthetic-content-v1',
      rolloutMode: EvidencePolicyRolloutMode.legacy,
      engagementAllowed: true,
    );

Map<String, Object?> answerPayload({EvidenceContext? evidence}) => {
  'sessionId': 'session-a',
  'wordId': 'word-a',
  'promptMode': 'meaningChoice',
  'isCorrect': true,
  'responseTimeMs': 320,
  'attemptNumber': 1,
  'occurredAtUtcMs': 2000,
  'providerProvenance': null,
  if (evidence != null) ...{
    'evidenceClass': evidence.evidenceClass.name,
    'evidenceContext': evidence.toJson(),
  },
};

Future<void> seedAnswerEvidenceOwners(AppDatabase database) async {
  await database.customStatement(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, is_active, created_at_utc_ms) VALUES '
    "('owner-a', 'uid-a', 'registered', 1, 1), "
    "('owner-b', 'uid-b', 'registered', 0, 2)",
  );
  for (final owner in ['a', 'b']) {
    await database.customStatement(
      'INSERT INTO vocabulary_categories '
      '(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
      'VALUES (?, ?, ?, ?, 1, 1)',
      ['category-$owner', 'owner-$owner', owner, owner],
    );
    await database.customStatement(
      'INSERT INTO vocabulary_words '
      '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
      'normalized_meaning, part_of_speech, source, created_at_utc_ms, updated_at_utc_ms) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
      [
        'word-$owner',
        'owner-$owner',
        'category-$owner',
        'word $owner',
        'word $owner',
        'meaning $owner',
        'meaning $owner',
        'noun',
        'manual',
      ],
    );
  }
}

Future<void> insertAnswerEvidence(
  AppDatabase database, {
  String owner = 'a',
  String id = 'attempt-a',
  required EvidenceContext evidence,
  bool queue = false,
}) async {
  await database.customStatement(
    'INSERT OR IGNORE INTO learning_sessions '
    '(id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id) '
    "VALUES (?, ?, 'quiz', 'active', 1000, 'synthetic', 'evidence-test')",
    ['session-$owner', 'owner-$owner'],
  );
  await database.customStatement(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, response_time_ms, '
    'attempt_number, occurred_at_utc_ms, evidence_class, evidence_context_json) '
    "VALUES (?, ?, ?, ?, 'meaningChoice', 1, 320, 1, 2000, ?, ?)",
    [
      id,
      'owner-$owner',
      'session-$owner',
      'word-$owner',
      evidence.evidenceClass.name,
      jsonEncode(evidence.toJson()),
    ],
  );
  if (queue) {
    await database.customStatement(
      'INSERT INTO outbox_operations '
      '(operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms) '
      "VALUES (?, ?, 'attempt', ?, 'upsert', 2000)",
      ['operation-$id', 'owner-$owner', id],
    );
  }
}
