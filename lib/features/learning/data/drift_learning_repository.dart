import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../vocabulary/domain/vocabulary_repository.dart';
import '../../vocabulary/data/packaged_starter_access.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../learning_packs/domain/content_quality_policy.dart';
import 'drift_learning_event_store.dart'
    hide
        ContextEvidencePolicyRolloutModeProvider,
        EvidencePolicyRolloutModeProvider,
        FixedEvidencePolicyRolloutModeProvider;
import 'drift_learning_projection_rebuilder.dart';
import '../domain/evidence_eligibility_policy.dart';
import '../domain/evidence_context.dart';
import '../domain/contrastive_explanation.dart';
import '../domain/evidence_policy_rollout.dart';
import '../domain/learning_evidence_contract.dart';
import '../domain/learning_event_context.dart';
import '../domain/learning_models.dart';
import '../domain/associative_reading_checkpoint.dart';
import '../domain/lexical_prompt_artifact_identity.dart';
import '../domain/learning_repository.dart';
import '../domain/session_configuration.dart';
import '../domain/srs_policy.dart';
import '../domain/srs_operation_identity.dart';
import '../pair_matching/domain/pair_matching_plan.dart';
import '../pair_matching/domain/pair_active_clock.dart';
import '../pair_matching/domain/pair_matching_engine.dart';
import '../pair_matching/domain/pair_matching_checkpoint_budget.dart';
import '../pair_matching/domain/pair_matching_launch.dart';
import '../domain/learning_activity_recovery_limits.dart';
import '../pair_matching/data/pair_matching_checkpoint_codec.dart';
import '../pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import '../pair_matching/domain/pair_matching_session_purpose.dart';
import '../pair_matching/application/pair_matching_atomic_start.dart';
import '../application/current_activity_evidence.dart'
    show FrozenPendingCurrentActivityEvidence;

final class DriftLearningRepository
    implements
        LearningRepository,
        PagedQuizWordRepository,
        LearningEvidenceReplayRepository,
        LearningSessionLifecycleRepository,
        PairAcceptedSessionDispositionRepository,
        SessionConfiguredLearningRepository,
        LearningActivityRecoveryRepository,
        AssociativeReadingRecoveryRepository,
        LearningActivitySessionHistoryRepository,
        PinnedLearningContentRepository,
        ExactPinnedLearningActivityRepository,
        PairPinnedLearningActivityRepository,
        PairMatchingSessionPurposeReader,
        ReviewSessionLearningRepository {
  static const int maxActivityRecoveryCheckpoints =
      LearningActivityRecoveryLimits.maximumCheckpoints;
  static const int maxActivityRecoveryAttempts =
      LearningActivityRecoveryLimits.maximumAttempts;

  DriftLearningRepository(
    this.database, {
    SrsPolicy srsPolicy = const BinarySm2SrsPolicy(),
    EvidenceEligibilityPolicy evidencePolicy =
        const EvidenceEligibilityPolicySet(),
    EvidencePolicyRolloutModeProvider rolloutModeProvider =
        const FixedEvidencePolicyRolloutModeProvider.legacy(),
    this.lexicalVocabulary,
  }) : projections = DriftLearningProjectionRebuilder(
         database,
         srsPolicy: srsPolicy,
         evidencePolicy: evidencePolicy,
         rolloutModeProvider: rolloutModeProvider,
       ),
       events = DriftLearningEventStore(
         database,
         evidencePolicy: evidencePolicy,
         rolloutModeProvider: rolloutModeProvider,
       );

  final db.AppDatabase database;
  @override
  Future<PairMatchingSessionPurpose> read({
    required String ownerId,
    required String sessionId,
  }) => DriftPairMatchingSessionPurposeReader(
    database,
  ).read(ownerId: ownerId, sessionId: sessionId);
  final VocabularyRepository? lexicalVocabulary;
  final DriftLearningProjectionRebuilder projections;
  final DriftLearningEventStore events;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) =>
      listQuizWordPage(ownerId: ownerId, categoryId: categoryId, limit: limit);

  @override
  Future<List<QuizWord>> listQuizWordPage({
    required String ownerId,
    String? categoryId,
    String? afterId,
    required int limit,
  }) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final query = database.select(database.vocabularyWords)
      ..where(
        (row) =>
            PackagedStarterAccess.wordsFor(database, ownerId) &
            row.isDeleted.equals(false) &
            (afterId == null
                ? const Constant(true)
                : row.id.isBiggerThanValue(afterId)) &
            (categoryId == null
                ? const Constant(true)
                : row.categoryId.equals(categoryId)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.id)])
      ..limit(limit);
    final rows = await query.get();
    final coreWords = rows.map(_quizWordFromRow).toList(growable: false);
    final vocabulary = lexicalVocabulary;
    if (vocabulary == null || coreWords.isEmpty) return coreWords;
    List<VocabularyWord> enriched;
    try {
      enriched = await vocabulary.readPinnedByIds(
        coreWords.map((word) => word.id),
      );
    } on Object {
      // Accepted variants are optional reviewed metadata. Core quiz content
      // remains available when that source is absent, stale, or offline.
      return coreWords;
    }
    if (enriched.length != coreWords.length) return coreWords;
    final enrichedById = <String, VocabularyWord>{
      for (final word in enriched) word.id: word,
    };
    return <QuizWord>[
      for (final core in coreWords)
        _withAcceptedSpellingVariants(core, enrichedById[core.id]),
    ];
  }

  @override
  Future<List<QuizWord>> listPinnedQuizWords({
    required String ownerId,
    required List<String> wordIds,
  }) async {
    if (wordIds.isEmpty ||
        wordIds.length > 100 ||
        wordIds.toSet().length != wordIds.length) {
      throw ArgumentError.value(
        wordIds,
        'wordIds',
        'must contain 1–100 unique IDs',
      );
    }
    for (final id in wordIds) {
      if (id.isEmpty || id != id.trim()) {
        throw ArgumentError.value(id, 'wordIds', 'must be canonical');
      }
    }
    final query = database.select(database.vocabularyWords)
      ..where(
        (row) =>
            PackagedStarterAccess.wordsFor(database, ownerId) &
            row.isDeleted.equals(false) &
            row.id.isIn(wordIds),
      );
    final rows = await query.get();
    final byId = <String, QuizWord>{
      for (final row in rows) row.id: _quizWordFromRow(row),
    };
    final ordered = <QuizWord>[for (final id in wordIds) ?byId[id]];
    final vocabulary = lexicalVocabulary;
    if (vocabulary == null || ordered.isEmpty) return ordered;
    try {
      final enriched = await vocabulary.readPinnedByIds(wordIds);
      if (enriched.length != ordered.length) return ordered;
      final enrichedById = <String, VocabularyWord>{
        for (final word in enriched) word.id: word,
      };
      return <QuizWord>[
        for (final core in ordered)
          _withAcceptedSpellingVariants(core, enrichedById[core.id]),
      ];
    } on Object {
      return ordered;
    }
  }

  @override
  Future<List<QuizWord>> listExactPinnedQuizWords({
    required String ownerId,
    required List<PinnedQuizContent> content,
  }) async {
    final frozenContent = List<PinnedQuizContent>.unmodifiable(content);
    final wordIds = _requireExactPinnedQuizIds(frozenContent);
    final words = await listPinnedQuizWords(ownerId: ownerId, wordIds: wordIds);
    if (words.length != frozenContent.length) return const <QuizWord>[];
    for (var index = 0; index < words.length; index += 1) {
      final word = words[index];
      final pin = frozenContent[index];
      if (word.id != pin.identity.id ||
          word.contentRevision != pin.identity.revision ||
          word.contentChecksumSha256 != pin.checksumSha256) {
        return const <QuizWord>[];
      }
    }
    return List<QuizWord>.unmodifiable(words);
  }

  List<String> _requireExactPinnedQuizIds(List<PinnedQuizContent> content) {
    if (content.isEmpty || content.length > 100) {
      throw ArgumentError.value(
        content,
        'content',
        'must contain 1–100 exact lexical identities',
      );
    }
    final ids = <String>{};
    for (final pin in content) {
      final identity = pin.identity;
      if (identity.type != ContentType.lexicalMetadata ||
          identity.id.isEmpty ||
          identity.id != identity.id.trim() ||
          identity.revision <= 0 ||
          !ids.add(identity.id) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(pin.checksumSha256)) {
        throw ArgumentError.value(
          pin,
          'content',
          'contains an invalid exact lexical identity',
        );
      }
    }
    return List<String>.unmodifiable(content.map((pin) => pin.identity.id));
  }

  @override
  Future<PinnedReviewSessionLaunch> startPinnedReviewSession({
    required LearningSessionDraft session,
    required List<ReviewedLexicalContentSnapshot> items,
  }) {
    final sessionId = _required(session.id, 'session.id');
    final ownerId = _required(session.ownerId, 'session.ownerId');
    final startedAtUtc = _requiredUtc(session.startedAtUtc, 'startedAtUtc');
    final appVersion = _required(session.appVersion, 'session.appVersion');
    final buildId = _required(session.buildId, 'session.buildId');
    if (session.activityType != 'reviewCenter' ||
        session.sessionConfiguration != null ||
        startedAtUtc.millisecondsSinceEpoch < 0 ||
        items.isEmpty ||
        items.length > 100) {
      throw ArgumentError('invalid pinned review session');
    }
    return database.transaction(() async {
      final activeOwners =
          await (database.select(database.localOwners)
                ..where((row) => row.isActive.equals(true))
                ..orderBy([(row) => OrderingTerm.asc(row.id)])
                ..limit(2))
              .get();
      if (activeOwners.length != 1 || activeOwners.single.id != ownerId) {
        throw StateError(
          'Pinned review session owner is no longer uniquely active.',
        );
      }
      final categories =
          await (database.select(database.vocabularyCategories)..where(
                (row) =>
                    PackagedStarterAccess.categoriesFor(database, ownerId) &
                    row.isDeleted.equals(false),
              ))
              .get();
      final categoryIds = categories.map((row) => row.id).toSet();
      final wordIds = items
          .map((item) => item.identity.id)
          .toList(growable: false);
      final rows =
          await (database.select(database.vocabularyWords)..where(
                (row) =>
                    PackagedStarterAccess.wordsFor(database, ownerId) &
                    row.id.isIn(wordIds),
              ))
              .get();
      final byId = <String, db.VocabularyWord>{
        for (final row in rows) row.id: row,
      };
      final words = <QuizWord>[];
      final validatedContent = <ReviewedLexicalContentSnapshot>[];
      for (final item in items) {
        final identity = item.identity;
        final row = byId[identity.id];
        if (identity.type != ContentType.lexicalMetadata ||
            row == null ||
            !_matchesReviewedLexicalSnapshot(row, item) ||
            !ContentQualityPolicy.isAvailableVocabulary(
              categoryAvailable: categoryIds.contains(row.categoryId),
              id: row.id,
              categoryId: row.categoryId,
              spelling: row.spelling,
              normalizedSpelling: row.normalizedSpelling,
              meaning: row.meaning,
              normalizedMeaning: row.normalizedMeaning,
              partOfSpeech: row.partOfSpeech,
              cefrLevel: row.cefrLevel,
              source: row.source,
              isGlobal: row.isGlobal,
              contentRevision: row.contentRevision,
              contentChecksumSha256: row.contentChecksumSha256,
              contentProvenance: row.contentProvenance,
              contentReviewState: row.contentReviewState,
              contentPublicationState: row.contentPublicationState,
              isDeleted: row.isDeleted,
            )) {
          throw StateError('Pinned review content is unavailable.');
        }
        final manifest =
            await (database.select(database.contentManifests)..where(
                  (candidate) =>
                      candidate.contentType.equals(
                        ContentType.lexicalMetadata.name,
                      ) &
                      candidate.contentId.equals(identity.id) &
                      candidate.revision.equals(identity.revision),
                ))
                .getSingleOrNull();
        final currentArtifact = manifest == null
            ? null
            : _reviewedLexicalArtifactSnapshot(manifest);
        if (currentArtifact != item.artifact) {
          throw StateError('Pinned review artifact identity changed.');
        }
        validatedContent.add(
          _reviewedLexicalContentSnapshot(row, currentArtifact),
        );
        words.add(_quizWordFromRow(row));
      }
      final quizSession = QuizSession(
        id: sessionId,
        ownerId: ownerId,
        questions: canonicalQuizQuestions(words),
        startedAtUtc: startedAtUtc,
      );
      if (quizSession.questions.length != items.length) {
        throw StateError('Pinned review content is unavailable.');
      }
      for (var index = 0; index < items.length; index += 1) {
        final item = items[index];
        final word = quizSession.questions[index].word;
        if (word.id != item.identity.id ||
            word.contentRevision != item.identity.revision ||
            word.contentChecksumSha256 != item.coreChecksumSha256) {
          throw StateError('Pinned review content identity changed.');
        }
      }
      final collision = await (database.select(
        database.learningSessions,
      )..where((row) => row.id.equals(sessionId))).getSingleOrNull();
      if (collision != null) {
        throw StateError('Pinned review session identity already exists.');
      }
      await database
          .into(database.learningSessions)
          .insert(
            db.LearningSessionsCompanion.insert(
              id: sessionId,
              ownerId: ownerId,
              activityType: 'reviewCenter',
              state: 'active',
              startedAtUtcMs: startedAtUtc.millisecondsSinceEpoch,
              appVersion: appVersion,
              buildId: buildId,
            ),
          );
      return PinnedReviewSessionLaunch(
        session: quizSession,
        content: validatedContent,
      );
    });
  }

  QuizWord _withAcceptedSpellingVariants(
    QuizWord core,
    VocabularyWord? enriched,
  ) {
    final metadata = enriched?.richMetadata;
    final variants = metadata?.acceptedSpellingVariants;
    final revision = metadata?.verifiedContentRevision;
    final checksum = metadata?.verifiedArtifactChecksumSha256;
    if (variants == null ||
        variants.isEmpty ||
        revision == null ||
        revision != core.contentRevision ||
        checksum == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
      return core;
    }
    return QuizWord(
      id: core.id,
      categoryId: core.categoryId,
      spelling: core.spelling,
      meaning: core.meaning,
      partOfSpeech: core.partOfSpeech,
      cefrLevel: core.cefrLevel,
      normalizedSpelling: core.normalizedSpelling,
      normalizedMeaning: core.normalizedMeaning,
      contentRevision: core.contentRevision,
      contentChecksumSha256: core.contentChecksumSha256,
      acceptedSpellingVariants: variants,
      acceptedSpellingVariantsRevision: revision,
      acceptedSpellingVariantsChecksumSha256: checksum,
    );
  }

  @override
  Future<void> startSession(LearningSessionDraft session) async {
    if (session.id.startsWith('reading:')) {
      throw StateError(
        'Reading namespace requires atomic exact pinned admission',
      );
    }
    await database.transaction(() async {
      final activeOwners =
          await (database.select(database.localOwners)
                ..where((row) => row.isActive.equals(true))
                ..limit(2))
              .get();
      if (activeOwners.length != 1 ||
          activeOwners.single.id != session.ownerId) {
        throw StateError(
          'Learning session owner is no longer uniquely active.',
        );
      }
      final existing = await (database.select(
        database.learningSessions,
      )..where((row) => row.id.equals(session.id))).getSingleOrNull();
      if (existing != null) {
        if (existing.ownerId != session.ownerId ||
            existing.activityType != session.activityType ||
            existing.startedAtUtcMs !=
                _requiredUtc(
                  session.startedAtUtc,
                  'startedAtUtc',
                ).millisecondsSinceEpoch ||
            existing.appVersion != session.appVersion ||
            existing.buildId != session.buildId ||
            existing.sessionConfigurationIdentity !=
                session.sessionConfiguration?.contentIdentity ||
            existing.sessionConfigurationJson !=
                session.sessionConfiguration?.stableSerialization) {
          throw StateError('learning session identity conflict');
        }
        return;
      }
      await _insertLearningSession(session);
    });
  }

  Future<void> _insertLearningSession(LearningSessionDraft session) async {
    final startedAt = _requiredUtc(session.startedAtUtc, 'startedAtUtc');
    final configuration = session.sessionConfiguration;
    if (configuration != null && configuration.ownerId != session.ownerId) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.ownerDrift,
      );
    }
    await database
        .into(database.learningSessions)
        .insert(
          db.LearningSessionsCompanion.insert(
            id: _required(session.id, 'id'),
            ownerId: _required(session.ownerId, 'ownerId'),
            activityType: _required(session.activityType, 'activityType'),
            state: 'active',
            startedAtUtcMs: startedAt.millisecondsSinceEpoch,
            appVersion: _required(session.appVersion, 'appVersion'),
            buildId: _required(session.buildId, 'buildId'),
            sessionConfigurationIdentity: Value(configuration?.contentIdentity),
            sessionConfigurationJson: Value(configuration?.stableSerialization),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<void> startSessionWithCheckpoint({
    required LearningSessionDraft session,
    required LearningActivityCheckpoint checkpoint,
  }) {
    if (session.id.startsWith('reading:')) {
      throw StateError('Reading namespace requires exact pinned admission');
    }
    if (checkpoint.sessionId != session.id ||
        checkpoint.activityType != session.activityType ||
        checkpoint.revision != 1) {
      throw ArgumentError.value(
        checkpoint,
        'checkpoint',
        'must be revision 1 for the same activity session',
      );
    }
    final canonicalCheckpoint = _canonicalizeActivityCheckpoint(checkpoint);
    final sessionId = _required(session.id, 'session.id');
    final ownerId = _required(session.ownerId, 'session.ownerId');
    return database.transaction(
      () => _startSessionWithCheckpointInTransaction(
        session: session,
        checkpoint: canonicalCheckpoint,
        sessionId: sessionId,
        ownerId: ownerId,
      ),
    );
  }

  @override
  Future<void> startExactPinnedSessionWithCheckpoint({
    required LearningSessionDraft session,
    required List<PinnedQuizContent> content,
    required LearningActivityCheckpoint checkpoint,
  }) => _startExactPinnedSessionWithCheckpoint(
    session: session,
    content: content,
    checkpoint: checkpoint,
  );

  Future<void> _startExactPinnedSessionWithCheckpoint({
    required LearningSessionDraft session,
    required List<PinnedQuizContent> content,
    required LearningActivityCheckpoint checkpoint,
    bool pairAdmission = false,
  }) {
    final frozenContent = List<PinnedQuizContent>.unmodifiable(content);
    if (checkpoint.sessionId != session.id ||
        checkpoint.activityType != session.activityType ||
        checkpoint.revision != 1) {
      throw ArgumentError.value(
        checkpoint,
        'checkpoint',
        'must be revision 1 for the same activity session',
      );
    }
    final wordIds = _requireExactPinnedQuizIds(frozenContent);
    final canonicalCheckpoint = _canonicalizeActivityCheckpoint(checkpoint);
    final sessionId = _required(session.id, 'session.id');
    final ownerId = _required(session.ownerId, 'session.ownerId');
    return database.transaction(() async {
      final activeOwners =
          await (database.select(database.localOwners)
                ..where((row) => row.isActive.equals(true))
                ..orderBy([(row) => OrderingTerm.asc(row.id)])
                ..limit(2))
              .get();
      if (activeOwners.length != 1 || activeOwners.single.id != ownerId) {
        throw StateError(
          'Pinned checkpoint session owner is no longer uniquely active.',
        );
      }
      final rows =
          await (database.select(database.vocabularyWords)..where(
                (row) =>
                    PackagedStarterAccess.wordsFor(database, ownerId) &
                    row.id.isIn(wordIds),
              ))
              .get();
      final byId = <String, db.VocabularyWord>{
        for (final row in rows) row.id: row,
      };
      for (final pin in frozenContent) {
        final row = byId[pin.identity.id];
        final word = row == null ? null : _quizWordFromRow(row);
        if (row == null ||
            row.isDeleted ||
            word!.contentRevision != pin.identity.revision ||
            word.contentChecksumSha256 != pin.checksumSha256) {
          throw StateError('Pinned checkpoint content is no longer exact.');
        }
      }
      if (session.id.startsWith('reading:')) {
        final reading = AssociativeReadingCheckpoint.fromJson(
          canonicalCheckpoint.state,
        );
        if (session.activityType != 'associativeReading' ||
            jsonEncode(
                  reading.words
                      .map((word) => [word.id, word.revision, word.checksum])
                      .toList(),
                ) !=
                jsonEncode(
                  frozenContent
                      .map(
                        (pin) => [
                          pin.identity.id,
                          pin.identity.revision,
                          pin.checksumSha256,
                        ],
                      )
                      .toList(),
                )) {
          throw StateError('Reading admission pins do not match checkpoint');
        }
      }
      await _startSessionWithCheckpointInTransaction(
        session: session,
        checkpoint: canonicalCheckpoint,
        sessionId: sessionId,
        ownerId: ownerId,
        pairAdmission: pairAdmission,
      );
    });
  }

  @override
  Future<void> startPinnedPairSession({
    required LearningSessionDraft session,
    required PairMatchingPlanV1 plan,
    required String launchOperationId,
    required LearningActivityCheckpoint checkpoint,
    required PairMatchingStartCapability capability,
  }) => _startPinnedPairSession(
    session: session,
    plan: plan,
    launchOperationId: launchOperationId,
    checkpoint: checkpoint,
    capability: capability,
  );

  @override
  Future<void> startMeasuredPinnedPairSession({
    required LearningSessionDraft session,
    required PairMatchingPlanV1 plan,
    required String launchOperationId,
    required LearningActivityCheckpoint checkpoint,
    required PairMatchingStartCapability capability,
  }) => _startPinnedPairSession(
    session: session,
    plan: plan,
    launchOperationId: launchOperationId,
    checkpoint: checkpoint,
    capability: capability,
    measuredAdmission: true,
  );

  Future<void> _startPinnedPairSession({
    required LearningSessionDraft session,
    required PairMatchingPlanV1 plan,
    required String launchOperationId,
    required LearningActivityCheckpoint checkpoint,
    required PairMatchingStartCapability capability,
    bool measuredAdmission = false,
  }) {
    final frozen = _canonicalizeActivityCheckpoint(checkpoint);
    final acceptedOperation =
        PairMatchingStartOperation.fromStableSerialization(
          _decodePinnedPairCheckpoint(frozen.state).startOperation,
        );
    if (acceptedOperation.configuration?.stableSerialization !=
        session.sessionConfiguration?.stableSerialization) {
      throw ArgumentError('Pair configured start identity changed');
    }
    if (session.id != plan.learningSessionId ||
        session.ownerId != plan.ownerId ||
        session.activityType != 'matching' ||
        session.startedAtUtc != plan.createdAtUtc ||
        session.id != pairSessionId(plan.ownerId, launchOperationId) ||
        frozen.sessionId != session.id ||
        frozen.activityType != 'matching' ||
        frozen.revision != 1 ||
        frozen.occurredAtUtc != plan.createdAtUtc ||
        frozen.state['schemaVersion'] != 6 ||
        frozen.state['planFingerprint'] != plan.planFingerprint ||
        jsonEncode(frozen.state['plan']) != plan.stableSerialization) {
      throw ArgumentError('Pair start binding mismatch');
    }
    return database.transaction(() async {
      final owners =
          await (database.select(database.localOwners)
                ..where((r) => r.isActive.equals(true))
                ..limit(2))
              .get();
      if (owners.length != 1 || owners.single.id != plan.ownerId) {
        throw StateError('Pair owner changed');
      }
      final prior = await (database.select(
        database.learningSessions,
      )..where((r) => r.id.equals(session.id))).getSingleOrNull();
      if (prior != null) {
        final key = _activityCheckpointKey(
          ownerId: plan.ownerId,
          sessionId: session.id,
          activityType: 'matching',
          revision: 1,
        );
        final event = await (database.select(
          database.eventsV2,
        )..where((r) => r.eventId.equals(key))).getSingleOrNull();
        if (prior.ownerId != session.ownerId ||
            prior.activityType != 'matching' ||
            prior.startedAtUtcMs != plan.createdAtUtc.millisecondsSinceEpoch ||
            prior.appVersion != session.appVersion ||
            prior.buildId != session.buildId ||
            prior.sessionConfigurationIdentity !=
                session.sessionConfiguration?.contentIdentity ||
            prior.sessionConfigurationJson !=
                session.sessionConfiguration?.stableSerialization ||
            event == null ||
            event.ownerId != plan.ownerId ||
            event.aggregateId != session.id ||
            jsonEncode((jsonDecode(event.payloadJson) as Map)['state']) !=
                jsonEncode(frozen.state)) {
          throw StateError('Pair operation identity conflict');
        }
        // Acknowledgement can be lost even after later checkpoints commit.
        // Reconcile the immutable initial event, never append revision 1 again.
        return;
      }
      capability.requireAllowed(plan);
      if (plan.sessionPurpose == PairSessionPurpose.practiceReplay) {
        final source = await DriftPairMatchingSessionPurposeReader(
          database,
        ).read(ownerId: plan.ownerId, sessionId: plan.sourceSessionId!);
        final snapshot = source.snapshot;
        final prior = snapshot?.engine.plan;
        if (snapshot == null ||
            snapshot.terminal?.acknowledged != true ||
            !snapshot.engine.complete ||
            prior!.learningSessionId == plan.learningSessionId ||
            plan.createdAtUtc.isBefore(snapshot.terminal!.atUtc) ||
            prior.shuffleSeed == plan.shuffleSeed ||
            prior.direction != plan.direction ||
            prior.density != plan.density ||
            prior.allowlistVersion != plan.allowlistVersion ||
            PairMatchingSessionPurpose.projectConfigurationOwner(
                  PairMatchingStartOperation.fromStableSerialization(
                    snapshot.startOperation,
                  ).configuration,
                  plan.ownerId,
                )?.stableSerialization !=
                acceptedOperation.configuration?.stableSerialization ||
            jsonEncode(
                  prior.orderedLexicalItems.map((i) => i.toJson()).toList(),
                ) !=
                jsonEncode(
                  plan.orderedLexicalItems.map((i) => i.toJson()).toList(),
                )) {
          throw StateError('Pair replay source or exact pins changed');
        }
      }
      PairMatchingCheckpointCodec.requireCompletionCapacity(
        _decodePinnedPairCheckpoint(frozen.state),
      );
      final admissionSnapshot = measuredAdmission
          ? PairMatchingCheckpointSnapshot(
              engine: PairMatchingState.initial(plan),
              startOperation: acceptedOperation.stableSerialization,
              timer: PairTimerState.initial(
                plan.timerPreset,
              ).copy(interactiveElapsedMs: 0),
            )
          : null;
      final admission = admissionSnapshot == null
          ? null
          : _canonicalizeActivityCheckpoint(
              LearningActivityCheckpoint(
                sessionId: session.id,
                activityType: 'matching',
                revision: 2,
                occurredAtUtc: plan.createdAtUtc,
                state: admissionSnapshot.toJson(),
              ),
            );
      if (admissionSnapshot != null) {
        PairMatchingCheckpointCodec.requireCompletionCapacity(
          admissionSnapshot,
        );
        if (!PairMatchingCheckpointBudget.canTransition(
          revision: 1,
          cost: 1,
          attempts: 0,
          remainingAttemptBound:
              admissionSnapshot.engine.remainingRepairAttemptBound,
          revealReserve: plan.orderedLexicalItems.length,
          timerReserve: admissionSnapshot.timer!.decisionReserve,
        )) {
          throw StateError('Pair measured admission capacity unavailable');
        }
      }
      final ids = plan.orderedLexicalItems.map((i) => i.wordId).toList();
      final reports =
          await (database.select(database.contentQualityReports)
                ..where(
                  (r) =>
                      r.ownerId.equals(plan.ownerId) &
                      r.contentType.equals(ContentType.lexicalMetadata.name) &
                      r.contentId.isIn(ids),
                )
                ..limit(1))
              .get();
      if (reports.isNotEmpty) throw StateError('Pair content is reported');
      final rows =
          await (database.select(database.vocabularyWords)..where(
                (r) =>
                    PackagedStarterAccess.wordsFor(database, plan.ownerId) &
                    r.id.isIn(ids),
              ))
              .get();
      final categories =
          await (database.select(database.vocabularyCategories)..where(
                (r) =>
                    PackagedStarterAccess.categoriesFor(
                      database,
                      plan.ownerId,
                    ) &
                    r.isDeleted.equals(false) &
                    r.id.isIn(rows.map((r) => r.categoryId).toSet()),
              ))
              .get();
      final availableCategories = categories.map((r) => r.id).toSet();
      for (final item in plan.orderedLexicalItems) {
        final matches = rows.where((r) => r.id == item.wordId);
        if (matches.length != 1 ||
            matches.single.isDeleted ||
            !availableCategories.contains(matches.single.categoryId) ||
            matches.single.contentReviewState == 'rejected' ||
            matches.single.contentPublicationState == 'retired' ||
            matches.single.spelling != item.spelling ||
            matches.single.meaning != item.meaning) {
          throw StateError('Pair labels/content changed');
        }
      }
      capability.requireAllowed(plan);
      await _startExactPinnedSessionWithCheckpoint(
        session: session,
        pairAdmission: true,
        content: plan.orderedLexicalItems
            .map(
              (i) => PinnedQuizContent(
                identity: ContentIdentity(
                  type: ContentType.lexicalMetadata,
                  id: i.wordId,
                  revision: i.contentRevision,
                ),
                checksumSha256: i.checksum,
              ),
            )
            .toList(),
        checkpoint: frozen,
      );
      if (admission != null) {
        await _appendActivityCheckpoint(
          ownerId: plan.ownerId,
          checkpoint: admission,
          measuredPairAdmission: true,
        );
      }
      // A gate may change during asynchronous persistence; rollback if so.
      capability.requireAllowed(plan);
    });
  }

  Future<void> _startSessionWithCheckpointInTransaction({
    required LearningSessionDraft session,
    required LearningActivityCheckpoint checkpoint,
    required String sessionId,
    required String ownerId,
    bool pairAdmission = false,
  }) async {
    var stored = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals(sessionId))).getSingleOrNull();
    if (stored == null) {
      final active =
          await (database.select(database.learningSessions)
                ..where(
                  (row) =>
                      row.ownerId.equals(ownerId) & row.state.equals('active'),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.id)])
                ..limit(1))
              .getSingleOrNull();
      if (active != null) {
        throw ActiveLearningSessionConflict(
          ownerId: ownerId,
          activeSessionId: active.id,
          requestedSessionId: sessionId,
        );
      }
      if (session.id.startsWith('reading:')) {
        await _insertLearningSession(session);
      } else {
        await startSession(session);
      }
      stored = await (database.select(
        database.learningSessions,
      )..where((row) => row.id.equals(sessionId))).getSingle();
    }
    if (stored.ownerId != ownerId ||
        stored.activityType != session.activityType ||
        stored.state != 'active' ||
        stored.startedAtUtcMs !=
            _requiredUtc(
              session.startedAtUtc,
              'startedAtUtc',
            ).millisecondsSinceEpoch ||
        stored.appVersion != session.appVersion ||
        stored.buildId != session.buildId ||
        stored.sessionConfigurationIdentity !=
            session.sessionConfiguration?.contentIdentity ||
        stored.sessionConfigurationJson !=
            session.sessionConfiguration?.stableSerialization) {
      throw StateError('learning activity session identity conflict');
    }
    await _appendActivityCheckpoint(
      ownerId: ownerId,
      checkpoint: checkpoint,
      pairAdmission: pairAdmission,
    );
  }

  @override
  Future<void> appendActivityCheckpoint({
    required String ownerId,
    required LearningActivityCheckpoint checkpoint,
  }) {
    final canonicalCheckpoint = _canonicalizeActivityCheckpoint(checkpoint);
    return database.transaction(
      () => _appendActivityCheckpoint(
        ownerId: ownerId,
        checkpoint: canonicalCheckpoint,
      ),
    );
  }

  LearningActivityCheckpoint _canonicalizeActivityCheckpoint(
    LearningActivityCheckpoint checkpoint,
  ) {
    late final Map<String, Object?> canonicalState;
    try {
      final decoded = jsonDecode(jsonEncode(checkpoint.state));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('checkpoint state must be an object');
      }
      canonicalState = _freezeJsonMap(decoded.cast<String, Object?>());
    } on Object catch (error) {
      throw ArgumentError.value(
        checkpoint.state,
        'state',
        'must be JSON encodable: $error',
      );
    }
    final stateBytes = utf8.encode(jsonEncode(canonicalState)).length;
    if (stateBytes > LearningActivityRecoveryLimits.maximumCheckpointBytes) {
      throw ArgumentError.value(
        stateBytes,
        'state',
        'checkpoint exceeds the 64 KiB bound',
      );
    }
    return LearningActivityCheckpoint(
      sessionId: checkpoint.sessionId,
      activityType: checkpoint.activityType,
      revision: checkpoint.revision,
      occurredAtUtc: checkpoint.occurredAtUtc,
      state: canonicalState,
      terminalAtUtc: checkpoint.terminalAtUtc,
      terminalAcknowledged: checkpoint.terminalAcknowledged,
    );
  }

  Future<void> _appendActivityCheckpoint({
    required String ownerId,
    required LearningActivityCheckpoint checkpoint,
    bool pairAdmission = false,
    bool measuredPairAdmission = false,
  }) async {
    final requiredOwnerId = _required(ownerId, 'ownerId');
    final sessionId = _required(checkpoint.sessionId, 'sessionId');
    final activityType = _required(checkpoint.activityType, 'activityType');
    if (checkpoint.revision < 1 ||
        checkpoint.revision > maxActivityRecoveryCheckpoints) {
      throw RangeError.range(
        checkpoint.revision,
        1,
        maxActivityRecoveryCheckpoints,
        'revision',
      );
    }
    final occurredAtUtc = _requiredUtc(
      checkpoint.occurredAtUtc,
      'occurredAtUtc',
    );
    final terminalAtUtc = checkpoint.terminalAtUtc == null
        ? null
        : _requiredUtc(checkpoint.terminalAtUtc, 'terminalAtUtc');
    if (checkpoint.terminalAcknowledged && terminalAtUtc == null) {
      throw ArgumentError.value(
        checkpoint,
        'checkpoint',
        'terminal acknowledgement requires a terminal identity',
      );
    }
    final canonicalTime = LearningEvidenceContract.canonicalEventUtcSecond(
      occurredAtUtc,
    );
    final canonicalState = checkpoint.state;
    final stateJson = jsonEncode(canonicalState);
    final session =
        await (database.select(database.learningSessions)..where(
              (row) =>
                  row.id.equals(sessionId) &
                  row.ownerId.equals(requiredOwnerId) &
                  row.activityType.equals(activityType),
            ))
            .getSingleOrNull();
    if (session == null) {
      throw StateError('learning activity session not found');
    }
    final storedTerminalAtUtc = _fromEpoch(session.endedAtUtcMs);
    if (session.state == 'active') {
      if (checkpoint.terminalAcknowledged) {
        throw StateError('active activity cannot acknowledge completion');
      }
    } else if (session.state == 'completed') {
      if (terminalAtUtc == null || terminalAtUtc != storedTerminalAtUtc) {
        throw StateError('completed activity terminal identity is invalid');
      }
    } else {
      throw StateError('learning activity session is not recoverable');
    }
    final latest = await _latestActivityCheckpoint(
      ownerId: requiredOwnerId,
      session: session,
    );
    if (activityType == 'associativeReading' &&
        (sessionId.startsWith('reading:') ||
            canonicalState['kind'] == 'associativeReading' ||
            latest?.state['kind'] == 'associativeReading')) {
      await _requireReadingOwner(requiredOwnerId);
      final reading = AssociativeReadingCheckpoint.fromJson(canonicalState);
      await _validateReadingPins(requiredOwnerId, reading);
      if (latest == null) {
        if (reading.stage != 1 || checkpoint.revision != 1) {
          throw StateError('Reading must start at stage one');
        }
      } else {
        final previous = AssociativeReadingCheckpoint.fromJson(latest.state);
        if (!reading.sameContent(previous) ||
            reading.stage < previous.stage ||
            reading.stage > previous.stage + 1) {
          throw StateError('Reading checkpoint transition is invalid');
        }
        // Before a terminal checkpoint is appended, completed state still has
        // the previous checkpoint. Authenticate its attempts without requiring
        // the terminal checkpoint that this transaction is about to append.
        final recovery = await _loadActivityRecoveryForSession(
          ownerId: requiredOwnerId,
          session: session.copyWith(state: 'active'),
          strictExactIdentity: true,
        );
        reading.recallResults(recovery!);
      }
    }
    if (activityType == 'matching' &&
        (canonicalState['schemaVersion'] == 6 ||
            latest?.state['schemaVersion'] == 6)) {
      if (latest == null && !pairAdmission) {
        throw StateError('Pair initial requires authorized atomic admission');
      }
      await _validatePinnedPairCheckpoint(
        session: session,
        checkpoint: checkpoint,
        latest: latest,
        measuredAdmission: measuredPairAdmission,
      );
    }
    if (latest != null && latest.revision >= checkpoint.revision) {
      if (latest.revision == checkpoint.revision &&
          jsonEncode(latest.state) == stateJson &&
          latest.occurredAtUtc == canonicalTime &&
          latest.terminalAtUtc == terminalAtUtc &&
          latest.terminalAcknowledged == checkpoint.terminalAcknowledged) {
        return;
      }
      throw StateError('activity checkpoint revision already exists');
    }
    final expectedRevision = (latest?.revision ?? 0) + 1;
    if (checkpoint.revision != expectedRevision) {
      throw StateError('activity checkpoint revision is not sequential');
    }
    final key = _activityCheckpointKey(
      ownerId: requiredOwnerId,
      sessionId: sessionId,
      activityType: activityType,
      revision: checkpoint.revision,
    );
    final payload = <String, Object?>{
      'schemaVersion': 2,
      'activityType': activityType,
      'sessionId': sessionId,
      'revision': checkpoint.revision,
      'state': canonicalState,
      'terminalAtUtc': terminalAtUtc?.toIso8601String(),
      'terminalAcknowledged': checkpoint.terminalAcknowledged,
    };
    await database
        .into(database.eventsV2)
        .insert(
          db.EventsV2Companion.insert(
            eventId: key,
            eventType: 'LearningActivityCheckpoint',
            eventVersion: 2,
            occurredAtUtc: canonicalTime,
            recordedAtUtc: canonicalTime,
            actorIdentity: requiredOwnerId,
            ownerId: requiredOwnerId,
            aggregateType: 'LearningSession',
            aggregateId: sessionId,
            idempotencyKey: key,
            consentContextJson: jsonEncode(<String, Object?>{
              'researchConsentVersion': 0,
              'aiConsentGranted': false,
              'voiceConsentGranted': false,
              'socialConsentGranted': false,
            }),
            appVersion: session.appVersion,
            buildId: session.buildId,
            privacyClassification: 'ownerOnly',
            payloadJson: jsonEncode(payload),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    if (activityType == 'matching' && canonicalState['schemaVersion'] == 6) {
      await _requireActivePairOwner(requiredOwnerId);
    }
    final stored = await (database.select(
      database.eventsV2,
    )..where((row) => row.eventId.equals(key))).getSingleOrNull();
    if (stored == null ||
        !_isExactStoredActivityCheckpoint(
          row: stored,
          eventId: key,
          eventVersion: 2,
          actorIdentity: requiredOwnerId,
          ownerId: requiredOwnerId,
          session: session,
          occurredAtUtc: canonicalTime,
          payloadJson: jsonEncode(payload),
        )) {
      throw StateError('activity checkpoint identity conflict');
    }
  }

  Future<void> _requireReadingOwner(String ownerId) async {
    final active = await (database.select(
      database.localOwners,
    )..where((row) => row.isActive.equals(true))).get();
    if (active.length != 1 || active.single.id != ownerId) {
      throw StateError('Reading owner is no longer active');
    }
  }

  Future<void> _validateReadingPins(
    String ownerId,
    AssociativeReadingCheckpoint content,
  ) async {
    final words = await listExactPinnedQuizWords(
      ownerId: ownerId,
      content: content.words.map((word) => word.content).toList(),
    );
    if (words.length != content.words.length)
      throw StateError('Reading content is unavailable');
    final categories =
        await (database.select(database.vocabularyCategories)..where(
              (row) =>
                  row.id.isIn(words.map((word) => word.categoryId)) &
                  PackagedStarterAccess.categoriesFor(database, ownerId) &
                  row.isDeleted.equals(false),
            ))
            .get();
    final categoryIds = categories.map((row) => row.id).toSet();
    if (words.any((word) => !categoryIds.contains(word.categoryId))) {
      throw StateError('Reading category is unavailable');
    }
    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      final pin = content.words[index];
      if (word.id != pin.id ||
          word.spelling != pin.spelling ||
          (word.normalizedSpelling ?? word.spelling) != pin.canonicalAnswer ||
          jsonEncode(word.acceptedSpellingVariants) !=
              jsonEncode(pin.acceptedVariants) ||
          (pin.acceptedVariants.isNotEmpty &&
              (word.acceptedSpellingVariantsRevision !=
                      pin.acceptedVariantsRevision ||
                  word.acceptedSpellingVariantsChecksumSha256 !=
                      pin.acceptedVariantsChecksum))) {
        throw StateError('Reading answer set changed');
      }
    }
  }

  @override
  Future<LearningActivityRecovery?> loadReadingRecovery({
    required String ownerId,
    required AssociativeReadingCheckpoint content,
  }) => database.transaction(() async {
    await _requireReadingOwner(ownerId);
    // Filter by document in SQLite before applying the bounded candidate scan.
    // Active mismatches are deliberately not retired; atomic admission rejects
    // any later attempt to start a competing activity.
    final candidates = await database
        .customSelect(
          '''
SELECT DISTINCT s.id FROM learning_sessions s
JOIN events_v2 e ON e.aggregate_id = s.id AND e.owner_id = s.owner_id
WHERE s.owner_id = ? AND s.activity_type = 'associativeReading'
  AND s.state IN ('active', 'completed')
  AND e.event_type = 'LearningActivityCheckpoint'
  AND json_valid(e.payload_json)
  AND json_extract(e.payload_json, '\$.state.kind') = 'associativeReading'
  AND json_extract(e.payload_json, '\$.state.documentId') = ?
  AND json_extract(e.payload_json, '\$.state.documentRevision') = ?
ORDER BY CASE s.state WHEN 'active' THEN 0 ELSE 1 END, s.started_at_utc_ms DESC, s.id DESC
LIMIT 1
''',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(content.documentId),
            Variable.withInt(content.documentRevision),
          ],
        )
        .get();
    if (candidates.isEmpty) return null;
    final recovery = await loadExactActivityRecovery(
      ownerId: ownerId,
      sessionId: candidates.single.read<String>('id'),
      activityType: 'associativeReading',
    );
    if (recovery == null || recovery.checkpoint == null)
      throw StateError('Reading recovery is missing');
    final stored = AssociativeReadingCheckpoint.fromJson(
      recovery.checkpoint!.state,
    );
    if (!stored.sameContent(content))
      throw StateError('Reading document content changed');
    stored.recallResults(recovery);
    await _validateReadingPins(ownerId, stored);
    await _requireReadingOwner(ownerId);
    return recovery;
  });

  @override
  Future<ReadingProgressSnapshot> saveReadingCheckpoint({
    required ReadingProgressCommand progress,
    required LearningActivityCheckpoint checkpoint,
  }) => database.transaction(() async {
    await _requireReadingOwner(progress.ownerId);
    final state = AssociativeReadingCheckpoint.fromJson(checkpoint.state);
    if (progress.documentId != state.documentId ||
        progress.documentRevision != state.documentRevision ||
        progress.position != state.stage ||
        progress.isCompleted) {
      throw StateError('Reading progress does not match active checkpoint');
    }
    await _appendActivityCheckpoint(
      ownerId: progress.ownerId,
      checkpoint: checkpoint,
    );
    return saveReadingProgress(progress);
  });

  @override
  Future<LearningActivityRecovery?> loadLatestActivityRecovery({
    required String ownerId,
    required String activityType,
  }) async {
    final requiredOwnerId = _required(ownerId, 'ownerId');
    final requiredActivityType = _required(activityType, 'activityType');
    var session =
        await (database.select(database.learningSessions)
              ..where(
                (row) =>
                    row.ownerId.equals(requiredOwnerId) &
                    row.activityType.equals(requiredActivityType) &
                    row.state.equals('active'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAtUtcMs)])
              ..limit(1))
            .getSingleOrNull();
    session ??=
        await (database.select(database.learningSessions)
              ..where(
                (row) =>
                    row.ownerId.equals(requiredOwnerId) &
                    row.activityType.equals(requiredActivityType) &
                    row.state.equals('completed'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAtUtcMs)])
              ..limit(1))
            .getSingleOrNull();
    if (session == null) return null;
    return _loadActivityRecoveryForSession(
      ownerId: requiredOwnerId,
      session: session,
    );
  }

  @override
  Future<LearningActivityRecovery?> loadExactActivityRecovery({
    required String ownerId,
    required String sessionId,
    required String activityType,
  }) async {
    final requiredOwnerId = _required(ownerId, 'ownerId');
    final requiredSessionId = _required(sessionId, 'sessionId');
    final requiredActivityType = _required(activityType, 'activityType');
    return database.transaction(() async {
      final session =
          await (database.select(database.learningSessions)..where(
                (row) =>
                    row.id.equals(requiredSessionId) &
                    row.ownerId.equals(requiredOwnerId) &
                    row.activityType.equals(requiredActivityType),
              ))
              .getSingleOrNull();
      if (session == null) return null;
      return _loadActivityRecoveryForSession(
        ownerId: requiredOwnerId,
        session: session,
        strictExactIdentity: true,
      );
    });
  }

  Future<LearningActivityRecovery?> _loadActivityRecoveryForSession({
    required String ownerId,
    required db.LearningSession session,
    bool strictExactIdentity = false,
  }) async {
    final recoverySession = session;
    final checkpoint = await _latestActivityCheckpoint(
      ownerId: ownerId,
      session: recoverySession,
      strictExactIdentity: strictExactIdentity,
    );
    if (recoverySession.id.startsWith('reading:')) {
      if (checkpoint == null)
        throw StateError('Canonical reading checkpoint missing');
      AssociativeReadingCheckpoint.fromJson(checkpoint.state);
    }
    if (checkpoint == null) {
      if (strictExactIdentity) {
        throw StateError('exact activity checkpoint is missing or corrupt');
      }
      if (recoverySession.state == 'completed') return null;
      return LearningActivityRecovery(
        session: _rowToSummary(recoverySession),
        checkpoint: null,
        attempts: const <RecordAnswerCandidate>[],
      );
    }
    if (recoverySession.state == 'completed' &&
        checkpoint.terminalAtUtc != _fromEpoch(recoverySession.endedAtUtcMs)) {
      if (strictExactIdentity) {
        throw StateError('exact activity terminal identity is corrupt');
      }
      return null;
    }
    final attemptQuery = database.select(database.answerAttempts)
      ..where(
        (row) => strictExactIdentity
            ? row.sessionId.equals(recoverySession.id)
            : row.ownerId.equals(ownerId) &
                  row.sessionId.equals(recoverySession.id),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.attemptNumber),
        (row) => OrderingTerm.asc(row.occurredAtUtcMs),
        (row) => OrderingTerm.asc(row.id),
      ])
      ..limit(maxActivityRecoveryAttempts + 1);
    final attempts = await attemptQuery.get();
    if (attempts.length > maxActivityRecoveryAttempts) {
      throw StateError('activity attempt recovery bound exceeded');
    }
    final sources = await events.readBySourceEvidenceIds(
      attempts.map((attempt) => attempt.id),
    );
    final candidates = <RecordAnswerCandidate>[];
    for (final attempt in attempts) {
      if (strictExactIdentity && attempt.ownerId != ownerId) {
        throw StateError('exact activity attempt owner is corrupt');
      }
      final source = sources[attempt.id];
      if (source == null ||
          await events.validateSourceForAttempt(
                attempt: attempt,
                source: source,
              ) !=
              null) {
        throw StateError('activity attempt has missing or corrupt event');
      }
      final decoded = jsonDecode(attempt.evidenceContextJson);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('activity attempt has corrupt evidence context');
      }
      final context = EvidenceContext.fromJson(decoded.cast<String, Object?>());
      candidates.add(
        RecordAnswerCandidate(
          id: attempt.id,
          ownerId: attempt.ownerId,
          sessionId: attempt.sessionId,
          wordId: attempt.wordId,
          promptMode: attempt.promptMode,
          isCorrect: attempt.isCorrect,
          responseTimeMs: attempt.responseTimeMs,
          attemptNumber: attempt.attemptNumber,
          occurredAtUtc: _fromEpoch(attempt.occurredAtUtcMs)!,
          evidenceContext: context,
          providerProvenance: attempt.providerProvenance,
          actorIdentity: source.actorIdentity,
          eventContext: LearningEventContext.fromEvidenceEnvelope(
            envelope: source,
            evidenceContext: context,
          ),
        ),
      );
    }
    if (checkpoint.state['schemaVersion'] == 6) {
      await _validatePinnedPairCheckpoint(
        session: recoverySession,
        checkpoint: checkpoint,
        latest: checkpoint,
      );
    }
    return LearningActivityRecovery(
      session: _rowToSummary(recoverySession),
      checkpoint: checkpoint,
      attempts: List<RecordAnswerCandidate>.unmodifiable(candidates),
    );
  }

  Future<LearningActivityCheckpoint?> _latestActivityCheckpoint({
    required String ownerId,
    required db.LearningSession session,
    bool strictExactIdentity = false,
  }) async {
    final query = database.select(database.eventsV2);
    if (strictExactIdentity) {
      final expectedKeys = <String>[
        for (
          var revision = 1;
          revision <= maxActivityRecoveryCheckpoints;
          revision += 1
        )
          _activityCheckpointKey(
            ownerId: ownerId,
            sessionId: session.id,
            activityType: session.activityType,
            revision: revision,
          ),
      ];
      query.where(
        (row) =>
            row.eventId.isIn(expectedKeys) |
            (row.aggregateId.equals(session.id) &
                (row.eventId.like('learning-activity-checkpoint:%') |
                    row.eventType.equals('LearningActivityCheckpoint'))),
      );
    } else {
      query.where(
        (row) =>
            row.eventId.like('learning-activity-checkpoint:%') &
            row.ownerId.equals(ownerId) &
            row.eventType.equals('LearningActivityCheckpoint') &
            row.aggregateType.equals('LearningSession') &
            row.aggregateId.equals(session.id),
      );
    }
    query.limit(maxActivityRecoveryCheckpoints + 1);
    final rows = await query.get();
    if (rows.length > maxActivityRecoveryCheckpoints) {
      throw StateError('activity checkpoint recovery bound exceeded');
    }
    LearningActivityCheckpoint? latest;
    final revisions = <int>[];
    for (final row in rows) {
      late final Object? decodedValue;
      try {
        decodedValue = jsonDecode(row.payloadJson);
      } on Object {
        if (strictExactIdentity || row.aggregateId == session.id) {
          throw StateError('activity checkpoint is corrupt');
        }
        continue;
      }
      if (decodedValue is! Map<String, dynamic>) {
        if (strictExactIdentity || row.aggregateId == session.id) {
          throw StateError('activity checkpoint is corrupt');
        }
        continue;
      }
      final decoded = decodedValue;
      if (!strictExactIdentity &&
          decoded['sessionId'] != session.id &&
          row.aggregateId != session.id) {
        continue;
      }
      final actorIsAuthorized = await _isAuthorizedCheckpointActor(
        actorIdentity: row.actorIdentity,
        ownerIdentity: ownerId,
      );
      final schemaVersion = decoded['schemaVersion'];
      final isV1 = schemaVersion == 1;
      final isV2 = schemaVersion == 2;
      const v1Keys = <String>{
        'schemaVersion',
        'activityType',
        'sessionId',
        'revision',
        'state',
      };
      const v2Keys = <String>{
        ...v1Keys,
        'terminalAtUtc',
        'terminalAcknowledged',
      };
      final expectedKeys = isV1 ? v1Keys : v2Keys;
      if ((!isV1 && !isV2) ||
          decoded.length != expectedKeys.length ||
          !decoded.keys.every(expectedKeys.contains) ||
          decoded['activityType'] != session.activityType ||
          decoded['sessionId'] != session.id ||
          decoded['revision'] is! int ||
          decoded['state'] is! Map<String, dynamic> ||
          row.eventVersion != schemaVersion ||
          row.recordedAtUtc != row.occurredAtUtc ||
          !actorIsAuthorized ||
          row.tenantContextJson != null ||
          row.correlationId != null ||
          row.causationId != null ||
          row.idempotencyKey != row.eventId ||
          row.consentContextJson !=
              jsonEncode(<String, Object?>{
                'researchConsentVersion': 0,
                'aiConsentGranted': false,
                'voiceConsentGranted': false,
                'socialConsentGranted': false,
              }) ||
          row.experimentContextJson != null ||
          row.contentRevision != null ||
          row.policyVersion != null ||
          row.appVersion != session.appVersion ||
          row.buildId != session.buildId ||
          row.providerProvenanceJson != null ||
          row.privacyClassification != 'ownerOnly') {
        throw StateError('activity checkpoint is corrupt');
      }
      final revision = decoded['revision']! as int;
      final canonicalState = _freezeJsonMap(
        (decoded['state']! as Map<String, dynamic>).cast<String, Object?>(),
      );
      if (revision < 1 ||
          revision > maxActivityRecoveryCheckpoints ||
          utf8.encode(jsonEncode(canonicalState)).length > 65536) {
        throw StateError('activity checkpoint is corrupt');
      }
      DateTime? terminalAtUtc;
      var terminalAcknowledged = false;
      if (isV2) {
        final encodedTerminal = decoded['terminalAtUtc'];
        terminalAcknowledged = decoded['terminalAcknowledged'] is bool
            ? decoded['terminalAcknowledged']! as bool
            : throw StateError('activity checkpoint is corrupt');
        if (encodedTerminal != null) {
          if (encodedTerminal is! String) {
            throw StateError('activity checkpoint is corrupt');
          }
          if (!encodedTerminal.endsWith('Z')) {
            throw StateError('activity checkpoint is corrupt');
          }
          terminalAtUtc = DateTime.tryParse(encodedTerminal);
          if (terminalAtUtc == null || !terminalAtUtc.isUtc) {
            throw StateError('activity checkpoint is corrupt');
          }
        }
        if (terminalAcknowledged && terminalAtUtc == null) {
          throw StateError('activity checkpoint is corrupt');
        }
      }
      final expectedKey = _activityCheckpointKey(
        ownerId: row.actorIdentity,
        sessionId: session.id,
        activityType: session.activityType,
        revision: revision,
      );
      if (row.eventId != expectedKey ||
          !_isExactStoredActivityCheckpoint(
            row: row,
            eventId: expectedKey,
            eventVersion: schemaVersion as int,
            actorIdentity: row.actorIdentity,
            ownerId: ownerId,
            session: session,
            occurredAtUtc: row.occurredAtUtc.toUtc(),
            payloadJson: row.payloadJson,
          )) {
        throw StateError('activity checkpoint identity is corrupt');
      }
      final candidate = LearningActivityCheckpoint(
        sessionId: session.id,
        activityType: session.activityType,
        revision: revision,
        occurredAtUtc: row.occurredAtUtc.toUtc(),
        state: canonicalState,
        terminalAtUtc: terminalAtUtc,
        terminalAcknowledged: terminalAcknowledged,
      );
      if (latest == null || candidate.revision > latest.revision) {
        latest = candidate;
      }
      revisions.add(revision);
    }
    revisions.sort();
    for (var index = 0; index < revisions.length; index += 1) {
      if (revisions[index] != index + 1) {
        throw StateError('activity checkpoint revision history is corrupt');
      }
    }
    return latest;
  }

  bool _isExactStoredActivityCheckpoint({
    required db.EventsV2Data row,
    required String eventId,
    required int eventVersion,
    required String actorIdentity,
    required String ownerId,
    required db.LearningSession session,
    required DateTime occurredAtUtc,
    required String payloadJson,
  }) {
    return row.eventId == eventId &&
        row.eventType == 'LearningActivityCheckpoint' &&
        row.eventVersion == eventVersion &&
        row.occurredAtUtc.toUtc() == occurredAtUtc &&
        row.recordedAtUtc.toUtc() == occurredAtUtc &&
        row.actorIdentity == actorIdentity &&
        row.ownerId == ownerId &&
        row.tenantContextJson == null &&
        row.aggregateType == 'LearningSession' &&
        row.aggregateId == session.id &&
        row.correlationId == null &&
        row.causationId == null &&
        row.idempotencyKey == eventId &&
        row.consentContextJson ==
            jsonEncode(<String, Object?>{
              'researchConsentVersion': 0,
              'aiConsentGranted': false,
              'voiceConsentGranted': false,
              'socialConsentGranted': false,
            }) &&
        row.experimentContextJson == null &&
        row.contentRevision == null &&
        row.policyVersion == null &&
        row.appVersion == session.appVersion &&
        row.buildId == session.buildId &&
        row.providerProvenanceJson == null &&
        row.privacyClassification == 'ownerOnly' &&
        row.payloadJson == payloadJson;
  }

  Map<String, Object?> _freezeJsonMap(Map<String, Object?> value) =>
      Map<String, Object?>.unmodifiable(
        value.map(
          (key, item) => MapEntry<String, Object?>(key, _freezeJsonValue(item)),
        ),
      );

  Object? _freezeJsonValue(Object? value) {
    if (value is Map<String, Object?>) return _freezeJsonMap(value);
    if (value is List<Object?>) {
      return List<Object?>.unmodifiable(value.map(_freezeJsonValue));
    }
    return value;
  }

  Future<bool> _isAuthorizedCheckpointActor({
    required String actorIdentity,
    required String ownerIdentity,
  }) async {
    if (actorIdentity == ownerIdentity) return true;
    final historicalActor = await (database.select(
      database.localOwners,
    )..where((row) => row.id.equals(actorIdentity))).getSingleOrNull();
    return historicalActor != null &&
        !historicalActor.isActive &&
        historicalActor.accountState == 'mergedInto:$ownerIdentity';
  }

  String _activityCheckpointKey({
    required String ownerId,
    required String sessionId,
    required String activityType,
    required int revision,
  }) {
    final digest = sha256
        .convert(
          utf8.encode(
            '$ownerId\u0000$sessionId\u0000$activityType\u0000$revision',
          ),
        )
        .toString();
    return 'learning-activity-checkpoint:$digest';
  }

  @override
  Future<CommittedAnswerReplay?> replayCommittedAnswer(
    RecordAnswerCandidate candidate,
  ) {
    _validateCandidate(candidate, requireSourceIdentity: true);
    return database.transaction(() async {
      final pairPurpose = await _pairPurposeForAnswer(
        candidate.ownerId,
        candidate.sessionId,
        candidate.promptMode,
      );
      if (pairPurpose != null) {
        _validateReservedPairCandidate(candidate, pairPurpose);
      }
      final existing = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(candidate.id))).getSingleOrNull();
      if (existing == null) return null;
      if (!_sameAttempt(existing, candidate)) {
        throw StateError('attempt id already exists with different evidence');
      }
      final event = await events.readBySourceEvidenceId(candidate.id);
      if (event == null ||
          await events.validateSourceForAttempt(
                attempt: existing,
                source: event,
              ) !=
              null ||
          !events.isExactDeclaredSourceForCandidate(
            candidate: candidate,
            source: event,
            // A retry captured after a guest-to-account merge naturally binds
            // to the active account owner while the durable event keeps the
            // historical guest actor. validateSourceForAttempt above has
            // already authenticated that actor lineage. An explicitly pinned
            // historical actor must still match exactly.
            allowStoredHistoricalActor:
                candidate.actorIdentity == candidate.ownerId,
          )) {
        throw StateError('committed answer has missing or corrupt event');
      }
      final expectedEventContext = candidate.eventContext;
      if (expectedEventContext != null) {
        late final LearningEventContext storedEventContext;
        try {
          storedEventContext = LearningEventContext.fromEvidenceEnvelope(
            envelope: event,
            evidenceContext: candidate.evidenceContext,
          );
        } on Object {
          throw StateError('committed answer has corrupt event context');
        }
        if (jsonEncode(storedEventContext.toJson()) !=
            jsonEncode(expectedEventContext.toJson())) {
          throw StateError('committed answer event context changed');
        }
      }
      final decisionSet = await events.ensureDecisionSetForAttempt(
        attempt: existing,
        sourceEvent: event,
      );
      if (pairPurpose != null) await _requireActivePairOwner(candidate.ownerId);
      return CommittedAnswerReplay(
        result: AnswerRecordResult(
          inserted: false,
          isCorrect: existing.isCorrect,
          srs: decisionSet.allows(LearningProjection.masterySrs)
              ? await _readSrsSnapshot(
                  ownerId: candidate.ownerId,
                  wordId: candidate.wordId,
                )
              : null,
        ),
        event: event,
      );
    });
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) {
    _validateAnswer(command);
    return database.transaction(() async {
      final event = command.event;
      final pairPurpose = await _pairPurposeForAnswer(
        command.ownerId,
        command.sessionId,
        command.promptMode,
      );
      if (pairPurpose != null) {
        _validateReservedPairCandidate(command.candidate, pairPurpose);
      }
      if (event != null &&
          !await _isAuthorizedCheckpointActor(
            actorIdentity: event.actorIdentity,
            ownerIdentity: command.ownerId,
          )) {
        throw ArgumentError.value(
          command,
          'command',
          'invalid answer actor lineage',
        );
      }
      final existing = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(command.id))).getSingleOrNull();
      if (existing != null) {
        if (!_sameAttempt(existing, command.candidate)) {
          throw StateError('attempt id already exists with different evidence');
        }
        final storedEvent = await events.readBySourceEvidenceId(command.id);
        late final LearningEvidenceDecisionSet decisionSet;
        if (command.isFrozenV13LegacyIngress) {
          if (storedEvent != null) {
            throw StateError('canonical event cannot be omitted during replay');
          }
          decisionSet = await events.ensureDecisionSetForAttempt(
            attempt: existing,
          );
        } else {
          final candidateEvent = command.event!;
          if (storedEvent == null ||
              await events.validateSourceForAttempt(
                    attempt: existing,
                    source: storedEvent,
                  ) !=
                  null) {
            throw StateError('canonical event cannot be retrofitted on replay');
          }
          if (jsonEncode(storedEvent.toJson()) !=
              jsonEncode(candidateEvent.toJson())) {
            throw StateError(
              'learning event identity already exists with different evidence',
            );
          }
          decisionSet = await events.ensureDecisionSetForAttempt(
            attempt: existing,
            sourceEvent: storedEvent,
          );
        }
        if (pairPurpose != null) {
          await _requireActivePairOwner(command.ownerId);
        }
        return AnswerRecordResult(
          inserted: false,
          isCorrect: existing.isCorrect,
          srs: decisionSet.allows(LearningProjection.masterySrs)
              ? await _readSrsSnapshot(
                  ownerId: command.ownerId,
                  wordId: command.wordId,
                )
              : null,
        );
      }

      if (event != null &&
          event.actorIdentity != command.ownerId &&
          pairPurpose == null) {
        throw ArgumentError.value(
          command,
          'command',
          'a first-write answer actor must equal its owner',
        );
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
                    PackagedStarterAccess.wordsFor(database, command.ownerId),
              ))
              .getSingleOrNull();
      if (word == null) {
        throw StateError('active vocabulary word not found');
      }
      final pairCheckpoint = session.activityType == 'matching'
          ? await _latestActivityCheckpoint(
              ownerId: command.ownerId,
              session: session,
            )
          : null;
      final isPair = pairCheckpoint?.state['schemaVersion'] == 6;
      if (session.activityType == 'matching') {
        final purpose = await read(
          ownerId: command.ownerId,
          sessionId: command.sessionId,
        );
        if (purpose.unknownMatching) {
          throw StateError('Matching checkpoint authority is unavailable');
        }
      }
      if (isPair) {
        await _validatePinnedPairAnswer(command, pairCheckpoint!);
      }
      if (word.isDeleted &&
          !isPair &&
          !await _isValidPinnedDeletedMatchingAnswer(
            command: command,
            session: session,
          )) {
        throw StateError('deleted vocabulary is not pinned to this session');
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
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'attempt',
        entityId: command.id,
        occurredAtUtc: command.occurredAtUtc,
      );
      if (event != null) await events.append(event);
      final insertedAttempt = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(command.id))).getSingle();
      final decisionSet = await events.ensureDecisionSetForAttempt(
        attempt: insertedAttempt,
        sourceEvent: event,
      );
      final rebuildWord =
          decisionSet.allows(LearningProjection.masterySrs) ||
          decisionSet.allows(LearningProjection.xp);
      final next = rebuildWord
          ? await projections.rebuildWord(
              ownerId: command.ownerId,
              wordId: command.wordId,
            )
          : null;
      await projections.rebuildSession(
        ownerId: command.ownerId,
        sessionId: command.sessionId,
      );
      if (decisionSet.allows(LearningProjection.achievement)) {
        await projections.rebuildAchievements(command.ownerId);
      }
      // Outbox hook — push updated SRS state to Firestore (Phase 0 Week 12-13).
      // Entity ID is wordId (unique per owner-word pair).
      if (decisionSet.allows(LearningProjection.masterySrs) && next != null) {
        await _appendSrsOutbox(
          ownerId: command.ownerId,
          wordId: command.wordId,
          answerAttemptId: command.id,
          occurredAtUtc: command.occurredAtUtc,
        );
      }
      if (isPair) await _requireActivePairOwner(command.ownerId);
      return AnswerRecordResult(
        inserted: true,
        isCorrect: command.isCorrect,
        srs: decisionSet.allows(LearningProjection.masterySrs) ? next : null,
      );
    });
  }

  Future<void> _requireActivePairOwner(String ownerId) async {
    final owners =
        await (database.select(database.localOwners)
              ..where((r) => r.isActive.equals(true))
              ..limit(2))
            .get();
    if (owners.length != 1 || owners.single.id != ownerId) {
      throw StateError('Pair canonical owner changed');
    }
  }

  Future<PairMatchingSessionPurpose?> _pairPurposeForAnswer(
    String ownerId,
    String sessionId,
    String promptMode,
  ) async {
    if (promptMode != 'matchingPair') return null;
    final purpose = await read(ownerId: ownerId, sessionId: sessionId);
    if (purpose.unknownMatching) {
      throw StateError('Matching checkpoint authority is unavailable');
    }
    if (purpose.snapshot != null) await _requireActivePairOwner(ownerId);
    return purpose.snapshot == null ? null : purpose;
  }

  void _validateReservedPairCandidate(
    RecordAnswerCandidate candidate,
    PairMatchingSessionPurpose purpose, {
    bool storedMilliseconds = false,
  }) {
    final reservation = purpose.reservations[candidate.id];
    if (reservation == null) {
      throw StateError('Pair answer has no accepted reservation');
    }
    final frozen = FrozenPendingCurrentActivityEvidence.fromJson(reservation);
    if (candidate.sessionId != frozen.sessionId ||
        candidate.wordId != frozen.wordId ||
        candidate.promptMode != frozen.promptMode ||
        candidate.isCorrect != frozen.isCorrect ||
        candidate.responseTimeMs != frozen.responseTimeMs ||
        candidate.attemptNumber != frozen.attemptNumber ||
        (storedMilliseconds
            ? candidate.occurredAtUtc.millisecondsSinceEpoch !=
                  frozen.occurredAtUtc.millisecondsSinceEpoch
            : candidate.occurredAtUtc != frozen.occurredAtUtc) ||
        candidate.providerProvenance != frozen.providerProvenance ||
        candidate.actorIdentity != frozen.actorIdentity ||
        jsonEncode(candidate.evidenceContext.toJson()) !=
            jsonEncode(frozen.evidenceContext.toJson()) ||
        jsonEncode(candidate.eventContext?.toJson()) !=
            jsonEncode(frozen.eventContext.toJson())) {
      throw StateError('Pair candidate differs from exact durable reservation');
    }
  }

  Future<PairMatchingSessionPurpose?> _authenticatePairSnapshot(
    db.LearningSession session,
    PairMatchingCheckpointSnapshot snapshot, {
    bool requireAccepted = true,
  }) async {
    PairMatchingSessionPurpose? accepted;
    if (requireAccepted) {
      accepted = await read(ownerId: session.ownerId, sessionId: session.id);
      if (accepted.snapshot == null ||
          accepted.snapshot!.startOperation != snapshot.startOperation) {
        throw StateError('Pair checkpoint has no authenticated accepted plan');
      }
    }
    final row = await database
        .customSelect(
          'SELECT * FROM learning_sessions WHERE id = ?',
          variables: [Variable(session.id)],
        )
        .getSingle();
    final query = PairMatchingSessionPurpose.historicalOwnerQuery(
      session.ownerId,
      [
        {
          'payload_json': jsonEncode({'state': snapshot.toJson()}),
        },
      ],
    );
    final owners = await database
        .customSelect(
          query.sql,
          variables: [for (final arg in query.args) Variable(arg as String)],
        )
        .get();
    PairMatchingSessionPurpose.authorizeSnapshot(
      ownerId: session.ownerId,
      session: row.data,
      snapshot: snapshot,
      historicalOwners: [for (final owner in owners) owner.data],
    );
    return accepted;
  }

  PairMatchingCheckpointSnapshot _decodePinnedPairCheckpoint(
    Map<String, Object?> state,
  ) {
    try {
      return PairMatchingCheckpointCodec.decode(state);
    } on FormatException {
      throw StateError('Pinned Pair checkpoint is invalid');
    }
  }

  FrozenPendingCurrentActivityEvidence _pinnedPairOccurrence(
    PairMatchingCheckpointSnapshot snapshot,
  ) {
    final frozen = FrozenPendingCurrentActivityEvidence.fromJson(
      snapshot.frozenEvidence!,
    );
    if (snapshot.engine.plan.sessionPurpose ==
        PairSessionPurpose.practiceReplay) {
      frozen.requirePracticeReplayContext();
    }
    final role = snapshot.engine.pending!;
    final item = snapshot.engine.plan.orderedLexicalItems.singleWhere(
      (i) => i.wordId == role.promptWordId,
    );
    final pin = LexicalPromptArtifactResolver.resolveForAdapter(
      promptMode: 'matchingPair',
      wordId: item.wordId,
      coreRevision: item.contentRevision,
      coreChecksumSha256: item.checksum,
    );
    if (pin == null ||
        frozen.contentRevision != pin.evidenceContentRevision ||
        frozen.declaredEvidenceClass !=
            (snapshot.engine.plan.sessionPurpose ==
                    PairSessionPurpose.practiceReplay
                ? EvidenceClass.recreational
                : snapshot.engine.classificationFor(role).evidenceClass) ||
        frozen.contrastiveFeedback != null) {
      throw StateError('Pair occurrence pin/classification changed');
    }
    return frozen;
  }

  Future<void> _validatePinnedPairAnswer(
    RecordAnswerCommand command,
    LearningActivityCheckpoint checkpoint,
  ) async {
    await _requireActivePairOwner(command.ownerId);
    final snapshot = _decodePinnedPairCheckpoint(checkpoint.state);
    final purpose = await read(
      ownerId: command.ownerId,
      sessionId: command.sessionId,
    );
    if (purpose.snapshot == null ||
        jsonEncode(purpose.snapshot!.toJson()) !=
            jsonEncode(snapshot.toJson())) {
      throw StateError('Pair answer reservation is not canonical');
    }
    if (snapshot.terminal?.atUtc != checkpoint.terminalAtUtc ||
        (snapshot.terminal?.acknowledged ?? false) !=
            checkpoint.terminalAcknowledged) {
      throw StateError('Pair terminal envelope changed');
    }
    if (snapshot.frozenEvidence == null) {
      throw StateError('Pair answer has no durable reservation');
    }
    final frozen = _pinnedPairOccurrence(snapshot);
    final event = command.event;
    if (event == null ||
        command.sessionId != frozen.sessionId ||
        command.id != frozen.sourceEvidenceId ||
        command.wordId != frozen.wordId ||
        command.promptMode != frozen.promptMode ||
        command.isCorrect != frozen.isCorrect ||
        command.responseTimeMs != frozen.responseTimeMs ||
        command.attemptNumber != frozen.attemptNumber ||
        command.occurredAtUtc != frozen.occurredAtUtc ||
        command.providerProvenance != frozen.providerProvenance ||
        event.actorIdentity != frozen.actorIdentity ||
        jsonEncode(command.evidenceContext.toJson()) !=
            jsonEncode(frozen.evidenceContext.toJson()) ||
        jsonEncode(
              LearningEventContext.fromEvidenceEnvelope(
                envelope: event,
                evidenceContext: command.evidenceContext,
              ).toJson(),
            ) !=
            jsonEncode(frozen.eventContext.toJson())) {
      throw StateError('Pair answer differs from reserved occurrence');
    }
  }

  Future<void> _validatePinnedPairCheckpoint({
    required db.LearningSession session,
    required LearningActivityCheckpoint checkpoint,
    required LearningActivityCheckpoint? latest,
    bool measuredAdmission = false,
  }) async {
    await _requireActivePairOwner(session.ownerId);
    if (checkpoint.state['schemaVersion'] != 6) {
      throw StateError('Pair writer cannot downgrade');
    }
    final snapshot = _decodePinnedPairCheckpoint(checkpoint.state);
    if (snapshot.terminal?.atUtc != checkpoint.terminalAtUtc ||
        (snapshot.terminal?.acknowledged ?? false) !=
            checkpoint.terminalAcknowledged) {
      throw StateError('Pair terminal envelope changed');
    }
    final plan = snapshot.engine.plan;
    final accepted = await _authenticatePairSnapshot(
      session,
      snapshot,
      requireAccepted: latest != null,
    );
    if (latest == null &&
        jsonEncode(checkpoint.state) !=
            jsonEncode(
              PairMatchingCheckpointCodec.initialState(
                plan,
                snapshot.startOperation,
              ),
            )) {
      throw StateError('Pair initial checkpoint must be empty');
    }
    PairMatchingCheckpointCodec.requireCompletionCapacity(
      snapshot,
      runtimeOwnerId: session.ownerId,
    );
    if (latest != null) {
      final prior = _decodePinnedPairCheckpoint(latest.state);
      if (snapshot.frozenEvidence != null &&
          prior.frozenEvidence == null &&
          snapshot.frozenEvidence!['ownerId'] != session.ownerId) {
        throw StateError('New Pair occurrence must use current owner');
      }
      // An exact immutable replay is validated by the ordinary repository
      // identity comparison below; it is not another lifecycle transition.
      if (checkpoint.revision != latest.revision) {
        PairMatchingCheckpointCodec.validateTransition(
          prior,
          snapshot,
          allowMeasuredAdmission:
              measuredAdmission &&
              latest.revision == 1 &&
              checkpoint.revision == 2 &&
              checkpoint.occurredAtUtc == plan.createdAtUtc,
        );
      }
      if (prior.startOperation != snapshot.startOperation ||
          prior.engine.plan.planFingerprint != plan.planFingerprint ||
          snapshot.engine.operationRevision < prior.engine.operationRevision ||
          snapshot.engine.attempts.length < prior.engine.attempts.length ||
          !snapshot.engine.supportedWordIds.containsAll(
            prior.engine.supportedWordIds,
          )) {
        throw StateError('Pair checkpoint lineage regressed');
      }
      for (var i = 0; i < prior.engine.attempts.length; i++) {
        if (jsonEncode(snapshot.engine.attempts[i].toJson()) !=
                jsonEncode(prior.engine.attempts[i].toJson()) ||
            snapshot.evidenceIds[i] != prior.evidenceIds[i]) {
          throw StateError('Pair committed ledger changed');
        }
      }
      for (final entry in prior.engine.supportAtRevision.entries) {
        if (snapshot.engine.supportAtRevision[entry.key] != entry.value) {
          throw StateError('Pair support acquisition changed');
        }
      }
      if (prior.engine.pending != null) {
        final next =
            snapshot.engine.pending ??
            (snapshot.engine.attempts.length > prior.engine.attempts.length
                ? snapshot.engine.attempts.last
                : null);
        if (next == null ||
            jsonEncode(next.toJson()) !=
                jsonEncode(prior.engine.pending!.toJson()) ||
            (snapshot.engine.pending != null &&
                jsonEncode(snapshot.frozenEvidence) !=
                    jsonEncode(prior.frozenEvidence))) {
          throw StateError('Pair pending reservation changed');
        }
      }
    }
    if (snapshot.frozenEvidence != null) _pinnedPairOccurrence(snapshot);
    final answers =
        await (database.select(database.answerAttempts)
              ..where(
                (r) =>
                    r.ownerId.equals(session.ownerId) &
                    r.sessionId.equals(session.id),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.attemptNumber)])
              ..limit(maxActivityRecoveryAttempts + 1))
            .get();
    final expected = [
      ...snapshot.engine.attempts,
      if (snapshot.engine.pending != null) snapshot.engine.pending!,
    ];
    if (answers.length < snapshot.engine.attempts.length ||
        answers.length > expected.length) {
      throw StateError('Pair checkpoint lost or invented attempts');
    }
    for (var i = 0; i < answers.length; i++) {
      final a = answers[i], role = expected[i];
      final id = i < snapshot.evidenceIds.length
          ? snapshot.evidenceIds[i]
          : snapshot.frozenEvidence!['sourceEvidenceId'];
      if (a.id != id ||
          a.wordId != role.promptWordId ||
          a.isCorrect != role.isCorrect ||
          a.attemptNumber != i + 1 ||
          a.responseTimeMs != role.responseTimeMs ||
          a.evidenceClass !=
              (plan.sessionPurpose == PairSessionPurpose.practiceReplay
                      ? EvidenceClass.recreational
                      : snapshot.engine.classificationFor(role).evidenceClass)
                  .name) {
        throw StateError('Pair checkpoint does not match canonical attempts');
      }
      final frozenJson = accepted?.reservations[a.id];
      final source = await events.readValidatedSourceForAttempt(attempt: a);
      if (frozenJson == null || source == null) {
        throw StateError(
          'Pair canonical answer has no authenticated reservation',
        );
      }
      final context = EvidenceContext.fromJson(
        (jsonDecode(a.evidenceContextJson) as Map).cast<String, Object?>(),
      );
      _validateReservedPairCandidate(
        RecordAnswerCandidate(
          id: a.id,
          ownerId: a.ownerId,
          sessionId: a.sessionId,
          wordId: a.wordId,
          promptMode: a.promptMode,
          isCorrect: a.isCorrect,
          responseTimeMs: a.responseTimeMs,
          attemptNumber: a.attemptNumber,
          occurredAtUtc: _fromEpoch(a.occurredAtUtcMs)!,
          evidenceContext: context,
          providerProvenance: a.providerProvenance,
          actorIdentity: source.actorIdentity,
          eventContext: LearningEventContext.fromEvidenceEnvelope(
            envelope: source,
            evidenceContext: context,
          ),
        ),
        accepted!,
        storedMilliseconds: true,
      );
    }
  }

  Future<bool> _isValidPinnedDeletedMatchingAnswer({
    required RecordAnswerCommand command,
    required db.LearningSession session,
  }) async {
    if (session.activityType != 'matching' ||
        command.promptMode != 'matchingPair' ||
        (command.providerProvenance != 'pinned-lexical-matching' &&
            !isContrastiveFeedbackAttemptProvenance(
              command.providerProvenance,
            )) ||
        command.evidenceContext.skillId != 'matching-recognition' ||
        (command.evidenceContext.evidenceClass != EvidenceClass.recognition &&
            command.evidenceContext.evidenceClass !=
                EvidenceClass.guidedPractice)) {
      return false;
    }
    final checkpoint = await _latestActivityCheckpoint(
      ownerId: command.ownerId,
      session: session,
    );
    final state = checkpoint?.state;
    final pairs = state?['pairs'];
    final pending = state?['pendingEvidence'];
    final stateVersion = state?['schemaVersion'];
    if ((stateVersion != 1 &&
            stateVersion != 2 &&
            stateVersion != 3 &&
            stateVersion != 4 &&
            stateVersion != 5) ||
        pairs is! List<Object?> ||
        pending is! Map<String, Object?>) {
      return false;
    }
    final matches = pairs
        .where((value) {
          return value is Map<String, Object?> && value['id'] == command.wordId;
        })
        .toList(growable: false);
    if (matches.length != 1) return false;
    final snapshot = matches.single! as Map<String, Object?>;
    const wordKeys = <String>{
      'id',
      'categoryId',
      'spelling',
      'meaning',
      'partOfSpeech',
      'normalizedSpelling',
      'normalizedMeaning',
      'contentRevision',
      'contentChecksumSha256',
    };
    if (snapshot.length != wordKeys.length ||
        !snapshot.keys.every(wordKeys.contains)) {
      return false;
    }
    final revision = snapshot['contentRevision'];
    final checksum = snapshot['contentChecksumSha256'];
    final contentIdentity = revision is int && checksum is String
        ? LexicalPromptArtifactResolver.resolveForAdapter(
            promptMode: 'matchingPair',
            wordId: command.wordId,
            coreRevision: revision,
            coreChecksumSha256: checksum,
          )
        : null;
    final evidenceContentRevision = contentIdentity?.evidenceContentRevision;
    if (evidenceContentRevision == null ||
        command.evidenceContext.contentRevision != evidenceContentRevision) {
      return false;
    }
    const pendingV1Keys = <String>{
      'sourceEvidenceId',
      'occurredAtUtc',
      'wordId',
      'selectedMeaningWordId',
      'isCorrect',
      'responseTimeMs',
      'attemptNumber',
      'evidenceClass',
      'hintLevel',
      'contentRevision',
      'canonicalCorrectAnswer',
      'evidenceContext',
      'eventContext',
    };
    const pendingV2Keys = <String>{
      ...pendingV1Keys,
      'schemaVersion',
      'actorIdentity',
    };
    const pendingV3Keys = <String>{...pendingV2Keys, 'providerProvenance'};
    const pendingV4Keys = <String>{...pendingV3Keys, 'contrastiveFeedback'};
    final pendingVersion = pending['schemaVersion'];
    final expectedPendingKeys = switch (pendingVersion) {
      2 => pendingV2Keys,
      3 => pendingV3Keys,
      4 => pendingV4Keys,
      _ => pendingV1Keys,
    };
    if (pendingVersion != null &&
        pendingVersion != 2 &&
        pendingVersion != 3 &&
        pendingVersion != 4) {
      return false;
    }
    if (pending.length != expectedPendingKeys.length ||
        !pending.keys.every(expectedPendingKeys.contains)) {
      return false;
    }
    final encodedOccurredAt = pending['occurredAtUtc'];
    if (encodedOccurredAt is! String || !encodedOccurredAt.endsWith('Z')) {
      return false;
    }
    final occurredAtUtc = DateTime.tryParse(encodedOccurredAt);
    final frozenEvidenceJson = pending['evidenceContext'];
    final frozenEventJson = pending['eventContext'];
    final event = command.event;
    final pendingActor =
        pendingVersion == 2 || pendingVersion == 3 || pendingVersion == 4
        ? pending['actorIdentity']
        : command.ownerId;
    final pendingProvider = pendingVersion == 3 || pendingVersion == 4
        ? pending['providerProvenance']
        : 'pinned-lexical-matching';
    FrozenContrastiveFeedbackContext? contrastiveFeedback;
    final encodedContrastive = pendingVersion == 4
        ? pending['contrastiveFeedback']
        : null;
    if (encodedContrastive is Map<String, Object?>) {
      try {
        contrastiveFeedback = FrozenContrastiveFeedbackContext.fromJson(
          encodedContrastive,
        );
      } on Object {
        return false;
      }
    } else if (encodedContrastive != null) {
      return false;
    }
    final contrastiveProvenance = isContrastiveFeedbackAttemptProvenance(
      command.providerProvenance,
    );
    if (contrastiveProvenance) {
      if (pendingVersion != 4 ||
          contrastiveFeedback == null ||
          pendingProvider != command.providerProvenance ||
          command.providerProvenance !=
              contrastiveFeedbackAttemptProvenance(contrastiveFeedback) ||
          contrastiveFeedback.manifestIdentity.id != command.wordId ||
          contrastiveFeedback.promptMode != command.promptMode ||
          contrastiveFeedback.evidenceContentRevision !=
              evidenceContentRevision ||
          contrastiveFeedback.correctOptionId != command.wordId ||
          contrastiveFeedback.selectedDistractorId !=
              pending['selectedMeaningWordId'] ||
          command.isCorrect) {
        return false;
      }
    } else if (contrastiveFeedback != null) {
      return false;
    }
    if (occurredAtUtc == null ||
        !occurredAtUtc.isUtc ||
        event == null ||
        pendingActor is! String ||
        pendingActor != event.actorIdentity ||
        frozenEvidenceJson is! Map<String, Object?> ||
        frozenEventJson is! Map<String, Object?> ||
        pending['sourceEvidenceId'] != command.id ||
        occurredAtUtc != command.occurredAtUtc ||
        pending['wordId'] != command.wordId ||
        pending['isCorrect'] != command.isCorrect ||
        pending['responseTimeMs'] != command.responseTimeMs ||
        pending['attemptNumber'] != command.attemptNumber ||
        ((pendingVersion == 3 || pendingVersion == 4) &&
            pendingProvider != command.providerProvenance) ||
        pending['evidenceClass'] !=
            command.evidenceContext.evidenceClass.name ||
        pending['hintLevel'] != command.evidenceContext.hintLevel ||
        pending['contentRevision'] != evidenceContentRevision ||
        pending['canonicalCorrectAnswer'] !=
            (snapshot['meaning'] as String).trim().replaceAll(
              RegExp(r'\s+'),
              ' ',
            ) ||
        pending['selectedMeaningWordId'] is! String ||
        command.isCorrect !=
            (pending['selectedMeaningWordId'] == command.wordId) ||
        jsonEncode(frozenEvidenceJson) !=
            jsonEncode(command.evidenceContext.toJson())) {
      return false;
    }
    if (!await _isAuthorizedCheckpointActor(
      actorIdentity: pendingActor,
      ownerIdentity: command.ownerId,
    )) {
      return false;
    }
    try {
      final frozenEventContext = LearningEventContext.fromJson(frozenEventJson);
      frozenEventContext.validateAgainst(
        evidenceContext: command.evidenceContext,
        occurredAtUtc: command.occurredAtUtc,
      );
      final commandEventContext = LearningEventContext.fromEvidenceEnvelope(
        envelope: event,
        evidenceContext: command.evidenceContext,
      );
      return jsonEncode(frozenEventContext.toJson()) ==
          jsonEncode(commandEventContext.toJson());
    } on Object {
      return false;
    }
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
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
      if (endedAtUtc.millisecondsSinceEpoch < row.startedAtUtcMs) {
        throw ArgumentError.value(
          endedAtUtc,
          'endedAtUtc',
          'precedes session start',
        );
      }
      LearningActivityCheckpoint? readingCheckpoint;
      AssociativeReadingCheckpoint? readingState;
      if (row.activityType == 'associativeReading') {
        final latest = await _latestActivityCheckpoint(
          ownerId: ownerId,
          session: row,
          strictExactIdentity: true,
        );
        if (row.id.startsWith('reading:') ||
            latest?.state['kind'] == 'associativeReading') {
          if (latest == null)
            throw StateError('Canonical reading checkpoint missing');
          await _requireReadingOwner(ownerId);
          final recovery = await _loadActivityRecoveryForSession(
            ownerId: ownerId,
            session: row,
            strictExactIdentity: true,
          );
          readingCheckpoint = latest;
          readingState = AssociativeReadingCheckpoint.fromJson(latest.state);
          if (readingState.stage != 6)
            throw StateError('Reading has not reached completion');
          readingState.recallResults(recovery!);
          await _validateReadingPins(ownerId, readingState);
        }
      }
      // A captured close can outlive the pane's owner binding. Authenticate
      // strict Pair work inside the canonical transaction, including retries.
      PairMatchingCheckpointSnapshot? pair;
      if (await _requiresPairCloseAuthentication(row)) {
        pair = (await read(ownerId: ownerId, sessionId: sessionId)).snapshot;
        if (pair == null) {
          throw StateError('Pair completion authority is unavailable');
        }
        final accepted = await _inspectPairDisposition(
          ownerId: ownerId,
          startOperation: pair.startOperation,
          requireConfiguration: false,
        );
        if (accepted.kind != PairAcceptedDispositionKind.complete ||
            accepted.recovery.checkpoint!.terminalAtUtc != endedAtUtc) {
          throw StateError(
            'Pair completion requires exact accepted terminal intent',
          );
        }
      }
      final total = row.correctCount + row.wrongCount;
      final score = total == 0 ? 0 : ((row.correctCount * 100) / total).round();
      if (row.state == 'completed') {
        if (row.endedAtUtcMs != endedAtUtc.millisecondsSinceEpoch) {
          throw StateError(
            'learning session was completed with a different terminal time',
          );
        }
        return _rowToSummary(row);
      }
      if (row.state != 'active') {
        throw StateError('learning session is not active');
      }
      {
        await (database.update(
          database.learningSessions,
        )..where((candidate) => candidate.id.equals(sessionId))).write(
          db.LearningSessionsCompanion(
            state: const Value('completed'),
            endedAtUtcMs: Value(endedAtUtc.millisecondsSinceEpoch),
            score: Value(score),
          ),
        );
        await projections.rebuildAchievements(ownerId);
      }
      if (pair != null) await _requireActivePairOwner(ownerId);
      final completed = await (database.select(
        database.learningSessions,
      )..where((candidate) => candidate.id.equals(sessionId))).getSingle();
      if (readingCheckpoint != null && readingState != null) {
        // Session timestamps are persisted at millisecond precision. Use that
        // durable identity for the generated reading checkpoint as well.
        final terminalAtUtc = _fromEpoch(completed.endedAtUtcMs)!;
        await _appendActivityCheckpoint(
          ownerId: ownerId,
          checkpoint: LearningActivityCheckpoint(
            sessionId: sessionId,
            activityType: 'associativeReading',
            revision: readingCheckpoint.revision + 1,
            occurredAtUtc: endedAtUtc,
            state: readingState.toJson(),
            terminalAtUtc: terminalAtUtc,
            terminalAcknowledged: true,
          ),
        );
        await saveReadingProgress(
          ReadingProgressCommand(
            eventId: 'reading-complete:$sessionId',
            ownerId: ownerId,
            documentId: readingState.documentId,
            documentRevision: readingState.documentRevision,
            position: 6,
            isCompleted: true,
            occurredAtUtc: endedAtUtc,
          ),
        );
      }
      return _rowToSummary(completed);
    });
  }

  Future<bool> _requiresPairCloseAuthentication(
    db.LearningSession session,
  ) async {
    // Atomic Pair admission reserves this namespace, including after rehome.
    // Missing or downgraded checkpoints must not turn it into a generic close.
    if (session.id.startsWith('pair:')) return true;
    if (session.activityType != 'matching') return false;
    final query = PairMatchingSessionPurpose.checkpointQuery(
      session.ownerId,
      session.id,
    );
    final candidates = await database
        .customSelect(
          query.sql,
          variables: [for (final arg in query.args) Variable(arg as String)],
        )
        .get();
    if (candidates.length > maxActivityRecoveryCheckpoints) {
      throw StateError('Matching completion checkpoint bound exceeded');
    }
    var pair = false;
    // Generic checkpoints may contain arbitrary valid map state. Inspect the
    // entire canonical candidate set for Pair evidence; never catch corruption
    // and reinterpret it as a legacy adapter checkpoint.
    for (final candidate in candidates) {
      final payload = jsonDecode(candidate.data['payload_json'] as String);
      if (payload is! Map || payload['state'] is! Map) {
        throw StateError('Matching completion checkpoint is malformed');
      }
      final state = payload['state'] as Map;
      pair =
          pair ||
          state['schemaVersion'] == 6 ||
          state.containsKey('startOperation') ||
          state.containsKey('plan');
    }
    return pair;
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
    final query =
        database.select(database.vocabularyWords).join([
            innerJoin(
              database.srsStates,
              database.srsStates.wordId.equalsExp(database.vocabularyWords.id) &
                  database.srsStates.ownerId.equals(ownerId) &
                  database.srsStates.dueAtUtcMs.isSmallerOrEqualValue(
                    nowUtc.millisecondsSinceEpoch,
                  ),
            ),
          ])
          ..where(
            PackagedStarterAccess.wordsFor(database, ownerId) &
                database.vocabularyWords.isDeleted.equals(false),
          )
          ..orderBy([OrderingTerm.asc(database.srsStates.dueAtUtcMs)])
          ..limit(limit);
    final rows = await query.get();
    return rows
        .map((row) => row.readTable(database.vocabularyWords))
        .map(_quizWordFromRow)
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

  Future<void> _appendImmutableOutbox({
    required String ownerId,
    required String entityType,
    required String entityId,
    required DateTime occurredAtUtc,
  }) async {
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId:
                entityType == 'attempt' &&
                    LearningEvidenceContract.validSourceEvidenceId(entityId)
                ? LearningEvidenceContract.answerAttemptOutboxOperationId(
                    entityId,
                  )
                : '$entityType:$entityId:1',
            ownerId: ownerId,
            entityType: entityType,
            entityId: entityId,
            operationKind: 'upsert',
            baseRevision: const Value(0),
            createdAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _appendSrsOutbox({
    required String ownerId,
    required String wordId,
    required String answerAttemptId,
    required DateTime occurredAtUtc,
  }) async {
    final attempts =
        await (database.select(database.answerAttempts)..where(
              (attempt) =>
                  attempt.ownerId.equals(ownerId) &
                  attempt.wordId.equals(wordId),
            ))
            .get();
    var revision = 0;
    for (final attempt in attempts) {
      final decisionSet = await projections.decisionSetForAttempt(attempt);
      if (decisionSet.allows(LearningProjection.masterySrs)) revision++;
    }
    if (revision < 1) {
      throw StateError('SRS revision requires durable answer evidence');
    }
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId: SrsOperationIdentity.create(
              ownerId: ownerId,
              wordId: wordId,
              answerAttemptId: answerAttemptId,
              revision: revision,
            ),
            ownerId: ownerId,
            entityType: 'srsState',
            entityId: wordId,
            operationKind: 'upsert',
            baseRevision: Value(revision - 1),
            createdAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<SrsSnapshot?> _readSrsSnapshot({
    required String ownerId,
    required String wordId,
  }) async {
    final row =
        await (database.select(database.srsStates)..where(
              (candidate) =>
                  candidate.ownerId.equals(ownerId) &
                  candidate.wordId.equals(wordId),
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

  bool _sameAttempt(db.AnswerAttempt row, RecordAnswerCandidate candidate) {
    return row.ownerId == candidate.ownerId &&
        row.sessionId == candidate.sessionId &&
        row.wordId == candidate.wordId &&
        row.promptMode == candidate.promptMode &&
        row.isCorrect == candidate.isCorrect &&
        row.responseTimeMs == candidate.responseTimeMs &&
        row.attemptNumber == candidate.attemptNumber &&
        row.occurredAtUtcMs == candidate.occurredAtUtc.millisecondsSinceEpoch &&
        row.providerProvenance == candidate.providerProvenance &&
        LearningEvidenceContract.sameEvidenceMetadata(
          evidenceClass: row.evidenceClass,
          evidenceContextJson: row.evidenceContextJson,
          expectedContext: candidate.evidenceContext,
        );
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
    final candidate = command.candidate;
    _validateCandidate(
      candidate,
      requireSourceIdentity: !command.isFrozenV13LegacyIngress,
    );
    if (command.isFrozenV13LegacyIngress) {
      if (command.event != null ||
          !LearningEvidenceContract.isExactFrozenV13LegacyEvidence(
            command.evidenceContext,
          )) {
        throw ArgumentError.value(
          command,
          'command',
          'invalid frozen-v13 legacy ingress',
        );
      }
      return;
    }
    final event = command.event;
    if (event == null ||
        !events.isExactDeclaredSourceForCandidate(
          candidate: candidate,
          source: event,
        )) {
      throw ArgumentError.value(command, 'command', 'invalid answer evidence');
    }
  }

  void _validateCandidate(
    RecordAnswerCandidate candidate, {
    required bool requireSourceIdentity,
  }) {
    final occurredAt = _requiredUtc(candidate.occurredAtUtc, 'occurredAtUtc');
    if ((requireSourceIdentity &&
            (!LearningEvidenceContract.validSourceEvidenceId(candidate.id) ||
                LearningEvidenceContract.isExactFrozenV13LegacyEvidence(
                  candidate.evidenceContext,
                ))) ||
        !LearningEvidenceContract.validAttempt(
          id: candidate.id,
          ownerId: candidate.ownerId,
          sessionId: candidate.sessionId,
          wordId: candidate.wordId,
          promptMode: candidate.promptMode,
          responseTimeMs: candidate.responseTimeMs,
          attemptNumber: candidate.attemptNumber,
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
          providerProvenance: candidate.providerProvenance,
          evidenceClass: candidate.evidenceContext.evidenceClass.name,
          evidenceContextJson: jsonEncode(candidate.evidenceContext.toJson()),
        )) {
      throw ArgumentError.value(
        candidate,
        'candidate',
        'invalid answer evidence',
      );
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

  @override
  Future<LearningSessionSummary?> getActiveSession({
    required String ownerId,
  }) async {
    final row =
        await (database.select(database.learningSessions)
              ..where(
                (t) => t.ownerId.equals(ownerId) & t.state.equals('active'),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.startedAtUtcMs)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return _rowToSummary(row);
  }

  @override
  Future<LearningSessionSummary?> loadSessionConfigurationState({
    required String ownerId,
    required String sessionId,
  }) async {
    final row =
        await (database.select(database.learningSessions)..where(
              (candidate) =>
                  candidate.ownerId.equals(_required(ownerId, 'ownerId')) &
                  candidate.id.equals(_required(sessionId, 'sessionId')),
            ))
            .getSingleOrNull();
    return row == null ? null : _rowToSummary(row);
  }

  @override
  Future<Duration> addSessionConfigurationActiveEffort({
    required String ownerId,
    required String sessionId,
    required String configurationIdentity,
    required Duration delta,
  }) async {
    final owner = _required(ownerId, 'ownerId');
    final session = _required(sessionId, 'sessionId');
    final identity = _required(configurationIdentity, 'configurationIdentity');
    if (delta.isNegative || delta > const Duration(minutes: 5)) {
      throw ArgumentError.value(
        delta,
        'delta',
        'must be between zero and five minutes',
      );
    }
    return database.transaction(() async {
      final purpose = await read(ownerId: owner, sessionId: session);
      if (!purpose.allowsLearningAuthority) {
        throw StateError('Session purpose does not admit configuration effort');
      }
      final updated = await database.customUpdate(
        'UPDATE learning_sessions SET configuration_active_effort_us = '
        'configuration_active_effort_us + ? WHERE id = ? AND owner_id = ? '
        'AND state = ? AND session_configuration_identity = ?',
        variables: <Variable<Object>>[
          Variable<int>(delta.inMicroseconds),
          Variable<String>(session),
          Variable<String>(owner),
          const Variable<String>('active'),
          Variable<String>(identity),
        ],
        updates: <TableInfo<Table, Object?>>{database.learningSessions},
      );
      if (updated != 1) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.tampered,
        );
      }
      final row =
          await (database.select(database.learningSessions)..where(
                (candidate) =>
                    candidate.id.equals(session) &
                    candidate.ownerId.equals(owner),
              ))
              .getSingle();
      if (row.configurationActiveEffortUs < 0) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.tampered,
        );
      }
      return Duration(microseconds: row.configurationActiveEffortUs);
    });
  }

  @override
  Future<void> abandonActiveSessions({required String ownerId}) async {
    await (database.update(database.learningSessions)
          ..where((t) => t.ownerId.equals(ownerId) & t.state.equals('active')))
        .write(const db.LearningSessionsCompanion(state: Value('abandoned')));
  }

  @override
  Future<PairAcceptedDispositionSnapshot> inspectPairDisposition({
    required String ownerId,
    required String startOperation,
  }) => database.transaction(
    () => _inspectPairDisposition(
      ownerId: ownerId,
      startOperation: startOperation,
    ),
  );

  Future<PairAcceptedDispositionSnapshot> _inspectPairDisposition({
    required String ownerId,
    required String startOperation,
    bool requireConfiguration = true,
  }) async {
    await _requireActivePairOwner(ownerId);
    final operation = PairMatchingStartOperation.fromStableSerialization(
      startOperation,
    );
    if (requireConfiguration && operation.configuration == null) {
      throw StateError(
        'unavailable Pair requires its accepted owner and configuration',
      );
    }
    final recovery = await loadExactActivityRecovery(
      ownerId: ownerId,
      sessionId: operation.plan.learningSessionId,
      activityType: 'matching',
    );
    if (recovery == null || recovery.checkpoint == null) {
      throw StateError('accepted Pair recovery is unavailable');
    }
    final purpose = await read(
      ownerId: ownerId,
      sessionId: operation.plan.learningSessionId,
    );
    final snapshot = purpose.snapshot;
    if (snapshot == null || snapshot.startOperation != startOperation) {
      throw StateError('accepted Pair configuration or checkpoint changed');
    }
    final row =
        await (database.select(database.learningSessions)..where(
              (r) =>
                  r.id.equals(operation.plan.learningSessionId) &
                  r.ownerId.equals(ownerId),
            ))
            .getSingle();
    await _validatePinnedPairCheckpoint(
      session: row,
      checkpoint: recovery.checkpoint!,
      latest: recovery.checkpoint!,
    );
    if (row.correctCount !=
            recovery.attempts.where((a) => a.isCorrect).length ||
        row.wrongCount != recovery.attempts.where((a) => !a.isCorrect).length) {
      throw StateError('Pair canonical answer counts changed');
    }
    for (final candidate in recovery.attempts) {
      final attempt = await (database.select(
        database.answerAttempts,
      )..where((r) => r.id.equals(candidate.id))).getSingle();
      final source = await events.readBySourceEvidenceId(candidate.id);
      if (source == null) {
        throw StateError('Pair committed source is unavailable');
      }
      await events.requireExistingDecisionSetForAttempt(
        attempt: attempt,
        sourceEvent: source,
      );
    }
    var kind = snapshot.engine.complete
        ? PairAcceptedDispositionKind.complete
        : PairAcceptedDispositionKind.incomplete;
    final frozen = snapshot.frozenEvidence == null
        ? null
        : _pinnedPairOccurrence(snapshot);
    if (frozen != null) {
      final attempt = await (database.select(
        database.answerAttempts,
      )..where((r) => r.id.equals(frozen.sourceEvidenceId))).getSingleOrNull();
      if (attempt == null) {
        final source = await events.readBySourceEvidenceId(
          frozen.sourceEvidenceId,
        );
        final orphanReceipts =
            await (database.select(database.eventsV2)
                  ..where((r) => r.aggregateId.equals(frozen.sourceEvidenceId))
                  ..limit(1))
                .get();
        final orphanOutbox =
            await (database.select(database.outboxOperations)
                  ..where((r) => r.entityId.equals(frozen.sourceEvidenceId))
                  ..limit(1))
                .get();
        if (source != null ||
            orphanReceipts.isNotEmpty ||
            orphanOutbox.isNotEmpty) {
          throw StateError('Pair pending answer has partial durable receipts');
        }
        kind = PairAcceptedDispositionKind.pendingUncommitted;
      } else {
        final candidate = RecordAnswerCandidate(
          id: frozen.sourceEvidenceId,
          ownerId: ownerId,
          sessionId: frozen.sessionId,
          wordId: frozen.wordId,
          promptMode: frozen.promptMode,
          isCorrect: frozen.isCorrect,
          responseTimeMs: frozen.responseTimeMs,
          attemptNumber: frozen.attemptNumber,
          occurredAtUtc: frozen.occurredAtUtc,
          evidenceContext: frozen.evidenceContext,
          providerProvenance: frozen.providerProvenance,
          actorIdentity: frozen.actorIdentity,
          eventContext: frozen.eventContext,
        );
        final source = await events.readBySourceEvidenceId(
          frozen.sourceEvidenceId,
        );
        if (!_sameAttempt(attempt, candidate) ||
            source == null ||
            !events.isExactDeclaredSourceForCandidate(
              candidate: candidate,
              source: source,
            ) ||
            jsonEncode(
                  LearningEventContext.fromEvidenceEnvelope(
                    envelope: source,
                    evidenceContext: frozen.evidenceContext,
                  ).toJson(),
                ) !=
                jsonEncode(frozen.eventContext.toJson())) {
          throw StateError('Pair pending committed identity changed');
        }
        await events.requireExistingDecisionSetForAttempt(
          attempt: attempt,
          sourceEvent: source,
        );
        kind = PairAcceptedDispositionKind.pendingCommitted;
      }
    }
    if (row.state == 'abandoned') {
      if (kind == PairAcceptedDispositionKind.pendingCommitted ||
          snapshot.engine.complete ||
          snapshot.terminal != null ||
          row.endedAtUtcMs == null) {
        throw StateError('stopped Pair has inconsistent terminal identity');
      }
      kind = PairAcceptedDispositionKind.stopped;
    } else if (row.state == 'completed' &&
        (kind != PairAcceptedDispositionKind.complete ||
            snapshot.terminal == null ||
            row.endedAtUtcMs !=
                snapshot.terminal!.atUtc.millisecondsSinceEpoch)) {
      throw StateError('completed Pair has inconsistent terminal identity');
    } else if (row.state != 'active' && row.state != 'completed') {
      throw StateError('Pair canonical state is unavailable');
    }
    await _requireActivePairOwner(ownerId);
    return PairAcceptedDispositionSnapshot(kind: kind, recovery: recovery);
  }

  @override
  Future<LearningSessionSummary> abandonUnavailablePairSession({
    required String ownerId,
    required String startOperation,
    required LearningActivityCheckpoint expectedCheckpoint,
    required DateTime abandonedAtUtc,
  }) => database.transaction(() async {
    final loaded = await _inspectPairDisposition(
      ownerId: ownerId,
      startOperation: startOperation,
    );
    final checkpoint = loaded.recovery.checkpoint!;
    if (checkpoint.sessionId != expectedCheckpoint.sessionId ||
        checkpoint.activityType != expectedCheckpoint.activityType ||
        checkpoint.revision != expectedCheckpoint.revision ||
        checkpoint.occurredAtUtc != expectedCheckpoint.occurredAtUtc ||
        checkpoint.terminalAtUtc != expectedCheckpoint.terminalAtUtc ||
        checkpoint.terminalAcknowledged !=
            expectedCheckpoint.terminalAcknowledged ||
        jsonEncode(checkpoint.state) != jsonEncode(expectedCheckpoint.state)) {
      throw StateError('Pair disposition checkpoint changed');
    }
    if (loaded.kind == PairAcceptedDispositionKind.complete ||
        loaded.kind == PairAcceptedDispositionKind.pendingCommitted) {
      throw StateError('Pair committed work requires exact reconciliation');
    }
    if (loaded.kind == PairAcceptedDispositionKind.pendingUncommitted) {
      final snapshot = _decodePinnedPairCheckpoint(checkpoint.state);
      final frozen = _pinnedPairOccurrence(snapshot);
      final currentMode = await events.rolloutModeProvider.resolve(
        ownerId: ownerId,
        evidenceContext: frozen.evidenceContext,
      );
      if (currentMode == frozen.evidenceContext.rolloutMode) {
        throw StateError(
          'Pair pending answer remains eligible for exact retry',
        );
      }
    }
    final result = await abandonSession(
      ownerId: ownerId,
      sessionId: loaded.recovery.session.id,
      abandonedAtUtc: abandonedAtUtc,
    );
    await _requireActivePairOwner(ownerId);
    return result;
  });

  @override
  Future<LearningSessionSummary> completeUnavailablePairSession({
    required String ownerId,
    required String startOperation,
    required DateTime completedAtUtc,
  }) => database.transaction(() async {
    final loaded = await _inspectPairDisposition(
      ownerId: ownerId,
      startOperation: startOperation,
    );
    if (loaded.kind != PairAcceptedDispositionKind.complete ||
        loaded.recovery.checkpoint!.terminalAtUtc != completedAtUtc) {
      throw StateError(
        'Pair completion requires exact accepted terminal intent',
      );
    }
    final result = await finishSession(
      ownerId: ownerId,
      sessionId: loaded.recovery.session.id,
      endedAtUtc: completedAtUtc,
    );
    await _requireActivePairOwner(ownerId);
    return result;
  });

  @override
  Future<void> replayAcceptedPairAnswer({
    required String ownerId,
    required String startOperation,
    required String sourceEvidenceId,
  }) => database.transaction(() async {
    final loaded = await _inspectPairDisposition(
      ownerId: ownerId,
      startOperation: startOperation,
    );
    if (loaded.kind != PairAcceptedDispositionKind.pendingCommitted ||
        loaded.recovery.attempts.last.id != sourceEvidenceId) {
      throw StateError(
        'Pair recovery requires an already committed pending answer',
      );
    }
    // Classification and the existing replay share this transaction. Neither
    // a missing attempt nor a missing decision can become a new first write.
    final result = await replayCommittedAnswer(loaded.recovery.attempts.last);
    if (result == null) throw StateError('Pair committed answer disappeared');
    await _requireActivePairOwner(ownerId);
  });

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) {
    final requiredOwnerId = _required(ownerId, 'ownerId');
    final requiredSessionId = _required(sessionId, 'sessionId');
    final terminalAt = _requiredUtc(abandonedAtUtc, 'abandonedAtUtc');
    final terminalAtUtcMs = terminalAt.millisecondsSinceEpoch;
    return database.transaction(() async {
      final row =
          await (database.select(database.learningSessions)..where(
                (candidate) =>
                    candidate.id.equals(requiredSessionId) &
                    candidate.ownerId.equals(requiredOwnerId),
              ))
              .getSingleOrNull();
      if (row == null) throw StateError('learning session not found');
      if (terminalAtUtcMs < row.startedAtUtcMs) {
        throw ArgumentError.value(
          abandonedAtUtc,
          'abandonedAtUtc',
          'precedes session start',
        );
      }
      if (row.state == 'abandoned') {
        if (row.endedAtUtcMs == terminalAtUtcMs) return _rowToSummary(row);
        throw StateError(
          'learning session was abandoned with a different terminal time',
        );
      }
      if (row.state != 'active') {
        throw StateError('learning session is not active');
      }
      await (database.update(database.learningSessions)..where(
            (candidate) =>
                candidate.id.equals(requiredSessionId) &
                candidate.ownerId.equals(requiredOwnerId) &
                candidate.state.equals('active'),
          ))
          .write(
            db.LearningSessionsCompanion(
              state: const Value('abandoned'),
              endedAtUtcMs: Value(terminalAtUtcMs),
            ),
          );
      final updated =
          await (database.select(database.learningSessions)..where(
                (candidate) =>
                    candidate.id.equals(requiredSessionId) &
                    candidate.ownerId.equals(requiredOwnerId),
              ))
              .getSingle();
      return _rowToSummary(updated);
    });
  }

  @override
  Future<List<LearningSessionSummary>> listSessionHistory({
    required String ownerId,
    required int limit,
  }) async {
    final rows =
        await (database.select(database.learningSessions)
              ..where(
                (t) => t.ownerId.equals(ownerId) & t.state.equals('completed'),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.startedAtUtcMs)])
              ..limit(limit))
            .get();
    return rows.map(_rowToSummary).toList(growable: false);
  }

  @override
  Future<List<LearningSessionSummary>> listCompletedActivitySessionHistory({
    required String ownerId,
    required String activityType,
    required int limit,
  }) async {
    final canonicalOwnerId = _required(ownerId, 'ownerId');
    final canonicalActivityType = _required(activityType, 'activityType');
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final rows =
        await (database.select(database.learningSessions)
              ..where(
                (row) =>
                    row.ownerId.equals(canonicalOwnerId) &
                    row.activityType.equals(canonicalActivityType) &
                    row.state.equals('completed'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAtUtcMs)])
              ..limit(limit))
            .get();
    return rows.map(_rowToSummary).toList(growable: false);
  }

  LearningSessionSummary _rowToSummary(db.LearningSession row) {
    final configuration = _sessionConfiguration(row);
    if (row.configurationActiveEffortUs < 0) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.tampered,
      );
    }
    return LearningSessionSummary(
      id: row.id,
      ownerId: row.ownerId,
      activityType: row.activityType,
      state: row.state,
      startedAtUtc: _fromEpoch(row.startedAtUtcMs)!,
      endedAtUtc: _fromEpoch(row.endedAtUtcMs),
      correctCount: row.correctCount,
      wrongCount: row.wrongCount,
      score: row.score ?? 0,
      appVersion: row.appVersion,
      buildId: row.buildId,
      sessionConfiguration: configuration,
      configurationActiveEffort: Duration(
        microseconds: row.configurationActiveEffortUs,
      ),
    );
  }

  SessionConfiguration? _sessionConfiguration(db.LearningSession row) {
    final identity = row.sessionConfigurationIdentity;
    final serialization = row.sessionConfigurationJson;
    if (identity == null && serialization == null) return null;
    if (identity == null || serialization == null) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.tampered,
      );
    }
    final configuration = SessionConfiguration.fromStableSerialization(
      serialization,
    );
    if (configuration.contentIdentity != identity ||
        configuration.ownerId != row.ownerId) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.tampered,
      );
    }
    return configuration;
  }
}

QuizWord _quizWordFromRow(db.VocabularyWord row) => QuizWord(
  id: row.id,
  categoryId: row.categoryId,
  spelling: row.spelling,
  meaning: row.meaning,
  partOfSpeech: row.partOfSpeech,
  cefrLevel: row.cefrLevel,
  normalizedSpelling: row.normalizedSpelling,
  normalizedMeaning: row.normalizedMeaning,
  contentRevision: row.contentRevision,
  contentChecksumSha256: ContentQualityPolicy.effectiveVocabularyChecksumSha256(
    categoryId: row.categoryId,
    spelling: row.spelling,
    normalizedSpelling: row.normalizedSpelling,
    meaning: row.meaning,
    normalizedMeaning: row.normalizedMeaning,
    partOfSpeech: row.partOfSpeech,
    cefrLevel: row.cefrLevel,
    source: row.source,
    isGlobal: row.isGlobal,
    storedChecksumSha256: row.contentChecksumSha256,
  ),
);

bool _matchesReviewedLexicalSnapshot(
  db.VocabularyWord row,
  ReviewedLexicalContentSnapshot snapshot,
) =>
    snapshot.identity.id == row.id &&
    snapshot.identity.revision == row.contentRevision &&
    snapshot.categoryId == row.categoryId &&
    snapshot.spelling == row.spelling &&
    snapshot.normalizedSpelling == row.normalizedSpelling &&
    snapshot.meaning == row.meaning &&
    snapshot.normalizedMeaning == row.normalizedMeaning &&
    snapshot.partOfSpeech == row.partOfSpeech &&
    snapshot.cefrLevel == row.cefrLevel &&
    snapshot.source == row.source &&
    snapshot.isGlobal == row.isGlobal &&
    snapshot.coreChecksumSha256 == row.contentChecksumSha256 &&
    snapshot.provenance.name == row.contentProvenance &&
    snapshot.reviewState.name == row.contentReviewState &&
    snapshot.publicationState.name == row.contentPublicationState &&
    !row.isDeleted;

ReviewedLexicalArtifactSnapshot? _reviewedLexicalArtifactSnapshot(
  db.ContentManifestRow row,
) {
  if (row.contentType != ContentType.lexicalMetadata.name ||
      row.contentId.isEmpty ||
      row.contentId != row.contentId.trim() ||
      row.revision <= 0 ||
      !_reviewArtifactSha256.hasMatch(row.checksumSha256) ||
      row.byteLength <= 0 ||
      row.provenance != ContentProvenance.packaged.name ||
      row.sourceUri.isEmpty ||
      row.sourceUri != row.sourceUri.trim() ||
      row.reviewState != ContentReviewState.approved.name ||
      row.publicationState != ContentPublicationState.published.name ||
      row.createdAtUtcMs < 0 ||
      row.reviewedAtUtcMs == null ||
      row.reviewedAtUtcMs! < 0 ||
      row.publishedAtUtcMs == null ||
      row.publishedAtUtcMs! < 0) {
    return null;
  }
  return ReviewedLexicalArtifactSnapshot(
    storageId: row.id,
    identity: ContentIdentity(
      type: ContentType.lexicalMetadata,
      id: row.contentId,
      revision: row.revision,
    ),
    checksumSha256: row.checksumSha256,
    byteLength: row.byteLength,
  );
}

ReviewedLexicalContentSnapshot _reviewedLexicalContentSnapshot(
  db.VocabularyWord row,
  ReviewedLexicalArtifactSnapshot? artifact,
) => ReviewedLexicalContentSnapshot(
  identity: ContentIdentity(
    type: ContentType.lexicalMetadata,
    id: row.id,
    revision: row.contentRevision,
  ),
  categoryId: row.categoryId,
  spelling: row.spelling,
  normalizedSpelling: row.normalizedSpelling,
  meaning: row.meaning,
  normalizedMeaning: row.normalizedMeaning,
  partOfSpeech: row.partOfSpeech,
  cefrLevel: row.cefrLevel,
  source: row.source,
  isGlobal: row.isGlobal,
  coreChecksumSha256: row.contentChecksumSha256!,
  provenance: ContentProvenance.values.byName(row.contentProvenance),
  reviewState: ContentReviewState.values.byName(row.contentReviewState),
  publicationState: ContentPublicationState.values.byName(
    row.contentPublicationState,
  ),
  artifact: artifact,
);

final RegExp _reviewArtifactSha256 = RegExp(r'^[0-9a-f]{64}$');
