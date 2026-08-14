import '../../runtime/production_feature_contract.dart';
import '../../runtime/registries/feature.dart';
import 'compatibility_profiles.dart';
import 'feature_contract_models.dart';

const String featureContractRevision = '1.0.0';
const String featureContractBaselineCommit = '61a4fec';
const int featureContractSchemaVersion = 1;
const String featureContractGeneratorVersion = '1.0.0';

const productContractIdsByRuntimeFeature = <Feature, Set<FeatureContractId>>{
  Feature.vocabulary: <FeatureContractId>{
    FeatureContractId.f01,
    FeatureContractId.f02,
    FeatureContractId.f03,
  },
  Feature.quiz: <FeatureContractId>{
    FeatureContractId.f07,
    FeatureContractId.f08,
    FeatureContractId.f09,
    FeatureContractId.f11,
  },
  Feature.srs: <FeatureContractId>{
    FeatureContractId.f06,
    FeatureContractId.f14,
    FeatureContractId.f22,
  },
  Feature.reading: <FeatureContractId>{FeatureContractId.f13},
  Feature.mastery: <FeatureContractId>{FeatureContractId.f36},
  Feature.weakness: <FeatureContractId>{FeatureContractId.f36},
  Feature.ghostDuel: <FeatureContractId>{FeatureContractId.f13},
  Feature.achievements: <FeatureContractId>{FeatureContractId.f31},
  Feature.shop: <FeatureContractId>{FeatureContractId.f32},
  Feature.objectScanner: <FeatureContractId>{FeatureContractId.f13},
  Feature.speechPractice: <FeatureContractId>{FeatureContractId.f13},
  Feature.aiTutor: <FeatureContractId>{
    FeatureContractId.f19,
    FeatureContractId.f33,
  },
  Feature.export: <FeatureContractId>{FeatureContractId.f40},
  Feature.shadowRewardV2: <FeatureContractId>{FeatureContractId.f29},
  Feature.questV2: <FeatureContractId>{FeatureContractId.f29},
};

final allTcasIdeaIntegrationCatalog = ProductFeatureCatalog.validated(
  revision: featureContractRevision,
  records: <ProductFeatureContract>[
    _record(
      id: FeatureContractId.f01,
      name: 'Curriculum & Learning Pack Catalog',
      purpose:
          'Discover and filter versioned packs by CEFR, topic, skill, and goal while referencing canonical Vocabulary IDs.',
      domain: FeatureDomain.learningContentAndPacks,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.infrastructure,
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.vocabulary,
      },
      authorityProfileId: vocabularyWriterAuthorityProfileId,
    ),
    _record(
      id: FeatureContractId.f02,
      name: 'Learning Pack Detail',
      purpose:
          'Explain pack level, content, progress, examples, and available activities before a session starts.',
      domain: FeatureDomain.learningContentAndPacks,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.neutral,
      dependencies: const <FeatureContractId>{FeatureContractId.f01},
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.vocabulary,
      },
    ),
    _record(
      id: FeatureContractId.f03,
      name: 'Rich Lexical Card',
      purpose:
          'Present canonical meanings, part of speech, CEFR, IPA, audio, examples, synonyms, and antonyms progressively.',
      domain: FeatureDomain.learningContentAndPacks,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{FeatureContractId.f01},
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.vocabulary,
      },
    ),
    _record(
      id: FeatureContractId.f04,
      name: 'Content Version & Quality Control',
      purpose:
          'Pin revision, provenance, review state, checksum, and publication status for reproducible learning and research.',
      domain: FeatureDomain.learningContentAndPacks,
      provenance: FeatureProvenance.lexiQuestControl,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.infrastructure,
      dependencies: const <FeatureContractId>{FeatureContractId.f01},
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.vocabulary,
      },
      activationProfileId: foundationActivationProfileId,
      rolloutProfileId: foundationRolloutProfileId,
    ),
    _record(
      id: FeatureContractId.f05,
      name: 'Unified Lesson Shell',
      purpose:
          'Own shared session state, progress, pause/resume, timer, audio actions, completion, and adapter boundaries.',
      domain: FeatureDomain.unifiedLearningExperience,
      provenance: FeatureProvenance.lexiQuestControl,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.infrastructure,
      dependencies: const <FeatureContractId>{FeatureContractId.f04},
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
        DomainAuthority.history,
      },
      authorityProfileId: responseEvidenceWriterAuthorityProfileId,
    ),
    _record(
      id: FeatureContractId.f06,
      name: 'Flashcard Mode',
      purpose:
          'Support exposure and self-rated recall through the existing SRS authority.',
      domain: FeatureDomain.unifiedLearningExperience,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.existing,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f03,
        FeatureContractId.f05,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
        DomainAuthority.masterySrs,
      },
      authorityProfileId: masterySrsWriterAuthorityProfileId,
      evidenceProfileId: flashcardEvidenceProfileId,
    ),
    _record(
      id: FeatureContractId.f07,
      name: 'Meaning Quiz',
      purpose:
          'Measure bidirectional meaning recognition without inventing a second quiz authority.',
      domain: FeatureDomain.unifiedLearningExperience,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.existing,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f03,
        FeatureContractId.f05,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
      },
      authorityProfileId: responseEvidenceWriterAuthorityProfileId,
      evidenceProfileId: recognitionEvidenceProfileId,
    ),
    _record(
      id: FeatureContractId.f08,
      name: 'Definition Quiz',
      purpose:
          'Practice English-definition recognition with explicit evidence calibration.',
      domain: FeatureDomain.unifiedLearningExperience,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f03,
        FeatureContractId.f05,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
      },
      authorityProfileId: responseEvidenceWriterAuthorityProfileId,
      evidenceProfileId: recognitionEvidenceProfileId,
    ),
    _record(
      id: FeatureContractId.f09,
      name: 'Cloze Test',
      purpose:
          'Practice contextual retrieval; selected and typed variants receive different evidence profiles.',
      domain: FeatureDomain.unifiedLearningExperience,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f03,
        FeatureContractId.f05,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
      },
      authorityProfileId: responseEvidenceWriterAuthorityProfileId,
      evidenceProfileId: clozeEvidenceProfileId,
    ),
    _record(
      id: FeatureContractId.f10,
      name: 'Matching Mode',
      purpose:
          'Train fluent recognition with lower mastery weight than independent recall.',
      domain: FeatureDomain.unifiedLearningExperience,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f03,
        FeatureContractId.f05,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
      },
      authorityProfileId: responseEvidenceWriterAuthorityProfileId,
      evidenceProfileId: recognitionEvidenceProfileId,
    ),
    _record(
      id: FeatureContractId.f11,
      name: 'Typed Recall / Writing',
      purpose:
          'Capture independent spelling and productive recall from meaning, audio, or context.',
      domain: FeatureDomain.unifiedLearningExperience,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f03,
        FeatureContractId.f05,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
        DomainAuthority.masterySrs,
      },
      authorityProfileId: responseEvidenceWriterAuthorityProfileId,
      evidenceProfileId: independentRecallEvidenceProfileId,
    ),
    _record(
      id: FeatureContractId.f12,
      name: 'Handwriting Scratchpad',
      purpose:
          'Provide local, ephemeral handwriting and self-checking without OCR or automatic mastery claims.',
      domain: FeatureDomain.unifiedLearningExperience,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f03,
        FeatureContractId.f05,
      },
    ),
    _record(
      id: FeatureContractId.f13,
      name: 'LexiQuest Native Modes Integration',
      purpose:
          'Adapt Dictation, Speaking, Shadowing, Reading, Scramble, and Associative Reading to the shared shell and evidence gateway.',
      domain: FeatureDomain.unifiedLearningExperience,
      provenance: FeatureProvenance.lexiQuestControl,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f03,
        FeatureContractId.f05,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
        DomainAuthority.masterySrs,
      },
      authorityProfileId: responseEvidenceWriterAuthorityProfileId,
      evidenceProfileId: nativeModesEvidenceProfileId,
    ),
    _record(
      id: FeatureContractId.f14,
      name: 'Flashcard-First Recommendation',
      purpose:
          'Recommend preparation before harder recall while preserving learner choice.',
      domain: FeatureDomain.recallFeedbackAndControl,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{FeatureContractId.f06},
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.masterySrs,
      },
    ),
    _record(
      id: FeatureContractId.f15,
      name: 'Active-Recall Ladder',
      purpose:
          'Sequence exposure, recognition, matching, cloze, typed recall, dictation, and speaking from evidence.',
      domain: FeatureDomain.recallFeedbackAndControl,
      provenance: FeatureProvenance.lexiQuestControl,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f06,
        FeatureContractId.f07,
        FeatureContractId.f08,
        FeatureContractId.f09,
        FeatureContractId.f10,
        FeatureContractId.f11,
        FeatureContractId.f13,
        FeatureContractId.f14,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
        DomainAuthority.masterySrs,
      },
    ),
    _record(
      id: FeatureContractId.f16,
      name: 'Session Configuration',
      purpose:
          'Configure item count, direction, difficulty, hints, time, and pack within protocol limits.',
      domain: FeatureDomain.recallFeedbackAndControl,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.infrastructure,
      dependencies: const <FeatureContractId>{FeatureContractId.f05},
    ),
    _record(
      id: FeatureContractId.f17,
      name: 'Immediate Answer Feedback',
      purpose:
          'Show accessible correct/incorrect feedback without creating an additional scored event.',
      domain: FeatureDomain.recallFeedbackAndControl,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.existing,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{FeatureContractId.f05},
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
      },
      evidenceProfileId: guidedPracticeEvidenceProfileId,
    ),
    _record(
      id: FeatureContractId.f18,
      name: 'Contrastive Distractor Explanation',
      purpose:
          "Explain the correct answer and the learner's selected distractor as guided feedback.",
      domain: FeatureDomain.recallFeedbackAndControl,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{FeatureContractId.f17},
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
      },
      evidenceProfileId: guidedPracticeEvidenceProfileId,
    ),
    _record(
      id: FeatureContractId.f19,
      name: 'Hint, Strategy & Context',
      purpose:
          'Record hint level and provide staged support without counting assisted work as independent recall.',
      domain: FeatureDomain.recallFeedbackAndControl,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{FeatureContractId.f17},
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
      },
      authorityProfileId: responseEvidenceWriterAuthorityProfileId,
      evidenceProfileId: guidedPracticeEvidenceProfileId,
    ),
    _record(
      id: FeatureContractId.f20,
      name: 'Bookmark / Save',
      purpose:
          'Preserve learner intent to revisit an item without classifying it as weakness.',
      domain: FeatureDomain.recallFeedbackAndControl,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.neutral,
      dependencies: const <FeatureContractId>{FeatureContractId.f03},
    ),
    _record(
      id: FeatureContractId.f21,
      name: 'Flag / Report Content',
      purpose:
          'Submit versioned quality reports for ambiguous or incorrect text, audio, answer, or explanation.',
      domain: FeatureDomain.recallFeedbackAndControl,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.infrastructure,
      dependencies: const <FeatureContractId>{FeatureContractId.f04},
    ),
    _record(
      id: FeatureContractId.f22,
      name: 'Review Center',
      purpose:
          'Compose saved, incorrect, due-SRS, and reported items while preserving the reason for each queue entry.',
      domain: FeatureDomain.reviewTimeAndAssessment,
      provenance: FeatureProvenance.adaptedToLexiQuest,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f06,
        FeatureContractId.f20,
        FeatureContractId.f21,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.masterySrs,
      },
    ),
    _record(
      id: FeatureContractId.f23,
      name: 'Focus Timer',
      purpose:
          'Create explicit focus intervals with start, pause, resume, and finish states.',
      domain: FeatureDomain.reviewTimeAndAssessment,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.measurement,
    ),
    _record(
      id: FeatureContractId.f24,
      name: 'Automatic Learning-Time Capture',
      purpose:
          'Measure active effort while excluding idle and background time from learning duration.',
      domain: FeatureDomain.reviewTimeAndAssessment,
      provenance: FeatureProvenance.adaptedToLexiQuest,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.measurement,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f05,
        FeatureContractId.f23,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
      },
      authorityProfileId: responseEvidenceWriterAuthorityProfileId,
    ),
    _record(
      id: FeatureContractId.f25,
      name: 'Learning Calendar & Weekly Analytics',
      purpose:
          'Present effort, accuracy, skill distribution, and trends as separate measures.',
      domain: FeatureDomain.reviewTimeAndAssessment,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.measurement,
      dependencies: const <FeatureContractId>{FeatureContractId.f24},
      authorityDependencies: const <DomainAuthority>{DomainAuthority.history},
      activationProfileId: readModelOnlyActivationProfileId,
    ),
    _record(
      id: FeatureContractId.f26,
      name: 'Goal / Test Countdown',
      purpose:
          'Track language-test, course, or personal learning deadlines without admission-score logic.',
      domain: FeatureDomain.reviewTimeAndAssessment,
      provenance: FeatureProvenance.adaptedToLexiQuest,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.neutral,
    ),
    _record(
      id: FeatureContractId.f27,
      name: 'Opt-in Study Reminder',
      purpose:
          'Schedule user-controlled reminders for due review or goals without punitive messaging.',
      domain: FeatureDomain.reviewTimeAndAssessment,
      provenance: FeatureProvenance.adaptedToLexiQuest,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.engagement,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f22,
        FeatureContractId.f26,
      },
    ),
    _record(
      id: FeatureContractId.f28,
      name: 'Learning Assessment & Progress Comparison',
      purpose:
          'Run versioned pre-learning and post-learning assessment and report their comparison separately from practice.',
      domain: FeatureDomain.reviewTimeAndAssessment,
      provenance: FeatureProvenance.lexiQuestControl,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.measurement,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f04,
        FeatureContractId.f05,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
        DomainAuthority.assessment,
      },
      authorityProfileId: assessmentWriterAuthorityProfileId,
      evidenceProfileId: assessmentEvidenceProfileId,
      activationProfileId: protocolAssignedActivationProfileId,
      rolloutProfileId: controlledRolloutProfileId,
      rollbackProfileId: protocolRollbackProfileId,
    ),
    _record(
      id: FeatureContractId.f29,
      name: 'Evidence-Based Quest',
      purpose:
          'Advance the existing Quest authority only from evidence allowed by the active policy.',
      domain: FeatureDomain.motivationAndEngagement,
      provenance: FeatureProvenance.adaptedToLexiQuest,
      coverage: FeatureCoverage.existing,
      researchRole: ResearchRole.engagement,
      dependencies: const <FeatureContractId>{FeatureContractId.f05},
      authorityDependencies: const <DomainAuthority>{DomainAuthority.quest},
      authorityProfileId: questWriterAuthorityProfileId,
    ),
    _record(
      id: FeatureContractId.f30,
      name: 'Gentle Streak',
      purpose:
          'Use the dedicated Streak authority with grace, freeze, and recovery rules that avoid punishment.',
      domain: FeatureDomain.motivationAndEngagement,
      provenance: FeatureProvenance.adaptedToLexiQuest,
      coverage: FeatureCoverage.existing,
      researchRole: ResearchRole.engagement,
      dependencies: const <FeatureContractId>{FeatureContractId.f24},
      authorityDependencies: const <DomainAuthority>{DomainAuthority.streak},
      authorityProfileId: streakWriterAuthorityProfileId,
    ),
    _record(
      id: FeatureContractId.f31,
      name: 'Achievement & Milestone',
      purpose:
          'Unlock durable milestones from eligible, idempotent learning evidence.',
      domain: FeatureDomain.motivationAndEngagement,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.existing,
      researchRole: ResearchRole.engagement,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f29,
        FeatureContractId.f30,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.lifetimeXp,
      },
    ),
    _record(
      id: FeatureContractId.f32,
      name: 'Avatar Level-Up & Cosmetic Unlock',
      purpose:
          'Connect lifetime progression to cosmetics while keeping XP and spendable Coins separate.',
      domain: FeatureDomain.motivationAndEngagement,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.engagement,
      dependencies: const <FeatureContractId>{FeatureContractId.f31},
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.lifetimeXp,
        DomainAuthority.spendableCoins,
      },
    ),
    _record(
      id: FeatureContractId.f33,
      name: 'Contextual Companion',
      purpose:
          'Use scripted, versioned reactions to session events before considering generative behavior.',
      domain: FeatureDomain.motivationAndEngagement,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.engagement,
      dependencies: const <FeatureContractId>{FeatureContractId.f05},
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.responseEvidence,
      },
    ),
    _record(
      id: FeatureContractId.f34,
      name: 'Achievement Share Card',
      purpose:
          'Generate an opt-in shareable artifact without creating an internal social network.',
      domain: FeatureDomain.motivationAndEngagement,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.engagement,
      dependencies: const <FeatureContractId>{FeatureContractId.f31},
    ),
    _record(
      id: FeatureContractId.f35,
      name: 'Learning Preference & Goal Quiz',
      purpose:
          'Set editable defaults from goals, available time, and activity preference without fixed learning-style labels.',
      domain: FeatureDomain.personalizationAndAccessibility,
      provenance: FeatureProvenance.adaptedToLexiQuest,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.neutral,
    ),
    _record(
      id: FeatureContractId.f36,
      name: 'Personal Learning Profile',
      purpose:
          'Read separate Mastery, SRS, effort, accuracy, weakness, and engagement projections.',
      domain: FeatureDomain.personalizationAndAccessibility,
      provenance: FeatureProvenance.alltcasConfirmed,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.measurement,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f06,
        FeatureContractId.f24,
        FeatureContractId.f25,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.masterySrs,
        DomainAuthority.history,
      },
      activationProfileId: readModelOnlyActivationProfileId,
    ),
    _record(
      id: FeatureContractId.f37,
      name: 'Recommendation Panel',
      purpose:
          'Explain the next suggested activity from canonical projections while allowing learner override.',
      domain: FeatureDomain.personalizationAndAccessibility,
      provenance: FeatureProvenance.lexiQuestControl,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f15,
        FeatureContractId.f36,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.masterySrs,
      },
      activationProfileId: readModelOnlyActivationProfileId,
    ),
    _record(
      id: FeatureContractId.f38,
      name: 'Accessibility',
      purpose:
          'Enforce scaling, screen-reader semantics, non-color cues, untimed alternatives, and input/media alternatives.',
      domain: FeatureDomain.personalizationAndAccessibility,
      provenance: FeatureProvenance.lexiQuestControl,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.infrastructure,
      dependencies: const <FeatureContractId>{FeatureContractId.f05},
      activationProfileId: foundationActivationProfileId,
      rolloutProfileId: foundationRolloutProfileId,
    ),
    _record(
      id: FeatureContractId.f39,
      name: 'Motion & Theme Controls',
      purpose: 'Support Light, Dark, System, and Reduced Motion consistently.',
      domain: FeatureDomain.personalizationAndAccessibility,
      provenance: FeatureProvenance.adaptedToLexiQuest,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.infrastructure,
      dependencies: const <FeatureContractId>{FeatureContractId.f38},
      activationProfileId: foundationActivationProfileId,
      rolloutProfileId: foundationRolloutProfileId,
    ),
    _record(
      id: FeatureContractId.f40,
      name: 'Local-First Operation',
      purpose:
          'Commit locally before cloud synchronization and preserve learning through outages and restarts.',
      domain: FeatureDomain.localReliabilityOfflineAndRollout,
      provenance: FeatureProvenance.lexiQuestControl,
      coverage: FeatureCoverage.existing,
      researchRole: ResearchRole.infrastructure,
      dependencies: const <FeatureContractId>{FeatureContractId.f04},
      authorityDependencies: const <DomainAuthority>{DomainAuthority.history},
    ),
    _record(
      id: FeatureContractId.f41,
      name: 'Feature Flag & Controlled Rollout',
      purpose:
          'Use the existing runtime registry for Internal → Pilot → Enabled rollout, kill switch, and fail-closed invocation.',
      domain: FeatureDomain.localReliabilityOfflineAndRollout,
      provenance: FeatureProvenance.lexiQuestControl,
      coverage: FeatureCoverage.existing,
      researchRole: ResearchRole.infrastructure,
      activationProfileId: foundationActivationProfileId,
      rolloutProfileId: foundationRolloutProfileId,
    ),
    _record(
      id: FeatureContractId.f42,
      name: 'Today Hub',
      purpose:
          'Compose assigned, due, resumable, and recommended work from canonical read models; it owns no progress metric.',
      domain: FeatureDomain.dailyContinuityAndHistory,
      provenance: FeatureProvenance.lexiQuestControl,
      coverage: FeatureCoverage.newCapability,
      researchRole: ResearchRole.neutral,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f22,
        FeatureContractId.f37,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.masterySrs,
        DomainAuthority.history,
      },
      activationProfileId: readModelOnlyActivationProfileId,
    ),
    _record(
      id: FeatureContractId.f43,
      name: 'Learning History',
      purpose:
          'Present immutable session/evidence history; replay creates a new session and never edits the original evidence.',
      domain: FeatureDomain.dailyContinuityAndHistory,
      provenance: FeatureProvenance.lexiQuestControl,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.measurement,
      dependencies: const <FeatureContractId>{FeatureContractId.f40},
      authorityDependencies: const <DomainAuthority>{DomainAuthority.history},
      activationProfileId: readModelOnlyActivationProfileId,
    ),
    _record(
      id: FeatureContractId.f44,
      name: 'Offline Content Manager',
      purpose:
          'Download, verify, pin, repair, and remove content/media versions without deleting learning evidence.',
      domain: FeatureDomain.localReliabilityOfflineAndRollout,
      provenance: FeatureProvenance.lexiQuestControl,
      coverage: FeatureCoverage.partial,
      researchRole: ResearchRole.infrastructure,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f04,
        FeatureContractId.f40,
      },
      authorityDependencies: const <DomainAuthority>{
        DomainAuthority.downloadState,
      },
      authorityProfileId: downloadStateWriterAuthorityProfileId,
    ),
  ],
  experimentalCandidates: <ExperimentalCandidate>[
    ExperimentalCandidate.validated(
      id: ExperimentalCandidateId.expP1,
      name: 'Protocol Candidate P1',
      purpose:
          'Reserve a protocol-assigned measurement candidate outside the production 8/44 catalog.',
      researchRole: ResearchRole.measurement,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f28,
        FeatureContractId.f41,
      },
      activationProfileId: protocolAssignedActivationProfileId,
      rolloutProfileId: experimentalRolloutProfileId,
      rollbackProfileId: protocolRollbackProfileId,
      verificationRefs: const <VerificationRef>[
        VerificationRef(
          'test/architecture/alltcas_idea_feature_contract_test.dart',
        ),
      ],
      introductionRevision: featureContractRevision,
    ),
    ExperimentalCandidate.validated(
      id: ExperimentalCandidateId.expP2,
      name: 'Protocol Candidate P2',
      purpose:
          'Reserve a protocol-assigned intervention candidate outside the production 8/44 catalog.',
      researchRole: ResearchRole.intervention,
      dependencies: const <FeatureContractId>{
        FeatureContractId.f13,
        FeatureContractId.f41,
      },
      activationProfileId: protocolAssignedActivationProfileId,
      rolloutProfileId: experimentalRolloutProfileId,
      rollbackProfileId: protocolRollbackProfileId,
      verificationRefs: const <VerificationRef>[
        VerificationRef(
          'test/architecture/alltcas_idea_feature_contract_test.dart',
        ),
      ],
      introductionRevision: featureContractRevision,
    ),
  ],
);

ProductFeatureContract _record({
  required FeatureContractId id,
  required String name,
  required String purpose,
  required FeatureDomain domain,
  required FeatureProvenance provenance,
  required FeatureCoverage coverage,
  required ResearchRole researchRole,
  Set<FeatureContractId> dependencies = const <FeatureContractId>{},
  Set<DomainAuthority> authorityDependencies = const <DomainAuthority>{},
  AuthorityProfileId authorityProfileId = readOnlyAuthorityProfileId,
  EvidenceProfileId evidenceProfileId = noEvidenceProfileId,
  ActivationProfileId? activationProfileId,
  RolloutProfileId? rolloutProfileId,
  RollbackProfileId? rollbackProfileId,
}) {
  final runtimeFeatures = _runtimeFeaturesFor(id);
  final hasRuntimeMapping = runtimeFeatures.isNotEmpty;
  return ProductFeatureContract.validated(
    id: id,
    name: name,
    purpose: purpose,
    domain: domain,
    provenance: provenance,
    coverage: coverage,
    researchRole: researchRole,
    runtimeFeatures: runtimeFeatures,
    dependencies: dependencies,
    authorityDependencies: authorityDependencies,
    authorityProfileId: authorityProfileId,
    evidenceProfileId: evidenceProfileId,
    lifecycleProfileId: _lifecycleProfileFor(coverage),
    activationProfileId:
        activationProfileId ??
        (hasRuntimeMapping
            ? runtimeFlaggedActivationProfileId
            : foundationActivationProfileId),
    rolloutProfileId:
        rolloutProfileId ??
        (hasRuntimeMapping
            ? existingRolloutProfileId
            : controlledRolloutProfileId),
    rollbackProfileId:
        rollbackProfileId ??
        (hasRuntimeMapping
            ? runtimeFlagRollbackProfileId
            : metadataOnlyRollbackProfileId),
    productionEntryIds: _productionEntryIdsFor(runtimeFeatures),
    verificationRefs: const <VerificationRef>[
      VerificationRef(
        'test/architecture/alltcas_idea_feature_contract_test.dart',
      ),
    ],
    introductionRevision: featureContractRevision,
  );
}

Set<Feature> _runtimeFeaturesFor(FeatureContractId id) =>
    Set<Feature>.unmodifiable(
      Feature.values.where(
        (feature) => productContractIdsByRuntimeFeature[feature]!.contains(id),
      ),
    );

List<ProductionEntryId> _productionEntryIdsFor(Set<Feature> runtimeFeatures) =>
    List<ProductionEntryId>.unmodifiable(
      Feature.values
          .where(runtimeFeatures.contains)
          .map(
            (feature) => productionFeatureContract[feature]!.productionEntryId,
          )
          .where((entryId) => entryId.isNotEmpty)
          .map(ProductionEntryId.new),
    );

LifecycleProfileId _lifecycleProfileFor(FeatureCoverage coverage) =>
    switch (coverage) {
      FeatureCoverage.existing => existingLifecycleProfileId,
      FeatureCoverage.partial => partialLifecycleProfileId,
      FeatureCoverage.newCapability => newCapabilityLifecycleProfileId,
    };
