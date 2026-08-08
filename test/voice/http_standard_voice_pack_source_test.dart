import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/voice/http_standard_voice_pack_source.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_download_manager.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

void main() {
  test('sends a bounded Range request and validates Content-Range', () async {
    late http.Request request;
    final source = HttpStandardVoicePackSource(
      MockClient((value) async {
        request = value;
        return http.Response.bytes(
          utf8.encode('bytes'),
          206,
          headers: {'content-range': 'bytes 4-8/9'},
        );
      }),
    );

    final response = await source.open(
      Uri.parse('https://assets.example.com/cat.wav'),
      start: 4,
    );

    expect(request.headers['range'], 'bytes=4-');
    expect(response.contentRangeStart, 4);
    expect(
      await response.bytes.expand((chunk) => chunk).toList(),
      utf8.encode('bytes'),
    );
  });

  test('rejects non-HTTPS and mismatched ranges', () async {
    final source = HttpStandardVoicePackSource(
      MockClient(
        (_) async => http.Response(
          'bad',
          206,
          headers: {'content-range': 'bytes 0-2/3'},
        ),
      ),
    );

    for (final uri in [
      Uri.parse('http://assets.example.com/cat.wav'),
      Uri.parse('https://assets.example.com/cat.wav'),
    ]) {
      await expectLater(
        source.open(uri, start: 4),
        throwsA(isA<VoiceFailure>()),
      );
    }
  });

  test('cancellation prevents network access', () async {
    var sends = 0;
    final token = StandardVoicePackCancellation()..cancel();
    final source = HttpStandardVoicePackSource(
      MockClient((_) async {
        sends++;
        return http.Response('', 200);
      }),
    );

    await expectLater(
      source.open(
        Uri.parse('https://assets.example.com/cat.wav'),
        start: 0,
        cancellation: token,
      ),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.cancelled,
        ),
      ),
    );
    expect(sends, 0);
  });
}
