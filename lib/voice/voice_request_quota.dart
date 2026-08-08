import 'voice_models.dart';

const _quotaFailure = VoiceFailure(
  category: VoiceFailureCategory.rateLimited,
  message: 'The dynamic voice session quota has been reached.',
);

final class VoiceRequestQuota {
  VoiceRequestQuota({
    required this.maxRequests,
    required this.maxCharacters,
    this.maxConcurrent = 1,
  }) : assert(maxRequests > 0),
       assert(maxCharacters > 0),
       assert(maxConcurrent > 0);

  final int maxRequests;
  final int maxCharacters;
  final int maxConcurrent;
  int _requests = 0;
  int _characters = 0;
  int _active = 0;

  Future<T> run<T>(VoiceRequest request, Future<T> Function() operation) async {
    if (_active >= maxConcurrent ||
        _requests >= maxRequests ||
        _characters + request.text.length > maxCharacters) {
      throw _quotaFailure;
    }
    _requests++;
    _characters += request.text.length;
    _active++;
    try {
      return await operation();
    } finally {
      _active--;
    }
  }

  void reset() {
    if (_active != 0) {
      throw StateError('Cannot reset voice quota while requests are active.');
    }
    _requests = 0;
    _characters = 0;
  }
}
