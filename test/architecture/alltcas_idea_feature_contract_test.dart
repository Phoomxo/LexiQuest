import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/product/feature_contract/alltcas_idea_integration_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/compatibility_profiles.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';
import 'package:vocab_learning_app/runtime/production_feature_contract.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

void main() {
  group('AllTCAS 8/44 product feature contract', () {
    test('pins the catalog metadata and exact approved definitions', () {
      expect(featureContractRevision, '1.2.0');
      expect(featureContractBaselineCommit, '61a4fec');
      expect(featureContractSchemaVersion, 1);
      expect(featureContractGeneratorVersion, '1.0.0');
      expect(allTcasIdeaIntegrationCatalog.revision, featureContractRevision);
      expect(allTcasIdeaIntegrationCatalog.records, hasLength(44));
      expect(
        allTcasIdeaIntegrationCatalog.records.map((record) => record.id),
        FeatureContractId.values,
      );
      expect(
        allTcasIdeaIntegrationCatalog.experimentalCandidates.map(
          (item) => item.id,
        ),
        ExperimentalCandidateId.values,
      );

      const expectedNames = <FeatureContractId, String>{
        FeatureContractId.f01: 'Curriculum & Learning Pack Catalog',
        FeatureContractId.f02: 'Learning Pack Detail',
        FeatureContractId.f03: 'Rich Lexical Card',
        FeatureContractId.f04: 'Content Version & Quality Control',
        FeatureContractId.f05: 'Unified Lesson Shell',
        FeatureContractId.f06: 'Flashcard Mode',
        FeatureContractId.f07: 'Meaning Quiz',
        FeatureContractId.f08: 'Definition Quiz',
        FeatureContractId.f09: 'Cloze Test',
        FeatureContractId.f10: 'Matching Mode',
        FeatureContractId.f11: 'Typed Recall / Writing',
        FeatureContractId.f12: 'Handwriting Scratchpad',
        FeatureContractId.f13: 'LexiQuest Native Modes Integration',
        FeatureContractId.f14: 'Flashcard-First Recommendation',
        FeatureContractId.f15: 'Active-Recall Ladder',
        FeatureContractId.f16: 'Session Configuration',
        FeatureContractId.f17: 'Immediate Answer Feedback',
        FeatureContractId.f18: 'Contrastive Distractor Explanation',
        FeatureContractId.f19: 'Hint, Strategy & Context',
        FeatureContractId.f20: 'Bookmark / Save',
        FeatureContractId.f21: 'Flag / Report Content',
        FeatureContractId.f22: 'Review Center',
        FeatureContractId.f23: 'Focus Timer',
        FeatureContractId.f24: 'Automatic Learning-Time Capture',
        FeatureContractId.f25: 'Learning Calendar & Weekly Analytics',
        FeatureContractId.f26: 'Goal / Test Countdown',
        FeatureContractId.f27: 'Opt-in Study Reminder',
        FeatureContractId.f28: 'Learning Assessment & Progress Comparison',
        FeatureContractId.f29: 'Evidence-Based Quest',
        FeatureContractId.f30: 'Gentle Streak',
        FeatureContractId.f31: 'Achievement & Milestone',
        FeatureContractId.f32: 'Avatar Level-Up & Cosmetic Unlock',
        FeatureContractId.f33: 'Contextual Companion',
        FeatureContractId.f34: 'Achievement Share Card',
        FeatureContractId.f35: 'Learning Preference & Goal Quiz',
        FeatureContractId.f36: 'Personal Learning Profile',
        FeatureContractId.f37: 'Recommendation Panel',
        FeatureContractId.f38: 'Accessibility',
        FeatureContractId.f39: 'Motion & Theme Controls',
        FeatureContractId.f40: 'Local-First Operation',
        FeatureContractId.f41: 'Feature Flag & Controlled Rollout',
        FeatureContractId.f42: 'Today Hub',
        FeatureContractId.f43: 'Learning History',
        FeatureContractId.f44: 'Offline Content Manager',
      };
      const expectedPurposes = <FeatureContractId, String>{
        FeatureContractId.f01:
            'Discover and filter versioned packs by CEFR, topic, skill, and goal while referencing canonical Vocabulary IDs.',
        FeatureContractId.f02:
            'Explain pack level, content, progress, examples, and available activities before a session starts.',
        FeatureContractId.f03:
            'Present canonical meanings, part of speech, CEFR, IPA, audio, examples, synonyms, and antonyms progressively.',
        FeatureContractId.f04:
            'Pin revision, provenance, review state, checksum, and publication status for reproducible learning and research.',
        FeatureContractId.f05:
            'Own shared session state, progress, pause/resume, timer, audio actions, completion, and adapter boundaries.',
        FeatureContractId.f06:
            'Support exposure and self-rated recall through the existing SRS authority.',
        FeatureContractId.f07:
            'Measure bidirectional meaning recognition without inventing a second quiz authority.',
        FeatureContractId.f08:
            'Practice English-definition recognition with explicit evidence calibration.',
        FeatureContractId.f09:
            'Practice contextual retrieval; selected and typed variants receive different evidence profiles.',
        FeatureContractId.f10:
            'Train fluent recognition with lower mastery weight than independent recall.',
        FeatureContractId.f11:
            'Capture independent spelling and productive recall from meaning, audio, or context.',
        FeatureContractId.f12:
            'Provide local, ephemeral handwriting and self-checking without OCR or automatic mastery claims.',
        FeatureContractId.f13:
            'Adapt Dictation, Speaking, Shadowing, Reading, Scramble, and Associative Reading to the shared shell and evidence gateway.',
        FeatureContractId.f14:
            'Recommend preparation before harder recall while preserving learner choice.',
        FeatureContractId.f15:
            'Sequence exposure, recognition, matching, cloze, typed recall, dictation, and speaking from evidence.',
        FeatureContractId.f16:
            'Configure item count, direction, difficulty, hints, time, and pack within protocol limits.',
        FeatureContractId.f17:
            'Show accessible correct/incorrect feedback without creating an additional scored event.',
        FeatureContractId.f18:
            "Explain the correct answer and the learner's selected distractor as guided feedback.",
        FeatureContractId.f19:
            'Record hint level and provide staged support without counting assisted work as independent recall.',
        FeatureContractId.f20:
            'Preserve learner intent to revisit an item without classifying it as weakness.',
        FeatureContractId.f21:
            'Submit versioned quality reports for ambiguous or incorrect text, audio, answer, or explanation.',
        FeatureContractId.f22:
            'Compose saved, incorrect, due-SRS, and reported items while preserving the reason for each queue entry.',
        FeatureContractId.f23:
            'Create explicit focus intervals with start, pause, resume, and finish states.',
        FeatureContractId.f24:
            'Measure active effort while excluding idle and background time from learning duration.',
        FeatureContractId.f25:
            'Present effort, accuracy, skill distribution, and trends as separate measures.',
        FeatureContractId.f26:
            'Track language-test, course, or personal learning deadlines without admission-score logic.',
        FeatureContractId.f27:
            'Schedule user-controlled reminders for due review or goals without punitive messaging.',
        FeatureContractId.f28:
            'Run versioned pre-learning and post-learning assessment and report their comparison separately from practice.',
        FeatureContractId.f29:
            'Advance the existing Quest authority only from evidence allowed by the active policy.',
        FeatureContractId.f30:
            'Use the dedicated Streak authority with grace, freeze, and recovery rules that avoid punishment.',
        FeatureContractId.f31:
            'Unlock durable milestones from eligible, idempotent learning evidence.',
        FeatureContractId.f32:
            'Connect lifetime progression to cosmetics while keeping XP and spendable Coins separate.',
        FeatureContractId.f33:
            'Use scripted, versioned reactions to session events before considering generative behavior.',
        FeatureContractId.f34:
            'Generate an opt-in shareable artifact without creating an internal social network.',
        FeatureContractId.f35:
            'Set editable defaults from goals, available time, and activity preference without fixed learning-style labels.',
        FeatureContractId.f36:
            'Read separate Mastery, SRS, effort, accuracy, weakness, and engagement projections.',
        FeatureContractId.f37:
            'Explain the next suggested activity from canonical projections while allowing learner override.',
        FeatureContractId.f38:
            'Enforce scaling, screen-reader semantics, non-color cues, untimed alternatives, and input/media alternatives.',
        FeatureContractId.f39:
            'Support Light, Dark, System, and Reduced Motion consistently.',
        FeatureContractId.f40:
            'Commit locally before cloud synchronization and preserve learning through outages and restarts.',
        FeatureContractId.f41:
            'Use the existing runtime registry for Internal → Pilot → Enabled rollout, kill switch, and fail-closed invocation.',
        FeatureContractId.f42:
            'Compose assigned, due, resumable, and recommended work from canonical read models; it owns no progress metric.',
        FeatureContractId.f43:
            'Present immutable session/evidence history; replay creates a new session and never edits the original evidence.',
        FeatureContractId.f44:
            'Download, verify, pin, repair, and remove content/media versions without deleting learning evidence.',
      };

      for (final record in allTcasIdeaIntegrationCatalog.records) {
        expect(
          record.name,
          expectedNames[record.id],
          reason: '${record.id} name',
        );
        expect(
          record.purpose,
          expectedPurposes[record.id],
          reason: '${record.id} responsibility',
        );
      }
    });

    test('preserves exact domain membership and 8/23/13 coverage', () {
      final domainCounts = <FeatureDomain, int>{
        for (final domain in FeatureDomain.values)
          domain: allTcasIdeaIntegrationCatalog.records
              .where((record) => record.domain == domain)
              .length,
      };
      expect(domainCounts, <FeatureDomain, int>{
        FeatureDomain.learningContentAndPacks: 4,
        FeatureDomain.unifiedLearningExperience: 9,
        FeatureDomain.recallFeedbackAndControl: 8,
        FeatureDomain.reviewTimeAndAssessment: 7,
        FeatureDomain.motivationAndEngagement: 6,
        FeatureDomain.personalizationAndAccessibility: 5,
        FeatureDomain.localReliabilityOfflineAndRollout: 3,
        FeatureDomain.dailyContinuityAndHistory: 2,
      });

      const expectedByDomain = <FeatureDomain, Set<FeatureContractId>>{
        FeatureDomain.learningContentAndPacks: {
          FeatureContractId.f01,
          FeatureContractId.f02,
          FeatureContractId.f03,
          FeatureContractId.f04,
        },
        FeatureDomain.unifiedLearningExperience: {
          FeatureContractId.f05,
          FeatureContractId.f06,
          FeatureContractId.f07,
          FeatureContractId.f08,
          FeatureContractId.f09,
          FeatureContractId.f10,
          FeatureContractId.f11,
          FeatureContractId.f12,
          FeatureContractId.f13,
        },
        FeatureDomain.recallFeedbackAndControl: {
          FeatureContractId.f14,
          FeatureContractId.f15,
          FeatureContractId.f16,
          FeatureContractId.f17,
          FeatureContractId.f18,
          FeatureContractId.f19,
          FeatureContractId.f20,
          FeatureContractId.f21,
        },
        FeatureDomain.reviewTimeAndAssessment: {
          FeatureContractId.f22,
          FeatureContractId.f23,
          FeatureContractId.f24,
          FeatureContractId.f25,
          FeatureContractId.f26,
          FeatureContractId.f27,
          FeatureContractId.f28,
        },
        FeatureDomain.motivationAndEngagement: {
          FeatureContractId.f29,
          FeatureContractId.f30,
          FeatureContractId.f31,
          FeatureContractId.f32,
          FeatureContractId.f33,
          FeatureContractId.f34,
        },
        FeatureDomain.personalizationAndAccessibility: {
          FeatureContractId.f35,
          FeatureContractId.f36,
          FeatureContractId.f37,
          FeatureContractId.f38,
          FeatureContractId.f39,
        },
        FeatureDomain.localReliabilityOfflineAndRollout: {
          FeatureContractId.f40,
          FeatureContractId.f41,
          FeatureContractId.f44,
        },
        FeatureDomain.dailyContinuityAndHistory: {
          FeatureContractId.f42,
          FeatureContractId.f43,
        },
      };
      for (final domain in FeatureDomain.values) {
        expect(
          allTcasIdeaIntegrationCatalog.records
              .where((record) => record.domain == domain)
              .map((record) => record.id)
              .toSet(),
          expectedByDomain[domain],
          reason: '$domain membership',
        );
      }

      final coverageCounts = <FeatureCoverage, int>{
        for (final coverage in FeatureCoverage.values)
          coverage: allTcasIdeaIntegrationCatalog.records
              .where((record) => record.coverage == coverage)
              .length,
      };
      expect(coverageCounts[FeatureCoverage.existing], 8);
      expect(coverageCounts[FeatureCoverage.partial], 23);
      expect(coverageCounts[FeatureCoverage.newCapability], 13);

      const expectedExisting = <FeatureContractId>{
        FeatureContractId.f06,
        FeatureContractId.f07,
        FeatureContractId.f17,
        FeatureContractId.f29,
        FeatureContractId.f30,
        FeatureContractId.f31,
        FeatureContractId.f40,
        FeatureContractId.f41,
      };
      const expectedPartial = <FeatureContractId>{
        FeatureContractId.f01,
        FeatureContractId.f02,
        FeatureContractId.f03,
        FeatureContractId.f04,
        FeatureContractId.f08,
        FeatureContractId.f09,
        FeatureContractId.f11,
        FeatureContractId.f13,
        FeatureContractId.f14,
        FeatureContractId.f15,
        FeatureContractId.f16,
        FeatureContractId.f19,
        FeatureContractId.f22,
        FeatureContractId.f24,
        FeatureContractId.f25,
        FeatureContractId.f32,
        FeatureContractId.f33,
        FeatureContractId.f36,
        FeatureContractId.f37,
        FeatureContractId.f38,
        FeatureContractId.f39,
        FeatureContractId.f43,
        FeatureContractId.f44,
      };
      const expectedNew = <FeatureContractId>{
        FeatureContractId.f05,
        FeatureContractId.f10,
        FeatureContractId.f12,
        FeatureContractId.f18,
        FeatureContractId.f20,
        FeatureContractId.f21,
        FeatureContractId.f23,
        FeatureContractId.f26,
        FeatureContractId.f27,
        FeatureContractId.f28,
        FeatureContractId.f34,
        FeatureContractId.f35,
        FeatureContractId.f42,
      };
      Set<FeatureContractId> idsWithCoverage(FeatureCoverage coverage) =>
          allTcasIdeaIntegrationCatalog.records
              .where((record) => record.coverage == coverage)
              .map((record) => record.id)
              .toSet();
      expect(idsWithCoverage(FeatureCoverage.existing), expectedExisting);
      expect(idsWithCoverage(FeatureCoverage.partial), expectedPartial);
      expect(idsWithCoverage(FeatureCoverage.newCapability), expectedNew);
    });

    test('preserves exact provenance classifications', () {
      const adapted = <FeatureContractId>{
        FeatureContractId.f22,
        FeatureContractId.f24,
        FeatureContractId.f26,
        FeatureContractId.f27,
        FeatureContractId.f29,
        FeatureContractId.f30,
        FeatureContractId.f35,
        FeatureContractId.f39,
      };
      const lexiQuest = <FeatureContractId>{
        FeatureContractId.f04,
        FeatureContractId.f05,
        FeatureContractId.f13,
        FeatureContractId.f15,
        FeatureContractId.f28,
        FeatureContractId.f37,
        FeatureContractId.f38,
        FeatureContractId.f40,
        FeatureContractId.f41,
        FeatureContractId.f42,
        FeatureContractId.f43,
        FeatureContractId.f44,
      };
      for (final record in allTcasIdeaIntegrationCatalog.records) {
        final expected = adapted.contains(record.id)
            ? FeatureProvenance.adaptedToLexiQuest
            : lexiQuest.contains(record.id)
            ? FeatureProvenance.lexiQuestControl
            : FeatureProvenance.alltcasConfirmed;
        expect(record.provenance, expected, reason: '${record.id} provenance');
      }
    });

    test('resolves every dependency and has no dependency cycle', () {
      final recordsById = <FeatureContractId, ProductFeatureContract>{
        for (final record in allTcasIdeaIntegrationCatalog.records)
          record.id: record,
      };
      for (final record in allTcasIdeaIntegrationCatalog.records) {
        expect(
          record.dependencies.every(recordsById.containsKey),
          isTrue,
          reason: '${record.id} has an unresolved dependency',
        );
      }
      for (final candidate
          in allTcasIdeaIntegrationCatalog.experimentalCandidates) {
        expect(
          candidate.dependencies.every(recordsById.containsKey),
          isTrue,
          reason: '${candidate.id} has an unresolved dependency',
        );
      }

      final visitState = <FeatureContractId, int>{};
      void visit(FeatureContractId id) {
        final state = visitState[id] ?? 0;
        if (state == 1) {
          fail('Dependency cycle reaches $id');
        }
        if (state == 2) {
          return;
        }
        visitState[id] = 1;
        for (final dependency in recordsById[id]!.dependencies) {
          visit(dependency);
        }
        visitState[id] = 2;
      }

      for (final id in FeatureContractId.values) {
        visit(id);
      }
    });

    test('pins f23 and f24 to the approved typed dependency order', () {
      final records = <FeatureContractId, ProductFeatureContract>{
        for (final record in allTcasIdeaIntegrationCatalog.records)
          record.id: record,
      };
      expect(
        records[FeatureContractId.f23]!.dependencies,
        const <FeatureContractId>{FeatureContractId.f24},
      );
      final f24 = records[FeatureContractId.f24]!;
      expect(f24.dependencies, const <FeatureContractId>{
        FeatureContractId.f05,
        FeatureContractId.f17,
        FeatureContractId.f19,
        FeatureContractId.f20,
        FeatureContractId.f21,
      });
      expect(f24.activationProfileId, runtimeFlaggedActivationProfileId);
      expect(f24.rolloutProfileId, controlledRolloutProfileId);
      expect(f24.rollbackProfileId, runtimeFlagRollbackProfileId);
      expect(f24.authorityDependencies, const <DomainAuthority>{
        DomainAuthority.responseEvidence,
        DomainAuthority.activeLearningTime,
      });
      expect(
        f24.authorityProfileId,
        activeLearningTimeWriterAuthorityProfileId,
      );
      expect(
        singleWriterAuthorityMatrix[DomainAuthority.activeLearningTime],
        activeLearningTimeWriterAuthorityProfileId,
      );
    });

    test('resolves every profile and gives each authority one writer', () {
      for (final record in allTcasIdeaIntegrationCatalog.records) {
        expect(authorityProfiles, contains(record.authorityProfileId));
        expect(evidenceProfiles, contains(record.evidenceProfileId));
        expect(lifecycleProfiles, contains(record.lifecycleProfileId));
        expect(activationProfiles, contains(record.activationProfileId));
        expect(rolloutProfiles, contains(record.rolloutProfileId));
        expect(rollbackProfiles, contains(record.rollbackProfileId));
        expect(
          record.authorityDependencies.every(
            singleWriterAuthorityMatrix.containsKey,
          ),
          isTrue,
        );
      }
      for (final candidate
          in allTcasIdeaIntegrationCatalog.experimentalCandidates) {
        expect(activationProfiles, contains(candidate.activationProfileId));
        expect(rolloutProfiles, contains(candidate.rolloutProfileId));
        expect(rollbackProfiles, contains(candidate.rollbackProfileId));
      }

      expect(
        singleWriterAuthorityMatrix.keys.toSet(),
        DomainAuthority.values.toSet(),
      );
      for (final authority in DomainAuthority.values) {
        final writers = authorityProfiles.values
            .where((profile) => profile.writableAuthorities.contains(authority))
            .toList(growable: false);
        expect(writers, hasLength(1), reason: '$authority writer count');
        expect(writers.single.id, singleWriterAuthorityMatrix[authority]);
      }
    });

    test('defines the complete 7 by 11 evidence compatibility matrix', () {
      const expected =
          <ContractEvidenceClass, Map<ProjectionFamily, ProjectionDecision>>{
            ContractEvidenceClass.assessment: {
              ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
              ProjectionFamily.masterySrs: ProjectionDecision.deny,
              ProjectionFamily.assessmentOutcome: ProjectionDecision.allow,
              ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
              ProjectionFamily.history: ProjectionDecision.allow,
              ProjectionFamily.pronunciation: ProjectionDecision.deny,
              ProjectionFamily.quest: ProjectionDecision.deny,
              ProjectionFamily.streak: ProjectionDecision.deny,
              ProjectionFamily.achievement: ProjectionDecision.deny,
              ProjectionFamily.xp: ProjectionDecision.deny,
              ProjectionFamily.coins: ProjectionDecision.deny,
            },
            ContractEvidenceClass.independentRecall: {
              ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
              ProjectionFamily.masterySrs: ProjectionDecision.allow,
              ProjectionFamily.assessmentOutcome: ProjectionDecision.deny,
              ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
              ProjectionFamily.history: ProjectionDecision.allow,
              ProjectionFamily.pronunciation: ProjectionDecision.deny,
              ProjectionFamily.quest: ProjectionDecision.protocolControlled,
              ProjectionFamily.streak: ProjectionDecision.protocolControlled,
              ProjectionFamily.achievement:
                  ProjectionDecision.protocolControlled,
              ProjectionFamily.xp: ProjectionDecision.protocolControlled,
              ProjectionFamily.coins: ProjectionDecision.protocolControlled,
            },
            ContractEvidenceClass.recognition: {
              ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
              ProjectionFamily.masterySrs: ProjectionDecision.deny,
              ProjectionFamily.assessmentOutcome: ProjectionDecision.deny,
              ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
              ProjectionFamily.history: ProjectionDecision.allow,
              ProjectionFamily.pronunciation: ProjectionDecision.deny,
              ProjectionFamily.quest: ProjectionDecision.protocolControlled,
              ProjectionFamily.streak: ProjectionDecision.protocolControlled,
              ProjectionFamily.achievement:
                  ProjectionDecision.protocolControlled,
              ProjectionFamily.xp: ProjectionDecision.protocolControlled,
              ProjectionFamily.coins: ProjectionDecision.protocolControlled,
            },
            ContractEvidenceClass.guidedPractice: {
              ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
              ProjectionFamily.masterySrs: ProjectionDecision.deny,
              ProjectionFamily.assessmentOutcome: ProjectionDecision.deny,
              ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
              ProjectionFamily.history: ProjectionDecision.allow,
              ProjectionFamily.pronunciation: ProjectionDecision.deny,
              ProjectionFamily.quest: ProjectionDecision.deny,
              ProjectionFamily.streak: ProjectionDecision.deny,
              ProjectionFamily.achievement: ProjectionDecision.deny,
              ProjectionFamily.xp: ProjectionDecision.deny,
              ProjectionFamily.coins: ProjectionDecision.deny,
            },
            ContractEvidenceClass.pronunciation: {
              ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
              ProjectionFamily.masterySrs: ProjectionDecision.deny,
              ProjectionFamily.assessmentOutcome: ProjectionDecision.deny,
              ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
              ProjectionFamily.history: ProjectionDecision.allow,
              ProjectionFamily.pronunciation: ProjectionDecision.allow,
              ProjectionFamily.quest: ProjectionDecision.deny,
              ProjectionFamily.streak: ProjectionDecision.deny,
              ProjectionFamily.achievement: ProjectionDecision.deny,
              ProjectionFamily.xp: ProjectionDecision.deny,
              ProjectionFamily.coins: ProjectionDecision.deny,
            },
            ContractEvidenceClass.exposure: {
              ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
              ProjectionFamily.masterySrs: ProjectionDecision.deny,
              ProjectionFamily.assessmentOutcome: ProjectionDecision.deny,
              ProjectionFamily.activeLearningEffort: ProjectionDecision.allow,
              ProjectionFamily.history: ProjectionDecision.allow,
              ProjectionFamily.pronunciation: ProjectionDecision.deny,
              ProjectionFamily.quest: ProjectionDecision.deny,
              ProjectionFamily.streak: ProjectionDecision.deny,
              ProjectionFamily.achievement: ProjectionDecision.deny,
              ProjectionFamily.xp: ProjectionDecision.deny,
              ProjectionFamily.coins: ProjectionDecision.deny,
            },
            ContractEvidenceClass.recreational: {
              ProjectionFamily.sessionOutcome: ProjectionDecision.allow,
              ProjectionFamily.masterySrs: ProjectionDecision.deny,
              ProjectionFamily.assessmentOutcome: ProjectionDecision.deny,
              ProjectionFamily.activeLearningEffort: ProjectionDecision.deny,
              ProjectionFamily.history: ProjectionDecision.allow,
              ProjectionFamily.pronunciation: ProjectionDecision.deny,
              ProjectionFamily.quest: ProjectionDecision.deny,
              ProjectionFamily.streak: ProjectionDecision.deny,
              ProjectionFamily.achievement: ProjectionDecision.deny,
              ProjectionFamily.xp: ProjectionDecision.deny,
              ProjectionFamily.coins: ProjectionDecision.deny,
            },
          };

      expect(evidenceCompatibilityMatrix, expected);
      expect(
        evidenceCompatibilityMatrix.keys.toSet(),
        ContractEvidenceClass.values.toSet(),
      );
      for (final row in evidenceCompatibilityMatrix.values) {
        expect(row.keys.toSet(), ProjectionFamily.values.toSet());
      }

      final assessment =
          evidenceCompatibilityMatrix[ContractEvidenceClass.assessment]!;
      for (final denied in <ProjectionFamily>{
        ProjectionFamily.masterySrs,
        ProjectionFamily.quest,
        ProjectionFamily.streak,
        ProjectionFamily.achievement,
        ProjectionFamily.xp,
        ProjectionFamily.coins,
      }) {
        expect(assessment[denied], ProjectionDecision.deny);
      }
      final recreational =
          evidenceCompatibilityMatrix[ContractEvidenceClass.recreational]!;
      expect(recreational[ProjectionFamily.history], ProjectionDecision.allow);
      expect(
        recreational[ProjectionFamily.activeLearningEffort],
        ProjectionDecision.deny,
      );
    });

    test(
      'keeps product metadata and runtime evidence policy in exact parity',
      () {
        expect(
          EvidenceClass.values.map((value) => value.name),
          ContractEvidenceClass.values.map((value) => value.name),
        );
        expect(
          LearningProjection.values.map((value) => value.name),
          ProjectionFamily.values.map((value) => value.name),
        );
        expect(
          ProjectionDisposition.values.map((value) => value.name),
          ProjectionDecision.values.map((value) => value.name),
        );

        for (final productEvidenceClass in ContractEvidenceClass.values) {
          final runtimeEvidenceClass = EvidenceClass.values.byName(
            productEvidenceClass.name,
          );
          final productRow = evidenceCompatibilityMatrix[productEvidenceClass]!;
          final runtimeRow = evidenceEligibilityV1[runtimeEvidenceClass]!;

          expect(
            runtimeRow.keys.map((value) => value.name).toSet(),
            productRow.keys.map((value) => value.name).toSet(),
            reason: '${productEvidenceClass.name} projection families',
          );
          for (final productProjection in ProjectionFamily.values) {
            final runtimeProjection = LearningProjection.values.byName(
              productProjection.name,
            );
            expect(
              runtimeRow[runtimeProjection]!.name,
              productRow[productProjection]!.name,
              reason:
                  '${productEvidenceClass.name} x ${productProjection.name}',
            );
          }
        }
      },
    );

    test('closes raw evidence construction behind validated factories', () {
      final source = File(
        'lib/features/learning/domain/evidence_context.dart',
      ).readAsStringSync();

      expect(source, contains('const EvidenceContext._({'));
      expect(source, isNot(contains('const EvidenceContext({')));
      expect(source, contains('factory EvidenceContext.forNewEvidence({'));
      expect(source, contains('factory EvidenceContext.fromJson('));
      expect(source, contains('factory EvidenceContext.legacyCompatibility({'));
    });

    test('closes evidence resolution against injectable policy bypasses', () {
      final source = File(
        'lib/features/learning/domain/evidence_eligibility_policy.dart',
      ).readAsStringSync();

      expect(source, contains('sealed class EvidenceEligibilityPolicy'));
      expect(
        source,
        isNot(contains('abstract interface class EvidenceEligibilityPolicy')),
      );
      expect(source, isNot(contains('EvidenceEligibilityPolicy policy')));

      final resolver = source.indexOf(
        'factory EvidenceProjectionDecision.resolve',
      );
      final validation = source.indexOf('context.validate();', resolver);
      final closedLookup = source.indexOf(
        'const EvidenceEligibilityPolicySet().disposition',
        resolver,
      );
      expect(resolver, greaterThanOrEqualTo(0));
      expect(validation, greaterThan(resolver));
      expect(closedLookup, greaterThan(validation));
    });

    test('maps every current runtime feature to the exact product IDs', () {
      const expected = <Feature, Set<FeatureContractId>>{
        Feature.vocabulary: {
          FeatureContractId.f01,
          FeatureContractId.f02,
          FeatureContractId.f03,
        },
        Feature.quiz: {
          FeatureContractId.f07,
          FeatureContractId.f08,
          FeatureContractId.f09,
          FeatureContractId.f11,
        },
        Feature.srs: {
          FeatureContractId.f06,
          FeatureContractId.f14,
          FeatureContractId.f22,
        },
        Feature.reading: {FeatureContractId.f13},
        Feature.mastery: {FeatureContractId.f36},
        Feature.weakness: {FeatureContractId.f36},
        Feature.ghostDuel: {FeatureContractId.f13},
        Feature.achievements: {FeatureContractId.f31},
        Feature.shop: {FeatureContractId.f32},
        Feature.objectScanner: {FeatureContractId.f13},
        Feature.speechPractice: {FeatureContractId.f13},
        Feature.aiTutor: {FeatureContractId.f19, FeatureContractId.f33},
        Feature.export: {FeatureContractId.f40},
        Feature.shadowRewardV2: {FeatureContractId.f29},
        Feature.questV2: {FeatureContractId.f29},
        Feature.studyPlanning: {
          FeatureContractId.f01,
          FeatureContractId.f26,
          FeatureContractId.f27,
        },
        Feature.researchAssessment: {FeatureContractId.f28},
        Feature.dailyContinuity: {
          FeatureContractId.f22,
          FeatureContractId.f30,
          FeatureContractId.f37,
          FeatureContractId.f42,
          FeatureContractId.f43,
        },
        Feature.offlineContent: {FeatureContractId.f44},
      };
      expect(Feature.values, hasLength(19));
      expect(productContractIdsByRuntimeFeature, expected);
      expect(
        productContractIdsByRuntimeFeature.keys.toSet(),
        Feature.values.toSet(),
      );

      final allowedProductionEntries = productionFeatureContract.values
          .map((delivery) => delivery.productionEntryId)
          .where((entryId) => entryId.isNotEmpty)
          .toSet();
      for (final record in allTcasIdeaIntegrationCatalog.records) {
        for (final feature in record.runtimeFeatures) {
          expect(
            productContractIdsByRuntimeFeature[feature],
            contains(record.id),
            reason: '${record.id} reverse runtime mapping',
          );
        }
        final expectedEntryIds = Feature.values
            .where(record.runtimeFeatures.contains)
            .map(
              (feature) =>
                  productionFeatureContract[feature]!.productionEntryId,
            )
            .where((entryId) => entryId.isNotEmpty)
            .toList(growable: false);
        expect(
          record.productionEntryIds.map((entryId) => entryId.value),
          expectedEntryIds,
          reason: '${record.id} production entries',
        );
        for (final entryId in record.productionEntryIds) {
          expect(entryId.value, isNotEmpty);
          expect(allowedProductionEntries, contains(entryId.value));
        }
      }
    });

    test('exposes immutable catalog and compatibility collections', () {
      expect(
        () => allTcasIdeaIntegrationCatalog.records.add(
          allTcasIdeaIntegrationCatalog.records.first,
        ),
        throwsUnsupportedError,
      );
      expect(
        () => allTcasIdeaIntegrationCatalog.records.first.runtimeFeatures.add(
          Feature.vocabulary,
        ),
        throwsUnsupportedError,
      );
      expect(
        () =>
            evidenceCompatibilityMatrix[ContractEvidenceClass
                    .assessment]![ProjectionFamily.masterySrs] =
                ProjectionDecision.allow,
        throwsUnsupportedError,
      );
    });
  });
}
