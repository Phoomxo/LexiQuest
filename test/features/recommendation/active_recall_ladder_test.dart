import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/recommendation/application/recall_ladder_use_cases.dart';
import 'package:vocab_learning_app/features/recommendation/domain/active_recall_ladder.dart';
import 'package:vocab_learning_app/features/recommendation/domain/recommendation_models.dart';
import 'package:vocab_learning_app/features/recommendation/domain/recommendation_policy.dart';

void main() {
  final now = DateTime.utc(2026, 8, 26, 12);

  RecallLadderObservation observation(
    int index,
    LessonMode mode,
    EvidenceClass evidenceClass, {
    bool successful = true,
    String ownerId = 'owner-1',
    String contentId = 'word-1',
    String? sourceEvidenceId,
    int recordVersion = 1,
    DateTime? observedAtUtc,
    RecommendationEvidenceReference? reference,
  }) {
    final sourceId = sourceEvidenceId ?? 'attempt:$index';
    final observed = observedAtUtc ?? now.subtract(Duration(hours: 10 - index));
    final canonicalReference = RecommendationEvidenceReference(
      source: RecommendationEvidenceSource.responseEvidenceReadModel,
      ownerId: ownerId,
      contentId: contentId,
      referenceId:
          'response:$sourceId:${mode.id}:${evidenceClass.name}:'
          '${successful ? 'success' : 'failure'}',
      version: 'response-v$recordVersion',
      capturedAtUtc: observed,
    );
    return RecallLadderObservation(
      mode: mode,
      evidenceClass: evidenceClass,
      successful: successful,
      sourceEvidenceId: sourceId,
      recordVersion: recordVersion,
      observedAtUtc: observed,
      evidenceReference: reference ?? canonicalReference,
    );
  }

  List<RecallLadderObservation> successfulPrefix(int length) {
    final observations = <RecallLadderObservation>[
      observation(0, LessonMode.flashcard, EvidenceClass.exposure),
      observation(1, LessonMode.meaningQuiz, EvidenceClass.recognition),
      observation(2, LessonMode.matching, EvidenceClass.recognition),
      observation(3, LessonMode.cloze, EvidenceClass.recognition),
      observation(4, LessonMode.typedRecall, EvidenceClass.independentRecall),
      observation(5, LessonMode.dictation, EvidenceClass.independentRecall),
      observation(6, LessonMode.speaking, EvidenceClass.pronunciation),
    ];
    return observations.take(length).toList(growable: false);
  }

  RecommendationEvidence evidence(
    List<RecallLadderObservation> observations, {
    String policyVersion = FlashcardFirstRecommendationPolicy.policyVersion,
    String ownerId = 'owner-1',
    String contentOwnerId = 'owner-1',
    String contentId = 'word-1',
    bool isUnseen = false,
    bool isMastered = false,
    DateTime? observedAtUtc,
    List<RecommendationEvidenceReference> extraReferences = const [],
  }) {
    final latest = observedAtUtc ?? now.subtract(const Duration(hours: 1));
    return RecommendationEvidence(
      policyVersion: policyVersion,
      ownerId: ownerId,
      contentOwnerId: contentOwnerId,
      contentId: contentId,
      confidence: isUnseen ? 0 : 0.8,
      isUnseen: isUnseen,
      isMastered: isMastered,
      observedAtUtc: latest,
      evaluatedAtUtc: now,
      evidenceReferences: <RecommendationEvidenceReference>[
        RecommendationEvidenceReference(
          source: RecommendationEvidenceSource.progressReadModel,
          ownerId: ownerId,
          contentId: contentId,
          referenceId: 'progress:$contentId',
          version: 'progress-v1',
          capturedAtUtc: latest,
        ),
        ...observations.map((entry) => entry.evidenceReference),
        ...extraReferences,
      ],
    );
  }

  RecallLadderProtocolLimits protocol({
    String ownerId = 'owner-1',
    String version = RecallLadderProtocolLimits.currentVersion,
    Set<LessonMode> lockedModes = const <LessonMode>{},
  }) => RecallLadderProtocolLimits(
    ownerId: ownerId,
    assignmentId: 'assignment-1',
    version: version,
    capturedAtUtc: now.subtract(const Duration(hours: 1)),
    lockedModes: lockedModes,
  );

  CanonicalRecallLadderSnapshot snapshot(
    List<RecallLadderObservation> observations, {
    String authorityVersion = CanonicalRecallLadderSnapshot.currentVersion,
    RecommendationEvidence? readEvidence,
    RecallLadderProtocolLimits? protocolLimits,
  }) => CanonicalRecallLadderSnapshot(
    authorityVersion: authorityVersion,
    evidence: readEvidence ?? evidence(observations),
    observations: observations,
    protocol: protocolLimits ?? protocol(),
  );

  Set<LessonMode> allLiveModes(LessonModeRegistry registry) => registry
      .registrations
      .where((registration) => registration.isDeliverable)
      .map((registration) => registration.mode)
      .toSet();

  RecallLadderUseCases useCases({
    CanonicalRecallLadderSnapshot? authoritySnapshot,
    LessonModeRegistry? registry,
    Set<LessonMode>? liveModes,
    bool throwOnRead = false,
  }) {
    final resolvedRegistry =
        registry ??
        buildLessonModeRegistry(
          matchingDeliveryState: LessonModeDeliveryState.enabled,
        );
    return RecallLadderUseCases(
      authority: _FakeRecallLadderAuthority(
        authoritySnapshot,
        throwOnRead: throwOnRead,
      ),
      registry: resolvedRegistry,
      liveEnabledModes: liveModes ?? allLiveModes(resolvedRegistry),
    );
  }

  Future<RecommendationDecision> recommend({
    int prefixLength = 0,
    CanonicalRecallLadderSnapshot? authoritySnapshot,
    RecallLadderUseCases? application,
    String ladderVersion = ActiveRecallLadder.policyVersion,
    RecallLadderAccessibility accessibility =
        const RecallLadderAccessibility.standard(),
  }) {
    final resolvedSnapshot =
        authoritySnapshot ?? snapshot(successfulPrefix(prefixLength));
    return (application ?? useCases(authoritySnapshot: resolvedSnapshot))
        .recommend(
          RecallLadderRequest(
            ladderVersion: ladderVersion,
            ownerId: 'owner-1',
            contentId: 'word-1',
            accessibility: accessibility,
          ),
        );
  }

  group('ActiveRecallLadder canonical authority', () {
    test(
      'deterministically recommends the next canonical typed mode',
      () async {
        const expected = <LessonMode>[
          LessonMode.flashcard,
          LessonMode.meaningQuiz,
          LessonMode.matching,
          LessonMode.cloze,
          LessonMode.typedRecall,
          LessonMode.dictation,
          LessonMode.speaking,
        ];

        for (
          var prefixLength = 0;
          prefixLength < expected.length;
          prefixLength++
        ) {
          final first = await recommend(prefixLength: prefixLength);
          final second = await recommend(prefixLength: prefixLength);

          expect(first.action, RecommendationAction.lessonMode);
          expect(first.recommendedMode, expected[prefixLength]);
          expect(first.reasonCode.value, 'recall_ladder_next_step');
          expect(second.action, first.action);
          expect(second.recommendedMode, first.recommendedMode);
          expect(second.reasonCode, first.reasonCode);
          expect(
            second.evidenceReferences.map((reference) => reference.referenceId),
            first.evidenceReferences.map((reference) => reference.referenceId),
          );
        }
      },
    );

    test('complete ladder and canonical mastery return no action', () async {
      final completeObservations = successfulPrefix(7);
      final complete = await recommend(
        authoritySnapshot: snapshot(completeObservations),
      );
      final masteredObservations = successfulPrefix(4);
      final mastered = await recommend(
        authoritySnapshot: snapshot(
          masteredObservations,
          readEvidence: evidence(
            masteredObservations,
            isMastered: true,
            extraReferences: <RecommendationEvidenceReference>[
              RecommendationEvidenceReference(
                source: RecommendationEvidenceSource.srsReadModel,
                ownerId: 'owner-1',
                contentId: 'word-1',
                referenceId: 'srs:word-1',
                version: 'srs-v1',
                capturedAtUtc: now.subtract(const Duration(hours: 1)),
              ),
            ],
          ),
        ),
      );

      expect(complete.action, RecommendationAction.noRecommendation);
      expect(
        complete.reasonCode,
        RecommendationReasonCode.recallLadderComplete,
      );
      expect(mastered.action, RecommendationAction.noRecommendation);
      expect(mastered.reasonCode, RecommendationReasonCode.masteredItem);
    });

    test('request exposes no observation or protocol override surface', () {
      final request = RecallLadderRequest(
        ladderVersion: ActiveRecallLadder.policyVersion,
        ownerId: 'owner-1',
        contentId: 'word-1',
        accessibility: const RecallLadderAccessibility.standard(),
      );

      expect(request.ownerId, 'owner-1');
      expect(request.contentId, 'word-1');
      expect(
        request.toString(),
        isNot(anyOf(contains('observations'), contains('lockedModes'))),
      );
    });

    test(
      'canonical guided or failed evidence cannot be relabelled to elevate',
      () async {
        final prefix = successfulPrefix(4);
        final canonicalGuided = <RecallLadderObservation>[
          ...prefix,
          observation(
            4,
            LessonMode.typedRecall,
            EvidenceClass.guidedPractice,
            successful: true,
          ),
        ];
        final canonicalFailed = <RecallLadderObservation>[
          ...prefix,
          observation(
            4,
            LessonMode.typedRecall,
            EvidenceClass.independentRecall,
            successful: false,
          ),
        ];

        for (final canonical in <List<RecallLadderObservation>>[
          canonicalGuided,
          canonicalFailed,
        ]) {
          final decision = await recommend(
            authoritySnapshot: snapshot(canonical),
          );

          expect(decision.action, RecommendationAction.learnerChoice);
          expect(
            decision.reasonCode,
            RecommendationReasonCode.circularRecommendationPrevented,
          );
          expect(
            decision.learnerChoiceModes,
            isNot(contains(LessonMode.typedRecall)),
          );
          expect(decision.recommendedMode, isNot(LessonMode.dictation));
        }
      },
    );

    test(
      'persisted protocol lock cannot be bypassed by caller state',
      () async {
        final prefix = successfulPrefix(2);
        final locked = snapshot(
          prefix,
          protocolLimits: protocol(
            lockedModes: <LessonMode>{LessonMode.matching},
          ),
        );
        final application = useCases(authoritySnapshot: locked);

        final decision = await application.recommend(
          RecallLadderRequest(
            ladderVersion: ActiveRecallLadder.policyVersion,
            ownerId: 'owner-1',
            contentId: 'word-1',
            accessibility: const RecallLadderAccessibility.standard(),
          ),
        );

        expect(decision.action, RecommendationAction.learnerChoice);
        expect(
          decision.reasonCode,
          RecommendationReasonCode.protocolLockedStep,
        );
        expect(
          decision.learnerChoiceModes,
          isNot(contains(LessonMode.matching)),
        );
      },
    );

    test('corrupt persisted protocol identity fails closed', () async {
      final observations = successfulPrefix(1);
      final corruptProtocol = RecallLadderProtocolLimits(
        ownerId: 'owner-1',
        assignmentId: ' assignment-1 ',
        version: RecallLadderProtocolLimits.currentVersion,
        capturedAtUtc: now.subtract(const Duration(hours: 1)),
      );

      final decision = await recommend(
        authoritySnapshot: snapshot(
          observations,
          protocolLimits: corruptProtocol,
        ),
      );

      expect(decision.action, RecommendationAction.noRecommendation);
      expect(
        decision.reasonCode,
        RecommendationReasonCode.invalidLadderEvidence,
      );
    });

    test(
      'canonical authority snapshot and protocol sets are immutable',
      () async {
        final observations = successfulPrefix(2).toList();
        final lockedModes = <LessonMode>{LessonMode.matching};
        final authoritySnapshot = snapshot(
          observations,
          protocolLimits: protocol(lockedModes: lockedModes),
        );
        observations.clear();
        lockedModes.clear();

        final decision = await recommend(authoritySnapshot: authoritySnapshot);

        expect(decision.action, RecommendationAction.learnerChoice);
        expect(
          decision.reasonCode,
          RecommendationReasonCode.protocolLockedStep,
        );
      },
    );

    test('missing, failed, or unknown authority fails closed', () async {
      final request = RecallLadderRequest(
        ladderVersion: ActiveRecallLadder.policyVersion,
        ownerId: 'owner-1',
        contentId: 'word-1',
        accessibility: const RecallLadderAccessibility.standard(),
      );
      final missing = await useCases(
        authoritySnapshot: null,
      ).recommend(request);
      final failed = await useCases(
        authoritySnapshot: snapshot(const <RecallLadderObservation>[]),
        throwOnRead: true,
      ).recommend(request);
      final unknown = await recommend(
        authoritySnapshot: snapshot(
          const <RecallLadderObservation>[],
          authorityVersion: 'recall-authority-v999',
        ),
      );

      expect(missing.action, RecommendationAction.noRecommendation);
      expect(
        missing.reasonCode,
        RecommendationReasonCode.canonicalAuthorityUnavailable,
      );
      expect(failed.action, RecommendationAction.noRecommendation);
      expect(
        failed.reasonCode,
        RecommendationReasonCode.canonicalAuthorityUnavailable,
      );
      expect(unknown.action, RecommendationAction.noRecommendation);
      expect(
        unknown.reasonCode,
        RecommendationReasonCode.unsupportedAuthorityVersion,
      );
    });

    test(
      'reference bindings reject relabel, outcome, and identity mismatch',
      () async {
        Future<RecommendationDecision> mismatched(
          RecommendationEvidenceReference Function(
            RecallLadderObservation canonical,
          )
          alter,
        ) {
          final canonical = observation(
            0,
            LessonMode.flashcard,
            EvidenceClass.exposure,
          );
          final changed = RecallLadderObservation(
            mode: canonical.mode,
            evidenceClass: canonical.evidenceClass,
            successful: canonical.successful,
            sourceEvidenceId: canonical.sourceEvidenceId,
            recordVersion: canonical.recordVersion,
            observedAtUtc: canonical.observedAtUtc,
            evidenceReference: alter(canonical),
          );
          return recommend(
            authoritySnapshot: snapshot(<RecallLadderObservation>[changed]),
          );
        }

        RecommendationEvidenceReference copy(
          RecallLadderObservation canonical, {
          String? referenceId,
          String? version,
          DateTime? capturedAtUtc,
        }) => RecommendationEvidenceReference(
          source: RecommendationEvidenceSource.responseEvidenceReadModel,
          ownerId: 'owner-1',
          contentId: 'word-1',
          referenceId: referenceId ?? canonical.evidenceReference.referenceId,
          version: version ?? canonical.evidenceReference.version,
          capturedAtUtc:
              capturedAtUtc ?? canonical.evidenceReference.capturedAtUtc,
        );

        final relabelled = await mismatched(
          (canonical) => copy(
            canonical,
            referenceId:
                'response:${canonical.sourceEvidenceId}:'
                '${LessonMode.typedRecall.id}:'
                '${EvidenceClass.independentRecall.name}:success',
          ),
        );
        final outcomeChanged = await mismatched(
          (canonical) => copy(
            canonical,
            referenceId: canonical.evidenceReference.referenceId.replaceFirst(
              ':success',
              ':failure',
            ),
          ),
        );
        final versionChanged = await mismatched(
          (canonical) => copy(canonical, version: 'response-v2'),
        );
        final timeChanged = await mismatched(
          (canonical) => copy(
            canonical,
            capturedAtUtc: canonical.observedAtUtc.add(
              const Duration(seconds: 1),
            ),
          ),
        );

        for (final decision in <RecommendationDecision>[
          relabelled,
          outcomeChanged,
          versionChanged,
          timeChanged,
        ]) {
          expect(decision.action, RecommendationAction.noRecommendation);
          expect(
            decision.reasonCode,
            RecommendationReasonCode.invalidEvidenceReference,
          );
        }
      },
    );

    test(
      'duplicate stale corrupt and cross-owner records fail closed',
      () async {
        final canonical = observation(
          0,
          LessonMode.flashcard,
          EvidenceClass.exposure,
        );
        final duplicate = await recommend(
          authoritySnapshot: snapshot(<RecallLadderObservation>[
            canonical,
            canonical,
          ]),
        );
        final staleObservation = observation(
          0,
          LessonMode.flashcard,
          EvidenceClass.exposure,
          observedAtUtc: now.subtract(const Duration(days: 31)),
        );
        final stale = await recommend(
          authoritySnapshot: snapshot(<RecallLadderObservation>[
            staleObservation,
          ]),
        );
        final corruptObservation = observation(
          0,
          LessonMode.flashcard,
          EvidenceClass.exposure,
          sourceEvidenceId: ' attempt:invalid',
        );
        final corrupt = await recommend(
          authoritySnapshot: snapshot(<RecallLadderObservation>[
            corruptObservation,
          ]),
        );
        final crossOwnerObservation = observation(
          0,
          LessonMode.flashcard,
          EvidenceClass.exposure,
          ownerId: 'owner-2',
        );
        final crossOwner = await recommend(
          authoritySnapshot: snapshot(<RecallLadderObservation>[
            crossOwnerObservation,
          ]),
        );
        final duplicateProgressReference = RecommendationEvidenceReference(
          source: RecommendationEvidenceSource.progressReadModel,
          ownerId: 'owner-1',
          contentId: 'word-1',
          referenceId: 'progress:word-1',
          version: 'progress-v1',
          capturedAtUtc: now.subtract(const Duration(hours: 1)),
        );
        final duplicateProgress = await recommend(
          authoritySnapshot: snapshot(
            const <RecallLadderObservation>[],
            readEvidence: evidence(
              const <RecallLadderObservation>[],
              extraReferences: <RecommendationEvidenceReference>[
                duplicateProgressReference,
              ],
            ),
          ),
        );
        final malformedProgress = await recommend(
          authoritySnapshot: snapshot(
            const <RecallLadderObservation>[],
            readEvidence: evidence(
              const <RecallLadderObservation>[],
              extraReferences: <RecommendationEvidenceReference>[
                RecommendationEvidenceReference(
                  source: RecommendationEvidenceSource.progressReadModel,
                  ownerId: 'owner-1',
                  contentId: 'word-1',
                  referenceId: 'not-progress',
                  version: 'progress-v0',
                  capturedAtUtc: now.subtract(const Duration(hours: 1)),
                ),
              ],
            ),
          ),
        );

        expect(
          duplicate.reasonCode,
          RecommendationReasonCode.invalidEvidenceReference,
        );
        expect(stale.reasonCode, RecommendationReasonCode.staleEvidence);
        expect(
          corrupt.reasonCode,
          RecommendationReasonCode.invalidEvidenceReference,
        );
        expect(
          crossOwner.reasonCode,
          RecommendationReasonCode.crossOwnerEvidence,
        );
        expect(
          duplicateProgress.reasonCode,
          RecommendationReasonCode.invalidEvidenceReference,
        );
        expect(
          malformedProgress.reasonCode,
          RecommendationReasonCode.invalidEvidenceReference,
        );
        for (final decision in <RecommendationDecision>[
          duplicate,
          stale,
          corrupt,
          crossOwner,
          duplicateProgress,
          malformedProgress,
        ]) {
          expect(decision.action, RecommendationAction.noRecommendation);
        }
      },
    );

    test(
      'source evidence identity uses the canonical learning boundary',
      () async {
        final prefix = 'attempt:';
        final accepted =
            '$prefix${'x' * (LearningEvidenceContract.maxSourceEvidenceIdLength - prefix.runes.length)}';
        final overlength = '${accepted}x';

        expect(accepted.runes, hasLength(197));
        expect(overlength.runes, hasLength(198));
        expect(
          LearningEvidenceContract.validSourceEvidenceId(accepted),
          isTrue,
        );

        final acceptedDecision = await recommend(
          authoritySnapshot: snapshot(<RecallLadderObservation>[
            observation(
              0,
              LessonMode.flashcard,
              EvidenceClass.exposure,
              sourceEvidenceId: accepted,
            ),
          ]),
        );
        final rejectedDecisions = await Future.wait(
          <String>[
            ' attempt:whitespace',
            'attempt:whitespace ',
            overlength,
          ].map(
            (sourceEvidenceId) => recommend(
              authoritySnapshot: snapshot(<RecallLadderObservation>[
                observation(
                  0,
                  LessonMode.flashcard,
                  EvidenceClass.exposure,
                  sourceEvidenceId: sourceEvidenceId,
                ),
              ]),
            ),
          ),
        );

        expect(acceptedDecision.action, RecommendationAction.lessonMode);
        expect(acceptedDecision.recommendedMode, LessonMode.meaningQuiz);
        for (final decision in rejectedDecisions) {
          expect(decision.action, RecommendationAction.noRecommendation);
          expect(
            decision.reasonCode,
            RecommendationReasonCode.invalidEvidenceReference,
          );
        }
      },
    );
  });

  group('ActiveRecallLadder chronology and fallback', () {
    test('permutations of the same evidence set are identical', () async {
      final canonical = successfulPrefix(4);
      final reversed = canonical.reversed.toList(growable: false);

      final ordered = await recommend(authoritySnapshot: snapshot(canonical));
      final reordered = await recommend(authoritySnapshot: snapshot(reversed));

      expect(reordered.action, ordered.action);
      expect(reordered.recommendedMode, ordered.recommendedMode);
      expect(reordered.reasonCode, ordered.reasonCode);
      expect(
        reordered.evidenceReferences.map((reference) => reference.referenceId),
        ordered.evidenceReferences.map((reference) => reference.referenceId),
      );
    });

    test('timestamp ties use stable source identity ordering', () async {
      final tiedAt = now.subtract(const Duration(hours: 4));
      final failedA = observation(
        1,
        LessonMode.meaningQuiz,
        EvidenceClass.recognition,
        successful: false,
        sourceEvidenceId: 'attempt:a',
        observedAtUtc: tiedAt,
      );
      final exposure = observation(
        0,
        LessonMode.flashcard,
        EvidenceClass.exposure,
        sourceEvidenceId: 'attempt:z-exposure',
        observedAtUtc: tiedAt.subtract(const Duration(hours: 1)),
      );
      final failedZ = observation(
        2,
        LessonMode.definitionQuiz,
        EvidenceClass.recognition,
        successful: false,
        sourceEvidenceId: 'attempt:z',
        observedAtUtc: tiedAt,
      );
      final first = await recommend(
        authoritySnapshot: snapshot(<RecallLadderObservation>[
          failedZ,
          exposure,
          failedA,
        ]),
      );
      final second = await recommend(
        authoritySnapshot: snapshot(<RecallLadderObservation>[
          failedA,
          failedZ,
          exposure,
        ]),
      );

      expect(first.action, RecommendationAction.learnerChoice);
      expect(second.action, first.action);
      expect(second.reasonCode, first.reasonCode);
      expect(second.learnerChoiceModes, first.learnerChoiceModes);
    });

    test(
      'higher-rung history with a gap recommends earliest unmet rung',
      () async {
        final history = <RecallLadderObservation>[
          observation(0, LessonMode.flashcard, EvidenceClass.exposure),
          observation(
            4,
            LessonMode.typedRecall,
            EvidenceClass.independentRecall,
          ),
          observation(5, LessonMode.dictation, EvidenceClass.independentRecall),
        ];

        final decision = await recommend(authoritySnapshot: snapshot(history));

        expect(decision.action, RecommendationAction.lessonMode);
        expect(decision.recommendedMode, LessonMode.meaningQuiz);
        expect(
          decision.reasonCode,
          RecommendationReasonCode.recallLadderNextStep,
        );
      },
    );

    test(
      'missing implemented-off and live-off modes use typed choices',
      () async {
        final prefix = successfulPrefix(2);
        final authoritySnapshot = snapshot(prefix);
        final enabled = buildLessonModeRegistry(
          matchingDeliveryState: LessonModeDeliveryState.enabled,
        );
        final missing = LessonModeRegistry(
          enabled.registrations.where(
            (registration) => registration.mode != LessonMode.matching,
          ),
        );
        final implementedOff = buildLessonModeRegistry();
        final liveOffModes = allLiveModes(enabled)..remove(LessonMode.matching);

        for (final application in <RecallLadderUseCases>[
          useCases(authoritySnapshot: authoritySnapshot, registry: missing),
          useCases(
            authoritySnapshot: authoritySnapshot,
            registry: implementedOff,
          ),
          useCases(
            authoritySnapshot: authoritySnapshot,
            registry: enabled,
            liveModes: liveOffModes,
          ),
        ]) {
          final decision = await application.recommend(
            RecallLadderRequest(
              ladderVersion: ActiveRecallLadder.policyVersion,
              ownerId: 'owner-1',
              contentId: 'word-1',
              accessibility: const RecallLadderAccessibility.standard(),
            ),
          );

          expect(decision.action, RecommendationAction.learnerChoice);
          expect(decision.reasonCode, RecommendationReasonCode.modeUnavailable);
          expect(decision.recommendedMode, isNull);
          expect(decision.learnerChoiceModes, isNotEmpty);
          expect(
            decision.learnerChoiceModes,
            isNot(contains(LessonMode.matching)),
          );
          expect(decision.learnerChoiceModes, everyElement(isA<LessonMode>()));
        }
      },
    );

    test(
      'speaking accessibility prefers typed and dictation when allowed',
      () async {
        final prefix = successfulPrefix(6);
        final noSpeechInput = await recommend(
          authoritySnapshot: snapshot(prefix),
          accessibility: const RecallLadderAccessibility(
            speechInputAvailable: false,
            audioPlaybackAvailable: true,
          ),
        );
        final dictationLocked = await recommend(
          authoritySnapshot: snapshot(
            prefix,
            protocolLimits: protocol(
              lockedModes: <LessonMode>{LessonMode.dictation},
            ),
          ),
          accessibility: const RecallLadderAccessibility(
            speechInputAvailable: false,
            audioPlaybackAvailable: true,
          ),
        );

        expect(noSpeechInput.action, RecommendationAction.learnerChoice);
        expect(
          noSpeechInput.reasonCode,
          RecommendationReasonCode.accessibilityAlternativeRequired,
        );
        expect(noSpeechInput.learnerChoiceModes, <LessonMode>[
          LessonMode.typedRecall,
          LessonMode.dictation,
        ]);
        expect(dictationLocked.learnerChoiceModes, <LessonMode>[
          LessonMode.typedRecall,
        ]);
      },
    );

    test(
      'speaking fallback expands to all earlier eligible accessible modes',
      () async {
        final prefix = successfulPrefix(6);
        final authoritySnapshot = snapshot(prefix);
        final registry = buildLessonModeRegistry(
          matchingDeliveryState: LessonModeDeliveryState.enabled,
        );
        final liveModes = allLiveModes(registry)
          ..remove(LessonMode.typedRecall)
          ..remove(LessonMode.dictation);
        final decision = await recommend(
          authoritySnapshot: authoritySnapshot,
          application: useCases(
            authoritySnapshot: authoritySnapshot,
            registry: registry,
            liveModes: liveModes,
          ),
          accessibility: const RecallLadderAccessibility(
            speechInputAvailable: false,
            audioPlaybackAvailable: true,
          ),
        );

        expect(decision.action, RecommendationAction.learnerChoice);
        expect(
          decision.reasonCode,
          RecommendationReasonCode.accessibilityAlternativeRequired,
        );
        expect(decision.learnerChoiceModes, <LessonMode>[
          LessonMode.flashcard,
          LessonMode.meaningQuiz,
          LessonMode.definitionQuiz,
          LessonMode.matching,
          LessonMode.cloze,
        ]);
      },
    );

    test(
      'locked preferred fallbacks expand without locked or live-off modes',
      () async {
        final prefix = successfulPrefix(6);
        final registry = buildLessonModeRegistry(
          matchingDeliveryState: LessonModeDeliveryState.enabled,
        );
        final liveModes = allLiveModes(registry)..remove(LessonMode.cloze);
        final authoritySnapshot = snapshot(
          prefix,
          protocolLimits: protocol(
            lockedModes: <LessonMode>{
              LessonMode.typedRecall,
              LessonMode.dictation,
              LessonMode.matching,
            },
          ),
        );
        final decision = await recommend(
          authoritySnapshot: authoritySnapshot,
          application: useCases(
            authoritySnapshot: authoritySnapshot,
            registry: registry,
            liveModes: liveModes,
          ),
          accessibility: const RecallLadderAccessibility(
            speechInputAvailable: false,
            audioPlaybackAvailable: true,
          ),
        );

        expect(decision.action, RecommendationAction.learnerChoice);
        expect(decision.learnerChoiceModes, <LessonMode>[
          LessonMode.flashcard,
          LessonMode.meaningQuiz,
          LessonMode.definitionQuiz,
        ]);
      },
    );

    test('unknown ladder policy or protocol version fails closed', () async {
      final observations = successfulPrefix(1);
      final unknownLadder = await recommend(
        authoritySnapshot: snapshot(observations),
        ladderVersion: 'f15-v999',
      );
      final unknownPolicy = await recommend(
        authoritySnapshot: snapshot(
          observations,
          readEvidence: evidence(observations, policyVersion: 'f14-v999'),
        ),
      );
      final unknownProtocol = await recommend(
        authoritySnapshot: snapshot(
          observations,
          protocolLimits: protocol(version: 'protocol-v999'),
        ),
      );

      expect(
        unknownLadder.reasonCode,
        RecommendationReasonCode.unsupportedLadderVersion,
      );
      expect(
        unknownPolicy.reasonCode,
        RecommendationReasonCode.unsupportedPolicyVersion,
      );
      expect(
        unknownProtocol.reasonCode,
        RecommendationReasonCode.unsupportedProtocolVersion,
      );
      expect(<RecommendationAction>[
        unknownLadder.action,
        unknownPolicy.action,
        unknownProtocol.action,
      ], everyElement(RecommendationAction.noRecommendation));
    });

    test(
      'decision remains advisory and preserves immutable canonical refs',
      () async {
        final observations = successfulPrefix(3);
        final readEvidence = evidence(observations);
        final authoritySnapshot = snapshot(
          observations,
          readEvidence: readEvidence,
        );

        final decision = await recommend(authoritySnapshot: authoritySnapshot);

        expect(decision.isAdvisory, isTrue);
        expect(decision.ownerId, readEvidence.ownerId);
        expect(decision.contentId, readEvidence.contentId);
        expect(decision.policyVersion, ActiveRecallLadder.policyVersion);
        expect(
          decision.evidenceReferences.map((reference) => reference.referenceId),
          unorderedEquals(
            readEvidence.evidenceReferences.map(
              (reference) => reference.referenceId,
            ),
          ),
        );
        expect(
          () => decision.evidenceReferences.add(
            readEvidence.evidenceReferences.first,
          ),
          throwsUnsupportedError,
        );
        expect(decision.reasonCode.value, isNotEmpty);
      },
    );
  });
}

final class _FakeRecallLadderAuthority
    implements RecallLadderCanonicalAuthority {
  const _FakeRecallLadderAuthority(this.snapshot, {this.throwOnRead = false});

  final CanonicalRecallLadderSnapshot? snapshot;
  final bool throwOnRead;

  @override
  Future<CanonicalRecallLadderSnapshot?> load({
    required String ownerId,
    required String contentId,
  }) async {
    if (throwOnRead) throw StateError('canonical authority unavailable');
    return snapshot;
  }
}
