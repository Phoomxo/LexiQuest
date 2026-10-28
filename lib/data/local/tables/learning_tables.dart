import 'package:drift/drift.dart';

import 'identity_tables.dart';
import 'vocabulary_tables.dart';

class LearningSessions extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get activityType => text()();
  TextColumn get state => text()();
  IntColumn get startedAtUtcMs => integer()();
  IntColumn get endedAtUtcMs => integer().nullable()();
  IntColumn get correctCount => integer().withDefault(const Constant(0))();
  IntColumn get wrongCount => integer().withDefault(const Constant(0))();
  IntColumn get score => integer().nullable()();
  TextColumn get appVersion => text()();
  TextColumn get buildId => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AnswerAttempts extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get sessionId =>
      text().references(LearningSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get wordId => text().references(VocabularyWords, #id)();
  TextColumn get promptMode => text()();
  BoolColumn get isCorrect => boolean()();
  IntColumn get responseTimeMs => integer().nullable()();
  IntColumn get attemptNumber => integer()();
  IntColumn get occurredAtUtcMs => integer()();
  TextColumn get providerProvenance => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SrsStates extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get wordId => text().references(VocabularyWords, #id)();
  RealColumn get stability => real().withDefault(const Constant(0))();
  RealColumn get difficulty => real().withDefault(const Constant(0))();
  IntColumn get intervalDays => integer().withDefault(const Constant(0))();
  IntColumn get repetitions => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  IntColumn get lastReviewAtUtcMs => integer().nullable()();
  IntColumn get dueAtUtcMs => integer()();
  IntColumn get algorithmVersion => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, wordId},
  ];
}

class ReadingProgressEntries extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get documentId => text()();
  IntColumn get documentRevision => integer().withDefault(const Constant(1))();
  IntColumn get lastPosition => integer().withDefault(const Constant(0))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, documentId, documentRevision},
  ];
}

class ReadingEvents extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get documentId => text()();
  IntColumn get documentRevision => integer().withDefault(const Constant(1))();
  TextColumn get eventType => text()();
  IntColumn get position => integer().nullable()();
  IntColumn get occurredAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
