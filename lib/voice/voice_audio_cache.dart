import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'voice_capability.dart';
import 'voice_models.dart';

/// Provider-neutral boundary for a bounded WAV payload cache used by the hybrid
/// voice service to avoid re-synthesizing identical OmniVoice requests.
abstract interface class VoiceAudioCache {
  Future<Uint8List?> get(VoiceAudioCacheKey key);

  Future<void> put(VoiceAudioCacheKey key, Uint8List bytes);

  Future<void> clear();
}

const _missingModelVersionFailure = VoiceFailure(
  category: VoiceFailureCategory.validation,
  message: 'Voice audio cache model version is missing.',
);

const _missingPayloadFailure = VoiceFailure(
  category: VoiceFailureCategory.validation,
  message: 'Voice audio cache payload is missing.',
);

const _transientCacheFailure = VoiceFailure(
  category: VoiceFailureCategory.validation,
  message: 'Participant-transient audio cannot use the standard cache.',
);

/// Immutable identity for a cached WAV built from the synthesis-relevant slice
/// of a [VoiceRequest], provider engine, and model version that produced it.
final class VoiceAudioCacheKey {
  const VoiceAudioCacheKey._({
    required this.text,
    required this.language,
    required this.voiceId,
    required this.speed,
    required this.engine,
    required this.modelVersion,
  });

  final String text;
  final String language;
  final String voiceId;
  final double speed;
  final VoiceEngine engine;
  final String modelVersion;

  factory VoiceAudioCacheKey.create({
    required VoiceRequest request,
    required VoiceEngine engine,
    required String modelVersion,
  }) {
    if (request.privacyScope != VoicePrivacyScope.standardContent) {
      throw _transientCacheFailure;
    }
    final trimmedModelVersion = modelVersion.trim();
    if (trimmedModelVersion.isEmpty) {
      throw _missingModelVersionFailure;
    }
    return VoiceAudioCacheKey._(
      text: request.text,
      language: request.language,
      voiceId: request.voiceId,
      speed: request.speed,
      engine: engine,
      modelVersion: trimmedModelVersion,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VoiceAudioCacheKey &&
        other.text == text &&
        other.language == language &&
        other.voiceId == voiceId &&
        other.speed == speed &&
        other.engine == engine &&
        other.modelVersion == modelVersion;
  }

  @override
  int get hashCode =>
      Object.hash(text, language, voiceId, speed, engine, modelVersion);
}

/// Bounded, insertion-ordered (LRU) in-memory [VoiceAudioCache].
final class MemoryVoiceAudioCache implements VoiceAudioCache {
  MemoryVoiceAudioCache({required this.maxEntries, required this.maxBytes}) {
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
    if (maxBytes <= 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be positive');
    }
  }

  final int maxEntries;
  final int maxBytes;

  final LinkedHashMap<VoiceAudioCacheKey, Uint8List> _entries =
      LinkedHashMap<VoiceAudioCacheKey, Uint8List>();
  int _totalBytes = 0;

  /// Number of entries currently held.
  int get entryCount => _entries.length;

  /// Total bytes currently held.
  int get totalBytes => _totalBytes;

  @override
  Future<Uint8List?> get(VoiceAudioCacheKey key) async {
    final bytes = _entries.remove(key);
    if (bytes == null) {
      return null;
    }
    _entries[key] = bytes;
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> put(VoiceAudioCacheKey key, Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw _missingPayloadFailure;
    }
    final existing = _entries.remove(key);
    if (existing != null) {
      _totalBytes -= existing.length;
    }
    if (bytes.length > maxBytes) {
      return;
    }
    final stored = Uint8List.fromList(bytes);
    _entries[key] = stored;
    _totalBytes += stored.length;
    _evictKeeping(key);
  }

  @override
  Future<void> clear() async {
    _entries.clear();
    _totalBytes = 0;
  }

  void _evictKeeping(VoiceAudioCacheKey guard) {
    final keys = _entries.keys.toList(growable: false);
    for (final key in keys) {
      if (_entries.length <= maxEntries && _totalBytes <= maxBytes) {
        return;
      }
      if (key == guard) {
        continue;
      }
      final removed = _entries.remove(key);
      if (removed != null) {
        _totalBytes -= removed.length;
      }
    }
  }
}
