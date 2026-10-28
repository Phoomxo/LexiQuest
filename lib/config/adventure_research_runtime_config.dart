import '../features/research/application/research_participation_permit_validator.dart';
import '../features/research/domain/motivation_study_protocol.dart';
import '../data/local/app_database.dart';

/// No bundled questionnaire, issuer, receipts or permission to enroll. An
/// explicitly provisioned deployment must supply all authorities together.
final class AdventureResearchRuntimeConfig {
  const AdventureResearchRuntimeConfig.off()
    : study = null,
      issuerPublicKeys = const {},
      receipts = null,
      createReceipts = null;
  AdventureResearchRuntimeConfig.configured({
    required MotivationStudyProtocol this.study,
    required Map<String, String> issuerPublicKeys,
    this.receipts,
    this.createReceipts,
  }) : issuerPublicKeys = Map.unmodifiable(issuerPublicKeys) {
    if ((receipts == null) == (createReceipts == null)) {
      throw const FormatException(
        'Supply exactly one research receipt authority',
      );
    }
    if (issuerPublicKeys.isEmpty) {
      throw const FormatException('Research issuer required');
    }
    for (final key in issuerPublicKeys.keys) {
      requireResearchCode(key);
    }
  }
  final MotivationStudyProtocol? study;
  final Map<String, String> issuerPublicKeys;
  final ResearchReceiptAuthority? receipts;

  /// Resolves once against bootstrap's existing connection, never a second DB.
  final ResearchReceiptAuthority Function(AppDatabase database)? createReceipts;
  bool get enabled =>
      study != null &&
      (receipts != null || createReceipts != null) &&
      issuerPublicKeys.isNotEmpty;
}
