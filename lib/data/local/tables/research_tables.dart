import 'package:drift/drift.dart';

import 'identity_tables.dart';
import 'learning_tables.dart';

@DataClassName('ExperimentAssignmentRow')
class ExperimentAssignments extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get experimentId => text()();
  IntColumn get experimentVersion => integer()();
  TextColumn get cohort => text()();
  TextColumn get protocolVersion => text()();
  IntColumn get assignedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, experimentId, experimentVersion},
  ];
}

@DataClassName('AssessmentRunRow')
class AssessmentRuns extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get learningSessionId =>
      text().references(LearningSessions, #id)();
  TextColumn get studyCycleId => text()();
  TextColumn get phase => text()();
  TextColumn get state => text()();
  TextColumn get protocolId => text()();
  TextColumn get protocolVersion => text()();
  TextColumn get experimentId => text()();
  IntColumn get experimentVersion => integer()();
  TextColumn get assignmentId =>
      text().references(ExperimentAssignments, #id)();
  TextColumn get cohort => text()();
  IntColumn get consentVersion => integer()();
  IntColumn get consentDecidedAtUtcMs => integer()();
  TextColumn get instrumentId => text()();
  TextColumn get instrumentVersion => text()();
  TextColumn get formId => text()();
  TextColumn get formVersion => text()();
  TextColumn get instrumentChecksumSha256 => text()();
  TextColumn get formChecksumSha256 => text()();
  TextColumn get appVersion => text()();
  TextColumn get buildId => text()();
  IntColumn get databaseSchemaVersion => integer()();
  TextColumn get contentRevision => text()();
  TextColumn get evidencePolicyVersion => text()();
  TextColumn get featureContractRevision => text()();
  TextColumn get featureContractHash => text()();
  IntColumn get startedAtUtcMs => integer()();
  IntColumn get completedAtUtcMs => integer().nullable()();
  IntColumn get abandonedAtUtcMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {learningSessionId},
    {ownerId, studyCycleId, phase},
  ];
}
