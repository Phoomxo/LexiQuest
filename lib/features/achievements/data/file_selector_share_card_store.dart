import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../application/achievement_share_card_use_cases.dart';

typedef AndroidShareCardSaver =
    Future<String?> Function(AchievementShareCardArtifact artifact);

/// User-selected local file storage for f34 share cards.
///
/// This deliberately mirrors the existing export store's Android document
/// channel and desktop save flow. It creates a temporary file only after a
/// non-Android destination has been selected, and always removes that file.
final class FileSelectorShareCardStore implements AchievementShareCardStore {
  const FileSelectorShareCardStore({this.isAndroid, this.androidSaver});

  static const _androidChannel = MethodChannel('com.lexiquest.app/export');

  final bool? isAndroid;
  final AndroidShareCardSaver? androidSaver;

  bool get _usesAndroidDocumentPicker => isAndroid ?? Platform.isAndroid;

  @override
  Future<AchievementShareCardStoreResult> selectDestinationAndSave(
    AchievementShareCardArtifact artifact,
  ) async {
    _validateArtifact(artifact);
    return _usesAndroidDocumentPicker
        ? _saveOnAndroid(artifact)
        : _saveWithFileSelector(artifact);
  }

  Future<AchievementShareCardStoreResult> _saveOnAndroid(
    AchievementShareCardArtifact artifact,
  ) async {
    try {
      final destination =
          await (androidSaver ?? _saveWithAndroidDocumentPicker)(artifact);
      if (destination == null) {
        return const AchievementShareCardStoreResult.cancelled();
      }
      return AchievementShareCardStoreResult.saved(destination: destination);
    } on AchievementShareCardException {
      rethrow;
    } on PlatformException {
      throw const AchievementShareCardException(
        AchievementShareCardFailureCode.writeFailed,
      );
    } catch (_) {
      throw const AchievementShareCardException(
        AchievementShareCardFailureCode.writeFailed,
      );
    }
  }

  Future<AchievementShareCardStoreResult> _saveWithFileSelector(
    AchievementShareCardArtifact artifact,
  ) async {
    final destination = await getSaveLocation(
      suggestedName: artifact.suggestedFileName,
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: 'achievement share card',
          extensions: const <String>['svg'],
          mimeTypes: <String>[artifact.mimeType],
        ),
      ],
    );
    if (destination == null) {
      return const AchievementShareCardStoreResult.cancelled();
    }
    File? partial;
    try {
      final temporaryDirectory = await getTemporaryDirectory();
      partial = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}'
        '${artifact.suggestedFileName}.partial',
      );
      if (await partial.exists()) await partial.delete();
      await partial.writeAsBytes(artifact.bytes, flush: true);
      await XFile(
        partial.path,
        mimeType: artifact.mimeType,
      ).saveTo(destination.path);
      return AchievementShareCardStoreResult.saved(
        destination: destination.path,
      );
    } on FileSystemException {
      throw const AchievementShareCardException(
        AchievementShareCardFailureCode.writeFailed,
      );
    } catch (_) {
      throw const AchievementShareCardException(
        AchievementShareCardFailureCode.writeFailed,
      );
    } finally {
      if (partial != null && await partial.exists()) {
        await partial.delete();
      }
    }
  }

  Future<String?> _saveWithAndroidDocumentPicker(
    AchievementShareCardArtifact artifact,
  ) {
    return _androidChannel
        .invokeMethod<String>('saveExportFile', <String, Object?>{
          'suggestedName': artifact.suggestedFileName,
          'mimeType': artifact.mimeType,
          'bytes': artifact.bytes,
        });
  }

  void _validateArtifact(AchievementShareCardArtifact artifact) {
    final validId = RegExp(
      r'^[a-z][a-z0-9_]{0,63}$',
    ).hasMatch(artifact.achievementId);
    final validTitle =
        artifact.title.isNotEmpty &&
        artifact.title == artifact.title.trim() &&
        artifact.title.runes.length <= 128 &&
        !artifact.title.runes.any((rune) => rune < 0x20 || rune == 0x7f);
    final expectedName =
        'lexiquest-${artifact.achievementId}-v${artifact.definitionVersion}.svg';
    if (!validId ||
        artifact.definitionVersion <= 0 ||
        !validTitle ||
        !artifact.unlockedAtUtc.isUtc ||
        artifact.unlockedAtUtc.millisecondsSinceEpoch < 0 ||
        artifact.suggestedFileName != expectedName ||
        artifact.mimeType != 'image/svg+xml' ||
        artifact.bytes.isEmpty ||
        artifact.bytes.length > 1024 * 1024) {
      throw const AchievementShareCardException(
        AchievementShareCardFailureCode.invalidArtifact,
      );
    }
  }
}
