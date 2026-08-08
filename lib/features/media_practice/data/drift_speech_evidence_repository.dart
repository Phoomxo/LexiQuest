import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../domain/speech_evidence_use_cases.dart';

final class DriftSpeechEvidenceRepository implements SpeechEvidenceRepository {
  DriftSpeechEvidenceRepository(this.database);

  final db.AppDatabase database;

  @override
  Future<String> recordSpeechEvidence(
    RecordSpeechEvidenceCommand command,
  ) async {
    final occurredMs = command.occurredAtUtc.millisecondsSinceEpoch;
    await database
        .into(database.speechEvidence)
        .insert(
          db.SpeechEvidenceCompanion.insert(
            id: command.id,
            ownerId: command.ownerId,
            sessionId: command.sessionId,
            wordId: command.wordId,
            promptMode: command.promptMode,
            targetContent: command.targetContent,
            recognizedTranscript: command.recognizedTranscript,
            locale: command.locale,
            sttEngine: command.sttEngine,
            similarityAlgorithm: command.similarityAlgorithm,
            similarityScore: Value(command.similarityScore),
            isExactMatch: command.isExactMatch,
            recognitionConfidence: Value(command.recognitionConfidence),
            sampleSize: Value(command.sampleSize),
            unavailableReason: Value(command.unavailableReason),
            occurredAtUtcMs: occurredMs,
            durationMs: Value(command.durationMs),
          ),
        );
    return command.id;
  }
}
