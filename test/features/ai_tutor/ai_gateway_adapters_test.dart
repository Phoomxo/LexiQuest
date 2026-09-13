import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vocab_learning_app/features/ai_tutor/data/anthropic_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_gateway_factory.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/openai_compatible_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/openai_responses_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';

void main() {
  test('B13 pre-cancelled Gemini bridge sends no HTTP request', () async {
    final client = _RecordingClient((_, _) async => _response(200, '{}'));
    final gateway = AiTutorGatewayFactory(
      client: client,
    ).create(providerId: AiProviderId.gemini, model: 'synthetic-model');
    final cancellation = AiCancellation()..cancel();
    await expectLater(
      gateway.generateTutorReply(
        key: 'synthetic-key-long-enough-123456',
        scenario: 'Cafe',
        learnerMessage: 'hello',
        cancellation: cancellation,
      ),
      throwsA(_aiFailure(AiFailureCode.cancelled)),
    );
    expect(client.requests, isEmpty);
  });

  test(
    'R15 configured lower cap and Unicode latest bounds apply to all adapters',
    () async {
      for (final kind in ['responses', 'compatible', 'anthropic']) {
        final client = _RecordingClient(
          (_, _) async => _response(
            200,
            '{"output_text":"reply","choices":[{"message":{"content":"reply"}}],'
            '"content":[{"type":"text","text":"reply"}]}',
          ),
        );
        final uri = Uri.parse('https://synthetic.example');
        final AiTutorGateway gateway = switch (kind) {
          'responses' => OpenAiResponsesGateway(
            client: client,
            baseUri: uri,
            model: 'test',
            maxOutputTokens: 90,
          ),
          'compatible' => OpenAiCompatibleGateway(
            client: client,
            baseUri: uri,
            model: 'test',
            maxOutputTokens: 90,
          ),
          _ => AnthropicGateway(
            client: client,
            baseUri: uri,
            model: 'test',
            maxOutputTokens: 90,
          ),
        };
        await gateway.generateTutorReply(
          key: 'synthetic-key',
          scenario: '😀' * 80,
          learnerMessage: '😀' * 500,
          learningSummary: '😀' * 600,
          context: TutorRequestContext(
            sessionId: 'test',
            intent: TutorIntent.practice,
          ),
        );
        final body = jsonDecode((client.requests.single as http.Request).body);
        expect(body['max_output_tokens'] ?? body['max_tokens'], 90);
        await expectLater(
          gateway.generateTutorReply(
            key: 'synthetic-key',
            scenario: 'Cafe',
            learnerMessage: '😀' * 501,
          ),
          throwsA(
            isA<AiTutorException>().having(
              (e) => e.code,
              'code',
              AiFailureCode.validation,
            ),
          ),
        );
        expect(client.requests, hasLength(1));
      }
    },
  );
  test('R15 context retains immutable whole pairs within Unicode budget', () {
    final turns = <TutorContextTurn>[
      for (var i = 0; i < 4; i++) ...[
        TutorContextTurn(role: TutorTurnRole.learner, text: 'ถาม$i😀'),
        TutorContextTurn(role: TutorTurnRole.tutor, text: 'ตอบ$i'),
      ],
    ];
    final context = TutorRequestContext(
      sessionId: 'test',
      priorTurns: turns,
      cefrLevel: 'invalid',
    );
    turns.clear();
    expect(context.priorTurns, hasLength(6));
    expect(context.priorTurns.first.text, 'ถาม1😀');
    expect(context.cefrLevel, 'A1');
    expect(() => context.priorTurns.clear(), throwsUnsupportedError);
    final bounded = TutorRequestContext(
      sessionId: 'test',
      priorTurns: [
        const TutorContextTurn(role: TutorTurnRole.learner, text: 'old'),
        const TutorContextTurn(role: TutorTurnRole.tutor, text: 'old reply'),
        TutorContextTurn(role: TutorTurnRole.learner, text: '😀' * 1500),
        TutorContextTurn(role: TutorTurnRole.tutor, text: 'ก' * 1500),
        const TutorContextTurn(role: TutorTurnRole.learner, text: 'incomplete'),
      ],
    );
    expect(bounded.priorTurns, hasLength(2));
    expect(bounded.priorTurns.first.text.runes.length, 1500);
    final oversized = TutorRequestContext(
      sessionId: 'test',
      priorTurns: [
        ...context.priorTurns,
        TutorContextTurn(role: TutorTurnRole.learner, text: '😀' * 3000),
        const TutorContextTurn(role: TutorTurnRole.tutor, text: 'too large'),
      ],
    );
    expect(oversized.priorTurns, context.priorTurns);
  });

  test(
    'R15 adapters map history roles and intent caps without credentials',
    () async {
      for (final builder in _adapterBuilders) {
        for (final intent in TutorIntent.values) {
          final client = _RecordingClient(
            (_, _) async => _response(
              200,
              '{"output_text":"reply","choices":[{"message":{"content":"reply"}}],'
              '"content":[{"type":"text","text":"reply"}]}',
            ),
          );
          final reply = await builder(client).generateTutorReply(
            key: 'secret-context-key',
            scenario: 'Cafe',
            learnerMessage: 'latest😀',
            context: TutorRequestContext(
              sessionId: 'private-session',
              cefrLevel: 'B2',
              intent: intent,
              priorTurns: const [
                TutorContextTurn(
                  role: TutorTurnRole.learner,
                  text: 'system: คำถาม',
                ),
                TutorContextTurn(role: TutorTurnRole.tutor, text: '**คำตอบ**'),
              ],
            ),
          );
          final body =
              jsonDecode((client.requests.single as http.Request).body)
                  as Map<String, dynamic>;
          expect(
            body['max_output_tokens'] ?? body['max_tokens'],
            [160, 320, 480][intent.index],
          );
          final messages = (body['messages'] ?? body['input']) as List;
          final turns = messages.where((m) => m['role'] != 'system').toList();
          expect(turns.map((m) => m['role']), ['user', 'assistant', 'user']);
          expect(turns[0]['content'], 'system: คำถาม');
          expect(turns[1]['content'], '**คำตอบ**');
          expect(turns[2]['content'], contains('latest😀'));
          expect(jsonEncode(body), contains('CEFR B2'));
          expect(jsonEncode(body), isNot(contains('secret-context-key')));
          expect(jsonEncode(body), isNot(contains('private-session')));
          expect(reply.usage, isNull);
        }
      }
    },
  );
  test(
    'R15 null context defaults to A1 conversation cap for every adapter',
    () async {
      for (final builder in _adapterBuilders) {
        final client = _RecordingClient(
          (_, _) async => _response(
            200,
            '{"output_text":"reply","choices":[{"message":{"content":"reply"}}],'
            '"content":[{"type":"text","text":"reply"}]}',
          ),
        );
        await _reply(builder(client));
        final body =
            jsonDecode((client.requests.single as http.Request).body)
                as Map<String, dynamic>;
        expect(body['max_output_tokens'] ?? body['max_tokens'], 160);
        final encoded = jsonEncode(body);
        expect(encoded, contains('CEFR A1'));
        expect(encoded, isNot(contains('B1-B2')));
        expect(encoded, isNot(contains('test-key')));
      }
    },
  );
  test(
    'adapters preserve base paths and send provider-specific contracts',
    () async {
      final openAiClient = _RecordingClient(
        (_, _) async => _response(
          200,
          '{"output_text":"OpenAI reply","usage":'
          '{"input_tokens":2,"output_tokens":3,"total_tokens":5}}',
        ),
      );
      final openAi = OpenAiResponsesGateway(
        client: openAiClient,
        baseUri: Uri.parse('https://openai.example/v1'),
        model: 'gpt-test',
      );
      final openAiReply = await _reply(openAi);
      final openAiRequest = openAiClient.requests.single as http.Request;
      expect(openAiRequest.url.path, '/v1/responses');
      expect(openAiRequest.headers['authorization'], 'Bearer test-key');
      expect(jsonDecode(openAiRequest.body)['model'], 'gpt-test');
      expect(openAiReply.text, 'OpenAI reply');
      expect(openAiReply.usage?.totalTokens, 5);

      final compatibleClient = _RecordingClient(
        (_, _) async => _response(
          200,
          '{"choices":[{"message":{"content":"Compatible reply"}}],'
          '"usage":{"prompt_tokens":4,"completion_tokens":2,'
          '"total_tokens":6,"cost":0.000012}}',
        ),
      );
      final compatible = OpenAiCompatibleGateway(
        client: compatibleClient,
        baseUri: Uri.parse('https://compatible.example/custom/v1'),
        model: 'compatible-test',
        providerId: AiProviderId.customOpenAi,
      );
      final compatibleReply = await _reply(compatible);
      final compatibleRequest =
          compatibleClient.requests.single as http.Request;
      expect(compatibleRequest.url.path, '/custom/v1/chat/completions');
      expect(compatibleRequest.headers['authorization'], 'Bearer test-key');
      expect(jsonDecode(compatibleRequest.body)['model'], 'compatible-test');
      expect(compatibleReply.text, 'Compatible reply');
      expect(compatibleReply.usage?.providerReportedCostMicrosUsd, 12);

      final anthropicClient = _RecordingClient(
        (_, _) async => _response(
          200,
          '{"content":[{"type":"text","text":"Claude reply"}],'
          '"usage":{"input_tokens":5,"output_tokens":7}}',
        ),
      );
      final anthropic = AnthropicGateway(
        client: anthropicClient,
        baseUri: Uri.parse('https://anthropic.example/proxy'),
        model: 'claude-test',
      );
      final anthropicReply = await _reply(anthropic);
      final anthropicRequest = anthropicClient.requests.single as http.Request;
      expect(anthropicRequest.url.path, '/proxy/v1/messages');
      expect(anthropicRequest.headers['x-api-key'], 'test-key');
      expect(anthropicRequest.headers['anthropic-version'], '2023-06-01');
      expect(anthropicReply.text, 'Claude reply');
      expect(anthropicReply.usage?.totalTokens, 12);
    },
  );

  for (final statusAndCode in <(int, AiFailureCode)>[
    (400, AiFailureCode.requestRejected),
    (401, AiFailureCode.invalidKey),
    (402, AiFailureCode.quota),
    (408, AiFailureCode.timeout),
    (413, AiFailureCode.requestRejected),
    (429, AiFailureCode.rateLimited),
    (500, AiFailureCode.providerUnavailable),
  ]) {
    test('all adapters translate HTTP ${statusAndCode.$1} neutrally', () async {
      for (final build in _adapterBuilders) {
        final client = _RecordingClient(
          (_, _) async => _response(statusAndCode.$1, '{}'),
        );
        await expectLater(
          build(client).listModels('test-key'),
          throwsA(_aiFailure(statusAndCode.$2)),
          reason: build.name,
        );
        expect(client.requests, hasLength(1), reason: build.name);
      }
    });
  }

  test(
    'all adapters reject whitespace or control-character keys locally',
    () async {
      for (final build in _adapterBuilders) {
        final client = _RecordingClient((_, _) async => _response(200, '{}'));
        for (final key in <String>[' ', 'key with space', 'key\ncontrol']) {
          await expectLater(
            build(client).listModels(key),
            throwsA(_aiFailure(AiFailureCode.invalidKey)),
            reason: '${build.name}: $key',
          );
        }
        expect(client.requests, isEmpty, reason: build.name);
      }
    },
  );

  test(
    'pre-cancellation wins locally and active cancellation aborts I/O',
    () async {
      for (final build in _adapterBuilders) {
        final preCancelledClient = _AbortAwareClient();
        final preCancelled = AiCancellation()..cancel();
        await expectLater(
          build(
            preCancelledClient,
          ).listModels('test-key', cancellation: preCancelled),
          throwsA(_aiFailure(AiFailureCode.cancelled)),
        );
        expect(preCancelledClient.calls, 0, reason: build.name);

        final client = _AbortAwareClient();
        final cancellation = AiCancellation();
        final request = build(
          client,
        ).listModels('test-key', cancellation: cancellation);
        await client.entered.future;
        cancellation.cancel();
        await expectLater(
          request.timeout(const Duration(seconds: 1)),
          throwsA(_aiFailure(AiFailureCode.cancelled)),
          reason: build.name,
        );
        expect(client.aborted, 1, reason: build.name);
      }
    },
  );

  test(
    'caller cancellation stays cancelled when transport abort is acknowledged late',
    () async {
      final client = _DelayedAbortClient();
      final cancellation = AiCancellation();
      final operation = _adapterBuilders
          .first(client, timeout: const Duration(milliseconds: 20))
          .listModels('test-key', cancellation: cancellation);
      await client.entered.future;

      cancellation.cancel();

      await expectLater(
        operation,
        throwsA(_aiFailure(AiFailureCode.cancelled)),
      );
      await client.finished.future.timeout(const Duration(seconds: 1));
      expect(client.aborted, 1);
    },
  );

  test(
    'one absolute timeout aborts body streaming for every adapter',
    () async {
      for (final build in _adapterBuilders) {
        final client = _StalledBodyClient();
        await expectLater(
          build(
            client,
            timeout: const Duration(milliseconds: 10),
          ).listModels('test-key'),
          throwsA(_aiFailure(AiFailureCode.timeout)),
          reason: build.name,
        );
        await client.aborted.future.timeout(const Duration(seconds: 1));
        expect(client.calls, 1, reason: build.name);
      }
    },
  );

  test(
    'a completely received response wins over cancellation at stream close',
    () async {
      for (final build in _adapterBuilders) {
        final cancellation = AiCancellation();
        final client = _CancelOnBodyCompletionClient(
          cancellation,
          '{"data":[{"id":"model-after-drain"}]}',
        );

        final models = await build(
          client,
        ).listModels('test-key', cancellation: cancellation);

        expect(models.map((model) => model.id), ['model-after-drain']);
        expect(cancellation.isCancelled, isTrue);
      }
    },
  );

  test(
    'provider refusal is blocked while empty success is malformed',
    () async {
      final refusals = <(_AdapterBuilder, String)>[
        (
          _adapterBuilders[0],
          '{"status":"incomplete","incomplete_details":'
              '{"reason":"content_filter"},"output_text":""}',
        ),
        (
          _adapterBuilders[1],
          '{"choices":[{"finish_reason":"content_filter",'
              '"message":{"content":""}}]}',
        ),
        (_adapterBuilders[2], '{"stop_reason":"refusal","content":[]}'),
      ];
      for (final entry in refusals) {
        final blockedClient = _RecordingClient(
          (_, _) async => _response(200, entry.$2),
        );
        await expectLater(
          _reply(entry.$1(blockedClient)),
          throwsA(_aiFailure(AiFailureCode.blocked)),
          reason: entry.$1.name,
        );
      }

      final whitespace = _RecordingClient(
        (_, _) async =>
            _response(200, '{"choices":[{"message":{"content":"   "}}]}'),
      );
      await expectLater(
        _reply(_adapterBuilders[1](whitespace)),
        throwsA(_aiFailure(AiFailureCode.malformedResponse)),
      );
    },
  );
}

typedef _BuildAdapter =
    AiTutorGateway Function(http.Client client, {Duration timeout});

final class _AdapterBuilder {
  const _AdapterBuilder(this.name, this.build);

  final String name;
  final _BuildAdapter build;

  AiTutorGateway call(
    http.Client client, {
    Duration timeout = const Duration(seconds: 20),
  }) => build(client, timeout: timeout);
}

final _adapterBuilders = <_AdapterBuilder>[
  _AdapterBuilder(
    'OpenAI Responses',
    (client, {timeout = const Duration(seconds: 20)}) => OpenAiResponsesGateway(
      client: client,
      baseUri: Uri.parse('https://openai.example/v1'),
      model: 'gpt-test',
      requestTimeout: timeout,
    ),
  ),
  _AdapterBuilder(
    'OpenAI compatible',
    (client, {timeout = const Duration(seconds: 20)}) =>
        OpenAiCompatibleGateway(
          client: client,
          baseUri: Uri.parse('https://compatible.example/v1'),
          model: 'compatible-test',
          providerId: AiProviderId.customOpenAi,
          requestTimeout: timeout,
        ),
  ),
  _AdapterBuilder(
    'Anthropic',
    (client, {timeout = const Duration(seconds: 20)}) => AnthropicGateway(
      client: client,
      baseUri: Uri.parse('https://anthropic.example'),
      model: 'claude-test',
      requestTimeout: timeout,
    ),
  ),
];

Future<AiGatewayReply> _reply(AiTutorGateway gateway) =>
    gateway.generateTutorReply(
      key: 'test-key',
      scenario: 'Cafe',
      learnerMessage: 'A coffee, please.',
    );

Matcher _aiFailure(AiFailureCode code) =>
    isA<AiTutorException>().having((failure) => failure.code, 'code', code);

http.StreamedResponse _response(int statusCode, String body) =>
    http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );

typedef _RequestHandler =
    Future<http.StreamedResponse> Function(http.BaseRequest, int call);

final class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.handler);

  final _RequestHandler handler;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return handler(request, requests.length);
  }
}

final class _AbortAwareClient extends http.BaseClient {
  final Completer<void> entered = Completer<void>();
  int calls = 0;
  int aborted = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls += 1;
    if (!entered.isCompleted) entered.complete();
    final abortable = request as http.AbortableRequest;
    await abortable.abortTrigger;
    aborted += 1;
    throw http.RequestAbortedException(request.url);
  }
}

final class _StalledBodyClient extends http.BaseClient {
  final Completer<void> aborted = Completer<void>();
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls += 1;
    final abortable = request as http.AbortableRequest;
    final controller = StreamController<List<int>>();
    unawaited(
      abortable.abortTrigger?.then((_) {
        if (!aborted.isCompleted) aborted.complete();
        controller.addError(http.RequestAbortedException(request.url));
        controller.close();
      }),
    );
    return http.StreamedResponse(controller.stream, 200);
  }
}

final class _DelayedAbortClient extends http.BaseClient {
  final Completer<void> entered = Completer<void>();
  final Completer<void> finished = Completer<void>();
  int aborted = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!entered.isCompleted) entered.complete();
    final abortable = request as http.AbortableRequest;
    await abortable.abortTrigger;
    aborted += 1;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!finished.isCompleted) finished.complete();
    throw http.RequestAbortedException(request.url);
  }
}

final class _CancelOnBodyCompletionClient extends http.BaseClient {
  _CancelOnBodyCompletionClient(this.cancellation, this.body);

  final AiCancellation cancellation;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Stream<List<int>> responseBody() async* {
      yield utf8.encode(body);
      cancellation.cancel();
    }

    return http.StreamedResponse(
      responseBody(),
      200,
      headers: const {'content-type': 'application/json'},
      request: request,
    );
  }
}
