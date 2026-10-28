import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../learning_packs/domain/content_manifest.dart';
import 'learning_models.dart';
import 'lexical_prompt_artifact_identity.dart';

/// Reading presentation state only. Results always come from authenticated
/// canonical attempts; no answer or score cache is accepted by this codec.
final class AssociativeReadingCheckpoint {
  AssociativeReadingCheckpoint({
    required this.documentId,
    required this.documentRevision,
    required this.cefrLevel,
    required this.passage,
    required this.stage,
    required Iterable<ReadingWordPin> words,
  }) : words = List.unmodifiable(words) {
    _text(documentId, 256);
    _positive(documentRevision);
    _text(cefrLevel, 32);
    _text(passage, 32768);
    if (stage < 1 ||
        stage > 6 ||
        this.words.isEmpty ||
        this.words.length > 100 ||
        this.words.map((word) => word.id).toSet().length != this.words.length ||
        this.words.map((word) => word.spelling).toSet().length !=
            this.words.length ||
        utf8.encode(jsonEncode(toJson())).length > 65536) {
      throw const FormatException('Invalid reading checkpoint');
    }
  }

  final String documentId;
  final int documentRevision;
  final String cefrLevel;
  final String passage;
  final int stage;
  final List<ReadingWordPin> words;

  AssociativeReadingCheckpoint atStage(int value) =>
      AssociativeReadingCheckpoint(
        documentId: documentId,
        documentRevision: documentRevision,
        cefrLevel: cefrLevel,
        passage: passage,
        stage: value,
        words: words,
      );

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'kind': 'associativeReading',
    'documentId': documentId,
    'documentRevision': documentRevision,
    'cefrLevel': cefrLevel,
    'passage': passage,
    'passageSha256': sha256.convert(utf8.encode(passage)).toString(),
    'stage': stage,
    'words': words.map((word) => word.toJson()).toList(),
  };

  factory AssociativeReadingCheckpoint.fromJson(Map<String, Object?> json) {
    _keys(json, const {
      'schemaVersion',
      'kind',
      'documentId',
      'documentRevision',
      'cefrLevel',
      'passage',
      'passageSha256',
      'stage',
      'words',
    });
    if (json['schemaVersion'] != 1 ||
        json['kind'] != 'associativeReading' ||
        json['words'] is! List ||
        json['passage'] is! String ||
        json['passageSha256'] !=
            sha256.convert(utf8.encode(json['passage'] as String)).toString()) {
      throw const FormatException('Invalid reading checkpoint identity');
    }
    return AssociativeReadingCheckpoint(
      documentId: json['documentId'] as String,
      documentRevision: json['documentRevision'] as int,
      cefrLevel: json['cefrLevel'] as String,
      passage: json['passage'] as String,
      stage: json['stage'] as int,
      words: (json['words'] as List).map(
        (word) =>
            ReadingWordPin.fromJson((word as Map).cast<String, Object?>()),
      ),
    );
  }

  bool sameContent(AssociativeReadingCheckpoint other) =>
      jsonEncode(atStage(1).toJson()) == jsonEncode(other.atStage(1).toJson());

  List<bool?> recallResults(LearningActivityRecovery recovery) {
    if (recovery.session.activityType != 'associativeReading' ||
        recovery.checkpoint?.sessionId != recovery.session.id ||
        recovery.checkpoint?.activityType != 'associativeReading') {
      throw StateError('Reading recovery session identity mismatch');
    }
    final results = List<bool?>.filled(words.length, null);
    final evidenceIds = <String>{};
    for (final attempt in recovery.attempts) {
      final index = attempt.attemptNumber - 1;
      if (index < 0 ||
          index >= words.length ||
          results[index] != null ||
          !evidenceIds.add(attempt.id) ||
          attempt.ownerId != recovery.session.ownerId ||
          attempt.sessionId != recovery.session.id ||
          attempt.wordId != words[index].id ||
          attempt.promptMode != 'associativeRecall' ||
          attempt.evidenceContext.contentRevision !=
              words[index].evidenceRevision) {
        throw StateError('Reading recall evidence is not an exact occurrence');
      }
      results[index] = attempt.isCorrect;
    }
    if ((stage < 3 && results.any((value) => value != null)) ||
        (stage > 3 && results.any((value) => value == null))) {
      throw StateError('Reading stage has missing or unexpected recall');
    }
    return results;
  }
}

final class ReadingWordPin {
  ReadingWordPin({
    required this.id,
    required this.spelling,
    required this.canonicalAnswer,
    required this.revision,
    required this.checksum,
    required this.normalizationRevision,
    Iterable<String> acceptedVariants = const [],
    this.acceptedVariantsRevision,
    this.acceptedVariantsChecksum,
  }) : acceptedVariants = List.unmodifiable(acceptedVariants) {
    _text(id, 256);
    _text(spelling, 512);
    _text(canonicalAnswer, 512);
    _positive(revision);
    if (normalizationRevision != 'vocabulary-text-v1' ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum) ||
        this.acceptedVariants.length > 100 ||
        (this.acceptedVariants.isEmpty &&
            (acceptedVariantsRevision != null ||
                acceptedVariantsChecksum != null))) {
      throw const FormatException('Invalid reading lexical pin');
    }
    for (final variant in this.acceptedVariants) {
      _text(variant, 512);
    }
    if (_artifact == null)
      throw const FormatException('Invalid reading answer set');
  }
  final String id, spelling, canonicalAnswer, checksum, normalizationRevision;
  final int revision;
  final List<String> acceptedVariants;
  final int? acceptedVariantsRevision;
  final String? acceptedVariantsChecksum;
  LexicalPromptArtifactIdentity? get _artifact =>
      LexicalPromptArtifactResolver.resolveForAdapter(
        promptMode: 'associativeRecall',
        wordId: id,
        coreRevision: revision,
        coreChecksumSha256: checksum,
        verifiedArtifactRevision: acceptedVariantsRevision,
        verifiedArtifactChecksumSha256: acceptedVariantsChecksum,
        usesAcceptedVariants: acceptedVariants.isNotEmpty,
      );
  String get evidenceRevision => _artifact!.evidenceContentRevision;
  PinnedQuizContent get content => PinnedQuizContent(
    identity: ContentIdentity(
      type: ContentType.lexicalMetadata,
      id: id,
      revision: revision,
    ),
    checksumSha256: checksum,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'spelling': spelling,
    'canonicalAnswer': canonicalAnswer,
    'revision': revision,
    'checksum': checksum,
    'normalizationRevision': normalizationRevision,
    'acceptedVariants': acceptedVariants,
    'acceptedVariantsRevision': acceptedVariantsRevision,
    'acceptedVariantsChecksum': acceptedVariantsChecksum,
  };
  factory ReadingWordPin.fromJson(Map<String, Object?> json) {
    _keys(json, const {
      'id',
      'spelling',
      'canonicalAnswer',
      'revision',
      'checksum',
      'normalizationRevision',
      'acceptedVariants',
      'acceptedVariantsRevision',
      'acceptedVariantsChecksum',
    });
    return ReadingWordPin(
      id: json['id'] as String,
      spelling: json['spelling'] as String,
      canonicalAnswer: json['canonicalAnswer'] as String,
      revision: json['revision'] as int,
      checksum: json['checksum'] as String,
      normalizationRevision: json['normalizationRevision'] as String,
      acceptedVariants: (json['acceptedVariants'] as List).cast<String>(),
      acceptedVariantsRevision: json['acceptedVariantsRevision'] as int?,
      acceptedVariantsChecksum: json['acceptedVariantsChecksum'] as String?,
    );
  }
}

void _keys(Map<String, Object?> json, Set<String> keys) {
  if (json.length != keys.length || !json.keys.every(keys.contains)) {
    throw const FormatException('Unexpected reading checkpoint fields');
  }
}

void _text(String value, int maximum) {
  if (value.trim().isEmpty ||
      value.length > maximum ||
      value.contains('\u0000')) {
    throw const FormatException('Invalid reading text');
  }
}

void _positive(int value) {
  if (value < 1) throw const FormatException('Invalid reading revision');
}
