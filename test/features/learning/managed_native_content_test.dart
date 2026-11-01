import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/ai/content_provider.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/voice/voice_auth_token_provider.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  for (final mode in ['sentenceScramble', 'clozeTyped', 'clozeChoice']) {
    test(
      '$mode uses a fresh owned generation identity and preserves it across auth retry without learning writes',
      () async {
        final storage = await ConfiguredQuizHarness.open();
        addTearDown(storage.close);
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          if (requests.length.isOdd) {
            return http.Response('{"detail":{"code":"UNAUTHENTICATED"}}', 401);
          }
          return _generated(request);
        });
        addTearDown(client.close);
        final learning = _learning(
          storage,
          client,
          _Token((_) async => 'synthetic-token'),
        );
        final before = await storage.snapshot();
        final first = await _prepare(learning, mode, () => true);
        final second = await _prepare(learning, mode, () => true);
        expect(first, isNotNull);
        expect(second, isNotNull);
        expect(first!.ownerId, configuredOwnerId);
        expect(first.id, isNot(second!.id));
        expect(requests, hasLength(4));
        final ids = requests
            .map((request) => request.headers['idempotency-key'])
            .toList();
        expect(ids.every((id) => id != null && id.length == 36), isTrue);
        expect(ids[0], ids[1]);
        expect(ids[2], ids[3]);
        expect(ids[0], isNot(ids[2]));
        expect(requests.map((request) => request.body).toSet(), hasLength(1));
        expect(await storage.snapshot(), before);
      },
    );
  }

  for (final (status, code, category) in [
    (402, 'BILLING_ENTITLEMENT_REQUIRED', AiFailureCategory.paymentRequired),
    (429, 'BILLING_QUOTA_EXHAUSTED', AiFailureCategory.quotaExhausted),
    (409, 'BILLING_OPERATION_UNCERTAIN', AiFailureCategory.operationUncertain),
  ]) {
    test(
      'native generation $code creates no session, reward, Research or outbox fact',
      () async {
        final storage = await ConfiguredQuizHarness.open();
        addTearDown(storage.close);
        var requests = 0;
        final client = MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode({
              'detail': {'code': code, 'message': 'PRIVATE-RESPONSE'},
            }),
            status,
          );
        });
        addTearDown(client.close);
        final learning = _learning(
          storage,
          client,
          _Token((_) async => 'synthetic-token'),
        );
        final before = await storage.snapshot();
        for (final mode in ['sentenceScramble', 'clozeTyped', 'clozeChoice']) {
          await expectLater(
            _prepare(learning, mode, () => true),
            throwsA(
              isA<AiFailure>()
                  .having((failure) => failure.category, 'category', category)
                  .having(
                    (failure) => failure.toString(),
                    'safe error',
                    isNot(contains('PRIVATE-RESPONSE')),
                  ),
            ),
          );
        }
        expect(requests, 3);
        expect(await storage.snapshot(), before);
      },
    );
  }

  for (final mode in ['sentenceScramble', 'clozeTyped', 'clozeChoice']) {
    test(
      '$mode passes its retired caller lease to the paid HTTP boundary',
      () async {
        final storage = await ConfiguredQuizHarness.open();
        final requested = Completer<void>();
        final pending = Completer<String>();
        var current = true;
        var posts = 0;
        final client = MockClient((request) async {
          posts++;
          return _generated(request);
        });
        final learning = _learning(
          storage,
          client,
          _Token((_) {
            if (!requested.isCompleted) requested.complete();
            return pending.future;
          }),
        );
        final before = await storage.snapshot();
        final outcome = _prepare(learning, mode, () => current).then<Object?>(
          (value) => value,
          onError: (Object error, StackTrace _) => error,
        );
        try {
          await requested.future.timeout(const Duration(seconds: 3));
          current = false;
          pending.complete('synthetic-token');
          expect(
            await outcome,
            isA<AiFailure>().having(
              (failure) => failure.category,
              'category',
              AiFailureCategory.cancelled,
            ),
          );
          expect(posts, 0);
          expect(await storage.snapshot(), before);
        } finally {
          current = false;
          if (!pending.isCompleted) pending.complete('synthetic-token');
          await outcome.timeout(const Duration(seconds: 3));
          client.close();
          await storage.close();
        }
      },
    );
  }
}

LearningUseCases _learning(
  ConfiguredQuizHarness storage,
  http.Client client,
  VoiceAuthTokenProvider token,
) {
  var nextId = 0;
  return LearningUseCases(
    owners: storage.owners,
    repository: DriftLearningRepository(
      storage.database,
      ownerWrites: storage.ownerWrites,
    ),
    generateId: () => 'synthetic-managed-native-${++nextId}',
    nowUtc: () => storage.now,
    buildInfo: const AppBuildInfo(
      version: 'synthetic',
      buildId: 'managed-native',
    ),
    contentProvider: HttpContentProvider(
      client: client,
      authTokenProvider: token,
      baseUri: Uri.parse('https://ai.example.invalid'),
    ),
  );
}

Future<AcceptedNativeExercise?> _prepare(
  LearningUseCases learning,
  String mode,
  bool Function() current,
) => switch (mode) {
  'sentenceScramble' => learning.prepareSentenceScramble(
    categoryId: configuredCategoryId,
    stillCurrent: current,
  ),
  'clozeTyped' => learning.prepareCloze(
    categoryId: configuredCategoryId,
    variant: ClozeVariant.typed,
    stillCurrent: current,
  ),
  'clozeChoice' => learning.prepareCloze(
    categoryId: configuredCategoryId,
    variant: ClozeVariant.choice,
    stillCurrent: current,
  ),
  _ => throw StateError('Unknown synthetic mode'),
};

http.Response _generated(http.Request request) {
  final body = jsonDecode(request.body) as Map;
  return http.Response(
    jsonEncode({
      'text': 'We visit the ${body['text']} today.',
      'kind': 'sentence',
      'cefr': 'a2',
      'language': 'en',
      'model_version': 'synthetic-managed-v1',
      'cached': false,
    }),
    200,
  );
}

final class _Token implements VoiceAuthTokenProvider {
  _Token(this.read);
  final Future<String> Function(bool forceRefresh) read;
  @override
  Future<String> getIdToken({bool forceRefresh = false}) => read(forceRefresh);
}
