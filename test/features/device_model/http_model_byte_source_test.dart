import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vocab_learning_app/features/device_model/data/http_model_byte_source.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';

void main() {
  test(
    'sends an exact range request and exposes streamed response bytes',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      String? range;
      server.listen((request) async {
        range = request.headers.value(HttpHeaders.rangeHeader);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 4096-4105/5000',
        );
        request.response.add(utf8.encode('model-tail'));
        await request.response.close();
      });
      final source = HttpModelByteSource(http.Client());
      addTearDown(source.close);

      final response = await source.open(
        Uri.parse('http://${server.address.host}:${server.port}/model'),
        start: 4096,
      );

      expect(range, 'bytes=4096-');
      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.contentRangeStart, 4096);
      expect(
        utf8.decode(await response.bytes.expand((chunk) => chunk).toList()),
        'model-tail',
      );
    },
  );

  test('maps a response timeout without retrying forever', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      // Intentionally withhold headers until the bounded client timeout.
    });
    final source = HttpModelByteSource(
      http.Client(),
      requestTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(source.close);

    await expectLater(
      source.open(
        Uri.parse('http://${server.address.host}:${server.port}/model'),
        start: 0,
      ),
      throwsA(
        isA<ModelLifecycleException>().having(
          (error) => error.code,
          'code',
          ModelFailureCode.network,
        ),
      ),
    );
  });

  test('cancellation aborts a stalled request immediately', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      // Intentionally stall until the client aborts the request.
    });
    final cancellation = ModelCancellation();
    final source = HttpModelByteSource(
      http.Client(),
      requestTimeout: const Duration(seconds: 5),
    );
    addTearDown(source.close);
    final operation = source.open(
      Uri.parse('http://${server.address.host}:${server.port}/model'),
      start: 0,
      cancellation: cancellation,
    );

    cancellation.cancel();

    await expectLater(
      operation,
      throwsA(
        isA<ModelLifecycleException>().having(
          (error) => error.code,
          'code',
          ModelFailureCode.cancelled,
        ),
      ),
    );
  });

  test('cancellation aborts a stalled response stream', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final headersSent = Completer<void>();
    final releaseServer = Completer<void>();
    addTearDown(() async {
      if (!releaseServer.isCompleted) releaseServer.complete();
      await server.close(force: true);
    });
    server.listen((request) async {
      request.response.statusCode = HttpStatus.ok;
      request.response.add(const [1]);
      await request.response.flush();
      headersSent.complete();
      await releaseServer.future;
      await request.response.close();
    });
    final cancellation = ModelCancellation();
    final source = HttpModelByteSource(
      http.Client(),
      requestTimeout: const Duration(seconds: 5),
    );
    addTearDown(source.close);
    final response = await source.open(
      Uri.parse('http://${server.address.host}:${server.port}/model'),
      start: 0,
      cancellation: cancellation,
    );
    final operation = response.bytes.expand((chunk) => chunk).toList();
    await headersSent.future;

    cancellation.cancel();

    await expectLater(
      operation,
      throwsA(
        isA<ModelLifecycleException>().having(
          (error) => error.code,
          'code',
          ModelFailureCode.cancelled,
        ),
      ),
    );
  });
}
