import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import '../../../data/local/app_database.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../domain/personal_sets.dart';
import '../domain/personal_set_archive.dart';
import '../domain/sense_crosswalk_repository.dart';

final class DriftPersonalSetRepository {
  DriftPersonalSetRepository(
    this.database,
    this.crosswalks, {
    required this.nowUtc,
  });
  final AppDatabase database;
  final SenseCrosswalkRepository crosswalks;
  final DateTime Function() nowUtc;

  Future<PersonalSetArchive> exportArchive({
    required String ownerId,
    required String leaseToken,
  }) => database.transaction(() async {
    await _requireOwner(ownerId, leaseToken);
    final rows =
        await (database.select(database.personalSetRevisions)
              ..where((r) => r.ownerId.equals(ownerId))
              ..orderBy([
                (r) => OrderingTerm.asc(r.setId),
                (r) => OrderingTerm.asc(r.revision),
              ]))
            .get();
    final revisions = <PersonalSetRevision>[];
    for (final row in rows) {
      revisions.add(
        (await readExact(
          ownerId: ownerId,
          setId: row.setId,
          revision: row.revision,
        ))!,
      );
    }
    final archive = PersonalSetArchive.create(
      ownerId: ownerId,
      revisions: revisions,
    );
    await _requireOwner(ownerId, leaseToken);
    return archive;
  });

  /// Import history without granting current content/activity admission. Every
  /// member retains its original pin even when that artifact is unavailable.
  /// Existing immutable rows are reconciled, never replaced or downgraded.
  Future<void> restoreArchive({
    required String ownerId,
    required String leaseToken,
    required Map<String, Object?> envelope,
    Future<void> Function()? requireCurrentGeneration,
  }) async {
    final archive = PersonalSetArchive.fromJson(envelope);
    if (archive.ownerId != ownerId) {
      throw StateError('Personal set archive owner mismatch');
    }
    await database.transaction(() async {
      await _requireOwner(ownerId, leaseToken);
      await requireCurrentGeneration?.call();
      for (final revision in archive.revisions) {
        final byOperation =
            await (database.select(database.personalSetRevisions)..where(
                  (r) =>
                      r.ownerId.equals(ownerId) &
                      r.operationId.equals(revision.operationId),
                ))
                .getSingleOrNull();
        if (byOperation != null &&
            (byOperation.setId != revision.setId ||
                byOperation.revision != revision.revision ||
                byOperation.payloadHash != revision.payloadHash)) {
          throw StateError('Personal set restore operation collision');
        }
        final existing = await readExact(
          ownerId: ownerId,
          setId: revision.setId,
          revision: revision.revision,
        );
        if (existing != null) {
          if (existing.payloadHash != revision.payloadHash) {
            throw StateError('Personal set restore revision collision');
          }
          continue;
        }
        await _insertRevision(ownerId, revision);
      }
      await _requireOwner(ownerId, leaseToken);
      await requireCurrentGeneration?.call();
    });
  }

  /// Callers hold the canonical owner-operation lease through content loading
  /// and commit. Replay precedes content availability checks, never authority.
  Future<PersonalSetRevision> save({
    required String ownerId,
    required String leaseToken,
    required PersonalSetRevision revision,
    Future<void> Function()? requireCurrentGeneration,
  }) async {
    Future<PersonalSetRevision?> replay() async {
      final row =
          await (database.select(database.personalSetRevisions)..where(
                (r) =>
                    r.ownerId.equals(ownerId) &
                    r.operationId.equals(revision.operationId),
              ))
              .getSingleOrNull();
      if (row == null) return null;
      final stored = await readExact(
        ownerId: ownerId,
        setId: row.setId,
        revision: row.revision,
      );
      if (stored == null || stored.payloadHash != revision.payloadHash) {
        throw StateError('Personal set operation payload collision');
      }
      return stored;
    }

    final existing = await database.transaction(() async {
      await _requireOwner(ownerId, leaseToken);
      await requireCurrentGeneration?.call();
      return replay();
    });
    if (existing != null) return existing;
    // Archive is a historical operation and remains possible offline. It must
    // retain the previous exact pin, members and metadata, checked below.
    if (!revision.archived) {
      final crosswalk = await crosswalks.requirePinned(revision.crosswalkPin);
      for (final member in revision.members) {
        crosswalk.resolve(member);
      }
    }
    return database.transaction(() async {
      await _requireOwner(ownerId, leaseToken);
      await requireCurrentGeneration?.call();
      final existing = await replay();
      if (existing != null) return existing;
      final rows =
          await (database.select(database.personalSetRevisions)
                ..where(
                  (r) =>
                      r.ownerId.equals(ownerId) &
                      r.setId.equals(revision.setId),
                )
                ..orderBy([(r) => OrderingTerm.desc(r.revision)])
                ..limit(1))
              .get();
      final priorRevision = rows.isEmpty ? 0 : rows.single.revision;
      if (priorRevision != revision.expectedPriorRevision) {
        throw StateError('Personal set revision conflict');
      }
      if (revision.archived) {
        final prior = await readExact(
          ownerId: ownerId,
          setId: revision.setId,
          revision: priorRevision,
        );
        if (prior == null ||
            jsonEncode(prior.crosswalkPin.toJson()) !=
                jsonEncode(revision.crosswalkPin.toJson()) ||
            jsonEncode(prior.members.map((r) => r.toJson()).toList()) !=
                jsonEncode(revision.members.map((r) => r.toJson()).toList()) ||
            prior.title != revision.title ||
            jsonEncode(prior.filterSnapshot) !=
                jsonEncode(revision.filterSnapshot)) {
          throw StateError('Archive must retain the prior set contents');
        }
      }
      await _insertRevision(ownerId, revision);
      await _requireOwner(ownerId, leaseToken);
      await requireCurrentGeneration?.call();
      return revision;
    });
  }

  Future<void> _insertRevision(
    String ownerId,
    PersonalSetRevision revision,
  ) async {
    await database
        .into(database.personalSetRevisions)
        .insert(
          PersonalSetRevisionsCompanion.insert(
            ownerId: ownerId,
            setId: revision.setId,
            revision: revision.revision,
            operationId: revision.operationId,
            payloadHash: revision.payloadHash,
            payloadJson: jsonEncode(revision.toJson()),
            archived: revision.archived,
          ),
        );
    for (var i = 0; i < revision.members.length; i++) {
      final json = jsonEncode(revision.members[i].toJson());
      await database
          .into(database.personalSetMembers)
          .insert(
            PersonalSetMembersCompanion.insert(
              ownerId: ownerId,
              setId: revision.setId,
              revision: revision.revision,
              position: i,
              senseRefHash: sha256.convert(utf8.encode(json)).toString(),
              senseRefJson: json,
            ),
          );
    }
  }

  Future<void> _requireOwner(String ownerId, String leaseToken) async {
    await DriftOwnerOperationGate(
      database,
    ).requireOwned(token: leaseToken, nowUtc: nowUtc());
    final owner =
        await (database.select(database.localOwners)
              ..where((r) => r.id.equals(ownerId) & r.isActive.equals(true)))
            .getSingleOrNull();
    if (owner == null) {
      throw StateError('Personal set owner is no longer active');
    }
  }

  /// Historical reads do not require today's content to remain available.
  Future<PersonalSetRevision?> readExact({
    required String ownerId,
    required String setId,
    required int revision,
  }) => database.transaction(() async {
    final row =
        await (database.select(database.personalSetRevisions)..where(
              (r) =>
                  r.ownerId.equals(ownerId) &
                  r.setId.equals(setId) &
                  r.revision.equals(revision),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    final value = PersonalSetRevision.fromJson(
      Map<String, Object?>.from(jsonDecode(row.payloadJson) as Map),
    );
    if (value.setId != row.setId ||
        value.revision != row.revision ||
        value.operationId != row.operationId ||
        value.payloadHash != row.payloadHash ||
        value.archived != row.archived) {
      throw StateError('Personal set envelope integrity mismatch');
    }
    final members =
        await (database.select(database.personalSetMembers)
              ..where(
                (r) =>
                    r.ownerId.equals(ownerId) &
                    r.setId.equals(setId) &
                    r.revision.equals(revision),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.position)]))
            .get();
    if (members.length != value.members.length) {
      throw StateError('Personal set member count mismatch');
    }
    for (var i = 0; i < members.length; i++) {
      final json = jsonEncode(value.members[i].toJson());
      if (members[i].position != i ||
          members[i].senseRefJson != json ||
          members[i].senseRefHash !=
              sha256.convert(utf8.encode(json)).toString()) {
        throw StateError('Personal set member integrity mismatch');
      }
    }
    return value;
  });

  Future<List<PersonalSetRevision>> listLatest({
    required String ownerId,
    bool includeArchived = false,
  }) => database.transaction(() async {
    final rows = await database
        .customSelect(
          'SELECT set_id, MAX(revision) AS revision FROM personal_set_revisions WHERE owner_id = ? GROUP BY set_id ORDER BY set_id',
          variables: [Variable(ownerId)],
          readsFrom: {database.personalSetRevisions},
        )
        .get();
    final result = <PersonalSetRevision>[];
    for (final row in rows) {
      final value = (await readExact(
        ownerId: ownerId,
        setId: row.read<String>('set_id'),
        revision: row.read<int>('revision'),
      ))!;
      if (includeArchived || !value.archived) result.add(value);
    }
    return List.unmodifiable(result);
  });
}
