import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'voice_capability.dart';
import 'voice_models.dart';
import 'voice_provider_descriptor.dart';
import 'voice_synthesis_provider.dart';

const _missingAssetFailure = VoiceFailure(
  category: VoiceFailureCategory.modelUnavailable,
  message: 'Bundled voice audio is unavailable.',
);

/// Provides verified, pre-rendered standard speech from the Flutter bundle.
final class BundledVoiceAssetProvider implements VoiceSynthesisProvider {
  const BundledVoiceAssetProvider({
    this.assetPrefix = 'assets/audio/omni_voice',
    this.bundle,
  });

  static final VoiceProviderDescriptor _descriptor = VoiceProviderDescriptor(
    engine: VoiceEngine.offlinePack,
    capabilities: const <VoiceCapability>{VoiceCapability.standardTargetSpeech},
    privacyScope: VoicePrivacyScope.standardContent,
    allowsStandardCache: true,
  );

  final String assetPrefix;
  final AssetBundle? bundle;

  AssetBundle get _activeBundle => bundle ?? rootBundle;

  @override
  VoiceProviderDescriptor get descriptor => _descriptor;

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
  Future<VoiceAudio> synthesize(VoiceRequest request) async {
    if (!descriptor.supports(request.capability) ||
        request.privacyScope != descriptor.privacyScope) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.unsupportedCapability,
        message: 'Bundled voice audio does not support this request.',
      );
    }

    final path = getAssetPath(request);
    try {
      final bytes = await _activeBundle.load(path);
      final list = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      return VoiceAudio(
        bytes: list,
        requestId: 'asset_${request.contentId}',
        engine: VoiceEngine.offlinePack,
        modelVersion: 'offline_v1',
        sampleRate: 24000,
      );
    } on VoiceFailure {
      rethrow;
    } on Object {
      throw _missingAssetFailure;
    }
  }
}
