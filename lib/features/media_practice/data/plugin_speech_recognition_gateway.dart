import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../domain/media_practice_contracts.dart';

final class PluginSpeechRecognitionGateway implements SpeechRecognitionGateway {
  PluginSpeechRecognitionGateway({
    SpeechToText? speech,
    DateTime Function()? nowUtc,
  }) : _speech = speech ?? SpeechToText(),
       _nowUtc = nowUtc ?? _systemNowUtc;

  final SpeechToText _speech;
  final DateTime Function() _nowUtc;
  SpeechFailureCallback? _onFailure;
  void Function(String status)? _onStatus;
  bool _initialized = false;

  static DateTime _systemNowUtc() => DateTime.now().toUtc();

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<MediaPermissionState> requestPermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted || status.isLimited) {
      return MediaPermissionState.granted;
    }
    if (status.isPermanentlyDenied) {
      return MediaPermissionState.permanentlyDenied;
    }
    if (status.isRestricted) return MediaPermissionState.restricted;
    if (status.isDenied) return MediaPermissionState.denied;
    return MediaPermissionState.unavailable;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    _onFailure = onFailure;
    _onStatus = onStatus;
    if (_initialized) return;
    final available = await _speech.initialize(
      onError: _handleError,
      onStatus: _handleStatus,
      debugLogging: false,
    );
    if (!available) {
      throw const SpeechPracticeException(SpeechFailureCode.unavailable);
    }
    _initialized = true;
  }

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    if (!_initialized) {
      throw const SpeechPracticeException(SpeechFailureCode.unavailable);
    }
    await _speech.listen(
      onResult: (result) => onEvent(_event(result, locale)),
      listenOptions: SpeechListenOptions(
        localeId: locale,
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        onDevice: false,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();

  SpeechRecognitionEvent _event(SpeechRecognitionResult result, String locale) {
    final confidence = result.hasConfidenceRating
        ? result.confidence.clamp(0.0, 1.0)
        : null;
    return SpeechRecognitionEvent(
      transcript: result.recognizedWords,
      isFinal: result.finalResult,
      recognizedAtUtc: _nowUtc(),
      engine: 'platform-speech-recognizer',
      locale: locale,
      recognitionConfidence: confidence,
    );
  }

  void _handleError(SpeechRecognitionError error) {
    final code = switch (error.errorMsg) {
      'error_no_match' || 'error_speech_timeout' => SpeechFailureCode.noMatch,
      'error_permission' => SpeechFailureCode.permissionDenied,
      _ => SpeechFailureCode.engine,
    };
    _onFailure?.call(code);
  }

  void _handleStatus(String status) => _onStatus?.call(status);
}
