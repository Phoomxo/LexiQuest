import 'dart:convert';
import 'dart:typed_data';

import '../../progress/domain/progress_models.dart';

/// The local, user-directed destination boundary for a share-card artifact.
///
/// Implementations must let the user choose a destination before writing any
/// bytes. The application layer intentionally has no social, network, or
/// persistence dependency.
abstract interface class AchievementShareCardStore {
  Future<AchievementShareCardStoreResult> selectDestinationAndSave(
    AchievementShareCardArtifact artifact,
  );
}

enum AchievementShareCardStoreStatus { saved, cancelled }

final class AchievementShareCardStoreResult {
  const AchievementShareCardStoreResult.saved({required this.destination})
    : status = AchievementShareCardStoreStatus.saved;

  const AchievementShareCardStoreResult.cancelled()
    : status = AchievementShareCardStoreStatus.cancelled,
      destination = null;

  final AchievementShareCardStoreStatus status;
  final String? destination;
}

enum AchievementShareCardStatus { saved, cancelled }

final class AchievementShareCardResult {
  const AchievementShareCardResult({
    required this.status,
    required this.artifact,
    this.destination,
  });

  final AchievementShareCardStatus status;
  final AchievementShareCardArtifact artifact;
  final String? destination;
}

enum AchievementShareCardFailureCode {
  confirmationRequired,
  achievementUnavailable,
  invalidCanonicalUnlock,
  invalidArtifact,
  writeFailed,
}

final class AchievementShareCardException implements Exception {
  const AchievementShareCardException(this.code);

  final AchievementShareCardFailureCode code;
}

/// A self-contained, user-managed local file. It has no link to the owner,
/// evidence, session, or event authority after creation.
final class AchievementShareCardArtifact {
  AchievementShareCardArtifact._({
    required this.achievementId,
    required this.definitionVersion,
    required this.title,
    required this.unlockedAtUtc,
    required this.suggestedFileName,
    required this.mimeType,
    required Uint8List bytes,
  }) : _bytes = Uint8List.fromList(bytes);

  final String achievementId;
  final int definitionVersion;
  final String title;
  final DateTime unlockedAtUtc;
  final String suggestedFileName;
  final String mimeType;
  final Uint8List _bytes;

  /// A defensive copy keeps the artifact immutable across UI/store callers.
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

/// Resolves reviewed presentation metadata for IDs already unlocked by the
/// canonical achievement projection. This catalog never decides an unlock.
final class AchievementShareCardUseCases {
  AchievementShareCardUseCases({required AchievementShareCardStore store})
    : this._(store);

  AchievementShareCardUseCases._(this._store);

  static const _definitions = <String, String>{
    'first_answer': 'บันทึกคำตอบครั้งแรก',
    'first_correct': 'ตอบถูกครั้งแรก',
    'first_session': 'เรียนจบเซสชันแรก',
    'perfect_session': 'ตอบถูกครบทั้งเซสชัน',
    'ten_correct': 'ตอบถูกครบ 10 ครั้ง',
  };

  final AchievementShareCardStore _store;
  final Map<String, Future<AchievementShareCardResult>> _inFlight =
      <String, Future<AchievementShareCardResult>>{};

  /// True only for a structurally valid, known display definition.
  bool canShare(AchievementEvidence achievement) {
    try {
      _validateUnlock(achievement);
      return _definitions.containsKey(achievement.id);
    } on AchievementShareCardException {
      return false;
    }
  }

  Future<AchievementShareCardResult> share({
    required ProgressSnapshot progress,
    required String achievementId,
    required int definitionVersion,
    required bool confirmed,
  }) async {
    if (!confirmed) {
      throw const AchievementShareCardException(
        AchievementShareCardFailureCode.confirmationRequired,
      );
    }
    final unlock = _resolveUnlockedAchievement(
      progress: progress,
      achievementId: achievementId,
      definitionVersion: definitionVersion,
    );
    final artifact = _buildArtifact(unlock);
    final operationId =
        '${artifact.achievementId}:'
        '${artifact.definitionVersion}:'
        '${artifact.unlockedAtUtc.millisecondsSinceEpoch}';
    return _inFlight.putIfAbsent(operationId, () async {
      try {
        final saved = await _store.selectDestinationAndSave(artifact);
        return switch (saved.status) {
          AchievementShareCardStoreStatus.saved => AchievementShareCardResult(
            status: AchievementShareCardStatus.saved,
            artifact: artifact,
            destination: saved.destination,
          ),
          AchievementShareCardStoreStatus.cancelled =>
            AchievementShareCardResult(
              status: AchievementShareCardStatus.cancelled,
              artifact: artifact,
            ),
        };
      } finally {
        _inFlight.remove(operationId);
      }
    });
  }

  AchievementEvidence _resolveUnlockedAchievement({
    required ProgressSnapshot progress,
    required String achievementId,
    required int definitionVersion,
  }) {
    if (!_isCanonicalAchievementId(achievementId) || definitionVersion <= 0) {
      throw const AchievementShareCardException(
        AchievementShareCardFailureCode.achievementUnavailable,
      );
    }
    final matches = progress.achievements
        .where(
          (achievement) =>
              achievement.id == achievementId &&
              achievement.definitionVersion == definitionVersion,
        )
        .toList(growable: false);
    if (matches.length != 1 || !_definitions.containsKey(achievementId)) {
      throw const AchievementShareCardException(
        AchievementShareCardFailureCode.achievementUnavailable,
      );
    }
    final unlock = matches.single;
    _validateUnlock(unlock);
    return unlock;
  }

  AchievementShareCardArtifact _buildArtifact(AchievementEvidence unlock) {
    final title = _definitions[unlock.id];
    if (title == null || !_isSafeDisplayText(title)) {
      throw const AchievementShareCardException(
        AchievementShareCardFailureCode.invalidArtifact,
      );
    }
    final date = _isoDate(unlock.unlockedAtUtc);
    final text =
        '''<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1080" viewBox="0 0 1080 1080" role="img" aria-labelledby="title description">
  <title id="title">LexiQuest Achievement</title>
  <desc id="description">${_xmlEscape(title)}</desc>
  <rect width="1080" height="1080" fill="#10233d"/>
  <text x="96" y="216" fill="#ffffff" font-family="sans-serif" font-size="54">LexiQuest</text>
  <text x="96" y="430" fill="#ffffff" font-family="sans-serif" font-size="72">${_xmlEscape(title)}</text>
  <text x="96" y="540" fill="#c7d8ff" font-family="sans-serif" font-size="38">Definition v${unlock.definitionVersion}</text>
  <text x="96" y="610" fill="#c7d8ff" font-family="sans-serif" font-size="38">Unlocked $date</text>
</svg>''';
    final bytes = Uint8List.fromList(utf8.encode(text));
    return AchievementShareCardArtifact._(
      achievementId: unlock.id,
      definitionVersion: unlock.definitionVersion,
      title: title,
      unlockedAtUtc: unlock.unlockedAtUtc.toUtc(),
      suggestedFileName:
          'lexiquest-${unlock.id}-v${unlock.definitionVersion}.svg',
      mimeType: 'image/svg+xml',
      bytes: bytes,
    );
  }

  void _validateUnlock(AchievementEvidence unlock) {
    if (!_isCanonicalAchievementId(unlock.id) ||
        unlock.definitionVersion <= 0 ||
        !_isCanonicalSourceId(unlock.sourceEventId) ||
        !unlock.unlockedAtUtc.isUtc ||
        unlock.unlockedAtUtc.millisecondsSinceEpoch < 0) {
      throw const AchievementShareCardException(
        AchievementShareCardFailureCode.invalidCanonicalUnlock,
      );
    }
  }

  static bool _isCanonicalAchievementId(String value) =>
      RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(value);

  static bool _isCanonicalSourceId(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$').hasMatch(value);

  static bool _isSafeDisplayText(String value) =>
      value.isNotEmpty &&
      value == value.trim() &&
      value.runes.length <= 128 &&
      !value.runes.any((rune) => rune < 0x20 || rune == 0x7f);

  static String _isoDate(DateTime value) {
    final utc = value.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
