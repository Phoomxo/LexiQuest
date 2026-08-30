import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../domain/export_contracts.dart';

final class ExportVocabularyRow {
  const ExportVocabularyRow({
    required this.id,
    required this.category,
    required this.spelling,
    required this.meaning,
    required this.partOfSpeech,
    required this.cefrLevel,
    required this.source,
    required this.contentRevision,
    required this.contentChecksumSha256,
    required this.contentProvenance,
    required this.contentReviewState,
    required this.contentPublicationState,
  });

  final String id;
  final String category;
  final String spelling;
  final String meaning;
  final String partOfSpeech;
  final String? cefrLevel;
  final String source;
  final int contentRevision;
  final String? contentChecksumSha256;
  final String contentProvenance;
  final String contentReviewState;
  final String contentPublicationState;
}

final class ExportAttemptRow {
  const ExportAttemptRow({
    required this.id,
    required this.sessionId,
    required this.wordId,
    required this.spelling,
    required this.promptMode,
    required this.isCorrect,
    required this.responseTimeMs,
    required this.occurredAtUtc,
    required this.evidenceContext,
    this.providerProvenance,
  });

  final String id;
  final String sessionId;
  final String wordId;
  final String spelling;
  final String promptMode;
  final bool isCorrect;
  final int? responseTimeMs;
  final DateTime occurredAtUtc;
  final EvidenceContext evidenceContext;

  /// Retained only for source compatibility. Raw provenance is never loaded
  /// by the production reader or emitted by an export artifact.
  @Deprecated('Raw provider provenance is excluded from exports.')
  final String? providerProvenance;
}

final class ExportReadingRow {
  const ExportReadingRow({
    required this.documentId,
    required this.documentRevision,
    required this.lastPosition,
    required this.isCompleted,
    required this.updatedAtUtc,
  });

  final String documentId;
  final int documentRevision;
  final int lastPosition;
  final bool isCompleted;
  final DateTime updatedAtUtc;
}

final class ExportSavedLearningItemRow {
  const ExportSavedLearningItemRow({
    required this.contentType,
    required this.contentId,
    required this.contentRevision,
    required this.savedAtUtc,
    required this.updatedAtUtc,
    required this.isSaved,
  });

  final String contentType;
  final String contentId;
  final int contentRevision;
  final DateTime savedAtUtc;
  final DateTime updatedAtUtc;
  final bool isSaved;
}

final class ExportLearningTimeSegmentRow {
  const ExportLearningTimeSegmentRow({
    required this.sessionId,
    required this.activeStartOffsetMs,
    required this.activeDurationMs,
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.timezoneId,
    required this.timezoneOffsetMinutes,
    required this.captureSource,
  });

  final String sessionId;
  final int activeStartOffsetMs;
  final int activeDurationMs;
  final DateTime startedAtUtc;
  final DateTime endedAtUtc;
  final String timezoneId;
  final int timezoneOffsetMinutes;
  final String captureSource;
}

final class ExportLearningGoalRow {
  const ExportLearningGoalRow({
    required this.kind,
    required this.title,
    required this.deadlineAtUtc,
    required this.timezoneId,
    required this.timezoneOffsetMinutes,
    required this.status,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  final String kind;
  final String title;
  final DateTime deadlineAtUtc;
  final String timezoneId;
  final int timezoneOffsetMinutes;
  final String status;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
}

final class ExportLearnerPreferenceRow {
  const ExportLearnerPreferenceRow({
    required this.preferenceVersion,
    required this.goal,
    required this.availableMinutesPerDay,
    required this.activityPreference,
    required this.updatedAtUtc,
    required this.themeMode,
    required this.motionMode,
    required this.displayUpdatedAtUtc,
  });

  final int preferenceVersion;
  final String goal;
  final int availableMinutesPerDay;
  final String activityPreference;
  final DateTime updatedAtUtc;
  final String themeMode;
  final String motionMode;
  final DateTime displayUpdatedAtUtc;
}

final class ExportDataSet {
  const ExportDataSet({
    required this.vocabulary,
    required this.attempts,
    required this.reading,
  });

  final List<ExportVocabularyRow> vocabulary;
  final List<ExportAttemptRow> attempts;
  final List<ExportReadingRow> reading;

  int get recordCount => vocabulary.length + attempts.length + reading.length;
}

final class DriftExportReader {
  const DriftExportReader(this.database);

  final AppDatabase database;

  Future<List<ExportSavedLearningItemRow>> loadSavedLearningItems(
    String ownerId,
  ) async {
    final rows =
        await (database.select(database.savedLearningItems)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.savedAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    return List<ExportSavedLearningItemRow>.unmodifiable(
      rows.map(
        (row) => ExportSavedLearningItemRow(
          contentType: row.contentType,
          contentId: row.contentId,
          contentRevision: row.contentRevision,
          savedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            row.savedAtUtcMs,
            isUtc: true,
          ),
          updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            row.updatedAtUtcMs,
            isUtc: true,
          ),
          isSaved: !row.isDeleted,
        ),
      ),
    );
  }

  Future<List<ExportLearningTimeSegmentRow>> loadLearningTimeSegments(
    String ownerId,
  ) async {
    final rows =
        await (database.select(database.learningTimeSegments)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.startedAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    return List<ExportLearningTimeSegmentRow>.unmodifiable(
      rows.map(
        (row) => ExportLearningTimeSegmentRow(
          sessionId: row.sessionId,
          activeStartOffsetMs: row.activeStartOffsetMs,
          activeDurationMs: row.activeDurationMs,
          startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            row.startedAtUtcMs,
            isUtc: true,
          ),
          endedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            row.endedAtUtcMs,
            isUtc: true,
          ),
          timezoneId: row.timezoneId,
          timezoneOffsetMinutes: row.timezoneOffsetMinutes,
          captureSource: row.captureSource,
        ),
      ),
    );
  }

  Future<List<ExportLearningGoalRow>> loadLearningGoals(String ownerId) async {
    final rows =
        await (database.select(database.learningGoals)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.deadlineAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    return List<ExportLearningGoalRow>.unmodifiable(
      rows.map(
        (row) => ExportLearningGoalRow(
          kind: row.kind,
          title: row.title,
          deadlineAtUtc: DateTime.fromMillisecondsSinceEpoch(
            row.deadlineAtUtcMs,
            isUtc: true,
          ),
          timezoneId: row.timezoneId,
          timezoneOffsetMinutes: row.timezoneOffsetMinutes,
          status: row.status,
          createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
            row.createdAtUtcMs,
            isUtc: true,
          ),
          updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            row.updatedAtUtcMs,
            isUtc: true,
          ),
        ),
      ),
    );
  }

  Future<List<ExportLearnerPreferenceRow>> loadLearnerPreferences(
    String ownerId,
  ) async {
    final rows =
        await (database.select(database.learnerPreferences)..where(
              (row) =>
                  row.ownerId.equals(ownerId) & row.isDeleted.equals(false),
            ))
            .get();
    return List<ExportLearnerPreferenceRow>.unmodifiable(
      rows.map(
        (row) => ExportLearnerPreferenceRow(
          preferenceVersion: row.preferenceVersion,
          goal: row.goal,
          availableMinutesPerDay: row.availableMinutesPerDay,
          activityPreference: row.activityPreference,
          updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            row.updatedAtUtcMs,
            isUtc: true,
          ),
          themeMode: row.themeMode,
          motionMode: row.motionMode,
          displayUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            row.displayUpdatedAtUtcMs,
            isUtc: true,
          ),
        ),
      ),
    );
  }

  Future<ExportDataSet> loadActiveSnapshot({
    required bool vocabulary,
    required bool attempts,
    required bool reading,
    int? researchConsentVersion,
  }) {
    final consentVersion = researchConsentVersion;
    if (consentVersion != null && consentVersion < 1) {
      throw ArgumentError.value(
        consentVersion,
        'researchConsentVersion',
        'must be at least one',
      );
    }
    return database.transaction(() async {
      final activeOwners = await (database.select(
        database.localOwners,
      )..where((row) => row.isActive.equals(true))).get();
      if (activeOwners.length != 1) {
        throw const ExportException(ExportFailureCode.unavailable);
      }
      final ownerId = activeOwners.single.id;
      if (consentVersion != null) {
        final consent =
            await (database.select(database.researchConsents)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.consentVersion.equals(consentVersion),
                ))
                .getSingleOrNull();
        if (consent?.consentState != 'accepted' ||
            consent?.withdrawnAtUtcMs != null) {
          throw const ExportException(ExportFailureCode.consentRequired);
        }
      }
      return load(
        ownerId: ownerId,
        vocabulary: vocabulary,
        attempts: attempts,
        reading: reading,
      );
    });
  }

  Future<ExportDataSet> load({
    required String ownerId,
    required bool vocabulary,
    required bool attempts,
    required bool reading,
  }) async {
    final vocabularyRows = vocabulary
        ? await database
              .customSelect(
                '''
                SELECT w.id, c.name AS category, w.spelling, w.meaning,
                       w.part_of_speech, w.cefr_level, w.source,
                       w.content_revision, w.content_checksum_sha256,
                       w.content_provenance, w.content_review_state,
                       w.content_publication_state
                FROM vocabulary_words w
                INNER JOIN vocabulary_categories c
                  ON c.id = w.category_id AND c.owner_id = w.owner_id
                WHERE w.owner_id = ? AND w.is_deleted = 0 AND c.is_deleted = 0
                ORDER BY c.sort_order, c.name, w.spelling, w.id
                ''',
                variables: [Variable<String>(ownerId)],
                readsFrom: {
                  database.vocabularyWords,
                  database.vocabularyCategories,
                },
              )
              .get()
        : const <QueryRow>[];
    final attemptRows = attempts
        ? await database
              .customSelect(
                '''
                SELECT a.id, a.session_id, a.word_id, w.spelling,
                       a.prompt_mode, a.is_correct, a.response_time_ms,
                       a.occurred_at_utc_ms, a.evidence_class,
                       a.evidence_context_json
                FROM answer_attempts a
                INNER JOIN vocabulary_words w
                  ON w.id = a.word_id AND w.owner_id = a.owner_id
                WHERE a.owner_id = ?
                ORDER BY a.occurred_at_utc_ms, a.id
                ''',
                variables: [Variable<String>(ownerId)],
                readsFrom: {database.answerAttempts, database.vocabularyWords},
              )
              .get()
        : const <QueryRow>[];
    final readingRows = reading
        ? await (database.select(database.readingProgressEntries)
                ..where((row) => row.ownerId.equals(ownerId))
                ..orderBy([
                  (row) => OrderingTerm.asc(row.updatedAtUtcMs),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get()
        : const <ReadingProgressEntry>[];
    return ExportDataSet(
      vocabulary: vocabularyRows
          .map(
            (row) => ExportVocabularyRow(
              id: row.read<String>('id'),
              category: row.read<String>('category'),
              spelling: row.read<String>('spelling'),
              meaning: row.read<String>('meaning'),
              partOfSpeech: row.read<String>('part_of_speech'),
              cefrLevel: row.readNullable<String>('cefr_level'),
              source: row.read<String>('source'),
              contentRevision: row.read<int>('content_revision'),
              contentChecksumSha256: row.readNullable<String>(
                'content_checksum_sha256',
              ),
              contentProvenance: row.read<String>('content_provenance'),
              contentReviewState: row.read<String>('content_review_state'),
              contentPublicationState: row.read<String>(
                'content_publication_state',
              ),
            ),
          )
          .toList(growable: false),
      attempts: attemptRows
          .map(
            (row) => ExportAttemptRow(
              id: row.read<String>('id'),
              sessionId: row.read<String>('session_id'),
              wordId: row.read<String>('word_id'),
              spelling: row.read<String>('spelling'),
              promptMode: row.read<String>('prompt_mode'),
              isCorrect: row.read<bool>('is_correct'),
              responseTimeMs: row.readNullable<int>('response_time_ms'),
              occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
                row.read<int>('occurred_at_utc_ms'),
                isUtc: true,
              ),
              evidenceContext: _readEvidenceContext(row),
            ),
          )
          .toList(growable: false),
      reading: readingRows
          .map(
            (row) => ExportReadingRow(
              documentId: row.documentId,
              documentRevision: row.documentRevision,
              lastPosition: row.lastPosition,
              isCompleted: row.isCompleted,
              updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                row.updatedAtUtcMs,
                isUtc: true,
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  EvidenceContext _readEvidenceContext(QueryRow row) {
    final evidenceClass = row.read<String>('evidence_class');
    final evidenceContextJson = row.read<String>('evidence_context_json');
    if (!LearningEvidenceContract.validEvidenceMetadata(
      evidenceClass: evidenceClass,
      evidenceContextJson: evidenceContextJson,
    )) {
      throw const ExportException(ExportFailureCode.unavailable);
    }
    return EvidenceContext.fromJson(
      (jsonDecode(evidenceContextJson) as Map).cast<String, Object?>(),
    );
  }
}
