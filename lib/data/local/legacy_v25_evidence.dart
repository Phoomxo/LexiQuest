import 'dart:convert';

/// Conservative ordinary-evidence subset from installed revision 00d6c8ea.
bool isCompatibleV25Attempt({
  required String activityType,
  required String promptMode,
  required String evidenceClass,
  required String evidenceContextJson,
}) {
  final quiz =
      const {
        'quiz',
        'sourcePractice',
        'weaknessPractice',
      }.contains(activityType) &&
      promptMode == 'meaningChoice';
  final srs = activityType == 'srsReview' && promptMode == 'srsRecall';
  if ((!quiz && !srs) ||
      evidenceContextJson.length > 16384 ||
      utf8.encode(evidenceContextJson).length > 16384) {
    return false;
  }
  final encoded = evidenceContextJson.trim();
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    if (decoded['classificationSource'] == 'legacyInferred') {
      return evidenceClass == 'independentRecall' &&
          encoded == jsonEncode(_legacyDefault);
    }
    final expectedClass = quiz ? 'recognition' : 'independentRecall';
    final content = decoded['contentRevision'];
    final revision = decoded['featureContractRevision'];
    if (evidenceClass != expectedClass ||
        content is! String ||
        content.isEmpty ||
        content.trim() != content ||
        content.runes.length > 256 ||
        revision is! String ||
        !_declaredIdentities.containsKey(revision)) {
      return false;
    }
    final expected = <String, Object?>{
      ..._legacyDefault,
      'evidenceClass': expectedClass,
      'skillId': quiz ? 'meaning-recall' : 'srs-recall',
      'policyVersion': 'learning-evidence-v1',
      'contentRevision': content,
      'featureContractRevision': revision,
      'featureContractHash': _declaredIdentities[revision],
      'classificationSource': 'declared',
      'engagementAllowed': false,
    };
    // The old writer used this exact toJson order. Equality also rejects
    // duplicate keys and numeric coercion without widening the migration.
    return encoded == jsonEncode(expected);
  } on FormatException {
    return false;
  }
}

/// Reward admission keeps the frozen v25 rule for the old native prompt modes.
bool isV25RewardEvidence({
  required String promptMode,
  required String evidenceClass,
  required String evidenceContextJson,
}) {
  final encoded = evidenceContextJson.trim();
  if (encoded.length > 16384 || evidenceClass == 'assessment') return false;
  const definitionOrMatching = {
    'definitionChoice',
    'definitionTyped',
    'matchingPair',
  };
  if (encoded == jsonEncode(_legacyDefault)) {
    return evidenceClass == 'independentRecall' &&
        !definitionOrMatching.contains(promptMode);
  }
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) return false;
    final skill = decoded['skillId'];
    final content = decoded['contentRevision'];
    final revision = decoded['featureContractRevision'];
    final hint = decoded['hintLevel'];
    final engagement = decoded['engagementAllowed'];
    if (!const {
          'independentRecall',
          'recognition',
          'guidedPractice',
          'pronunciation',
          'exposure',
          'recreational',
        }.contains(evidenceClass) ||
        !_v25Identifier(skill) ||
        !_v25Identifier(content) ||
        !_declaredIdentities.containsKey(revision) ||
        hint is! int ||
        hint < 0 ||
        engagement is! bool) {
      return false;
    }
    final expected = <String, Object?>{
      ..._legacyDefault,
      'evidenceClass': evidenceClass,
      'skillId': skill,
      'hintLevel': hint,
      'policyVersion': 'learning-evidence-v1',
      'contentRevision': content,
      'featureContractRevision': revision,
      'featureContractHash': _declaredIdentities[revision],
      'classificationSource': 'declared',
      'engagementAllowed': engagement,
    };
    if (encoded != jsonEncode(expected)) return false;
    if (v25NativeRewardPromptModes.contains(promptMode)) {
      return promptMode != 'matchingPair' &&
          engagement &&
          (evidenceClass == 'independentRecall' ||
              evidenceClass == 'recognition');
    }
    return true;
  } on FormatException {
    return false;
  }
}

const v25NativeRewardPromptModes = {
  'dictation',
  'clozeTyped',
  'clozeChoice',
  'wordScramble',
  'sentenceScramble',
  'definitionChoice',
  'definitionTyped',
  'matchingPair',
};

bool _v25Identifier(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value.trim() == value &&
    value.runes.length <= 256;

// Frozen defaults and supported identity pairs from 00d6c8ea, not today's policy.
const _legacyDefault = <String, Object?>{
  'schemaVersion': 1,
  'evidenceClass': 'independentRecall',
  'skillId': 'legacy-unspecified',
  'hintLevel': 0,
  'policyVersion': 'legacy-v1',
  'contentRevision': 'legacy-unknown',
  'featureContractRevision': 'legacy-unversioned',
  'featureContractHash':
      '0000000000000000000000000000000000000000000000000000000000000000',
  'classificationSource': 'legacyInferred',
  'rolloutMode': 'legacy',
  'protocolId': null,
  'protocolVersion': null,
  'experimentId': null,
  'experimentVersion': null,
  'assignmentId': null,
  'cohort': null,
  'researchConsentVersion': null,
  'instrumentId': null,
  'instrumentVersion': null,
  'formId': null,
  'formVersion': null,
  'assessmentItemId': null,
  'assessmentResponseCode': null,
  'scoringRuleVersion': null,
  'engagementAllowed': true,
};

const _declaredIdentities = {
  '1.0.0': 'f60ad6c20312b7e898c9961cf55618d9c8a5995c11d254cf32efad0c6d8a4cb0',
  '1.1.0': '40e587aa5605d066e67aee81f3254671ea5484beca04dbb41fccbfd3ddb2af27',
  '1.2.0': 'c6a772993afa6cc2d78f3eb11687d615192ef6ff52581fa882826180f90afee7',
  '1.3.0': '41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4',
};
