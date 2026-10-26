import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/account_deletion/data/http_privileged_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';

void main() {
  final now = DateTime.utc(2026, 10, 24, 12);

  test('sends only server-verifiable identity and parses receipt', () async {
    late http.Request request;
    final gateway = HttpPrivilegedAccountDeletionGateway(
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'receiptId': 'receipt-1',
            'ownerId': 'owner-1',
            'firebaseUid': 'uid-1',
            'idempotencyKey': 'delete:synthetic-operation',
            'completedAtUtc': now.toIso8601String(),
          }),
          200,
        );
      }),
      baseUri: Uri.parse('https://api.example.test/'),
      idToken: () async => 'synthetic-token',
    );

    final receipt = await gateway.deleteRecursively(
      ownerId: 'owner-1',
      firebaseUid: 'uid-1',
      idempotencyKey: 'delete:synthetic-operation',
      exportReceipt: _export(now),
      authenticationReceipt: RecentAuthenticationReceipt(
        firebaseUid: 'uid-1',
        authenticatedAtUtc: now,
      ),
    );

    expect(receipt.firebaseUid, 'uid-1');
    expect(request.url.path, '/v1/account-deletions');
    expect(request.headers['authorization'], 'Bearer synthetic-token');
    expect(request.headers.containsKey('idempotency-key'), isFalse);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body.containsKey('firebaseUid'), isFalse);
    expect(body.containsKey('authenticatedAtUtc'), isFalse);
    expect(body['ownerId'], 'owner-1');
    expect(
      (body['exportReceipt'] as Map<String, dynamic>)['ownerId'],
      'owner-1',
    );
  });

  test('fails closed without an ID token or with an invalid receipt', () async {
    final noToken = HttpPrivilegedAccountDeletionGateway(
      client: MockClient((_) async => http.Response('{}', 200)),
      baseUri: Uri.parse('https://api.example.test/'),
      idToken: () async => null,
    );
    await expectLater(
      _delete(noToken, now),
      throwsA(
        isA<AccountDeletionException>().having(
          (error) => error.code,
          'code',
          AccountDeletionFailureCode.reauthenticationRequired,
        ),
      ),
    );

    final malformed = HttpPrivilegedAccountDeletionGateway(
      client: MockClient((_) async => http.Response('{}', 200)),
      baseUri: Uri.parse('https://api.example.test/'),
      idToken: () async => 'synthetic-token',
    );
    await expectLater(
      _delete(malformed, now),
      throwsA(
        isA<AccountDeletionException>().having(
          (error) => error.code,
          'code',
          AccountDeletionFailureCode.invalidCloudReceipt,
        ),
      ),
    );
  });

  test(
    'recovers a completed deletion after the Firebase identity is gone',
    () async {
      late http.Request request;
      final gateway = HttpPrivilegedAccountDeletionGateway(
        client: MockClient((value) async {
          request = value;
          return http.Response(
            jsonEncode({
              'receiptId': 'receipt-recovered',
              'ownerId': 'owner-1',
              'firebaseUid': 'uid-1',
              'idempotencyKey': 'delete:synthetic-operation',
              'completedAtUtc': now.toIso8601String(),
            }),
            200,
          );
        }),
        baseUri: Uri.parse('https://api.example.test/'),
        idToken: () async => null,
      );

      final receipt = await _delete(gateway, now);

      expect(receipt.receiptId, 'receipt-recovered');
      expect(request.url.path, '/v1/account-deletions/recover');
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(jsonDecode(request.body), {
        'ownerId': 'owner-1',
        'firebaseUid': 'uid-1',
        'idempotencyKey': 'delete:synthetic-operation',
      });
    },
  );

  test(
    'recovers when refreshing the token throws after server commit',
    () async {
      late http.Request request;
      final gateway = HttpPrivilegedAccountDeletionGateway(
        client: MockClient((value) async {
          request = value;
          return http.Response(
            jsonEncode({
              'receiptId': 'receipt-recovered',
              'ownerId': 'owner-1',
              'firebaseUid': 'uid-1',
              'idempotencyKey': 'delete:synthetic-operation',
              'completedAtUtc': now.toIso8601String(),
            }),
            200,
          );
        }),
        baseUri: Uri.parse('https://api.example.test/'),
        idToken: () async => throw StateError('Firebase Auth user is gone'),
      );

      final receipt = await _delete(gateway, now);

      expect(receipt.receiptId, 'receipt-recovered');
      expect(request.url.path, '/v1/account-deletions/recover');
    },
  );

  test(
    'classifies a network failure as retryable cloud deletion failure',
    () async {
      final gateway = HttpPrivilegedAccountDeletionGateway(
        client: MockClient((_) async => throw http.ClientException('offline')),
        baseUri: Uri.parse('https://api.example.test/'),
        idToken: () async => 'synthetic-token',
      );

      await expectLater(
        _delete(gateway, now),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.cloudDeleteFailed,
          ),
        ),
      );
    },
  );
}

Future<CloudDeletionReceipt> _delete(
  HttpPrivilegedAccountDeletionGateway gateway,
  DateTime now,
) => gateway.deleteRecursively(
  ownerId: 'owner-1',
  firebaseUid: 'uid-1',
  idempotencyKey: 'delete:synthetic-operation',
  exportReceipt: _export(now),
  authenticationReceipt: RecentAuthenticationReceipt(
    firebaseUid: 'uid-1',
    authenticatedAtUtc: now,
  ),
);

FullAccountExportReceipt _export(DateTime now) => FullAccountExportReceipt(
  ownerId: 'owner-1',
  artifactId: 'artifact-1',
  artifactSha256: 'a' * 64,
  bytesWritten: 10,
  schemaVersion: 10,
  coveredScopes: requiredFullAccountExportScopes,
  completedAtUtc: now,
);
