import 'package:drift/drift.dart';

import 'identity_tables.dart';
import 'learning_tables.dart';
import 'vocabulary_tables.dart';

/// Real microphone/STT pronunciation evidence. Stores the recognized transcript
/// and derived metadata (similarity score, STT engine, algorithm version) so a
/// speech result no longer collapses to a single boolean. Raw microphone audio
/// is never persisted.
///
/// Rows are linked to the [LearningSessions] and [VocabularyWords] that produced
/// them but are written in addition to (not instead of) an [AnswerAttempts]
/// boolean, which still feeds SRS.
class SpeechEvidence extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get sessionId =>
      text().references(LearningSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get wordId => text().references(VocabularyWords, #id)();
  TextColumn get promptMode => text()();
  TextColumn get targetContent => text()();
  TextColumn get recognizedTranscript => text()();
  TextColumn get locale => text()();
  TextColumn get sttEngine => text()();
  TextColumn get similarityAlgorithm => text()();
  IntColumn get similarityScore => integer().nullable()();
  BoolColumn get isExactMatch => boolean()();
  RealColumn get recognitionConfidence => real().nullable()();
  IntColumn get sampleSize => integer().withDefault(const Constant(1))();
  TextColumn get unavailableReason => text().nullable()();
  IntColumn get occurredAtUtcMs => integer()();
  IntColumn get durationMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
