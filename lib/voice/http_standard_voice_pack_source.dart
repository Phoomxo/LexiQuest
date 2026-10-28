import 'dart:async';

import 'package:http/http.dart' as http;

import 'standard_voice_pack_download_manager.dart';
import 'voice_models.dart';

const _networkFailure = VoiceFailure(
  category: VoiceFailureCategory.network,
  message: 'The voice pack could not be downloaded.',
);
const _timeoutFailure = VoiceFailure(
  category: VoiceFailureCategory.timeout,
  message: 'The voice pack download timed out.',
);
const _cancelledFailure = VoiceFailure(
  category: VoiceFailureCategory.cancelled,
  message: 'Voice pack installation was cancelled.',
);

final class HttpStandardVoicePackSource implements StandardVoicePackByteSource {
  const HttpStandardVoicePackSource(
    this._client, {
    this.timeout = const Duration(seconds: 30),
  });

  final http.Client _client;
  final Duration timeout;

  @override
  Future<StandardVoicePackByteResponse> open(
    Uri uri, {
    required int start,
    StandardVoicePackCancellation? cancellation,
  }) async {
    if (uri.scheme != 'https' || uri.host.isEmpty || start < 0) {
      throw _networkFailure;
    }
    if (cancellation?.isCancelled ?? false) throw _cancelledFailure;
    final request = http.Request('GET', uri);
    if (start > 0) request.headers['range'] = 'bytes=$start-';
    try {
      final response = await _client.send(request).timeout(timeout);
      final contentRangeStart = response.statusCode == 206
          ? _parseContentRangeStart(response.headers['content-range'])
          : null;
      if (response.statusCode == 206 && contentRangeStart != start) {
        throw _networkFailure;
      }
      return StandardVoicePackByteResponse(
        statusCode: response.statusCode,
        bytes: response.stream,
        contentRangeStart: contentRangeStart,
      );
    } on TimeoutException {
      throw _timeoutFailure;
    } on http.ClientException {
      throw _networkFailure;
    }
  }

  int? _parseContentRangeStart(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^bytes (\d+)-\d+/\d+$').firstMatch(value.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
