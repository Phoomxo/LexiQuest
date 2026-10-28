import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'standard_voice_pack_download_manager.dart';
import 'standard_voice_pack_manifest.dart';

final class FileStandardVoicePackStore {
  const FileStandardVoicePackStore(this.rootDirectory);

  final Future<Directory> Function() rootDirectory;

  Future<InstalledStandardVoicePack?> loadActive(String packId) async {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(packId)) {
      return null;
    }
    final root = await rootDirectory();
    final separator = Platform.pathSeparator;
    final marker = File('${root.path}$separator$packId.active');
    if (!await marker.exists()) return null;
    final version = (await marker.readAsString()).trim();
    if (!RegExp(r'^\d+\.\d+\.\d+(?:\+\d+)?$').hasMatch(version)) {
      await marker.delete();
      return null;
    }
    final directory = Directory('${root.path}$separator$packId@$version');
    final manifestFile = File('${directory.path}${separator}manifest.json');
    try {
      if (!await manifestFile.exists()) throw const FormatException();
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final manifest = StandardVoicePackManifest.fromJson(decoded);
      if (manifest.packId != packId || manifest.version != version) {
        throw const FormatException();
      }
      for (final descriptor in manifest.files) {
        final file = File(
          '${directory.path}$separator'
          '${descriptor.relativePath.replaceAll('/', separator)}',
        );
        if (!await file.exists() ||
            await file.length() != descriptor.byteSize) {
          throw const FormatException();
        }
        final digest = await file.openRead().transform(sha256).single;
        if (digest.toString() != descriptor.sha256) {
          throw const FormatException();
        }
      }
      return InstalledStandardVoicePack(
        rootPath: directory.path,
        manifest: manifest,
        activeMarkerPath: marker.path,
      );
    } on Object {
      if (await marker.exists()) await marker.delete();
      return null;
    }
  }
}
