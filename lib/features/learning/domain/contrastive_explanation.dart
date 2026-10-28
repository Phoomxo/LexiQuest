import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../learning_packs/domain/content_manifest.dart';
import 'evidence_context.dart';
import 'lexical_prompt_artifact_identity.dart';

const String contrastiveFeedbackAttemptProvenancePrefix = 'f18:v1:';

/// The option and f04 artifact identity frozen with a submission before its
/// one canonical answer write begins.
final class ContrastiveFeedbackContext {
  factory ContrastiveFeedbackContext({
    required ContentIdentity manifestIdentity,
    required String manifestChecksumSha256,
    required String promptMode,
    required String evidenceContentRevision,
    required String correctOptionId,
    required String selectedDistractorId,
  }) {
    final frozen = FrozenContrastiveFeedbackContext._validated(
      manifestIdentity: manifestIdentity,
      manifestChecksumSha256: manifestChecksumSha256,
      promptMode: promptMode,
      evidenceContentRevision: evidenceContentRevision,
      correctOptionId: correctOptionId,
      selectedDistractorId: selectedDistractorId,
    );
    return ContrastiveFeedbackContext._(frozen);
  }

  const ContrastiveFeedbackContext._(this._frozen);

  final FrozenContrastiveFeedbackContext _frozen;

  FrozenContrastiveFeedbackContext freeze() => _frozen;
}

/// Immutable answer semantics retained by the same pending operation that
/// owns the canonical attempt identity and retry.
final class FrozenContrastiveFeedbackContext {
  factory FrozenContrastiveFeedbackContext.fromJson(Map<String, Object?> json) {
    const keys = <String>{
      'contentType',
      'contentId',
      'contentRevision',
      'manifestChecksumSha256',
      'promptMode',
      'evidenceContentRevision',
      'correctOptionId',
      'selectedDistractorId',
    };
    if (json.length != keys.length || !json.keys.every(keys.contains)) {
      throw const FormatException('invalid frozen contrastive feedback shape.');
    }
    T require<T>(String field) {
      final value = json[field];
      if (value is! T) {
        throw FormatException('invalid frozen contrastive $field.');
      }
      return value;
    }

    final contentType = require<String>('contentType');
    if (contentType != ContentType.lexicalMetadata.name) {
      throw const FormatException(
        'frozen contrastive feedback must be lexical metadata.',
      );
    }
    return FrozenContrastiveFeedbackContext._validated(
      manifestIdentity: ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: require<String>('contentId'),
        revision: require<int>('contentRevision'),
      ),
      manifestChecksumSha256: require<String>('manifestChecksumSha256'),
      promptMode: require<String>('promptMode'),
      evidenceContentRevision: require<String>('evidenceContentRevision'),
      correctOptionId: require<String>('correctOptionId'),
      selectedDistractorId: require<String>('selectedDistractorId'),
    );
  }

  factory FrozenContrastiveFeedbackContext._validated({
    required ContentIdentity manifestIdentity,
    required String manifestChecksumSha256,
    required String promptMode,
    required String evidenceContentRevision,
    required String correctOptionId,
    required String selectedDistractorId,
  }) {
    _requireLexicalManifestIdentity(manifestIdentity);
    _requireChecksum(manifestChecksumSha256);
    _requireCanonicalIdentifier(promptMode, 'promptMode');
    _requireCanonicalIdentifier(
      evidenceContentRevision,
      'evidenceContentRevision',
      maxRunes: 512,
    );
    _requireCanonicalIdentifier(correctOptionId, 'correctOptionId');
    _requireCanonicalIdentifier(selectedDistractorId, 'selectedDistractorId');
    if (correctOptionId == selectedDistractorId) {
      throw const FormatException(
        'selectedDistractorId must differ from correctOptionId.',
      );
    }
    if (!_matchesEvidenceContentRevision(
      promptMode: promptMode,
      wordId: manifestIdentity.id,
      revision: manifestIdentity.revision,
      manifestChecksumSha256: manifestChecksumSha256,
      evidenceContentRevision: evidenceContentRevision,
    )) {
      throw const FormatException(
        'contrastive content must match the exact evidence revision.',
      );
    }
    return FrozenContrastiveFeedbackContext._(
      manifestIdentity: manifestIdentity,
      manifestChecksumSha256: manifestChecksumSha256,
      promptMode: promptMode,
      evidenceContentRevision: evidenceContentRevision,
      correctOptionId: correctOptionId,
      selectedDistractorId: selectedDistractorId,
    );
  }

  const FrozenContrastiveFeedbackContext._({
    required this.manifestIdentity,
    required this.manifestChecksumSha256,
    required this.promptMode,
    required this.evidenceContentRevision,
    required this.correctOptionId,
    required this.selectedDistractorId,
  });

  final ContentIdentity manifestIdentity;
  final String manifestChecksumSha256;
  final String promptMode;
  final String evidenceContentRevision;
  final String correctOptionId;
  final String selectedDistractorId;

  Map<String, Object?> toJson() => <String, Object?>{
    'contentType': manifestIdentity.type.name,
    'contentId': manifestIdentity.id,
    'contentRevision': manifestIdentity.revision,
    'manifestChecksumSha256': manifestChecksumSha256,
    'promptMode': promptMode,
    'evidenceContentRevision': evidenceContentRevision,
    'correctOptionId': correctOptionId,
    'selectedDistractorId': selectedDistractorId,
  };
}

String contrastiveFeedbackAttemptProvenance(
  FrozenContrastiveFeedbackContext context,
) =>
    '$contrastiveFeedbackAttemptProvenancePrefix'
    '${sha256.convert(utf8.encode(jsonEncode(context.toJson())))}';

bool isContrastiveFeedbackAttemptProvenance(String? value) =>
    value != null && RegExp(r'^f18:v1:[0-9a-f]{64}$').hasMatch(value);

/// Attempt identity emitted only after the canonical evidence operation has
/// acknowledged the exact frozen submission.
final class CommittedContrastiveAttempt {
  const CommittedContrastiveAttempt({
    required this.attemptIdentity,
    required this.ownerId,
    required this.sessionId,
    required this.wordId,
    required this.promptMode,
    required this.evidenceContentRevision,
    required this.manifestIdentity,
    required this.manifestChecksumSha256,
    required this.correctOptionId,
    required this.selectedDistractorId,
  });

  final String attemptIdentity;
  final String ownerId;
  final String sessionId;
  final String wordId;
  final String promptMode;
  final String evidenceContentRevision;
  final ContentIdentity manifestIdentity;
  final String manifestChecksumSha256;
  final String correctOptionId;
  final String selectedDistractorId;

  bool get isSelfConsistent {
    try {
      _requireCanonicalIdentifier(attemptIdentity, 'attemptIdentity');
      _requireCanonicalIdentifier(ownerId, 'ownerId');
      _requireCanonicalIdentifier(sessionId, 'sessionId');
      _requireCanonicalIdentifier(wordId, 'wordId');
      final frozen = FrozenContrastiveFeedbackContext._validated(
        manifestIdentity: manifestIdentity,
        manifestChecksumSha256: manifestChecksumSha256,
        promptMode: promptMode,
        evidenceContentRevision: evidenceContentRevision,
        correctOptionId: correctOptionId,
        selectedDistractorId: selectedDistractorId,
      );
      return frozen.manifestIdentity.id == wordId;
    } on Object {
      return false;
    }
  }

  String get stableFingerprint => jsonEncode(<String, Object?>{
    'attemptIdentity': attemptIdentity,
    'ownerId': ownerId,
    'sessionId': sessionId,
    'wordId': wordId,
    'promptMode': promptMode,
    'evidenceContentRevision': evidenceContentRevision,
    'contentType': manifestIdentity.type.name,
    'contentId': manifestIdentity.id,
    'contentRevision': manifestIdentity.revision,
    'manifestChecksumSha256': manifestChecksumSha256,
    'correctOptionId': correctOptionId,
    'selectedDistractorId': selectedDistractorId,
  });
}

/// Read-only guided feedback resolved from one reviewed, pinned artifact.
final class ContrastiveExplanation {
  factory ContrastiveExplanation.reviewed({
    required ContentIdentity manifestIdentity,
    required String correctOptionId,
    required String selectedDistractorId,
    required String correctRationale,
    required String distractorRationale,
  }) {
    _requireLexicalManifestIdentity(manifestIdentity);
    _requireCanonicalIdentifier(correctOptionId, 'correctOptionId');
    _requireCanonicalIdentifier(selectedDistractorId, 'selectedDistractorId');
    if (correctOptionId == selectedDistractorId) {
      throw const FormatException(
        'selectedDistractorId must differ from correctOptionId.',
      );
    }
    _requireRationale(correctRationale, 'correctRationale');
    _requireRationale(distractorRationale, 'distractorRationale');
    return ContrastiveExplanation._(
      manifestIdentity: manifestIdentity,
      correctOptionId: correctOptionId,
      selectedDistractorId: selectedDistractorId,
      correctRationale: correctRationale,
      distractorRationale: distractorRationale,
    );
  }

  const ContrastiveExplanation._({
    required this.manifestIdentity,
    required this.correctOptionId,
    required this.selectedDistractorId,
    required this.correctRationale,
    required this.distractorRationale,
  });

  final ContentIdentity manifestIdentity;
  final String correctOptionId;
  final String selectedDistractorId;
  final String correctRationale;
  final String distractorRationale;

  EvidenceClass get evidenceClass => EvidenceClass.guidedPractice;
}

String contrastiveEvidenceContentRevision({
  required String promptMode,
  required String wordId,
  required int revision,
  required String checksumSha256,
}) => LexicalPromptArtifactResolver.formatEvidenceContentRevision(
  promptMode: promptMode,
  wordId: wordId,
  revision: revision,
  checksumSha256: checksumSha256,
);

bool _matchesEvidenceContentRevision({
  required String promptMode,
  required String wordId,
  required int revision,
  required String manifestChecksumSha256,
  required String evidenceContentRevision,
}) {
  final escapedWordId = RegExp.escape(wordId);
  final prefix = switch (promptMode) {
    'matchingPair' => 'lexical-matching:v$revision:',
    'meaningChoice' ||
    'wordChoice' => 'lexical-meaning:$escapedWordId@$revision:',
    'definitionChoice' => 'lexical-definition:$escapedWordId@$revision:',
    'clozeSelected' ||
    'clozeTyped' => 'lexical-cloze:$escapedWordId@$revision:',
    'typedRecall' ||
    'associativeRecall' => 'lexical-typed-recall:$escapedWordId@$revision:',
    _ => null,
  };
  return prefix != null &&
      RegExp('^$prefix[0-9a-f]{64}\$').hasMatch(evidenceContentRevision) &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(manifestChecksumSha256);
}

void _requireLexicalManifestIdentity(ContentIdentity identity) {
  if (identity.type != ContentType.lexicalMetadata ||
      identity.id.isEmpty ||
      identity.id != identity.id.trim() ||
      identity.id.runes.length > 256 ||
      identity.revision <= 0) {
    throw const FormatException(
      'Contrastive feedback requires pinned lexical metadata.',
    );
  }
}

void _requireCanonicalIdentifier(
  String value,
  String field, {
  int maxRunes = 256,
}) {
  if (value.isEmpty || value != value.trim() || value.runes.length > maxRunes) {
    throw FormatException('$field must be a canonical identifier.');
  }
}

void _requireChecksum(String value) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('manifest checksum must be lowercase SHA-256.');
  }
}

void _requireRationale(String value, String field) {
  if (value.isEmpty || value != value.trim() || value.runes.length > 4000) {
    throw FormatException('$field must be reviewed bounded text.');
  }
}
