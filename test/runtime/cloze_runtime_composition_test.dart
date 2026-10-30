import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/ai/ai_service_factory.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_auth_token_provider.dart';

import '../support/configured_quiz_harness.dart';

AppConfig _config() => AppConfig.fromValues(
  voiceApiUrl: 'https://voice.example.test',
  aiApiUrl: 'https://content.example.test',
  isDebug: false,
);

ContentRequest _request() => ContentRequest.create(
  text: 'station',
  kind: ContentKind.sentence,
  cefr: CefrLevel.a2,
  language: 'en',
);

AppBootstrap _bootstrap(
  ConfiguredQuizHarness h, {
  required ContentServiceFactory contentFactory,
  AppConfig? config,
  bool firebaseReady = true,
  Object? laterFailure,
}) => AppBootstrap(
  createDatabase: () => h.database,
  initializeFirebase: () async {
    if (!firebaseReady) throw StateError('synthetic unavailable Firebase');
  },
  initializeSupabase: () async {},
  loadConfig: () =>
      config ?? (throw const AppConfigException('synthetic absent config')),
  guestSessionService: _Guest(),
  contentServiceFactory: contentFactory,
  geminiSettingsStoreFactory: laterFailure == null
      ? null
      : () => throw laterFailure,
);

void main() {
  for (final (configured, firebaseReady) in const [
    (false, true),
    (true, false),
    (false, false),
  ]) {
    test(
      'config=$configured Firebase=$firebaseReady never creates unavailable content service',
      () async {
        final h = await ConfiguredQuizHarness.open();
        addTearDown(h.close);
        var factories = 0;
        final dependencies = await _bootstrap(
          h,
          config: configured ? _config() : null,
          firebaseReady: firebaseReady,
          contentFactory: (_) {
            factories++;
            throw StateError('unavailable factory must not run');
          },
        ).initialize();
        addTearDown(dependencies.dispose);
        expect(factories, 0);
        expect(dependencies.learning!.contentProvider, isNull);
        expect(
          await dependencies.learning!.prepareCloze(
            categoryId: configuredCategoryId,
            variant: ClozeVariant.typed,
            stillCurrent: () => true,
          ),
          isNull,
        );
        expect(await h.count('learning_sessions'), 0);
        final ordinary = (await dependencies.learning!.prepareDictation(
          categoryId: configuredCategoryId,
          stillCurrent: () => true,
        ))!;
        await dependencies.learning!.startNativeExercise(
          ordinary,
          stillCurrent: () => true,
        );
        expect(await h.count('learning_sessions'), 1);
      },
    );
  }

  test(
    'one configured managed provider generates both variants outside transactions',
    () async {
      final h = await ConfiguredQuizHarness.open();
      addTearDown(h.close);
      final configured = _config();
      final requests = <Map<String, dynamic>>[];
      final client = _Client((request) async {
        expect(await h.ownerWrites.hasAmbientTransaction(), isFalse);
        expect(await h.count('learning_sessions'), 0);
        expect(
          request.url,
          Uri.parse('https://content.example.test/v1/content'),
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        expect(body['kind'], 'sentence');
        expect(body['language'], 'en');
        expect(body['cefr'], 'a2');
        return _response(body['text']! as String);
      });
      late ManagedAiService service;
      var factories = 0;
      final dependencies = await _bootstrap(
        h,
        config: configured,
        contentFactory: (actualConfig) {
          factories++;
          expect(identical(actualConfig, configured), isTrue);
          return service = AiServiceFactory.create(
            config: actualConfig,
            client: client,
            firebaseTokenReader: _Token(),
          );
        },
      ).initialize();
      addTearDown(dependencies.dispose);
      expect(factories, 1);
      expect(
        identical(dependencies.learning!.contentProvider, service),
        isTrue,
      );
      for (final variant in ClozeVariant.values) {
        final prepared = await dependencies.learning!.prepareCloze(
          categoryId: configuredCategoryId,
          variant: variant,
          stillCurrent: () => true,
        );
        expect(prepared, isNotNull);
        expect(prepared!.ownerId, configuredOwnerId);
        expect(
          prepared.content.gapText.toLowerCase(),
          prepared.word.spelling.toLowerCase(),
        );
      }
      expect(factories, 1);
      expect(requests, hasLength(2));
      expect(client.closes, 0);
      await dependencies.dispose();
      await dependencies.dispose();
      expect(client.closes, 1);
      await expectLater(
        service.generate(_request()),
        throwsA(isA<AiFailure>()),
      );
    },
  );

  test(
    'optional factory failure marks backend unavailable and preserves ordinary learning',
    () async {
      final h = await ConfiguredQuizHarness.open();
      addTearDown(h.close);
      var factories = 0;
      final dependencies = await _bootstrap(
        h,
        config: _config(),
        contentFactory: (_) {
          factories++;
          throw StateError('synthetic factory failure');
        },
      ).initialize();
      addTearDown(dependencies.dispose);
      expect(factories, 1);
      expect(
        dependencies.runtimeStatus.backends,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.learning!.contentProvider, isNull);
      final ordinary = (await dependencies.learning!.prepareDictation(
        categoryId: configuredCategoryId,
        stillCurrent: () => true,
      ))!;
      await dependencies.learning!.startNativeExercise(
        ordinary,
        stillCurrent: () => true,
      );
      expect(await h.count('learning_sessions'), 1);
    },
  );

  for (final closeThrows in [false, true]) {
    test(
      'later bootstrap failure closes content and preserves original error (closeThrows=$closeThrows)',
      () async {
        final h = await ConfiguredQuizHarness.open();
        addTearDown(h.close);
        final original = StateError('synthetic later composition failure');
        final client = _Client((_) async => _response('station'))
          ..closeFailure = closeThrows
              ? StateError('synthetic close failure')
              : null;
        late ManagedAiService service;
        final bootstrap = _bootstrap(
          h,
          config: _config(),
          laterFailure: original,
          contentFactory: (config) => service = AiServiceFactory.create(
            config: config,
            client: client,
            firebaseTokenReader: _Token(),
          ),
        );
        await expectLater(bootstrap.initialize(), throwsA(same(original)));
        expect(client.closes, 1);
        await expectLater(
          service.generate(_request()),
          throwsA(isA<AiFailure>()),
        );
      },
    );
  }

  test(
    'content disposal failure still runs the existing database cleanup once',
    () async {
      final h = await ConfiguredQuizHarness.open();
      addTearDown(h.close);
      final closeFailure = StateError('synthetic managed close failure');
      final client = _Client((_) async => _response('station'))
        ..closeFailure = closeFailure;
      final dependencies = await _bootstrap(
        h,
        config: _config(),
        contentFactory: (config) => AiServiceFactory.create(
          config: config,
          client: client,
          firebaseTokenReader: _Token(),
        ),
      ).initialize();
      await expectLater(dependencies.dispose(), throwsA(same(closeFailure)));
      await expectLater(dependencies.dispose(), throwsA(same(closeFailure)));
      expect(client.closes, 1);
      await expectLater(
        h.database.customSelect('SELECT 1').getSingle(),
        throwsA(isA<StateError>()),
      );
    },
  );

  testWidgets(
    'actual app dependency replacement closes only the old content client',
    (tester) async {
      final first = (await tester.runAsync(ConfiguredQuizHarness.open))!;
      final second = (await tester.runAsync(ConfiguredQuizHarness.open))!;
      final oldClient = _Client((_) async => _response('station'));
      final newClient = _Client((_) async => _response('station'));
      ManagedAiService managed(AppConfig config, _Client client) =>
          AiServiceFactory.create(
            config: config,
            client: client,
            firebaseTokenReader: _Token(),
          );
      final oldDependencies = (await tester.runAsync(
        () => _bootstrap(
          first,
          config: _config(),
          contentFactory: (config) => managed(config, oldClient),
        ).initialize(),
      ))!;
      final newDependencies = (await tester.runAsync(
        () => _bootstrap(
          second,
          config: _config(),
          contentFactory: (config) => managed(config, newClient),
        ).initialize(),
      ))!;
      try {
        await tester.pumpWidget(MyApp(dependencies: oldDependencies));
        await tester.pumpAndSettle();
        await tester.pumpWidget(MyApp(dependencies: newDependencies));
        await tester.pumpAndSettle();
        expect(oldClient.closes, 1);
        expect(newClient.closes, 0);
        await _drainWidgetDisposal(tester, oldDependencies.dispose);
        expect(oldClient.closes, 1);
        expect(newClient.closes, 0);
        final generated = await tester.runAsync(
          () => newDependencies.learning!.contentProvider!.generate(_request()),
        );
        expect(generated!.text, contains('station'));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(oldClient.closes, 1);
        expect(newClient.closes, 1);
        await _drainWidgetDisposal(tester, newDependencies.dispose);
        expect(oldClient.closes, 1);
        expect(newClient.closes, 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await _drainWidgetDisposal(tester, oldDependencies.dispose);
        await _drainWidgetDisposal(tester, newDependencies.dispose);
        await tester.runAsync(first.close);
        await tester.runAsync(second.close);
      }
    },
  );
}

Future<void> _drainWidgetDisposal(
  WidgetTester tester,
  Future<void> Function() dispose,
) async {
  final cleanup = dispose();
  var completed = false;
  cleanup.then<void>(
    (_) => completed = true,
    onError: (Object _) => completed = true,
  );
  for (var i = 0; i < 100 && !completed; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(completed, isTrue, reason: 'Widget-started disposal must complete');
  await cleanup;
}

http.Response _response(String target) => http.Response(
  jsonEncode({
    'text': 'We saw $target beside the window.',
    'kind': 'sentence',
    'cefr': 'A2',
    'language': 'en',
    'model_version': 'synthetic-runtime-1',
    'cached': false,
  }),
  200,
  headers: {'content-type': 'application/json'},
);

final class _Client extends MockClient {
  _Client(super.handler);
  int closes = 0;
  Object? closeFailure;
  @override
  void close() {
    closes++;
    super.close();
    if (closeFailure case final failure?) throw failure;
  }
}

final class _Token implements FirebaseTokenReader {
  @override
  Future<String?> readIdToken({required bool forceRefresh}) async =>
      'synthetic-runtime-token';
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}
