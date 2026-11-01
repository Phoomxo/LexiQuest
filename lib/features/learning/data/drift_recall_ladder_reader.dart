import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../account_deletion/domain/account_deletion_contracts.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../domain/accepted_quiz_plan.dart';
import '../domain/evidence_context.dart';
import '../domain/learning_evidence_contract.dart';
import '../domain/learning_models.dart';
import '../domain/matching_exercise.dart';
import '../domain/recall_ladder.dart';

final class DriftRecallLadderReader implements RecallLadderReader {
  DriftRecallLadderReader({required this.database, required this.ownerWrites}) {
    if (!identical(database, ownerWrites.database)) {
      throw ArgumentError('Recall suggestions require the same owner database');
    }
  }
  final db.AppDatabase database;
  final DriftOwnerWriteCoordinator ownerWrites;

  @override
  Future<RecallLadderSnapshot> load({
    required String expectedOwnerId,
    String? wordId,
    required bool Function() stillCurrent,
  }) async {
    if (!LearningEvidenceContract.validIdentifier(expectedOwnerId) ||
        (wordId != null && !LearningEvidenceContract.validIdentifier(wordId))) {
      throw StateError('Recall suggestion source is unavailable');
    }
    var valid = true;
    final changes = Zone.root
        .run(
          () => database.tableUpdates(
            TableUpdateQuery.onTable(database.localOwners),
          ),
        )
        .listen(
          (_) => valid = false,
          onError: (Object _) => valid = false,
          onDone: () => valid = false,
        );
    bool current() => valid && stillCurrent();
    try {
      if (await ownerWrites.hasAmbientTransaction()) {
        throw StateError('Recall suggestion source is unavailable');
      }
      final snapshot = await database.transaction(() async {
        await _requireOwner(expectedOwnerId, current);
        final row = await database
            .customSelect(
              'SELECT w.* FROM vocabulary_words w JOIN vocabulary_categories c '
              'ON c.id = w.category_id AND c.owner_id = w.owner_id '
              'WHERE w.owner_id = ? AND w.is_deleted = 0 AND c.is_deleted = 0 '
              '${wordId == null ? '' : 'AND w.id = ? '}'
              'ORDER BY w.normalized_spelling,w.id LIMIT 1',
              variables: [
                Variable<String>(expectedOwnerId),
                if (wordId != null) Variable<String>(wordId),
              ],
            )
            .getSingleOrNull();
        if (row == null) {
          return RecallLadderSnapshot(
            ownerId: expectedOwnerId,
            word: null,
            observations: const [],
          );
        }
        final word = QuizWord(
          id: row.read<String>('id'),
          categoryId: row.read<String>('category_id'),
          spelling: row.read<String>('spelling'),
          meaning: row.read<String>('meaning'),
          partOfSpeech: row.read<String>('part_of_speech'),
          contentRevision:
              'local-vocabulary-v1:${row.read<int>('local_revision')}',
        );
        final attempts = await database
            .customSelect(
              'SELECT a.*,s.accepted_plan_id,s.accepted_plan_json,'
              's.activity_type AS session_activity FROM answer_attempts a '
              'JOIN learning_sessions s ON s.id = a.session_id AND s.owner_id = a.owner_id '
              "WHERE a.owner_id = ? AND a.word_id = ? AND s.state IN ('active','completed') "
              "AND s.activity_type <> 'assessment' "
              'AND NOT EXISTS (SELECT 1 FROM assessment_runs r WHERE r.learning_session_id = s.id) '
              'AND NOT EXISTS (SELECT 1 FROM measurement_opportunities m WHERE m.learning_session_id = s.id) '
              'ORDER BY a.occurred_at_utc_ms DESC,a.id DESC LIMIT 200',
              variables: [
                Variable<String>(expectedOwnerId),
                Variable<String>(word.id),
              ],
            )
            .get();
        final observations = <RecallLadderObservation>[];
        for (final attempt in attempts) {
          final observation = await _observation(
            attempt,
            word,
            expectedOwnerId,
          );
          if (observation != null) observations.add(observation);
        }
        await _requireOwner(expectedOwnerId, current);
        return RecallLadderSnapshot(
          ownerId: expectedOwnerId,
          word: word,
          observations: observations,
        );
      });
      await _requireOwner(expectedOwnerId, current);
      return snapshot;
    } finally {
      await changes.cancel();
    }
  }

  Future<void> _requireOwner(String ownerId, bool Function() current) async {
    if (!current()) throw StateError('Recall suggestion owner changed');
    final owners = await (database.select(
      database.localOwners,
    )..where((row) => row.isActive.equals(true))).get();
    if (owners.length != 1 || owners.single.id != ownerId) {
      throw StateError('Recall suggestion owner changed');
    }
    final fence = await ownerWrites.inspect();
    if (fence != null &&
        (fence.casToken == null ||
            fence.casToken!.matchesOwner(ownerId) ||
            (fence.cloudReceipt != null &&
                accountDeletionReplacementGuestOwnerId(fence.cloudReceipt!) ==
                    ownerId))) {
      throw StateError('Recall suggestion owner is fenced');
    }
    if (!current()) throw StateError('Recall suggestion scope changed');
  }

  Future<RecallLadderObservation?> _observation(
    QueryRow row,
    QuizWord word,
    String ownerId,
  ) async {
    try {
      if (!LearningEvidenceContract.validAttempt(
        id: row.read<String>('id'),
        ownerId: ownerId,
        sessionId: row.read<String>('session_id'),
        wordId: word.id,
        promptMode: row.read<String>('prompt_mode'),
        responseTimeMs: row.readNullable<int>('response_time_ms'),
        attemptNumber: row.read<int>('attempt_number'),
        occurredAtUtcMs: row.read<int>('occurred_at_utc_ms'),
        providerProvenance: row.readNullable<String>('provider_provenance'),
        evidenceClass: row.read<String>('evidence_class'),
        evidenceContextJson: row.read<String>('evidence_context_json'),
      )) {
        return null;
      }
      final context = EvidenceContext.fromJson(
        jsonDecode(row.read<String>('evidence_context_json'))
            as Map<String, dynamic>,
      );
      final observation = RecallLadderObservation.fromEvidence(
        attemptId: row.read<String>('id'),
        promptMode: row.read<String>('prompt_mode'),
        isCorrect: row.read<bool>('is_correct'),
        context: context,
        occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('occurred_at_utc_ms'),
          isUtc: true,
        ),
      );
      if (observation == null ||
          !await _currentSource(row, word, ownerId, context)) {
        return null;
      }
      return observation;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    } on NativeExerciseUnavailable {
      return null;
    }
  }

  Future<bool> _currentSource(
    QueryRow row,
    QuizWord word,
    String owner,
    EvidenceContext context,
  ) async {
    final prompt = row.read<String>('prompt_mode');
    if (const {
      'srsRecall',
      'associativeRecall',
      'shadowing',
      'pronunciationTranscript',
    }.contains(prompt)) {
      return context.contentRevision == word.contentRevision;
    }
    final id = row.readNullable<String>('accepted_plan_id');
    final json = row.readNullable<String>('accepted_plan_json');
    if (id == null || json == null) return false;
    if (id.startsWith('quiz-plan:')) {
      final plan = AcceptedQuizPlan.parse(id: id, json: json);
      if (!plan.supportsCurrentPolicy ||
          plan.activityType != row.read<String>('session_activity')) {
        return false;
      }
      final question = plan.questions
          .where((question) => question.word.id == word.id)
          .firstOrNull;
      if (question == null ||
          !_sameWord(question.word, word) ||
          question.promptMode != prompt ||
          question.evidenceContentRevision != context.contentRevision) {
        return false;
      }
      final lexical = question.lexical;
      if (lexical == null) return true;
      if (lexical.source.ownerId != owner) return false;
      final snapshot = await database
          .customSelect(
            'SELECT l.*,p.package_sha256,p.manifest_sha256,p.manifest_json,p.installed_at_utc_ms '
            'FROM lexical_content_snapshots l JOIN learning_pack_versions p '
            'ON p.id = l.pack_version_id AND p.owner_id = l.owner_id '
            'WHERE l.id = ? AND l.owner_id = ? AND l.word_id = ?',
            variables: [
              Variable<String>(lexical.target.snapshotId),
              Variable<String>(owner),
              Variable<String>(word.id),
            ],
          )
          .getSingleOrNull();
      return snapshot != null &&
          snapshot.readNullable<int>('installed_at_utc_ms') != null &&
          snapshot.read<String>('pack_version_id') ==
              lexical.source.packVersionId &&
          snapshot.read<int>('bound_word_revision') ==
              lexical.target.wordRevision &&
          snapshot.read<String>('lexical_json') ==
              lexical.target.entry.canonicalJson &&
          snapshot.read<String>('lexical_sha256') ==
              lexical.target.entry.contentSha256 &&
          snapshot.read<String>('package_sha256') ==
              lexical.source.packageSha256 &&
          snapshot.read<String>('manifest_sha256') ==
              lexical.source.manifestSha256 &&
          sha256
                  .convert(utf8.encode(snapshot.read<String>('manifest_json')))
                  .toString() ==
              lexical.source.manifestSha256;
    }
    if (id.startsWith(AcceptedNativePlan.idPrefix)) {
      final plan = AcceptedNativePlan.parse(id: id, json: json);
      final exercise = plan.exercise;
      final actualPrompt = switch (exercise) {
        DictationSession() => 'dictation',
        TypedClozeSession() => 'clozeTyped',
        ChoiceClozeSession() => 'clozeChoice',
        _ => null,
      };
      return exercise.ownerId == owner &&
          exercise.id == row.read<String>('session_id') &&
          exercise.session.activityType ==
              row.read<String>('session_activity') &&
          _sameWord(exercise.word, word) &&
          actualPrompt == prompt &&
          exercise.evidenceContentRevision == context.contentRevision;
    }
    if (id.startsWith(MatchingPlan.idPrefix)) {
      final plan = MatchingPlan.parse(id: id, json: json);
      return plan.session.ownerId == owner &&
          plan.session.id == row.read<String>('session_id') &&
          row.read<String>('session_activity') == MatchingPlan.activityType &&
          prompt == MatchingPlan.promptMode &&
          context.contentRevision == plan.id &&
          jsonEncode(context.toJson()) == jsonEncode(plan.evidence.toJson()) &&
          plan.words.any((candidate) => _sameWord(candidate, word));
    }
    return false;
  }
}

bool _sameWord(QuizWord a, QuizWord b) =>
    a.id == b.id &&
    a.categoryId == b.categoryId &&
    a.spelling == b.spelling &&
    a.meaning == b.meaning &&
    a.partOfSpeech == b.partOfSpeech &&
    a.contentRevision == b.contentRevision;
