import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:crypto/crypto.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../learning_packs/data/drift_learning_pack_repository.dart';
import '../../learning_packs/domain/learning_pack_repository.dart';
import '../../motivation/data/drift_learning_day_recorder.dart';
import '../../account_deletion/domain/account_deletion_contracts.dart';
import '../domain/learning_time_admission.dart';
import '../domain/accepted_quiz_plan.dart';
import '../../rewards/data/drift_reward_projection_rebuilder.dart';
import 'drift_learning_projection_rebuilder.dart';
import 'learning_session_lifecycle_observer.dart';
import '../domain/learning_evidence_contract.dart';
import '../domain/evidence_context.dart';
import '../domain/evidence_eligibility_policy.dart';
import '../domain/learning_models.dart';
import '../domain/cloze_content.dart';
import '../domain/sentence_scramble_content.dart';
import '../domain/native_sentence_source.dart';
import '../domain/learning_repository.dart';
import '../domain/srs_policy.dart';
import '../domain/matching_exercise.dart';

part 'drift_matching_repository.dart';

final class DriftLearningRepository
    implements
        LearningRepository,
        ConfiguredQuizRepository,
        LexicalQuizRepository,
        NativeExerciseRepository,
        AuthoredNativeExerciseRepository,
        SrsReviewRepository,
        CanonicalLearningTimeAdmissionRepository,
        SourceBoundVocabularyStartRepository {
  DriftLearningRepository(
    this.database, {
    SrsPolicy srsPolicy = const BinarySm2SrsPolicy(),
    this.lifecycleObserver,
    DriftOwnerWriteCoordinator? ownerWrites,
    this.lexicalContent,
  }) : _ownerWrites =
           ownerWrites ??
           DriftOwnerWriteCoordinator(
             database,
             nowUtc: () => DateTime.now().toUtc(),
           ),
       projections = DriftLearningProjectionRebuilder(
         database,
         srsPolicy: srsPolicy,
       ),
       rewardProjections = DriftRewardProjectionRebuilder(database) {
    if (!identical(database, _ownerWrites.database)) {
      throw ArgumentError(
        'Learning and owner coordinator must share a database',
      );
    }
    if (lifecycleObserver != null &&
        !identical(database, lifecycleObserver!.database)) {
      throw ArgumentError(
        'Learning and its lifecycle observer must share a database',
      );
    }
  }

  final db.AppDatabase database;
  final DriftLearningPackRepository? lexicalContent;
  final Expando<_LexicalIssuance> _lexicalBindings =
      Expando<_LexicalIssuance>();
  StreamSubscription<Set<TableUpdate>>? _configuredOwnerChanges;
  int _configuredOwnerEpoch = 0;
  final Expando<_DriftConfiguredQuizReadBinding> _quizCheckpointBindings =
      Expando<_DriftConfiguredQuizReadBinding>();

  void _trackConfiguredOwner() {
    // A read lease must outlive the transaction-local streams Drift closes at commit.
    _configuredOwnerChanges ??= Zone.root
        .run(
          () => database.tableUpdates(
            TableUpdateQuery.onTable(database.localOwners),
          ),
        )
        .listen(
          (_) => _configuredOwnerEpoch++,
          onError: (Object _) => _configuredOwnerEpoch++,
          onDone: () => _configuredOwnerEpoch++,
        );
  }

  final DriftOwnerWriteCoordinator _ownerWrites;
  final LearningSessionLifecycleObserver? lifecycleObserver;
  final DriftLearningProjectionRebuilder projections;
  final DriftRewardProjectionRebuilder rewardProjections;
  final Expando<_NativeIssuance> _nativeBindings = Expando<_NativeIssuance>();

  @override
  Future<ClozeSession?> prepareAuthoredCloze({
    required LearningSessionDraft session,
    String? categoryId,
    required ClozeVariant variant,
    required bool Function() stillCurrent,
  }) async =>
      await _prepareAuthoredNative(
            session,
            categoryId,
            stillCurrent,
            variant: variant,
          )
          as ClozeSession?;

  @override
  Future<SentenceScrambleSession?> prepareAuthoredSentenceScramble({
    required LearningSessionDraft session,
    String? categoryId,
    required bool Function() stillCurrent,
  }) async =>
      await _prepareAuthoredNative(session, categoryId, stillCurrent)
          as SentenceScrambleSession?;

  Future<AcceptedNativeExercise?> _prepareAuthoredNative(
    LearningSessionDraft session,
    String? categoryId,
    bool Function() stillCurrent, {
    ClozeVariant? variant,
  }) async {
    final reader = lexicalContent;
    if (reader == null) return null;
    if (!identical(reader.database, database) ||
        !identical(reader.ownerWrites, _ownerWrites)) {
      throw StateError(
        'Lexical content must share the canonical database and owner coordinator',
      );
    }
    _trackConfiguredOwner();
    final epoch = _configuredOwnerEpoch;
    bool current() => epoch == _configuredOwnerEpoch && stillCurrent();
    if (await _ownerWrites.hasAmbientTransaction()) {
      throw StateError(
        'Authored preparation requires an independent read boundary',
      );
    }
    if (!current()) throw StateError('Authored native owner changed');
    return _ownerWrites.writeForActiveOwner(
      expectedOwnerId: session.ownerId,
      write: () async {
        if (!current()) throw StateError('Authored native owner changed');
        String? cursor;
        while (true) {
          final words = await listQuizWords(
            ownerId: session.ownerId,
            categoryId: categoryId,
            afterWordId: cursor,
            limit: 100,
          );
          if (!current()) throw StateError('Authored native owner changed');
          if (words.isEmpty) return null;
          for (final word in words) {
            cursor = word.id;
            if (!(variant == null
                ? SentenceScrambleContent.supportsTarget(word.spelling)
                : ClozeContent.supportsTarget(word.spelling))) {
              continue;
            }
            CurrentLexicalContent? found;
            try {
              found = await reader.currentLexical(
                expectedOwnerId: session.ownerId,
                wordId: word.id,
                stillCurrent: current,
              );
            } on PackStorageException catch (error) {
              if ({
                PackStorageFailureCode.notFound,
                PackStorageFailureCode.staleContent,
                PackStorageFailureCode.conflict,
              }.contains(error.code)) {
                continue;
              }
              rethrow;
            }
            if (!current()) throw StateError('Authored native owner changed');
            if (found == null ||
                !found.pack.isInstalled ||
                found.pack.identityConflict ||
                found.pack.manifest.language.split('-').first != 'en' ||
                !_sameNativeWord(word, found)) {
              continue;
            }
            final pack = _nativePackPin(found);
            final target = LexicalEntryPin(
              snapshotId: found.binding.snapshotId,
              wordRevision: found.binding.wordRevision,
              word: word,
              entryJson: found.entry.canonicalJson,
            );
            for (var index = 0; index < target.entry.examples.length; index++) {
              final source = AuthoredSentenceSource(
                pack: pack,
                target: target,
                exampleIndex: index,
              );
              AcceptedNativeExercise exercise;
              ClozeContent? cloze;
              SentenceScrambleContent? scramble;
              try {
                if (variant == null) {
                  scramble = SentenceScrambleContent.authored(source);
                } else {
                  cloze = ClozeContent.authored(source);
                }
              } on FormatException {
                continue;
              }
              if (variant == null) {
                exercise = SentenceScrambleSession(
                  session: session,
                  word: word,
                  content: scramble!,
                );
              } else {
                if (variant == ClozeVariant.typed) {
                  exercise = TypedClozeSession(
                    session: session,
                    word: word,
                    content: cloze!,
                  );
                } else {
                  final choices = <QuizWord>[word];
                  String? peerCursor;
                  while (choices.length < 3) {
                    final peers = await listQuizWords(
                      ownerId: session.ownerId,
                      categoryId: word.categoryId,
                      afterWordId: peerCursor,
                      limit: 100,
                    );
                    if (!current()) {
                      throw StateError('Authored native owner changed');
                    }
                    if (peers.isEmpty) break;
                    for (final peer in peers) {
                      peerCursor = peer.id;
                      if (ClozeContent.supportsTarget(peer.spelling) &&
                          !choices.any(
                            (v) =>
                                v.spelling.toLowerCase() ==
                                peer.spelling.toLowerCase(),
                          )) {
                        choices.add(peer);
                      }
                      if (choices.length == 3) break;
                    }
                  }
                  if (choices.length != 3) break;
                  choices.sort((a, b) => a.id.compareTo(b.id));
                  final offset =
                      word.id.codeUnits.fold<int>(
                        0,
                        (sum, unit) => sum + unit,
                      ) %
                      choices.length;
                  exercise = ChoiceClozeSession(
                    session: session,
                    word: word,
                    content: cloze!,
                    choices: [...choices.skip(offset), ...choices.take(offset)],
                  );
                }
              }
              await _requireNativeTargets(exercise);
              if (!current()) throw StateError('Authored native owner changed');
              _nativeBindings[exercise] = _NativeIssuance(current);
              return exercise;
            }
          }
          if (words.length < 100) return null;
        }
      },
    );
  }

  LexicalPackPin _nativePackPin(CurrentLexicalContent found) => LexicalPackPin(
    ownerId: found.pack.ownerId,
    packVersionId: found.pack.id,
    packId: found.pack.manifest.packId,
    version: found.pack.manifest.version,
    packageSha256: found.pack.packageSha256,
    manifestSha256: sha256
        .convert(utf8.encode(found.pack.manifest.canonicalJson))
        .toString(),
  );

  bool _sameNativeWord(QuizWord word, CurrentLexicalContent found) =>
      found.word.id == word.id &&
      found.word.categoryId == word.categoryId &&
      found.word.spelling == word.spelling &&
      found.word.meaning == word.meaning &&
      found.word.partOfSpeech == word.partOfSpeech &&
      word.contentRevision ==
          'local-vocabulary-v1:${found.binding.wordRevision}';

  final Expando<_DriftSourceBoundVocabularyStart>
  _sourceBoundVocabularyLinkReceipts =
      Expando<_DriftSourceBoundVocabularyStart>();

  @override
  Future<CanonicalLearningTimeSessionLinkReceipt>
  readSourceBoundVocabularyStartReceipt(
    PreparedSourceBoundVocabularyStart intent, {
    required String expectedOwnerId,
    required bool Function() ownerStillCurrent,
  }) => database.transaction(() async {
    await _requireTimeReadOwner(expectedOwnerId, ownerStillCurrent);
    final original = _requireSourceBoundVocabularyStart(intent);
    if (!original.started ||
        original.ownerId != expectedOwnerId ||
        original.callerContext != LearningTimeCallerContext.ordinary) {
      throw StateError('Original acknowledged ordinary start is unavailable');
    }
    final row = await _requireSourceBoundVocabularyFacts(original);
    await _requireTimeOrdinarySession(row.id);
    final receipt = _DriftVocabularySessionLinkReceipt(
      ownerId: original.ownerId,
      sessionId: original.sessionId,
      activityType: original.session.activityType,
      sourceKind: original.source.sourceKind,
      sourceBindingJson: original.source.sourceBindingJson,
    );
    _sourceBoundVocabularyLinkReceipts[receipt] = original;
    await _requireTimeReadOwner(expectedOwnerId, ownerStillCurrent);
    return receipt;
  });

  @override
  Future<void> requireCanonicalLearningTimeSessionLinkReceipt(
    CanonicalLearningTimeSessionLinkReceipt receipt, {
    required String expectedOwnerId,
    required bool Function() ownerStillCurrent,
  }) async {
    if (receipt is CanonicalLearningTimeAdmission) {
      return requireCanonicalLearningTimeAdmission(
        receipt,
        expectedOwnerId: expectedOwnerId,
        ownerStillCurrent: ownerStillCurrent,
      );
    }
    await _requireTimeReadOwner(expectedOwnerId, ownerStillCurrent);
    final original = _sourceBoundVocabularyLinkReceipts[receipt];
    if (receipt is! _DriftVocabularySessionLinkReceipt ||
        original == null ||
        _sourceBoundVocabularyStarts[original] != true ||
        !original.started ||
        original.ownerId != expectedOwnerId ||
        receipt.ownerId != expectedOwnerId ||
        original.callerContext != LearningTimeCallerContext.ordinary) {
      throw StateError(
        'Original canonical session-link receipt is unavailable',
      );
    }
    final row = await _requireSourceBoundVocabularyFacts(original);
    await _requireTimeOrdinarySession(row.id);
    await _requireTimeReadOwner(expectedOwnerId, ownerStillCurrent);
  }

  final Expando<bool> _sourceBoundVocabularyStarts = Expando<bool>();

  @override
  Future<PreparedSourceBoundVocabularyStart> prepareSourceBoundVocabularyStart({
    required LearningSessionDraft session,
    required List<QuizWord> words,
    required QuizSession presentation,
    required VocabularyLearningTimeSourcePin source,
    required LearningTimeCallerContext callerContext,
    required bool Function() stillCurrent,
  }) => database.transaction(() async {
    await _requireTimeReadOwner(session.ownerId, stillCurrent);
    if (words.isEmpty ||
        words.length > 100 ||
        words.map((word) => word.id).toSet().length != words.length ||
        session.activityType != source.activityType ||
        presentation.id != session.id ||
        presentation.startedAtUtc != session.startedAtUtc ||
        presentation.configured != null ||
        presentation.questions.length != words.length ||
        source.targetPinsSha256 != learningTimeTargetPinsSha256(words)) {
      throw StateError('Source-bound canonical start facts differ');
    }
    _required(session.id, 'sessionId');
    _requiredUtc(session.startedAtUtc, 'startedAtUtc');
    _required(session.appVersion, 'appVersion');
    _required(session.buildId, 'buildId');
    for (var index = 0; index < words.length; index++) {
      if (_timeVocabularyWordIdentity(presentation.questions[index].word) !=
          _timeVocabularyWordIdentity(words[index])) {
        throw StateError('Source-bound displayed word differs');
      }
    }
    if (source case VoiceLearningTimeSourcePin()) {
      final actual = VoiceLearningTimeSourcePin.capture(
        sessionId: session.id,
        practiceKind: source.practiceKind,
        words: words,
      );
      if (source.sourceBindingJson != actual.sourceBindingJson) {
        throw StateError('Source-bound voice prompt differs');
      }
    }
    final prepared = _DriftSourceBoundVocabularyStart(
      session: session,
      words: List<QuizWord>.unmodifiable(words),
      presentation: QuizSession(
        id: presentation.id,
        startedAtUtc: presentation.startedAtUtc,
        questions: List<QuizQuestion>.unmodifiable([
          for (final question in presentation.questions)
            QuizQuestion(
              word: question.word,
              options: List<String>.unmodifiable(question.options),
            ),
        ]),
      ),
      source: source,
      callerContext: callerContext,
    );
    await _requireSourceBoundVocabularyTargets(prepared);
    _timeJson(jsonDecode(source.sourceBindingJson) as Map<String, Object?>);
    _sourceBoundVocabularyStarts[prepared] = true;
    await _requireTimeReadOwner(session.ownerId, stillCurrent);
    return prepared;
  });

  @override
  Future<QuizSession> startSourceBoundVocabularySession(
    PreparedSourceBoundVocabularyStart intent, {
    required bool Function() operationStillCurrent,
  }) async {
    final original = _requireSourceBoundVocabularyStart(intent);
    if (await _ownerWrites.hasAmbientTransaction()) {
      throw StateError('Canonical vocabulary start requires its own ACK');
    }
    await _requireTimeReadOwner(original.ownerId, operationStillCurrent);
    await _ownerWrites.writeForActiveOwner(
      expectedOwnerId: original.ownerId,
      write: () async {
        await _requireTimeReadOwner(original.ownerId, operationStillCurrent);
        final existing = await _session(original.sessionId);
        if (existing == null) {
          if (original.started) {
            throw StateError(
              'Acknowledged canonical vocabulary session is missing',
            );
          }
          await _requireSourceBoundVocabularyTargets(original);
          original.startAttempted = true;
          // Same guarded canonical operation used by _startWordPractice and
          // _startVocabularySession, once under the original fixed draft.
          await startSession(original.session);
        } else if (!original.startAttempted) {
          throw StateError(
            'Canonical start requires its original prepared intent',
          );
        }
        await _requireSourceBoundVocabularyFacts(original);
        await _requireTimeReadOwner(original.ownerId, operationStillCurrent);
      },
    );
    // A return here acknowledges this coordinator-owned transaction, rather
    // than an inherited outer transaction or the best-effort Study observer.
    await _requireTimeReadOwner(original.ownerId, operationStillCurrent);
    await _requireSourceBoundVocabularyFacts(original);
    original.started = true;
    return original.presentation;
  }

  _DriftSourceBoundVocabularyStart _requireSourceBoundVocabularyStart(
    PreparedSourceBoundVocabularyStart intent,
  ) {
    if (intent is! _DriftSourceBoundVocabularyStart ||
        _sourceBoundVocabularyStarts[intent] != true) {
      throw StateError('Original source-bound canonical start is unavailable');
    }
    return intent;
  }

  Future<db.LearningSession> _requireSourceBoundVocabularyFacts(
    _DriftSourceBoundVocabularyStart original,
  ) async {
    final row = await _session(original.sessionId);
    final draft = original.session;
    if (row == null ||
        row.ownerId != draft.ownerId ||
        row.activityType != draft.activityType ||
        row.startedAtUtcMs != draft.startedAtUtc?.millisecondsSinceEpoch ||
        row.appVersion != draft.appVersion ||
        row.buildId != draft.buildId ||
        row.acceptedPlanId != null ||
        row.acceptedPlanJson != null ||
        row.checkpointRevision != 0 ||
        row.checkpointJson != null ||
        (row.state != 'active' && row.state != 'completed')) {
      throw StateError('Original source-bound canonical facts changed');
    }
    return row;
  }

  Future<void> _requireSourceBoundVocabularyTargets(
    _DriftSourceBoundVocabularyStart original,
  ) async {
    final current = await listQuizWords(
      ownerId: original.ownerId,
      wordIds: original.words.map((word) => word.id),
      limit: original.words.length,
    );
    final byId = {for (final word in current) word.id: word};
    if (current.length != original.words.length) {
      throw StateError('Original source-bound vocabulary is unavailable');
    }
    for (final expected in original.words) {
      final actual = byId[expected.id];
      if (actual == null ||
          _timeVocabularyWordIdentity(actual) !=
              _timeVocabularyWordIdentity(expected)) {
        throw StateError('Original source-bound vocabulary changed');
      }
    }
  }

  String _timeVocabularyWordIdentity(QuizWord word) => _timeDigest([
    word.id,
    word.categoryId,
    word.spelling,
    word.meaning,
    word.partOfSpeech,
    word.contentRevision,
  ]);

  final Expando<_CanonicalTimeBinding> _canonicalTimeBindings =
      Expando<_CanonicalTimeBinding>();

  @override
  Future<CanonicalLearningTimeAdmission> admitCanonicalLearningTime(
    CanonicalLearningTimeAdmissionRequest request, {
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async {
    if (await _ownerWrites.hasAmbientTransaction()) {
      throw StateError('Learning-time admission requires a committed source');
    }
    return database.transaction(() async {
      await _requireTimeReadOwner(expectedOwnerId, stillCurrent);
      if (request.callerContext != LearningTimeCallerContext.ordinary) {
        throw StateError('Ordinary learning-time context is unavailable');
      }
      late db.LearningSession row;
      late CanonicalLearningTimeSourceKind kind;
      late EvidenceContext evidence;
      late Map<String, Object?> source;
      late Map<String, Object?> context;
      switch (request) {
        case MatchingTimeAdmission(:final state):
          if (state is! _DriftMatchingState ||
              !identical(state.issuer.canonical, this) ||
              !state.lease.current) {
            throw StateError('Original matching time context is unavailable');
          }
          final saved = await state.issuer._read(
            state.plan.session.id,
            expectedOwnerId,
            state.lease,
          );
          if (saved.checkpoint.phase != MatchingPhase.selecting ||
              saved.revision != state.revision ||
              saved.plan.id != state.plan.id ||
              saved.checkpoint.stableSerialization !=
                  state.checkpoint.stableSerialization) {
            throw StateError('Original matching board changed');
          }
          row = (await _session(saved.plan.session.id))!;
          kind = CanonicalLearningTimeSourceKind.matching;
          evidence = saved.plan.evidence;
          source = {
            'schemaVersion': 1,
            'kind': kind.name,
            'sessionId': row.id,
            'activityType': row.activityType,
            'acceptedPlanId': saved.plan.id,
          };
          context = {
            'schemaVersion': 1,
            'checkpointRevision': saved.revision,
            'attemptCount': saved.checkpoint.attemptCount,
            'phase': MatchingPhase.selecting.name,
            'promptMode': MatchingPlan.promptMode,
            'evidenceContext': evidence.toJson(),
          };
        case ConfiguredQuizTimeAdmission(:final state):
          final saved = await _loadQuiz(state.sessionId, expectedOwnerId);
          if (saved.state != 'active' ||
              saved.checkpoint is! AwaitingQuizAnswer ||
              !saved.plan.supportsCurrentPolicy ||
              saved.plan.id != state.plan.id ||
              saved.plan.stableSerialization !=
                  state.plan.stableSerialization ||
              saved.checkpointRevision != state.checkpointRevision ||
              saved.checkpoint.stableSerialization !=
                  state.checkpoint.stableSerialization) {
            throw StateError('Original acknowledged quiz context changed');
          }
          row = (await _session(saved.sessionId))!;
          final ordinal = saved.checkpoint.questionOrdinal;
          final question = saved.plan.questions[ordinal];
          final word = question.word;
          final hint = saved.checkpoint.assistance.hintFirstShownAtUtcMs == null
              ? 0
              : 1;
          kind = CanonicalLearningTimeSourceKind.configuredQuiz;
          evidence = EvidenceContext.forNewEvidence(
            evidenceClass: hint == 0
                ? question.unassistedEvidenceClass
                : EvidenceClass.guidedPractice,
            skillId: question.skillId,
            hintLevel: hint,
            contentRevision: question.evidenceContentRevision,
            rolloutMode: EvidencePolicyRolloutMode.legacy,
          );
          source = {
            'schemaVersion': 1,
            'kind': kind.name,
            'sessionId': row.id,
            'activityType': row.activityType,
            'acceptedPlanId': saved.plan.id,
          };
          context = {
            'schemaVersion': 1,
            'questionOrdinal': ordinal,
            'checkpointRevision': saved.checkpointRevision,
            'wordId': word.id,
            'contentRevision': question.evidenceContentRevision,
            'promptMode': question.promptMode,
            'phase': 'awaitingAnswer',
            'evidenceContext': evidence.toJson(),
          };
        case OwnedSrsTimeAdmission(:final review, :final cardIndex):
          final binding = _srsBinding(review);
          final facts = await _requireSrsFacts(review, binding);
          if (!binding.started ||
              binding.closing != null ||
              facts.session.state != 'active' ||
              cardIndex != facts.attempts.length ||
              cardIndex < 0 ||
              cardIndex >= review.words.length) {
            throw StateError('Original acknowledged SRS context changed');
          }
          await _requireSrsTargets(review, [cardIndex]);
          row = facts.session;
          final word = review.words[cardIndex];
          kind = CanonicalLearningTimeSourceKind.ownedSrs;
          evidence = EvidenceContext.forNewEvidence(
            evidenceClass: EvidenceClass.independentRecall,
            skillId: 'srs-recall',
            hintLevel: 0,
            contentRevision: word.contentRevision!,
            rolloutMode: EvidencePolicyRolloutMode.legacy,
          );
          source = {
            'schemaVersion': 1,
            'kind': kind.name,
            'sessionId': row.id,
            'selection': review.selection.name,
            'deckPinsSha256': _timeDigest([
              for (final word in review.words)
                [word.id, word.categoryId, word.contentRevision],
            ]),
          };
          context = {
            'schemaVersion': 1,
            'cardIndex': cardIndex,
            'phase': request.phase.name,
            'wordId': word.id,
            'contentRevision': word.contentRevision,
            'promptMode': 'srsRecall',
            'evidenceContext': evidence.toJson(),
          };
        case SourceBoundVocabularyTimeAdmission(:final start, :final wordIndex):
          final original = _requireSourceBoundVocabularyStart(start);
          if (!original.started ||
              original.callerContext != LearningTimeCallerContext.ordinary ||
              original.ownerId != expectedOwnerId ||
              wordIndex < 0 ||
              wordIndex >= original.words.length) {
            throw StateError(
              'Acknowledged ordinary vocabulary source is unavailable',
            );
          }
          row = await _requireSourceBoundVocabularyFacts(original);
          if (row.state != 'active') {
            throw StateError('Canonical vocabulary source has completed');
          }
          await _requireSourceBoundVocabularyTargets(original);
          final word = original.words[wordIndex];
          final (prompt, evidenceClass, skill) = switch (original.source) {
            ReadingLearningTimeSourcePin() => throw StateError(
              'Reading collection requires its actual displayed snapshot source',
            ),
            VoiceLearningTimeSourcePin(:final practiceKind) => (
              practiceKind == VoiceLearningTimePracticeKind.shadowing
                  ? 'shadowing'
                  : 'pronunciationTranscript',
              EvidenceClass.pronunciation,
              practiceKind == VoiceLearningTimePracticeKind.shadowing
                  ? 'shadowing-pronunciation'
                  : 'pronunciation-transcript',
            ),
          };
          kind = original.source.sourceKind;
          evidence = EvidenceContext.forNewEvidence(
            evidenceClass: evidenceClass,
            skillId: skill,
            hintLevel: 0,
            contentRevision: word.contentRevision!,
            rolloutMode: EvidencePolicyRolloutMode.legacy,
          );
          source =
              jsonDecode(original.source.sourceBindingJson)
                  as Map<String, Object?>;
          context = {
            'schemaVersion': 1,
            'wordIndex': wordIndex,
            'wordId': word.id,
            'contentRevision': word.contentRevision,
            'promptMode': prompt,
            'evidenceContext': evidence.toJson(),
          };
        case NativeLearningTimeAdmission(:final exercise, :final hintLevel):
          _requireNativeBinding(exercise);
          final saved = await _loadNative(
            exercise.id,
            expectedOwnerId,
            issued: exercise,
          );
          if (exercise is WordScrambleSession ||
              exercise is SentenceScrambleSession ||
              hintLevel < 0 ||
              hintLevel > 2 ||
              saved.checkpoint is! AwaitingNativeAnswer ||
              !_nativeCurrent(exercise, stillCurrent)) {
            throw StateError('Native learning-time context is unavailable');
          }
          row = await _requireNativeSession(exercise);
          await _requireNativeTargets(exercise);
          final attempts = await (database.select(
            database.answerAttempts,
          )..where((attempt) => attempt.sessionId.equals(exercise.id))).get();
          if (row.state != 'active' || attempts.isNotEmpty) {
            throw StateError(
              'Original native prompt is no longer accepting input',
            );
          }
          final (prompt, evidenceClass, skill, actualHint) = switch (exercise) {
            DictationSession() => (
              'dictation',
              hintLevel == 0 && !saved.checkpoint.draft.assisted
                  ? EvidenceClass.independentRecall
                  : EvidenceClass.guidedPractice,
              'dictation-spelling',
              hintLevel == 0 && !saved.checkpoint.draft.assisted ? 0 : 1,
            ),
            TypedClozeSession() => (
              'clozeTyped',
              EvidenceClass.guidedPractice,
              'cloze-context',
              1,
            ),
            ChoiceClozeSession() => (
              'clozeChoice',
              EvidenceClass.recognition,
              'cloze-context',
              0,
            ),
            _ => throw StateError('Unsupported native learning-time source'),
          };
          kind = exercise is DictationSession
              ? CanonicalLearningTimeSourceKind.dictation
              : CanonicalLearningTimeSourceKind.cloze;
          evidence = EvidenceContext.forNewEvidence(
            evidenceClass: evidenceClass,
            skillId: skill,
            hintLevel: actualHint,
            contentRevision: exercise.evidenceContentRevision,
            rolloutMode: EvidencePolicyRolloutMode.legacy,
          );
          source = {
            'schemaVersion': 1,
            'kind': kind.name,
            'sessionId': row.id,
            'wordId': exercise.word.id,
            'wordContentRevision': exercise.wordContentRevision,
            'evidenceContentRevision': exercise.evidenceContentRevision,
          };
          context = {
            'schemaVersion': 2,
            'checkpointRevision': saved.checkpointRevision,
            'wordId': exercise.word.id,
            'promptMode': prompt,
            'evidenceContext': evidence.toJson(),
          };
      }
      if (row.ownerId != expectedOwnerId) {
        throw StateError('Learning-time owner changed');
      }
      await _requireTimeOrdinarySession(row.id);
      final decision = EvidenceProjectionDecision.resolve(
        context: evidence,
        projection: LearningProjection.activeLearningEffort,
      );
      if (!decision.isEligible) {
        throw StateError('Evidence is ineligible for active learning effort');
      }
      final proof = _DriftCanonicalLearningTimeAdmission(
        ownerId: row.ownerId,
        sessionId: row.id,
        activityType: row.activityType,
        sourceKind: kind,
        sourceBindingJson: _timeJson(source),
        contextBindingJson: _timeJson(context),
        evidenceContext: evidence,
      );
      _canonicalTimeBindings[proof] = _CanonicalTimeBinding(
        request: request,
        sessionFingerprint: _timeSessionFingerprint(row),
      );
      await _requireTimeReadOwner(expectedOwnerId, stillCurrent);
      return proof;
    });
  }

  @override
  Future<void> requireLiveCanonicalLearningTimeAdmission(
    CanonicalLearningTimeAdmission admission, {
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async {
    final original = _canonicalTimeBindings[admission];
    if (admission is! _DriftCanonicalLearningTimeAdmission ||
        original == null ||
        admission.ownerId != expectedOwnerId) {
      throw StateError(
        'Original live canonical learning-time proof is unavailable',
      );
    }
    // LIVE admission performs the inherited-transaction rejection before its
    // own consistent read. Do not replace this with CLOSED verification.
    final refreshed = await admitCanonicalLearningTime(
      original.request,
      expectedOwnerId: expectedOwnerId,
      stillCurrent: stillCurrent,
    );
    if (refreshed.ownerId != admission.ownerId ||
        refreshed.sessionId != admission.sessionId ||
        refreshed.activityType != admission.activityType ||
        refreshed.sourceKind != admission.sourceKind ||
        refreshed.sourceBindingJson != admission.sourceBindingJson ||
        refreshed.contextBindingJson != admission.contextBindingJson) {
      throw StateError('Original live canonical learning-time context changed');
    }
  }

  @override
  Future<void> requireCanonicalLearningTimeAdmission(
    CanonicalLearningTimeAdmission admission, {
    required String expectedOwnerId,
    required bool Function() ownerStillCurrent,
  }) async {
    await _requireTimeReadOwner(expectedOwnerId, ownerStillCurrent);
    final binding = _canonicalTimeBindings[admission];
    if (admission is! _DriftCanonicalLearningTimeAdmission ||
        binding == null ||
        admission.ownerId != expectedOwnerId ||
        binding.request.callerContext != LearningTimeCallerContext.ordinary) {
      throw StateError('Original canonical learning-time proof is unavailable');
    }
    final row = await _session(admission.sessionId);
    if (row == null ||
        _timeSessionFingerprint(row) != binding.sessionFingerprint ||
        !{'active', 'completed', 'abandoned'}.contains(row.state)) {
      throw StateError('Original canonical learning-time identity changed');
    }
    // No old checkpoint/prompt/content-currentness check belongs here. The
    // immutable window was admitted before closing. The time writer checks its
    // captured owner and preference epoch, independently of the new live slot.
    switch (binding.request) {
      case MatchingTimeAdmission():
        break;
      case ConfiguredQuizTimeAdmission():
        break;
      case OwnedSrsTimeAdmission(:final review):
        final original = _srsBindings[review];
        if (original == null || !original.started) {
          throw StateError('Original acknowledged SRS handle is unavailable');
        }
        // Deliberately not _srsBinding: its original route may have ended.
        await _requireSrsFacts(review, original);
      case SourceBoundVocabularyTimeAdmission(:final start):
        final original = _requireSourceBoundVocabularyStart(start);
        if (!original.started ||
            original.callerContext != LearningTimeCallerContext.ordinary) {
          throw StateError('Original ordinary vocabulary ACK is unavailable');
        }
        await _requireSourceBoundVocabularyFacts(original);
      case NativeLearningTimeAdmission(:final exercise):
        _requireNativeBinding(exercise);
        await _requireNativeSession(exercise);
    }
    await _requireTimeOrdinarySession(row.id);
    if (!EvidenceProjectionDecision.resolve(
      context: admission.evidenceContext,
      projection: LearningProjection.activeLearningEffort,
    ).isEligible) {
      throw StateError('Evidence is ineligible for active learning effort');
    }
    await _requireTimeReadOwner(expectedOwnerId, ownerStillCurrent);
  }

  Future<void> _requireTimeReadOwner(
    String expectedOwnerId,
    bool Function() stillCurrent,
  ) async {
    if (!stillCurrent()) throw StateError('Learning-time scope changed');
    final owners =
        await (database.select(database.localOwners)
              ..where((owner) => owner.isActive.equals(true))
              ..limit(2))
            .get();
    if (owners.length != 1 || owners.single.id != expectedOwnerId) {
      throw StateError('Learning-time owner changed');
    }
    // inspect is SELECT-only. requireOwnerUnfenced intentionally acquires a
    // writer and must not be substituted into this read-only capability.
    final fence = await _ownerWrites.inspect();
    if (fence != null &&
        (fence.casToken == null ||
            fence.casToken!.matchesOwner(expectedOwnerId) ||
            (fence.cloudReceipt != null &&
                expectedOwnerId ==
                    accountDeletionReplacementGuestOwnerId(
                      fence.cloudReceipt!,
                    )))) {
      throw StateError('Learning-time owner is fenced');
    }
    if (!stillCurrent()) throw StateError('Learning-time scope changed');
  }

  Future<void> _requireTimeOrdinarySession(String sessionId) async {
    final controlled = await database
        .customSelect(
          'SELECT 1 AS controlled FROM assessment_runs '
          'WHERE learning_session_id = ? '
          'UNION ALL SELECT 1 AS controlled FROM measurement_opportunities '
          'WHERE learning_session_id = ? LIMIT 1',
          variables: [Variable<String>(sessionId), Variable<String>(sessionId)],
        )
        .getSingleOrNull();
    if (controlled != null) {
      throw StateError('Research-controlled time collection is excluded');
    }
  }

  String _timeSessionFingerprint(db.LearningSession row) => _timeDigest([
    row.id,
    row.ownerId,
    row.activityType,
    row.startedAtUtcMs,
    row.appVersion,
    row.buildId,
    row.acceptedPlanId,
    row.acceptedPlanJson,
  ]);

  String _timeDigest(Object? body) =>
      sha256.convert(utf8.encode(jsonEncode(body))).toString();

  String _timeJson(Map<String, Object?> body) {
    final result = jsonEncode(body);
    if (utf8.encode(result).length > 16384) {
      throw StateError('Learning-time binding exceeds its storage limit');
    }
    return result;
  }

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    String? afterWordId,
    required int limit,
  }) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final words = database.vocabularyWords;
    final categories = database.vocabularyCategories;
    final query =
        database.select(words).join([
            innerJoin(
              categories,
              categories.id.equalsExp(words.categoryId) &
                  categories.ownerId.equalsExp(words.ownerId) &
                  categories.isDeleted.equals(false),
            ),
          ])
          ..where(
            words.ownerId.equals(ownerId) &
                words.isDeleted.equals(false) &
                (categoryId == null
                    ? const Constant(true)
                    : words.categoryId.equals(categoryId)) &
                (wordIds == null
                    ? const Constant(true)
                    : words.id.isIn(wordIds)) &
                (afterWordId == null
                    ? const Constant(true)
                    : words.id.isBiggerThanValue(afterWordId)),
          )
          ..orderBy([OrderingTerm.asc(words.id)])
          ..limit(limit);
    final rows = (await query.get()).map((row) => row.readTable(words));
    return rows
        .map(
          (row) => QuizWord(
            id: row.id,
            categoryId: row.categoryId,
            spelling: row.spelling,
            meaning: row.meaning,
            partOfSpeech: row.partOfSpeech,
            contentRevision: 'local-vocabulary-v1:${row.localRevision}',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> startSession(LearningSessionDraft session) async {
    if (session.activityType == MatchingPlan.activityType ||
        session.id.startsWith(MatchingPlan.sessionPrefix) ||
        _srsActivities.contains(session.activityType) ||
        session.id.startsWith(SrsReviewSession.idPrefix) ||
        session.activityType == 'sentenceScramble' ||
        session.id.startsWith(SentenceScrambleSession.idPrefix) ||
        session.id.startsWith(DictationSession.idPrefix) ||
        session.id.startsWith(WordScrambleSession.idPrefix) ||
        session.id.startsWith(ClozeSession.idPrefix)) {
      throw StateError(
        'Native Dictation requires its original launch capability',
      );
    }
    await _startSession(session);
  }

  Future<void> _startSession(
    LearningSessionDraft session, {
    Future<void> Function()? beforeObserved,
  }) async {
    final startedAt = _requiredUtc(session.startedAtUtc, 'startedAtUtc');
    final id = _required(session.id, 'id');
    final owner = _required(session.ownerId, 'ownerId');
    final activity = _required(session.activityType, 'activityType');
    final app = _required(session.appVersion, 'appVersion');
    final build = _required(session.buildId, 'buildId');
    await database.transaction(() async {
      await database
          .into(database.learningSessions)
          .insert(
            db.LearningSessionsCompanion.insert(
              id: id,
              ownerId: owner,
              activityType: activity,
              state: 'active',
              startedAtUtcMs: startedAt.millisecondsSinceEpoch,
              appVersion: app,
              buildId: build,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      final inserted =
          (await database
                  .customSelect('SELECT changes() AS affected')
                  .getSingle())
              .read<int>('affected') ==
          1;
      final row = await (database.select(
        database.learningSessions,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (row == null ||
          row.ownerId != owner ||
          row.activityType != activity ||
          row.startedAtUtcMs != startedAt.millisecondsSinceEpoch ||
          row.appVersion != app ||
          row.buildId != build) {
        throw StateError('session id already exists with different identity');
      }
      if (inserted) await beforeObserved?.call();
      final observer = lifecycleObserver;
      if (inserted && observer != null) {
        await _observe(
          () => observer.accepted(LearningSessionLifecycleFact.fromRow(row)),
        );
      }
    });
  }

  @override
  Future<AnswerRecordResult> recordAnswer(
    RecordAnswerCommand command,
  ) => database.transaction(() async {
    if (command.promptMode == MatchingPlan.promptMode ||
        command.sessionId.startsWith(MatchingPlan.sessionPrefix) ||
        command.promptMode == 'srsRecall' ||
        command.promptMode == 'definitionChoice' ||
        command.promptMode == 'definitionTyped' ||
        command.sessionId.startsWith(SrsReviewSession.idPrefix) ||
        command.promptMode == 'sentenceScramble' ||
        command.sessionId.startsWith(SentenceScrambleSession.idPrefix) ||
        command.sessionId.startsWith(DictationSession.idPrefix) ||
        command.sessionId.startsWith(WordScrambleSession.idPrefix) ||
        command.sessionId.startsWith(ClozeSession.idPrefix)) {
      throw StateError(
        'Native Dictation answers require their original capability',
      );
    }
    if (await _requiresDedicatedWriter(command.sessionId)) {
      throw StateError(
        'Configured quiz, SRS, or Sentence Scramble answers require their dedicated writer',
      );
    }
    return _recordAnswer(command);
  });

  Future<AnswerRecordResult> _recordAnswer(RecordAnswerCommand command) {
    _validateAnswer(command);
    final masteryEligible = _allowsAnswerProjection(
      command,
      LearningProjection.masterySrs,
    );
    return database.transaction(() async {
      final assessmentSession =
          await (database.select(database.learningSessions)..where(
                (row) =>
                    row.id.equals(command.sessionId) &
                    row.ownerId.equals(command.ownerId) &
                    row.activityType.equals('assessment'),
              ))
              .getSingleOrNull();
      if (assessmentSession != null) {
        throw StateError(
          'Assessment answers require the dedicated Assessment writer',
        );
      }
      final existing = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(command.id))).getSingleOrNull();
      if (existing != null) {
        if (!_sameAttempt(existing, command)) {
          throw StateError('attempt id already exists with different evidence');
        }
        final srs = masteryEligible
            ? await projections.rebuildWord(
                ownerId: command.ownerId,
                wordId: command.wordId,
              )
            : await _readSavedSrs(command.ownerId, command.wordId);
        if (srs == null && masteryEligible) {
          throw StateError('ordinary answer has no ordinary SRS evidence');
        }
        await projections.rebuildSession(
          ownerId: command.ownerId,
          sessionId: command.sessionId,
        );
        await projections.rebuildAchievements(command.ownerId);
        await _rebuildOptionalRewards(command.ownerId);
        return AnswerRecordResult(inserted: false, srs: srs);
      }

      final session =
          await (database.select(database.learningSessions)..where(
                (row) =>
                    row.id.equals(command.sessionId) &
                    row.ownerId.equals(command.ownerId) &
                    row.state.equals('active'),
              ))
              .getSingleOrNull();
      if (session == null) {
        throw StateError('active learning session not found');
      }
      final word =
          await (database.select(database.vocabularyWords)..where(
                (row) =>
                    row.id.equals(command.wordId) &
                    row.ownerId.equals(command.ownerId) &
                    row.isDeleted.equals(false),
              ))
              .getSingleOrNull();
      if (word == null) {
        throw StateError('active vocabulary word not found');
      }

      await database
          .into(database.answerAttempts)
          .insert(
            db.AnswerAttemptsCompanion.insert(
              id: command.id,
              ownerId: command.ownerId,
              sessionId: command.sessionId,
              wordId: command.wordId,
              promptMode: command.promptMode,
              isCorrect: command.isCorrect,
              responseTimeMs: Value(command.responseTimeMs),
              attemptNumber: command.attemptNumber,
              occurredAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
              providerProvenance: Value(command.providerProvenance),
              evidenceClass: Value(command.evidenceContext.evidenceClass.name),
              evidenceContextJson: Value(
                jsonEncode(command.evidenceContext.toJson()),
              ),
            ),
          );
      await DriftLearningDayRecorder(
        database,
        ownerWrites: _ownerWrites,
      ).recordAnswer(command.id);
      final next = masteryEligible
          ? await projections.rebuildWord(
              ownerId: command.ownerId,
              wordId: command.wordId,
            )
          : await _readSavedSrs(command.ownerId, command.wordId);
      if (next == null && masteryEligible) {
        throw StateError('ordinary answer has no ordinary SRS evidence');
      }
      await projections.rebuildSession(
        ownerId: command.ownerId,
        sessionId: command.sessionId,
      );
      await projections.rebuildAchievements(command.ownerId);
      await _rebuildOptionalRewards(command.ownerId);
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'attempt',
        entityId: command.id,
        occurredAtUtc: command.occurredAtUtc,
        payloadVersion:
            jsonEncode(command.evidenceContext.toJson()) ==
                LearningEvidenceContract.frozenV13LegacyEvidenceContextJson
            ? 1
            : 2,
      );
      // Outbox hook — push updated SRS state to Firestore (Phase 0 Week 12-13).
      // Entity ID is wordId (unique per owner-word pair).
      if (masteryEligible && next != null) {
        await _appendImmutableOutbox(
          ownerId: command.ownerId,
          entityType: 'srsState',
          entityId: command.wordId,
          occurredAtUtc: command.occurredAtUtc,
        );
      }
      return AnswerRecordResult(inserted: true, srs: next);
    });
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) => database.transaction(() async {
    if (sessionId.startsWith(MatchingPlan.sessionPrefix) ||
        sessionId.startsWith(SrsReviewSession.idPrefix) ||
        sessionId.startsWith(SentenceScrambleSession.idPrefix) ||
        sessionId.startsWith(DictationSession.idPrefix) ||
        sessionId.startsWith(WordScrambleSession.idPrefix) ||
        sessionId.startsWith(ClozeSession.idPrefix)) {
      throw StateError(
        'Native Dictation completion requires its original close intent',
      );
    }
    if (await _requiresDedicatedWriter(sessionId)) {
      throw StateError(
        'Configured quiz, SRS, or Sentence Scramble completion requires its dedicated writer',
      );
    }
    return _finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
  });

  Future<LearningSessionSummary> _finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
    bool observe = true,
  }) {
    _requiredUtc(endedAtUtc, 'endedAtUtc');
    return database.transaction(() async {
      final row =
          await (database.select(database.learningSessions)..where(
                (candidate) =>
                    candidate.id.equals(sessionId) &
                    candidate.ownerId.equals(ownerId),
              ))
              .getSingleOrNull();
      if (row == null) throw StateError('learning session not found');
      if (row.activityType == 'assessment') {
        throw StateError(
          'Assessment completion requires the dedicated Assessment writer',
        );
      }
      if (row.state != 'active' && row.state != 'completed') {
        throw StateError('learning session cannot be completed');
      }
      final total = row.correctCount + row.wrongCount;
      final score = total == 0 ? 0 : ((row.correctCount * 100) / total).round();
      final attempts =
          await (database.select(database.answerAttempts)..where(
                (attempt) =>
                    attempt.sessionId.equals(sessionId) &
                    attempt.ownerId.equals(ownerId),
              ))
              .get();
      final sessionAchievements = attempts.isEmpty
          ? row.activityType != 'dictation'
          : attempts.any(
              (attempt) => LearningEvidenceContract.allowsOrdinaryProjection(
                promptMode: attempt.promptMode,
                evidenceClass: attempt.evidenceClass,
                evidenceContextJson: attempt.evidenceContextJson,
                projection: LearningProjection.achievement,
              ),
            );
      if (row.state != 'completed') {
        await (database.update(
          database.learningSessions,
        )..where((candidate) => candidate.id.equals(sessionId))).write(
          db.LearningSessionsCompanion(
            state: const Value('completed'),
            endedAtUtcMs: Value(endedAtUtc.millisecondsSinceEpoch),
            score: Value(score),
          ),
        );
        if (sessionAchievements) {
          await _unlockAchievement(
            ownerId: ownerId,
            achievementId: 'first_session',
            sourceEventId: sessionId,
            unlockedAtUtc: endedAtUtc,
          );
        }
        if (sessionAchievements && total > 0 && row.wrongCount == 0) {
          await _unlockAchievement(
            ownerId: ownerId,
            achievementId: 'perfect_session',
            sourceEventId: sessionId,
            unlockedAtUtc: endedAtUtc,
          );
        }
      }
      final observer = lifecycleObserver;
      if (observe && observer != null) {
        final completed =
            await (database.select(database.learningSessions)..where(
                  (candidate) =>
                      candidate.id.equals(sessionId) &
                      candidate.ownerId.equals(ownerId),
                ))
                .getSingle();
        await _observe(
          () => observer.completed(
            LearningSessionLifecycleFact.fromRow(completed),
          ),
        );
      }
      return LearningSessionSummary(
        id: row.id,
        state: 'completed',
        correctCount: row.correctCount,
        wrongCount: row.wrongCount,
        score: score,
      );
    });
  }

  @override
  Future<bool> hasAmbientTransaction() => _ownerWrites.hasAmbientTransaction();

  final _srsBindings = Expando<_SrsReviewBinding>();

  @override
  Future<SrsReviewSession?> prepareSrsReview({
    required LearningSessionDraft session,
    required SrsReviewSelection selection,
    Iterable<String>? sourceWordIds,
    int limit = 20,
    required bool Function() stillCurrent,
  }) async {
    if (!session.id.startsWith(SrsReviewSession.idPrefix) ||
        session.id.length == SrsReviewSession.idPrefix.length ||
        !LearningEvidenceContract.validIdentifier(session.id) ||
        !LearningEvidenceContract.validIdentifier(session.ownerId) ||
        session.activityType != 'srsReview' ||
        session.startedAtUtc == null ||
        !session.startedAtUtc!.isUtc ||
        session.startedAtUtc!.microsecondsSinceEpoch < 0 ||
        session.startedAtUtc!.microsecondsSinceEpoch % 1000 != 0 ||
        session.appVersion.trim().isEmpty ||
        session.buildId.trim().isEmpty ||
        limit < 1 ||
        limit > 20) {
      throw ArgumentError('Invalid original SRS preparation');
    }
    final ids = sourceWordIds?.toList(growable: false);
    if ((selection == SrsReviewSelection.due && ids != null) ||
        (selection == SrsReviewSelection.source &&
            (ids == null ||
                ids.isEmpty ||
                ids.length > limit ||
                ids.toSet().length != ids.length ||
                ids.any(
                  (id) => !LearningEvidenceContract.validIdentifier(id),
                )))) {
      throw ArgumentError('Invalid original SRS selection');
    }
    final review = await _writeSrsBoundary<SrsReviewSession?>(
      session.ownerId,
      stillCurrent,
      write: () async {
        if (await _session(session.id) != null) {
          throw StateError('SRS preparation cannot adopt a persisted session');
        }
        final words = selection == SrsReviewSelection.due
            ? await listDueWords(
                ownerId: session.ownerId,
                nowUtc: session.startedAtUtc!,
                limit: limit,
              )
            : await listQuizWords(
                ownerId: session.ownerId,
                wordIds: ids,
                limit: limit,
              );
        if (selection == SrsReviewSelection.source &&
            (words.length != ids!.length ||
                words.any((word) => !ids.contains(word.id)))) {
          throw StateError('Original SRS source target unavailable');
        }
        if (words.isEmpty) return null;
        return SrsReviewSession(
          session: session,
          words: selection == SrsReviewSelection.due
              ? words
              : [
                  for (final id in ids!)
                    words.singleWhere((word) => word.id == id),
                ],
          selection: selection,
        );
      },
      verify: (review) async {
        if (review != null) await _requireSrsTargets(review);
      },
    );
    if (review != null) {
      _srsBindings[review] = _SrsReviewBinding(stillCurrent);
    }
    return review;
  }

  @override
  Future<SrsReviewStartResult> startSrsReview(
    SrsReviewSession review, {
    required bool Function() stillCurrent,
  }) async {
    final binding = _srsBinding(review);
    final result = await _writeSrsBoundary<SrsReviewStartResult>(
      review.ownerId,
      () => _srsCurrent(review, stillCurrent),
      write: () async {
        final saved = await _session(review.id);
        var inserted = false;
        if (saved == null) {
          if (binding.started) {
            throw StateError('Original acknowledged SRS session is missing');
          }
          await _requireSrsTargets(review);
          if (review.selection == SrsReviewSelection.due) {
            final placeholders = List.filled(
              review.words.length,
              '?',
            ).join(',');
            final rows = await database
                .customSelect(
                  'SELECT word_id FROM srs_states WHERE owner_id = ? '
                  'AND word_id IN ($placeholders) AND due_at_utc_ms <= ?',
                  variables: [
                    Variable<String>(review.ownerId),
                    ...review.words.map((word) => Variable<String>(word.id)),
                    Variable<int>(review.startedAtUtc.millisecondsSinceEpoch),
                  ],
                )
                .get();
            if (rows.length != review.words.length) {
              throw StateError('Original SRS due selection changed');
            }
          }
          binding.startAttempted = true;
          await _startSession(review.session);
          inserted = true;
        } else if (!binding.startAttempted) {
          throw StateError('SRS start requires its original prepared handle');
        }
        await _requireSrsFacts(review, binding);
        return SrsReviewStartResult(review: review, inserted: inserted);
      },
      verify: (result) async {
        await _requireSrsFacts(review, binding);
        if (result.inserted) await _requireSrsTargets(review);
      },
    );
    binding.started = true;
    return result;
  }

  @override
  Future<AnswerRecordResult> commitSrsRating(
    SrsReviewAnswerIntent intent, {
    required bool Function() stillCurrent,
  }) async {
    final review = intent.review;
    final binding = _srsBinding(review);
    if (!binding.started) {
      throw StateError('SRS rating requires its original start receipt');
    }
    _validateSrsRating(intent);
    final original = binding.answers[intent.cardIndex];
    if (original != null && !identical(original, intent)) {
      throw StateError('Original SRS rating intent changed');
    }
    return _writeSrsBoundary<AnswerRecordResult>(
      review.ownerId,
      () => _srsCurrent(review, stillCurrent),
      write: () async {
        final facts = await _requireSrsFacts(review, binding);
        if (intent.cardIndex < facts.attempts.length) {
          if (!_sameAttempt(facts.attempts[intent.cardIndex], intent.command)) {
            throw StateError('Original saved SRS rating changed');
          }
          final saved = await _readSavedSrs(
            review.ownerId,
            intent.command.wordId,
          );
          return AnswerRecordResult(inserted: false, srs: saved);
        }
        if (facts.session.state != 'active' ||
            binding.closing != null ||
            intent.cardIndex != facts.attempts.length) {
          throw StateError('SRS rating is not the next original card');
        }
        if (facts.attempts.isNotEmpty &&
            intent.command.occurredAtUtc.millisecondsSinceEpoch <
                facts.attempts.last.occurredAtUtcMs) {
          throw StateError('SRS rating time precedes the previous card');
        }
        await _requireSrsTargets(review, [intent.cardIndex]);
        binding.answers[intent.cardIndex] = intent;
        return _recordAnswer(intent.command);
      },
      verify: (result) async {
        final facts = await _requireSrsFacts(review, binding);
        if (facts.attempts.length <= intent.cardIndex ||
            !_sameAttempt(facts.attempts[intent.cardIndex], intent.command)) {
          throw StateError('SRS rating readback changed');
        }
        if (result.inserted) {
          await _requireSrsTargets(review, [intent.cardIndex]);
        }
      },
    );
  }

  @override
  Future<SrsReviewFinishResult> finishSrsReview(
    SrsReviewFinishIntent intent, {
    required bool Function() stillCurrent,
  }) async {
    final review = intent.review;
    final binding = _srsBinding(review);
    if (!binding.started) {
      throw StateError('SRS finish requires its original start receipt');
    }
    if (binding.closing != null && !identical(binding.closing, intent)) {
      throw StateError('Original SRS closing intent changed');
    }
    return _writeSrsBoundary<SrsReviewFinishResult>(
      review.ownerId,
      () => _srsCurrent(review, stillCurrent),
      write: () async {
        final facts = await _requireSrsFacts(review, binding);
        if (facts.attempts.length != review.words.length ||
            intent.endedAtUtc.millisecondsSinceEpoch <
                facts.attempts.last.occurredAtUtcMs) {
          throw StateError('SRS completion requires every original rating');
        }
        if (facts.session.state == 'completed') {
          if (!binding.finishAttempted ||
              facts.session.endedAtUtcMs !=
                  intent.endedAtUtc.millisecondsSinceEpoch) {
            throw StateError('Saved SRS end differs from its original intent');
          }
          return SrsReviewFinishResult(
            summary: _nativeSummary(facts.session),
            inserted: false,
          );
        }
        binding.closing = intent;
        await _requireSrsTargets(review);
        binding.finishAttempted = true;
        final summary = await _finishSession(
          ownerId: review.ownerId,
          sessionId: review.id,
          endedAtUtc: intent.endedAtUtc,
        );
        return SrsReviewFinishResult(summary: summary, inserted: true);
      },
      verify: (result) async {
        final facts = await _requireSrsFacts(review, binding);
        if (facts.session.state != 'completed' ||
            facts.session.endedAtUtcMs !=
                intent.endedAtUtc.millisecondsSinceEpoch) {
          throw StateError('SRS completion readback changed');
        }
        if (result.inserted) await _requireSrsTargets(review);
      },
    );
  }

  Future<T> _writeSrsBoundary<T>(
    String ownerId,
    bool Function() stillCurrent, {
    required Future<T> Function() write,
    required Future<void> Function(T result) verify,
  }) async {
    if (await _ownerWrites.hasAmbientTransaction()) {
      throw StateError('SRS review requires its own committed transaction');
    }
    if (!stillCurrent()) throw StateError('SRS review is no longer current');
    return _ownerWrites.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: () async {
        final result = await write();
        await verify(result);
        return _ownerWrites.writeForActiveOwner(
          expectedOwnerId: ownerId,
          write: () async {
            if (!stillCurrent()) {
              throw StateError('SRS review is no longer current');
            }
            return result;
          },
        );
      },
    );
  }

  _SrsReviewBinding _srsBinding(SrsReviewSession review) {
    final binding = _srsBindings[review];
    if (binding == null) {
      throw StateError('SRS review requires its original prepared instance');
    }
    if (binding.invalidated || !binding.current()) {
      binding.invalidated = true;
      throw StateError('Original SRS review scope is no longer current');
    }
    return binding;
  }

  bool _srsCurrent(SrsReviewSession review, bool Function() stillCurrent) {
    final binding = _srsBinding(review);
    if (!stillCurrent()) {
      binding.invalidated = true;
      return false;
    }
    return true;
  }

  Future<void> _requireSrsTargets(
    SrsReviewSession review, [
    Iterable<int>? cardIndices,
  ]) async {
    for (final index
        in cardIndices ?? List.generate(review.words.length, (i) => i)) {
      final target = review.words[index];
      final row = await database
          .customSelect(
            'SELECT w.category_id,w.spelling,w.meaning,w.part_of_speech,w.local_revision '
            'FROM vocabulary_words w JOIN vocabulary_categories c '
            'ON c.id = w.category_id AND c.owner_id = w.owner_id '
            'WHERE w.id = ? AND w.owner_id = ? AND w.is_deleted = 0 '
            'AND c.is_deleted = 0',
            variables: [
              Variable<String>(target.id),
              Variable<String>(review.ownerId),
            ],
          )
          .getSingleOrNull();
      if (row == null ||
          row.read<String>('category_id') != target.categoryId ||
          row.read<String>('spelling') != target.spelling ||
          row.read<String>('meaning') != target.meaning ||
          row.read<String>('part_of_speech') != target.partOfSpeech ||
          'local-vocabulary-v1:${row.read<int>('local_revision')}' !=
              target.contentRevision) {
        throw StateError('Original SRS target changed');
      }
    }
  }

  void _validateSrsRating(SrsReviewAnswerIntent intent) {
    final review = intent.review;
    final command = intent.command;
    _validateAnswer(command);
    final index = intent.cardIndex;
    if (index < 0 || index >= review.words.length) {
      throw ArgumentError('SRS rating index is outside its original deck');
    }
    final expected = EvidenceContext.forNewEvidence(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'srs-recall',
      hintLevel: 0,
      contentRevision: review.words[index].contentRevision!,
      rolloutMode: EvidencePolicyRolloutMode.legacy,
    );
    if (command.id != 'attempt:srs:${review.id}:$index' ||
        command.ownerId != review.ownerId ||
        command.sessionId != review.id ||
        command.wordId != review.words[index].id ||
        command.attemptNumber != index + 1 ||
        command.promptMode != 'srsRecall' ||
        command.providerProvenance != null ||
        command.occurredAtUtc.microsecondsSinceEpoch % 1000 != 0 ||
        command.occurredAtUtc.isBefore(review.startedAtUtc) ||
        jsonEncode(command.evidenceContext.toJson()) !=
            jsonEncode(expected.toJson())) {
      throw ArgumentError(
        'SRS rating differs from its original target/profile',
      );
    }
  }

  Future<({db.LearningSession session, List<db.AnswerAttempt> attempts})>
  _requireSrsFacts(SrsReviewSession review, _SrsReviewBinding binding) async {
    final row = await _session(review.id);
    final original = review.session;
    if (row == null ||
        row.ownerId != review.ownerId ||
        row.activityType != 'srsReview' ||
        row.startedAtUtcMs != review.startedAtUtc.millisecondsSinceEpoch ||
        row.appVersion != original.appVersion ||
        row.buildId != original.buildId ||
        row.acceptedPlanId != null ||
        row.acceptedPlanJson != null ||
        row.checkpointJson != null ||
        row.checkpointRevision != 0 ||
        (row.state != 'active' && row.state != 'completed')) {
      throw StateError('Original SRS session facts changed');
    }
    final attempts =
        await (database.select(database.answerAttempts)
              ..where((attempt) => attempt.sessionId.equals(review.id))
              ..orderBy([(attempt) => OrderingTerm.asc(attempt.attemptNumber)]))
            .get();
    if (attempts.length > review.words.length) {
      throw StateError('SRS session contains extra ratings');
    }
    var previous = review.startedAtUtc.millisecondsSinceEpoch;
    for (var index = 0; index < attempts.length; index++) {
      final intent = binding.answers[index];
      final attempt = attempts[index];
      if (intent == null ||
          attempt.id != intent.command.id ||
          !_sameAttempt(attempt, intent.command) ||
          attempt.attemptNumber != index + 1 ||
          attempt.occurredAtUtcMs < previous) {
        throw StateError('SRS session contains a different original rating');
      }
      _validateSrsRating(intent);
      previous = attempt.occurredAtUtcMs;
    }
    final correct = attempts.where((attempt) => attempt.isCorrect).length;
    final score = attempts.isEmpty
        ? 0
        : ((correct * 100) / attempts.length).round();
    if (row.correctCount != correct ||
        row.wrongCount != attempts.length - correct ||
        (row.state == 'active' &&
            (row.endedAtUtcMs != null || row.score != null)) ||
        (row.state == 'completed' &&
            (attempts.length != review.words.length ||
                row.endedAtUtcMs == null ||
                row.endedAtUtcMs! < previous ||
                row.score != score))) {
      throw StateError('SRS outcome differs from its original ratings');
    }
    return (session: row, attempts: attempts);
  }

  @override
  Future<T> startNativeExercise<T extends AcceptedNativeExercise>(
    T exercise, {
    required bool Function() stillCurrent,
  }) async {
    final plan = AcceptedNativePlan(exercise);
    final authored = switch (exercise) {
      ClozeSession(:final content) => content.source is AuthoredSentenceSource,
      SentenceScrambleSession(:final content) =>
        content.source is AuthoredSentenceSource,
      _ => false,
    };
    if (authored && _nativeBindings[exercise] == null) {
      throw StateError('Original authored launch is required');
    }
    final binding = _nativeBindings[exercise] ??= _NativeIssuance(stillCurrent);
    await _writeNativeExercise<void>(
      exercise,
      stillCurrent,
      write: () async {
        final existing = await _session(exercise.id);
        if (existing != null && !binding.startAttempted) {
          throw StateError(
            'A bare native session has no original launch handle',
          );
        }
        if (existing == null) {
          if (binding.started) {
            throw StateError('Acknowledged native session is missing');
          }
          await _requireNativeTargets(exercise);
          binding.startAttempted = true;
          await _startSession(
            exercise.session,
            beforeObserved: () => _writeNativeStorage(
              exercise.id,
              plan: plan,
              expectedRevision: 0,
              checkpoint: AwaitingNativeAnswer(NativeExerciseDraft()),
            ),
          );
        } else {
          _sameNativeSession(existing, exercise);
        }
      },
      verify: (_) async {
        await _loadNative(exercise.id, exercise.ownerId, issued: exercise);
      },
    );
    binding.started = true;
    return exercise;
  }

  @override
  Future<NativeExerciseState> resumeNativeExercise({
    required String sessionId,
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async {
    _trackConfiguredOwner();
    final epoch = _configuredOwnerEpoch;
    bool current() => epoch == _configuredOwnerEpoch && stillCurrent();
    if (await _ownerWrites.hasAmbientTransaction()) {
      throw StateError('Native resume requires committed source facts');
    }
    if (!current()) throw StateError('Native owner changed');
    return database.transaction(() async {
      await _requireTimeReadOwner(expectedOwnerId, current);
      final state = await _loadNative(sessionId, expectedOwnerId);
      await _requireTimeOrdinarySession(sessionId);
      await _requireTimeReadOwner(expectedOwnerId, current);
      _nativeBindings[state.exercise] = _NativeIssuance(current)
        ..startAttempted = true
        ..started = true;
      return state;
    });
  }

  @override
  Future<NativeExerciseState> readNativeExerciseState(
    AcceptedNativeExercise exercise, {
    required bool Function() stillCurrent,
  }) async {
    _requireNativeBinding(exercise);
    if (await _ownerWrites.hasAmbientTransaction()) {
      throw StateError(
        'Native checkpoint read requires committed source facts',
      );
    }
    return database.transaction(() async {
      await _requireTimeReadOwner(
        exercise.ownerId,
        () => _nativeCurrent(exercise, stillCurrent),
      );
      final state = await _loadNative(
        exercise.id,
        exercise.ownerId,
        issued: exercise,
      );
      await _requireTimeReadOwner(
        exercise.ownerId,
        () => _nativeCurrent(exercise, stillCurrent),
      );
      return state;
    });
  }

  @override
  Future<NativeExerciseState> saveNativeCheckpoint(
    NativeExerciseState state,
    NativeCheckpoint checkpoint, {
    required bool Function() stillCurrent,
  }) async {
    if (state is! _DriftNativeState || !identical(state.issuer, this)) {
      throw StateError('Native checkpoint requires its issued state');
    }
    final exercise = state.exercise;
    _requireNativeBinding(exercise);
    checkpoint.validate(state.plan);
    if (checkpoint.answer case final command?) {
      _validateNativeAnswer(exercise, command);
    }
    return _writeNativeExercise<NativeExerciseState>(
      exercise,
      stillCurrent,
      write: () async {
        final saved = await _loadNative(
          exercise.id,
          exercise.ownerId,
          issued: exercise,
        );
        if (_reconcilesNativeStage(state, saved, checkpoint)) return saved;
        if (saved.checkpointRevision == state.checkpointRevision + 1 &&
            saved.checkpoint.stableSerialization ==
                checkpoint.stableSerialization) {
          _requireNativeTransition(state.checkpoint, checkpoint);
          return saved;
        }
        if (saved.checkpointRevision != state.checkpointRevision ||
            saved.plan.id != state.plan.id ||
            saved.checkpoint.stableSerialization !=
                state.checkpoint.stableSerialization) {
          throw NativeExerciseUnavailable(
            NativeExerciseUnavailableReason.revisionChanged,
          );
        }
        _requireNativeTransition(saved.checkpoint, checkpoint);
        if (checkpoint is AbandonedNativeExercise) {
          final changed = await database.customUpdate(
            "UPDATE learning_sessions SET state = 'abandoned', ended_at_utc_ms = ?, score = 0 "
            "WHERE id = ? AND owner_id = ? AND state = 'active' AND checkpoint_revision = ?",
            variables: [
              Variable<int>(checkpoint.endedAtUtc.millisecondsSinceEpoch),
              Variable<String>(exercise.id),
              Variable<String>(exercise.ownerId),
              Variable<int>(saved.checkpointRevision),
            ],
            updates: {database.learningSessions},
          );
          if (changed != 1) throw StateError('Native abandon identity changed');
        }
        await _writeNativeStorage(
          exercise.id,
          plan: saved.plan,
          expectedRevision: saved.checkpointRevision,
          checkpoint: checkpoint,
        );
        return _loadNative(exercise.id, exercise.ownerId, issued: exercise);
      },
      verify: (_) async {
        await _loadNative(exercise.id, exercise.ownerId, issued: exercise);
      },
    );
  }

  @override
  Future<AnswerRecordResult> commitNativeAnswer(
    AcceptedNativeExercise exercise,
    RecordAnswerCommand command, {
    required bool Function() stillCurrent,
  }) async {
    _requireNativeBinding(exercise);
    _validateNativeAnswer(exercise, command);
    return _writeNativeExercise<AnswerRecordResult>(
      exercise,
      stillCurrent,
      write: () async {
        var current = await _loadNative(
          exercise.id,
          exercise.ownerId,
          issued: exercise,
        );
        if (current.checkpoint is AwaitingNativeAnswer) {
          final pending = PendingNativeAnswer(command.nativeDraft!, command);
          _requireNativeTransition(current.checkpoint, pending);
          await _writeNativeStorage(
            exercise.id,
            plan: current.plan,
            expectedRevision: current.checkpointRevision,
            checkpoint: pending,
          );
          current = await _loadNative(
            exercise.id,
            exercise.ownerId,
            issued: exercise,
          );
        }
        final original = current.checkpoint.answer;
        if (original == null || !_sameNativeCommand(original, command)) {
          throw StateError('Native pending answer identity changed');
        }
        if (current.checkpoint is! PendingNativeAnswer) {
          if (current.checkpoint is! AnsweredNativeExercise &&
              current.checkpoint is! ClosingNativeExercise &&
              current.checkpoint is! CompletedNativeExercise) {
            throw StateError('Native answer phase is unavailable');
          }
          return AnswerRecordResult(
            inserted: false,
            srs: await _readSavedSrs(exercise.ownerId, exercise.word.id),
          );
        }
        final result = await _recordAnswer(original);
        await _writeNativeStorage(
          exercise.id,
          plan: current.plan,
          expectedRevision: current.checkpointRevision,
          checkpoint: AnsweredNativeExercise(
            current.checkpoint.draft,
            original,
          ),
        );
        return result;
      },
      verify: (_) async {
        final current = await _loadNative(
          exercise.id,
          exercise.ownerId,
          issued: exercise,
        );
        if (current.checkpoint is PendingNativeAnswer ||
            current.checkpoint.answer == null ||
            !_sameNativeCommand(current.checkpoint.answer!, command)) {
          throw StateError('Native answer acknowledgement changed');
        }
      },
    );
  }

  @override
  Future<LearningSessionSummary> finishNativeExercise(
    NativeFinishIntent intent, {
    required bool Function() stillCurrent,
  }) async {
    final exercise = intent.exercise;
    _requireNativeBinding(exercise);
    _validateNativeAnswer(exercise, intent.answer);
    _requiredUtc(intent.endedAtUtc, 'endedAtUtc');
    if (intent.endedAtUtc.isBefore(intent.answer.occurredAtUtc) ||
        intent.endedAtUtc.microsecondsSinceEpoch % 1000 != 0) {
      throw ArgumentError('Native completion precedes its answer');
    }
    var newlyCompleted = false;
    return _writeNativeExercise<LearningSessionSummary>(
      exercise,
      stillCurrent,
      write: () async {
        var current = await _loadNative(
          exercise.id,
          exercise.ownerId,
          issued: exercise,
        );
        if (current.checkpoint is AnsweredNativeExercise) {
          final closing = ClosingNativeExercise(
            current.checkpoint.draft,
            intent.answer,
            intent.endedAtUtc,
          );
          _requireNativeTransition(current.checkpoint, closing);
          await _writeNativeStorage(
            exercise.id,
            plan: current.plan,
            expectedRevision: current.checkpointRevision,
            checkpoint: closing,
          );
          current = await _loadNative(
            exercise.id,
            exercise.ownerId,
            issued: exercise,
          );
        }
        final checkpoint = current.checkpoint;
        if ((checkpoint is! ClosingNativeExercise &&
                checkpoint is! CompletedNativeExercise) ||
            checkpoint.answer == null ||
            !_sameNativeCommand(checkpoint.answer!, intent.answer) ||
            checkpoint.endedAtUtc != intent.endedAtUtc) {
          throw StateError('Native close identity changed');
        }
        if (checkpoint is CompletedNativeExercise) {
          return _nativeSummary((await _session(exercise.id))!);
        }
        newlyCompleted = true;
        final summary = await _finishSession(
          ownerId: exercise.ownerId,
          sessionId: exercise.id,
          endedAtUtc: intent.endedAtUtc,
          observe: false,
        );
        await _writeNativeStorage(
          exercise.id,
          plan: current.plan,
          expectedRevision: current.checkpointRevision,
          checkpoint: CompletedNativeExercise(
            checkpoint.draft,
            intent.answer,
            intent.endedAtUtc,
          ),
        );
        final observer = lifecycleObserver;
        if (observer != null) {
          final row = (await _session(exercise.id))!;
          await _observe(
            () => observer.completed(LearningSessionLifecycleFact.fromRow(row)),
          );
        }
        return summary;
      },
      verify: (_) async {
        final current = await _loadNative(
          exercise.id,
          exercise.ownerId,
          issued: exercise,
        );
        if (current.checkpoint is! CompletedNativeExercise ||
            current.checkpoint.endedAtUtc != intent.endedAtUtc) {
          throw StateError('Native completion acknowledgement changed');
        }
        if (newlyCompleted) await _requireNativeTargets(exercise);
      },
    );
  }

  Future<T> _writeNativeExercise<T>(
    AcceptedNativeExercise exercise,
    bool Function() stillCurrent, {
    required Future<T> Function() write,
    required Future<void> Function(T result) verify,
  }) async {
    if (await _ownerWrites.hasAmbientTransaction()) {
      throw StateError(
        'Native learning requires its own committed transaction',
      );
    }
    if (!_nativeCurrent(exercise, stillCurrent)) {
      throw StateError('Native exercise is no longer current');
    }
    return _ownerWrites.writeForActiveOwner(
      expectedOwnerId: exercise.ownerId,
      write: () async {
        final result = await write();
        await _ownerWrites.writeForActiveOwner(
          expectedOwnerId: exercise.ownerId,
          write: () => verify(result),
        );
        if (!_nativeCurrent(exercise, stillCurrent)) {
          throw StateError('Native exercise is no longer current');
        }
        return result;
      },
    );
  }

  bool _nativeCurrent(
    AcceptedNativeExercise exercise,
    bool Function() stillCurrent,
  ) {
    final issued = _nativeBindings[exercise];
    if (issued == null || issued.retired) return false;
    if (!issued.current() || !stillCurrent()) {
      issued.retired = true;
      return false;
    }
    return true;
  }

  _NativeIssuance _requireNativeBinding(AcceptedNativeExercise exercise) {
    final binding = _nativeBindings[exercise];
    if (binding == null || !binding.started) {
      throw StateError(
        'Native exercise requires its original acknowledged launch',
      );
    }
    return binding;
  }

  Future<_DriftNativeState> _loadNative(
    String sessionId,
    String ownerId, {
    AcceptedNativeExercise? issued,
  }) async {
    final row = await _session(sessionId);
    if (row == null) {
      throw NativeExerciseUnavailable(NativeExerciseUnavailableReason.notFound);
    }
    if (row.ownerId != ownerId) {
      throw NativeExerciseUnavailable(
        NativeExerciseUnavailableReason.ownerChanged,
      );
    }
    final planId = row.acceptedPlanId;
    final planJson = row.acceptedPlanJson;
    final checkpointJson = row.checkpointJson;
    if (planId != null &&
        planId.startsWith('native-plan-') &&
        !planId.startsWith(AcceptedNativePlan.idPrefix)) {
      throw NativeExerciseUnavailable(
        NativeExerciseUnavailableReason.unsupportedPolicy,
      );
    }
    if (planId == null ||
        planJson == null ||
        checkpointJson == null ||
        !planId.startsWith(AcceptedNativePlan.idPrefix)) {
      throw NativeExerciseUnavailable(NativeExerciseUnavailableReason.legacy);
    }
    late AcceptedNativePlan plan;
    late NativeCheckpoint checkpoint;
    try {
      plan = AcceptedNativePlan.parse(id: planId, json: planJson);
      if (plan.exercise.ownerId != row.ownerId) {
        throw NativeExerciseUnavailable(
          NativeExerciseUnavailableReason.ownerChanged,
        );
      }
      checkpoint = NativeCheckpoint.parse(checkpointJson, plan: plan);
      _sameNativeSession(row, plan.exercise);
      if (issued != null) _sameNativeSession(row, issued);
      if (checkpoint.answer case final command?) {
        _validateNativeAnswer(plan.exercise, command);
      }
      final attempts = await _nativeAttempts(plan.exercise);
      if (checkpoint.answer case final command?) {
        if (checkpoint is PendingNativeAnswer) {
          if (attempts.isNotEmpty ||
              row.correctCount != 0 ||
              row.wrongCount != 0) {
            throw StateError(
              'Pending native answer has unacknowledged canonical facts',
            );
          }
        } else {
          _sameNativeAnswer(attempts, command);
          _sameNativeOutcome(row, command);
        }
      } else if (attempts.isNotEmpty ||
          row.correctCount != 0 ||
          row.wrongCount != 0) {
        throw StateError('Native checkpoint omitted canonical answers');
      }
      final expectedState = switch (checkpoint) {
        CompletedNativeExercise() => 'completed',
        AbandonedNativeExercise() => 'abandoned',
        _ => 'active',
      };
      if (row.state != expectedState ||
          (row.state == 'abandoned' && row.score != 0) ||
          (row.state == 'active' &&
              (row.endedAtUtcMs != null || row.score != null)) ||
          (row.state != 'active' &&
              row.endedAtUtcMs !=
                  checkpoint.endedAtUtc!.millisecondsSinceEpoch) ||
          row.checkpointRevision < 1) {
        throw StateError('Native checkpoint contradicts canonical session');
      }
    } on NativeExerciseUnavailable {
      rethrow;
    } on Object {
      throw NativeExerciseUnavailable(NativeExerciseUnavailableReason.corrupt);
    }
    if (row.state == 'active') {
      try {
        await _requireNativeTargets(plan.exercise);
      } on Object {
        throw NativeExerciseUnavailable(
          NativeExerciseUnavailableReason.contentChanged,
        );
      }
    }
    return _DriftNativeState(
      issuer: this,
      exercise: issued ?? plan.exercise,
      plan: plan,
      checkpoint: checkpoint,
      checkpointRevision: row.checkpointRevision,
      completedSummary: checkpoint is CompletedNativeExercise
          ? _nativeSummary(row)
          : null,
    );
  }

  Future<db.LearningSession> _requireNativeSession(
    AcceptedNativeExercise exercise,
  ) async {
    final row = await _session(exercise.id);
    if (row == null) throw StateError('Native session is missing');
    _sameNativeSession(row, exercise);
    return row;
  }

  void _sameNativeSession(
    db.LearningSession row,
    AcceptedNativeExercise exercise,
  ) {
    final plan = AcceptedNativePlan(exercise);
    if (row.id != exercise.id ||
        row.ownerId != exercise.ownerId ||
        row.activityType != exercise.session.activityType ||
        row.startedAtUtcMs != exercise.startedAtUtc.millisecondsSinceEpoch ||
        row.appVersion != exercise.session.appVersion ||
        row.buildId != exercise.session.buildId ||
        row.acceptedPlanId != plan.id ||
        row.acceptedPlanJson != plan.stableSerialization ||
        row.checkpointJson == null ||
        row.checkpointRevision < 1 ||
        !{'active', 'completed', 'abandoned'}.contains(row.state)) {
      throw StateError('Native launch identity changed');
    }
    NativeCheckpoint.parse(row.checkpointJson!, plan: plan);
  }

  bool _reconcilesNativeStage(
    _DriftNativeState original,
    _DriftNativeState saved,
    NativeCheckpoint requested,
  ) {
    if (original.plan.id != saved.plan.id ||
        original.plan.stableSerialization != saved.plan.stableSerialization) {
      return false;
    }
    final before = original.checkpoint;
    final current = saved.checkpoint;
    final distance = saved.checkpointRevision - original.checkpointRevision;
    bool sameDraft(NativeCheckpoint left, NativeCheckpoint right) =>
        jsonEncode(left.draft.toJson()) == jsonEncode(right.draft.toJson());
    int? answerPosition(NativeCheckpoint checkpoint) => switch (checkpoint) {
      AwaitingNativeAnswer() => 0,
      PendingNativeAnswer() => 1,
      AnsweredNativeExercise() => 2,
      ClosingNativeExercise() => 3,
      CompletedNativeExercise() => 4,
      AbandonedNativeExercise() => null,
    };
    if (requested is PendingNativeAnswer) {
      final originPosition = answerPosition(before);
      final currentPosition = answerPosition(current);
      final answer = current.answer;
      if (originPosition == null ||
          currentPosition == null ||
          currentPosition < 1 ||
          currentPosition < originPosition ||
          distance != currentPosition - originPosition ||
          answer == null ||
          !sameDraft(requested, current)) {
        return false;
      }
      if (before is AwaitingNativeAnswer) {
        _requireNativeTransition(before, requested);
      } else if (before.answer == null ||
          !_sameNativeCommand(before.answer!, answer) ||
          !sameDraft(before, current)) {
        return false;
      }
      final expected = nativeAnswerJson(answer)
        ..remove('id')
        ..remove('occurredAtUtcMs');
      final proposed = nativeAnswerJson(requested.answer)
        ..remove('id')
        ..remove('occurredAtUtcMs');
      return jsonEncode(expected) == jsonEncode(proposed);
    }
    if (requested is ClosingNativeExercise) {
      final originPosition = answerPosition(before);
      final currentPosition = answerPosition(current);
      if (originPosition == null ||
          originPosition < 2 ||
          currentPosition == null ||
          currentPosition < 3 ||
          currentPosition < originPosition ||
          distance != currentPosition - originPosition ||
          before.answer == null ||
          current.answer == null ||
          !_sameNativeCommand(before.answer!, current.answer!) ||
          !_sameNativeCommand(requested.answer, current.answer!) ||
          !sameDraft(before, current) ||
          !sameDraft(requested, current)) {
        return false;
      }
      if (before is AnsweredNativeExercise) {
        _requireNativeTransition(before, requested);
      } else if (before.endedAtUtc != requested.endedAtUtc) {
        return false;
      }
      return true;
    }
    if (requested is AbandonedNativeExercise &&
        current is AbandonedNativeExercise) {
      if (!sameDraft(before, current) || !sameDraft(requested, current)) {
        return false;
      }
      if (before is AwaitingNativeAnswer && distance == 1) {
        _requireNativeTransition(before, requested);
        return true;
      }
      return before is AbandonedNativeExercise &&
          distance == 0 &&
          before.endedAtUtc == requested.endedAtUtc;
    }
    return false;
  }

  void _requireNativeTransition(
    NativeCheckpoint previous,
    NativeCheckpoint next,
  ) {
    final sameDraft = previous.draft.toJson();
    final draft = next.draft;
    if ((previous.draft.assisted && !draft.assisted) ||
        draft.responseTimeMs < previous.draft.responseTimeMs) {
      throw StateError('Native assistance or response time cannot be reset');
    }
    final allowed =
        (previous is AwaitingNativeAnswer &&
            (next is AwaitingNativeAnswer ||
                next is PendingNativeAnswer ||
                next is AbandonedNativeExercise)) ||
        (previous is AnsweredNativeExercise &&
            next is ClosingNativeExercise &&
            _sameNativeCommand(previous.answer, next.answer) &&
            jsonEncode(sameDraft) == jsonEncode(next.draft.toJson()));
    if (!allowed) throw StateError('Invalid native checkpoint transition');
  }

  Future<void> _writeNativeStorage(
    String sessionId, {
    required AcceptedNativePlan plan,
    required int expectedRevision,
    required NativeCheckpoint checkpoint,
  }) async {
    checkpoint.validate(plan);
    final changed = await database.customUpdate(
      'UPDATE learning_sessions SET accepted_plan_id = ?, accepted_plan_json = ?, '
      'checkpoint_revision = ?, checkpoint_json = ? WHERE id = ? AND owner_id = ? AND checkpoint_revision = ?',
      variables: [
        Variable<String>(plan.id),
        Variable<String>(plan.stableSerialization),
        Variable<int>(expectedRevision + 1),
        Variable<String>(checkpoint.stableSerialization),
        Variable<String>(sessionId),
        Variable<String>(plan.exercise.ownerId),
        Variable<int>(expectedRevision),
      ],
      updates: {database.learningSessions},
    );
    if (changed != 1) {
      throw NativeExerciseUnavailable(
        NativeExerciseUnavailableReason.revisionChanged,
      );
    }
  }

  Future<void> _requireNativeTargets(AcceptedNativeExercise session) async {
    final pins = switch (session) {
      DictationSession() => [(session.word, session.wordContentRevision)],
      WordScrambleSession() => [(session.word, session.wordContentRevision)],
      SentenceScrambleSession() => [
        (session.word, session.wordContentRevision),
      ],
      TypedClozeSession() => [(session.word, session.wordContentRevision)],
      ChoiceClozeSession() => [
        for (final choice in session.choices) (choice, choice.contentRevision!),
      ],
    };
    for (final (target, revision) in pins) {
      final word = await database
          .customSelect(
            'SELECT w.category_id,w.spelling,w.meaning,w.part_of_speech,w.local_revision '
            'FROM vocabulary_words w JOIN vocabulary_categories c '
            'ON c.id = w.category_id AND c.owner_id = w.owner_id '
            'WHERE w.id = ? AND w.owner_id = ? AND w.is_deleted = 0 AND c.is_deleted = 0',
            variables: [Variable(target.id), Variable(session.ownerId)],
          )
          .getSingleOrNull();
      if (word == null ||
          word.read<String>('category_id') != target.categoryId ||
          word.read<String>('spelling') != target.spelling ||
          word.read<String>('meaning') != target.meaning ||
          word.read<String>('part_of_speech') != target.partOfSpeech ||
          'local-vocabulary-v1:${word.read<int>('local_revision')}' !=
              revision) {
        throw StateError('Dictation target changed');
      }
    }
    final source = switch (session) {
      ClozeSession(:final content) => content.source,
      SentenceScrambleSession(:final content) => content.source,
      _ => null,
    };
    if (source is AuthoredSentenceSource) {
      final reader = lexicalContent;
      if (reader == null ||
          !identical(reader.database, database) ||
          !identical(reader.ownerWrites, _ownerWrites) ||
          source.pack.ownerId != session.ownerId) {
        throw StateError('Authored source unavailable');
      }
      final found = await reader.currentLexical(
        expectedOwnerId: session.ownerId,
        wordId: session.word.id,
        packVersionId: source.pack.packVersionId,
        stillCurrent: () => true,
      );
      if (found == null ||
          !found.pack.isInstalled ||
          found.pack.identityConflict ||
          found.pack.manifest.language.split('-').first != 'en' ||
          !_sameNativeWord(session.word, found) ||
          jsonEncode(_nativePackPin(found).toJson()) !=
              jsonEncode(source.pack.toJson()) ||
          found.binding.snapshotId != source.target.snapshotId ||
          found.binding.wordRevision != source.target.wordRevision ||
          found.entry.canonicalJson != source.target.entry.canonicalJson ||
          !_sameNativeWord(source.target.word, found)) {
        throw StateError('Authored native source changed');
      }
      final admitted = switch (session) {
        ClozeSession() =>
          ClozeContent.authored(source).sentence == session.content.sentence &&
              ClozeContent.authored(source).gapStart ==
                  session.content.gapStart &&
              ClozeContent.authored(source).gapEnd == session.content.gapEnd,
        SentenceScrambleSession() =>
          jsonEncode([
                SentenceScrambleContent.authored(source).sentence,
                SentenceScrambleContent.authored(source).tokens,
                SentenceScrambleContent.authored(source).tokenOrder,
              ]) ==
              jsonEncode([
                session.content.sentence,
                session.content.tokens,
                session.content.tokenOrder,
              ]),
        _ => false,
      };
      if (!admitted) throw StateError('Authored native content changed');
    }
  }

  Future<List<db.AnswerAttempt>> _nativeAttempts(
    AcceptedNativeExercise session,
  ) => (database.select(
    database.answerAttempts,
  )..where((attempt) => attempt.sessionId.equals(session.id))).get();

  void _sameNativeAnswer(
    List<db.AnswerAttempt> attempts,
    RecordAnswerCommand command,
  ) {
    if (attempts.length != 1 || !_sameAttempt(attempts.single, command)) {
      throw StateError(
        'Dictation requires exactly its original saved response',
      );
    }
  }

  void _sameNativeOutcome(db.LearningSession row, RecordAnswerCommand command) {
    if (row.correctCount != (command.isCorrect ? 1 : 0) ||
        row.wrongCount != (command.isCorrect ? 0 : 1) ||
        (row.state == 'completed' &&
            row.score != (command.isCorrect ? 100 : 0))) {
      throw StateError('Dictation outcome differs from its original response');
    }
  }

  void _validateNativeAnswer(
    AcceptedNativeExercise session,
    RecordAnswerCommand command,
  ) {
    _validateAnswer(command);
    final draft = command.nativeDraft;
    if (draft == null) {
      throw ArgumentError('Native answer requires its captured response');
    }
    try {
      PendingNativeAnswer(draft, command).validate(AcceptedNativePlan(session));
    } on Object {
      throw ArgumentError('Native response differs from its captured command');
    }
    final context = command.evidenceContext;
    final matchesExercise = switch (session) {
      DictationSession() =>
        command.promptMode == 'dictation' &&
            command.providerProvenance == null &&
            context.skillId == 'dictation-spelling' &&
            ((context.hintLevel == 0 &&
                    context.evidenceClass == EvidenceClass.independentRecall) ||
                (context.hintLevel == 1 &&
                    context.evidenceClass == EvidenceClass.guidedPractice)),
      WordScrambleSession() =>
        command.promptMode == 'wordScramble' &&
            command.providerProvenance == null &&
            context.skillId == 'word-scramble' &&
            context.hintLevel == 0 &&
            context.evidenceClass == EvidenceClass.recreational,
      SentenceScrambleSession() =>
        command.promptMode == 'sentenceScramble' &&
            command.providerProvenance == session.providerProvenance &&
            context.skillId == 'sentence-scramble' &&
            context.hintLevel == 0 &&
            context.evidenceClass == EvidenceClass.recreational,
      TypedClozeSession() =>
        command.promptMode == 'clozeTyped' &&
            command.providerProvenance == session.providerProvenance &&
            context.skillId == 'cloze-context' &&
            context.hintLevel == 1 &&
            context.evidenceClass == EvidenceClass.guidedPractice,
      ChoiceClozeSession() =>
        command.promptMode == 'clozeChoice' &&
            command.providerProvenance == session.providerProvenance &&
            context.skillId == 'cloze-context' &&
            context.hintLevel == 0 &&
            context.evidenceClass == EvidenceClass.recognition,
    };
    if (command.ownerId != session.ownerId ||
        command.sessionId != session.id ||
        command.wordId != session.word.id ||
        command.attemptNumber != 1 ||
        command.occurredAtUtc.isBefore(session.startedAtUtc) ||
        context.contentRevision != session.evidenceContentRevision ||
        context.classificationSource != EvidenceClassificationSource.declared ||
        context.policyVersion != EvidenceContext.currentPolicyVersion ||
        context.engagementAllowed ||
        !matchesExercise) {
      throw ArgumentError(
        'Dictation answer does not match its captured target',
      );
    }
  }

  bool _sameNativeCommand(RecordAnswerCommand a, RecordAnswerCommand b) =>
      (
        a.id,
        a.ownerId,
        a.sessionId,
        a.wordId,
        a.promptMode,
        a.isCorrect,
        a.responseTimeMs,
        a.attemptNumber,
        a.occurredAtUtc,
        a.providerProvenance,
        jsonEncode(a.evidenceContext.toJson()),
        jsonEncode(a.nativeDraft?.toJson()),
      ) ==
      (
        b.id,
        b.ownerId,
        b.sessionId,
        b.wordId,
        b.promptMode,
        b.isCorrect,
        b.responseTimeMs,
        b.attemptNumber,
        b.occurredAtUtc,
        b.providerProvenance,
        jsonEncode(b.evidenceContext.toJson()),
        jsonEncode(b.nativeDraft?.toJson()),
      );

  LearningSessionSummary _nativeSummary(db.LearningSession row) =>
      LearningSessionSummary(
        id: row.id,
        state: row.state,
        correctCount: row.correctCount,
        wrongCount: row.wrongCount,
        score: row.score ?? 0,
      );

  bool _allowsAnswerProjection(
    RecordAnswerCommand command,
    LearningProjection projection,
  ) => LearningEvidenceContract.allowsOrdinaryProjection(
    promptMode: command.promptMode,
    evidenceClass: command.evidenceContext.evidenceClass.name,
    evidenceContextJson: jsonEncode(command.evidenceContext.toJson()),
    projection: projection,
  );

  @override
  Future<AcceptedQuizPlan> prepareLexicalQuizPlan({
    required LearningSessionDraft session,
    required LexicalQuizConfiguration configuration,
    required bool Function() stillCurrent,
  }) async {
    final reader = lexicalContent;
    if (reader == null ||
        !identical(reader.database, database) ||
        !identical(reader.ownerWrites, _ownerWrites)) {
      throw StateError(
        'Lexical content must share the canonical database and owner coordinator',
      );
    }
    _trackConfiguredOwner();
    final epoch = _configuredOwnerEpoch;
    bool current() => epoch == _configuredOwnerEpoch && stillCurrent();
    return _ownerWrites.writeForActiveOwner(
      expectedOwnerId: session.ownerId,
      write: () async {
        if (!current() || session.activityType != 'quiz') {
          throw StateError('Lexical launch is no longer current');
        }
        final plan = await _readLexicalPlan(
          session.ownerId,
          configuration,
          current,
        );
        if (!current()) throw StateError('Lexical owner changed');
        _lexicalBindings[plan] = _LexicalIssuance(session, current);
        return plan;
      },
    );
  }

  Future<AcceptedQuizPlan> _readLexicalPlan(
    String owner,
    LexicalQuizConfiguration configuration,
    bool Function() current,
  ) async {
    final reader = lexicalContent;
    if (reader == null) {
      throw StateError('Owned lexical content reader is unavailable');
    }
    final detail = await reader.detail(
      expectedOwnerId: owner,
      packVersionId: configuration.packVersionId,
      stillCurrent: current,
    );
    if (!current() ||
        !detail.pack.isInstalled ||
        detail.pack.identityConflict ||
        detail.content == null ||
        detail.pack.manifest.language.split('-').first != 'en') {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.contentChanged,
      );
    }
    final source = LexicalPackPin(
      ownerId: detail.pack.ownerId,
      packVersionId: detail.pack.id,
      packId: detail.pack.manifest.packId,
      version: detail.pack.manifest.version,
      packageSha256: detail.pack.packageSha256,
      manifestSha256: sha256
          .convert(utf8.encode(detail.pack.manifest.canonicalJson))
          .toString(),
    );
    final bindings = <String, PackLexicalBinding>{};
    for (final binding in detail.bindings) {
      if (bindings.containsKey(binding.entry.code)) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.contentChanged,
        );
      }
      bindings[binding.entry.code] = binding;
    }
    final codes = configuration.entryCodes
        .take(configuration.limit)
        .toList(growable: false);
    final requiredCodes = <String>{...codes};
    for (final code in codes) {
      final binding = bindings[code];
      if (binding == null || !binding.isCurrent) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.contentChanged,
        );
      }
      if (configuration.input == LexicalQuizInput.definitionChoice) {
        final authored = binding.entry.definitionQuestion;
        if (authored == null) {
          throw const ConfiguredQuizUnavailable(
            ConfiguredQuizUnavailableReason.contentChanged,
          );
        }
        requiredCodes.addAll(
          authored.options.map((option) => option.entryCode),
        );
      }
    }
    final wordIds = <String>[];
    for (final code in requiredCodes) {
      final binding = bindings[code];
      if (binding == null || !binding.isCurrent || binding.word == null) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.contentChanged,
        );
      }
      wordIds.add(binding.wordId);
    }
    final words = <String, QuizWord>{};
    for (var offset = 0; offset < wordIds.length; offset += 100) {
      final chunk = wordIds.skip(offset).take(100).toList(growable: false);
      for (final word in await listQuizWords(
        ownerId: owner,
        wordIds: chunk,
        limit: 100,
      )) {
        words[word.id] = word;
      }
    }
    LexicalEntryPin pin(String code) {
      final binding = bindings[code]!;
      final word = words[binding.wordId];
      if (word == null) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.contentChanged,
        );
      }
      return LexicalEntryPin(
        snapshotId: binding.snapshotId,
        wordRevision: binding.wordRevision,
        word: word,
        entryJson: binding.entry.canonicalJson,
      );
    }

    final questions = <QuizQuestion>[];
    for (final code in codes) {
      final target = pin(code);
      questions.add(
        QuizQuestion.lexical(switch (configuration.input) {
          LexicalQuizInput.definitionTyped => DefinitionTypedContent(
            source: source,
            target: target,
          ),
          LexicalQuizInput.definitionChoice => DefinitionChoiceContent(
            source: source,
            target: target,
            options: [
              for (final option in target.entry.definitionQuestion!.options)
                LexicalDefinitionOption(
                  code: option.code,
                  pin: pin(option.entryCode),
                  contrastiveExplanation: option.contrastiveExplanation,
                ),
            ],
          ),
        }),
      );
    }
    if (!current()) throw StateError('Lexical owner changed');
    return AcceptedQuizPlan.create(
      configuration: QuizConfiguration.lexical(
        lexical: configuration,
        wordIds: questions.map((question) => question.word.id),
      ),
      questions: questions,
    );
  }

  void _requireLexicalIssuance(
    AcceptedQuizPlan plan,
    LearningSessionDraft session,
  ) {
    if (!plan.isLexical) return;
    final issued = _lexicalBindings[plan];
    if (issued == null || issued.retired || !issued.current()) {
      if (issued != null) issued.retired = true;
      throw StateError('Original current lexical launch is required');
    }
    final original = issued.session;
    if (original.id != session.id ||
        original.ownerId != session.ownerId ||
        original.activityType != session.activityType ||
        original.startedAtUtc != session.startedAtUtc ||
        original.appVersion != session.appVersion ||
        original.buildId != session.buildId) {
      throw StateError('Lexical launch identity changed');
    }
  }

  @override
  Future<ConfiguredQuizState?> findConfiguredQuizStart(
    ConfiguredQuizLaunch launch,
  ) => _ownerWrites.writeForActiveOwner(
    expectedOwnerId: launch.session.ownerId,
    write: () async {
      if (launch.configuration.lexical != null) {
        final plan = launch.preparedPlan;
        if (plan == null) throw StateError('Original lexical plan is required');
        _requireLexicalIssuance(plan, launch.session);
      }
      final row = await _session(launch.session.id);
      if (row == null) return null;
      _sameQuizLaunch(row, launch.session);
      final saved = await _readConfigured(row);
      if (saved.plan.configuration.stableSerialization !=
          launch.configuration.stableSerialization) {
        throw StateError('configured quiz launch identity changed');
      }
      if (launch.preparedPlan != null &&
          saved.plan.id != launch.preparedPlan!.id) {
        throw StateError('Accepted lexical plan changed');
      }
      if (launch.preparedPlan != null) {
        _requireLexicalIssuance(launch.preparedPlan!, launch.session);
      }
      return saved;
    },
  );

  @override
  Future<ConfiguredQuizState> startConfiguredQuiz({
    required LearningSessionDraft session,
    required AcceptedQuizPlan plan,
  }) {
    if (session.activityType != plan.activityType) {
      throw ArgumentError('quiz configuration does not match its activity');
    }
    return _ownerWrites.writeForActiveOwner(
      expectedOwnerId: session.ownerId,
      write: () async {
        _requireLexicalIssuance(plan, session);
        final existing = await _session(session.id);
        if (existing != null) {
          _sameQuizLaunch(existing, session);
          final saved = await _readConfigured(existing);
          if (saved.plan.configuration.stableSerialization !=
              plan.configuration.stableSerialization) {
            throw StateError('configured quiz launch identity changed');
          }
          if (plan.isLexical && saved.plan.id != plan.id) {
            throw StateError('Accepted lexical plan changed');
          }
          return saved.asRestored();
        }
        if (!plan.supportsCurrentPolicy) {
          throw const ConfiguredQuizUnavailable(
            ConfiguredQuizUnavailableReason.unsupportedPolicy,
          );
        }
        await _requireQuizContent(session.ownerId, plan);
        final checkpoint = QuizCheckpoint.initial(plan);
        await _startSession(
          session,
          beforeObserved: () => _writeQuizStorage(
            session.id,
            plan: plan,
            revision: 1,
            checkpoint: checkpoint,
          ),
        );
        final saved = await _readConfigured((await _session(session.id))!);
        _requireLexicalIssuance(plan, session);
        return saved;
      },
    );
  }

  /// Read-only plan/checkpoint proof. Callers must check active owner and fence.
  Future<ConfiguredQuizState> inspectConfiguredQuiz({
    required String sessionId,
    required String expectedOwnerId,
  }) => _loadQuiz(sessionId, expectedOwnerId);

  @override
  Future<ConfiguredQuizState> resumeQuiz({
    required String sessionId,
    required String expectedOwnerId,
  }) => _ownerWrites.writeForActiveOwner(
    expectedOwnerId: expectedOwnerId,
    write: () => _loadQuiz(sessionId, expectedOwnerId),
  );

  @override
  Future<ConfiguredQuizState> saveQuizCheckpoint({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
    required QuizCheckpoint checkpoint,
  }) => _ownerWrites.writeForActiveOwner(
    expectedOwnerId: expectedOwnerId,
    write: () async {
      final binding = _quizCheckpointBindings[checkpoint];
      if (binding == null) {
        throw StateError('Original configured checkpoint write is required');
      }
      binding.requireCurrent();
      if (binding.ownerId != expectedOwnerId ||
          binding.sessionId != sessionId ||
          binding.checkpointRevision != expectedRevision ||
          binding.planId != checkpoint.planId) {
        throw StateError('Configured checkpoint read identity changed');
      }
      final saved = await _loadQuiz(sessionId, expectedOwnerId);
      checkpoint.validateFor(saved.plan);
      if (expectedRevision < 1) {
        throw StateError('invalid quiz checkpoint revision');
      }
      if (checkpoint.stableSerialization ==
              saved.checkpoint.stableSerialization &&
          expectedRevision <= saved.checkpointRevision) {
        binding.requireCurrent();
        return saved;
      }
      if (binding.checkpointJson != saved.checkpoint.stableSerialization) {
        throw StateError('Configured checkpoint read changed');
      }
      if (expectedRevision != saved.checkpointRevision ||
          saved.state != 'active') {
        throw StateError('quiz checkpoint changed');
      }
      _requireQuizTransition(saved, checkpoint);
      if (checkpoint is AwaitingQuizAnswer || checkpoint is PendingQuizAnswer) {
        await _requireQuizContent(expectedOwnerId, saved.plan);
      }
      if (checkpoint is AbandonedQuizSession) {
        await database.customUpdate(
          "UPDATE learning_sessions SET state = 'abandoned', ended_at_utc_ms = ? "
          "WHERE id = ? AND owner_id = ? AND state = 'active'",
          variables: [
            Variable<int>(checkpoint.close.endedAtUtcMs),
            Variable<String>(sessionId),
            Variable<String>(expectedOwnerId),
          ],
          updates: {database.learningSessions},
        );
      }
      await _writeQuizStorage(
        sessionId,
        plan: saved.plan,
        revision: saved.checkpointRevision + 1,
        checkpoint: checkpoint,
        expectedRevision: expectedRevision,
      );
      final result = await _loadQuiz(sessionId, expectedOwnerId);
      binding.requireCurrent();
      await _requireTimeReadOwner(expectedOwnerId, () => true);
      binding.requireCurrent();
      return result;
    },
  );

  @override
  Future<ConfiguredQuizAnswerResult> commitQuizAnswer({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
  }) => _ownerWrites.writeForActiveOwner(
    expectedOwnerId: expectedOwnerId,
    write: () async {
      final saved = await _loadQuiz(sessionId, expectedOwnerId);
      final checkpoint = saved.checkpoint;
      if (checkpoint is AnsweredQuizQuestion) {
        if (expectedRevision < saved.checkpointRevision - 1 ||
            expectedRevision > saved.checkpointRevision) {
          throw StateError('quiz checkpoint changed');
        }
        return ConfiguredQuizAnswerResult(
          state: saved,
          record: AnswerRecordResult(
            inserted: false,
            srs: await _quizReplaySrs(sessionId, checkpoint.answer),
          ),
        );
      }
      if (checkpoint is! PendingQuizAnswer ||
          saved.state != 'active' ||
          expectedRevision != saved.checkpointRevision) {
        throw StateError('pending quiz answer was not found');
      }
      if (checkpoint.answer.capturedOwnerId != expectedOwnerId) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.ownerChanged,
        );
      }
      final command = checkpoint.answer.toCommand(sessionId: sessionId);
      final existing = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(command.id))).getSingleOrNull();
      if (existing != null && !_sameAttempt(existing, command)) {
        throw StateError('attempt id already exists with different evidence');
      }
      final record = existing == null
          ? await _recordAnswer(command)
          : AnswerRecordResult(
              inserted: false,
              srs: await _quizReplaySrs(sessionId, checkpoint.answer),
            );
      await _writeQuizStorage(
        sessionId,
        plan: saved.plan,
        revision: saved.checkpointRevision + 1,
        checkpoint: AnsweredQuizQuestion(
          planId: saved.plan.id,
          questionOrdinal: checkpoint.questionOrdinal,
          assistance: checkpoint.assistance,
          answer: checkpoint.answer,
          lexical: checkpoint.lexical,
        ),
        expectedRevision: expectedRevision,
      );
      return ConfiguredQuizAnswerResult(
        state: await _loadQuiz(sessionId, expectedOwnerId),
        record: record,
      );
    },
  );

  @override
  Future<ConfiguredQuizFinishResult> finishConfiguredQuiz({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
  }) => _ownerWrites.writeForActiveOwner(
    expectedOwnerId: expectedOwnerId,
    write: () async {
      final saved = await _loadQuiz(sessionId, expectedOwnerId);
      final checkpoint = saved.checkpoint;
      if (checkpoint is! ClosingQuizSession &&
          checkpoint is! CompletedQuizSession) {
        throw StateError('quiz closing receipt was not found');
      }
      if (expectedRevision < saved.checkpointRevision - 1 ||
          expectedRevision > saved.checkpointRevision ||
          (checkpoint is ClosingQuizSession &&
              expectedRevision != saved.checkpointRevision)) {
        throw StateError('quiz checkpoint changed');
      }
      final close = checkpoint.close!;
      if (close.capturedOwnerId != expectedOwnerId) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.ownerChanged,
        );
      }
      if (checkpoint is ClosingQuizSession && saved.plan.isLexical) {
        await _requireQuizContent(expectedOwnerId, saved.plan);
      }
      final summary = await _finishSession(
        ownerId: expectedOwnerId,
        sessionId: sessionId,
        endedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          close.endedAtUtcMs,
          isUtc: true,
        ),
        observe: false,
      );
      if (checkpoint is ClosingQuizSession) {
        await _writeQuizStorage(
          sessionId,
          plan: saved.plan,
          revision: saved.checkpointRevision + 1,
          checkpoint: CompletedQuizSession(
            planId: saved.plan.id,
            questionOrdinal: checkpoint.questionOrdinal,
            assistance: checkpoint.assistance,
            lexical: checkpoint.lexical,
            close: close,
          ),
          expectedRevision: expectedRevision,
        );
      }
      final completed = (await _session(sessionId))!;
      final observer = lifecycleObserver;
      if (observer != null) {
        await _observe(
          () => observer.completed(
            LearningSessionLifecycleFact.fromRow(completed),
          ),
        );
      }
      if (checkpoint is ClosingQuizSession && saved.plan.isLexical) {
        await _requireQuizContent(expectedOwnerId, saved.plan);
      }
      return ConfiguredQuizFinishResult(
        state: await _loadQuiz(sessionId, expectedOwnerId),
        summary: summary,
      );
    },
  );

  Future<db.LearningSession?> _session(String id) => (database.select(
    database.learningSessions,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<bool> _requiresDedicatedWriter(String sessionId) async =>
      (await database
              .customSelect(
                'SELECT activity_type, accepted_plan_id, accepted_plan_json, checkpoint_revision, checkpoint_json '
                'FROM learning_sessions WHERE id = ?',
                variables: [Variable<String>(sessionId)],
                readsFrom: {database.learningSessions},
              )
              .getSingleOrNull())
          ?.data
          .entries
          .any(
            (entry) => switch (entry.key) {
              'activity_type' =>
                entry.value == MatchingPlan.activityType ||
                    entry.value == 'sentenceScramble' ||
                    _srsActivities.contains(entry.value),
              'checkpoint_revision' => entry.value != 0,
              _ => entry.value != null,
            },
          ) ??
      false;

  void _sameQuizLaunch(db.LearningSession row, LearningSessionDraft session) {
    if (row.ownerId != session.ownerId ||
        row.activityType != session.activityType ||
        row.startedAtUtcMs != session.startedAtUtc?.millisecondsSinceEpoch ||
        row.appVersion != session.appVersion ||
        row.buildId != session.buildId) {
      throw StateError('configured quiz id already exists with another launch');
    }
  }

  Future<ConfiguredQuizState> _loadQuiz(String id, String owner) async {
    final row = await _session(id);
    if (row == null) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.notFound,
      );
    }
    if (row.ownerId != owner) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.ownerChanged,
      );
    }
    return _readConfigured(row);
  }

  Future<ConfiguredQuizState> _readConfigured(db.LearningSession row) async {
    _trackConfiguredOwner();
    final ownerEpoch = _configuredOwnerEpoch;
    if (row.activityType == 'syncedEvidence' || row.state == 'syncedEvidence') {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.syncedEvidence,
      );
    }
    final storage = await database
        .customSelect(
          'SELECT accepted_plan_id, accepted_plan_json, checkpoint_revision, checkpoint_json '
          'FROM learning_sessions WHERE id = ?',
          variables: [Variable<String>(row.id)],
          readsFrom: {database.learningSessions},
        )
        .getSingle();
    final id = storage.readNullable<String>('accepted_plan_id');
    final json = storage.readNullable<String>('accepted_plan_json');
    final revision = storage.read<int>('checkpoint_revision');
    final checkpointJson = storage.readNullable<String>('checkpoint_json');
    if (id?.startsWith(AcceptedNativePlan.idPrefix) == true) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.legacy,
      );
    }
    if (id == null && json == null && revision == 0 && checkpointJson == null) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.legacy,
      );
    }
    late AcceptedQuizPlan plan;
    late QuizCheckpoint checkpoint;
    try {
      if (id == null ||
          json == null ||
          checkpointJson == null ||
          revision < 1) {
        throw const FormatException('partial configured quiz storage');
      }
      plan = AcceptedQuizPlan.parse(id: id, json: json);
      checkpoint = QuizCheckpoint.parse(checkpointJson, plan: plan);
      if (row.activityType != plan.activityType ||
          row.startedAtUtcMs < 0 ||
          (checkpoint is CompletedQuizSession
              ? row.state != 'completed'
              : checkpoint is AbandonedQuizSession
              ? row.state != 'abandoned'
              : row.state != 'active')) {
        throw const FormatException(
          'quiz checkpoint contradicts canonical session',
        );
      }
      final close = checkpoint.close;
      if (close != null &&
          (close.endedAtUtcMs < row.startedAtUtcMs ||
              (row.state != 'active' &&
                  row.endedAtUtcMs != close.endedAtUtcMs))) {
        throw const FormatException('quiz terminal receipt changed');
      }
      if (row.state == 'active' && row.endedAtUtcMs != null) {
        throw const FormatException('active quiz has terminal time');
      }
    } on Object {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.corrupt,
      );
    }
    if (plan.isLexical &&
        plan.questions.any(
          (question) => question.lexical!.source.ownerId != row.ownerId,
        )) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.ownerChanged,
      );
    }
    await _requireTimeReadOwner(row.ownerId, () => true);
    if (checkpoint.answer?.capturedOwnerId != null &&
        checkpoint.answer!.capturedOwnerId != row.ownerId) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.ownerChanged,
      );
    }
    if (checkpoint.close?.capturedOwnerId != null &&
        checkpoint.close!.capturedOwnerId != row.ownerId) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.ownerChanged,
      );
    }
    final attempts = await _requireQuizAttempts(row, plan, checkpoint);
    final needsFreshInput =
        checkpoint is AwaitingQuizAnswer ||
        (checkpoint is PendingQuizAnswer &&
            attempts.length == checkpoint.questionOrdinal);
    if (row.state == 'active' && (needsFreshInput || plan.isLexical)) {
      await _requireQuizContent(row.ownerId, plan);
    }
    if (ownerEpoch != _configuredOwnerEpoch) {
      throw StateError('Configured quiz owner changed during read');
    }
    return ConfiguredQuizState(
      sessionId: row.id,
      ownerId: row.ownerId,
      activityType: row.activityType,
      startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.startedAtUtcMs,
        isUtc: true,
      ),
      appVersion: row.appVersion,
      buildId: row.buildId,
      state: row.state,
      endedAtUtc: _fromEpoch(row.endedAtUtcMs),
      plan: plan,
      checkpointRevision: revision,
      checkpoint: checkpoint,
      readBinding: _DriftConfiguredQuizReadBinding(
        issuer: this,
        ownerId: row.ownerId,
        sessionId: row.id,
        planId: plan.id,
        checkpointRevision: revision,
        checkpointJson: checkpoint.stableSerialization,
        ownerEpoch: ownerEpoch,
      ),
      mistakeWords: [
        for (var index = 0; index < attempts.length; index++)
          if (!attempts[index].isCorrect) plan.questions[index].word,
      ],
    );
  }

  Future<void> _requireQuizContent(String owner, AcceptedQuizPlan plan) async {
    if (!plan.supportsCurrentPolicy) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.unsupportedPolicy,
      );
    }
    if (plan.isLexical) {
      try {
        final actual = await _readLexicalPlan(
          owner,
          plan.configuration.lexical!,
          () => true,
        );
        if (actual.id != plan.id ||
            actual.stableSerialization != plan.stableSerialization) {
          throw const ConfiguredQuizUnavailable(
            ConfiguredQuizUnavailableReason.contentChanged,
          );
        }
      } on ConfiguredQuizUnavailable {
        rethrow;
      } on Object {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.contentChanged,
        );
      }
      return;
    }
    final checkedCategories = <String>{};
    for (final question in plan.questions) {
      final word =
          await (database.select(database.vocabularyWords)..where(
                (row) =>
                    row.id.equals(question.word.id) &
                    row.ownerId.equals(owner) &
                    row.isDeleted.equals(false),
              ))
              .getSingleOrNull();
      if (word == null ||
          quizWordChecksum(
                QuizWord(
                  id: word.id,
                  categoryId: word.categoryId,
                  spelling: word.spelling,
                  meaning: word.meaning,
                  partOfSpeech: word.partOfSpeech,
                  contentRevision: 'local-vocabulary-v1:${word.localRevision}',
                ),
              ) !=
              quizWordChecksum(question.word)) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.contentChanged,
        );
      }
      if (checkedCategories.add(question.word.categoryId)) {
        final category =
            await (database.select(database.vocabularyCategories)..where(
                  (row) =>
                      row.id.equals(question.word.categoryId) &
                      row.ownerId.equals(owner) &
                      row.isDeleted.equals(false),
                ))
                .getSingleOrNull();
        if (category == null) {
          throw const ConfiguredQuizUnavailable(
            ConfiguredQuizUnavailableReason.contentChanged,
          );
        }
      }
    }
  }

  Future<List<db.AnswerAttempt>> _requireQuizAttempts(
    db.LearningSession session,
    AcceptedQuizPlan plan,
    QuizCheckpoint checkpoint,
  ) async {
    final attempts =
        await (database.select(database.answerAttempts)
              ..where((row) => row.sessionId.equals(session.id))
              ..orderBy([(row) => OrderingTerm.asc(row.attemptNumber)]))
            .get();
    var requiredCount = checkpoint.questionOrdinal;
    if (checkpoint is AnsweredQuizQuestion) requiredCount++;
    if (checkpoint is ClosingQuizSession ||
        checkpoint is CompletedQuizSession) {
      requiredCount = plan.questions.length;
    }
    final pendingExists =
        checkpoint is PendingQuizAnswer && attempts.length == requiredCount + 1;
    final abandonedAnswered =
        checkpoint is AbandonedQuizSession &&
        attempts.length == requiredCount + 1;
    if (attempts.length != requiredCount &&
        !pendingExists &&
        !abandonedAnswered) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.corrupt,
      );
    }
    if (checkpoint.lexical case final LexicalTypedLocalData local) {
      final expected = checkpoint is PendingQuizAnswer
          ? checkpoint.questionOrdinal + 1
          : attempts.length;
      if (local.responses.length != expected) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.corrupt,
        );
      }
    }
    for (var index = 0; index < attempts.length; index++) {
      final attempt = attempts[index];
      final question = plan.questions[index];
      EvidenceContext evidence;
      try {
        evidence = EvidenceContext.fromJson(
          jsonDecode(attempt.evidenceContextJson) as Map<String, dynamic>,
        );
      } on Object {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.corrupt,
        );
      }
      if (checkpoint.lexical case final LexicalTypedLocalData local) {
        final text = local.responses[index];
        final revealed = evidence.hintLevel == 2;
        if (!local.responses.containsKey(index) ||
            (revealed ? text != null : text == null) ||
            attempt.isCorrect !=
                (!revealed &&
                    text != null &&
                    normalizeLexicalResponse(text) ==
                        normalizeLexicalResponse(question.correctAnswer))) {
          throw const ConfiguredQuizUnavailable(
            ConfiguredQuizUnavailableReason.corrupt,
          );
        }
      }
      if (attempt.ownerId != session.ownerId ||
          attempt.attemptNumber != index + 1 ||
          attempt.wordId != question.word.id ||
          attempt.promptMode != question.promptMode ||
          attempt.occurredAtUtcMs < session.startedAtUtcMs ||
          evidence.contentRevision != question.evidenceContentRevision ||
          (!plan.configuration.allowsHints && evidence.hintLevel == 1) ||
          (question.lexical != null &&
              (evidence.skillId != question.skillId ||
                  evidence.hintLevel < 0 ||
                  evidence.hintLevel > 2 ||
                  evidence.classificationSource !=
                      EvidenceClassificationSource.declared ||
                  evidence.policyVersion != plan.evidencePolicyVersion ||
                  evidence.featureContractHash != plan.featureContractHash ||
                  evidence.featureContractRevision !=
                      plan.featureContractRevision ||
                  evidence.engagementAllowed ||
                  evidence.evidenceClass !=
                      (evidence.hintLevel == 0
                          ? question.unassistedEvidenceClass
                          : EvidenceClass.guidedPractice))) ||
          !LearningEvidenceContract.isOrdinaryEvidence(evidence)) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.corrupt,
        );
      }
    }
    final answer = checkpoint.answer;
    if (answer != null) {
      if (answer.occurredAtUtcMs < session.startedAtUtcMs) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.corrupt,
        );
      }
      if ((checkpoint is AnsweredQuizQuestion || pendingExists) &&
          !_sameAttempt(
            attempts[checkpoint.questionOrdinal],
            answer.toCommand(sessionId: session.id),
          )) {
        throw const ConfiguredQuizUnavailable(
          ConfiguredQuizUnavailableReason.corrupt,
        );
      }
    }
    final close = checkpoint.close;
    if (close != null &&
        attempts.any((row) => row.occurredAtUtcMs > close.endedAtUtcMs)) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.corrupt,
      );
    }
    final correct = attempts.where((attempt) => attempt.isCorrect).length;
    if (session.correctCount != correct ||
        session.wrongCount != attempts.length - correct) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.corrupt,
      );
    }
    return attempts;
  }

  void _requireQuizTransition(ConfiguredQuizState saved, QuizCheckpoint next) {
    final previous = saved.checkpoint;
    if (previous.lexical case final LexicalTypedLocalData oldLocal) {
      final nextLocal = next.lexical;
      if (nextLocal is! LexicalTypedLocalData ||
          oldLocal.responses.entries.any(
            (entry) =>
                !nextLocal.responses.containsKey(entry.key) ||
                nextLocal.responses[entry.key] != entry.value,
          )) {
        throw StateError('Accepted private typed response changed');
      }
    }
    if (next.planId != saved.plan.id) throw StateError('quiz plan changed');
    final oldAssistance = previous.assistance;
    final assistance = next.assistance;
    if ((oldAssistance.hintFirstShownAtUtcMs != null &&
            assistance.hintFirstShownAtUtcMs !=
                oldAssistance.hintFirstShownAtUtcMs) ||
        (oldAssistance.revealRequestedAtUtcMs != null &&
            assistance.revealRequestedAtUtcMs !=
                oldAssistance.revealRequestedAtUtcMs)) {
      if (previous is! AnsweredQuizQuestion ||
          next is! AwaitingQuizAnswer ||
          next.questionOrdinal != previous.questionOrdinal + 1) {
        throw StateError('quiz assistance receipt changed');
      }
    }
    final sameItem = previous.questionOrdinal == next.questionOrdinal;
    final allowed =
        (previous is AwaitingQuizAnswer &&
            sameItem &&
            (next is AwaitingQuizAnswer || next is PendingQuizAnswer)) ||
        (previous is AnsweredQuizQuestion &&
            next is AwaitingQuizAnswer &&
            next.questionOrdinal == previous.questionOrdinal + 1 &&
            jsonEncode(next.assistance.toJson()) ==
                jsonEncode(QuizAssistance().toJson())) ||
        (previous is AnsweredQuizQuestion &&
            next is ClosingQuizSession &&
            sameItem &&
            next.questionOrdinal == saved.plan.questions.length - 1) ||
        (previous is! PendingQuizAnswer &&
            previous is! ClosingQuizSession &&
            next is AbandonedQuizSession &&
            sameItem);
    if (!allowed) throw StateError('invalid quiz checkpoint transition');
    final answer = next.answer;
    final close = next.close;
    final hint = assistance.hintFirstShownAtUtcMs;
    final reveal = assistance.revealRequestedAtUtcMs;
    if ((answer != null && answer.capturedOwnerId != saved.ownerId) ||
        (close != null && close.capturedOwnerId != saved.ownerId) ||
        (answer != null &&
            answer.occurredAtUtcMs <
                saved.startedAtUtc.millisecondsSinceEpoch) ||
        (close != null &&
            close.endedAtUtcMs < saved.startedAtUtc.millisecondsSinceEpoch) ||
        (hint != null && hint < saved.startedAtUtc.millisecondsSinceEpoch) ||
        (reveal != null &&
            reveal < saved.startedAtUtc.millisecondsSinceEpoch)) {
      throw StateError('quiz receipt owner or time changed');
    }
  }

  Future<void> _writeQuizStorage(
    String sessionId, {
    required AcceptedQuizPlan plan,
    required int revision,
    required QuizCheckpoint checkpoint,
    int? expectedRevision,
  }) async {
    checkpoint.validateFor(plan);
    final changed = await database.customUpdate(
      'UPDATE learning_sessions SET accepted_plan_id = ?, accepted_plan_json = ?, '
      'checkpoint_revision = ?, checkpoint_json = ? WHERE id = ?'
      '${expectedRevision == null ? '' : ' AND checkpoint_revision = ?'}',
      variables: [
        Variable<String>(plan.id),
        Variable<String>(plan.stableSerialization),
        Variable<int>(revision),
        Variable<String>(checkpoint.stableSerialization),
        Variable<String>(sessionId),
        if (expectedRevision != null) Variable<int>(expectedRevision),
      ],
      updates: {database.learningSessions},
    );
    if (changed != 1) throw StateError('quiz checkpoint changed');
  }

  Future<SrsSnapshot> _savedQuizSrs(String ownerId, String wordId) async {
    final saved = await _readSavedSrs(ownerId, wordId);
    if (saved == null) {
      throw const ConfiguredQuizUnavailable(
        ConfiguredQuizUnavailableReason.corrupt,
      );
    }
    return saved;
  }

  Future<SrsSnapshot?> _quizReplaySrs(
    String sessionId,
    QuizAnswerReceipt answer,
  ) =>
      _allowsAnswerProjection(
        answer.toCommand(sessionId: sessionId),
        LearningProjection.masterySrs,
      )
      ? _savedQuizSrs(answer.capturedOwnerId, answer.wordId)
      : _readSavedSrs(answer.capturedOwnerId, answer.wordId);

  Future<SrsSnapshot?> _readSavedSrs(String ownerId, String wordId) async {
    final row =
        await (database.select(database.srsStates)..where(
              (row) => row.ownerId.equals(ownerId) & row.wordId.equals(wordId),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return SrsSnapshot(
      intervalDays: row.intervalDays,
      repetitions: row.repetitions,
      lapses: row.lapses,
      stability: row.stability,
      difficulty: row.difficulty,
      lastReviewAtUtc: _fromEpoch(row.lastReviewAtUtcMs),
      dueAtUtc: _fromEpoch(row.dueAtUtcMs),
      algorithmVersion: row.algorithmVersion,
    );
  }

  Future<void> _observe(Future<void> Function() callback) async {
    try {
      await database.transaction(callback, requireNew: true);
    } on Object {
      // The research savepoint rolls back while canonical learning continues.
    }
  }

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) async {
    _requiredUtc(nowUtc, 'nowUtc');
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final words = database.vocabularyWords;
    final srs = database.srsStates;
    final categories = database.vocabularyCategories;
    final query =
        database.select(words).join([
            innerJoin(
              srs,
              srs.wordId.equalsExp(words.id) &
                  srs.ownerId.equals(ownerId) &
                  srs.dueAtUtcMs.isSmallerOrEqualValue(
                    nowUtc.millisecondsSinceEpoch,
                  ),
            ),
            innerJoin(
              categories,
              categories.id.equalsExp(words.categoryId) &
                  categories.ownerId.equalsExp(words.ownerId) &
                  categories.isDeleted.equals(false),
              useColumns: false,
            ),
          ])
          ..where(words.ownerId.equals(ownerId) & words.isDeleted.equals(false))
          ..orderBy([
            OrderingTerm.asc(srs.dueAtUtcMs),
            OrderingTerm.asc(words.id),
          ])
          ..limit(limit);
    final rows = await query.get();
    return rows
        .map((row) => row.readTable(words))
        .map(
          (word) => QuizWord(
            id: word.id,
            categoryId: word.categoryId,
            spelling: word.spelling,
            meaning: word.meaning,
            partOfSpeech: word.partOfSpeech,
            contentRevision: 'local-vocabulary-v1:${word.localRevision}',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async {
    final row =
        await (database.select(database.readingProgressEntries)..where(
              (candidate) =>
                  candidate.ownerId.equals(ownerId) &
                  candidate.documentId.equals(documentId) &
                  candidate.documentRevision.equals(documentRevision),
            ))
            .getSingleOrNull();
    return row == null ? null : _readingSnapshot(row);
  }

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) {
    _validateReading(command);
    return database.transaction(() async {
      final activeOwner =
          await (database.select(database.localOwners)..where(
                (row) =>
                    row.id.equals(command.ownerId) & row.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (activeOwner == null) {
        throw StateError('reading owner is no longer active');
      }
      final priorEvent = await (database.select(
        database.readingEvents,
      )..where((row) => row.id.equals(command.eventId))).getSingleOrNull();
      if (priorEvent != null) {
        if (!_sameReadingEvent(priorEvent, command)) {
          throw StateError(
            'reading event id already exists with different evidence',
          );
        }
        return projections.rebuildReading(
          ownerId: command.ownerId,
          documentId: command.documentId,
          documentRevision: command.documentRevision,
        );
      }
      await database
          .into(database.readingEvents)
          .insert(
            db.ReadingEventsCompanion.insert(
              id: command.eventId,
              ownerId: command.ownerId,
              documentId: command.documentId,
              documentRevision: Value(command.documentRevision),
              eventType: command.isCompleted ? 'completed' : 'checkpoint',
              position: Value(command.position),
              occurredAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
            ),
          );
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'readingEvent',
        entityId: command.eventId,
        occurredAtUtc: command.occurredAtUtc,
      );
      return projections.rebuildReading(
        ownerId: command.ownerId,
        documentId: command.documentId,
        documentRevision: command.documentRevision,
      );
    });
  }

  Future<void> _unlockAchievement({
    required String ownerId,
    required String achievementId,
    required String sourceEventId,
    required DateTime unlockedAtUtc,
  }) async {
    const definitionVersion = 1;
    final achievementId_ =
        'achievement:$ownerId:$achievementId:$definitionVersion';
    await database
        .into(database.achievementUnlocks)
        .insert(
          db.AchievementUnlocksCompanion.insert(
            id: achievementId_,
            ownerId: ownerId,
            achievementId: achievementId,
            definitionVersion: definitionVersion,
            sourceEventId: sourceEventId,
            unlockedAtUtcMs: unlockedAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    // Outbox hook — sync achievement unlock to Firestore (Phase 0 Week 12-13).
    await _appendImmutableOutbox(
      ownerId: ownerId,
      entityType: 'achievementUnlock',
      entityId: achievementId_,
      occurredAtUtc: unlockedAtUtc,
    );
  }

  Future<void> _appendImmutableOutbox({
    required String ownerId,
    required String entityType,
    required String entityId,
    required DateTime occurredAtUtc,
    int payloadVersion = 1,
  }) async {
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId: '$entityType:$entityId:1',
            ownerId: ownerId,
            entityType: entityType,
            entityId: entityId,
            operationKind: 'upsert',
            payloadVersion: Value(payloadVersion),
            baseRevision: const Value(0),
            createdAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _rebuildOptionalRewards(String ownerId) async {
    try {
      await rewardProjections.rebuild(ownerId);
    } catch (_) {
      // Reward savepoint rolls back; immutable local learning still commits.
    }
  }

  bool _sameAttempt(db.AnswerAttempt row, RecordAnswerCommand command) {
    return row.id == command.id &&
        row.ownerId == command.ownerId &&
        row.sessionId == command.sessionId &&
        row.wordId == command.wordId &&
        row.promptMode == command.promptMode &&
        row.isCorrect == command.isCorrect &&
        row.responseTimeMs == command.responseTimeMs &&
        row.attemptNumber == command.attemptNumber &&
        row.occurredAtUtcMs == command.occurredAtUtc.millisecondsSinceEpoch &&
        row.providerProvenance == command.providerProvenance &&
        row.evidenceClass == command.evidenceContext.evidenceClass.name &&
        jsonEncode(
              EvidenceContext.fromJson(
                jsonDecode(row.evidenceContextJson) as Map<String, dynamic>,
              ).toJson(),
            ) ==
            jsonEncode(command.evidenceContext.toJson());
  }

  bool _sameReadingEvent(db.ReadingEvent row, ReadingProgressCommand command) {
    return row.ownerId == command.ownerId &&
        row.documentId == command.documentId &&
        row.documentRevision == command.documentRevision &&
        row.eventType == (command.isCompleted ? 'completed' : 'checkpoint') &&
        row.position == command.position &&
        row.occurredAtUtcMs == command.occurredAtUtc.millisecondsSinceEpoch;
  }

  ReadingProgressSnapshot _readingSnapshot(db.ReadingProgressEntry row) {
    return ReadingProgressSnapshot(
      documentId: row.documentId,
      documentRevision: row.documentRevision,
      lastPosition: row.lastPosition,
      isCompleted: row.isCompleted,
      updatedAtUtc: _fromEpoch(row.updatedAtUtcMs)!,
    );
  }

  void _validateAnswer(RecordAnswerCommand command) {
    final occurredAt = _requiredUtc(command.occurredAtUtc, 'occurredAtUtc');
    if (!LearningEvidenceContract.validAttempt(
      id: command.id,
      ownerId: command.ownerId,
      sessionId: command.sessionId,
      wordId: command.wordId,
      promptMode: command.promptMode,
      responseTimeMs: command.responseTimeMs,
      attemptNumber: command.attemptNumber,
      occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
      providerProvenance: command.providerProvenance,
      evidenceClass: command.evidenceContext.evidenceClass.name,
      evidenceContextJson: jsonEncode(command.evidenceContext.toJson()),
    )) {
      throw ArgumentError.value(command, 'command', 'invalid answer evidence');
    }
  }

  void _validateReading(ReadingProgressCommand command) {
    final occurredAt = _requiredUtc(command.occurredAtUtc, 'occurredAtUtc');
    if (!LearningEvidenceContract.validReading(
      eventId: command.eventId,
      ownerId: command.ownerId,
      documentId: command.documentId,
      documentRevision: command.documentRevision,
      eventType: command.isCompleted ? 'completed' : 'checkpoint',
      position: command.position,
      occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
    )) {
      throw ArgumentError.value(command, 'command', 'invalid reading evidence');
    }
  }

  String _required(String value, String field) {
    final result = value.trim();
    if (result.isEmpty) throw ArgumentError.value(value, field, 'blank');
    return result;
  }

  DateTime _requiredUtc(DateTime? value, String field) {
    if (value == null || !value.isUtc) {
      throw ArgumentError.value(value, field, 'must be UTC');
    }
    return value;
  }

  DateTime? _fromEpoch(int? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}

final class _DriftConfiguredQuizReadBinding
    implements ConfiguredQuizReadBinding {
  _DriftConfiguredQuizReadBinding({
    required this.issuer,
    required this.ownerId,
    required this.sessionId,
    required this.planId,
    required this.checkpointRevision,
    required this.checkpointJson,
    required this.ownerEpoch,
  });
  final DriftLearningRepository issuer;
  final String ownerId;
  final String sessionId;
  final String planId;
  final int checkpointRevision;
  final String checkpointJson;
  final int ownerEpoch;
  bool retired = false;

  @override
  void requireCurrent() {
    if (retired || ownerEpoch != issuer._configuredOwnerEpoch) {
      retired = true;
      throw StateError('Configured quiz read owner is no longer current');
    }
  }

  @override
  QuizCheckpoint bindCheckpointWrite(QuizCheckpoint checkpoint) {
    requireCurrent();
    if (checkpoint.planId != planId) {
      throw StateError('Configured checkpoint plan changed');
    }
    issuer._quizCheckpointBindings[checkpoint] = this;
    return checkpoint;
  }
}

final class _LexicalIssuance {
  _LexicalIssuance(this.session, this.current);
  final LearningSessionDraft session;
  final bool Function() current;
  bool retired = false;
}

final class _NativeIssuance {
  _NativeIssuance(this.current);
  final bool Function() current;
  bool retired = false;
  bool startAttempted = false;
  bool started = false;
}

final class _DriftNativeState implements NativeExerciseState {
  const _DriftNativeState({
    required this.issuer,
    required this.exercise,
    required this.plan,
    required this.checkpoint,
    required this.checkpointRevision,
    this.completedSummary,
  });
  final DriftLearningRepository issuer;
  @override
  final AcceptedNativeExercise exercise;
  @override
  final AcceptedNativePlan plan;
  @override
  final NativeCheckpoint checkpoint;
  @override
  final int checkpointRevision;
  @override
  final LearningSessionSummary? completedSummary;
  @override
  NativeCheckpointPhase get phase => checkpoint.phase;
}

const _srsActivities = <String>{'srsReview', 'flashcard', 'flashcards'};

final class _SrsReviewBinding {
  _SrsReviewBinding(this.current);
  final bool Function() current;
  bool invalidated = false;
  bool startAttempted = false;
  bool started = false;
  bool finishAttempted = false;
  final answers = <int, SrsReviewAnswerIntent>{};
  SrsReviewFinishIntent? closing;
}

final class _CanonicalTimeBinding {
  const _CanonicalTimeBinding({
    required this.request,
    required this.sessionFingerprint,
  });
  final CanonicalLearningTimeAdmissionRequest request;
  final String sessionFingerprint;
}

final class _DriftCanonicalLearningTimeAdmission
    implements CanonicalLearningTimeAdmission {
  const _DriftCanonicalLearningTimeAdmission({
    required this.ownerId,
    required this.sessionId,
    required this.activityType,
    required this.sourceKind,
    required this.sourceBindingJson,
    required this.contextBindingJson,
    required this.evidenceContext,
  });
  @override
  final String ownerId;
  @override
  final String sessionId;
  @override
  final String activityType;
  @override
  final CanonicalLearningTimeSourceKind sourceKind;
  @override
  final String sourceBindingJson;
  @override
  final String contextBindingJson;
  @override
  final EvidenceContext evidenceContext;
}

final class _DriftSourceBoundVocabularyStart
    implements PreparedSourceBoundVocabularyStart {
  _DriftSourceBoundVocabularyStart({
    required this.session,
    required this.words,
    required this.presentation,
    required this.source,
    required this.callerContext,
  });
  final LearningSessionDraft session;
  final List<QuizWord> words;
  @override
  final QuizSession presentation;
  @override
  final VocabularyLearningTimeSourcePin source;
  @override
  final LearningTimeCallerContext callerContext;
  @override
  String get ownerId => session.ownerId;
  @override
  String get sessionId => session.id;
  bool startAttempted = false;
  bool started = false;
}

final class _DriftVocabularySessionLinkReceipt
    implements CanonicalLearningTimeSessionLinkReceipt {
  const _DriftVocabularySessionLinkReceipt({
    required this.ownerId,
    required this.sessionId,
    required this.activityType,
    required this.sourceKind,
    required this.sourceBindingJson,
  });
  @override
  final String ownerId;
  @override
  final String sessionId;
  @override
  final String activityType;
  @override
  final CanonicalLearningTimeSourceKind sourceKind;
  @override
  final String sourceBindingJson;
}
