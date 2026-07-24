import 'dart:io';
import 'dart:typed_data';

/// Persistent local disk audio cache for saving WAV audio bytes offline.
class PersistentAudioCache {
  final Directory storageDirectory;

  PersistentAudioCache(this.storageDirectory);

  File _getFileForKey(String key) {
    final safeKey = key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final filePath =
        '${storageDirectory.path}${Platform.pathSeparator}$safeKey.wav';
    return File(filePath);
  }

  Future<bool> containsKey(String key) async {
    final file = _getFileForKey(key);
    return await file.exists();
  }

  Future<Uint8List?> get(String key) async {
    try {
      final file = _getFileForKey(key);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> put(String key, Uint8List bytes) async {
    try {
      if (!await storageDirectory.exists()) {
        await storageDirectory.create(recursive: true);
      }
      final file = _getFileForKey(key);
      await file.writeAsBytes(bytes);
    } catch (_) {
      // Disk cache errors swallow gracefully
    }
  }
}
