import 'voice_models.dart';

final class VoiceProviderRegistry<T> {
  VoiceProviderRegistry(Iterable<MapEntry<VoiceEngine, T>> entries)
    : _providers = _build(entries);

  final Map<VoiceEngine, T> _providers;

  Set<VoiceEngine> get engines =>
      Set<VoiceEngine>.unmodifiable(_providers.keys);

  T? providerFor(VoiceEngine engine) => _providers[engine];

  static Map<VoiceEngine, T> _build<T>(
    Iterable<MapEntry<VoiceEngine, T>> entries,
  ) {
    final providers = <VoiceEngine, T>{};
    for (final entry in entries) {
      if (providers.containsKey(entry.key)) {
        throw ArgumentError.value(entry.key, 'entries', 'duplicate engine');
      }
      providers[entry.key] = entry.value;
    }
    if (providers.isEmpty) {
      throw ArgumentError.value(entries, 'entries', 'must not be empty');
    }
    return Map<VoiceEngine, T>.unmodifiable(providers);
  }
}
