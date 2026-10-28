import 'motivation_instrument.dart';

/// Explicit deployment inputs. This object is not an ethics approval and ships
/// with no questionnaire, issuer or participant enrollment by default.
final class MotivationStudyProtocol {
  MotivationStudyProtocol({
    required this.protocolId,
    required this.protocolVersion,
    required this.consentVersion,
    required this.experimentId,
    required this.experimentVersion,
    required this.instrument,
    required String approvedInstrumentChecksum,
    required this.appVersion,
    required this.buildId,
    required this.contentRevision,
    required this.evidencePolicyVersion,
    required this.catalogVersion,
  }) {
    for (final value in [
      protocolId,
      protocolVersion,
      experimentId,
      appVersion,
      buildId,
      contentRevision,
      evidencePolicyVersion,
      catalogVersion,
    ]) {
      requireResearchCode(value);
    }
    if (consentVersion <= 0 ||
        experimentVersion <= 0 ||
        instrument.checksumSha256 != approvedInstrumentChecksum) {
      throw const FormatException(
        'Invalid version or unapproved instrument checksum',
      );
    }
  }
  final String protocolId;
  final String protocolVersion;
  final int consentVersion;
  final String experimentId;
  final int experimentVersion;
  final MotivationInstrument instrument;
  final String appVersion;
  final String buildId;
  final String contentRevision;
  final String evidencePolicyVersion;
  final String catalogVersion;
}

void requireResearchCode(String value) {
  if (value.isEmpty ||
      value.length > 128 ||
      RegExp(r'[^A-Za-z0-9_.:\-]').hasMatch(value)) {
    throw const FormatException('Expected a bounded research catalog code');
  }
}

void requireResearchUtc(DateTime value) {
  if (!value.isUtc ||
      value.millisecondsSinceEpoch < 0 ||
      value.microsecondsSinceEpoch % 1000 != 0) {
    throw const FormatException('Expected UTC milliseconds');
  }
}
