import 'dart:typed_data';

import 'motivation_study_protocol.dart';
import 'research_operation_authorizer.dart';
import 'research_participation_permit.dart';

final class ResearchAuthorityBinding {
  ResearchAuthorityBinding({
    required this.ownerId,
    required this.authSubjectId,
    required this.generation,
  }) {
    requireResearchCode(ownerId);
    requireResearchCode(authSubjectId);
    if (generation < 0) throw const FormatException('Invalid auth generation');
  }

  final String ownerId;
  final String authSubjectId;

  /// Must advance across every auth/owner transition, including an A-B-A cycle.
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is ResearchAuthorityBinding &&
      ownerId == other.ownerId &&
      authSubjectId == other.authSubjectId &&
      generation == other.generation;

  @override
  int get hashCode => Object.hash(ownerId, authSubjectId, generation);

  @override
  String toString() => 'ResearchAuthorityBinding';
}

final class ResearchAuthorityScope {
  ResearchAuthorityScope({
    required this.binding,
    required this.requirements,
    required this.protocolVersion,
    required this.consentVersion,
  }) {
    requireResearchCode(protocolVersion);
    if (consentVersion < 1) {
      throw const FormatException('Invalid consent version');
    }
  }

  final ResearchAuthorityBinding binding;
  final ResearchPermitRequirements requirements;
  final String protocolVersion;
  final int consentVersion;

  List<Object> get _pins => [
    requirements.supportedFormatVersion,
    requirements.trustedIssuerId,
    requirements.trustedIssuerKeyId,
    requirements.signatureAlgorithm,
    requirements.assignmentId,
    requirements.assignmentRevision,
    requirements.protocolId,
    requirements.protocolRevision,
    requirements.instrumentId,
    requirements.instrumentRevision,
  ];

  @override
  bool operator ==(Object other) {
    if (other is! ResearchAuthorityScope ||
        binding != other.binding ||
        protocolVersion != other.protocolVersion ||
        consentVersion != other.consentVersion) {
      return false;
    }
    final pins = _pins;
    final otherPins = other._pins;
    for (var index = 0; index < pins.length; index++) {
      if (pins[index] != otherPins[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    binding,
    protocolVersion,
    consentVersion,
    Object.hashAll(_pins),
  );

  @override
  String toString() => 'ResearchAuthorityScope';
}

final class ResearchAuthorityRefreshRequest {
  const ResearchAuthorityRefreshRequest({
    required this.scope,
    required this.requestId,
    required this.clockSessionId,
    required this.monotonicEpoch,
    required this.startedAtMonotonic,
    required this.monotonicElapsed,
  });

  final ResearchAuthorityScope scope;
  final String requestId;
  final String clockSessionId;
  final int monotonicEpoch;
  final Duration startedAtMonotonic;
  final Duration Function() monotonicElapsed;
}

final class ResearchAuthorityReceipt {
  const ResearchAuthorityReceipt({
    required this.ownerId,
    required this.receiptId,
    required this.kind,
    required this.revision,
    required this.active,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
    this.consentVersion,
    this.decidedAtUtc,
  });

  final String ownerId;
  final String receiptId;
  final ResearchReceiptKind kind;
  final int revision;
  final bool active;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;
  final int? consentVersion;
  final DateTime? decidedAtUtc;
}

/// Input from the explicit trusted gateway, not an independently verified proof.
/// There is deliberately no JSON/signature protocol or production issuer here.
final class ServerAttestedResearchAuthorityPacket {
  ServerAttestedResearchAuthorityPacket({
    required this.scope,
    required this.requestId,
    required this.clockSessionId,
    required this.monotonicEpoch,
    required this.snapshotRevision,
    required this.anchorUtc,
    required this.ageAtObservation,
    required this.observedAtMonotonic,
    required this.validUntilUtc,
    required this.maximumAge,
    required List<List<int>> operationDocuments,
    required Map<String, ResearchPermitState> operationStates,
    required List<String> participationDocuments,
    required List<ResearchAuthorityReceipt> receipts,
  }) : _operationDocuments = [
         for (final bytes in operationDocuments) _copyBytes(bytes),
       ],
       operationStates = Map.unmodifiable(operationStates),
       participationDocuments = List.unmodifiable(participationDocuments),
       receipts = List.unmodifiable(receipts);

  final ResearchAuthorityScope scope;
  final String requestId;
  final String clockSessionId;
  final int monotonicEpoch;
  final int snapshotRevision;
  final DateTime anchorUtc;
  final Duration ageAtObservation;
  final Duration observedAtMonotonic;
  final DateTime validUntilUtc;
  final Duration maximumAge;
  final List<Uint8List> _operationDocuments;
  final Map<String, ResearchPermitState> operationStates;
  final List<String> participationDocuments;
  final List<ResearchAuthorityReceipt> receipts;

  List<Uint8List> get operationDocuments => [
    for (final bytes in _operationDocuments) Uint8List.fromList(bytes),
  ];

  @override
  String toString() => 'ServerAttestedResearchAuthorityPacket';
}

/// TRUST BOUNDARY: implementations must authenticate independent CURRENT server
/// state, bind it to this request/auth scope, and prove the UTC/monotonic mapping
/// and freshness lease. A submitted permit, cached SDK document, wall clock, or
/// a locally asserted boolean cannot establish that contract.
///
/// No production implementation is supplied. Issuer/current-state/freshness
/// artifacts remain external dependencies. This port is invoked only by an
/// explicit refresh outside SQLite transactions, never by the five local reads.
abstract interface class ResearchAuthorityGateway {
  Future<ServerAttestedResearchAuthorityPacket?> fetchCurrent(
    ResearchAuthorityRefreshRequest request,
  );
}

Uint8List _copyBytes(List<int> bytes) {
  if (bytes.length > 16384 || bytes.any((byte) => byte < 0 || byte > 255)) {
    throw const FormatException('Invalid authority document bytes');
  }
  return Uint8List.fromList(bytes);
}
