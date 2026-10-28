import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Canonical evidence identity for one lexical prompt and its exact artifact.
final class LexicalPromptArtifactIdentity {
  const LexicalPromptArtifactIdentity._({
    required this.promptMode,
    required this.wordId,
    required this.revision,
    required this.checksumSha256,
    required this.verifiedArtifactChecksumSha256,
  });

  final String promptMode;
  final String wordId;
  final int revision;
  final String checksumSha256;
  final String? verifiedArtifactChecksumSha256;

  String get evidenceContentRevision =>
      LexicalPromptArtifactResolver.formatEvidenceContentRevision(
        promptMode: promptMode,
        wordId: wordId,
        revision: revision,
        checksumSha256: checksumSha256,
      );
}

/// One prompt-to-artifact authority shared by production mode adapters and
/// evidence readers. Every digest commits the core prompt/answer checksum;
/// modes that consume reviewed rich metadata additionally commit that exact
/// artifact revision and checksum.
abstract final class LexicalPromptArtifactResolver {
  static LexicalPromptArtifactIdentity? resolveForAdapter({
    required String promptMode,
    required String wordId,
    required int coreRevision,
    required String? coreChecksumSha256,
    int? verifiedArtifactRevision,
    String? verifiedArtifactChecksumSha256,
    bool usesAcceptedVariants = false,
  }) {
    if (!_validWordId(wordId) ||
        coreRevision <= 0 ||
        coreChecksumSha256 == null ||
        !_sha256.hasMatch(coreChecksumSha256)) {
      return null;
    }
    final richIdentityAvailable =
        verifiedArtifactRevision == coreRevision &&
        verifiedArtifactChecksumSha256 != null &&
        _sha256.hasMatch(verifiedArtifactChecksumSha256);
    final consumesRichArtifact = switch (promptMode) {
      'meaningChoice' ||
      'wordChoice' ||
      'definitionChoice' ||
      'clozeSelected' ||
      'clozeTyped' => true,
      'typedRecall' || 'associativeRecall' => usesAcceptedVariants,
      'matchingPair' => false,
      _ => null,
    };
    if (consumesRichArtifact == null ||
        (consumesRichArtifact && !richIdentityAvailable)) {
      return null;
    }
    final checksum = canonicalPromptChecksumSha256(
      promptMode: promptMode,
      coreChecksumSha256: coreChecksumSha256,
      verifiedArtifactRevision: consumesRichArtifact
          ? verifiedArtifactRevision
          : null,
      verifiedArtifactChecksumSha256: consumesRichArtifact
          ? verifiedArtifactChecksumSha256
          : null,
    );
    return LexicalPromptArtifactIdentity._(
      promptMode: promptMode,
      wordId: wordId,
      revision: coreRevision,
      checksumSha256: checksum,
      verifiedArtifactChecksumSha256: consumesRichArtifact
          ? verifiedArtifactChecksumSha256
          : null,
    );
  }

  static List<LexicalPromptArtifactIdentity> resolveReaderCandidates({
    required String promptMode,
    required String wordId,
    required int coreRevision,
    required String? coreChecksumSha256,
    required bool verifiedArtifactLoaded,
    required bool usesAcceptedVariants,
    int? verifiedArtifactRevision,
    String? verifiedArtifactChecksumSha256,
  }) {
    final candidates = <LexicalPromptArtifactIdentity>[];
    void add(LexicalPromptArtifactIdentity? candidate) {
      if (candidate != null &&
          candidates.every(
            (existing) =>
                existing.evidenceContentRevision !=
                candidate.evidenceContentRevision,
          )) {
        candidates.add(candidate);
      }
    }

    add(
      resolveForAdapter(
        promptMode: promptMode,
        wordId: wordId,
        coreRevision: coreRevision,
        coreChecksumSha256: coreChecksumSha256,
        verifiedArtifactRevision: verifiedArtifactLoaded
            ? verifiedArtifactRevision
            : null,
        verifiedArtifactChecksumSha256: verifiedArtifactLoaded
            ? verifiedArtifactChecksumSha256
            : null,
        usesAcceptedVariants:
            (promptMode == 'typedRecall' ||
                promptMode == 'associativeRecall') &&
            verifiedArtifactLoaded &&
            usesAcceptedVariants,
      ),
    );
    return List<LexicalPromptArtifactIdentity>.unmodifiable(candidates);
  }

  static String formatEvidenceContentRevision({
    required String promptMode,
    required String wordId,
    required int revision,
    required String checksumSha256,
  }) {
    if (!_validWordId(wordId) ||
        revision <= 0 ||
        !_sha256.hasMatch(checksumSha256)) {
      throw FormatException('invalid lexical prompt artifact identity');
    }
    return switch (promptMode) {
      'meaningChoice' ||
      'wordChoice' => 'lexical-meaning:$wordId@$revision:$checksumSha256',
      'definitionChoice' =>
        'lexical-definition:$wordId@$revision:$checksumSha256',
      'clozeSelected' ||
      'clozeTyped' => 'lexical-cloze:$wordId@$revision:$checksumSha256',
      'typedRecall' || 'associativeRecall' =>
        'lexical-typed-recall:$wordId@$revision:$checksumSha256',
      'matchingPair' => 'lexical-matching:v$revision:$checksumSha256',
      _ => throw FormatException(
        'unsupported lexical prompt mode: $promptMode',
      ),
    };
  }

  static String typedRecallAnswerSetChecksumSha256({
    required String coreChecksumSha256,
    required int acceptedVariantsRevision,
    required String acceptedVariantsChecksumSha256,
  }) {
    if (!_sha256.hasMatch(coreChecksumSha256) ||
        acceptedVariantsRevision <= 0 ||
        !_sha256.hasMatch(acceptedVariantsChecksumSha256)) {
      throw ArgumentError('typed recall answer-set identity must be canonical');
    }
    return canonicalPromptChecksumSha256(
      promptMode: 'typedRecall',
      coreChecksumSha256: coreChecksumSha256,
      verifiedArtifactRevision: acceptedVariantsRevision,
      verifiedArtifactChecksumSha256: acceptedVariantsChecksumSha256,
    );
  }

  static String canonicalPromptChecksumSha256({
    required String promptMode,
    required String coreChecksumSha256,
    int? verifiedArtifactRevision,
    String? verifiedArtifactChecksumSha256,
  }) {
    if (!_supportedPromptModes.contains(promptMode) ||
        !_sha256.hasMatch(coreChecksumSha256) ||
        ((verifiedArtifactRevision == null) !=
            (verifiedArtifactChecksumSha256 == null)) ||
        (verifiedArtifactRevision != null &&
            (verifiedArtifactRevision <= 0 ||
                !_sha256.hasMatch(verifiedArtifactChecksumSha256!)))) {
      throw ArgumentError('lexical prompt identity inputs must be canonical');
    }
    return sha256
        .convert(
          utf8.encode(
            'lexical-prompt-artifact-v1\u0000$promptMode\u0000'
            '$coreChecksumSha256\u0000'
            '${verifiedArtifactRevision ?? '-'}\u0000'
            '${verifiedArtifactChecksumSha256 ?? '-'}',
          ),
        )
        .toString();
  }

  static bool _validWordId(String value) =>
      value.isNotEmpty &&
      value == value.trim() &&
      value.runes.length <= 256 &&
      !value.contains('@') &&
      !_control.hasMatch(value);
}

const Set<String> _supportedPromptModes = <String>{
  'meaningChoice',
  'wordChoice',
  'definitionChoice',
  'clozeSelected',
  'clozeTyped',
  'typedRecall',
  'associativeRecall',
  'matchingPair',
};

final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _control = RegExp(r'[\u0000-\u001f\u007f-\u009f]', unicode: true);
