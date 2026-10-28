import 'dart:io';

import 'package:crypto/crypto.dart';

import 'standard_voice_pack_download_manager.dart';
import 'standard_voice_pack_manifest.dart';
import 'voice_capability.dart';
import 'voice_models.dart';
import 'voice_provider_descriptor.dart';
import 'voice_synthesis_provider.dart';

const _unavailableFailure = VoiceFailure(
  category: VoiceFailureCategory.modelUnavailable,
  message: 'Verified offline speech is unavailable.',
);
const _checksumFailure = VoiceFailure(
  category: VoiceFailureCategory.checksumMismatch,
  message: 'Offline speech failed integrity verification.',
);

final class InstalledVoicePackProvider implements VoiceSynthesisProvider {
  InstalledVoicePackProvider(this._installed)
    : _byContentId = {
        for (final file in _installed.manifest.files) file.contentId: file,
      };

  final InstalledStandardVoicePack _installed;
  final Map<String, StandardVoicePackFile> _byContentId;

  static final VoiceProviderDescriptor _descriptor = VoiceProviderDescriptor(
    engine: VoiceEngine.offlinePack,
    capabilities: const {VoiceCapability.standardTargetSpeech},
    privacyScope: VoicePrivacyScope.standardContent,
    allowsStandardCache: true,
  );

  @override
  VoiceProviderDescriptor get descriptor => _descriptor;

  @override
  Future<VoiceAudio> synthesize(VoiceRequest request) async {
    if (!descriptor.supports(request.capability) ||
        request.privacyScope != VoicePrivacyScope.standardContent) {
      throw _unavailableFailure;
    }
    final packFile = _byContentId[request.contentId];
    if (packFile == null || !packFile.matchesText(request.text)) {
      throw _unavailableFailure;
    }
    final file = File(_installed.pathFor(packFile.relativePath));
    if (!await file.exists() || await file.length() != packFile.byteSize) {
      throw _checksumFailure;
    }
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != packFile.sha256) {
      throw _checksumFailure;
    }
    return VoiceAudio(
      bytes: bytes,
      requestId: 'pack:${_installed.manifest.recordId}:${packFile.contentId}',
      engine: VoiceEngine.offlinePack,
      modelVersion:
          '${_installed.manifest.recordId}:'
          '${_installed.manifest.modelVersion}',
      sampleRate: 48000,
    );
  }
}
