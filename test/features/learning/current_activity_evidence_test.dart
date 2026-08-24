import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  test(
    'typed activity declarations cover the complete current-mode matrix',
    () async {
      final repository = _RecordingRepository();
      var nextId = 0;
      final learning = _learning(
        repository: repository,
        generateId: () => 'declaration-${++nextId}',
      );
      final adapter = CurrentActivityEvidenceAdapter(learning: learning);
      const expected = <CurrentActivityInput, EvidenceClass>{
        CurrentActivityInput.meaningMultipleChoice: EvidenceClass.recognition,
        CurrentActivityInput.srsRecall: EvidenceClass.independentRecall,
        CurrentActivityInput.typedRecall: EvidenceClass.independentRecall,
        CurrentActivityInput.associativeRecall: EvidenceClass.independentRecall,
        CurrentActivityInput.ghostDuel: EvidenceClass.recreational,
        CurrentActivityInput.speakToText: EvidenceClass.pronunciation,
        CurrentActivityInput.shadowing: EvidenceClass.pronunciation,
        CurrentActivityInput.readingExposure: EvidenceClass.exposure,
      };

      for (final input in CurrentActivityInput.values) {
        final pending = adapter.capture(
          input: input,
          sessionId: 'session-1',
          wordId: 'word-1',
          isCorrect: true,
          responseTimeMs: 17,
          attemptNumber: 1,
        );
        await pending.record();
        final context = repository.commands.last.evidenceContext;
        expect(context.evidenceClass, expected[input], reason: input.name);
        expect(
          context.classificationSource,
          EvidenceClassificationSource.legacyInferred,
          reason: input.name,
        );
      }
    },
  );

  test(
    'capture freezes identity, time, response, and provenance synchronously',
    () async {
      final rollout = _DelayedRolloutProvider();
      final research = _DelayedResearchStateProvider();
      final repository = _RecordingRepository();
      var now = DateTime.utc(2026, 8, 14, 9, 30, 0, 123);
      var source = 'frozen-1';
      final learning = _learning(
        repository: repository,
        generateId: () => source,
        nowUtc: () => now,
        eventContextProvider: research,
      );
      final adapter = CurrentActivityEvidenceAdapter(
        learning: learning,
        rolloutModeProvider: rollout,
        researchStateProvider: research,
      );

      final pending = adapter.capture(
        input: CurrentActivityInput.meaningMultipleChoice,
        sessionId: 'session-original',
        wordId: 'word-original',
        isCorrect: true,
        responseTimeMs: 321,
        attemptNumber: 2,
        providerProvenance: 'device-stt|en-US|v1',
        hintLevel: 1,
      );
      expect(pending.sourceEvidenceId, 'attempt:frozen-1');
      expect(pending.occurredAtUtc, DateTime.utc(2026, 8, 14, 9, 30, 0, 123));
      expect(rollout.calls, 0);
      expect(research.activityCalls, 0);

      source = 'mutated';
      now = DateTime.utc(2030);
      final write = pending.record();
      await rollout.entered.future;
      expect(pending.sourceEvidenceId, 'attempt:frozen-1');
      expect(pending.occurredAtUtc.year, 2026);
      rollout.complete(EvidencePolicyRolloutMode.shadow);
      await research.entered.future;
      research.complete(_researchSnapshot(pending.occurredAtUtc));
      await write;

      final command = repository.commands.single;
      expect(command.id, 'attempt:frozen-1');
      expect(command.occurredAtUtc, pending.occurredAtUtc);
      expect(command.sessionId, 'session-original');
      expect(command.wordId, 'word-original');
      expect(command.promptMode, 'meaningChoice');
      expect(command.isCorrect, isTrue);
      expect(command.responseTimeMs, 321);
      expect(command.attemptNumber, 2);
      expect(command.providerProvenance, 'device-stt|en-US|v1');
      expect(command.evidenceContext.hintLevel, 1);
      expect(research.ownerIds, ['owner-1']);
      expect(research.occurrences, [pending.occurredAtUtc]);
    },
  );

  test(
    'pending coalesces in-flight writes and requires explicit stable retry',
    () async {
      final rollout = _CountingRolloutProvider();
      final research = _CountingLegacyResearchStateProvider();
      final repository = _RecordingRepository(failFirst: true);
      final owners = _CountingOwnerRepository();
      final learning = _learning(
        owners: owners,
        repository: repository,
        eventContextProvider: research,
      );
      final pending =
          CurrentActivityEvidenceAdapter(
            learning: learning,
            rolloutModeProvider: rollout,
            researchStateProvider: research,
          ).capture(
            input: CurrentActivityInput.typedRecall,
            sessionId: 'session-1',
            wordId: 'word-1',
            isCorrect: false,
            responseTimeMs: 987,
            attemptNumber: 3,
            providerProvenance: 'keyboard|local|v1',
          );

      final first = pending.record();
      final concurrent = pending.record();
      expect(identical(first, concurrent), isTrue);
      await expectLater(first, throwsStateError);
      expect(pending.requiresRetry, isTrue);
      expect(pending.isResponseLocked, isTrue);
      expect(repository.commands, hasLength(1));

      await expectLater(pending.record(), throwsStateError);
      expect(repository.commands, hasLength(1));
      final result = await pending.retry();

      expect(result.inserted, isTrue);
      expect(pending.isCommitted, isTrue);
      expect(owners.calls, 1);
      expect(rollout.calls, 1);
      expect(research.activityCalls, 1);
      expect(repository.commands, hasLength(2));
      final original = repository.commands.first;
      final retry = repository.commands.last;
      expect(retry.id, original.id);
      expect(retry.occurredAtUtc, original.occurredAtUtc);
      expect(retry.sessionId, original.sessionId);
      expect(retry.wordId, original.wordId);
      expect(retry.promptMode, original.promptMode);
      expect(retry.isCorrect, original.isCorrect);
      expect(retry.responseTimeMs, original.responseTimeMs);
      expect(retry.attemptNumber, original.attemptNumber);
      expect(retry.providerProvenance, original.providerProvenance);
      expect(retry.evidenceContext.toJson(), original.evidenceContext.toJson());
    },
  );

  test(
    'failed resolution retry preserves the first owner-bound basis',
    () async {
      final owners = _ChangingOwnerRepository();
      final rollout = _CountingRolloutProvider();
      final research = _FailOnceResearchStateProvider();
      final repository = _RecordingRepository();
      var source = 'owner-bound-1';
      var now = DateTime.utc(2026, 8, 14, 9, 30, 0, 123);
      final learning = _learning(
        owners: owners,
        repository: repository,
        generateId: () => source,
        nowUtc: () => now,
        eventContextProvider: research,
      );
      final pending =
          CurrentActivityEvidenceAdapter(
            learning: learning,
            rolloutModeProvider: rollout,
            researchStateProvider: research,
          ).capture(
            input: CurrentActivityInput.typedRecall,
            sessionId: 'session-owner-1',
            wordId: 'word-owner-1',
            isCorrect: false,
            responseTimeMs: 654,
            attemptNumber: 4,
            providerProvenance: 'keyboard|local|v1',
            hintLevel: 2,
          );
      final frozenId = pending.sourceEvidenceId;
      final frozenOccurrence = pending.occurredAtUtc;

      await expectLater(pending.record(), throwsStateError);
      expect(owners.calls, 1);
      expect(research.ownerIds, ['owner-1']);

      owners.activeOwnerId = 'owner-2';
      source = 'mutated';
      now = DateTime.utc(2030);
      final result = await pending.retry();

      expect(result.inserted, isTrue);
      expect(owners.calls, 1);
      expect(rollout.ownerIds, ['owner-1', 'owner-1']);
      expect(research.ownerIds, ['owner-1', 'owner-1']);
      expect(research.inputs, [
        CurrentActivityInput.typedRecall,
        CurrentActivityInput.typedRecall,
      ]);
      expect(research.occurrences, [frozenOccurrence, frozenOccurrence]);
      final command = repository.commands.single;
      expect(command.ownerId, 'owner-1');
      expect(command.id, frozenId);
      expect(command.occurredAtUtc, frozenOccurrence);
      expect(command.sessionId, 'session-owner-1');
      expect(command.wordId, 'word-owner-1');
      expect(command.promptMode, 'typedRecall');
      expect(command.isCorrect, isFalse);
      expect(command.responseTimeMs, 654);
      expect(command.attemptNumber, 4);
      expect(command.providerProvenance, 'keyboard|local|v1');
      expect(command.evidenceContext.hintLevel, 2);
    },
  );

  test(
    'only a complete non-Legacy Ghost protocol may override class',
    () async {
      for (final mode in <EvidencePolicyRolloutMode>{
        EvidencePolicyRolloutMode.shadow,
        EvidencePolicyRolloutMode.enforced,
      }) {
        final repository = _RecordingRepository();
        final research = _FixedResearchStateProvider(
          _researchSnapshot(
            DateTime.utc(2026, 8, 14),
            override: EvidenceClass.guidedPractice,
          ),
        );
        final learning = _learning(
          repository: repository,
          eventContextProvider: research,
        );
        final adapter = CurrentActivityEvidenceAdapter(
          learning: learning,
          rolloutModeProvider: FixedEvidencePolicyRolloutModeProvider(mode),
          researchStateProvider: research,
        );

        final invalid = adapter.capture(
          input: CurrentActivityInput.meaningMultipleChoice,
          sessionId: 'session-1',
          wordId: 'word-1',
          isCorrect: true,
          responseTimeMs: 1,
          attemptNumber: 1,
        );
        await expectLater(invalid.record(), throwsStateError);

        final ghost = adapter.capture(
          input: CurrentActivityInput.ghostDuel,
          sessionId: 'session-1',
          wordId: 'word-1',
          isCorrect: true,
          responseTimeMs: 1,
          attemptNumber: 1,
        );
        await ghost.record();
        expect(
          repository.commands.last.evidenceContext.evidenceClass,
          EvidenceClass.guidedPractice,
        );
      }
    },
  );

  test('Legacy Ghost rejects a protocol evidence-class override', () async {
    final repository = _RecordingRepository();
    final research = _FixedResearchStateProvider(
      _researchSnapshot(
        DateTime.utc(2026, 8, 14),
        override: EvidenceClass.guidedPractice,
      ),
    );
    final pending =
        CurrentActivityEvidenceAdapter(
          learning: _learning(
            repository: repository,
            eventContextProvider: research,
          ),
          rolloutModeProvider:
              const FixedEvidencePolicyRolloutModeProvider.legacy(),
          researchStateProvider: research,
        ).capture(
          input: CurrentActivityInput.ghostDuel,
          sessionId: 'session-1',
          wordId: 'word-1',
          isCorrect: true,
          responseTimeMs: 1,
          attemptNumber: 1,
        );

    await expectLater(pending.record(), throwsStateError);
    expect(repository.commands, isEmpty);
  });

  test('non-Legacy Ghost rejects every incomplete protocol override', () async {
    final occurrence = DateTime.utc(2026, 8, 14);
    final incomplete = <String, CurrentActivityResearchSnapshot>{
      'consent': _researchSnapshot(
        occurrence,
        override: EvidenceClass.guidedPractice,
        researchConsentVersion: 0,
      ),
      'experiment': _researchSnapshot(
        occurrence,
        override: EvidenceClass.guidedPractice,
        includeExperimentContext: false,
      ),
      'protocolId': _researchSnapshot(
        occurrence,
        override: EvidenceClass.guidedPractice,
        protocolId: null,
      ),
      'protocolVersion': _researchSnapshot(
        occurrence,
        override: EvidenceClass.guidedPractice,
        protocolVersion: null,
      ),
      'experimentVersion': _researchSnapshot(
        occurrence,
        override: EvidenceClass.guidedPractice,
        experimentVersion: null,
      ),
      'assignmentId': _researchSnapshot(
        occurrence,
        override: EvidenceClass.guidedPractice,
        assignmentId: null,
      ),
    };

    for (final mode in <EvidencePolicyRolloutMode>{
      EvidencePolicyRolloutMode.shadow,
      EvidencePolicyRolloutMode.enforced,
    }) {
      for (final entry in incomplete.entries) {
        final repository = _RecordingRepository();
        final research = _FixedResearchStateProvider(entry.value);
        final pending =
            CurrentActivityEvidenceAdapter(
              learning: _learning(
                repository: repository,
                eventContextProvider: research,
              ),
              rolloutModeProvider: FixedEvidencePolicyRolloutModeProvider(mode),
              researchStateProvider: research,
            ).capture(
              input: CurrentActivityInput.ghostDuel,
              sessionId: 'session-1',
              wordId: 'word-1',
              isCorrect: true,
              responseTimeMs: 1,
              attemptNumber: 1,
            );

        await expectLater(
          pending.record(),
          throwsStateError,
          reason: '${mode.name}/${entry.key}',
        );
        expect(
          repository.commands,
          isEmpty,
          reason: '${mode.name}/${entry.key}',
        );
      }
    }
  });
}

LearningUseCases _learning({
  LocalOwnerRepository? owners,
  required LearningRepository repository,
  String Function()? generateId,
  DateTime Function()? nowUtc,
  LearningEventContextProvider? eventContextProvider,
}) {
  return LearningUseCases(
    owners: owners ?? _CountingOwnerRepository(),
    repository: repository,
    generateId: generateId ?? () => 'evidence-1',
    nowUtc: nowUtc ?? () => DateTime.utc(2026, 8, 14),
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    eventContextProvider: eventContextProvider,
  );
}

CurrentActivityResearchSnapshot _researchSnapshot(
  DateTime occurrence, {
  EvidenceClass? override,
  int researchConsentVersion = 1,
  bool includeExperimentContext = true,
  String? protocolId = 'evidence-pilot',
  String? protocolVersion = '1.0.0',
  int? experimentVersion = 1,
  String? assignmentId = 'assignment-1',
}) {
  return CurrentActivityResearchSnapshot(
    engagementAllowed: false,
    protocolEvidenceClassOverride: override,
    consentContext: ConsentContext(
      researchConsentVersion: researchConsentVersion,
      aiConsentGranted: false,
      voiceConsentGranted: false,
      socialConsentGranted: false,
    ),
    experimentContext: includeExperimentContext
        ? ExperimentContext(
            experimentId: 'evidence-eligibility',
            variantId: 'shadow',
            assignedAtUtc: occurrence.subtract(const Duration(minutes: 1)),
          )
        : null,
    protocolId: protocolId,
    protocolVersion: protocolVersion,
    experimentVersion: experimentVersion,
    assignmentId: assignmentId,
  );
}

final class _CountingOwnerRepository implements LocalOwnerRepository {
  int calls = 0;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    calls += 1;
    return LocalOwner(id: 'owner-1', createdAtUtc: DateTime.utc(2026));
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _ChangingOwnerRepository implements LocalOwnerRepository {
  int calls = 0;
  String activeOwnerId = 'owner-1';

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    calls += 1;
    return LocalOwner(id: activeOwnerId, createdAtUtc: DateTime.utc(2026));
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _RecordingRepository implements LearningRepository {
  _RecordingRepository({this.failFirst = false});

  final bool failFirst;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  bool _failed = false;

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (failFirst && !_failed) {
      _failed = true;
      throw StateError('simulated local write failure');
    }
    return AnswerRecordResult(
      inserted: true,
      isCorrect: command.isCorrect,
      srs: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DelayedRolloutProvider
    implements EvidencePolicyRolloutModeProvider {
  final Completer<void> entered = Completer<void>();
  final Completer<EvidencePolicyRolloutMode> _result =
      Completer<EvidencePolicyRolloutMode>();
  int calls = 0;

  void complete(EvidencePolicyRolloutMode mode) => _result.complete(mode);

  @override
  Future<EvidencePolicyRolloutMode> resolve({
    required String ownerId,
    required EvidenceContext? evidenceContext,
  }) {
    calls += 1;
    if (!entered.isCompleted) entered.complete();
    return _result.future;
  }
}

final class _CountingRolloutProvider
    implements EvidencePolicyRolloutModeProvider {
  int calls = 0;
  final List<String> ownerIds = <String>[];

  @override
  Future<EvidencePolicyRolloutMode> resolve({
    required String ownerId,
    required EvidenceContext? evidenceContext,
  }) async {
    calls += 1;
    ownerIds.add(ownerId);
    return EvidencePolicyRolloutMode.legacy;
  }
}

final class _FailOnceResearchStateProvider
    implements CurrentActivityResearchStateProvider {
  int activityCalls = 0;
  final List<String> ownerIds = <String>[];
  final List<CurrentActivityInput> inputs = <CurrentActivityInput>[];
  final List<DateTime> occurrences = <DateTime>[];

  @override
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required String ownerId,
    required CurrentActivityInput input,
    required DateTime occurredAtUtc,
    required EvidencePolicyRolloutMode rolloutMode,
  }) async {
    activityCalls += 1;
    ownerIds.add(ownerId);
    inputs.add(input);
    occurrences.add(occurredAtUtc);
    if (activityCalls == 1) {
      throw StateError('simulated research-state resolution failure');
    }
    return const CurrentActivityResearchSnapshot.legacyCompatibility();
  }

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async => throw StateError('adapter must reuse the activity snapshot');
}

final class _DelayedResearchStateProvider
    implements CurrentActivityResearchStateProvider {
  final Completer<void> entered = Completer<void>();
  final Completer<CurrentActivityResearchSnapshot> _result =
      Completer<CurrentActivityResearchSnapshot>();
  int activityCalls = 0;
  final List<String> ownerIds = <String>[];
  final List<DateTime> occurrences = <DateTime>[];

  void complete(CurrentActivityResearchSnapshot state) =>
      _result.complete(state);

  @override
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required String ownerId,
    required CurrentActivityInput input,
    required DateTime occurredAtUtc,
    required EvidencePolicyRolloutMode rolloutMode,
  }) {
    activityCalls += 1;
    ownerIds.add(ownerId);
    occurrences.add(occurredAtUtc);
    if (!entered.isCompleted) entered.complete();
    return _result.future;
  }

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async => throw StateError('adapter must reuse the activity snapshot');
}

final class _CountingLegacyResearchStateProvider
    implements CurrentActivityResearchStateProvider {
  int activityCalls = 0;

  @override
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required String ownerId,
    required CurrentActivityInput input,
    required DateTime occurredAtUtc,
    required EvidencePolicyRolloutMode rolloutMode,
  }) async {
    activityCalls += 1;
    return const CurrentActivityResearchSnapshot.legacyCompatibility();
  }

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async => LearningEventContext.noResearch(evidenceContext);
}

final class _FixedResearchStateProvider
    implements CurrentActivityResearchStateProvider {
  const _FixedResearchStateProvider(this.snapshot);

  final CurrentActivityResearchSnapshot snapshot;

  @override
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required String ownerId,
    required CurrentActivityInput input,
    required DateTime occurredAtUtc,
    required EvidencePolicyRolloutMode rolloutMode,
  }) async => snapshot;

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async => LearningEventContext(
    consentContext: snapshot.consentContext,
    experimentContext: snapshot.experimentContext,
    protocolId: snapshot.protocolId,
    protocolVersion: snapshot.protocolVersion,
    experimentVersion: snapshot.experimentVersion,
    assignmentId: snapshot.assignmentId,
    featureContractIdentity: FeatureContractIdentity(
      revision: evidenceContext.featureContractRevision,
      semanticHash: evidenceContext.featureContractHash,
    ),
  );
}
