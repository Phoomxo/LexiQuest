import 'dart:typed_data';

import 'voice_models.dart';
import 'voice_provider_descriptor.dart';

/// Immutable synthesized audio with provider-neutral provenance.
final class VoiceAudio {
  VoiceAudio({
    required Uint8List bytes,
    required this.requestId,
    required this.engine,
    required this.modelVersion,
    required this.sampleRate,
  }) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  final String requestId;
  final VoiceEngine engine;
  final String modelVersion;
  final int sampleRate;

  Uint8List get bytes => Uint8List.fromList(_bytes);
}

/// Boundary implemented by every provider that synthesizes audio bytes.
abstract interface class VoiceSynthesisProvider {
  VoiceProviderDescriptor get descriptor;

  Future<VoiceAudio> synthesize(VoiceRequest request);
}
