import 'dart:typed_data';
import 'voice_audio_cache.dart';

/// Ephemeral cache owned by one owner-generation capability. All provider
/// engines share this aggregate bound; whole lessons are evicted in LRU order.
final class LessonAudioCache {
  LessonAudioCache({
    required this.requireCurrent,
    this.maxLessons = 10,
    this.maxBytes = 20 * 1024 * 1024,
  }) {
    if (maxLessons < 1 || maxBytes < 1) {
      throw ArgumentError('Invalid cache bound');
    }
  }
  final Future<void> Function() requireCurrent;
  final int maxLessons, maxBytes;
  final _entries = <String, Map<VoiceAudioCacheKey, Uint8List>>{};
  final _versions = <String, int>{};
  bool _retired = false;
  int get totalBytes =>
      _entries.values.expand((v) => v.values).fold(0, (n, b) => n + b.length);
  int get lessonCount => _entries.length;
  VoiceAudioCache lesson(String id) {
    if (_retired || id.isEmpty) throw StateError('Audio cache retired');
    return _LessonScope(this, id, _versions[id] ?? 0);
  }

  Future<void> _fence(String id, int version) async {
    void check() {
      if (_retired || (_versions[id] ?? 0) != version) {
        throw StateError('Audio cache retired');
      }
    }

    check();
    await requireCurrent();
    check();
  }

  Future<void> deleteLesson(String id) async {
    _versions[id] = (_versions[id] ?? 0) + 1;
    _entries.remove(id);
  }

  void retire() {
    _retired = true;
    _entries.clear();
  }
}

final class _LessonScope implements VoiceAudioCache {
  const _LessonScope(this.owner, this.id, this.version);
  final LessonAudioCache owner;
  final String id;
  final int version;
  @override
  Future<Uint8List?> get(VoiceAudioCacheKey key) async {
    await owner._fence(id, version);
    final entry = owner._entries.remove(id);
    if (entry == null) return null;
    owner._entries[id] = entry;
    final bytes = entry[key];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> put(VoiceAudioCacheKey key, Uint8List bytes) async {
    // Copy before awaiting validation so caller mutation cannot change payload.
    if (bytes.isEmpty) throw ArgumentError('Empty audio payload');
    if (bytes.length > owner.maxBytes) {
      await owner._fence(id, version);
      return;
    }
    final copy = Uint8List.fromList(bytes);
    await owner._fence(id, version);
    final entry =
        owner._entries.remove(id) ?? <VoiceAudioCacheKey, Uint8List>{};
    entry[key] = copy;
    owner._entries[id] = entry;
    while (owner.lessonCount > owner.maxLessons ||
        owner.totalBytes > owner.maxBytes) {
      owner._entries.remove(owner._entries.keys.first);
    }
  }

  @override
  Future<void> clear() => owner.deleteLesson(id);
}
