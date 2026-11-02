import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/billing/data/http_billing_repository.dart';
import 'package:vocab_learning_app/features/billing/domain/billing_contracts.dart';

import 'support/billing_fixture.dart';

void main() {
  test('catalog v2 admits server managed quota before purchase', () async {
    final value = _catalog();
    value['schemaVersion'] = 2;
    ((value['products'] as List).single as Map)['dailyManagedUnits'] = 10;
    final client = MockClient((_) async => _json(value));
    addTearDown(client.close);
    final result = await _repository(
      client,
    ).loadCatalog(syntheticAccount, stillCurrent: () => true);
    expect(result.products.single.entitlements, {'managedContent'});
    expect(result.products.single.dailyManagedUnits, 10);
  });

  for (final units in [null, 0, -1, 1.5, '10', true, 1000001]) {
    test(
      'catalog rejects malformed or unusable managed quota $units',
      () async {
        final value = _catalog();
        ((value['products'] as List).single as Map)['dailyManagedUnits'] =
            units;
        final client = MockClient((_) async => _json(value));
        addTearDown(client.close);
        await expectLater(
          _repository(
            client,
          ).loadCatalog(syntheticAccount, stillCurrent: () => true),
          throwsA(_failure(BillingFailureCode.invalidResponse)),
        );
      },
    );
  }

  test('catalog cannot advertise an unimplemented premium benefit', () async {
    final value = _catalog();
    ((value['products'] as List).single as Map)['entitlements'] = [
      'offlinePremium',
    ];
    final client = MockClient((_) async => _json(value));
    addTearDown(client.close);
    await expectLater(
      _repository(
        client,
      ).loadCatalog(syntheticAccount, stillCurrent: () => true),
      throwsA(_failure(BillingFailureCode.invalidResponse)),
    );
  });

  test(
    'catalog binds authenticated account and exact product/base-plan allowlist',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://billing.example/v1/billing/catalog',
        );
        expect(request.headers['authorization'], 'Bearer synthetic-id-token');
        expect(request.followRedirects, isFalse);
        return _json(_catalog());
      });
      addTearDown(client.close);
      final result = await _repository(
        client,
      ).loadCatalog(syntheticAccount, stillCurrent: () => true);
      expect(result.accountIdentifier, 'a' * 64);
      expect(result.products.single.basePlanId, 'monthly');
      expect(result.products.single.entitlements, {'managedContent'});
    },
  );

  test(
    'an owner invalidated while awaiting an ID token cannot submit a verification',
    () async {
      var calls = 0;
      var current = true;
      final token = Completer<String?>();
      final client = MockClient((_) async {
        calls++;
        return _json(_snapshot());
      });
      addTearDown(client.close);
      final repository = HttpBillingRepository(
        client: client,
        baseUri: Uri.https('billing.example'),
        loadIdToken: (_) => token.future,
        isCurrent: (_) => true,
      );
      final operation = repository.verify(
        syntheticAccount,
        const BillingVerification(
          purchaseToken: 'synthetic-purchase-secret',
          requestId: 'synthetic-id',
        ),
        stillCurrent: () => current,
      );
      final assertion = expectLater(
        operation,
        throwsA(_failure(BillingFailureCode.ownerChanged)),
      );
      current = false;
      token.complete('synthetic-id-token');
      await assertion;
      expect(calls, 0);
    },
  );

  test(
    'exact verification retry sends the original request identity and no owner parameter',
    () async {
      final bodies = <String>[];
      final client = MockClient((request) async {
        bodies.add(request.body);
        return bodies.length == 1
            ? _json({
                'detail': {'message': 'synthetic-purchase-secret'},
              }, status: 503)
            : _json(_snapshot());
      });
      addTearDown(client.close);
      final repository = _repository(client);
      const command = BillingVerification(
        purchaseToken: 'synthetic-purchase-secret',
        requestId: 'synthetic-id',
      );
      Object? failure;
      try {
        await repository.verify(
          syntheticAccount,
          command,
          stillCurrent: () => true,
        );
      } catch (error) {
        failure = error;
      }
      expect(failure, _failure(BillingFailureCode.unavailable));
      expect(failure.toString(), isNot(contains('synthetic-purchase-secret')));
      await repository.verify(
        syntheticAccount,
        command,
        stillCurrent: () => true,
      );
      expect(bodies.first, bodies.last);
      expect(jsonDecode(bodies.last), {
        'purchaseToken': 'synthetic-purchase-secret',
        'requestId': 'synthetic-id',
      });
      expect(command.toString(), isNot(contains(command.purchaseToken)));
    },
  );

  for (final change in <Map<String, Object?>>[
    {'schemaVersion': 1},
    {'schemaVersion': 3},
    {'schemaVersion': 2.0},
    {'managedContentRequired': false},
    {'managedContentRequired': 'true'},
    {'packageName': 'other.package'},
    {'accountIdentifier': 'raw-user-id'},
    {'ownerId': 'not-allowed'},
    {'products': []},
    {
      'products': [
        {
          'productId': 'synthetic.monthly',
          'basePlanId': 'monthly',
          'entitlements': ['managedContent', 'managedContent'],
          'dailyManagedUnits': 10,
        },
      ],
    },
  ]) {
    test(
      'malformed catalog cannot establish purchased plans ${change.keys.join()}',
      () async {
        final client = MockClient(
          (_) async => _json({..._catalog(), ...change}),
        );
        addTearDown(client.close);
        await expectLater(
          () => _repository(
            client,
          ).loadCatalog(syntheticAccount, stillCurrent: () => true),
          throwsA(_failure(BillingFailureCode.invalidResponse)),
        );
      },
    );
  }

  test(
    'overlapping verified purchases may carry the same entitlement without inventing extra quota',
    () async {
      final snapshot = _snapshot();
      snapshot['grants'] = [_grant(), _grant()];
      final client = MockClient((_) async => _json(snapshot));
      addTearDown(client.close);
      final result = await _repository(
        client,
      ).loadEntitlements(syntheticAccount, stillCurrent: () => true);
      expect(result.grants, hasLength(2));
      expect(result.grants.map((grant) => grant.dailyManagedUnits), [10, 10]);
    },
  );

  for (final grant in <Map<String, Object?>>[
    {..._grant(), 'expiresAtUtc': '2026-10-01T00:00:00Z'},
    {..._grant(), 'checkedAtUtc': '2026-11-02T00:00:00Z'},
    {..._grant(), 'checkedAtUtc': '2026-11-01T00:00:00'},
    {..._grant(), 'dailyManagedUnits': -1},
    {..._grant(), 'dailyManagedUnits': 1.5},
  ]) {
    test('invalid grant cannot become active ${grant.toString()}', () async {
      final client = MockClient(
        (_) async => _json({
          ..._snapshot(),
          'grants': [grant],
        }),
      );
      addTearDown(client.close);
      await expectLater(
        () => _repository(
          client,
        ).loadEntitlements(syntheticAccount, stillCurrent: () => true),
        throwsA(_failure(BillingFailureCode.invalidResponse)),
      );
    });
  }

  test(
    'response bytes remain bounded and unexpected sensitive fields are rejected',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          'x' * (HttpBillingRepository.maximumResponseBytes + 1),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      addTearDown(client.close);
      await expectLater(
        () => _repository(
          client,
        ).loadEntitlements(syntheticAccount, stillCurrent: () => true),
        throwsA(_failure(BillingFailureCode.invalidResponse)),
      );
      final extra = MockClient(
        (_) async =>
            _json({..._snapshot(), 'purchaseToken': 'synthetic-secret'}),
      );
      addTearDown(extra.close);
      await expectLater(
        () => _repository(
          extra,
        ).loadEntitlements(syntheticAccount, stillCurrent: () => true),
        throwsA(_failure(BillingFailureCode.invalidResponse)),
      );
    },
  );

  test('remote HTTP and credential-bearing origins are rejected', () {
    final client = MockClient((_) async => _json(_snapshot()));
    addTearDown(client.close);
    for (final uri in [
      'http://billing.example',
      'https://user:pass@billing.example',
      'https://billing.example/prefix',
    ]) {
      expect(
        () => HttpBillingRepository(
          client: client,
          baseUri: Uri.parse(uri),
          loadIdToken: (_) async => 'synthetic-id-token',
          isCurrent: (_) => true,
        ),
        throwsArgumentError,
      );
    }
  });

  test('anonymous account never requests even an ID token', () async {
    var tokenCalls = 0;
    final client = MockClient((_) async => _json(_snapshot()));
    addTearDown(client.close);
    final repository = HttpBillingRepository(
      client: client,
      baseUri: Uri.https('billing.example'),
      loadIdToken: (_) async {
        tokenCalls++;
        return 'synthetic';
      },
      isCurrent: (_) => true,
    );
    await expectLater(
      () => repository.loadEntitlements(
        const BillingAccount(
          ownerId: 'synthetic',
          firebaseUid: 'synthetic',
          isAnonymous: true,
        ),
        stillCurrent: () => true,
      ),
      throwsA(_failure(BillingFailureCode.accountRequired)),
    );
    expect(tokenCalls, 0);
  });

  test(
    'verification rate limiting preserves retry-after and is distinct from exhausted quota',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'detail': {'code': 'BILLING_VERIFICATION_RATE_LIMITED'},
          }),
          429,
          headers: {'content-type': 'application/json', 'retry-after': '60'},
        ),
      );
      addTearDown(client.close);
      await expectLater(
        () => _repository(
          client,
        ).loadEntitlements(syntheticAccount, stillCurrent: () => true),
        throwsA(
          isA<BillingException>()
              .having((e) => e.code, 'code', BillingFailureCode.retryLater)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 60),
              ),
        ),
      );
    },
  );
}

HttpBillingRepository _repository(http.Client client) => HttpBillingRepository(
  client: client,
  baseUri: Uri.https('billing.example'),
  loadIdToken: (_) async => 'synthetic-id-token',
  isCurrent: (_) => true,
);
http.Response _json(Map<String, Object?> value, {int status = 200}) =>
    http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json'},
    );
Map<String, Object?> _catalog() => {
  'schemaVersion': 2,
  'packageName': 'com.lexiquest.app',
  'policyRevision': 'synthetic-v1',
  'accountIdentifier': 'a' * 64,
  'managedContentRequired': true,
  'products': [
    <String, Object?>{
      'productId': 'synthetic.monthly',
      'basePlanId': 'monthly',
      'entitlements': ['managedContent'],
      'dailyManagedUnits': 10,
    },
  ],
};
Map<String, Object?> _grant() => {
  'entitlement': 'managedContent',
  'expiresAtUtc': '2026-12-01T00:00:00Z',
  'checkedAtUtc': '2026-11-01T00:00:00Z',
  'dailyManagedUnits': 10,
};
Map<String, Object?> _snapshot() => {
  'schemaVersion': 1,
  'serverTimeUtc': '2026-11-01T00:00:00+00:00',
  'acknowledgementPending': false,
  'refreshRequired': false,
  'grants': [_grant()],
};
Matcher _failure(BillingFailureCode code) =>
    isA<BillingException>().having((error) => error.code, 'code', code);
