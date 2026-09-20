import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../data/local/app_database.dart';
import '../../ai_tutor/application/owner_operation_coordinator.dart';
import '../../ai_tutor/domain/ai_tutor_contracts.dart';
import '../../identity/application/owner_generation.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../learning_packs/domain/content_quality_policy.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../../vocabulary/data/packaged_starter_access.dart';
import '../data/drift_learning_repository.dart';
import '../domain/answer_feedback.dart';
import '../domain/contrastive_explanation.dart';
import '../domain/evidence_context.dart';
import '../domain/guided_repair.dart';
import '../domain/hint_policy.dart';
import '../domain/learning_models.dart';
import 'contrastive_feedback_use_cases.dart';

final class GuidedRepairTicket {
  const GuidedRepairTicket._(
    this.owner,
    this.feedback,
    this.state,
    this.revision,
    this.spelling,
    this.context,
    this.explanation,
  );
  final OwnerGenerationToken owner;
  final AnswerFeedback feedback;
  final GuidedRepairState state;
  final int revision;
  final String spelling;
  final String context;
  final ContrastiveExplanation? explanation;
}

/// Serial, owner-fenced supplemental practice. No scoring writer is called.
final class GuidedRepairUseCases {
  GuidedRepairUseCases({
    required this.learning,
    required this.manifests,
    required this.ownerGeneration,
    required this.ownerOperations,
    required this.nowUtc,
    required this.isAvailable,
  });
  final DriftLearningRepository learning;
  final ContentManifestRepository manifests;
  final OwnerGeneration ownerGeneration;
  final OwnerOperationCoordinator ownerOperations;
  final DateTime Function() nowUtc;
  final bool Function() isAvailable;
  AppDatabase get database => learning.database;

  Future<void> requireCurrent(OwnerGenerationToken owner) async {
    if (!isAvailable()) throw StateError('Guided repair is unavailable');
    await ownerGeneration.requireCurrentAsync(owner);
  }

  Future<T> _run<T>(
    OwnerGenerationToken owner,
    Future<T> Function() body,
  ) async {
    await requireCurrent(owner);
    return ownerOperations.run(AiCancellation(), (active) async {
      await requireCurrent(owner);
      if (active != owner.ownerId) throw StateError('Repair owner changed');
      return database.transaction(() async {
        await DriftOwnerOperationGate(database).requireOwned(
          token: ownerOperations.currentOperationVersion,
          nowUtc: nowUtc(),
        );
        await requireCurrent(owner);
        final result = await body();
        await requireCurrent(owner);
        return result;
      });
    });
  }

  Stream<bool> watchCurrent(OwnerGenerationToken owner) => database
      .customSelect(
        'SELECT id FROM local_owners WHERE is_active=1',
        readsFrom: {database.localOwners, database.runtimeFlags},
      )
      .watch()
      .asyncMap((rows) async {
        try {
          await requireCurrent(owner);
          return rows.length == 1 &&
              rows.single.read<String>('id') == owner.ownerId;
        } on Object {
          return false;
        }
      });

  Future<GuidedRepairTicket> open(AnswerFeedback feedback) async {
    final owner = await ownerGeneration.capture();
    return _run(owner, () => _load(owner, feedback));
  }

  Future<GuidedRepairTicket> resume(String originId) async {
    final owner = await ownerGeneration.capture();
    return _run(owner, () async {
      final rows =
          await (database.select(database.guidedRepairOperations)
                ..where(
                  (r) =>
                      r.ownerId.equals(owner.ownerId) &
                      r.originId.equals(originId),
                )
                ..orderBy([(r) => OrderingTerm.asc(r.revision)])
                ..limit(1))
              .get();
      if (rows.isEmpty) throw StateError('Repair history is unavailable');
      final pin = Map<String, Object?>.from(
        _payload(rows.single.payloadJson)['origin'] as Map,
      );
      return _load(owner, _feedbackFromPin(owner.ownerId, pin));
    });
  }

  Map<String, Object?> _origin(AnswerFeedback feedback) {
    final attempt = feedback.committedContrastiveAttempt;
    if (feedback.isCorrect || attempt == null || !attempt.isSelfConsistent) {
      throw StateError('A committed incorrect lexical answer is required');
    }
    // Ownership is a table key and can transfer during canonical guest upgrade.
    return Map<String, Object?>.from(
      jsonDecode(attempt.stableFingerprint) as Map,
    )..remove('ownerId');
  }

  Future<GuidedRepairTicket> _load(
    OwnerGenerationToken owner,
    AnswerFeedback feedback,
  ) async {
    final pin = _origin(feedback);
    final attempt = feedback.committedContrastiveAttempt!;
    if (attempt.ownerId != owner.ownerId) {
      throw StateError('Repair origin owner mismatch');
    }
    final row =
        await (database.select(database.answerAttempts)..where(
              (r) =>
                  r.ownerId.equals(owner.ownerId) &
                  r.id.equals(attempt.attemptIdentity),
            ))
            .getSingleOrNull();
    if (row == null ||
        row.isCorrect ||
        row.sessionId != attempt.sessionId ||
        row.wordId != attempt.wordId ||
        row.promptMode != attempt.promptMode ||
        await learning.events.readValidatedSourceForAttempt(attempt: row) ==
            null) {
      throw StateError('Repair origin is missing or unauthenticated');
    }
    final evidence = EvidenceContext.fromJson(
      Map<String, Object?>.from(jsonDecode(row.evidenceContextJson) as Map),
    );
    final frozen = ContrastiveFeedbackContext(
      manifestIdentity: attempt.manifestIdentity,
      manifestChecksumSha256: attempt.manifestChecksumSha256,
      promptMode: attempt.promptMode,
      evidenceContentRevision: attempt.evidenceContentRevision,
      correctOptionId: attempt.correctOptionId,
      selectedDistractorId: attempt.selectedDistractorId,
    ).freeze();
    if (evidence.contentRevision != attempt.evidenceContentRevision ||
        row.providerProvenance !=
            contrastiveFeedbackAttemptProvenance(frozen)) {
      throw StateError('Repair origin content changed');
    }
    final verified = await manifests.requireVerified(attempt.manifestIdentity);
    final manifest = verified.manifest;
    if (manifest.identity != attempt.manifestIdentity ||
        manifest.checksumSha256 != attempt.manifestChecksumSha256 ||
        manifest.provenance != ContentProvenance.packaged ||
        manifest.reviewState != ContentReviewState.approved ||
        manifest.publicationState != ContentPublicationState.published ||
        manifest.reviewedAtUtc == null ||
        manifest.publishedAtUtc == null) {
      throw StateError('Repair content is unavailable');
    }
    final word =
        await (database.select(database.vocabularyWords)..where(
              (w) =>
                  w.id.equals(row.wordId) &
                  w.isDeleted.equals(false) &
                  PackagedStarterAccess.wordsFor(database, owner.ownerId),
            ))
            .getSingleOrNull();
    if (word == null ||
        word.contentRevision != attempt.manifestIdentity.revision ||
        word.contentReviewState != 'approved' ||
        word.contentPublicationState != 'published' ||
        (!word.isGlobal && word.ownerId != owner.ownerId)) {
      throw StateError('Pinned repair word is unavailable');
    }
    final category =
        await (database.select(database.vocabularyCategories)..where(
              (c) =>
                  c.id.equals(word.categoryId) &
                  c.isDeleted.equals(false) &
                  PackagedStarterAccess.categoriesFor(database, owner.ownerId),
            ))
            .getSingleOrNull();
    if (category == null) {
      throw StateError('Pinned repair category is unavailable');
    }
    if (word.contentProvenance != 'packaged' ||
        word.contentChecksumSha256 !=
            ContentQualityPolicy.vocabularyChecksumSha256(
              categoryId: word.categoryId,
              spelling: word.spelling,
              normalizedSpelling: word.normalizedSpelling,
              meaning: word.meaning,
              normalizedMeaning: word.normalizedMeaning,
              partOfSpeech: word.partOfSpeech,
              cefrLevel: word.cefrLevel,
              source: word.source,
              isGlobal: word.isGlobal,
            )) {
      throw StateError('Pinned repair core is corrupt');
    }
    final metadata = RichLexicalMetadata.fromVerifiedArtifact(
      bytes: verified.bytes,
      wordId: row.wordId,
      contentRevision: manifest.identity.revision,
      verifiedArtifactChecksumSha256: manifest.checksumSha256,
    );
    var state = GuidedRepairState.start(
      originId: row.id,
      priorHintLevel: HintPolicy.applyToRepairEvidence(
        evidence,
        const HintUsageSnapshot.known(0),
      ).hintLevel,
    );
    var revision = 0;
    final operations =
        await (database.select(database.guidedRepairOperations)
              ..where(
                (r) =>
                    r.ownerId.equals(owner.ownerId) & r.originId.equals(row.id),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.revision)]))
            .get();
    for (final op in operations) {
      final payload = _payload(op.payloadJson);
      if (op.revision != revision + 1 ||
          jsonEncode(payload['origin']) != jsonEncode(pin) ||
          payload['expectedRevision'] != revision ||
          payload['operationId'] != op.operationId) {
        throw StateError('Repair history is inconsistent');
      }
      state = _reduce(
        state,
        payload['action'] as String,
        payload['answer'] as String,
        word.spelling,
        metadata.acceptedSpellingVariants,
      );
      if (jsonEncode(state.toJson()) != jsonEncode(payload['state'])) {
        throw StateError('Repair state is inconsistent');
      }
      revision = op.revision;
    }
    final explanation = await ContrastiveFeedbackUseCases(
      manifests: manifests,
    ).resolveForRepair(committedFeedback: feedback);
    return GuidedRepairTicket._(
      owner,
      feedback,
      state,
      revision,
      word.spelling,
      metadata.examples.isNotEmpty
          ? metadata.examples.first
          : metadata.englishDefinition ?? word.meaning,
      explanation,
    );
  }

  Map<String, Object?> _payload(String text) {
    final p = Map<String, Object?>.from(jsonDecode(text) as Map);
    if (p.length != 7 ||
        p['schemaVersion'] != 1 ||
        p['operationId'] is! String ||
        (p['operationId'] as String).trim().isEmpty ||
        (p['operationId'] as String).length > 256 ||
        p['origin'] is! Map ||
        p['expectedRevision'] is! int ||
        (p['expectedRevision'] as int) < 0 ||
        (p['expectedRevision'] as int) > 5 ||
        p['action'] is! String ||
        p['answer'] is! String ||
        (p['answer'] as String).length > 256 ||
        p['state'] is! Map) {
      throw const FormatException('Invalid repair operation');
    }
    GuidedRepairState.fromJson(Map<String, Object?>.from(p['state'] as Map));
    return p;
  }

  GuidedRepairState _reduce(
    GuidedRepairState state,
    String action,
    String answer,
    String spelling,
    List<String> variants,
  ) {
    if (action != 'answer' && answer.isNotEmpty) {
      throw StateError('Unexpected repair answer');
    }
    return switch (action) {
      'hint' => state.revealHint(),
      'exit' when !state.terminal => state.exit(),
      'answer' when answer.trim().isNotEmpty => state.answer(
        correct: [
          spelling,
          ...variants,
        ].any((v) => v.trim().toLowerCase() == answer.trim().toLowerCase()),
      ),
      _ => throw StateError('Invalid repair operation'),
    };
  }

  Future<GuidedRepairTicket> act(
    GuidedRepairTicket ticket, {
    required String operationId,
    required String action,
    String answer = '',
    bool Function()? mutationAllowed,
  }) {
    if (operationId.trim().isEmpty ||
        operationId.length > 256 ||
        answer.length > 256) {
      return Future.error(ArgumentError('Invalid repair input'));
    }
    return _run(ticket.owner, () async {
      if (mutationAllowed?.call() == false) {
        throw StateError('Repair route retired');
      }
      final current = await _load(ticket.owner, ticket.feedback);
      final request = <String, Object?>{
        'schemaVersion': 1,
        'operationId': operationId,
        'origin': _origin(ticket.feedback),
        'expectedRevision': ticket.revision,
        'action': action,
        'answer': answer,
      };
      final existing =
          await (database.select(database.guidedRepairOperations)..where(
                (r) =>
                    r.ownerId.equals(ticket.owner.ownerId) &
                    r.operationId.equals(operationId),
              ))
              .getSingleOrNull();
      if (existing != null) {
        final p = _payload(existing.payloadJson);
        final state = GuidedRepairState.fromJson(
          Map<String, Object?>.from(p.remove('state') as Map),
        );
        if (jsonEncode(p) != jsonEncode(request)) {
          throw StateError('Repair operation collision');
        }
        return GuidedRepairTicket._(
          ticket.owner,
          ticket.feedback,
          state,
          existing.revision,
          current.spelling,
          current.context,
          current.explanation,
        );
      }
      if (current.revision != ticket.revision) {
        throw StateError('Repair changed; reopen latest');
      }
      final a = ticket.feedback.committedContrastiveAttempt!;
      final verified = await manifests.requireVerified(a.manifestIdentity);
      final metadata = RichLexicalMetadata.fromVerifiedArtifact(
        bytes: verified.bytes,
        wordId: a.wordId,
        contentRevision: a.manifestIdentity.revision,
        verifiedArtifactChecksumSha256: a.manifestChecksumSha256,
      );
      final next = _reduce(
        current.state,
        action,
        answer,
        current.spelling,
        metadata.acceptedSpellingVariants,
      );
      if (mutationAllowed?.call() == false) {
        throw StateError('Repair route retired');
      }
      await requireCurrent(ticket.owner);
      await database
          .into(database.guidedRepairOperations)
          .insert(
            GuidedRepairOperationsCompanion.insert(
              ownerId: ticket.owner.ownerId,
              operationId: operationId,
              originId: current.state.originId,
              revision: current.revision + 1,
              payloadJson: jsonEncode({...request, 'state': next.toJson()}),
            ),
          );
      return GuidedRepairTicket._(
        ticket.owner,
        ticket.feedback,
        next,
        current.revision + 1,
        current.spelling,
        current.context,
        current.explanation,
      );
    });
  }

  Future<Map<String, Object?>> exportArchive(OwnerGenerationToken owner) =>
      _run(
        owner,
        () async => {
          'schemaVersion': 1,
          'databaseSchemaVersion': AppDatabase.currentSchemaVersion,
          'kind': 'guided-repair-history',
          'ownerId': owner.ownerId,
          'operations':
              (await (database.select(
                    database.guidedRepairOperations,
                  )..where((r) => r.ownerId.equals(owner.ownerId))).get())
                  .map((r) => _payload(r.payloadJson))
                  .toList(),
        },
      );

  Future<void> restoreArchive(
    OwnerGenerationToken owner,
    Map<String, Object?> envelope,
  ) {
    final copy = Map<String, Object?>.from(
      jsonDecode(jsonEncode(envelope)) as Map,
    );
    if (copy.length != 5 ||
        copy['schemaVersion'] != 1 ||
        copy['kind'] != 'guided-repair-history' ||
        copy['databaseSchemaVersion'] is! int ||
        (copy['databaseSchemaVersion'] as int) >
            AppDatabase.currentSchemaVersion ||
        (copy['databaseSchemaVersion'] as int) < 31 ||
        copy['operations'] is! List ||
        (copy['operations'] as List).length > 10000) {
      return Future.error(const FormatException('Unsupported repair archive'));
    }
    if (copy['ownerId'] != owner.ownerId) {
      return Future.error(StateError('Repair archive owner mismatch'));
    }
    return _run(owner, () async {
      final touched = <String, AnswerFeedback>{};
      for (final raw in copy['operations'] as List) {
        final p = _payload(jsonEncode(raw));
        final pin = Map<String, Object?>.from(p['origin'] as Map);
        final feedback = _feedbackFromPin(owner.ownerId, pin);
        final originId = feedback.committedContrastiveAttempt!.attemptIdentity;
        final id = p['operationId'] as String;
        final existing =
            await (database.select(database.guidedRepairOperations)..where(
                  (r) =>
                      r.ownerId.equals(owner.ownerId) &
                      r.operationId.equals(id),
                ))
                .getSingleOrNull();
        if (existing != null) {
          if (existing.payloadJson != jsonEncode(p)) {
            throw StateError('Repair restore collision');
          }
        } else {
          await database
              .into(database.guidedRepairOperations)
              .insert(
                GuidedRepairOperationsCompanion.insert(
                  ownerId: owner.ownerId,
                  operationId: id,
                  originId: originId,
                  revision: (p['expectedRevision'] as int) + 1,
                  payloadJson: jsonEncode(p),
                ),
              );
        }
        touched[originId] = feedback;
      }
      // Validate complete contiguous histories and original source before commit.
      for (final feedback in touched.values) {
        await _load(owner, feedback);
      }
    });
  }

  AnswerFeedback _feedbackFromPin(String ownerId, Map<String, Object?> p) =>
      AnswerFeedback.fromCommittedResult(
        result: AnswerRecordResult(
          inserted: false,
          isCorrect: false,
          srs: null,
          committedContrastiveAttempt: CommittedContrastiveAttempt(
            attemptIdentity: p['attemptIdentity'] as String,
            ownerId: ownerId,
            sessionId: p['sessionId'] as String,
            wordId: p['wordId'] as String,
            promptMode: p['promptMode'] as String,
            evidenceContentRevision: p['evidenceContentRevision'] as String,
            manifestIdentity: ContentIdentity(
              type: ContentType.lexicalMetadata,
              id: p['contentId'] as String,
              revision: p['contentRevision'] as int,
            ),
            manifestChecksumSha256: p['manifestChecksumSha256'] as String,
            correctOptionId: p['correctOptionId'] as String,
            selectedDistractorId: p['selectedDistractorId'] as String,
          ),
        ),
        context: const AnswerFeedbackContext(
          canonicalCorrectAnswer: 'Pinned repair',
        ),
      );
}
