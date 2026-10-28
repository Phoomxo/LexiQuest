import 'package:drift/drift.dart';
import '../../../../data/local/app_database.dart';
import '../domain/pair_matching_session_purpose.dart';

final class DriftPairMatchingSessionPurposeReader
    implements PairMatchingSessionPurposeReader {
  const DriftPairMatchingSessionPurposeReader(this.database);
  final AppDatabase database;
  @override
  Future<PairMatchingSessionPurpose> read({
    required String ownerId,
    required String sessionId,
  }) => database.transaction(() async {
    final session = await database
        .customSelect(
          'SELECT * FROM learning_sessions WHERE id = ?',
          variables: [Variable(sessionId)],
        )
        .getSingleOrNull();
    if (session == null) {
      throw StateError('Pair purpose session is unavailable');
    }
    final query = PairMatchingSessionPurpose.checkpointQuery(
      ownerId,
      sessionId,
    );
    final rows = session.data['activity_type'] == 'matching'
        ? await database
              .customSelect(
                query.sql,
                variables: [
                  for (final arg in query.args) Variable(arg as String),
                ],
              )
              .get()
        : <QueryRow>[];
    final checkpoints = [for (final row in rows) row.data];
    final actorsQuery = PairMatchingSessionPurpose.historicalOwnerQuery(
      ownerId,
      checkpoints,
    );
    final actors = await database
        .customSelect(
          actorsQuery.sql,
          variables: [
            for (final arg in actorsQuery.args) Variable(arg as String),
          ],
        )
        .get();
    return PairMatchingSessionPurpose.decode(
      ownerId: ownerId,
      session: session.data,
      checkpoints: checkpoints,
      historicalOwners: [for (final actor in actors) actor.data],
    );
  });
}
