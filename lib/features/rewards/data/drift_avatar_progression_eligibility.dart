import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../events/domain/event_envelope_v2.dart';
import '../domain/avatar_progression_policy.dart';
import '../domain/economy_transaction_policy.dart';
import '../domain/reward_models.dart';

/// Durable per-owner boundary for the catalog-v1 era.
///
/// The marker fingerprints the complete set of v1 avatar rows that existed
/// when f32 became authoritative. A later local/downgraded v1 insertion changes
/// that set and fails rebuilding. A cloud v1 row may extend the fingerprint
/// only when its immutable occurrence predates the global cutover and the
/// trusted server receipt also predates the cutover without predating the row.
/// The first-device marker uses the same client-attested UTC trust boundary as
/// other local evidence. It detects ordinary late upgrades, not a hostile
/// device-clock rollback; cloud admission never trusts that clock and requires
/// a server-timestamped pre-cutover echo or a deterministic carry receipt.
final class DriftAvatarProgressionEligibility {
  DriftAvatarProgressionEligibility(
    this.database, {
    this.transactionPolicy = const EconomyTransactionPolicy(),
    DateTime Function()? nowUtc,
  }) : nowUtc = nowUtc ?? _systemNowUtc;

  static const int cutoverVersion = 2;
  static const int grandfatheredProgressionPolicyVersion = 1;
  static const int grandfatheredCatalogVersion = 1;
  static const int activatedCatalogVersion = 2;
  static const String cutoverPolicyVersion =
      'avatar-progression-eligibility-v2';
  static const String eventType = 'AvatarProgressionEligibilityCutover';
  static const String aggregateType = 'AvatarProgressionEligibility';
  static const int maxPreMarkerLegacyRows = 256;
  static const String _quarantineReason = 'ownerRehomeMarkerMismatch';

  final db.AppDatabase database;
  final EconomyTransactionPolicy transactionPolicy;
  final DateTime Function() nowUtc;

  Future<void> establishCutover(String ownerId) => database.transaction(
    () => _establishCutover(_requiredIdentifier(ownerId, 'ownerId')),
  );

  Future<void> requireGrandfatheredSet(String ownerId) =>
      database.transaction(() async {
        final canonicalOwnerId = _requiredIdentifier(ownerId, 'ownerId');
        await _establishCutover(canonicalOwnerId);
        final marker = await _readMarker(canonicalOwnerId);
        if (marker == null) throw StateError('avatar cutover is unavailable');
        await _requireMarkerMatchesRows(canonicalOwnerId, marker);
      });

  Future<String> registerTrustedLegacyPull({
    required String ownerId,
    required String transactionId,
    required String idempotencyKey,
    required String transactionType,
    required int amount,
    required String itemId,
    required int catalogVersion,
    required String? sourceEventId,
    required int occurredAtUtcMs,
    required int serverUpdatedAtUtcMs,
  }) => database.transaction(() async {
    final canonicalOwnerId = _requiredIdentifier(ownerId, 'ownerId');
    final canonicalTransactionId = _requiredIdentifier(
      transactionId,
      'transactionId',
    );
    final canonicalIdempotencyKey = _requiredIdentifier(
      idempotencyKey,
      'idempotencyKey',
    );
    final canonicalSource = _trustedLegacySource(
      transactionId: canonicalTransactionId,
      idempotencyKey: canonicalIdempotencyKey,
      transactionType: transactionType,
      amount: amount,
      itemId: itemId,
      catalogVersion: catalogVersion,
      sourceEventId: sourceEventId,
      occurredAtUtcMs: occurredAtUtcMs,
      serverUpdatedAtUtcMs: serverUpdatedAtUtcMs,
    );
    final candidate = _LegacyAvatarTransaction(
      id: canonicalTransactionId,
      idempotencyKey: canonicalIdempotencyKey,
      transactionType: transactionType,
      amount: amount,
      itemId: itemId,
      catalogVersion: catalogVersion,
      sourceEventId: canonicalSource,
      occurredAtUtcMs: occurredAtUtcMs,
    );
    _requireLegacyTransaction(candidate);
    final existing =
        await (database.select(database.rewardTransactions)..where(
              (row) =>
                  row.id.equals(canonicalTransactionId) &
                  row.ownerId.equals(canonicalOwnerId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      _requireTrustedEcho(existing, candidate, inboundSource: sourceEventId);
      final marker = await _readMarker(canonicalOwnerId);
      if (marker != null && !marker.isQuarantined) {
        await _requireMarkerMatchesRows(canonicalOwnerId, marker);
      }
      if (existing.sourceEventId != canonicalSource) {
        await (database.update(database.rewardTransactions)..where(
              (row) =>
                  row.id.equals(canonicalTransactionId) &
                  row.ownerId.equals(canonicalOwnerId),
            ))
            .write(
              db.RewardTransactionsCompanion(
                sourceEventId: Value(canonicalSource),
              ),
            );
      }
      if (marker != null && marker.isQuarantined) {
        final remaining = await _legacyTransactions(canonicalOwnerId);
        if (remaining.any((row) => row.sourceEventId == null)) {
          // An exact trusted echo repairs only its own row. The recognized
          // quarantine remains durable until the complete set is portable.
          return canonicalSource;
        }
        await _writeMarker(canonicalOwnerId, remaining);
      } else if (marker == null) {
        final remaining = await _legacyTransactions(canonicalOwnerId);
        final establishedAtUtcMs =
            (_requiredUtc(nowUtc()).millisecondsSinceEpoch ~/ 1000) * 1000;
        if (establishedAtUtcMs >=
                AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs &&
            remaining.any((row) => row.sourceEventId == null)) {
          // Each trusted echo is promoted independently. The final echo can
          // establish the marker; until then every avatar row stays closed.
          return canonicalSource;
        }
        await _establishCutover(canonicalOwnerId);
      } else {
        await _writeMarker(
          canonicalOwnerId,
          await _legacyTransactions(canonicalOwnerId),
        );
      }
      return canonicalSource;
    }

    await _establishCutover(canonicalOwnerId);
    final marker = await _readMarker(canonicalOwnerId);
    if (marker == null) throw StateError('avatar cutover is unavailable');
    final current = await _legacyTransactions(canonicalOwnerId);
    _requireMarkerMatches(marker, current);
    final sameId = current.where((row) => row.id == candidate.id).toList();
    if (sameId.isNotEmpty) {
      if (sameId.length != 1 || sameId.single != candidate) {
        throw StateError('legacy avatar identity collision');
      }
      return canonicalSource;
    }
    await _writeMarker(canonicalOwnerId, <_LegacyAvatarTransaction>[
      ...current,
      candidate,
    ]);
    return canonicalSource;
  });

  Future<void> prepareLegacyCloudCarryForward({
    required String ownerId,
    required String transactionId,
  }) async {
    await prepareLegacyCloudCarryForwardBatch(
      ownerId: ownerId,
      transactionIds: <String>{transactionId},
    );
  }

  Future<Set<String>> prepareLegacyCloudCarryForwardBatch({
    required String ownerId,
    required Set<String> transactionIds,
  }) => database.transaction(() async {
    final canonicalOwnerId = _requiredIdentifier(ownerId, 'ownerId');
    if (transactionIds.isEmpty ||
        transactionIds.length > maxPreMarkerLegacyRows) {
      throw ArgumentError.value(transactionIds, 'transactionIds');
    }
    final canonicalTransactionIds = <String>{
      for (final id in transactionIds) _requiredIdentifier(id, 'transactionId'),
    };
    var marker = await _readMarker(canonicalOwnerId);
    final before = await _legacyTransactions(canonicalOwnerId);
    if (before.length > maxPreMarkerLegacyRows) {
      throw StateError('legacy avatar carry-forward population is too large');
    }
    if (marker != null && marker.isQuarantined) {
      // This may resolve an already repaired, entirely portable population;
      // it can never manufacture carry evidence from quarantined raw rows.
      await _establishCutover(canonicalOwnerId);
      marker = await _readMarker(canonicalOwnerId);
    }
    if (marker != null) {
      _requireMarkerMatches(marker, before);
    }
    final byId = <String, _LegacyAvatarTransaction>{
      for (final transaction in before) transaction.id: transaction,
    };
    for (final id in canonicalTransactionIds) {
      if (!byId.containsKey(id)) {
        throw StateError('legacy avatar carry-forward row is unavailable');
      }
    }

    final requestedAtUtcMs =
        (_requiredUtc(nowUtc()).millisecondsSinceEpoch ~/ 1000) * 1000;
    final lateFirstLaunch =
        marker == null &&
        requestedAtUtcMs >=
            AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs;
    if (marker == null && !lateFirstLaunch) {
      await _establishCutover(canonicalOwnerId);
    }
    final rowsToConvert = lateFirstLaunch
        ? before.where((row) => row.sourceEventId == null)
        : before.where(
            (row) =>
                canonicalTransactionIds.contains(row.id) &&
                row.sourceEventId == null,
          );
    final converted = <String>{};
    for (final transaction in rowsToConvert) {
      await _writeCarryForwardSource(canonicalOwnerId, transaction);
      converted.add(transaction.id);
    }
    final after = await _legacyTransactions(canonicalOwnerId);
    if (lateFirstLaunch) {
      await _insertMarker(canonicalOwnerId, after, requestedAtUtcMs);
    } else {
      await _writeMarker(canonicalOwnerId, after);
    }
    return Set<String>.unmodifiable(converted);
  });

  /// Owner upgrade is already fenced and may canonically rewrite a colliding
  /// idempotency key. Refreshing is limited to structurally valid pre-cutover
  /// rows; it cannot grandfather a late v1 purchase.
  Future<void> refreshForOwnerMerge(String ownerId) =>
      database.transaction(() async {
        final canonicalOwnerId = _requiredIdentifier(ownerId, 'ownerId');
        final marker = await _readMarker(canonicalOwnerId);
        if (marker == null || marker.isQuarantined) {
          throw StateError('avatar cutover is unavailable during owner merge');
        }
        final transactions = await _legacyTransactions(canonicalOwnerId);
        if (transactions.length != marker.transactionCount) {
          throw StateError(
            'avatar cutover population changed during owner merge',
          );
        }
        await _writeMarker(canonicalOwnerId, transactions);
      });

  Future<Set<String>> mergeCutovers({
    required String sourceId,
    required String targetId,
  }) => database.transaction(() async {
    final sourceOwnerId = _requiredIdentifier(sourceId, 'sourceId');
    final targetOwnerId = _requiredIdentifier(targetId, 'targetId');
    if (sourceOwnerId == targetOwnerId) {
      await _establishCutover(sourceOwnerId);
      return const <String>{};
    }
    await _establishCutover(sourceOwnerId);
    await _establishCutover(targetOwnerId);
    await _carryForwardAuthorizedRows(sourceOwnerId);
    final convertedTargetTransactionIds = await _carryForwardAuthorizedRows(
      targetOwnerId,
    );
    final sourceRows = await _legacyTransactions(sourceOwnerId);
    final targetRows = await _legacyTransactions(targetOwnerId);
    await _writeMarker(targetOwnerId, <_LegacyAvatarTransaction>[
      ...sourceRows,
      ...targetRows,
    ]);
    final deleted = await (database.delete(
      database.eventsV2,
    )..where((row) => row.eventId.equals(_cutoverId(sourceOwnerId)))).go();
    if (deleted != 1) throw StateError('avatar cutover merge is incomplete');
    return convertedTargetTransactionIds;
  });

  /// Converts valid marker populations to portable carry evidence before
  /// rehome. A rejected marker is replaced by an explicit target-bound
  /// quarantine, never marker absence: its exact envelope is committed into
  /// the provenance digest, including any earlier quarantine on repeated
  /// merges. Never-marked legacy populations keep their separate recovery
  /// path. Only target rows actually converted are returned for retry revival.
  Future<Set<String>> detachCutoversForQuarantinedMerge({
    required String sourceId,
    required String targetId,
  }) => database.transaction(() async {
    final targetOwnerId = _requiredIdentifier(targetId, 'targetId');
    final convertedTargetTransactionIds = <String>{};
    final rejectedMarkers = <String>[];
    final ownerIds = <String>{
      _requiredIdentifier(sourceId, 'sourceId'),
      targetOwnerId,
    };
    for (final ownerId in ownerIds) {
      final priorMarkers =
          await (database.select(database.eventsV2)..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.eventType.equals(eventType),
              ))
              .get();
      try {
        final marker = await _readMarker(ownerId);
        if (marker != null) {
          final converted = await _carryForwardAuthorizedRows(ownerId);
          if (ownerId == targetOwnerId) {
            convertedTargetTransactionIds.addAll(converted);
          }
        }
      } on StateError {
        // The lifecycle may proceed, but existing rejected authority must not
        // become indistinguishable from a never-marked legacy installation.
        rejectedMarkers.addAll(
          priorMarkers.map((row) => jsonEncode(row.toJson())),
        );
      }
      await (database.delete(database.eventsV2)..where(
            (row) =>
                row.ownerId.equals(ownerId) & row.eventType.equals(eventType),
          ))
          .go();
    }
    if (rejectedMarkers.isNotEmpty) {
      rejectedMarkers.sort();
      final provenanceDigest = sha256
          .convert(utf8.encode('${rejectedMarkers.join('\n')}\n'))
          .toString();
      final establishedAtUtcMs =
          (_requiredUtc(nowUtc()).millisecondsSinceEpoch ~/ 1000) * 1000;
      await _insertMarker(
        targetOwnerId,
        const <_LegacyAvatarTransaction>[],
        establishedAtUtcMs,
        quarantineProvenanceDigest: provenanceDigest,
      );
    }
    return Set<String>.unmodifiable(convertedTargetTransactionIds);
  });

  Future<void> rollbackEmptyTransition(String ownerId) =>
      database.transaction(() async {
        final canonicalOwnerId = _requiredIdentifier(ownerId, 'ownerId');
        final marker = await _readMarker(canonicalOwnerId);
        if (marker == null ||
            marker.isQuarantined ||
            marker.transactionCount != 0) {
          throw StateError('avatar cutover rollback is not safe');
        }
        final reward =
            await (database.select(database.rewardTransactions)
                  ..where((row) => row.ownerId.equals(canonicalOwnerId))
                  ..limit(1))
                .getSingleOrNull();
        if (reward != null) {
          throw StateError('avatar cutover rollback has durable rewards');
        }
        final deleted =
            await (database.delete(database.eventsV2)..where(
                  (row) =>
                      row.eventId.equals(_cutoverId(canonicalOwnerId)) &
                      row.ownerId.equals(canonicalOwnerId) &
                      row.eventType.equals(eventType),
                ))
                .go();
        if (deleted != 1) throw StateError('avatar cutover rollback failed');
      });

  Future<void> _establishCutover(String ownerId) async {
    final existing = await _readMarker(ownerId);
    if (existing != null) {
      if (existing.isQuarantined) {
        // Validating every portable row is required even after explicit
        // repair; a non-null but malformed source is never sufficient.
        await _writeMarker(ownerId, await _legacyTransactions(ownerId));
      } else {
        await _requireMarkerMatchesRows(ownerId, existing);
      }
      return;
    }
    final rows = await _legacyTransactions(ownerId);
    final requestedAtUtc = _requiredUtc(nowUtc());
    final establishedAtUtcMs =
        (requestedAtUtc.millisecondsSinceEpoch ~/ 1000) * 1000;
    if (establishedAtUtcMs >=
            AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs &&
        rows.any((row) => row.sourceEventId == null)) {
      throw StateError(
        'raw catalog-v1 avatar rows require pre-cutover authority',
      );
    }
    await _insertMarker(ownerId, rows, establishedAtUtcMs);
  }

  Future<void> _insertMarker(
    String ownerId,
    List<_LegacyAvatarTransaction> rows,
    int establishedAtUtcMs, {
    String? quarantineProvenanceDigest,
  }) async {
    final atUtc = DateTime.fromMillisecondsSinceEpoch(
      AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs,
      isUtc: true,
    );
    final establishedAtUtc = DateTime.fromMillisecondsSinceEpoch(
      establishedAtUtcMs,
      isUtc: true,
    );
    final key = _cutoverId(ownerId);
    await database
        .into(database.eventsV2)
        .insert(
          db.EventsV2Companion.insert(
            eventId: key,
            eventType: eventType,
            eventVersion: cutoverVersion,
            occurredAtUtc: atUtc,
            recordedAtUtc: establishedAtUtc,
            actorIdentity: ownerId,
            ownerId: ownerId,
            aggregateType: aggregateType,
            aggregateId: ownerId,
            idempotencyKey: key,
            consentContextJson: jsonEncode(
              const ConsentContext.none().toJson(),
            ),
            policyVersion: const Value(cutoverPolicyVersion),
            appVersion: 'avatar-progression-cutover',
            buildId: 'v$cutoverVersion',
            privacyClassification: PrivacyClassification.ownerOnly.name,
            payloadJson: _payload(
              ownerId,
              rows,
              establishedAtUtcMs,
              quarantineProvenanceDigest: quarantineProvenanceDigest,
            ),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final inserted = await _readMarker(ownerId);
    if (inserted == null) throw StateError('avatar cutover write conflict');
    if (quarantineProvenanceDigest != null) {
      if (inserted.quarantineProvenanceDigest != quarantineProvenanceDigest) {
        throw StateError('avatar quarantine write conflict');
      }
    } else {
      await _requireMarkerMatchesRows(ownerId, inserted);
    }
  }

  Future<_AvatarCutoverMarker?> _readMarker(String ownerId) async {
    final rows =
        await (database.select(database.eventsV2)..where(
              (row) =>
                  row.ownerId.equals(ownerId) & row.eventType.equals(eventType),
            ))
            .get();
    if (rows.isEmpty) return null;
    if (rows.length != 1) throw StateError('invalid avatar cutover identity');
    final row = rows.single;
    late final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(row.payloadJson);
      if (decoded is! Map) throw const FormatException();
      payload = decoded.cast<String, dynamic>();
    } catch (_) {
      throw StateError('invalid avatar cutover payload');
    }
    final isQuarantined = payload['state'] == 'quarantined';
    final keys = <String>{
      'ownerId',
      'cutoverVersion',
      'progressionPolicyVersion',
      'legacyCatalogVersion',
      'activeCatalogVersion',
      'legacyV1CutoverUtcMs',
      'establishedAtUtcMs',
      if (isQuarantined) ...{
        'state',
        'reasonCode',
        'quarantineProvenanceDigest',
      } else ...{
        'grandfatheredTransactionCount',
        'grandfatheredTransactionDigest',
      },
    };
    final establishedAtUtcMs = payload['establishedAtUtcMs'];
    final transactionCount = payload['grandfatheredTransactionCount'];
    final transactionDigest = payload['grandfatheredTransactionDigest'];
    final quarantineProvenanceDigest = payload['quarantineProvenanceDigest'];
    final digestPattern = RegExp(r'^[0-9a-f]{64}$');
    final atUtc = DateTime.fromMillisecondsSinceEpoch(
      AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs,
      isUtc: true,
    );
    if (payload.keys.toSet().length != keys.length ||
        !payload.keys.toSet().containsAll(keys) ||
        payload['ownerId'] != ownerId ||
        payload['cutoverVersion'] != cutoverVersion ||
        payload['progressionPolicyVersion'] !=
            grandfatheredProgressionPolicyVersion ||
        payload['legacyCatalogVersion'] != grandfatheredCatalogVersion ||
        payload['activeCatalogVersion'] != activatedCatalogVersion ||
        payload['legacyV1CutoverUtcMs'] !=
            AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs ||
        establishedAtUtcMs is! int ||
        establishedAtUtcMs < 0 ||
        (isQuarantined
            ? payload['reasonCode'] != _quarantineReason ||
                  quarantineProvenanceDigest is! String ||
                  !digestPattern.hasMatch(quarantineProvenanceDigest)
            : transactionCount is! int ||
                  transactionCount < 0 ||
                  transactionDigest is! String ||
                  !digestPattern.hasMatch(transactionDigest)) ||
        row.eventId != _cutoverId(ownerId) ||
        row.idempotencyKey != _cutoverId(ownerId) ||
        row.eventType != eventType ||
        row.eventVersion != cutoverVersion ||
        row.occurredAtUtc.toUtc() != atUtc ||
        row.recordedAtUtc.toUtc().millisecondsSinceEpoch !=
            establishedAtUtcMs ||
        row.actorIdentity != ownerId ||
        row.aggregateType != aggregateType ||
        row.aggregateId != ownerId ||
        row.policyVersion != cutoverPolicyVersion) {
      throw StateError('invalid durable avatar cutover');
    }
    return _AvatarCutoverMarker(
      establishedAtUtcMs: establishedAtUtcMs,
      transactionCount: isQuarantined ? null : transactionCount as int,
      transactionDigest: isQuarantined ? null : transactionDigest as String,
      quarantineProvenanceDigest: isQuarantined
          ? quarantineProvenanceDigest as String
          : null,
    );
  }

  Future<List<_LegacyAvatarTransaction>> _legacyTransactions(
    String ownerId,
  ) async {
    final rows =
        await (database.select(database.rewardTransactions)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.transactionType.isIn(<String>[
                    EconomyTransactionType.purchase.name,
                    EconomyTransactionType.equip.name,
                  ]) &
                  row.catalogVersion.equals(grandfatheredCatalogVersion),
            ))
            .get();
    final transactions = <_LegacyAvatarTransaction>[
      for (final row in rows)
        _LegacyAvatarTransaction(
          id: row.id,
          idempotencyKey: row.idempotencyKey,
          transactionType: row.transactionType,
          amount: row.amount,
          itemId: row.itemId,
          catalogVersion: row.catalogVersion,
          sourceEventId: row.sourceEventId,
          occurredAtUtcMs: row.occurredAtUtcMs,
        ),
    ];
    for (final transaction in transactions) {
      _requireLegacyTransaction(transaction);
    }
    transactions.sort((left, right) => left.id.compareTo(right.id));
    return transactions;
  }

  void _requireLegacyTransaction(_LegacyAvatarTransaction transaction) {
    final item = transaction.itemId == null
        ? null
        : RewardCatalog.byIdAtVersion(
            transaction.itemId!,
            grandfatheredCatalogVersion,
          );
    if (item == null ||
        transaction.catalogVersion != grandfatheredCatalogVersion ||
        transaction.occurredAtUtcMs < 0 ||
        transaction.occurredAtUtcMs >=
            AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs ||
        !transactionPolicy.isValidPersistedRow(
          idempotencyKey: transaction.idempotencyKey,
          transactionType: transaction.transactionType,
          amount: transaction.amount,
          itemId: transaction.itemId,
          slot: item.slot,
          catalogVersion: transaction.catalogVersion,
          sourceEventId: transaction.sourceEventId,
          occurredAtUtcMs: transaction.occurredAtUtcMs,
        ) ||
        (transaction.sourceEventId != null &&
            !const AvatarLegacyCarryForwardContract()
                .isValidPersistedTransaction(
                  transactionId: transaction.id,
                  idempotencyKey: transaction.idempotencyKey,
                  transactionType: transaction.transactionType,
                  amount: transaction.amount,
                  itemId: transaction.itemId,
                  catalogVersion: transaction.catalogVersion,
                  sourceEventId: transaction.sourceEventId,
                  occurredAtUtcMs: transaction.occurredAtUtcMs,
                ))) {
      throw StateError('invalid grandfathered catalog-v1 avatar row');
    }
  }

  String _trustedLegacySource({
    required String transactionId,
    required String idempotencyKey,
    required String transactionType,
    required int amount,
    required String itemId,
    required int catalogVersion,
    required String? sourceEventId,
    required int occurredAtUtcMs,
    required int serverUpdatedAtUtcMs,
  }) {
    if (serverUpdatedAtUtcMs < occurredAtUtcMs) {
      throw StateError('catalog-v1 server receipt predates its occurrence');
    }
    if (sourceEventId == null &&
        serverUpdatedAtUtcMs >=
            AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs) {
      throw StateError('catalog-v1 server receipt crossed avatar cutover');
    }
    final issued = const AvatarLegacyCarryForwardContract()
        .issue(
          transactionId: transactionId,
          idempotencyKey: idempotencyKey,
          transactionType: transactionType,
          amount: amount,
          itemId: itemId,
          catalogVersion: catalogVersion,
          occurredAtUtcMs: occurredAtUtcMs,
        )
        .sourceEventId;
    if (sourceEventId != null && sourceEventId != issued) {
      throw StateError('catalog-v1 server carry evidence is invalid');
    }
    return issued;
  }

  void _requireTrustedEcho(
    db.RewardTransaction existing,
    _LegacyAvatarTransaction candidate, {
    required String? inboundSource,
  }) {
    if (existing.id != candidate.id ||
        existing.idempotencyKey != candidate.idempotencyKey ||
        existing.transactionType != candidate.transactionType ||
        existing.amount != candidate.amount ||
        existing.itemId != candidate.itemId ||
        existing.catalogVersion != candidate.catalogVersion ||
        existing.occurredAtUtcMs != candidate.occurredAtUtcMs ||
        (existing.sourceEventId != null &&
            existing.sourceEventId != candidate.sourceEventId) ||
        (inboundSource != null && inboundSource != candidate.sourceEventId)) {
      throw StateError('legacy avatar trusted echo changed identity');
    }
  }

  Future<Set<String>> _carryForwardAuthorizedRows(String ownerId) async {
    final marker = await _readMarker(ownerId);
    if (marker == null) throw StateError('avatar cutover is unavailable');
    final before = await _legacyTransactions(ownerId);
    _requireMarkerMatches(marker, before);
    final convertedTransactionIds = <String>{};
    for (final transaction in before.where(
      (candidate) => candidate.sourceEventId == null,
    )) {
      await _writeCarryForwardSource(ownerId, transaction);
      convertedTransactionIds.add(transaction.id);
    }
    await _writeMarker(ownerId, await _legacyTransactions(ownerId));
    return Set<String>.unmodifiable(convertedTransactionIds);
  }

  Future<void> _writeCarryForwardSource(
    String ownerId,
    _LegacyAvatarTransaction transaction,
  ) async {
    final source = const AvatarLegacyCarryForwardContract()
        .issue(
          transactionId: transaction.id,
          idempotencyKey: transaction.idempotencyKey,
          transactionType: transaction.transactionType,
          amount: transaction.amount,
          itemId: transaction.itemId!,
          catalogVersion: transaction.catalogVersion,
          occurredAtUtcMs: transaction.occurredAtUtcMs,
        )
        .sourceEventId;
    final changed =
        await (database.update(database.rewardTransactions)..where(
              (row) =>
                  row.id.equals(transaction.id) &
                  row.ownerId.equals(ownerId) &
                  row.sourceEventId.isNull(),
            ))
            .write(
              db.RewardTransactionsCompanion(sourceEventId: Value(source)),
            );
    if (changed != 1) {
      throw StateError('avatar carry-forward transaction changed');
    }
  }

  Future<void> _requireMarkerMatchesRows(
    String ownerId,
    _AvatarCutoverMarker marker,
  ) async {
    _requireMarkerMatches(marker, await _legacyTransactions(ownerId));
  }

  void _requireMarkerMatches(
    _AvatarCutoverMarker marker,
    List<_LegacyAvatarTransaction> rows,
  ) {
    if (marker.isQuarantined) {
      throw StateError('avatar cutover remains quarantined');
    }
    if (marker.establishedAtUtcMs >=
            AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs &&
        rows.any((row) => row.sourceEventId == null)) {
      throw StateError('late avatar cutover contains raw catalog-v1 rows');
    }
    if (marker.transactionCount != rows.length ||
        marker.transactionDigest != _digest(rows)) {
      throw StateError('catalog-v1 avatar set crossed avatar cutover');
    }
  }

  Future<void> _writeMarker(
    String ownerId,
    List<_LegacyAvatarTransaction> transactions,
  ) async {
    for (final transaction in transactions) {
      _requireLegacyTransaction(transaction);
    }
    final marker = await _readMarker(ownerId);
    if (marker == null) throw StateError('avatar cutover is unavailable');
    if ((marker.isQuarantined ||
            marker.establishedAtUtcMs >=
                AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs) &&
        transactions.any((row) => row.sourceEventId == null)) {
      throw StateError(
        'avatar cutover cannot admit unverified raw catalog-v1 rows',
      );
    }
    final updated =
        await (database.update(database.eventsV2)..where(
              (row) =>
                  row.eventId.equals(_cutoverId(ownerId)) &
                  row.ownerId.equals(ownerId) &
                  row.eventType.equals(eventType),
            ))
            .write(
              db.EventsV2Companion(
                payloadJson: Value(
                  _payload(ownerId, transactions, marker.establishedAtUtcMs),
                ),
              ),
            );
    if (updated != 1) throw StateError('avatar cutover update failed');
  }

  String _payload(
    String ownerId,
    List<_LegacyAvatarTransaction> transactions,
    int establishedAtUtcMs, {
    String? quarantineProvenanceDigest,
  }) => jsonEncode(<String, Object?>{
    'ownerId': ownerId,
    'cutoverVersion': cutoverVersion,
    'progressionPolicyVersion': grandfatheredProgressionPolicyVersion,
    'legacyCatalogVersion': grandfatheredCatalogVersion,
    'activeCatalogVersion': activatedCatalogVersion,
    'legacyV1CutoverUtcMs':
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs,
    'establishedAtUtcMs': establishedAtUtcMs,
    if (quarantineProvenanceDigest != null) ...{
      'state': 'quarantined',
      'reasonCode': _quarantineReason,
      'quarantineProvenanceDigest': quarantineProvenanceDigest,
    } else ...{
      'grandfatheredTransactionCount': transactions.length,
      'grandfatheredTransactionDigest': _digest(transactions),
    },
  });

  String _digest(List<_LegacyAvatarTransaction> transactions) {
    final sorted = [...transactions]
      ..sort((left, right) => left.id.compareTo(right.id));
    final canonical = StringBuffer();
    for (final row in sorted) {
      canonical
        ..write(row.id)
        ..write('\u0000')
        ..write(row.idempotencyKey)
        ..write('\u0000')
        ..write(row.transactionType)
        ..write('\u0000')
        ..write(row.amount)
        ..write('\u0000')
        ..write(row.itemId)
        ..write('\u0000')
        ..write(row.catalogVersion)
        ..write('\u0000')
        ..write(row.sourceEventId)
        ..write('\u0000')
        ..write(row.occurredAtUtcMs)
        ..write('\n');
    }
    return sha256.convert(utf8.encode(canonical.toString())).toString();
  }

  static String _cutoverId(String ownerId) =>
      'avatar-progression-cutover:$ownerId:v$cutoverVersion';

  static String _requiredIdentifier(String value, String name) {
    if (value.isEmpty || value.trim() != value || value.runes.length > 256) {
      throw ArgumentError.value(value, name);
    }
    return value;
  }

  static DateTime _requiredUtc(DateTime value) {
    if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(value, 'nowUtc', 'must be non-negative UTC');
    }
    return value;
  }

  static DateTime _systemNowUtc() => DateTime.now().toUtc();
}

final class _AvatarCutoverMarker {
  const _AvatarCutoverMarker({
    required this.establishedAtUtcMs,
    required this.transactionCount,
    required this.transactionDigest,
    this.quarantineProvenanceDigest,
  });

  final int establishedAtUtcMs;
  final int? transactionCount;
  final String? transactionDigest;
  final String? quarantineProvenanceDigest;

  bool get isQuarantined => quarantineProvenanceDigest != null;
}

final class _LegacyAvatarTransaction {
  const _LegacyAvatarTransaction({
    required this.id,
    required this.idempotencyKey,
    required this.transactionType,
    required this.amount,
    required this.itemId,
    required this.catalogVersion,
    required this.sourceEventId,
    required this.occurredAtUtcMs,
  });

  final String id;
  final String idempotencyKey;
  final String transactionType;
  final int amount;
  final String? itemId;
  final int catalogVersion;
  final String? sourceEventId;
  final int occurredAtUtcMs;

  @override
  bool operator ==(Object other) =>
      other is _LegacyAvatarTransaction &&
      id == other.id &&
      idempotencyKey == other.idempotencyKey &&
      transactionType == other.transactionType &&
      amount == other.amount &&
      itemId == other.itemId &&
      catalogVersion == other.catalogVersion &&
      sourceEventId == other.sourceEventId &&
      occurredAtUtcMs == other.occurredAtUtcMs;

  @override
  int get hashCode => Object.hash(
    id,
    idempotencyKey,
    transactionType,
    amount,
    itemId,
    catalogVersion,
    sourceEventId,
    occurredAtUtcMs,
  );
}
