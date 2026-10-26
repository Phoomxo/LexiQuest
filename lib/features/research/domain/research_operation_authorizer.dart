import 'dart:convert';
import 'dart:typed_data';

import 'research_trusted_time.dart';

enum ResearchOperation {
  collect('collect'),
  export('export'),
  upload('upload');

  const ResearchOperation(this.wireName);

  final String wireName;
}

abstract interface class ResearchOperationAuthorizer {
  Future<bool> authorize({
    required String ownerId,
    required ResearchOperation operation,
  });
}

final class DenyAllResearchOperationAuthorizer
    implements ResearchOperationAuthorizer {
  const DenyAllResearchOperationAuthorizer();

  @override
  Future<bool> authorize({
    required String ownerId,
    required ResearchOperation operation,
  }) async => false;
}

final class ResearchPermit {
  ResearchPermit({
    required this.formatVersion,
    required this.permitId,
    required this.issuerId,
    required this.issuerKeyId,
    required this.signatureAlgorithm,
    required this.ownerId,
    required this.operation,
    required this.assignmentId,
    required this.assignmentRevision,
    required this.protocolId,
    required this.protocolRevision,
    required this.instrumentId,
    required this.instrumentRevision,
    required this.revision,
    required DateTime issuedAtUtc,
    required DateTime expiresAtUtc,
    required List<int> signature,
  }) : issuedAtUtc = issuedAtUtc.toUtc(),
       expiresAtUtc = expiresAtUtc.toUtc(),
       _signature = Uint8List.fromList(signature);

  final int formatVersion;
  final String permitId;
  final String issuerId;
  final String issuerKeyId;
  final String signatureAlgorithm;
  final String ownerId;
  final ResearchOperation operation;
  final String assignmentId;
  final int assignmentRevision;
  final String protocolId;
  final int protocolRevision;
  final String instrumentId;
  final int instrumentRevision;
  final int revision;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;
  final Uint8List _signature;

  Uint8List get signature => Uint8List.fromList(_signature);

  Uint8List signedPayload() => Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object>{
        'formatVersion': formatVersion,
        'permitId': permitId,
        'issuerId': issuerId,
        'issuerKeyId': issuerKeyId,
        'signatureAlgorithm': signatureAlgorithm,
        'ownerId': ownerId,
        'operation': operation.wireName,
        'assignmentId': assignmentId,
        'assignmentRevision': assignmentRevision,
        'protocolId': protocolId,
        'protocolRevision': protocolRevision,
        'instrumentId': instrumentId,
        'instrumentRevision': instrumentRevision,
        'revision': revision,
        'issuedAtUtcMs': issuedAtUtc.millisecondsSinceEpoch,
        'expiresAtUtcMs': expiresAtUtc.millisecondsSinceEpoch,
      }),
    ),
  );
}

final class ResearchPermitRequirements {
  const ResearchPermitRequirements({
    required this.supportedFormatVersion,
    required this.trustedIssuerId,
    required this.trustedIssuerKeyId,
    required this.signatureAlgorithm,
    required this.assignmentId,
    required this.assignmentRevision,
    required this.protocolId,
    required this.protocolRevision,
    required this.instrumentId,
    required this.instrumentRevision,
  });

  final int supportedFormatVersion;
  final String trustedIssuerId;
  final String trustedIssuerKeyId;
  final String signatureAlgorithm;
  final String assignmentId;
  final int assignmentRevision;
  final String protocolId;
  final int protocolRevision;
  final String instrumentId;
  final int instrumentRevision;
}

final class ResearchPermitState {
  const ResearchPermitState({
    required this.currentRevision,
    required this.revoked,
  });

  final int currentRevision;
  final bool revoked;
}

abstract interface class ResearchPermitSource {
  Future<ResearchPermit?> loadPermit({
    required String ownerId,
    required ResearchOperation operation,
  });
}

abstract interface class ResearchPermitStateSource {
  Future<ResearchPermitState?> loadState({required String permitId});
}

abstract interface class ResearchPermitSignatureVerifier {
  Future<bool> verify({
    required String algorithm,
    required String issuerKeyId,
    required Uint8List message,
    required Uint8List signature,
  });
}

final class SignedPermitResearchOperationAuthorizer
    implements ResearchOperationAuthorizer {
  SignedPermitResearchOperationAuthorizer({
    required this.permits,
    required this.states,
    required this.verifier,
    required this.requirements,
    this.nowUtc,
    this.trustedTime,
  }) {
    if ((nowUtc == null) == (trustedTime == null)) {
      throw ArgumentError('Exactly one research clock authority is required.');
    }
  }

  final ResearchPermitSource permits;
  final ResearchPermitStateSource states;
  final ResearchPermitSignatureVerifier verifier;
  final ResearchPermitRequirements requirements;
  final DateTime Function()? nowUtc;
  final ResearchTrustedTimeSource? trustedTime;

  @override
  Future<bool> authorize({
    required String ownerId,
    required ResearchOperation operation,
  }) async {
    try {
      final now = await _trustedNowUtc();
      if (now == null) return false;
      final permit = await permits.loadPermit(
        ownerId: ownerId,
        operation: operation,
      );
      if (permit == null || !_matches(permit, ownerId, operation, now)) {
        return false;
      }
      if (!await verifier.verify(
        algorithm: permit.signatureAlgorithm,
        issuerKeyId: permit.issuerKeyId,
        message: permit.signedPayload(),
        signature: permit.signature,
      )) {
        return false;
      }
      final state = await states.loadState(permitId: permit.permitId);
      return state != null &&
          !state.revoked &&
          state.currentRevision > 0 &&
          state.currentRevision == permit.revision;
    } catch (_) {
      return false;
    }
  }

  bool _matches(
    ResearchPermit permit,
    String ownerId,
    ResearchOperation operation,
    DateTime now,
  ) {
    final textValues = <String>[
      permit.permitId,
      permit.issuerId,
      permit.issuerKeyId,
      permit.signatureAlgorithm,
      permit.ownerId,
      permit.assignmentId,
      permit.protocolId,
      permit.instrumentId,
      requirements.trustedIssuerId,
      requirements.trustedIssuerKeyId,
      requirements.signatureAlgorithm,
      requirements.assignmentId,
      requirements.protocolId,
      requirements.instrumentId,
    ];
    if (textValues.any((value) => value.trim().isEmpty)) return false;
    if (permit.formatVersion <= 0 ||
        permit.revision <= 0 ||
        permit.assignmentRevision <= 0 ||
        permit.protocolRevision <= 0 ||
        permit.instrumentRevision <= 0 ||
        requirements.supportedFormatVersion <= 0 ||
        requirements.assignmentRevision <= 0 ||
        requirements.protocolRevision <= 0 ||
        requirements.instrumentRevision <= 0 ||
        permit._signature.isEmpty) {
      return false;
    }
    if (permit.formatVersion != requirements.supportedFormatVersion ||
        permit.issuerId != requirements.trustedIssuerId ||
        permit.issuerKeyId != requirements.trustedIssuerKeyId ||
        permit.signatureAlgorithm != requirements.signatureAlgorithm ||
        permit.ownerId != ownerId ||
        permit.operation != operation ||
        permit.assignmentId != requirements.assignmentId ||
        permit.assignmentRevision != requirements.assignmentRevision ||
        permit.protocolId != requirements.protocolId ||
        permit.protocolRevision != requirements.protocolRevision ||
        permit.instrumentId != requirements.instrumentId ||
        permit.instrumentRevision != requirements.instrumentRevision) {
      return false;
    }
    return permit.issuedAtUtc.isBefore(permit.expiresAtUtc) &&
        !permit.issuedAtUtc.isAfter(now) &&
        permit.expiresAtUtc.isAfter(now);
  }

  Future<DateTime?> _trustedNowUtc() async {
    final source = trustedTime;
    if (source == null) return nowUtc!().toUtc();
    final reading = await source.read();
    return reading != null && reading.isFresh ? reading.effectiveNowUtc : null;
  }
}
