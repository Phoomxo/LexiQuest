import 'dart:convert';
import 'package:drift/drift.dart';
import '../../ai_tutor/application/owner_operation_coordinator.dart';
import '../../ai_tutor/domain/ai_tutor_contracts.dart';
import '../../identity/application/owner_generation.dart';
import '../../vocabulary/data/packaged_starter_access.dart';
import '../../learning_packs/data/drift_personal_set_repository.dart';
import '../../learning_packs/data/drift_content_manifest_repository.dart';
import '../../learning_packs/domain/sense_crosswalk_repository.dart';
import '../data/drift_study_plan_repository.dart';
import '../domain/study_plan.dart';

final class StudyPlanUseCases {
  StudyPlanUseCases({
    required this.repository,
    required this.ownerOperations,
    required this.ownerGeneration,
    required this.nowUtc,
    required this.timezoneId,
    required this.isAvailable,
  });
  final DriftStudyPlanRepository repository;
  final OwnerOperationCoordinator ownerOperations;
  final OwnerGeneration ownerGeneration;
  final DateTime Function() nowUtc;
  final String timezoneId;
  final bool Function() isAvailable;
  Future<OwnerGenerationToken> begin() async {
    _available();
    return ownerGeneration.capture();
  }

  void _available() {
    if (!isAvailable()) throw StateError('Study planning is disabled');
  }

  Future<void> _current(OwnerGenerationToken owner) async {
    _available();
    await ownerGeneration.requireCurrentAsync(owner);
  }

  Stream<bool> watchOwnerCurrent(OwnerGenerationToken owner) {
    final db = repository.database;
    return db
        .customSelect(
          'SELECT id FROM local_owners WHERE is_active=1',
          readsFrom: {db.localOwners, db.runtimeFlags},
        )
        .watch()
        .asyncMap((rows) async {
          try {
            await _current(owner);
            return rows.length == 1 &&
                rows.single.read<String>('id') == owner.ownerId;
          } on Object {
            return false;
          }
        });
  }

  Future<T> _run<T>(
    OwnerGenerationToken owner,
    Future<T> Function(String lease) body,
  ) async {
    await _current(owner);
    return ownerOperations.run(AiCancellation(), (active) async {
      await _current(owner);
      if (active != owner.ownerId) throw StateError('Study plan owner changed');
      final result = await body(ownerOperations.currentOperationVersion);
      await _current(owner);
      return result;
    });
  }

  Future<StudyPlanRevision?> active(OwnerGenerationToken owner) =>
      _run(owner, (_) => repository.active(owner.ownerId));
  Future<Map<String, Object?>> exportArchive(OwnerGenerationToken owner) =>
      _run(
        owner,
        (lease) =>
            repository.exportArchive(ownerId: owner.ownerId, leaseToken: lease),
      );
  Future<void> restoreArchive(
    OwnerGenerationToken owner,
    Map<String, Object?> envelope, {
    bool Function()? mutationAllowed,
  }) {
    final frozen = Map<String, Object?>.from(
      jsonDecode(jsonEncode(envelope)) as Map,
    );
    return _run(
      owner,
      (lease) => repository.restoreArchive(
        ownerId: owner.ownerId,
        leaseToken: lease,
        envelope: frozen,
        requireCurrent: () async {
          await _current(owner);
          if (mutationAllowed != null && !mutationAllowed()) {
            throw StateError('Study plan destination retired');
          }
        },
      ),
    );
  }

  Future<Map<String, String>> labels(OwnerGenerationToken owner) =>
      _run(owner, (_) async {
        final db = repository.database;
        final rows =
            await (db.select(db.vocabularyWords)..where(
                  (r) =>
                      PackagedStarterAccess.wordsFor(db, owner.ownerId) &
                      r.isDeleted.equals(false),
                ))
                .get();
        return {for (final r in rows) r.id: r.spelling};
      });
  Future<List<({String id, String title})>> goals(OwnerGenerationToken owner) =>
      _run(owner, (_) async {
        final db = repository.database;
        final rows =
            await (db.select(db.learningGoals)..where(
                  (r) =>
                      r.ownerId.equals(owner.ownerId) &
                      r.isDeleted.equals(false) &
                      r.status.equals('active'),
                ))
                .get();
        return rows.map((r) => (id: r.id, title: r.title)).toList();
      });

  Future<StudyPlanRevision> propose(
    OwnerGenerationToken owner, {
    required String operationId,
    required int availableMinutes,
    String? goalId,
  }) => _run(
    owner,
    (_) => repository.database.transaction(() async {
      final prior = await repository.active(owner.ownerId);
      final source = await _source(owner.ownerId, goalId);
      return StudyPlanRevision.propose(
        operationId: operationId,
        expectedPriorRevision: prior?.revision ?? 0,
        createdAtUtc: nowUtc(),
        priorCreatedAtUtc: prior?.createdAtUtc,
        timezoneId: source.timezoneId,
        availableMinutes: availableMinutes,
        authorityHash: source.hash,
        goalId: goalId,
        deadlineAtUtc: source.deadline,
        dueItemIds: source.due,
        newItemIds: source.fresh,
      );
    }),
  );
  Future<StudyPlanRevision> accept(
    OwnerGenerationToken owner,
    StudyPlanRevision proposal, {
    bool Function()? mutationAllowed,
  }) => _run(
    owner,
    (lease) => repository.accept(
      ownerId: owner.ownerId,
      leaseToken: lease,
      proposal: proposal,
      requireCurrent: () async {
        await _current(owner);
        if (mutationAllowed != null && !mutationAllowed()) {
          throw StateError('Study plan destination retired');
        }
      },
      readAuthorityHash: () async {
        final source = await _source(owner.ownerId, proposal.goalId);
        final prior = await repository.active(owner.ownerId);
        // Caller cannot forge an allocation from a legitimate source hash.
        final expected = StudyPlanRevision.propose(
          operationId: proposal.operationId,
          expectedPriorRevision: proposal.expectedPriorRevision,
          createdAtUtc: proposal.createdAtUtc,
          priorCreatedAtUtc: prior?.createdAtUtc,
          timezoneId: source.timezoneId,
          availableMinutes: proposal.availableMinutes,
          authorityHash: source.hash,
          goalId: proposal.goalId,
          deadlineAtUtc: source.deadline,
          dueItemIds: source.due,
          newItemIds: source.fresh,
        );
        if (expected.payloadHash != proposal.payloadHash) {
          throw StateError('Study plan allocation changed');
        }
        return source.hash;
      },
    ),
  );

  Future<_PlanSource> _source(String ownerId, String? goalId) async {
    final db = repository.database;
    final goal = goalId == null
        ? null
        : await (db.select(db.learningGoals)..where(
                (r) =>
                    r.ownerId.equals(ownerId) &
                    r.id.equals(goalId) &
                    r.isDeleted.equals(false) &
                    r.status.equals('active'),
              ))
              .getSingleOrNull();
    if (goalId != null && goal == null) {
      throw StateError('Study plan goal is no longer active');
    }
    final srs =
        await (db.select(db.srsStates)
              ..where((r) => r.ownerId.equals(ownerId))
              ..orderBy([
                (r) => OrderingTerm.asc(r.dueAtUtcMs),
                (r) => OrderingTerm.asc(r.wordId),
              ]))
            .get();
    final due = srs
        .where((r) => r.dueAtUtcMs <= nowUtc().millisecondsSinceEpoch)
        .map((r) => r.wordId)
        .toList();
    final seen = srs.map((r) => r.wordId).toSet();
    final sets = await DriftPersonalSetRepository(
      db,
      SenseCrosswalkRepository(DriftContentManifestRepository(db)),
      nowUtc: nowUtc,
    ).listLatest(ownerId: ownerId);
    final fresh = <String>{};
    for (final set in sets) {
      for (final member in set.members) {
        final id = member.wordId;
        if (!seen.contains(id)) fresh.add(id);
      }
    }
    // Planning references are organizational; launching still uses F01's exact
    // content admission. A saved set never confers reviewed/scored status.
    return _PlanSource(
      hash: studyPlanHash({
        'goal': goal?.toJson(),
        'srs': srs.map((r) => r.toJson()).toList(),
        'due': due,
        'sets': sets.map((r) => r.payloadHash).toList(),
        'timezone': goal?.timezoneId ?? timezoneId,
      }),
      timezoneId: goal?.timezoneId ?? timezoneId,
      deadline: goal == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              goal.deadlineAtUtcMs,
              isUtc: true,
            ),
      due: due,
      fresh: fresh.toList(),
    );
  }
}

final class _PlanSource {
  _PlanSource({
    required this.hash,
    required this.timezoneId,
    required this.deadline,
    required this.due,
    required this.fresh,
  });
  final String hash, timezoneId;
  final DateTime? deadline;
  final List<String> due, fresh;
}
