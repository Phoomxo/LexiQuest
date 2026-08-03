/// Voice Use Cases — screen-facing boundary for all speech synthesis.
///
/// Screens MUST use this class instead of importing VoiceProvider directly.
/// This ensures a single enforcement point for consent, quota, logging, and
/// future policy changes.
///
/// Screens get this from [AppDependenciesScope] or from constructor injection
/// in tests.
library;

import '../../../voice/voice_models.dart';
import '../../../voice/voice_provider.dart';
import '../../../voice/voice_service_factory.dart';

final class VoiceUseCases {
  /// Creates a [VoiceUseCases] wrapping the given [provider].
  ///
  /// Pass a concrete provider in production; pass a [FakeVoiceProvider] in
  /// widget tests.
  const VoiceUseCases(this._provider);

  /// Creates a [VoiceUseCases] with a lazily-created default provider.
  ///
  /// Used by screens when no provider was injected via [AppDependencies].
  factory VoiceUseCases.createDefault() =>
      VoiceUseCases(VoiceServiceFactory.create());

  final VoiceProvider _provider;

  /// Synthesise [request] and return the playback result.
  Future<VoicePlaybackResult> speak(VoiceRequest request) =>
      _provider.speak(request);

  /// Stop any currently-playing speech.
  Future<void> stop() => _provider.stop();

  /// Disposes the underlying provider if [owns] is true and the provider
  /// implements [ManagedVoiceService].
  ///
  /// Call from a screen's [State.dispose] when the screen created the provider
  /// itself (i.e. [owns] == true). Safe to call when [owns] is false or when
  /// the provider is not a [ManagedVoiceService].
  void disposeIfOwned(bool owns) {
    if (owns && _provider is ManagedVoiceService) {
      _provider.dispose();
    }
  }

  /// Access the underlying provider when a legacy service requires a raw
  /// [VoiceProvider] (e.g. [BackgroundAudioPlayerService]).
  VoiceProvider get provider => _provider;
}
