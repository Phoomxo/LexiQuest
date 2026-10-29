import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/application/assessment_comparison.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_repository.dart';
import 'package:vocab_learning_app/features/research/domain/research_trusted_time.dart';

import 'support/assessment_application_harness.dart';

void main() {
  late AssessmentRun pre;
  late AssessmentRun post;
  late SyntheticAssessmentRepository repository;
  late SyntheticContentAuthority content;
  late SyntheticCycleReader cycle;
  late AssessmentComparison comparison;
  late SyntheticTrustedTime trustedTime;
  var visible = true;
  setUp(() {
    pre = syntheticRun(state: AssessmentRunState.completed);
    post = syntheticRun(
      phase: AssessmentPhase.post,
      state: AssessmentRunState.completed,
    );
    repository = SyntheticAssessmentRepository([pre, post]);
    repository.evidence[pre.learningSessionId] = [
      syntheticEvidence(pre, 0),
      syntheticEvidence(pre, 1, correct: false),
    ];
    repository.evidence[post.learningSessionId] = [
      syntheticEvidence(post, 0),
      syntheticEvidence(post, 1),
    ];
    final definition = syntheticDefinition();
    content = SyntheticContentAuthority(definition);
    cycle = SyntheticCycleReader();
    trustedTime = SyntheticTrustedTime();
    visible = true;
    comparison = AssessmentComparison(
      repository: repository,
      instrumentCatalog: AssessmentInstrumentCatalog(entries: [definition]),
      contentAuthority: content,
      cycleReader: cycle,
      trustedTime: trustedTime,
    );
  });
  Future<AssessmentComparisonResult> compare() => comparison.compare(
    ownerId: pre.ownerId,
    studyCycleId: pre.studyCycleId,
    stillVisible: () => visible,
  );
  final incompatible = isA<AssessmentComparisonIncompatibleMetadata>();

  test(
    'compatible exact pair returns descriptive counts and accuracy deltas',
    () async {
      final result = await compare() as AssessmentComparisonReady;
      expect(result.preOutcome.sampleSize, 2);
      expect(result.preOutcome.correctCount, 1);
      expect(result.preOutcome.incorrectCount, 1);
      expect(result.preOutcome.accuracy, .5);
      expect(result.postOutcome.correctCount, 2);
      expect(result.postOutcome.accuracy, 1);
      expect(result.comparison.correctCountDelta, 1);
      expect(result.comparison.accuracyDelta, .5);
      expect(cycle.readRuns, [post]);
      // Each catalog item has its own scoring-rule version. No invented global rule.
      expect(
        content.definition.items.map((item) => item.scoringRuleVersion).toSet(),
        hasLength(2),
      );
    },
  );

  test(
    'missing or unfinished phase is missing pair, never a zero score',
    () async {
      repository.runs.clear();
      expect(await compare(), isA<AssessmentComparisonMissingPair>());
      repository.runs.add(pre);
      expect(await compare(), isA<AssessmentComparisonMissingPair>());
      repository.runs.add(syntheticRun(phase: AssessmentPhase.post));
      expect(await compare(), isA<AssessmentComparisonMissingPair>());
    },
  );

  test(
    'duplicate, foreign and same-container pairs are incompatible',
    () async {
      repository.runs.add(pre);
      expect(await compare(), incompatible);
      repository.runs.removeLast();
      for (final changes in [
        {'ownerId': 'foreign-owner'},
        {'studyCycleId': 'foreign-cycle'},
        {'id': pre.id},
        {'learningSessionId': pre.learningSessionId},
      ]) {
        repository.runs[1] = syntheticRun(
          phase: AssessmentPhase.post,
          state: AssessmentRunState.completed,
          changes: changes,
        );
        expect(await compare(), incompatible);
      }
    },
  );

  final changedSharedPins = <String, Object>{
    'protocolId': 'rotated-protocol',
    'protocolVersion': 'rotated-version',
    'protocolRevision': 13,
    'experimentId': 'rotated-experiment',
    'experimentVersion': 12,
    'assignmentId': 'rotated-assignment',
    'assignmentRevision': 14,
    'cohort': 'adventure',
    'consentVersion': 15,
    'consentDecidedAtUtc': syntheticTime(1),
    'instrumentId': 'rotated-instrument',
    'instrumentVersion': 'rotated-version',
    'instrumentRevision': 16,
    'formId': 'rotated-form',
    'formVersion': 'rotated-form-version',
    'formContentRevision': 17,
    'participationPermitId': 'rotated-permit',
    'participationPermitRevision': 18,
    'participationPermitPayloadSha256': 'b' * 64,
    'instrumentChecksumSha256': 'c' * 64,
    'formChecksumSha256': 'd' * 64,
    'appVersion': 'rotated-app',
    'buildId': 'rotated-build',
    'databaseSchemaVersion': 19,
    'contentRevision': 'rotated-content',
    'evidencePolicyVersion': 'rotated-policy',
    'featureContractRevision': 'rotated-contract',
    'featureContractHash': 'e' * 64,
  };
  for (final pin in changedSharedPins.entries) {
    test('pair rejects changed original ${pin.key}', () async {
      repository.runs[1] = syntheticRun(
        phase: AssessmentPhase.post,
        state: AssessmentRunState.completed,
        changes: {pin.key: pin.value},
      );
      expect(await compare(), incompatible);
    });
  }

  test(
    'historical pre and post must bracket the exact original intervention',
    () async {
      for (final receipt in [
        SyntheticCycleReceipt(firstExposureAtUtc: syntheticTime(19)),
        SyntheticCycleReceipt(interventionStartedAtUtc: syntheticTime(19)),
        SyntheticCycleReceipt(interventionCompletedAtUtc: syntheticTime(51)),
        SyntheticCycleReceipt(interventionCompletedAtUtc: syntheticTime(30)),
      ]) {
        cycle.receipt = receipt;
        expect(await compare(), incompatible);
      }
      cycle.receipt = SyntheticCycleReceipt();
      trustedTime.value = ResearchTrustedTime(
        anchorUtc: syntheticTime(59),
        validUntilUtc: syntheticTime(80),
        age: Duration.zero,
        maximumAge: const Duration(minutes: 10),
      );
      expect(await compare(), incompatible);
      trustedTime.value = null;
      expect(await compare(), incompatible);
    },
  );

  test(
    'only current post cycle proof is used, unavailable proof fails closed',
    () async {
      cycle.denied = true;
      expect(await compare(), incompatible);
      expect(cycle.readRuns, [post]);
      cycle.denied = false;
      for (final receipt in [
        SyntheticCycleReceipt(ownerId: 'foreign-owner'),
        SyntheticCycleReceipt(studyCycleId: 'foreign-cycle'),
        SyntheticCycleReceipt(phase: AssessmentPhase.pre),
        SyntheticCycleReceipt(opportunityId: null),
        SyntheticCycleReceipt(interventionSessionId: null),
        SyntheticCycleReceipt(interventionSessionId: pre.learningSessionId),
        SyntheticCycleReceipt(firstExposureAtUtc: DateTime(2026)),
      ]) {
        cycle.receipt = receipt;
        expect(await compare(), incompatible);
      }
    },
  );

  test('missing, duplicate and extra item evidence is incompatible', () async {
    final saved = [...repository.evidence[pre.learningSessionId]!];
    for (final evidence in [
      <dynamic>[],
      [saved.first],
      [saved.first, saved.first],
      [...saved, saved.first],
    ]) {
      repository.evidence[pre.learningSessionId] = evidence.cast();
      expect(await compare(), incompatible);
    }
  });

  final wrongEvidence = <String, Object>{
    'sourceEvidenceId': 'foreign-source',
    'ownerId': 'foreign-owner',
    'learningSessionId': 'foreign-session',
    'wordId': 'foreign-word',
    'promptMode': 'foreign-mode',
    'isCorrect': false,
    'occurredAtUtc': syntheticTime(9),
  };
  for (final field in wrongEvidence.entries) {
    test('evidence rejects changed ${field.key}', () async {
      repository.evidence[pre.learningSessionId]![0] = syntheticEvidence(
        pre,
        0,
        changes: {field.key: field.value},
      );
      expect(await compare(), incompatible);
    });
  }
  final wrongContext = <String, Object>{
    'skillId': 'foreign-skill',
    'protocolId': 'foreign-protocol',
    'protocolVersion': 'foreign-version',
    'experimentId': 'foreign-experiment',
    'experimentVersion': 99,
    'assignmentId': 'foreign-assignment',
    'cohort': 'foreign-cohort',
    'researchConsentVersion': 99,
    'instrumentId': 'foreign-instrument',
    'instrumentVersion': 'foreign-version',
    'formId': 'foreign-form',
    'formVersion': 'foreign-form-version',
    'assessmentItemId': 'foreign-item',
    'assessmentResponseCode': 'foreign-code',
    'scoringRuleVersion': 'foreign-rule',
    'contentRevision': 'foreign-content',
    'policyVersion': 'foreign-policy',
    'featureContractRevision': 'foreign-contract',
    'featureContractHash': 'f' * 64,
  };
  for (final field in wrongContext.entries) {
    if ({
      'policyVersion',
      'featureContractRevision',
      'featureContractHash',
    }.contains(field.key)) {
      test('EvidenceContext boundary rejects unsupported ${field.key}', () {
        expect(
          () => syntheticEvidence(
            pre,
            0,
            contextChanges: {field.key: field.value},
          ),
          throwsFormatException,
        );
      });
      continue;
    }
    test('evidence rejects changed context ${field.key}', () async {
      repository.evidence[pre.learningSessionId]![0] = syntheticEvidence(
        pre,
        0,
        contextChanges: {field.key: field.value},
      );
      expect(await compare(), incompatible);
    });
  }

  test(
    'validated evidence snapshots survive reused-list mutation during proof await',
    () async {
      repository.shareEvidenceLists = true;
      cycle.onRead = () {
        repository.evidence[pre.learningSessionId]!.clear();
        final after = repository.evidence[post.learningSessionId]!;
        after.add(after.first);
      };
      final result = await compare() as AssessmentComparisonReady;
      expect(result.preOutcome.sampleSize, 2);
      expect(result.preOutcome.correctCount, 1);
      expect(result.postOutcome.sampleSize, 2);
      expect(result.postOutcome.correctCount, 2);
      expect(result.comparison.accuracyDelta, .5);
    },
  );

  test(
    'response identity uses canonical JSON tuple without delimiter aliasing',
    () {
      expect(
        assessmentResponseIdentity('a|b', 'c'),
        isNot(assessmentResponseIdentity('a', 'b|c')),
      );
      expect(
        assessmentResponseIdentity('a|b', 'c'),
        syntheticResponseId('a|b', 'c'),
      );
    },
  );

  test(
    'content authority mismatch denies comparison without invented approval',
    () async {
      content.returned = AssessmentVerifiedFormContent(
        identity: AssessmentFormContentIdentity(
          formId: 'foreign-form',
          revision: 7,
        ),
        checksumSha256: content.definition.formChecksumSha256,
        bytes: content.definition.formBytes,
      );
      expect(await compare(), incompatible);
    },
  );

  test(
    'final trusted time follows post proof and visibility loss denies output',
    () async {
      trustedTime.onRead = () {
        expect(cycle.readRuns, [post]);
        visible = false;
      };
      expect(await compare(), incompatible);
      trustedTime.onRead = null;
      visible = true;
      trustedTime.value = ResearchTrustedTime(
        anchorUtc: syntheticTime(70),
        validUntilUtc: syntheticTime(80),
        age: const Duration(minutes: 11),
        maximumAge: const Duration(minutes: 10),
      );
      expect(await compare(), incompatible);
    },
  );
}
