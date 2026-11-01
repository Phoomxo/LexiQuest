import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../consent/domain/research_consent.dart';
import 'research_authority_snapshot.dart';
import 'research_operation_authorizer.dart';

final class SuppliedResearchConsentNotice {
  SuppliedResearchConsentNotice({
    required this.version,
    required this.protocolVersion,
    required this.title,
    required this.body,
  }) {
    if (version < 1 ||
        protocolVersion.isEmpty ||
        protocolVersion.length > 128 ||
        title.trim().isEmpty ||
        title.length > 300 ||
        body.trim().isEmpty ||
        utf8.encode(body).length > 16384) {
      throw const FormatException(
        'A bounded supplied consent notice is required',
      );
    }
  }
  final int version;
  final String protocolVersion;
  final String title;
  final String body;
  String get contentSha256 => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'version': version,
            'protocolVersion': protocolVersion,
            'title': title,
            'body': body,
          }),
        ),
      )
      .toString();
}

enum ResearchTransportFailureCode {
  unavailable,
  invalidResponse,
  accountRequired,
  ownerChanged,
  denied,
  notEnrolled,
  conflict,
  withdrawalPending,
}

final class ResearchTransportException implements Exception {
  const ResearchTransportException(this.code);
  final ResearchTransportFailureCode code;

  @override
  String toString() => 'ResearchTransportException(${code.name})';
}

final class ResearchEnrollmentContext {
  const ResearchEnrollmentContext({
    required this.enrollmentId,
    required this.ownerId,
    required this.authSubjectId,
    required this.consentVersion,
    required this.protocolVersion,
    required this.motivationRequirements,
    required this.assessmentRequirements,
  });

  final String enrollmentId;
  final String ownerId;
  final String authSubjectId;
  final int consentVersion;
  final String protocolVersion;
  final ResearchPermitRequirements motivationRequirements;
  final ResearchPermitRequirements assessmentRequirements;

  ResearchAuthorityScope scope({
    required ResearchAuthorityBinding binding,
    required bool assessment,
  }) {
    if (binding.ownerId != ownerId || binding.authSubjectId != authSubjectId) {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.ownerChanged,
      );
    }
    return ResearchAuthorityScope(
      binding: binding,
      requirements: assessment
          ? assessmentRequirements
          : motivationRequirements,
      protocolVersion: protocolVersion,
      consentVersion: consentVersion,
    );
  }
}

final class ResearchConsentAcknowledgement {
  const ResearchConsentAcknowledgement({
    required this.enrollmentId,
    required this.ownerId,
    required this.version,
    required this.requestId,
    required this.accepted,
    required this.receiptId,
    required this.revision,
    required this.decidedAtUtc,
    required this.withdrawnAtUtc,
  });

  final String enrollmentId;
  final String ownerId;
  final int version;
  final String requestId;
  final bool accepted;
  final String receiptId;
  final int revision;
  final DateTime? decidedAtUtc;
  final DateTime? withdrawnAtUtc;

  ResearchConsentStatus get status => ResearchConsentStatus(
    ownerId: ownerId,
    version: version,
    accepted: accepted,
    decidedAtUtc: decidedAtUtc ?? withdrawnAtUtc,
    withdrawnAtUtc: withdrawnAtUtc,
  );
}

abstract interface class ResearchEnrollmentGateway {
  Future<ResearchEnrollmentContext> loadEnrollment(
    ResearchAuthorityBinding binding, {
    required bool Function() stillCurrent,
  });

  Future<ResearchConsentAcknowledgement> decideConsent({
    required ResearchAuthorityBinding binding,
    required ResearchEnrollmentContext enrollment,
    required bool accepted,
    required String requestId,
    required bool Function() stillCurrent,
  });
}

const maximumStudyUploadBytes = 512 * 1024;

final class StudyUploadRequest {
  StudyUploadRequest({
    required this.motivationScope,
    required this.assessmentScope,
    required this.cycleKey,
    required Uint8List bytes,
  }) : _bytes = Uint8List.fromList(bytes),
       payloadSha256 = sha256.convert(bytes).toString();

  final ResearchAuthorityScope motivationScope;
  final ResearchAuthorityScope assessmentScope;
  final String cycleKey;
  final Uint8List _bytes;
  final String payloadSha256;
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

final class StudyUploadReceipt {
  const StudyUploadReceipt({
    required this.uploadId,
    required this.receiptId,
    required this.payloadSha256,
    required this.acceptedAtUtc,
  });
  final String uploadId;
  final String receiptId;
  final String payloadSha256;
  final DateTime acceptedAtUtc;
}

abstract interface class StudyUploadGateway {
  Future<StudyUploadReceipt> upload(
    StudyUploadRequest request, {
    required bool Function() stillCurrent,
    required Future<void> Function() revalidateBeforeSubmit,
  });
}
