import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/research/domain/experiment_assignment.dart'
    show experimentAssignmentId;

Future<String> seedOwnerAssignment(AppDatabase database, String ownerId) async {
  final id = experimentAssignmentId(
    ownerId: ownerId,
    experimentId: 'synthetic-study',
    experimentVersion: 1,
  );
  await database.customStatement(
    'INSERT INTO experiment_assignments '
    '(id, owner_id, experiment_id, experiment_version, cohort, protocol_version, assigned_at_utc_ms) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
    [id, ownerId, 'synthetic-study', 1, 'standard', 'synthetic-protocol-v1', 1],
  );
  return id;
}
