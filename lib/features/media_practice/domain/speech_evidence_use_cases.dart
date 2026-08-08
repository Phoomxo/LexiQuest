import '../../../features/identity/domain/local_owner_repository.dart';

/// Command to persist one real speech-evidence record.
final class RecordSpeechEvidenceCommand {
  const RecordSpeechEvidenceCommand({
    required this.id,
    required this.ownerId,
    required this.sessionId,
    required this.wordId,
    required this.promptMode,
    required this.targetContent,
    required this.recognizedTranscript,
    required this.locale,
    required this.sttEngine,
    required this.similarityAlgorithm,
    required this.similarityScore,
    required this.isExactMatch,
    required this.recognitionConfidence,
    required this.sampleSize,
    required this.unavailableReason,
    required this.occurredAtUtc,
    this.durationMs,
  });

  final String id;
  final String ownerId;
  final String sessionId;
  final String wordId;
  final String promptMode;
  final String targetContent;
  final String recognizedTranscript;
  final String locale;
  final String sttEngine;
  final String similarityAlgorithm;
  final int? similarityScore;
  final bool isExactMatch;
  final double? recognitionConfidence;
  final int sampleSize;
  final String? unavailableReason;
  final DateTime occurredAtUtc;
  final int? durationMs;
}

/// Persists real microphone/STT pronunciation evidence.
abstract interface class SpeechEvidenceRepository {
  Future<String> recordSpeechEvidence(RecordSpeechEvidenceCommand command);
}

/// Resolves the active owner and persists real speech evidence.
final class SpeechEvidenceUseCases {
  SpeechEvidenceUseCases({
    required this.owners,
    required this.repository,
    required this._nowUtc,
    required this._generateId,
    this.onLocalMutation,
  });

  final LocalOwnerRepository owners;
  final SpeechEvidenceRepository repository;
  final DateTime Function() _nowUtc;
  final String Function() _generateId;
  final void Function()? onLocalMutation;

  Future<String> record({
    required String sessionId,
    required String wordId,
    required String promptMode,
    required String targetContent,
    required String recognizedTranscript,
    required String locale,
    required String sttEngine,
    required String similarityAlgorithm,
    required int? similarityScore,
    required bool isExactMatch,
    required double? recognitionConfidence,
    required int sampleSize,
    required String? unavailableReason,
    DateTime? occurredAtUtc,
    int? durationMs,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    final command = RecordSpeechEvidenceCommand(
      id: 'speech-evidence:${_generateId()}',
      ownerId: owner.id,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: promptMode,
      targetContent: targetContent,
      recognizedTranscript: recognizedTranscript,
      locale: locale,
      sttEngine: sttEngine,
      similarityAlgorithm: similarityAlgorithm,
      similarityScore: similarityScore,
      isExactMatch: isExactMatch,
      recognitionConfidence: recognitionConfidence,
      sampleSize: sampleSize,
      unavailableReason: unavailableReason,
      occurredAtUtc: occurredAtUtc ?? _nowUtc(),
      durationMs: durationMs,
    );
    final id = await repository.recordSpeechEvidence(command);
    onLocalMutation?.call();
    return id;
  }
}
