import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/research/data/http_research_authority_gateway.dart';
import 'package:vocab_learning_app/features/research/data/local_research_authority_cache.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';

import '../../support/research_authority_cache_harness.dart';
import '../../support/research_transport_wire.dart';

void main() {
  test(
    'configured transport installs current signed authority into SQLite-backed cache',
    () async {
      final fixture = await AuthorityCacheFixture.open();
      addTearDown(fixture.close);
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final packet = fixture.gateway.build(
          ResearchAuthorityRefreshRequest(
            scope: fixture.scope!,
            requestId: body['requestId'] as String,
            clockSessionId: body['clockSessionId'] as String,
            monotonicEpoch: body['monotonicEpoch'] as int,
            startedAtMonotonic: fixture.elapsed,
            monotonicElapsed: () => fixture.elapsed,
          ),
        );
        return http.Response(
          jsonEncode(researchAuthorityWire(packet, body['scope'])),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      fixture.cache.dispose();
      fixture.cache = LocalResearchAuthorityCache(
        ownerWrites: fixture.study.participation.ownerWrites,
        currentScope: () => fixture.scope,
        gateway: HttpResearchTransport(
          client: client,
          baseUri: Uri.parse('https://synthetic-authority.example'),
          currentBinding: () => fixture.scope?.binding,
          loadIdToken: (_) async => 'synthetic-firebase-token',
        ),
        operationSignatures: fixture.study.authorities.operationSignatures,
        participationSignatures:
            fixture.study.authorities.participationSignatures,
        generateRequestId: () => 'synthetic-http-refresh',
        maximumAcceptedAge: const Duration(minutes: 10),
        initiallyForeground: true,
        monotonicElapsed: () => fixture.elapsed,
      );
      expect(await fixture.cache.refresh(), isTrue);
      expect(await fixture.cache.read(), isNotNull);
      expect(calls, 1);
    },
  );

  for (final mutation in <String, void Function(Map<String, Object?>)>{
    'unknown key': (data) => data['publicKeys'] = {},
    'replayed nonce': (data) => data['requestId'] = 'synthetic-other-request',
    'wrong clock': (data) => data['clockSessionId'] = 'synthetic-other-clock',
    'wrong epoch': (data) => data['monotonicEpoch'] = 999,
    'fractional version': (data) => data['schemaVersion'] = 1.0,
    'zero freshness': (data) => data['maximumAgeMs'] = 0,
    'future-invalid date': (data) =>
        data['anchorUtc'] = '2026-02-31T00:00:00.000Z',
    'scope substitution': (data) =>
        ((data['scope'] as Map)['binding'] as Map)['ownerId'] =
            'synthetic-other-owner',
    'changed consent time': (data) =>
        ((data['receipts'] as List).first as Map)['decidedAtUtc'] =
            '2026-01-01T00:00:00.000Z',
    'invalid operation bytes': (data) => data['operationDocuments'] = [
      base64.encode([1, 2, 3]),
    ],
    'unsigned participation': (data) => data['participationDocuments'] = ['{}'],
  }.entries) {
    test('HTTP ${mutation.key} grants no local authority', () async {
      final h = await _HttpFixture.open();
      addTearDown(h.close);
      h.mutate = mutation.value;
      expect(await h.fixture.cache.refresh(), isFalse);
      expect(await h.fixture.cache.read(), isNull);
      expect(h.calls, 1);
    });
  }

  test(
    'token wait is excluded and the complete round trip consumes freshness',
    () async {
      final h = await _HttpFixture.open();
      addTearDown(h.close);
      h.tokenDelay = const Duration(seconds: 5);
      h.networkDelay = const Duration(seconds: 2);
      expect(await h.fixture.cache.refresh(), isTrue);
      final reading = (await h.fixture.cache.read())!;
      expect(reading.age, const Duration(seconds: 2));
      expect(
        reading.effectiveNowUtc,
        participationStart.add(const Duration(seconds: 7)),
      );
      h.networkDelay = const Duration(minutes: 11);
      expect(await h.fixture.cache.refresh(), isFalse);
      expect(await h.fixture.cache.read(), isNull);
    },
  );

  test('redirects and non-JSON replies never install authority', () async {
    final h = await _HttpFixture.open();
    addTearDown(h.close);
    h.status = 302;
    expect(await h.fixture.cache.refresh(), isFalse);
    expect(h.followRedirects, isFalse);
    expect(h.calls, 1);
    h.status = 200;
    h.contentType = 'text/html';
    expect(await h.fixture.cache.refresh(), isFalse);
    expect(await h.fixture.cache.read(), isNull);
  });

  test(
    'oversized reply is bounded and retired tokens never reach HTTP',
    () async {
      final h = await _HttpFixture.open();
      addTearDown(h.close);
      h.oversized = true;
      expect(await h.fixture.cache.refresh(), isFalse);
      final calls = h.calls;
      final token = Completer<String?>();
      h.token = () => token.future;
      final refreshing = h.fixture.cache.refresh();
      await Future<void>.delayed(Duration.zero);
      h.fixture.scope = h.fixture.scopeFor('owner-b', 'uid-b', 2);
      h.fixture.scope = h.fixture.scopeFor('owner-a', 'uid-a', 3);
      token.complete('synthetic-token');
      expect(await refreshing, isFalse);
      expect(h.calls, calls);
    },
  );

  test('Research transport accepts only a configured HTTPS origin', () {
    for (final uri in [
      'http://synthetic.example',
      'https://u:p@synthetic.example',
      'https://synthetic.example/other',
      'https://synthetic.example/?token=x',
    ]) {
      final client = MockClient((_) async => http.Response('{}', 200));
      addTearDown(client.close);
      expect(
        () => HttpResearchTransport(
          client: client,
          baseUri: Uri.parse(uri),
          currentBinding: () => null,
          loadIdToken: (_) async => null,
        ),
        throwsArgumentError,
      );
    }
  });
}

final class _HttpFixture {
  _HttpFixture(this.fixture);
  final AuthorityCacheFixture fixture;
  late final http.Client client;
  int calls = 0;
  int status = 200;
  bool? followRedirects;
  String contentType = 'application/json';
  bool oversized = false;
  Duration tokenDelay = Duration.zero;
  Duration networkDelay = Duration.zero;
  Future<String?> Function()? token;
  void Function(Map<String, Object?>)? mutate;

  static Future<_HttpFixture> open() async {
    final h = _HttpFixture(await AuthorityCacheFixture.open());
    h.client = MockClient((request) async {
      h.calls++;
      h.followRedirects = request.followRedirects;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final packet = h.fixture.gateway.build(
        ResearchAuthorityRefreshRequest(
          scope: h.fixture.scope!,
          requestId: body['requestId'] as String,
          clockSessionId: body['clockSessionId'] as String,
          monotonicEpoch: body['monotonicEpoch'] as int,
          startedAtMonotonic: h.fixture.elapsed,
          monotonicElapsed: () => h.fixture.elapsed,
        ),
      );
      final data = researchAuthorityWire(packet, body['scope']);
      h.mutate?.call(data);
      h.fixture.advance(h.networkDelay);
      final bytes = h.oversized
          ? List.filled(HttpResearchTransport.maximumResponseBytes + 1, 32)
          : utf8.encode(jsonEncode(data));
      return http.Response.bytes(
        bytes,
        h.status,
        headers: {
          'content-type': h.contentType,
          'location': 'https://synthetic-untrusted.example',
        },
      );
    });
    h.fixture.cache.dispose();
    h.fixture.cache = LocalResearchAuthorityCache(
      ownerWrites: h.fixture.study.participation.ownerWrites,
      currentScope: () => h.fixture.scope,
      gateway: HttpResearchTransport(
        client: h.client,
        baseUri: Uri.parse('https://synthetic-authority.example'),
        currentBinding: () => h.fixture.scope?.binding,
        loadIdToken: (_) async {
          h.fixture.advance(h.tokenDelay);
          return h.token == null ? 'synthetic-token' : await h.token!();
        },
      ),
      operationSignatures: h.fixture.study.authorities.operationSignatures,
      participationSignatures:
          h.fixture.study.authorities.participationSignatures,
      generateRequestId: () => 'synthetic-http-refresh',
      maximumAcceptedAge: const Duration(minutes: 10),
      initiallyForeground: true,
      monotonicElapsed: () => h.fixture.elapsed,
    );
    return h;
  }

  Future<void> close() async {
    client.close();
    await fixture.close();
  }
}
