import '../../../product/feature_contract/feature_contract_digest.dart';

enum EvidenceClass {
  assessment,
  independentRecall,
  recognition,
  guidedPractice,
  pronunciation,
  exposure,
  recreational,
}

enum EvidenceClassificationSource { declared, legacyInferred }

enum EvidencePolicyRolloutMode { legacy, shadow, enforced }

final class EvidenceContext {
  const EvidenceContext({
    required this.evidenceClass,
    required this.skillId,
    required this.hintLevel,
    required this.policyVersion,
    required this.contentRevision,
    required this.featureContractRevision,
    required this.featureContractHash,
    required this.classificationSource,
    required this.rolloutMode,
    this.protocolId,
    this.protocolVersion,
    this.experimentId,
    this.experimentVersion,
    this.assignmentId,
    this.cohort,
    this.researchConsentVersion,
    this.instrumentId,
    this.instrumentVersion,
    this.formId,
    this.formVersion,
    this.assessmentItemId,
    this.assessmentResponseCode,
    this.scoringRuleVersion,
    this.engagementAllowed = false,
  });

  factory EvidenceContext.forNewEvidence({
    required EvidenceClass evidenceClass,
    required String skillId,
    required int hintLevel,
    required String contentRevision,
    required EvidencePolicyRolloutMode rolloutMode,
    String? protocolId,
    String? protocolVersion,
    String? experimentId,
    int? experimentVersion,
    String? assignmentId,
    String? cohort,
    int? researchConsentVersion,
    String? instrumentId,
    String? instrumentVersion,
    String? formId,
    String? formVersion,
    String? assessmentItemId,
    String? assessmentResponseCode,
    String? scoringRuleVersion,
    bool engagementAllowed = false,
  }) {
    final context = EvidenceContext(
      evidenceClass: evidenceClass,
      skillId: skillId,
      hintLevel: hintLevel,
      policyVersion: currentPolicyVersion,
      contentRevision: contentRevision,
      featureContractRevision: currentFeatureContractIdentity.revision,
      featureContractHash: currentFeatureContractIdentity.semanticHash,
      classificationSource: EvidenceClassificationSource.declared,
      rolloutMode: rolloutMode,
      protocolId: protocolId,
      protocolVersion: protocolVersion,
      experimentId: experimentId,
      experimentVersion: experimentVersion,
      assignmentId: assignmentId,
      cohort: cohort,
      researchConsentVersion: researchConsentVersion,
      instrumentId: instrumentId,
      instrumentVersion: instrumentVersion,
      formId: formId,
      formVersion: formVersion,
      assessmentItemId: assessmentItemId,
      assessmentResponseCode: assessmentResponseCode,
      scoringRuleVersion: scoringRuleVersion,
      engagementAllowed: engagementAllowed,
    );
    context.validate();
    return context;
  }

  factory EvidenceContext.fromJson(Map<String, Object?> json) {
    if (json.length != _jsonKeys.length ||
        !json.keys.every(_jsonKeys.contains)) {
      throw const FormatException('Invalid evidence context schema.');
    }
    final serializedSchemaVersion = _requiredInt(json, 'schemaVersion');
    if (serializedSchemaVersion != schemaVersion) {
      throw FormatException(
        'Unsupported evidence context schema $serializedSchemaVersion.',
      );
    }

    final context = EvidenceContext(
      evidenceClass: _requiredEnum(json, 'evidenceClass', EvidenceClass.values),
      skillId: _requiredString(json, 'skillId'),
      hintLevel: _requiredInt(json, 'hintLevel'),
      policyVersion: _requiredString(json, 'policyVersion'),
      contentRevision: _requiredString(json, 'contentRevision'),
      featureContractRevision: _requiredString(json, 'featureContractRevision'),
      featureContractHash: _requiredString(json, 'featureContractHash'),
      classificationSource: _requiredEnum(
        json,
        'classificationSource',
        EvidenceClassificationSource.values,
      ),
      rolloutMode: _requiredEnum(
        json,
        'rolloutMode',
        EvidencePolicyRolloutMode.values,
      ),
      protocolId: _optionalString(json, 'protocolId'),
      protocolVersion: _optionalString(json, 'protocolVersion'),
      experimentId: _optionalString(json, 'experimentId'),
      experimentVersion: _optionalInt(json, 'experimentVersion'),
      assignmentId: _optionalString(json, 'assignmentId'),
      cohort: _optionalString(json, 'cohort'),
      researchConsentVersion: _optionalInt(json, 'researchConsentVersion'),
      instrumentId: _optionalString(json, 'instrumentId'),
      instrumentVersion: _optionalString(json, 'instrumentVersion'),
      formId: _optionalString(json, 'formId'),
      formVersion: _optionalString(json, 'formVersion'),
      assessmentItemId: _optionalString(json, 'assessmentItemId'),
      assessmentResponseCode: _optionalString(json, 'assessmentResponseCode'),
      scoringRuleVersion: _optionalString(json, 'scoringRuleVersion'),
      engagementAllowed: _requiredBool(json, 'engagementAllowed'),
    );
    context.validate();
    return context;
  }

  static const int schemaVersion = 1;
  static const int maxIdentifierLength = 256;
  static const String currentPolicyVersion = 'learning-evidence-v1';
  static const String legacyPolicyVersion = 'legacy-v1';
  static const String legacyFeatureContractRevision = 'legacy-unversioned';
  static const String legacyFeatureContractHash =
      '0000000000000000000000000000000000000000000000000000000000000000';

  static const Set<String> _jsonKeys = <String>{
    'schemaVersion',
    'evidenceClass',
    'skillId',
    'hintLevel',
    'policyVersion',
    'contentRevision',
    'featureContractRevision',
    'featureContractHash',
    'classificationSource',
    'rolloutMode',
    'protocolId',
    'protocolVersion',
    'experimentId',
    'experimentVersion',
    'assignmentId',
    'cohort',
    'researchConsentVersion',
    'instrumentId',
    'instrumentVersion',
    'formId',
    'formVersion',
    'assessmentItemId',
    'assessmentResponseCode',
    'scoringRuleVersion',
    'engagementAllowed',
  };

  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _assessmentResponseCodePattern = RegExp(
    r'^[a-z0-9][a-z0-9._:-]*$',
  );

  final EvidenceClass evidenceClass;
  final String skillId;
  final int hintLevel;
  final String policyVersion;
  final String contentRevision;
  final String featureContractRevision;
  final String featureContractHash;
  final EvidenceClassificationSource classificationSource;
  final EvidencePolicyRolloutMode rolloutMode;
  final String? protocolId;
  final String? protocolVersion;
  final String? experimentId;
  final int? experimentVersion;
  final String? assignmentId;
  final String? cohort;
  final int? researchConsentVersion;
  final String? instrumentId;
  final String? instrumentVersion;
  final String? formId;
  final String? formVersion;
  final String? assessmentItemId;
  final String? assessmentResponseCode;
  final String? scoringRuleVersion;
  final bool engagementAllowed;

  void validate() {
    _validateIdentifier(skillId, 'skillId');
    _validateIdentifier(policyVersion, 'policyVersion');
    _validateIdentifier(contentRevision, 'contentRevision');
    _validateIdentifier(featureContractRevision, 'featureContractRevision');
    if (hintLevel < 0) {
      throw const FormatException('hintLevel must be nonnegative.');
    }

    for (final entry in <String, String?>{
      'protocolId': protocolId,
      'protocolVersion': protocolVersion,
      'experimentId': experimentId,
      'assignmentId': assignmentId,
      'cohort': cohort,
      'instrumentId': instrumentId,
      'instrumentVersion': instrumentVersion,
      'formId': formId,
      'formVersion': formVersion,
      'assessmentItemId': assessmentItemId,
      'assessmentResponseCode': assessmentResponseCode,
      'scoringRuleVersion': scoringRuleVersion,
    }.entries) {
      final value = entry.value;
      if (value != null) {
        _validateIdentifier(value, entry.key);
      }
    }
    final responseCode = assessmentResponseCode;
    if (responseCode != null &&
        !_assessmentResponseCodePattern.hasMatch(responseCode)) {
      throw const FormatException(
        'assessmentResponseCode must be a controlled code.',
      );
    }

    final experimentVersionValue = experimentVersion;
    if (experimentVersionValue != null && experimentVersionValue <= 0) {
      throw const FormatException('experimentVersion must be positive.');
    }
    final consentVersionValue = researchConsentVersion;
    if (consentVersionValue != null && consentVersionValue <= 0) {
      throw const FormatException('researchConsentVersion must be positive.');
    }

    switch (classificationSource) {
      case EvidenceClassificationSource.declared:
        if (policyVersion != currentPolicyVersion) {
          throw FormatException('Unsupported declared policy $policyVersion.');
        }
        _validateDeclaredFeatureContractIdentity();
      case EvidenceClassificationSource.legacyInferred:
        if (policyVersion != legacyPolicyVersion ||
            rolloutMode != EvidencePolicyRolloutMode.legacy ||
            featureContractRevision != legacyFeatureContractRevision ||
            featureContractHash != legacyFeatureContractHash) {
          throw const FormatException(
            'Invalid legacy-inferred evidence context.',
          );
        }
    }

    if (classificationSource == EvidenceClassificationSource.declared &&
        rolloutMode != EvidencePolicyRolloutMode.legacy) {
      _requirePresent(protocolId, 'protocolId');
      _requirePresent(protocolVersion, 'protocolVersion');
      _requirePresent(experimentId, 'experimentId');
      _requirePositive(experimentVersion, 'experimentVersion');
      _requirePresent(assignmentId, 'assignmentId');
      _requirePresent(cohort, 'cohort');
      _requirePositive(researchConsentVersion, 'researchConsentVersion');
    }

    if (evidenceClass == EvidenceClass.assessment) {
      _requirePresent(instrumentId, 'instrumentId');
      _requirePresent(instrumentVersion, 'instrumentVersion');
      _requirePresent(formId, 'formId');
      _requirePresent(formVersion, 'formVersion');
      _requirePresent(assessmentItemId, 'assessmentItemId');
      _requirePresent(assessmentResponseCode, 'assessmentResponseCode');
      _requirePresent(scoringRuleVersion, 'scoringRuleVersion');
    }
  }

  Map<String, Object?> toJson() {
    validate();
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'schemaVersion': schemaVersion,
      'evidenceClass': evidenceClass.name,
      'skillId': skillId,
      'hintLevel': hintLevel,
      'policyVersion': policyVersion,
      'contentRevision': contentRevision,
      'featureContractRevision': featureContractRevision,
      'featureContractHash': featureContractHash,
      'classificationSource': classificationSource.name,
      'rolloutMode': rolloutMode.name,
      'protocolId': protocolId,
      'protocolVersion': protocolVersion,
      'experimentId': experimentId,
      'experimentVersion': experimentVersion,
      'assignmentId': assignmentId,
      'cohort': cohort,
      'researchConsentVersion': researchConsentVersion,
      'instrumentId': instrumentId,
      'instrumentVersion': instrumentVersion,
      'formId': formId,
      'formVersion': formVersion,
      'assessmentItemId': assessmentItemId,
      'assessmentResponseCode': assessmentResponseCode,
      'scoringRuleVersion': scoringRuleVersion,
      'engagementAllowed': engagementAllowed,
    });
  }

  void _validateDeclaredFeatureContractIdentity() {
    if (!_sha256Pattern.hasMatch(featureContractHash)) {
      throw const FormatException(
        'featureContractHash must be a lowercase SHA-256.',
      );
    }
    final supported = supportedFeatureContractIdentities.any(
      (identity) =>
          identity.revision == featureContractRevision &&
          identity.semanticHash == featureContractHash,
    );
    if (!supported) {
      throw const FormatException('Unsupported feature-contract identity.');
    }
  }

  static void _validateIdentifier(String value, String field) {
    if (value.trim() != value ||
        value.isEmpty ||
        value.runes.length > maxIdentifierLength) {
      throw FormatException('Invalid $field.');
    }
  }

  static void _requirePresent(String? value, String field) {
    if (value == null) {
      throw FormatException('$field is required.');
    }
  }

  static void _requirePositive(int? value, String field) {
    if (value == null || value <= 0) {
      throw FormatException('$field must be positive.');
    }
  }

  static String _requiredString(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! String) {
      throw FormatException('$field must be a string.');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException('$field must be a string or null.');
    }
    return value;
  }

  static int _requiredInt(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! int) {
      throw FormatException('$field must be an integer.');
    }
    return value;
  }

  static int? _optionalInt(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value == null) {
      return null;
    }
    if (value is! int) {
      throw FormatException('$field must be an integer or null.');
    }
    return value;
  }

  static bool _requiredBool(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! bool) {
      throw FormatException('$field must be a boolean.');
    }
    return value;
  }

  static T _requiredEnum<T extends Enum>(
    Map<String, Object?> json,
    String field,
    List<T> values,
  ) {
    final name = _requiredString(json, field);
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }
    throw FormatException('Unknown $field $name.');
  }
}
