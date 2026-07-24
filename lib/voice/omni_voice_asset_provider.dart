import 'dart:typed_data';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'omni_voice_provider.dart';
import 'voice_models.dart';

/// Provides pre-rendered offline OmniVoice audio assets from Flutter app bundles
/// when network synthesis is unavailable or offline mode is requested.
final class OmniVoiceAssetProvider implements OmniVoiceSynthesizer {
  const OmniVoiceAssetProvider({
    this.assetPrefix = 'assets/audio/omni_voice',
    this.bundle,
  });

  final String assetPrefix;
  final AssetBundle? bundle;

  AssetBundle get _activeBundle => bundle ?? rootBundle;

  /// Builds a canonical asset path for a given [VoiceRequest].
  String getAssetPath(VoiceRequest request) {
    final sanitizedContent = request.contentId
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .toLowerCase();
    final sanitizedVoice = request.voiceId
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .toLowerCase();
    return '$assetPrefix/${sanitizedVoice}_$sanitizedContent.wav';
  }

  @override
  Future<OmniVoiceAudio> synthesize(VoiceRequest request) async {
    final path = getAssetPath(request);
    try {
      final bytes = await _activeBundle.load(path);
      final list = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      return OmniVoiceAudio(
        bytes: list,
        requestId: 'asset_${request.contentId}',
        engine: 'omni_voice_offline_asset',
        modelVersion: 'offline_v1',
        sampleRate: 24000,
      );
    } catch (_) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.network,
        message: 'Offline OmniVoice asset not found in bundle.',
      );
    }
  }
}
