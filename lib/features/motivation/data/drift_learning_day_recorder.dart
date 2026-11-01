import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../../../data/local/app_database.dart' as db;
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../learning/domain/evidence_eligibility_policy.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../learning_profile/domain/learning_timezone.dart';
import '../domain/motivation_snapshot.dart';

final class DriftLearningDayRecorder {
  DriftLearningDayRecorder(this.database, {required this.ownerWrites}) {
    if (!identical(database, ownerWrites.database)) {
      throw ArgumentError('Learning days require the canonical owner database');
    }
  }
  final db.AppDatabase database;
  final DriftOwnerWriteCoordinator ownerWrites;

  Future<void> recordAnswer(String attemptId) async {
    if (!await ownerWrites.hasAmbientTransaction()) {
      throw StateError(
        'Learning-day receipt requires the canonical answer transaction',
      );
    }
    final attempt = await (database.select(
      database.answerAttempts,
    )..where((row) => row.id.equals(attemptId))).getSingleOrNull();
    if (attempt == null) return;
    final active =
        await (database.select(database.localOwners)
              ..where((row) => row.isActive.equals(true))
              ..limit(2))
            .get();
    if (active.length != 1 || active.single.id != attempt.ownerId) return;
    final fence = await ownerWrites.inspect();
    if (fence != null &&
        (fence.casToken == null ||
            fence.casToken!.matchesOwner(attempt.ownerId))) {
      return;
    }
    if (!await _isOrdinaryStreakAttempt(database, attempt)) return;
    final profile = await (database.select(
      database.learningProfiles,
    )..where((row) => row.ownerId.equals(attempt.ownerId))).getSingleOrNull();
    final String zone;
    try {
      zone = requireLearningTimezone(profile?.learningTimezoneId ?? 'UTC');
    } on FormatException {
      return;
    }
    final at = DateTime.fromMillisecondsSinceEpoch(
      attempt.occurredAtUtcMs,
      isUtc: true,
    );
    final local = timezone.TZDateTime.from(at, timezone.getLocation(zone));
    final label = motivationDayLabel(local);
    final sourceReceipt =
        await (database.select(database.learningDayLog)..where(
              (row) =>
                  row.ownerId.equals(attempt.ownerId) &
                  row.sourceAttemptId.equals(attempt.id) &
                  row.policyVersion.equals(1),
            ))
            .get();
    if (sourceReceipt.isNotEmpty) return;
    final existing =
        await (database.select(database.learningDayLog)
              ..where(
                (row) =>
                    row.ownerId.equals(attempt.ownerId) &
                    row.learningDay.equals(label) &
                    row.policyVersion.equals(1),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return;
    if (await _hasOpenPinnedDay(attempt, at)) return;
    await database
        .into(database.learningDayLog)
        .insert(
          db.LearningDayLogCompanion.insert(
            id: 'day:v1:${attempt.ownerId}:$label',
            ownerId: attempt.ownerId,
            learningDay: label,
            firstSessionAtUtcMs: attempt.occurredAtUtcMs,
            sourceAttemptId: Value(attempt.id),
            timezoneId: Value(zone),
            policyVersion: const Value(1),
          ),
        );
  }

  Future<bool> _hasOpenPinnedDay(db.AnswerAttempt attempt, DateTime at) async {
    final rows =
        await (database.select(database.learningDayLog)..where(
              (row) =>
                  row.ownerId.equals(attempt.ownerId) &
                  row.policyVersion.equals(1) &
                  row.firstSessionAtUtcMs.isSmallerOrEqualValue(
                    attempt.occurredAtUtcMs,
                  ),
            ))
            .get();
    for (final row in rows) {
      if (row.timezoneId == null ||
          row.sourceAttemptId == null ||
          row.firstSessionAtUtcMs < 0 ||
          row.firstSessionAtUtcMs > 8640000000000000) {
        continue;
      }
      final String zone;
      try {
        zone = requireLearningTimezone(row.timezoneId!);
      } on FormatException {
        continue;
      }
      final location = timezone.getLocation(zone);
      final pinnedAt = DateTime.fromMillisecondsSinceEpoch(
        row.firstSessionAtUtcMs,
        isUtc: true,
      );
      final local = timezone.TZDateTime.from(pinnedAt, location);
      final end = timezone.TZDateTime(
        location,
        local.year,
        local.month,
        local.day + 1,
      ).toUtc();
      if (motivationDayLabel(local) != row.learningDay || !at.isBefore(end)) {
        continue;
      }
      final pins =
          await (database.select(database.learningDayLog)..where(
                (candidate) =>
                    candidate.ownerId.equals(attempt.ownerId) &
                    candidate.policyVersion.equals(1) &
                    candidate.sourceAttemptId.equals(row.sourceAttemptId!),
              ))
              .get();
      if (pins.length != 1) continue;
      final source =
          await (database.select(database.answerAttempts)..where(
                (source) =>
                    source.id.equals(row.sourceAttemptId!) &
                    source.ownerId.equals(attempt.ownerId),
              ))
              .getSingleOrNull();
      if (source != null &&
          source.occurredAtUtcMs == row.firstSessionAtUtcMs &&
          await _isOrdinaryStreakAttempt(database, source)) {
        return true;
      }
    }
    return false;
  }
}

Future<bool> _isOrdinaryStreakAttempt(
  db.AppDatabase database,
  db.AnswerAttempt attempt,
) async {
  final session = await (database.select(
    database.learningSessions,
  )..where((row) => row.id.equals(attempt.sessionId))).getSingleOrNull();
  final controlled = await database
      .customSelect(
        'SELECT learning_session_id FROM measurement_opportunities WHERE learning_session_id=? '
        'UNION SELECT learning_session_id FROM assessment_runs WHERE learning_session_id=? LIMIT 1',
        variables: [
          Variable<String>(attempt.sessionId),
          Variable<String>(attempt.sessionId),
        ],
      )
      .get();
  return _eligible(
    attempt,
    session,
    controlled.map((row) => row.read<String>('learning_session_id')).toSet(),
  );
}

Future<Map<String, db.AnswerAttempt>> loadOrdinaryStreakAttempts(
  db.AppDatabase database,
  String ownerId,
) async {
  final sessions = await (database.select(
    database.learningSessions,
  )..where((row) => row.ownerId.equals(ownerId))).get();
  final bySession = {for (final session in sessions) session.id: session};
  final controlled = await database
      .customSelect(
        'SELECT learning_session_id FROM measurement_opportunities WHERE owner_id=? AND learning_session_id IS NOT NULL '
        'UNION SELECT learning_session_id FROM assessment_runs WHERE owner_id=?',
        variables: [Variable<String>(ownerId), Variable<String>(ownerId)],
      )
      .get();
  final excluded = controlled
      .map((row) => row.read<String>('learning_session_id'))
      .toSet();
  final attempts = await (database.select(
    database.answerAttempts,
  )..where((row) => row.ownerId.equals(ownerId))).get();
  return {
    for (final attempt in attempts)
      if (_eligible(
        attempt,
        bySession[attempt.sessionId],
        excluded,
        allowSyncedEvidence: true,
      ))
        attempt.id: attempt,
  };
}

bool _eligible(
  db.AnswerAttempt attempt,
  db.LearningSession? session,
  Set<String> controlled, {
  bool allowSyncedEvidence = false,
}) =>
    session != null &&
    session.ownerId == attempt.ownerId &&
    session.activityType != 'assessment' &&
    !controlled.contains(session.id) &&
    session.activityType.trim().isNotEmpty &&
    session.appVersion.trim().isNotEmpty &&
    session.buildId.trim().isNotEmpty &&
    session.startedAtUtcMs >= 0 &&
    (({'active', 'completed', 'abandoned'}.contains(session.state) &&
            attempt.occurredAtUtcMs >= session.startedAtUtcMs &&
            (session.state == 'active'
                ? session.endedAtUtcMs == null
                : session.endedAtUtcMs != null &&
                      session.endedAtUtcMs! >= attempt.occurredAtUtcMs)) ||
        (allowSyncedEvidence &&
            session.activityType == 'syncedEvidence' &&
            session.state == 'syncedEvidence' &&
            session.appVersion == 'unknown' &&
            session.buildId == 'synced' &&
            session.endedAtUtcMs == null &&
            session.acceptedPlanId == null &&
            session.acceptedPlanJson == null &&
            session.checkpointRevision == 0 &&
            session.checkpointJson == null)) &&
    LearningEvidenceContract.validAttempt(
      id: attempt.id,
      ownerId: attempt.ownerId,
      sessionId: attempt.sessionId,
      wordId: attempt.wordId,
      promptMode: attempt.promptMode,
      responseTimeMs: attempt.responseTimeMs,
      attemptNumber: attempt.attemptNumber,
      occurredAtUtcMs: attempt.occurredAtUtcMs,
      providerProvenance: attempt.providerProvenance,
      evidenceClass: attempt.evidenceClass,
      evidenceContextJson: attempt.evidenceContextJson,
    ) &&
    LearningEvidenceContract.allowsOrdinaryProjection(
      promptMode: attempt.promptMode,
      evidenceClass: attempt.evidenceClass,
      evidenceContextJson: attempt.evidenceContextJson,
      projection: LearningProjection.streak,
    );

Future<List<LearningDayFact>> readCanonicalLearningDays(
  db.AppDatabase database, {
  required String ownerId,
  required DateTime nowUtc,
}) async {
  final attempts = await loadOrdinaryStreakAttempts(database, ownerId);
  final importedSessions =
      await (database.select(database.learningSessions)..where(
            (row) =>
                row.ownerId.equals(ownerId) &
                row.state.equals('syncedEvidence'),
          ))
          .get();
  final importedSessionIds = importedSessions.map((row) => row.id).toSet();
  final rows = await (database.select(
    database.learningDayLog,
  )..where((row) => row.ownerId.equals(ownerId))).get();
  final facts = <LearningDayFact>[];
  final covered = <String>{};
  final sourceCounts = <String, int>{};
  for (final row in rows) {
    if (row.policyVersion == 1 && row.sourceAttemptId != null) {
      sourceCounts.update(
        row.sourceAttemptId!,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }
  for (final row in rows) {
    final source = attempts[row.sourceAttemptId];
    if (row.policyVersion != 1 ||
        source == null ||
        importedSessionIds.contains(source.sessionId) ||
        sourceCounts[source.id] != 1 ||
        row.timezoneId == null ||
        row.firstSessionAtUtcMs != source.occurredAtUtcMs ||
        source.occurredAtUtcMs > nowUtc.millisecondsSinceEpoch) {
      continue;
    }
    try {
      final zone = requireLearningTimezone(row.timezoneId!);
      final at = DateTime.fromMillisecondsSinceEpoch(
        source.occurredAtUtcMs,
        isUtc: true,
      );
      final location = timezone.getLocation(zone);
      final local = timezone.TZDateTime.from(at, location);
      if (motivationDayLabel(local) != row.learningDay) continue;
      final end = timezone.TZDateTime(
        location,
        local.year,
        local.month,
        local.day + 1,
      ).toUtc();
      facts.add(
        LearningDayFact(
          learningDay: row.learningDay,
          timezoneId: zone,
          sourceAttemptId: source.id,
          occurredAtUtc: at,
          pinned: true,
        ),
      );
      covered.addAll(
        attempts.values
            .where(
              (candidate) =>
                  candidate.occurredAtUtcMs >= source.occurredAtUtcMs &&
                  candidate.occurredAtUtcMs < end.millisecondsSinceEpoch,
            )
            .map((candidate) => candidate.id),
      );
    } on FormatException {
      continue;
    }
  }
  for (final attempt in attempts.values) {
    if (covered.contains(attempt.id) ||
        attempt.occurredAtUtcMs > nowUtc.millisecondsSinceEpoch) {
      continue;
    }
    final at = DateTime.fromMillisecondsSinceEpoch(
      attempt.occurredAtUtcMs,
      isUtc: true,
    );
    facts.add(
      LearningDayFact(
        learningDay: motivationDayLabel(at),
        timezoneId: 'UTC',
        sourceAttemptId: attempt.id,
        occurredAtUtc: at,
        pinned: false,
      ),
    );
  }
  facts.sort((a, b) {
    final time = a.occurredAtUtc.compareTo(b.occurredAtUtc);
    return time == 0 ? a.sourceAttemptId.compareTo(b.sourceAttemptId) : time;
  });
  return List.unmodifiable(facts);
}
