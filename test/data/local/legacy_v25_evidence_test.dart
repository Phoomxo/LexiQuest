import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/legacy_v25_evidence.dart';

// Literal persisted default from 00d6c8ea learning_tables.dart.
const _frozenDefault =
    '{"schemaVersion":1,"evidenceClass":"independentRecall",'
    '"skillId":"legacy-unspecified","hintLevel":0,'
    '"policyVersion":"legacy-v1","contentRevision":"legacy-unknown",'
    '"featureContractRevision":"legacy-unversioned",'
    '"featureContractHash":"0000000000000000000000000000000000000000000000000000000000000000",'
    '"classificationSource":"legacyInferred","rolloutMode":"legacy",'
    '"protocolId":null,"protocolVersion":null,'
    '"experimentId":null,"experimentVersion":null,'
    '"assignmentId":null,"cohort":null,"researchConsentVersion":null,'
    '"instrumentId":null,"instrumentVersion":null,'
    '"formId":null,"formVersion":null,'
    '"assessmentItemId":null,"assessmentResponseCode":null,'
    '"scoringRuleVersion":null,"engagementAllowed":true}';

// The v25 factory emits declared ordinary evidence with engagementAllowed=false.
Map<String, Object?> _declared({bool srs = false}) => {
  ...jsonDecode(_frozenDefault) as Map<String, dynamic>,
  'evidenceClass': srs ? 'independentRecall' : 'recognition',
  'skillId': srs ? 'srs-recall' : 'meaning-recall',
  'policyVersion': 'learning-evidence-v1',
  'contentRevision': 'word:synthetic-word:1',
  'featureContractRevision': '1.3.0',
  'featureContractHash':
      '41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4',
  'classificationSource': 'declared',
  'engagementAllowed': false,
};

bool _quiz(String encoded, {String evidenceClass = 'recognition'}) =>
    isCompatibleV25Attempt(
      activityType: 'quiz',
      promptMode: 'meaningChoice',
      evidenceClass: evidenceClass,
      evidenceContextJson: encoded,
    );

void main() {
  test('actual frozen default remains compatible in the four base flows', () {
    for (final (activity, mode) in const [
      ('quiz', 'meaningChoice'),
      ('sourcePractice', 'meaningChoice'),
      ('weaknessPractice', 'meaningChoice'),
      ('srsReview', 'srsRecall'),
    ]) {
      expect(
        isCompatibleV25Attempt(
          activityType: activity,
          promptMode: mode,
          evidenceClass: 'independentRecall',
          evidenceContextJson: _frozenDefault,
        ),
        isTrue,
        reason: activity,
      );
    }
  });

  test('authentic declared quiz and SRS retain their different classes', () {
    for (final activity in ['quiz', 'sourcePractice', 'weaknessPractice']) {
      expect(
        isCompatibleV25Attempt(
          activityType: activity,
          promptMode: 'meaningChoice',
          evidenceClass: 'recognition',
          evidenceContextJson: jsonEncode(_declared()),
        ),
        isTrue,
      );
    }
    expect(
      isCompatibleV25Attempt(
        activityType: 'srsReview',
        promptMode: 'srsRecall',
        evidenceClass: 'independentRecall',
        evidenceContextJson: jsonEncode(_declared(srs: true)),
      ),
      isTrue,
    );
    expect(_quiz(' \n${jsonEncode(_declared())}\t'), isTrue);
  });

  test(
    'declared identities are exact revision and hash pairs pinned in v25',
    () {
      for (final (revision, hash) in const [
        (
          '1.0.0',
          'f60ad6c20312b7e898c9961cf55618d9c8a5995c11d254cf32efad0c6d8a4cb0',
        ),
        (
          '1.1.0',
          '40e587aa5605d066e67aee81f3254671ea5484beca04dbb41fccbfd3ddb2af27',
        ),
        (
          '1.2.0',
          'c6a772993afa6cc2d78f3eb11687d615192ef6ff52581fa882826180f90afee7',
        ),
      ]) {
        final context = _declared()
          ..['featureContractRevision'] = revision
          ..['featureContractHash'] = hash;
        expect(_quiz(jsonEncode(context)), isTrue, reason: revision);
        context['featureContractRevision'] = '1.3.0';
        expect(
          _quiz(jsonEncode(context)),
          isFalse,
          reason: 'mismatched $revision',
        );
      }
    },
  );

  test('unsupported activity or prompt cannot reuse compatible metadata', () {
    for (final (activity, mode) in const [
      ('assessment', 'meaningChoice'),
      ('syncedEvidence', 'meaningChoice'),
      ('unknown', 'meaningChoice'),
      ('quiz', 'definitionChoice'),
      ('quiz', 'definitionTyped'),
      ('quiz', 'matchingPair'),
      ('quiz', 'spellingChoice'),
      ('quiz', 'srsRecall'),
      ('srsReview', 'meaningChoice'),
      ('dictation', 'dictation'),
      ('cloze', 'clozeChoice'),
      ('wordScramble', 'wordScramble'),
      ('ghostDuel', 'ghostSpelling'),
    ]) {
      expect(
        isCompatibleV25Attempt(
          activityType: activity,
          promptMode: mode,
          evidenceClass: 'independentRecall',
          evidenceContextJson: _frozenDefault,
        ),
        isFalse,
        reason: '$activity/$mode',
      );
    }
  });

  test(
    'unknown, hinted, mismatched or widened declarations are historical',
    () {
      for (final (key, value) in <(String, Object?)>[
        ('schemaVersion', 2),
        ('schemaVersion', 1.0),
        ('evidenceClass', 'independentRecall'),
        ('evidenceClass', 'guidedPractice'),
        ('evidenceClass', 'assessment'),
        ('skillId', 'srs-recall'),
        ('hintLevel', 1),
        ('hintLevel', -1),
        ('hintLevel', 0.0),
        ('policyVersion', 'future-policy'),
        ('classificationSource', 'legacyInferred'),
        ('rolloutMode', 'shadow'),
        ('rolloutMode', 'enforced'),
        ('engagementAllowed', true),
        ('engagementAllowed', 0),
        ('featureContractRevision', '9.0.0'),
        ('featureContractHash', '0' * 64),
        ('contentRevision', null),
        ('contentRevision', ''),
        ('contentRevision', ' word:1'),
        ('contentRevision', 'x' * 257),
      ]) {
        expect(
          _quiz(jsonEncode(_declared()..[key] = value)),
          isFalse,
          reason: '$key=$value',
        );
      }
      expect(
        _quiz(jsonEncode(_declared()), evidenceClass: 'independentRecall'),
        isFalse,
      );
      expect(_quiz(_frozenDefault), isFalse);
      final changedLegacy = jsonDecode(_frozenDefault) as Map<String, dynamic>;
      changedLegacy['contentRevision'] = 'not-the-frozen-default';
      expect(
        _quiz(jsonEncode(changedLegacy), evidenceClass: 'independentRecall'),
        isFalse,
      );
    },
  );

  test('every research or assessment pin must remain null', () {
    for (final key in [
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
    ]) {
      expect(
        _quiz(jsonEncode(_declared()..[key] = 'synthetic-pin')),
        isFalse,
        reason: key,
      );
    }
  });

  test(
    'rejects malformed, duplicate-key and noncanonical JSON without throwing',
    () {
      final valid = jsonEncode(_declared());
      final missing = _declared()..remove('protocolId');
      final extra = _declared()..['futureField'] = null;
      for (final encoded in [
        '',
        '{',
        '[]',
        'null',
        'true',
        jsonEncode(missing),
        jsonEncode(extra),
        valid.replaceFirst('"hintLevel":0', '"hintLevel":1,"hintLevel":0'),
        valid.replaceFirst('"hintLevel":0', '"hintLevel":0,"hintLevel":0'),
        jsonEncode(Map.fromEntries(_declared().entries.toList().reversed)),
        '${' ' * 16384}$valid',
      ]) {
        expect(_quiz(encoded), isFalse);
      }
    },
  );

  test('original Unicode content pins are retained without normalization', () {
    final context = _declared()..['contentRevision'] = 'คำศัพท์:สังเคราะห์:1';
    expect(_quiz(jsonEncode(context)), isTrue);
  });
}
