import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import '../../../data/local/app_database.dart';
import '../../ai_tutor/domain/ai_tutor_contracts.dart';
import '../../identity/application/owner_generation.dart';
import '../../learning_packs/application/personal_sets_use_cases.dart';
import '../../learning_packs/domain/personal_sets.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../../vocabulary/data/drift_vocabulary_repository.dart';
import '../../vocabulary/data/packaged_starter_access.dart';
import '../domain/context_practice.dart';
import '../domain/written_rubric.dart';

final class WrittenPracticeRollout {
  const WrittenPracticeRollout.implementedOff() : enabled = false;
  const WrittenPracticeRollout.internal() : enabled = true;
  final bool enabled;
}

final class WrittenPracticeTicket {
  WrittenPracticeTicket._(
    this.owner,
    this.set,
    this.memberIndex,
    this.activityId,
    List<WrittenRubricResult> results,
  ) : results = List.unmodifiable(results);
  final OwnerGenerationToken owner;
  final PersonalSetRevision set;
  final int memberIndex;
  final String activityId;
  final List<WrittenRubricResult> results;
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  String get target =>
      set.members[memberIndex].wordId.substring('word:starter-'.length);
  String get prompt => WrittenRubric.prompts[target]!;
  Map<String, Object?> get pin => {
    'schemaVersion': 1,
    'set': set.toJson(),
    'memberIndex': memberIndex,
    'rubricRevision': WrittenRubric.revision,
    'inventoryHash': WrittenRubric.fingerprint,
    'prompt': prompt,
  };
}

final class WrittenPracticeUseCases {
  WrittenPracticeUseCases({required this.sets, required this.isAvailable});
  final PersonalSetsUseCases sets;
  final bool Function() isAvailable;
  AppDatabase get database => sets.repository.database;

  Future<void> _fence(
    OwnerGenerationToken owner, [
    WrittenPracticeTicket? ticket,
    bool requireAvailable = true,
  ]) async {
    if ((requireAvailable && !isAvailable()) || (ticket?._cancelled ?? false)) {
      throw StateError('Writing retired');
    }
    await sets.ownerGeneration.requireCurrentAsync(owner);
    await DriftOwnerOperationGate(database).requireOwned(
      token: sets.ownerOperations.currentOperationVersion,
      nowUtc: sets.repository.nowUtc(),
    );
  }

  Future<T> _run<T>(
    OwnerGenerationToken owner,
    Future<T> Function() action, [
    WrittenPracticeTicket? ticket,
    bool requireAvailable = true,
  ]) async {
    if (requireAvailable && !isAvailable()) {
      throw StateError('Writing unavailable');
    }
    await sets.ownerGeneration.requireCurrentAsync(owner);
    return sets.ownerOperations.run(AiCancellation(), (active) async {
      if (active != owner.ownerId) throw StateError('Writing owner changed');
      return database.transaction(() async {
        await _fence(owner, ticket, requireAvailable);
        final value = await action();
        await _fence(owner, ticket, requireAvailable);
        return value;
      });
    });
  }

  Future<WrittenPracticeTicket> open(
    OwnerGenerationToken owner, {
    required String setId,
    required int setRevision,
    required int memberIndex,
    required String activityId,
  }) => _run(owner, () async {
    _identifier(activityId);
    final set = await sets.repository.readExact(
      ownerId: owner.ownerId,
      setId: setId,
      revision: setRevision,
    );
    if (set == null ||
        set.archived ||
        memberIndex < 0 ||
        memberIndex >= set.members.length) {
      throw StateError('Written prompt is unavailable');
    }
    final ticket = WrittenPracticeTicket._(
      owner,
      set,
      memberIndex,
      activityId,
      [],
    );
    await _admit(ticket);
    return _load(ticket);
  });

  Future<void> _admit(WrittenPracticeTicket ticket) async {
    final current = await sets.repository.readExact(
      ownerId: ticket.owner.ownerId,
      setId: ticket.set.setId,
      revision: ticket.set.revision,
    );
    if (current?.payloadHash != ticket.set.payloadHash || current!.archived) {
      throw StateError('Set pin changed');
    }
    final ref = ticket.set.members[ticket.memberIndex];
    final context = const ContextPracticeInventory().find(ref.wordId);
    if (context == null ||
        ref.senseKey != 'starter-object-v1' ||
        ref.senseRevision != 1 ||
        ref.lexicalArtifactHash != context.artifactHash) {
      throw StateError('Unreviewed written sense');
    }
    final crosswalk = await sets.repository.crosswalks.requirePinned(
      ticket.set.crosswalkPin,
    );
    final entry = crosswalk.resolve(ref);
    final word = (await DriftVocabularyRepository(
      database,
      contentManifests: sets.repository.crosswalks.manifests,
    ).readPinnedByIds([ref.wordId])).single;
    final categories =
        await (database.select(database.vocabularyCategories)..where(
              (r) =>
                  PackagedStarterAccess.categoriesFor(
                    database,
                    ticket.owner.ownerId,
                  ) &
                  r.isDeleted.equals(false),
            ))
            .get();
    final artifact = await sets.repository.crosswalks.manifests.requireVerified(
      ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: ref.wordId,
        revision: entry.wordRevision,
      ),
    );
    crosswalk.requireScored(
      ref,
      word: word,
      categoryAvailable: categories.any((c) => c.id == word.categoryId),
      lexicalArtifact: artifact,
    );
  }

  Future<WrittenPracticeTicket> _load(WrittenPracticeTicket ticket) async {
    final rows =
        await (database.select(database.writtenPracticeResults)
              ..where(
                (r) =>
                    r.ownerId.equals(ticket.owner.ownerId) &
                    r.activityId.equals(ticket.activityId),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.revision)]))
            .get();
    final results = <WrittenRubricResult>[];
    for (final row in rows) {
      final payload = jsonDecode(row.payloadJson) as Map;
      if (row.revision != results.length + 1 ||
          payload.length != 2 ||
          jsonEncode(payload['pin']) != jsonEncode(ticket.pin)) {
        throw StateError('Writing history pin mismatch');
      }
      final result = WrittenRubricResult.fromJson(
        Map<String, Object?>.from(payload['result'] as Map),
      );
      if (result.target != ticket.target) {
        throw StateError('Writing target mismatch');
      }
      results.add(result);
    }
    return WrittenPracticeTicket._(
      ticket.owner,
      ticket.set,
      ticket.memberIndex,
      ticket.activityId,
      results,
    );
  }

  Future<WrittenPracticeTicket> submit(
    WrittenPracticeTicket ticket, {
    required String operationId,
    required String response,
  }) => _run(ticket.owner, () async {
    _identifier(operationId);
    // Bound stored text even for unassessable input.
    if (response.length > 1000) throw ArgumentError('Response too long');
    await _admit(ticket);
    await _fence(ticket.owner, ticket);
    final result = const WrittenRubric().assess(ticket.target, response);
    final payload = jsonEncode({'pin': ticket.pin, 'result': result.toJson()});
    final replay =
        await (database.select(database.writtenPracticeResults)..where(
              (r) =>
                  r.ownerId.equals(ticket.owner.ownerId) &
                  r.operationId.equals(operationId),
            ))
            .getSingleOrNull();
    if (replay != null) {
      if (replay.activityId != ticket.activityId ||
          replay.revision != ticket.results.length + 1 ||
          replay.payloadJson != payload) {
        throw StateError('Writing operation collision');
      }
      return _load(ticket);
    }
    final latest = await _load(ticket);
    if (latest.results.length != ticket.results.length ||
        latest.results.length >= 20) {
      throw StateError('Stale writing revision or revision limit');
    }
    await database
        .into(database.writtenPracticeResults)
        .insert(
          WrittenPracticeResultsCompanion.insert(
            ownerId: ticket.owner.ownerId,
            activityId: ticket.activityId,
            revision: latest.results.length + 1,
            operationId: operationId,
            payloadJson: payload,
          ),
        );
    await _admit(ticket);
    await _fence(ticket.owner, ticket);
    return _load(ticket);
  }, ticket);

  void _identifier(String value) {
    if (value.isEmpty ||
        value != value.trim() ||
        value.length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw ArgumentError('Invalid writing identity');
    }
  }

  /// Coherent local backup, separate from redacted privacy export. The digest
  /// detects corruption, not authenticity. Restore requires current ownership,
  /// exact existing personal-set revisions and complete rubric replay.
  Future<Map<String, Object?>> exportArchive(OwnerGenerationToken owner) =>
      _run(
        owner,
        () async {
          final rows =
              await (database.select(database.writtenPracticeResults)
                    ..where((r) => r.ownerId.equals(owner.ownerId))
                    ..orderBy([
                      (r) => OrderingTerm.asc(r.activityId),
                      (r) => OrderingTerm.asc(r.revision),
                    ]))
                  .get();
          final records = [
            for (final row in rows)
              {
                'activityId': row.activityId,
                'revision': row.revision,
                'operationId': row.operationId,
                'payload': jsonDecode(row.payloadJson),
              },
          ];
          final content = <String, Object?>{
            'schemaVersion': 1,
            'ownerId': owner.ownerId,
            'records': records,
          };
          return {
            ...content,
            'sha256': sha256
                .convert(utf8.encode(jsonEncode(content)))
                .toString(),
          };
        },
        null,
        false,
      );

  Future<void> restoreArchive(
    OwnerGenerationToken owner,
    Map<String, Object?> envelope,
  ) {
    // Freeze caller input before waiting for the owner lease.
    final frozen = Map<String, Object?>.from(
      jsonDecode(jsonEncode(envelope)) as Map,
    );
    return _run(
      owner,
      () async {
        if (frozen.length != 4 ||
            frozen['schemaVersion'] != 1 ||
            frozen['ownerId'] != owner.ownerId ||
            frozen['records'] is! List ||
            (frozen['records'] as List).length > 10000) {
          throw const FormatException('Unsupported writing archive');
        }
        final content = {...frozen}..remove('sha256');
        if (sha256.convert(utf8.encode(jsonEncode(content))).toString() !=
            frozen['sha256']) {
          throw const FormatException('Writing archive checksum mismatch');
        }
        final revisions = <String, int>{};
        final operations = <String>{};
        for (final raw in frozen['records'] as List) {
          if (raw is! Map ||
              raw.length != 4 ||
              raw['activityId'] is! String ||
              raw['operationId'] is! String ||
              raw['revision'] is! int ||
              raw['payload'] is! Map) {
            throw const FormatException('Invalid writing archive record');
          }
          final activity = raw['activityId'] as String,
              operation = raw['operationId'] as String;
          _identifier(activity);
          _identifier(operation);
          final revision = raw['revision'] as int;
          if (revision != (revisions[activity] ?? 0) + 1 ||
              revision > 20 ||
              !operations.add(operation)) {
            throw const FormatException('Invalid writing revision chain');
          }
          revisions[activity] = revision;
          final payload = Map<String, Object?>.from(raw['payload'] as Map);
          if (payload.length != 2 ||
              payload['pin'] is! Map ||
              payload['result'] is! Map) {
            throw const FormatException('Invalid writing payload');
          }
          final pin = Map<String, Object?>.from(payload['pin'] as Map);
          if (pin['set'] is! Map || pin['memberIndex'] is! int) {
            throw const FormatException('Invalid writing pin');
          }
          final set = PersonalSetRevision.fromJson(
            Map<String, Object?>.from(pin['set'] as Map),
          );
          final index = pin['memberIndex'] as int;
          if (index < 0 || index >= set.members.length) {
            throw const FormatException('Invalid writing member');
          }
          final stored = await sets.repository.readExact(
            ownerId: owner.ownerId,
            setId: set.setId,
            revision: set.revision,
          );
          if (stored?.payloadHash != set.payloadHash) {
            throw StateError('Restore the exact personal set first');
          }
          final context = const ContextPracticeInventory().find(
            set.members[index].wordId,
          );
          if (context == null ||
              set.members[index].senseKey != 'starter-object-v1' ||
              set.members[index].senseRevision != 1 ||
              set.members[index].lexicalArtifactHash != context.artifactHash) {
            throw const FormatException('Unsupported archived sense');
          }
          final ticket = WrittenPracticeTicket._(
            owner,
            set,
            index,
            activity,
            [],
          );
          if (jsonEncode(ticket.pin) != jsonEncode(pin)) {
            throw const FormatException('Unsupported rubric pin');
          }
          final result = WrittenRubricResult.fromJson(
            Map<String, Object?>.from(payload['result'] as Map),
          );
          if (result.target != ticket.target || result.response.length > 1000) {
            throw const FormatException('Invalid archived result');
          }
          final encoded = jsonEncode(payload);
          final prior =
              await (database.select(database.writtenPracticeResults)..where(
                    (r) =>
                        r.ownerId.equals(owner.ownerId) &
                        (r.operationId.equals(operation) |
                            (r.activityId.equals(activity) &
                                r.revision.equals(revision))),
                  ))
                  .get();
          if (prior.isNotEmpty) {
            if (prior.length != 1 ||
                prior.single.operationId != operation ||
                prior.single.activityId != activity ||
                prior.single.revision != revision ||
                prior.single.payloadJson != encoded) {
              throw StateError('Writing restore collision');
            }
          } else {
            await database
                .into(database.writtenPracticeResults)
                .insert(
                  WrittenPracticeResultsCompanion.insert(
                    ownerId: owner.ownerId,
                    activityId: activity,
                    revision: revision,
                    operationId: operation,
                    payloadJson: encoded,
                  ),
                );
          }
          await _load(ticket);
        }
      },
      null,
      false,
    );
  }
}
