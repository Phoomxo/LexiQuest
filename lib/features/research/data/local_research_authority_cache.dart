import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../identity/data/drift_owner_write_coordinator.dart';
import '../application/research_participation_permit_validator.dart';
import '../domain/ed25519_research_permit_signature_verifier.dart';
import '../domain/experiment_assignment_admission.dart';
import '../domain/motivation_study_protocol.dart';
import '../domain/research_authority_snapshot.dart';
import '../domain/research_operation_authorizer.dart';
import '../domain/research_participation_permit.dart';
import '../domain/research_permit_document.dart';
import '../domain/research_permit_json_codec.dart';
import '../domain/research_trusted_time.dart';
import 'research_p256_signature_verifier.dart';

/// Refresh is the only installation boundary. All five authority reads below
/// consult memory and the monotonic clock, never SQLite or the gateway.
/// The caller must suspend on every unproven lifecycle/auth interval; resuming
/// never restores a prior lease. No production gateway or rollout is supplied.
final class LocalResearchAuthorityCache
    implements
        ResearchPermitSource,
        ResearchPermitStateSource,
        ResearchParticipationDocumentSource,
        ResearchReceiptAuthority,
        ResearchTrustedTimeSource {
  LocalResearchAuthorityCache({
    required this.ownerWrites,
    required this.currentScope,
    required this.gateway,
    required this.operationSignatures,
    required this.participationSignatures,
    required this.generateRequestId,
    required this.maximumAcceptedAge,
    required bool initiallyForeground,
    Duration Function()? monotonicElapsed,
  }) : _foreground = initiallyForeground {
    if (maximumAcceptedAge <= Duration.zero) {
      throw ArgumentError('A positive authority freshness limit is required');
    }
    _stopwatch.start();
    _monotonicElapsed = monotonicElapsed ?? (() => _stopwatch.elapsed);
  }

  final DriftOwnerWriteCoordinator ownerWrites;
  final ResearchAuthorityScope? Function() currentScope;
  final ResearchAuthorityGateway gateway;
  final Ed25519ResearchPermitSignatureVerifier operationSignatures;
  final ResearchP256SignatureVerifier participationSignatures;
  final String Function() generateRequestId;
  final Duration maximumAcceptedAge;
  final _stopwatch = Stopwatch();
  final _clockSessionId = const Uuid().v4();
  late final Duration Function() _monotonicElapsed;
  final _versions = <_FactKey, _FactVersion>{};
  _VerifiedAuthoritySnapshot? _snapshot;
  Duration? _lastElapsed;
  int _epoch = 0;
  int _refreshGeneration = 0;
  bool _foreground;
  bool _disposed = false;

  int get readGeneration => _refreshGeneration;

  ResearchAuthorityReceipt? inspectReceipt({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
  }) {
    final current = _current();
    return current?.packet.scope.binding.ownerId == ownerId
        ? current?.receipts[(receiptId, kind)]
        : null;
  }

  void invalidate() {
    _epoch++;
    _refreshGeneration++;
    _snapshot = null;
  }

  void suspend() {
    _foreground = false;
    invalidate();
  }

  void resume() {
    invalidate();
    _foreground = true;
  }

  void dispose() {
    _disposed = true;
    suspend();
    _stopwatch.stop();
  }

  /// The configured gateway attests current server state. We additionally
  /// verify every signed document and all local scope/freshness/revision facts.
  /// An unsuccessful/newer refresh cannot fall back to a prior grant.
  Future<bool> refresh() async {
    final generation = ++_refreshGeneration;
    _snapshot = null;
    try {
      if (_disposed || !_foreground) return false;
      if (await ownerWrites.hasAmbientTransaction()) return false;
      final scope = currentScope();
      if (scope == null) return false;
      final requestId = generateRequestId();
      requireResearchCode(requestId);
      final request = ResearchAuthorityRefreshRequest(
        scope: scope,
        requestId: requestId,
        clockSessionId: _clockSessionId,
        monotonicEpoch: _epoch,
        startedAtMonotonic: _elapsed(),
        monotonicElapsed: _elapsed,
      );
      final before = await _localBinding(scope);
      if (before == null || !_pending(request, generation)) return false;
      final packet = await gateway.fetchCurrent(request);
      if (packet == null || !_pending(request, generation)) return false;
      final verified = await _verify(packet, request, before);
      if (!_pending(request, generation)) return false;
      final after = await _localBinding(scope);
      if (after == null ||
          jsonEncode(before) != jsonEncode(after) ||
          !_pending(request, generation) ||
          !_time(packet).isFresh) {
        return false;
      }
      _versions.addAll(verified.versions);
      _snapshot = verified;
      return true;
    } on Object {
      return false;
    }
  }

  bool _pending(ResearchAuthorityRefreshRequest request, int generation) =>
      !_disposed &&
      _foreground &&
      generation == _refreshGeneration &&
      request.monotonicEpoch == _epoch &&
      currentScope() == request.scope;

  Future<Map<String, Object?>?> _localBinding(
    ResearchAuthorityScope scope,
  ) async {
    if (await ownerWrites.inspect() != null) return null;
    final rows = await ownerWrites.database
        .customSelect(
          'SELECT o.id, o.firebase_uid, o.account_state, o.created_at_utc_ms, '
          'o.upgraded_at_utc_ms, c.id AS consent_id, c.consent_version, '
          'c.consent_state, c.decided_at_utc_ms, c.withdrawn_at_utc_ms '
          'FROM local_owners o LEFT JOIN research_consents c '
          'ON c.owner_id = o.id AND c.consent_version = ? '
          'WHERE o.is_active = 1 ORDER BY o.id LIMIT 2',
          variables: [Variable<int>(scope.consentVersion)],
        )
        .get();
    if (rows.length != 1) return null;
    final row = rows.single.data;
    if (row['id'] != scope.binding.ownerId ||
        row['firebase_uid'] != scope.binding.authSubjectId ||
        row['account_state'] != 'firebaseBound' ||
        row['consent_version'] != scope.consentVersion ||
        row['consent_state'] != 'accepted' ||
        row['withdrawn_at_utc_ms'] != null ||
        row['decided_at_utc_ms'] is! int ||
        (row['decided_at_utc_ms']! as int) < 0) {
      return null;
    }
    return row;
  }

  Future<_VerifiedAuthoritySnapshot> _verify(
    ServerAttestedResearchAuthorityPacket packet,
    ResearchAuthorityRefreshRequest request,
    Map<String, Object?> local,
  ) async {
    if (packet.scope != request.scope ||
        packet.requestId != request.requestId ||
        packet.clockSessionId != request.clockSessionId ||
        packet.clockSessionId != _clockSessionId ||
        packet.monotonicEpoch != request.monotonicEpoch ||
        packet.observedAtMonotonic < request.startedAtMonotonic ||
        packet.snapshotRevision < 1 ||
        !_time(packet).isFresh) {
      throw const FormatException('Unproven authority packet');
    }
    final scope = request.scope;
    final pins = scope.requirements;
    final now = DateTime.fromMillisecondsSinceEpoch(
      _time(packet).effectiveNowUtc.millisecondsSinceEpoch,
      isUtc: true,
    );
    if ((local['decided_at_utc_ms']! as int) > now.millisecondsSinceEpoch) {
      throw const FormatException('Future consent');
    }
    final operations = <ResearchOperation, ResearchPermit>{};
    final ids = <String>{};
    final staged = <_FactKey, _FactVersion>{};
    final operationDocuments = packet.operationDocuments;
    if (operationDocuments.length > ResearchOperation.values.length ||
        packet.operationStates.length != operationDocuments.length ||
        packet.participationDocuments.length > 64 ||
        packet.receipts.length > 192) {
      throw const FormatException('Unbounded authority packet');
    }
    for (final document in operationDocuments) {
      if (document.length > 16384) throw const FormatException();
      final permit = const ResearchPermitJsonCodec().decode(document);
      for (final value in [
        permit.permitId,
        permit.issuerId,
        permit.issuerKeyId,
        permit.ownerId,
        permit.assignmentId,
        permit.protocolId,
        permit.instrumentId,
      ]) {
        requireResearchCode(value);
      }
      if (!ids.add(permit.permitId) ||
          operations.containsKey(permit.operation) ||
          permit.ownerId != scope.binding.ownerId ||
          permit.formatVersion != pins.supportedFormatVersion ||
          permit.issuerId != pins.trustedIssuerId ||
          permit.issuerKeyId != pins.trustedIssuerKeyId ||
          permit.signatureAlgorithm !=
              Ed25519ResearchPermitSignatureVerifier.algorithm ||
          permit.signatureAlgorithm != pins.signatureAlgorithm ||
          permit.assignmentId != pins.assignmentId ||
          permit.assignmentRevision != pins.assignmentRevision ||
          permit.protocolId != pins.protocolId ||
          permit.protocolRevision != pins.protocolRevision ||
          permit.instrumentId != pins.instrumentId ||
          permit.instrumentRevision != pins.instrumentRevision ||
          permit.revision < 1 ||
          !_date(permit.issuedAtUtc) ||
          !_date(permit.expiresAtUtc) ||
          !permit.issuedAtUtc.isBefore(permit.expiresAtUtc) ||
          !await operationSignatures.verify(
            algorithm: permit.signatureAlgorithm,
            issuerKeyId: permit.issuerKeyId,
            message: permit.signedPayload(),
            signature: permit.signature,
          )) {
        throw const FormatException('Invalid operation authority');
      }
      final state = packet.operationStates[permit.permitId];
      if (state == null || state.currentRevision < permit.revision) {
        throw const FormatException('Missing current operation state');
      }
      operations[permit.operation] = permit;
      _stage(
        staged,
        scope,
        'operation',
        permit.permitId,
        permit.revision,
        utf8.decode(document),
        false,
      );
      _stage(
        staged,
        scope,
        'state',
        permit.permitId,
        state.currentRevision,
        '${state.currentRevision}:${state.revoked}',
        state.revoked,
      );
    }
    final documents = <String, ResearchParticipationPermit>{};
    final validator = ResearchParticipationPermitValidator(
      protocolId: pins.protocolId,
      protocolVersion: scope.protocolVersion,
      signatures: participationSignatures,
      receipts: this,
    );
    for (final document in packet.participationDocuments) {
      final permit = decodeResearchPermitDocument(document);
      if (documents.containsKey(permit.id) ||
          validator.validateAuthenticity(
                permit,
                expectedOwnerId: scope.binding.ownerId,
                expectedAssignmentId: pins.assignmentId,
                evaluatedAtUtc: now,
              ) !=
              ResearchPermitDenialReason.none) {
        throw const FormatException('Invalid participation authority');
      }
      documents[permit.id] = permit;
      _stage(
        staged,
        scope,
        'participation',
        permit.id,
        permit.cloudRevision,
        '${permit.canonicalPayload()}:${permit.payloadSha256}:${permit.signature}',
        permit.isDeleted || permit.revokedAtUtc != null,
      );
    }
    final receipts =
        <(String, ResearchReceiptKind), ResearchAuthorityReceipt>{};
    for (final receipt in packet.receipts) {
      requireResearchCode(receipt.receiptId);
      final key = (receipt.receiptId, receipt.kind);
      if (receipt.ownerId != scope.binding.ownerId ||
          receipts.containsKey(key) ||
          receipt.revision < 1 ||
          !_date(receipt.issuedAtUtc) ||
          !_date(receipt.expiresAtUtc) ||
          !receipt.issuedAtUtc.isBefore(receipt.expiresAtUtc) ||
          (receipt.kind == ResearchReceiptKind.consent
              ? receipt.consentVersion != scope.consentVersion ||
                    receipt.decidedAtUtc?.millisecondsSinceEpoch !=
                        local['decided_at_utc_ms'] ||
                    !_date(receipt.decidedAtUtc!)
              : receipt.consentVersion != null ||
                    receipt.decidedAtUtc != null)) {
        throw const FormatException('Invalid receipt authority');
      }
      receipts[key] = receipt;
      _stage(
        staged,
        scope,
        'receipt:${receipt.kind.name}',
        receipt.receiptId,
        receipt.revision,
        jsonEncode([
          receipt.active,
          receipt.issuedAtUtc.millisecondsSinceEpoch,
          receipt.expiresAtUtc.millisecondsSinceEpoch,
          receipt.consentVersion,
          receipt.decidedAtUtc?.millisecondsSinceEpoch,
        ]),
        !receipt.active,
      );
    }
    final ordered = staged.entries.toList()
      ..sort(
        (a, b) =>
            '${a.key.kind}:${a.key.id}'.compareTo('${b.key.kind}:${b.key.id}'),
      );
    _stage(
      staged,
      scope,
      'snapshot',
      scope.protocolVersion,
      packet.snapshotRevision,
      jsonEncode([
        for (final fact in ordered)
          [fact.key.kind, fact.key.id, fact.value.revision, fact.value.digest],
      ]),
      false,
    );
    if (!_time(packet).isFresh) {
      throw const FormatException('Authority expired');
    }
    return _VerifiedAuthoritySnapshot(
      packet,
      operations,
      documents,
      receipts,
      staged,
    );
  }

  void _stage(
    Map<_FactKey, _FactVersion> staged,
    ResearchAuthorityScope scope,
    String kind,
    String id,
    int revision,
    String body,
    bool denied,
  ) {
    final key = (
      owner: scope.binding.ownerId,
      subject: scope.binding.authSubjectId,
      protocol: scope.requirements.protocolId,
      kind: kind,
      id: id,
    );
    final next = _FactVersion(
      revision,
      sha256.convert(utf8.encode(body)).toString(),
      denied,
    );
    final previous = _versions[key];
    if (previous != null &&
        (revision < previous.revision ||
            (revision == previous.revision && next.digest != previous.digest) ||
            (previous.denied && !denied))) {
      throw const FormatException('Authority revision regressed');
    }
    staged[key] = next;
  }

  ResearchTrustedTime _time(ServerAttestedResearchAuthorityPacket packet) {
    final elapsed = _elapsed();
    if (packet.monotonicEpoch != _epoch ||
        packet.observedAtMonotonic.isNegative ||
        packet.observedAtMonotonic > elapsed ||
        packet.ageAtObservation.isNegative ||
        packet.maximumAge <= Duration.zero ||
        packet.maximumAge > maximumAcceptedAge ||
        !_date(packet.anchorUtc) ||
        !_date(packet.validUntilUtc)) {
      throw const FormatException('Unproven monotonic authority time');
    }
    return ResearchTrustedTime(
      anchorUtc: packet.anchorUtc,
      validUntilUtc: packet.validUntilUtc,
      age: packet.ageAtObservation + elapsed - packet.observedAtMonotonic,
      maximumAge: packet.maximumAge,
    );
  }

  Duration _elapsed() {
    final elapsed = _monotonicElapsed();
    if (elapsed.isNegative ||
        (_lastElapsed != null && elapsed < _lastElapsed!)) {
      invalidate();
      throw const FormatException('Monotonic clock regressed');
    }
    _lastElapsed = elapsed;
    return elapsed;
  }

  _VerifiedAuthoritySnapshot? _current() {
    try {
      final snapshot = _snapshot;
      if (_disposed ||
          !_foreground ||
          snapshot == null ||
          snapshot.packet.scope != currentScope() ||
          !_time(snapshot.packet).isFresh) {
        return null;
      }
      return snapshot;
    } on Object {
      return null;
    }
  }

  @override
  Future<ResearchPermit?> loadPermit({
    required String ownerId,
    required ResearchOperation operation,
  }) async {
    final current = _current();
    return current?.packet.scope.binding.ownerId == ownerId
        ? current?.operations[operation]
        : null;
  }

  @override
  Future<ResearchPermitState?> loadState({required String permitId}) async =>
      _current()?.packet.operationStates[permitId];

  @override
  Future<ResearchParticipationPermit?> loadCurrent({
    required String ownerId,
    required String permitId,
  }) async {
    final current = _current();
    return current?.packet.scope.binding.ownerId == ownerId
        ? current?.documents[permitId]
        : null;
  }

  @override
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  }) async {
    try {
      final current = _current();
      if (current == null ||
          current.packet.scope.binding.ownerId != ownerId ||
          !_date(evaluatedAtUtc)) {
        return false;
      }
      final receipt = current.receipts[(receiptId, kind)];
      final reading = _time(current.packet);
      final now = reading.effectiveNowUtc;
      return reading.isFresh &&
          receipt != null &&
          receipt.active &&
          !evaluatedAtUtc.isAfter(now) &&
          !evaluatedAtUtc.isBefore(receipt.issuedAtUtc) &&
          evaluatedAtUtc.isBefore(receipt.expiresAtUtc) &&
          now.isBefore(receipt.expiresAtUtc);
    } on Object {
      return false;
    }
  }

  @override
  Future<ResearchTrustedTime?> read() async {
    try {
      final current = _current();
      if (current == null) return null;
      final reading = _time(current.packet);
      if (!reading.isFresh) return null;
      // Existing signed receipts and R3 fact times use canonical milliseconds.
      // Test the full monotonic age first, then expose that precision.
      return ResearchTrustedTime(
        anchorUtc: reading.anchorUtc,
        validUntilUtc: reading.validUntilUtc,
        age: Duration(milliseconds: reading.age.inMilliseconds),
        maximumAge: reading.maximumAge,
      );
    } on Object {
      return null;
    }
  }

  static bool _date(DateTime value) =>
      value.isUtc &&
      value.microsecondsSinceEpoch >= 0 &&
      value.microsecond == 0;
}

typedef _FactKey = ({
  String owner,
  String subject,
  String protocol,
  String kind,
  String id,
});

final class _FactVersion {
  const _FactVersion(this.revision, this.digest, this.denied);
  final int revision;
  final String digest;
  final bool denied;
}

final class _VerifiedAuthoritySnapshot {
  _VerifiedAuthoritySnapshot(
    this.packet,
    Map<ResearchOperation, ResearchPermit> operations,
    Map<String, ResearchParticipationPermit> documents,
    Map<(String, ResearchReceiptKind), ResearchAuthorityReceipt> receipts,
    this.versions,
  ) : operations = Map.unmodifiable(operations),
      documents = Map.unmodifiable(documents),
      receipts = Map.unmodifiable(receipts);
  final ServerAttestedResearchAuthorityPacket packet;
  final Map<ResearchOperation, ResearchPermit> operations;
  final Map<String, ResearchParticipationPermit> documents;
  final Map<(String, ResearchReceiptKind), ResearchAuthorityReceipt> receipts;
  final Map<_FactKey, _FactVersion> versions;
}
