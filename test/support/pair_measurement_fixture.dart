import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:vocab_learning_app/config/adventure_research_runtime_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/research/application/adventure_research_runtime.dart';
import 'package:vocab_learning_app/features/research/application/assigned_learning_event_context_provider.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/research/domain/research_permit_document.dart';
import 'package:vocab_learning_app/features/review/application/pair_review_deferral.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

import '../features/learning/pair_matching/pair_matching_source_composer_test.dart'
    as lexical;
import '../features/learning/pair_matching/pair_matching_evidence_contract_test.dart'
    show PairFaultRepository;
import 'motivation_research_fixture.dart';

enum PairMeasurementAuthority { active, absent, denied, expired, withdrawn }

/// Synthetic SQL/content/receipt boundary composed with real signature,
/// participation, measurement, configuration and Pair authorities.
/// The base fixture's string-comparison signature verifier is never used.
final class PairMeasurementFixture {
  final base = MotivationResearchFixture();
  static const owner = 'owner:a';
  AppDatabase get database => base.database;
  DateTime get now => base.now;
  set now(DateTime value) => base.now = value;
  late AdventureResearchRuntime research;
  late DriftLearningRepository real;
  PairMeasurementCloseFaultRepository? closeFaults;
  late LearningUseCases learning;
  late CurrentActivityEvidenceAdapter currentActivityEvidence;
  late PersistedEvidencePolicyRolloutModeProvider rollout;
  late PersistedSessionConfigurationProtocolProvider protocols;
  late PairMatchingExperienceRuntime runtime;
  late ResearchParticipationPermit permit;
  late TodayHubSnapshot today;
  final items = List<PairLexicalItem>.generate(4, (i) => lexical.fixture(i));
  late final allowlist = PairCuratedAllowlist(
    version: 'pm7-synthetic-v1',
    items: items,
  );
  final preferences = const PairDensityPreferences(
    ownerId: owner,
    learnerPreference: PairDensity.compact4,
  );
  int generatedIds = 0;
  int controllers = 0;
  int monotonicMicros = 0;

  Future<void> initialize({
    TodayExperiencePresentation presentation =
        TodayExperiencePresentation.adventure,
    PairMeasurementAuthority authority = PairMeasurementAuthority.active,
    bool evidenceProtocolEnabled = true,
    bool loseCloseAckOnce = false,
  }) async {
    await base.initialize(enroll: false);
    // Initial synthetic assignment, before signing/importing any permit.
    await (database.update(
      database.experimentAssignments,
    )..where((r) => r.ownerId.equals(owner))).write(
      ExperimentAssignmentsCompanion(cohort: Value(presentation.name)),
    );
    research = AdventureResearchRuntime.fromConfig(
      database,
      AdventureResearchRuntimeConfig.configured(
        study: base.study,
        issuerPublicKeys: _syntheticPublicKeys,
        receipts: base.authority,
      ),
      nowUtc: () => now,
    )!;
    permit = signedPermit(presentation: presentation);
    if (authority != PairMeasurementAuthority.absent) {
      await research.participation.importPermit(permit);
    }
    switch (authority) {
      case PairMeasurementAuthority.active:
      case PairMeasurementAuthority.absent:
        break;
      case PairMeasurementAuthority.denied:
        base.authority.receiptsActive = false;
      case PairMeasurementAuthority.expired:
        now = permit.expiresAtUtc.add(const Duration(milliseconds: 1));
      case PairMeasurementAuthority.withdrawn:
        await research.withdraw(owner);
    }
    final catalog = ResearchProtocolModeCatalog(
      mappings: evidenceProtocolEnabled
          ? const [
              ResearchProtocolModeMapping(
                protocolId: 'motivation',
                experimentId: 'motivation',
                experimentVersion: 1,
                protocolVersion: '1',
                consentVersion: 1,
                mode: EvidencePolicyRolloutMode.enforced,
              ),
            ]
          : const [],
    );
    final experiments = DriftExperimentRegistry(
      DriftExperimentAssignmentRepository(database),
    );
    final consents = DriftConsentRegistry(database);
    final assigned = AssignedLearningEventContextProvider(
      experimentRegistry: experiments,
      consentRegistry: consents,
      protocolModeCatalog: catalog,
    );
    rollout = PersistedEvidencePolicyRolloutModeProvider(
      experimentRegistry: experiments,
      consentRegistry: consents,
      protocolModeCatalog: catalog,
      currentActivityResearchStateProvider: assigned,
    );
    protocols = PersistedSessionConfigurationProtocolProvider(
      currentResearchState: assigned,
      rolloutMode: rollout,
      nowUtc: () => now,
      catalog: SessionConfigurationProtocolCatalog(
        baseline: const SessionConfigurationProtocolLimits.standard(),
        bindings: [
          for (final treatment in TodayExperiencePresentation.values)
            SessionConfigurationProtocolBinding(
              experimentId: 'motivation',
              experimentVersion: 1,
              cohort: treatment.name,
              protocolVersion: '1',
              consentVersion: 1,
              limits: const SessionConfigurationProtocolLimits.standard()
                  .copyWith(protocolId: 'motivation'),
            ),
        ],
      ),
    );
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'synthetic-category',
            ownerId: owner,
            name: 'Synthetic',
            normalizedName: 'synthetic',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final item in items) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: item.wordId,
              ownerId: owner,
              categoryId: 'synthetic-category',
              spelling: item.spelling,
              normalizedSpelling: item.spelling,
              meaning: item.meaning,
              normalizedMeaning: item.meaning,
              partOfSpeech: 'noun',
              contentRevision: Value(item.contentRevision),
              contentChecksumSha256: Value(item.checksum),
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
    real = DriftLearningRepository(database, rolloutModeProvider: rollout);
    LearningRepository repository = real;
    if (loseCloseAckOnce) {
      closeFaults = PairMeasurementCloseFaultRepository(real)
        ..afterWrite = true
        ..closeFault = true;
      repository = closeFaults!;
    }
    learning = LearningUseCases(
      owners: DriftLocalOwnerRepository(
        database,
        generateId: () => throw StateError('Unexpected new owner'),
        nowUtc: () => now,
      ),
      repository: repository,
      generateId: () => 'pm7-synthetic-${++generatedIds}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: '1', buildId: 'test'),
      eventContextProvider: assigned,
    );
    currentActivityEvidence = CurrentActivityEvidenceAdapter(
      learning: learning,
      rolloutModeProvider: rollout,
      researchStateProvider: rollout.currentActivityResearchStateProvider!,
    );
    runtime = PairMatchingExperienceRuntime(
      database: database,
      learning: learning,
      currentActivityEvidence: currentActivityEvidence,
      registry: buildLessonModeRegistry(
        internalPairMatching: true,
        matchingDeliveryState: LessonModeDeliveryState.enabled,
      ),
      createController: (adapter) {
        controllers++;
        return UnifiedLessonController(
          learning: learning,
          adapter: adapter,
          sessionPurposeReader: real,
        );
      },
      composer: PairMatchingSourceComposer(allowlist: allowlist),
      protocols: protocols,
      reviewDeferral: PairReviewDeferral(database),
      start: PairMatchingAtomicStartAdapter(
        repository: real,
        capability: InternalPairMatchingCapability(
          allowlist: allowlist,
          isEnabled: () => true,
        ),
      ),
      canStart: () => true,
      features: const BuildFeatureRegistry.allEnabled(),
      monotonicMicros: () => monotonicMicros,
    );
    today = TodayHubSnapshot(
      ownerId: owner,
      evaluatedAtUtc: now,
      sectionOrder: const [TodayHubSectionKind.review],
      resumableSession: null,
      assignedAssessment: null,
      reviewWork: [
        for (final item in items)
          TodayHubReviewWorkItem(
            item: ReviewQueueItem(
              snapshot: ReviewedLexicalContentSnapshot(
                identity: ContentIdentity(
                  type: ContentType.lexicalMetadata,
                  id: item.wordId,
                  revision: item.contentRevision,
                ),
                categoryId: 'synthetic-category',
                spelling: item.spelling,
                normalizedSpelling: item.spelling,
                meaning: item.meaning,
                normalizedMeaning: item.meaning,
                partOfSpeech: 'noun',
                cefrLevel: null,
                source: 'manual',
                isGlobal: false,
                coreChecksumSha256: item.checksum,
                provenance: ContentProvenance.userAuthored,
                reviewState: ContentReviewState.unreviewed,
                publicationState: ContentPublicationState.private,
                artifact: null,
              ),
              provenance: [
                ReviewReasonProvenance.due(
                  sourceId: 'synthetic-due:${item.wordId}',
                  dueAtUtc: now,
                ),
              ],
            ),
            recommendation: null,
          ),
      ],
      recommendation: TodayHubRecommendation(
        result: RecommendationPanelResult.unavailable(
          ownerId: owner,
          reason: RecommendationPanelReason.noEligibleActivity,
          freshness: RecommendationEvidenceFreshness.missing,
          protocolConstraint: RecommendationProtocolConstraint.open,
        ),
        isAuthoritative: false,
        mergedInto: null,
      ),
      goals: const [],
      reminders: const [],
      quests: const [],
      gentleStreak: null,
      dependencyStates: {
        for (final d in TodayHubDependency.values)
          d: TodayHubDependencyState.ready,
      },
    );
  }

  ResearchParticipationPermit signedPermit({
    TodayExperiencePresentation presentation =
        TodayExperiencePresentation.adventure,
  }) {
    final payload = <String, Object?>{
      ...jsonDecode(base.permit().canonicalPayload()) as Map<String, dynamic>,
      'assignedTreatment': presentation.name,
      'issuerKeyId': 'pm7-synthetic-only',
    };
    final bytes = utf8.encode(jsonEncode(payload));
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(_syntheticPrivateKey));
    final signature = signer.generateSignature(bytes) as ECSignature;
    final hex =
        '${signature.r.toRadixString(16).padLeft(64, '0')}'
        '${signature.s.toRadixString(16).padLeft(64, '0')}';
    return decodeResearchPermitDocument(
      jsonEncode({
        ...payload,
        'payloadSha256': sha256.convert(bytes).toString(),
        'signature': base64Encode([
          for (var i = 0; i < hex.length; i += 2)
            int.parse(hex.substring(i, i + 2), radix: 16),
        ]),
      }),
    );
  }

  /// Prior unassisted recall supplies real existing learning history. Pair's
  /// recognition policy cannot itself create an SRS/points replay baseline.
  /// Use the same persisted providers as the production SRS composition.
  Future<PendingCurrentActivityEvidence> recordPriorRecall() async {
    const sessionId = 'session:pm7-prior-recall';
    final occurredAtUtc = today.evaluatedAtUtc.subtract(
      const Duration(minutes: 5),
    );
    await real.startSession(
      LearningSessionDraft(
        id: sessionId,
        ownerId: owner,
        activityType: 'srsReview',
        startedAtUtc: occurredAtUtc,
        appVersion: '1',
        buildId: 'test',
      ),
    );
    final pending =
        CurrentActivityEvidenceAdapter(
          learning: learning,
          rolloutModeProvider: rollout,
          researchStateProvider: rollout.currentActivityResearchStateProvider!,
          nowUtc: () => occurredAtUtc,
        ).capture(
          ownerId: owner,
          input: CurrentActivityInput.srsRecall,
          sessionId: sessionId,
          wordId: items.first.wordId,
          isCorrect: true,
          responseTimeMs: 250,
          attemptNumber: 1,
        );
    await pending.record();
    // The configured fault wraps the subsequent Pair close, so close this
    // historical recall directly through its canonical repository authority.
    await real.finishSession(
      ownerId: owner,
      sessionId: sessionId,
      endedAtUtc: occurredAtUtc.add(const Duration(seconds: 1)),
    );
    return pending;
  }
}

/// Reuses the canonical fault fixture: only the close acknowledgement is lost;
/// all content, configuration, checkpoint and answer authority remains SQL.
final class PairMeasurementCloseFaultRepository extends PairFaultRepository
    implements
        PinnedLearningContentRepository,
        SessionConfiguredLearningRepository,
        LearningSessionLifecycleRepository {
  PairMeasurementCloseFaultRepository(super.delegate);

  final closeCalls =
      <({String ownerId, String sessionId, DateTime endedAtUtc})>[];

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) {
    closeCalls.add((
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    ));
    return super.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
  }

  @override
  Future<LearningSessionSummary?> getActiveSession({required String ownerId}) =>
      delegate.getActiveSession(ownerId: ownerId);

  @override
  Future<LearningSessionSummary?> loadSessionConfigurationState({
    required String ownerId,
    required String sessionId,
  }) => delegate.loadSessionConfigurationState(
    ownerId: ownerId,
    sessionId: sessionId,
  );

  @override
  Future<Duration> addSessionConfigurationActiveEffort({
    required String ownerId,
    required String sessionId,
    required String configurationIdentity,
    required Duration delta,
  }) => delegate.addSessionConfigurationActiveEffort(
    ownerId: ownerId,
    sessionId: sessionId,
    configurationIdentity: configurationIdentity,
    delta: delta,
  );

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) => delegate.abandonSession(
    ownerId: ownerId,
    sessionId: sessionId,
    abandonedAtUtc: abandonedAtUtc,
  );

  @override
  Future<List<QuizWord>> listPinnedQuizWords({
    required String ownerId,
    required List<String> wordIds,
  }) => delegate.listPinnedQuizWords(ownerId: ownerId, wordIds: wordIds);

  @override
  Future<List<QuizWord>> listExactPinnedQuizWords({
    required String ownerId,
    required List<PinnedQuizContent> content,
  }) => delegate.listExactPinnedQuizWords(ownerId: ownerId, content: content);
}

// Explicit non-production test key; never imported by application source.
final _syntheticCurve = ECCurve_secp256r1();
final _syntheticPrivateKey = ECPrivateKey(BigInt.one, _syntheticCurve);
final _syntheticPublicKeys = {
  'pm7-synthetic-only': _syntheticCurve.G
      .getEncoded(false)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(),
};
