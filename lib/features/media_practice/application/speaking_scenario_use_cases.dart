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
import '../../learning/domain/context_practice.dart';
import '../domain/speaking_scenario.dart';

final class SpeakingScenarioRollout {
  const SpeakingScenarioRollout.implementedOff() : enabled = false;
  const SpeakingScenarioRollout.internal() : enabled = true;
  final bool enabled;
}

final class SpeakingScenarioTicket {
  SpeakingScenarioTicket._(
    this.owner,
    this.set,
    this.memberIndex,
    this.activityId,
    this.intent,
    List<SpeakingRubricResult> results,
  ) : results = List.unmodifiable(results);
  final OwnerGenerationToken owner;
  final PersonalSetRevision set;
  final int memberIndex;
  final String activityId;
  final SpeakingIntent intent;
  final List<SpeakingRubricResult> results;
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  String get target =>
      set.members[memberIndex].wordId.substring('word:starter-'.length);
  String get prompt => SpeakingRubric.prompts[target]!;
  Map<String, Object?> get pin => {
    'schemaVersion': 1,
    'set': set.toJson(),
    'memberIndex': memberIndex,
    'intent': intent.name,
    'rubricRevision': SpeakingRubric.revision,
    'inventoryHash': SpeakingRubric.fingerprint,
    'prompt': prompt,
  };
}

final class SpeakingScenarioUseCases {
  SpeakingScenarioUseCases({required this.sets, required this.isAvailable});
  final PersonalSetsUseCases sets;
  final bool Function() isAvailable;
  AppDatabase get database => sets.repository.database;

  Future<void> _fence(
    OwnerGenerationToken owner, [
    SpeakingScenarioTicket? ticket,
    bool requireAvailable = true,
  ]) async {
    if ((requireAvailable && !isAvailable()) || (ticket?._cancelled ?? false)) {
      throw StateError('Speaking retired');
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
    SpeakingScenarioTicket? ticket,
    bool requireAvailable = true,
  ]) async {
    if (requireAvailable && !isAvailable()) {
      throw StateError('Speaking unavailable');
    }
    await sets.ownerGeneration.requireCurrentAsync(owner);
    return sets.ownerOperations.run(AiCancellation(), (active) async {
      if (active != owner.ownerId) throw StateError('Speaking owner changed');
      return database.transaction(() async {
        await _fence(owner, ticket, requireAvailable);
        final value = await action();
        await _fence(owner, ticket, requireAvailable);
        return value;
      });
    });
  }

  Future<SpeakingScenarioTicket> open(
    OwnerGenerationToken owner, {
    required String setId,
    required int setRevision,
    required int memberIndex,
    required String activityId,
    required SpeakingIntent intent,
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
      throw StateError('Speaking prompt is unavailable');
    }
    final ticket = SpeakingScenarioTicket._(
      owner,
      set,
      memberIndex,
      activityId,
      intent,
      [],
    );
    await _admit(ticket);
    return _load(ticket);
  });

  Future<void> _admit(SpeakingScenarioTicket ticket) async {
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
      throw StateError('Unreviewed speaking sense');
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

  Future<SpeakingScenarioTicket> _load(SpeakingScenarioTicket ticket) async {
    final rows =
        await (database.select(database.speakingPracticeResults)
              ..where(
                (r) =>
                    r.ownerId.equals(ticket.owner.ownerId) &
                    r.activityId.equals(ticket.activityId),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.revision)]))
            .get();
    final results = <SpeakingRubricResult>[];
    for (final row in rows) {
      final payload = jsonDecode(row.payloadJson) as Map;
      if (row.revision != results.length + 1 ||
          payload.length != 2 ||
          jsonEncode(payload['pin']) != jsonEncode(ticket.pin)) {
        throw StateError('Speaking history pin mismatch');
      }
      final result = SpeakingRubricResult.fromJson(
        Map<String, Object?>.from(payload['result'] as Map),
      );
      if (result.target != ticket.target) {
        throw StateError('Speaking target mismatch');
      }
      results.add(result);
    }
    return SpeakingScenarioTicket._(
      ticket.owner,
      ticket.set,
      ticket.memberIndex,
      ticket.activityId,
      ticket.intent,
      results,
    );
  }

  Future<SpeakingScenarioTicket> submit(
    SpeakingScenarioTicket ticket, {
    required String operationId,
    required String response,
    SpeakingInput input = SpeakingInput.speech,
    bool confirmed = false,
    bool isFinal = true,
  }) => _run(ticket.owner, () async {
    _identifier(operationId);
    // Bound stored text even for unassessable input.
    if (response.length > 1000) throw ArgumentError('Response too long');
    await _admit(ticket);
    await _fence(ticket.owner, ticket);
    final result = const SpeakingRubric().assess(
      ticket.target,
      response,
      input: input,
      confirmed: confirmed,
      isFinal: isFinal,
    );
    final payload = jsonEncode({'pin': ticket.pin, 'result': result.toJson()});
    final replay =
        await (database.select(database.speakingPracticeResults)..where(
              (r) =>
                  r.ownerId.equals(ticket.owner.ownerId) &
                  r.operationId.equals(operationId),
            ))
            .getSingleOrNull();
    if (replay != null) {
      if (replay.activityId != ticket.activityId ||
          replay.revision != ticket.results.length + 1 ||
          replay.payloadJson != payload) {
        throw StateError('Speaking operation collision');
      }
      return _load(ticket);
    }
    final latest = await _load(ticket);
    if (latest.results.length != ticket.results.length ||
        latest.results.length >= 6) {
      throw StateError('Stale speaking revision or revision limit');
    }
    await database
        .into(database.speakingPracticeResults)
        .insert(
          SpeakingPracticeResultsCompanion.insert(
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
      throw ArgumentError('Invalid speaking identity');
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
              await (database.select(database.speakingPracticeResults)
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
          throw const FormatException('Unsupported speaking archive');
        }
        final content = {...frozen}..remove('sha256');
        if (sha256.convert(utf8.encode(jsonEncode(content))).toString() !=
            frozen['sha256']) {
          throw const FormatException('Speaking archive checksum mismatch');
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
            throw const FormatException('Invalid speaking archive record');
          }
          final activity = raw['activityId'] as String,
              operation = raw['operationId'] as String;
          _identifier(activity);
          _identifier(operation);
          final revision = raw['revision'] as int;
          if (revision != (revisions[activity] ?? 0) + 1 ||
              revision > 6 ||
              !operations.add(operation)) {
            throw const FormatException('Invalid speaking revision chain');
          }
          revisions[activity] = revision;
          final payload = Map<String, Object?>.from(raw['payload'] as Map);
          if (payload.length != 2 ||
              payload['pin'] is! Map ||
              payload['result'] is! Map) {
            throw const FormatException('Invalid speaking payload');
          }
          final pin = Map<String, Object?>.from(payload['pin'] as Map);
          if (pin['set'] is! Map || pin['memberIndex'] is! int) {
            throw const FormatException('Invalid speaking pin');
          }
          final set = PersonalSetRevision.fromJson(
            Map<String, Object?>.from(pin['set'] as Map),
          );
          final index = pin['memberIndex'] as int;
          if (index < 0 || index >= set.members.length) {
            throw const FormatException('Invalid speaking member');
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
          final ticket = SpeakingScenarioTicket._(
            owner,
            set,
            index,
            activity,
            SpeakingIntent.values.byName(pin['intent'] as String),
            [],
          );
          if (jsonEncode(ticket.pin) != jsonEncode(pin)) {
            throw const FormatException('Unsupported rubric pin');
          }
          final result = SpeakingRubricResult.fromJson(
            Map<String, Object?>.from(payload['result'] as Map),
          );
          if (result.target != ticket.target || result.response.length > 1000) {
            throw const FormatException('Invalid archived result');
          }
          final encoded = jsonEncode(payload);
          final prior =
              await (database.select(database.speakingPracticeResults)..where(
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
              throw StateError('Speaking restore collision');
            }
          } else {
            await database
                .into(database.speakingPracticeResults)
                .insert(
                  SpeakingPracticeResultsCompanion.insert(
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
