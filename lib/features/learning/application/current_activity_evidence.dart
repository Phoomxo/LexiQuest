import 'dart:convert';
import '../../events/domain/event_envelope_v2.dart';
import '../../../product/feature_contract/feature_contract_digest.dart';
import '../domain/evidence_context.dart';
import '../domain/contrastive_explanation.dart';
import '../domain/evidence_policy_rollout.dart';
import '../domain/hint_policy.dart';
import '../domain/learning_evidence_contract.dart';
import '../domain/learning_event_context.dart';
import '../domain/learning_models.dart';
import '../domain/lexical_prompt_artifact_identity.dart';
import 'learning_use_cases.dart';
import '../pair_matching/domain/pair_matching_plan.dart';
import '../pair_matching/domain/pair_matching_launch.dart';

enum CurrentActivityInput {
  meaningMultipleChoice,
  meaningToWordMultipleChoice,
  definitionMultipleChoice,
  clozeSelected,
  clozeTyped,
  matchingPair,
  srsRecall,
  typedRecall,
  associativeRecall,
  ghostDuel,
  speakToText,
  shadowing,
  readingExposure,
  dictation,
  sentenceScramble,
  wordScramble,
}

HintEvidenceClassification classifyCurrentActivityEvidence(
  CurrentActivityInput input, {
  required int hintLevel,
}) {
  final declaration = _declarationFor(input);
  if ((input == CurrentActivityInput.definitionMultipleChoice ||
          input == CurrentActivityInput.clozeSelected ||
          input == CurrentActivityInput.matchingPair) &&
      hintLevel != 0) {
    return HintEvidenceClassification(
      evidenceClass: EvidenceClass.guidedPractice,
      hintLevel: hintLevel < 0 ? 2 : hintLevel,
    );
  }
  return HintPolicy.classifyEvidence(
    declaredClass: declaration.evidenceClass,
    hint: HintUsageSnapshot.fromRecordedLevel(hintLevel),
  );
}

/// One immutable, read-only research-state snapshot for an occurrence.
final class CurrentActivityResearchSnapshot {
  const CurrentActivityResearchSnapshot({
    required this.engagementAllowed,
    required this.consentContext,
    required this.experimentContext,
    required this.protocolId,
    required this.protocolVersion,
    required this.experimentVersion,
    required this.assignmentId,
    this.protocolEvidenceClassOverride,
  });

  const CurrentActivityResearchSnapshot.legacyCompatibility()
    : engagementAllowed = true,
      consentContext = const ConsentContext.none(),
      experimentContext = null,
      protocolId = null,
      protocolVersion = null,
      experimentVersion = null,
      assignmentId = null,
      protocolEvidenceClassOverride = null;

  final bool engagementAllowed;
  final ConsentContext consentContext;
  final ExperimentContext? experimentContext;
  final String? protocolId;
  final String? protocolVersion;
  final int? experimentVersion;
  final String? assignmentId;
  final EvidenceClass? protocolEvidenceClassOverride;

  bool get hasCompleteResearchProtocol =>
      consentContext.researchConsentVersion > 0 &&
      experimentContext != null &&
      protocolId != null &&
      protocolVersion != null &&
      experimentVersion != null &&
      assignmentId != null;

  LearningEventContext eventContextFor(EvidenceContext evidenceContext) {
    if (evidenceContext.rolloutMode == EvidencePolicyRolloutMode.legacy) {
      return LearningEventContext.noResearch(evidenceContext);
    }
    return LearningEventContext(
      consentContext: consentContext,
      experimentContext: experimentContext,
      protocolId: protocolId,
      protocolVersion: protocolVersion,
      experimentVersion: experimentVersion,
      assignmentId: assignmentId,
      featureContractIdentity: FeatureContractIdentity(
        revision: evidenceContext.featureContractRevision,
        semanticHash: evidenceContext.featureContractHash,
      ),
    );
  }
}

/// Canonical read-only research state used by activity classification and by
/// all other learning-event recording paths.
abstract interface class CurrentActivityResearchStateProvider
    implements LearningEventContextProvider {
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required String ownerId,
    required CurrentActivityInput input,
    required DateTime occurredAtUtc,
    required EvidencePolicyRolloutMode rolloutMode,
  });
}

/// One baseline object serves both interfaces in safe Legacy composition.
final class BaselineCurrentActivityResearchStateProvider
    implements CurrentActivityResearchStateProvider {
  const BaselineCurrentActivityResearchStateProvider();

  @override
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required String ownerId,
    required CurrentActivityInput input,
    required DateTime occurredAtUtc,
    required EvidencePolicyRolloutMode rolloutMode,
  }) async {
    if (ownerId.trim() != ownerId || ownerId.isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'invalid identifier');
    }
    if (!occurredAtUtc.isUtc) {
      throw ArgumentError.value(occurredAtUtc, 'occurredAtUtc', 'must be UTC');
    }
    if (rolloutMode != EvidencePolicyRolloutMode.legacy) {
      throw StateError('persisted research state is unavailable');
    }
    return const CurrentActivityResearchSnapshot.legacyCompatibility();
  }

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) {
    return const BaselineLearningEventContextProvider().resolve(
      ownerId: ownerId,
      evidenceContext: evidenceContext,
      occurredAtUtc: occurredAtUtc,
    );
  }
}

/// A complete pending-answer snapshot that can cross a process boundary
/// without consulting mutable owner, rollout, or research state again.
final class FrozenPendingCurrentActivityEvidence {
  factory FrozenPendingCurrentActivityEvidence.fromJson(
    Map<String, Object?> json,
  ) {
    if (json.length != _jsonKeys.length ||
        !json.keys.every(_jsonKeys.contains) ||
        json['schemaVersion'] is! int ||
        json['schemaVersion'] != currentSchemaVersion) {
      throw const FormatException('invalid frozen pending evidence schema');
    }
    try {
      final declaration = _requiredJsonMap(json, 'declaration');
      if (declaration.length != _declarationKeys.length ||
          !declaration.keys.every(_declarationKeys.contains)) {
        throw const FormatException(
          'invalid frozen pending evidence declaration',
        );
      }
      final occurredAtEncoded = _requiredString(json, 'occurredAtUtc');
      final occurredAtUtc = occurredAtEncoded.endsWith('Z')
          ? DateTime.tryParse(occurredAtEncoded)
          : null;
      if (occurredAtUtc == null ||
          !occurredAtUtc.isUtc ||
          occurredAtUtc.toIso8601String() != occurredAtEncoded) {
        throw const FormatException(
          'invalid frozen pending evidence occurrence',
        );
      }
      final contrastiveJson = json['contrastiveFeedback'];
      final contrastiveFeedback = contrastiveJson == null
          ? null
          : FrozenContrastiveFeedbackContext.fromJson(
              _requiredJsonMap(json, 'contrastiveFeedback'),
            );
      return FrozenPendingCurrentActivityEvidence._validated(
        ownerId: _requiredString(json, 'ownerId'),
        sourceEvidenceId: _requiredString(json, 'sourceEvidenceId'),
        occurredAtUtc: occurredAtUtc,
        sessionId: _requiredString(json, 'sessionId'),
        wordId: _requiredString(json, 'wordId'),
        promptMode: _requiredString(json, 'promptMode'),
        isCorrect: _requiredBool(json, 'isCorrect'),
        responseTimeMs: _optionalInt(json, 'responseTimeMs'),
        attemptNumber: _requiredInt(json, 'attemptNumber'),
        providerProvenance: _optionalString(json, 'providerProvenance'),
        actorIdentity: _requiredString(json, 'actorIdentity'),
        input: _requiredEnum(json, 'input', CurrentActivityInput.values),
        declaredEvidenceClass: _requiredEnum(
          declaration,
          'evidenceClass',
          EvidenceClass.values,
        ),
        skillId: _requiredString(declaration, 'skillId'),
        declarationPromptMode: _requiredString(declaration, 'promptMode'),
        contentRevision: _requiredString(declaration, 'contentRevision'),
        hintLevel: _requiredInt(json, 'hintLevel'),
        contrastiveFeedback: contrastiveFeedback,
        evidenceContext: EvidenceContext.fromJson(
          _requiredJsonMap(json, 'evidenceContext'),
        ),
        eventContext: LearningEventContext.fromJson(
          _requiredJsonMap(json, 'eventContext'),
        ),
      );
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('invalid frozen pending evidence: $error');
    }
  }

  factory FrozenPendingCurrentActivityEvidence._validated({
    required String ownerId,
    required String sourceEvidenceId,
    required DateTime occurredAtUtc,
    required String sessionId,
    required String wordId,
    required String promptMode,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    required String? providerProvenance,
    required String actorIdentity,
    required CurrentActivityInput input,
    required EvidenceClass declaredEvidenceClass,
    required String skillId,
    required String declarationPromptMode,
    required String contentRevision,
    required int hintLevel,
    required FrozenContrastiveFeedbackContext? contrastiveFeedback,
    required EvidenceContext evidenceContext,
    required LearningEventContext eventContext,
  }) {
    _requireCanonicalIdentifier(ownerId, 'ownerId');
    if (!LearningEvidenceContract.validSourceEvidenceId(sourceEvidenceId)) {
      throw const FormatException('invalid frozen source evidence identity');
    }
    if (!occurredAtUtc.isUtc || occurredAtUtc.millisecondsSinceEpoch < 0) {
      throw const FormatException('invalid frozen pending evidence occurrence');
    }
    _requireCanonicalIdentifier(sessionId, 'sessionId');
    _requireCanonicalIdentifier(wordId, 'wordId');
    _requirePromptMode(promptMode, 'promptMode');
    _requireCanonicalIdentifier(actorIdentity, 'actorIdentity');
    _requireCanonicalIdentifier(skillId, 'skillId');
    _requirePromptMode(declarationPromptMode, 'declaration.promptMode');
    _requireCanonicalIdentifier(contentRevision, 'contentRevision');
    if (promptMode != declarationPromptMode ||
        responseTimeMs != null &&
            (responseTimeMs < 0 ||
                responseTimeMs > LearningEvidenceContract.maxResponseTimeMs) ||
        attemptNumber <= 0 ||
        attemptNumber > LearningEvidenceContract.maxAttemptNumber ||
        hintLevel < 0 ||
        providerProvenance != null &&
            providerProvenance.runes.length >
                LearningEvidenceContract.maxProviderProvenanceLength) {
      throw const FormatException('invalid frozen pending evidence values');
    }
    _validateDeclaration(
      input: input,
      evidenceClass: declaredEvidenceClass,
      skillId: skillId,
      promptMode: declarationPromptMode,
    );
    try {
      evidenceContext.validate();
      eventContext.validateAgainst(
        evidenceContext: evidenceContext,
        occurredAtUtc: occurredAtUtc,
      );
    } on Object catch (error) {
      throw FormatException('invalid frozen pending contexts: $error');
    }
    if (evidenceContext.skillId != skillId ||
        evidenceContext.hintLevel != hintLevel ||
        evidenceContext.contentRevision != contentRevision) {
      throw const FormatException(
        'frozen pending declaration conflicts with resolved evidence',
      );
    }
    final classified = HintPolicy.classifyEvidence(
      declaredClass: declaredEvidenceClass,
      hint: HintUsageSnapshot.fromRecordedLevel(hintLevel),
    );
    final validProtocolOverride =
        input == CurrentActivityInput.ghostDuel &&
        evidenceContext.rolloutMode != EvidencePolicyRolloutMode.legacy;
    if (evidenceContext.evidenceClass != classified.evidenceClass &&
        !validProtocolOverride) {
      throw const FormatException(
        'frozen pending class conflicts with its declaration',
      );
    }
    if (contrastiveFeedback != null) {
      if (isCorrect ||
          contrastiveFeedback.manifestIdentity.id != wordId ||
          contrastiveFeedback.promptMode != promptMode ||
          contrastiveFeedback.evidenceContentRevision != contentRevision ||
          providerProvenance !=
              contrastiveFeedbackAttemptProvenance(contrastiveFeedback)) {
        throw const FormatException(
          'frozen pending contrastive evidence is inconsistent',
        );
      }
    } else if (isContrastiveFeedbackAttemptProvenance(providerProvenance)) {
      throw const FormatException(
        'frozen pending contrastive provenance has no context',
      );
    }
    return FrozenPendingCurrentActivityEvidence._(
      ownerId: ownerId,
      sourceEvidenceId: sourceEvidenceId,
      occurredAtUtc: occurredAtUtc,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: promptMode,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance: providerProvenance,
      actorIdentity: actorIdentity,
      input: input,
      declaredEvidenceClass: declaredEvidenceClass,
      skillId: skillId,
      contentRevision: contentRevision,
      hintLevel: hintLevel,
      contrastiveFeedback: contrastiveFeedback,
      evidenceContext: evidenceContext,
      eventContext: eventContext,
    );
  }

  const FrozenPendingCurrentActivityEvidence._({
    required this.ownerId,
    required this.sourceEvidenceId,
    required this.occurredAtUtc,
    required this.sessionId,
    required this.wordId,
    required this.promptMode,
    required this.isCorrect,
    required this.responseTimeMs,
    required this.attemptNumber,
    required this.providerProvenance,
    required this.actorIdentity,
    required this.input,
    required this.declaredEvidenceClass,
    required this.skillId,
    required this.contentRevision,
    required this.hintLevel,
    required this.contrastiveFeedback,
    required this.evidenceContext,
    required this.eventContext,
  });

  static const int currentSchemaVersion = 1;
  static const Set<String> _jsonKeys = <String>{
    'schemaVersion',
    'ownerId',
    'sourceEvidenceId',
    'occurredAtUtc',
    'sessionId',
    'wordId',
    'promptMode',
    'isCorrect',
    'responseTimeMs',
    'attemptNumber',
    'providerProvenance',
    'actorIdentity',
    'input',
    'declaration',
    'hintLevel',
    'contrastiveFeedback',
    'evidenceContext',
    'eventContext',
  };
  static const Set<String> _declarationKeys = <String>{
    'evidenceClass',
    'skillId',
    'promptMode',
    'contentRevision',
  };

  int get schemaVersion => currentSchemaVersion;
  final String ownerId;
  final String sourceEvidenceId;
  final DateTime occurredAtUtc;
  final String sessionId;
  final String wordId;
  final String promptMode;
  final bool isCorrect;
  final int? responseTimeMs;
  final int attemptNumber;
  final String? providerProvenance;
  final String actorIdentity;
  final CurrentActivityInput input;
  final EvidenceClass declaredEvidenceClass;
  final String skillId;
  final String contentRevision;
  final int hintLevel;
  final FrozenContrastiveFeedbackContext? contrastiveFeedback;
  final EvidenceContext evidenceContext;
  final LearningEventContext eventContext;

  void requirePracticeReplayContext() {
    final expected = EvidenceContext.forNewEvidence(
      evidenceClass: EvidenceClass.recreational,
      skillId: 'matching-recognition',
      hintLevel: 0,
      contentRevision: contentRevision,
      rolloutMode: EvidencePolicyRolloutMode.legacy,
      engagementAllowed: false,
    );
    if (jsonEncode(evidenceContext.toJson()) != jsonEncode(expected.toJson()) ||
        jsonEncode(eventContext.toJson()) !=
            jsonEncode(LearningEventContext.noResearch(expected).toJson())) {
      throw StateError(
        'Pair replay requires exact recreational no-research context',
      );
    }
  }

  Map<String, Object?> toJson() => _deepFreezeJsonMap(<String, Object?>{
    'schemaVersion': currentSchemaVersion,
    'ownerId': ownerId,
    'sourceEvidenceId': sourceEvidenceId,
    'occurredAtUtc': occurredAtUtc.toIso8601String(),
    'sessionId': sessionId,
    'wordId': wordId,
    'promptMode': promptMode,
    'isCorrect': isCorrect,
    'responseTimeMs': responseTimeMs,
    'attemptNumber': attemptNumber,
    'providerProvenance': providerProvenance,
    'actorIdentity': actorIdentity,
    'input': input.name,
    'declaration': <String, Object?>{
      'evidenceClass': declaredEvidenceClass.name,
      'skillId': skillId,
      'promptMode': promptMode,
      'contentRevision': contentRevision,
    },
    'hintLevel': hintLevel,
    'contrastiveFeedback': contrastiveFeedback?.toJson(),
    'evidenceContext': evidenceContext.toJson(),
    'eventContext': eventContext.toJson(),
  });

  static Map<String, Object?> _requiredJsonMap(
    Map<String, Object?> json,
    String field,
  ) {
    final value = json[field];
    if (value is! Map) {
      throw FormatException('invalid frozen pending evidence $field');
    }
    try {
      return value.cast<String, Object?>();
    } on Object {
      throw FormatException('invalid frozen pending evidence $field');
    }
  }

  static String _requiredString(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! String) {
      throw FormatException('invalid frozen pending evidence $field');
    }
    return value;
  }

  static String? _optionalString(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value != null && value is! String) {
      throw FormatException('invalid frozen pending evidence $field');
    }
    return value as String?;
  }

  static int _requiredInt(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! int) {
      throw FormatException('invalid frozen pending evidence $field');
    }
    return value;
  }

  static int? _optionalInt(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value != null && value is! int) {
      throw FormatException('invalid frozen pending evidence $field');
    }
    return value as int?;
  }

  static bool _requiredBool(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! bool) {
      throw FormatException('invalid frozen pending evidence $field');
    }
    return value;
  }

  static T _requiredEnum<T extends Enum>(
    Map<String, Object?> json,
    String field,
    List<T> values,
  ) {
    final encoded = _requiredString(json, field);
    for (final value in values) {
      if (value.name == encoded) return value;
    }
    throw FormatException('invalid frozen pending evidence $field');
  }

  static void _requireCanonicalIdentifier(String value, String field) {
    if (value != value.trim() ||
        !LearningEvidenceContract.validIdentifier(value)) {
      throw FormatException('invalid frozen pending evidence $field');
    }
  }

  static void _requirePromptMode(String value, String field) {
    if (value != value.trim() ||
        !LearningEvidenceContract.validText(
          value,
          maxLength: LearningEvidenceContract.maxPromptModeLength,
        )) {
      throw FormatException('invalid frozen pending evidence $field');
    }
  }

  static void _validateDeclaration({
    required CurrentActivityInput input,
    required EvidenceClass evidenceClass,
    required String skillId,
    required String promptMode,
  }) {
    bool oneOf(Set<EvidenceClass> values) => values.contains(evidenceClass);
    final valid = switch (input) {
      CurrentActivityInput.meaningMultipleChoice =>
        skillId == 'meaning-recall' &&
            promptMode == 'meaningChoice' &&
            oneOf(const <EvidenceClass>{
              EvidenceClass.recognition,
              EvidenceClass.guidedPractice,
            }),
      CurrentActivityInput.meaningToWordMultipleChoice =>
        skillId == 'meaning-recall' &&
            promptMode == 'wordChoice' &&
            evidenceClass == EvidenceClass.recognition,
      CurrentActivityInput.definitionMultipleChoice =>
        skillId == 'definition-recognition' &&
            promptMode == 'definitionChoice' &&
            oneOf(const <EvidenceClass>{
              EvidenceClass.recognition,
              EvidenceClass.guidedPractice,
            }),
      CurrentActivityInput.clozeSelected =>
        skillId == 'cloze-context' &&
            promptMode == 'clozeSelected' &&
            oneOf(const <EvidenceClass>{
              EvidenceClass.recognition,
              EvidenceClass.guidedPractice,
            }),
      CurrentActivityInput.clozeTyped =>
        skillId == 'cloze-context' &&
            promptMode == 'clozeTyped' &&
            oneOf(const <EvidenceClass>{
              EvidenceClass.independentRecall,
              EvidenceClass.guidedPractice,
            }),
      CurrentActivityInput.matchingPair =>
        skillId == 'matching-recognition' &&
            promptMode == 'matchingPair' &&
            oneOf(const <EvidenceClass>{
              EvidenceClass.recognition,
              EvidenceClass.guidedPractice,
              EvidenceClass.recreational,
            }),
      CurrentActivityInput.srsRecall =>
        skillId == 'srs-recall' &&
            ((promptMode == 'srsRecall' &&
                    evidenceClass == EvidenceClass.independentRecall) ||
                (promptMode == 'flashcardExposure' &&
                    evidenceClass == EvidenceClass.exposure)),
      CurrentActivityInput.typedRecall =>
        skillId == 'typed-recall' &&
            promptMode == 'typedRecall' &&
            oneOf(const <EvidenceClass>{
              EvidenceClass.independentRecall,
              EvidenceClass.guidedPractice,
            }),
      CurrentActivityInput.associativeRecall =>
        skillId == 'associative-recall' &&
            promptMode == 'associativeRecall' &&
            oneOf(const <EvidenceClass>{
              EvidenceClass.independentRecall,
              EvidenceClass.guidedPractice,
            }),
      CurrentActivityInput.ghostDuel =>
        skillId == 'ghost-duel' &&
            promptMode == 'ghostSpelling' &&
            evidenceClass == EvidenceClass.recreational,
      CurrentActivityInput.speakToText =>
        skillId == 'pronunciation-transcript' &&
            promptMode == 'pronunciationTranscript' &&
            evidenceClass == EvidenceClass.pronunciation,
      CurrentActivityInput.shadowing =>
        skillId == 'shadowing-pronunciation' &&
            promptMode == 'shadowing' &&
            evidenceClass == EvidenceClass.pronunciation,
      CurrentActivityInput.readingExposure =>
        skillId == 'reading-exposure' &&
            promptMode == 'readingExposure' &&
            evidenceClass == EvidenceClass.exposure,
      CurrentActivityInput.dictation =>
        skillId == 'dictation-spelling' &&
            promptMode == 'dictation' &&
            evidenceClass == EvidenceClass.independentRecall,
      CurrentActivityInput.sentenceScramble =>
        skillId == 'sentence-scramble' &&
            promptMode == 'sentenceScramble' &&
            evidenceClass == EvidenceClass.recreational,
      CurrentActivityInput.wordScramble =>
        skillId == 'word-scramble' &&
            promptMode == 'wordScramble' &&
            evidenceClass == EvidenceClass.recreational,
    };
    if (!valid) {
      throw const FormatException('invalid frozen pending declaration');
    }
  }
}

Map<String, Object?> _deepFreezeJsonMap(Map<String, Object?> source) =>
    Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in source.entries)
        entry.key: _deepFreezeJsonValue(entry.value),
    });

Object? _deepFreezeJsonValue(Object? value) {
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException('frozen pending JSON keys must be strings');
      }
      result[key] = _deepFreezeJsonValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_deepFreezeJsonValue));
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw FormatException(
    'unsupported frozen pending JSON value ${value.runtimeType}',
  );
}

final class CurrentActivityEvidenceAdapter {
  CurrentActivityEvidenceAdapter({
    required this.learning,
    this.rolloutModeProvider =
        const FixedEvidencePolicyRolloutModeProvider.legacy(),
    this.researchStateProvider =
        const BaselineCurrentActivityResearchStateProvider(),
    LearningIdGenerator? generateId,
    LearningUtcNow? nowUtc,
  }) : generateId = generateId ?? learning.generateId,
       nowUtc = nowUtc ?? learning.nowUtc;

  final LearningUseCases learning;
  final LearningIdGenerator generateId;
  final LearningUtcNow nowUtc;
  final EvidencePolicyRolloutModeProvider rolloutModeProvider;
  final CurrentActivityResearchStateProvider researchStateProvider;

  /// Captures occurrence identity and every response semantic synchronously.
  PendingCurrentActivityEvidence capture({
    String? ownerId,
    required CurrentActivityInput input,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    String? providerProvenance,
    int hintLevel = 0,
  }) {
    if (input == CurrentActivityInput.definitionMultipleChoice ||
        input == CurrentActivityInput.clozeSelected ||
        input == CurrentActivityInput.clozeTyped ||
        input == CurrentActivityInput.matchingPair) {
      throw StateError(
        'This activity requires its typed mode capture contract.',
      );
    }
    final declaration = _declarationFor(input);
    return _capture(
      ownerId: ownerId,
      input: input,
      declaration: declaration,
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance: providerProvenance,
      hintLevel: hintLevel,
    );
  }

  /// Captures meaning recognition against an exact verified lexical revision.
  PendingCurrentActivityEvidence capturePinnedMeaningRecognition({
    String? ownerId,
    required CurrentActivityInput input,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required int contentRevision,
    required String checksumSha256,
    HintEvidenceClassification classification =
        const HintEvidenceClassification(
          evidenceClass: EvidenceClass.recognition,
          hintLevel: 0,
        ),
    ContrastiveFeedbackContext? contrastiveFeedback,
  }) {
    if (input != CurrentActivityInput.meaningMultipleChoice &&
        input != CurrentActivityInput.meaningToWordMultipleChoice) {
      throw ArgumentError.value(input, 'input', 'must be a meaning choice');
    }
    if (contentRevision <= 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksumSha256)) {
      throw ArgumentError('Pinned meaning content identity is invalid.');
    }
    final guidedMeaningChoice =
        input == CurrentActivityInput.meaningMultipleChoice &&
        classification.evidenceClass == EvidenceClass.guidedPractice &&
        classification.hintLevel > 0 &&
        classification.hintLevel <= 2;
    final unassistedRecognition =
        classification.evidenceClass == EvidenceClass.recognition &&
        classification.hintLevel == 0;
    if (!unassistedRecognition && !guidedMeaningChoice) {
      throw ArgumentError.value(
        classification,
        'classification',
        'must be unhinted recognition or guided meaning choice',
      );
    }
    final declaration = _declarationFor(input);
    return _capture(
      ownerId: ownerId,
      input: input,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: classification.evidenceClass,
        skillId: declaration.skillId,
        promptMode: declaration.promptMode,
        contentRevision: contrastiveEvidenceContentRevision(
          promptMode: declaration.promptMode,
          wordId: wordId,
          revision: contentRevision,
          checksumSha256: checksumSha256,
        ),
      ),
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance:
          'reviewed-lexical-meaning:$contentRevision:$checksumSha256',
      hintLevel: classification.hintLevel,
      contrastiveFeedback: contrastiveFeedback,
    );
  }

  /// Captures a reviewed, version-pinned definition-recognition occurrence.
  /// The hint snapshot is resolved by the shell-owned f19 authority before
  /// this immutable pending command is created.
  PendingCurrentActivityEvidence captureDefinitionRecognition({
    String? ownerId,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required int contentRevision,
    required String checksumSha256,
    required HintEvidenceClassification classification,
    ContrastiveFeedbackContext? contrastiveFeedback,
  }) {
    if (contentRevision <= 0) {
      throw ArgumentError.value(
        contentRevision,
        'contentRevision',
        'must be positive',
      );
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksumSha256)) {
      throw ArgumentError.value(
        checksumSha256,
        'checksumSha256',
        'must be lowercase SHA-256',
      );
    }
    final hintLevel = classification.hintLevel;
    final evidenceClass = classification.evidenceClass;
    if ((hintLevel == 0 && evidenceClass != EvidenceClass.recognition) ||
        (hintLevel > 0 && evidenceClass != EvidenceClass.guidedPractice) ||
        hintLevel < 0) {
      throw ArgumentError.value(
        classification,
        'classification',
        'must be unhinted recognition or hinted guided practice',
      );
    }
    return _capture(
      ownerId: ownerId,
      input: CurrentActivityInput.definitionMultipleChoice,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: evidenceClass,
        skillId: 'definition-recognition',
        promptMode: 'definitionChoice',
        contentRevision:
            LexicalPromptArtifactResolver.formatEvidenceContentRevision(
              promptMode: 'definitionChoice',
              wordId: wordId,
              revision: contentRevision,
              checksumSha256: checksumSha256,
            ),
      ),
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance:
          'reviewed-lexical-definition:$contentRevision:$checksumSha256',
      hintLevel: hintLevel,
      contrastiveFeedback: contrastiveFeedback,
    );
  }

  /// Captures the recognition leg hosted by the explicit typed-recall route.
  /// The legacy f07 quiz remains unassisted recognition; this ingress accepts
  /// only the shell-owned support classification frozen by the typed adapter.
  PendingCurrentActivityEvidence captureSupportedMeaningRecognition({
    String? ownerId,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required HintEvidenceClassification classification,
  }) {
    final validUnassisted =
        classification.hintLevel == 0 &&
        classification.evidenceClass == EvidenceClass.recognition;
    final validAssisted =
        classification.hintLevel > 0 &&
        classification.hintLevel <= 2 &&
        classification.evidenceClass == EvidenceClass.guidedPractice;
    if ((!validUnassisted && !validAssisted) || responseTimeMs < 0) {
      throw ArgumentError.value(
        classification,
        'classification',
        'must be unhinted recognition or hinted guided practice',
      );
    }
    return _capture(
      ownerId: ownerId,
      input: CurrentActivityInput.meaningMultipleChoice,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: classification.evidenceClass,
        skillId: 'meaning-recall',
        promptMode: 'meaningChoice',
      ),
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance: null,
      hintLevel: classification.hintLevel,
    );
  }

  /// Captures one reviewed, revision-pinned cloze occurrence. The adapter
  /// owns response scoring and assistance classification; this gateway owns
  /// the sole canonical evidence write.
  PendingCurrentActivityEvidence captureCloze({
    String? ownerId,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required int contentRevision,
    required String checksumSha256,
    required bool typed,
    required HintEvidenceClassification classification,
    ContrastiveFeedbackContext? contrastiveFeedback,
  }) {
    if (contentRevision <= 0) {
      throw ArgumentError.value(
        contentRevision,
        'contentRevision',
        'must be positive',
      );
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksumSha256)) {
      throw ArgumentError.value(
        checksumSha256,
        'checksumSha256',
        'must be lowercase SHA-256',
      );
    }
    final expectedUnassisted = typed
        ? EvidenceClass.independentRecall
        : EvidenceClass.recognition;
    final validUnassisted =
        classification.hintLevel == 0 &&
        classification.evidenceClass == expectedUnassisted;
    final validAssisted =
        classification.hintLevel > 0 &&
        classification.evidenceClass == EvidenceClass.guidedPractice;
    if ((!validUnassisted && !validAssisted) || classification.hintLevel < 0) {
      throw ArgumentError.value(
        classification,
        'classification',
        'must match the cloze input and assistance snapshot',
      );
    }
    return _capture(
      ownerId: ownerId,
      input: typed
          ? CurrentActivityInput.clozeTyped
          : CurrentActivityInput.clozeSelected,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: classification.evidenceClass,
        skillId: 'cloze-context',
        promptMode: typed ? 'clozeTyped' : 'clozeSelected',
        contentRevision:
            LexicalPromptArtifactResolver.formatEvidenceContentRevision(
              promptMode: typed ? 'clozeTyped' : 'clozeSelected',
              wordId: wordId,
              revision: contentRevision,
              checksumSha256: checksumSha256,
            ),
      ),
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance:
          'reviewed-lexical-example:$contentRevision:$checksumSha256',
      hintLevel: classification.hintLevel,
      contrastiveFeedback: contrastiveFeedback,
    );
  }

  /// Captures one version-pinned productive spelling response. Correctness
  /// and assistance classification are owned by the typed-recall adapter;
  /// this gateway only freezes the resulting controlled evidence command.
  PendingCurrentActivityEvidence captureTypedRecall({
    String? ownerId,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    required int contentRevision,
    required String checksumSha256,
    required bool contextual,
    required String providerProvenance,
    required HintEvidenceClassification classification,
  }) {
    if (contentRevision <= 0) {
      throw ArgumentError.value(
        contentRevision,
        'contentRevision',
        'must be positive',
      );
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksumSha256)) {
      throw ArgumentError.value(
        checksumSha256,
        'checksumSha256',
        'must be lowercase SHA-256',
      );
    }
    final validUnassisted =
        classification.hintLevel == 0 &&
        classification.evidenceClass == EvidenceClass.independentRecall;
    final validAssisted =
        classification.hintLevel > 0 &&
        classification.evidenceClass == EvidenceClass.guidedPractice;
    if ((!validUnassisted && !validAssisted) ||
        classification.hintLevel < 0 ||
        providerProvenance.isEmpty ||
        providerProvenance.length > 96) {
      throw ArgumentError.value(
        classification,
        'classification',
        'must be unassisted recall or assisted guided practice',
      );
    }
    final input = contextual
        ? CurrentActivityInput.associativeRecall
        : CurrentActivityInput.typedRecall;
    return _capture(
      ownerId: ownerId,
      input: input,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: classification.evidenceClass,
        skillId: contextual ? 'associative-recall' : 'typed-recall',
        promptMode: contextual ? 'associativeRecall' : 'typedRecall',
        contentRevision:
            LexicalPromptArtifactResolver.formatEvidenceContentRevision(
              promptMode: contextual ? 'associativeRecall' : 'typedRecall',
              wordId: wordId,
              revision: contentRevision,
              checksumSha256: checksumSha256,
            ),
      ),
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance: providerProvenance,
      hintLevel: classification.hintLevel,
    );
  }

  /// Typed exposure ingress for a flashcard answer reveal. Research assignment
  /// still resolves against the SRS activity while the durable declaration is
  /// exposure, so a reveal can never masquerade as independent recall.
  PendingCurrentActivityEvidence captureFlashcardExposure({
    String? ownerId,
    required String sessionId,
    required String wordId,
    required int? responseTimeMs,
    required int attemptNumber,
  }) => _capture(
    ownerId: ownerId,
    input: CurrentActivityInput.srsRecall,
    declaration: const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.exposure,
      skillId: 'srs-recall',
      promptMode: 'flashcardExposure',
    ),
    sessionId: sessionId,
    wordId: wordId,
    isCorrect: false,
    responseTimeMs: responseTimeMs,
    attemptNumber: attemptNumber,
    providerProvenance: null,
    hintLevel: 0,
  );

  /// Captures one matching resolution through the canonical AnswerAttempts
  /// authority. Matching is recognition unless the shell-owned hint/support
  /// snapshot proves any assistance, in which case it is guided practice.
  PendingCurrentActivityEvidence captureMatching({
    String? ownerId,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required String contentRevision,
    required HintEvidenceClassification classification,
    ContrastiveFeedbackContext? contrastiveFeedback,
  }) {
    final validUnassisted =
        classification.hintLevel == 0 &&
        classification.evidenceClass == EvidenceClass.recognition;
    final validAssisted =
        classification.hintLevel > 0 &&
        classification.evidenceClass == EvidenceClass.guidedPractice;
    if ((!validUnassisted && !validAssisted) || responseTimeMs < 0) {
      throw ArgumentError.value(
        classification,
        'classification',
        'must be unassisted recognition or assisted guided practice',
      );
    }
    return _capture(
      ownerId: ownerId,
      input: CurrentActivityInput.matchingPair,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: classification.evidenceClass,
        skillId: 'matching-recognition',
        promptMode: 'matchingPair',
        contentRevision: contentRevision,
      ),
      sessionId: sessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance: 'pinned-lexical-matching',
      hintLevel: classification.hintLevel,
      contrastiveFeedback: contrastiveFeedback,
    );
  }

  PendingCurrentActivityEvidence capturePracticeReplayMatching({
    required PairMatchingPlanV1 plan,
    String? ownerId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required String contentRevision,
  }) {
    if (plan.sessionPurpose != PairSessionPurpose.practiceReplay ||
        plan.sourceSessionId == null ||
        plan.sourceSessionId == plan.learningSessionId ||
        !plan.orderedLexicalItems.any((i) => i.wordId == wordId) ||
        responseTimeMs < 0) {
      throw StateError(
        'Pair replay capture requires source-linked accepted pins',
      );
    }
    return _capture(
      ownerId: ownerId ?? plan.ownerId,
      input: CurrentActivityInput.matchingPair,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: EvidenceClass.recreational,
        skillId: 'matching-recognition',
        promptMode: 'matchingPair',
        contentRevision: contentRevision,
      ),
      sessionId: plan.learningSessionId,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: attemptNumber,
      providerProvenance: 'pinned-lexical-matching',
      hintLevel: 0,
    );
  }

  PendingCurrentActivityEvidence restorePracticeReplayMatching(
    FrozenPendingCurrentActivityEvidence frozen, {
    required PairMatchingPlanV1 plan,
    String? ownerId,
  }) {
    frozen.requirePracticeReplayContext();
    if (plan.sessionPurpose != PairSessionPurpose.practiceReplay ||
        plan.sourceSessionId == null ||
        frozen.sessionId != plan.learningSessionId ||
        (ownerId == null && frozen.ownerId != plan.ownerId) ||
        frozen.input != CurrentActivityInput.matchingPair ||
        frozen.declaredEvidenceClass != EvidenceClass.recreational ||
        frozen.evidenceContext.evidenceClass != EvidenceClass.recreational ||
        frozen.hintLevel != 0 ||
        frozen.evidenceContext.protocolId != null ||
        frozen.eventContext.protocolId != null ||
        frozen.evidenceContext.engagementAllowed ||
        frozen.contrastiveFeedback != null) {
      throw StateError('Pair replay frozen context changed');
    }
    return restore(frozen, ownerId: ownerId);
  }

  /// Reconstructs a fully resolved occurrence without consulting mutable
  /// owner, rollout, or research providers. An explicit retry is mandatory.
  PendingCurrentActivityEvidence restore(
    FrozenPendingCurrentActivityEvidence frozen, {
    String? ownerId,
  }) {
    final recoveredOwnerId = ownerId ?? frozen.ownerId;
    if (recoveredOwnerId.isEmpty ||
        recoveredOwnerId != recoveredOwnerId.trim() ||
        recoveredOwnerId.runes.length > 256) {
      throw ArgumentError.value(
        recoveredOwnerId,
        'ownerId',
        'must be canonical',
      );
    }
    return PendingCurrentActivityEvidence._(
      learning: learning,
      ownerId: recoveredOwnerId,
      input: frozen.input,
      declaration: _CurrentActivityDeclaration(
        evidenceClass: frozen.declaredEvidenceClass,
        skillId: frozen.skillId,
        promptMode: frozen.promptMode,
        contentRevision: frozen.contentRevision,
      ),
      hintLevel: frozen.hintLevel,
      rolloutModeProvider: rolloutModeProvider,
      researchStateProvider: researchStateProvider,
      contrastiveFeedback: frozen.contrastiveFeedback,
      restoredContexts: ResolvedLearningEvidenceContexts(
        evidenceContext: frozen.evidenceContext,
        eventContext: frozen.eventContext,
      ),
      command: FrozenLearningEvidenceCommand(
        sourceEvidenceId: frozen.sourceEvidenceId,
        occurredAtUtc: frozen.occurredAtUtc,
        sessionId: frozen.sessionId,
        wordId: frozen.wordId,
        promptMode: frozen.promptMode,
        isCorrect: frozen.isCorrect,
        responseTimeMs: frozen.responseTimeMs,
        attemptNumber: frozen.attemptNumber,
        providerProvenance: frozen.providerProvenance,
        actorIdentity: frozen.actorIdentity,
      ),
    ).._status = PendingCurrentActivityEvidenceStatus.retryRequired;
  }

  /// Reconstructs a previously checkpointed matching occurrence with its
  /// exact caller-owned identity. The returned command deliberately requires
  /// an explicit retry before any canonical write can occur.
  PendingCurrentActivityEvidence restoreMatching({
    String? ownerId,
    required String sourceEvidenceId,
    required DateTime occurredAtUtc,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int responseTimeMs,
    required int attemptNumber,
    required String contentRevision,
    required HintEvidenceClassification classification,
    required ResolvedLearningEvidenceContexts contexts,
    String? actorIdentity,
    String providerProvenance = 'pinned-lexical-matching',
    FrozenContrastiveFeedbackContext? contrastiveFeedback,
  }) {
    final validUnassisted =
        classification.hintLevel == 0 &&
        classification.evidenceClass == EvidenceClass.recognition;
    final validAssisted =
        classification.hintLevel > 0 &&
        classification.evidenceClass == EvidenceClass.guidedPractice;
    if ((!validUnassisted && !validAssisted) ||
        responseTimeMs < 0 ||
        !occurredAtUtc.isUtc) {
      throw ArgumentError.value(
        classification,
        'classification',
        'invalid restored matching evidence',
      );
    }
    final frozenEvidenceContext = contexts.evidenceContext;
    final frozenContrastiveFeedback = contrastiveFeedback;
    if (providerProvenance != 'pinned-lexical-matching' &&
        !isContrastiveFeedbackAttemptProvenance(providerProvenance)) {
      throw ArgumentError.value(
        providerProvenance,
        'providerProvenance',
        'invalid restored matching provenance',
      );
    }
    if (frozenContrastiveFeedback != null &&
        providerProvenance !=
            contrastiveFeedbackAttemptProvenance(frozenContrastiveFeedback)) {
      throw StateError(
        'restored matching contrastive feedback identity is corrupt',
      );
    }
    try {
      contexts.eventContext.validateAgainst(
        evidenceContext: frozenEvidenceContext,
        occurredAtUtc: occurredAtUtc,
      );
    } on Object catch (error) {
      throw StateError('restored matching contexts are corrupt: $error');
    }
    if (frozenEvidenceContext.evidenceClass != classification.evidenceClass ||
        frozenEvidenceContext.hintLevel != classification.hintLevel ||
        frozenEvidenceContext.skillId != 'matching-recognition' ||
        frozenEvidenceContext.contentRevision != contentRevision) {
      throw StateError(
        'restored matching contexts conflict with their classification',
      );
    }
    final canonicalOwnerId = ownerId ?? actorIdentity;
    if (canonicalOwnerId == null) {
      throw StateError('restored matching owner identity is unavailable');
    }
    return restore(
      FrozenPendingCurrentActivityEvidence._validated(
        ownerId: canonicalOwnerId,
        sourceEvidenceId: sourceEvidenceId,
        occurredAtUtc: occurredAtUtc,
        sessionId: sessionId,
        wordId: wordId,
        promptMode: 'matchingPair',
        isCorrect: isCorrect,
        responseTimeMs: responseTimeMs,
        attemptNumber: attemptNumber,
        providerProvenance: providerProvenance,
        actorIdentity: actorIdentity ?? canonicalOwnerId,
        input: CurrentActivityInput.matchingPair,
        declaredEvidenceClass: classification.evidenceClass,
        skillId: 'matching-recognition',
        contentRevision: contentRevision,
        declarationPromptMode: 'matchingPair',
        hintLevel: classification.hintLevel,
        contrastiveFeedback: frozenContrastiveFeedback,
        evidenceContext: frozenEvidenceContext,
        eventContext: contexts.eventContext,
      ),
    );
  }

  PendingCurrentActivityEvidence _capture({
    required String? ownerId,
    required CurrentActivityInput input,
    required _CurrentActivityDeclaration declaration,
    required String sessionId,
    required String wordId,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    required String? providerProvenance,
    required int hintLevel,
    ContrastiveFeedbackContext? contrastiveFeedback,
  }) {
    final generatedId = generateId().trim();
    if (generatedId.isEmpty) {
      throw StateError('learning id generator returned blank');
    }
    final occurredAtUtc = nowUtc();
    if (!occurredAtUtc.isUtc) {
      throw ArgumentError.value(occurredAtUtc, 'nowUtc', 'must be UTC');
    }
    final frozenContrastiveFeedback = contrastiveFeedback?.freeze();
    final canonicalProviderProvenance = frozenContrastiveFeedback == null
        ? providerProvenance
        : contrastiveFeedbackAttemptProvenance(frozenContrastiveFeedback);
    return PendingCurrentActivityEvidence._(
      learning: learning,
      ownerId: ownerId,
      input: input,
      declaration: declaration,
      hintLevel: hintLevel,
      rolloutModeProvider: rolloutModeProvider,
      researchStateProvider: researchStateProvider,
      contrastiveFeedback: frozenContrastiveFeedback,
      command: FrozenLearningEvidenceCommand(
        sourceEvidenceId: 'attempt:$generatedId',
        occurredAtUtc: occurredAtUtc,
        sessionId: sessionId,
        wordId: wordId,
        promptMode: declaration.promptMode,
        isCorrect: isCorrect,
        responseTimeMs: responseTimeMs,
        attemptNumber: attemptNumber,
        providerProvenance: canonicalProviderProvenance,
      ),
    );
  }
}

enum PendingCurrentActivityEvidenceStatus {
  captured,
  resolving,
  writing,
  retryRequired,
  committed,
}

final class PendingCurrentActivityEvidence {
  PendingCurrentActivityEvidence._({
    required this._learning,
    required this._ownerId,
    required this._input,
    required this._declaration,
    required this._hintLevel,
    required this._rolloutModeProvider,
    required this._researchStateProvider,
    required this._command,
    this._contrastiveFeedback,
    this._restoredContexts,
  });

  final LearningUseCases _learning;
  final String? _ownerId;
  final CurrentActivityInput _input;
  final _CurrentActivityDeclaration _declaration;
  final int _hintLevel;
  final EvidencePolicyRolloutModeProvider _rolloutModeProvider;
  final CurrentActivityResearchStateProvider _researchStateProvider;
  final FrozenLearningEvidenceCommand _command;
  final FrozenContrastiveFeedbackContext? _contrastiveFeedback;
  final ResolvedLearningEvidenceContexts? _restoredContexts;

  PendingCurrentActivityEvidenceStatus _status =
      PendingCurrentActivityEvidenceStatus.captured;
  Future<OwnerBoundLearningEvidenceBasis>? _bindingInFlight;
  OwnerBoundLearningEvidenceBasis? _boundBasis;
  Future<ResolvedLearningEvidenceRecord>? _resolutionInFlight;
  ResolvedLearningEvidenceRecord? _resolved;
  Future<AnswerRecordResult>? _recordInFlight;
  AnswerRecordResult? _result;

  String get sourceEvidenceId => _command.sourceEvidenceId;
  DateTime get occurredAtUtc => _command.occurredAtUtc;
  String get sessionId => _command.sessionId;
  String get wordId => _command.wordId;
  String get promptMode => _command.promptMode;
  bool get isCorrect => _command.isCorrect;
  int? get responseTimeMs => _command.responseTimeMs;
  int get attemptNumber => _command.attemptNumber;
  String? get providerProvenance => _command.providerProvenance;
  String? get actorIdentity => _command.actorIdentity ?? _boundBasis?.ownerId;
  FrozenContrastiveFeedbackContext? get contrastiveFeedback =>
      _contrastiveFeedback;
  EvidenceContext? get evidenceContext => _resolved?.contexts.evidenceContext;
  PendingCurrentActivityEvidenceStatus get status => _status;
  bool get requiresRetry =>
      _status == PendingCurrentActivityEvidenceStatus.retryRequired;
  bool get isCommitted =>
      _status == PendingCurrentActivityEvidenceStatus.committed;
  bool get isInFlight => _recordInFlight != null;

  /// Once captured, mutable response controls remain locked until the owning
  /// screen advances after a successful commit.
  bool get isResponseLocked => !isCommitted;

  /// Opaque authority check for controller-owned capture boundaries. The
  /// underlying [LearningUseCases] instance is deliberately not exposed.
  bool belongsToLearningAuthority(LearningUseCases authority) =>
      identical(_learning, authority);

  /// Freezes one owner-bound, fully resolved pending occurrence without
  /// performing its canonical answer write.
  Future<FrozenPendingCurrentActivityEvidence> freezeForRecovery() async {
    if (_recordInFlight != null) {
      throw StateError('pending evidence write is already in flight');
    }
    if (isCommitted) {
      throw StateError('committed evidence cannot be frozen as pending');
    }
    final previousStatus = _status;
    _status = PendingCurrentActivityEvidenceStatus.resolving;
    try {
      final resolved = await _resolveOnce();
      final command = resolved.command;
      return FrozenPendingCurrentActivityEvidence._validated(
        ownerId: resolved.ownerId,
        sourceEvidenceId: command.sourceEvidenceId,
        occurredAtUtc: command.occurredAtUtc,
        sessionId: command.sessionId,
        wordId: command.wordId,
        promptMode: command.promptMode,
        isCorrect: command.isCorrect,
        responseTimeMs: command.responseTimeMs,
        attemptNumber: command.attemptNumber,
        providerProvenance: command.providerProvenance,
        actorIdentity: command.actorIdentity ?? resolved.ownerId,
        input: _input,
        declaredEvidenceClass: _declaration.evidenceClass,
        skillId: _declaration.skillId,
        declarationPromptMode: _declaration.promptMode,
        contentRevision: _declaration.contentRevision,
        hintLevel: _hintLevel,
        contrastiveFeedback: _contrastiveFeedback,
        evidenceContext: resolved.contexts.evidenceContext,
        eventContext: resolved.contexts.eventContext,
      );
    } catch (_) {
      _status = PendingCurrentActivityEvidenceStatus.retryRequired;
      rethrow;
    } finally {
      if (_status == PendingCurrentActivityEvidenceStatus.resolving) {
        _status = previousStatus;
      }
    }
  }

  Future<ResolvedLearningEvidenceContexts> freezeContexts() async {
    final previousStatus = _status;
    _status = PendingCurrentActivityEvidenceStatus.resolving;
    try {
      return (await _resolveOnce()).contexts;
    } catch (_) {
      _status = PendingCurrentActivityEvidenceStatus.retryRequired;
      rethrow;
    } finally {
      if (_status == PendingCurrentActivityEvidenceStatus.resolving) {
        _status = previousStatus;
      }
    }
  }

  Future<AnswerRecordResult> record() {
    final inFlight = _recordInFlight;
    if (inFlight != null) return inFlight;
    if (requiresRetry) {
      return Future<AnswerRecordResult>.error(
        StateError('explicit retry is required for pending evidence'),
      );
    }
    final result = _result;
    if (result != null) return Future<AnswerRecordResult>.value(result);
    return _startRecord();
  }

  Future<AnswerRecordResult> retry() {
    final inFlight = _recordInFlight;
    if (inFlight != null) return inFlight;
    if (!requiresRetry) {
      return Future<AnswerRecordResult>.error(
        StateError('pending evidence is not awaiting retry'),
      );
    }
    return _startRecord();
  }

  Future<AnswerRecordResult> _startRecord() {
    final future = _executeRecord();
    _recordInFlight = future;
    return future;
  }

  Future<AnswerRecordResult> _executeRecord() async {
    try {
      _status = PendingCurrentActivityEvidenceStatus.resolving;
      final resolved = await _resolveOnce();
      _status = PendingCurrentActivityEvidenceStatus.writing;
      final result = await _learning.recordResolvedEvidence(
        resolved,
        contrastiveFeedback: _contrastiveFeedback,
      );
      _result = result;
      _status = PendingCurrentActivityEvidenceStatus.committed;
      return result;
    } catch (_) {
      _status = PendingCurrentActivityEvidenceStatus.retryRequired;
      rethrow;
    } finally {
      _recordInFlight = null;
    }
  }

  Future<ResolvedLearningEvidenceRecord> _resolveOnce() {
    final resolved = _resolved;
    if (resolved != null) {
      return Future<ResolvedLearningEvidenceRecord>.value(resolved);
    }
    return _resolutionInFlight ??= _resolveAndMemoize();
  }

  Future<ResolvedLearningEvidenceRecord> _resolveAndMemoize() async {
    try {
      final basis = await _bindOnce();
      final restoredContexts = _restoredContexts;
      final resolved = await _learning.resolveOwnerBoundEvidenceForRecording(
        basis: basis,
        resolveContexts: ({required ownerId, required command}) async {
          if (restoredContexts != null) return restoredContexts;
          if (_input == CurrentActivityInput.matchingPair &&
              _declaration.evidenceClass == EvidenceClass.recreational) {
            final context = EvidenceContext.forNewEvidence(
              evidenceClass: EvidenceClass.recreational,
              skillId: 'matching-recognition',
              hintLevel: 0,
              contentRevision: _declaration.contentRevision,
              rolloutMode: EvidencePolicyRolloutMode.legacy,
              engagementAllowed: false,
            );
            return ResolvedLearningEvidenceContexts(
              evidenceContext: context,
              eventContext: LearningEventContext.noResearch(context),
            );
          }
          final rolloutMode = await _rolloutModeProvider.resolve(
            ownerId: ownerId,
            evidenceContext: null,
          );
          final research = await _researchStateProvider.resolveActivity(
            ownerId: ownerId,
            input: _input,
            occurredAtUtc: command.occurredAtUtc,
            rolloutMode: rolloutMode,
          );
          final evidenceClassOverride = research.protocolEvidenceClassOverride;
          if (evidenceClassOverride != null &&
              (_input != CurrentActivityInput.ghostDuel ||
                  rolloutMode == EvidencePolicyRolloutMode.legacy ||
                  !research.hasCompleteResearchProtocol)) {
            throw StateError(
              'protocol evidence-class overrides require a complete '
              'non-Legacy Ghost Duel protocol',
            );
          }
          final declaredEvidenceClass =
              evidenceClassOverride ?? _declaration.evidenceClass;
          final hintClassification = HintPolicy.classifyEvidence(
            declaredClass: declaredEvidenceClass,
            hint: HintUsageSnapshot.fromRecordedLevel(_hintLevel),
          );
          final useVersionedLegacyMatrix =
              rolloutMode == EvidencePolicyRolloutMode.legacy &&
              _input == CurrentActivityInput.matchingPair;
          final evidenceContext =
              rolloutMode == EvidencePolicyRolloutMode.legacy &&
                  !useVersionedLegacyMatrix
              ? EvidenceContext.legacyCompatibility(
                  evidenceClass: hintClassification.evidenceClass,
                  skillId: _declaration.skillId,
                  hintLevel: hintClassification.hintLevel,
                  contentRevision: _declaration.contentRevision,
                  engagementAllowed: research.engagementAllowed,
                )
              : EvidenceContext.forNewEvidence(
                  evidenceClass: hintClassification.evidenceClass,
                  skillId: _declaration.skillId,
                  hintLevel: hintClassification.hintLevel,
                  contentRevision: _declaration.contentRevision,
                  rolloutMode: rolloutMode,
                  protocolId: research.protocolId,
                  protocolVersion: research.protocolVersion,
                  experimentId: research.experimentContext?.experimentId,
                  experimentVersion: research.experimentVersion,
                  assignmentId: research.assignmentId,
                  cohort: research.experimentContext?.variantId,
                  researchConsentVersion: useVersionedLegacyMatrix
                      ? null
                      : research.consentContext.researchConsentVersion,
                  engagementAllowed: useVersionedLegacyMatrix
                      ? false
                      : research.engagementAllowed,
                );
          return ResolvedLearningEvidenceContexts(
            evidenceContext: evidenceContext,
            eventContext: research.eventContextFor(evidenceContext),
          );
        },
      );
      _resolved = resolved;
      return resolved;
    } finally {
      _resolutionInFlight = null;
    }
  }

  Future<OwnerBoundLearningEvidenceBasis> _bindOnce() {
    final basis = _boundBasis;
    if (basis != null) {
      return Future<OwnerBoundLearningEvidenceBasis>.value(basis);
    }
    return _bindingInFlight ??= _bindAndMemoize();
  }

  Future<OwnerBoundLearningEvidenceBasis> _bindAndMemoize() async {
    try {
      final basis = await _learning.bindEvidenceForRecording(
        command: _command,
        ownerId: _ownerId,
      );
      _boundBasis = basis;
      return basis;
    } finally {
      _bindingInFlight = null;
    }
  }
}

final class _CurrentActivityDeclaration {
  const _CurrentActivityDeclaration({
    required this.evidenceClass,
    required this.skillId,
    required this.promptMode,
    this.contentRevision = 'built-in-v1',
  });

  final EvidenceClass evidenceClass;
  final String skillId;
  final String promptMode;
  final String contentRevision;
}

_CurrentActivityDeclaration _declarationFor(CurrentActivityInput input) {
  return switch (input) {
    CurrentActivityInput.meaningMultipleChoice =>
      const _CurrentActivityDeclaration(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'meaning-recall',
        promptMode: 'meaningChoice',
      ),
    CurrentActivityInput.meaningToWordMultipleChoice =>
      const _CurrentActivityDeclaration(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'meaning-recall',
        promptMode: 'wordChoice',
      ),
    CurrentActivityInput.definitionMultipleChoice =>
      const _CurrentActivityDeclaration(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'definition-recognition',
        promptMode: 'definitionChoice',
      ),
    CurrentActivityInput.clozeSelected => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.recognition,
      skillId: 'cloze-context',
      promptMode: 'clozeSelected',
    ),
    CurrentActivityInput.clozeTyped => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'cloze-context',
      promptMode: 'clozeTyped',
    ),
    CurrentActivityInput.matchingPair => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.recognition,
      skillId: 'matching-recognition',
      promptMode: 'matchingPair',
    ),
    CurrentActivityInput.srsRecall => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'srs-recall',
      promptMode: 'srsRecall',
    ),
    CurrentActivityInput.typedRecall => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'typed-recall',
      promptMode: 'typedRecall',
    ),
    CurrentActivityInput.associativeRecall => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'associative-recall',
      promptMode: 'associativeRecall',
    ),
    CurrentActivityInput.ghostDuel => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.recreational,
      skillId: 'ghost-duel',
      promptMode: 'ghostSpelling',
    ),
    CurrentActivityInput.speakToText => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.pronunciation,
      skillId: 'pronunciation-transcript',
      promptMode: 'pronunciationTranscript',
    ),
    CurrentActivityInput.shadowing => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.pronunciation,
      skillId: 'shadowing-pronunciation',
      promptMode: 'shadowing',
    ),
    CurrentActivityInput.readingExposure => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.exposure,
      skillId: 'reading-exposure',
      promptMode: 'readingExposure',
    ),
    CurrentActivityInput.dictation => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'dictation-spelling',
      promptMode: 'dictation',
    ),
    CurrentActivityInput.sentenceScramble => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.recreational,
      skillId: 'sentence-scramble',
      promptMode: 'sentenceScramble',
    ),
    CurrentActivityInput.wordScramble => const _CurrentActivityDeclaration(
      evidenceClass: EvidenceClass.recreational,
      skillId: 'word-scramble',
      promptMode: 'wordScramble',
    ),
  };
}
