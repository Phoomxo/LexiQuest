import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/ai/ai_service_factory.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/voice/voice_auth_token_provider.dart';

void main() {
  final config = AppConfig.fromValues(
    voiceApiUrl: 'https://voice.example.invalid',
    aiApiUrl: 'https://ai.example.invalid',
    isDebug: false,
  );

  test(
    'managed service forwards the immutable identity and owns one client close',
    () async {
      http.Request? sent;
      final client = _Client((request) async {
        sent = request;
        return _response();
      });
      final service = AiServiceFactory.create(
        config: config,
        client: client,
        firebaseTokenReader: _Token((_) async => 'synthetic-token'),
      );
      final request = ContentRequest.create(
        text: 'cat',
        kind: ContentKind.sentence,
      );
      expect((await service.generate(request)).text, 'The cat sleeps.');
      expect(sent!.headers['idempotency-key'], request.operationId);
      expect((jsonDecode(sent!.body) as Map).keys.toSet(), {
        'text',
        'kind',
        'cefr',
        'language',
      });
      final firstClose = service.dispose();
      final secondClose = service.dispose();
      await Future.wait([firstClose, secondClose]);
      expect(client.closes, 1);
      await expectLater(
        service.generate(request),
        throwsA(
          isA<AiFailure>().having(
            (failure) => failure.category,
            'category',
            AiFailureCategory.configuration,
          ),
        ),
      );
    },
  );

  test(
    'managed service checks the supplied auth generation after its token await',
    () async {
      final pending = Completer<String?>();
      Object binding = ('synthetic-a', 0);
      var posts = 0;
      final client = _Client((_) async {
        posts++;
        return _response();
      });
      final service = AiServiceFactory.create(
        config: config,
        client: client,
        firebaseTokenReader: _Token((_) => pending.future),
        readAuthBinding: () => binding,
      );
      addTearDown(service.dispose);
      final result = service.generate(
        ContentRequest.create(text: 'cat', kind: ContentKind.sentence),
      );
      binding = ('synthetic-b', 1);
      binding = ('synthetic-a', 2);
      pending.complete('synthetic-token');
      await expectLater(
        result,
        throwsA(
          isA<AiFailure>().having(
            (failure) => failure.category,
            'category',
            AiFailureCategory.cancelled,
          ),
        ),
      );
      expect(posts, 0);
    },
  );
}

http.Response _response() => http.Response(
  jsonEncode({
    'text': 'The cat sleeps.',
    'kind': 'sentence',
    'cefr': 'a2',
    'language': 'en',
    'model_version': 'synthetic-model',
    'cached': false,
  }),
  200,
);

final class _Token implements FirebaseTokenReader {
  _Token(this.read);
  final Future<String?> Function(bool forceRefresh) read;
  @override
  Future<String?> readIdToken({required bool forceRefresh}) =>
      read(forceRefresh);
}

final class _Client extends MockClient {
  _Client(super.handler);
  int closes = 0;
  @override
  void close() {
    closes++;
    super.close();
  }
}
