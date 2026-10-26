import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/account_deletion_contracts.dart';

typedef AccountDeletionIdTokenProvider = Future<String?> Function();

final class HttpPrivilegedAccountDeletionGateway
    implements PrivilegedAccountDeletionGateway {
  factory HttpPrivilegedAccountDeletionGateway({
    required http.Client client,
    required Uri baseUri,
    required AccountDeletionIdTokenProvider idToken,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      HttpPrivilegedAccountDeletionGateway._(client, baseUri, idToken, timeout);

  const HttpPrivilegedAccountDeletionGateway._(
    this._client,
    this._baseUri,
    this._idToken,
    this.timeout,
  );

  final http.Client _client;
  final Uri _baseUri;
  final AccountDeletionIdTokenProvider _idToken;
  final Duration timeout;

  @override
  Future<CloudDeletionReceipt> deleteRecursively({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required FullAccountExportReceipt exportReceipt,
    required RecentAuthenticationReceipt authenticationReceipt,
  }) async {
    final token = (await _idToken())?.trim();
    if (token == null || token.isEmpty) {
      throw const AccountDeletionException(
        AccountDeletionFailureCode.reauthenticationRequired,
      );
    }
    try {
      final response = await _client
          .post(
            _baseUri.resolve('/v1/account-deletions'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
              'idempotency-key': idempotencyKey,
            },
            body: jsonEncode({
              'ownerId': ownerId,
              'idempotencyKey': idempotencyKey,
              'exportReceipt': {
                'ownerId': exportReceipt.ownerId,
                'artifactId': exportReceipt.artifactId,
                'artifactSha256': exportReceipt.artifactSha256,
                'bytesWritten': exportReceipt.bytesWritten,
                'schemaVersion': exportReceipt.schemaVersion,
                'coveredScopes': exportReceipt.coveredScopes.toList()..sort(),
                'completedAtUtc': exportReceipt.completedAtUtc
                    .toIso8601String(),
              },
            }),
          )
          .timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AccountDeletionException(
          AccountDeletionFailureCode.reauthenticationRequired,
        );
      }
      if (response.statusCode != 200) {
        throw const AccountDeletionException(
          AccountDeletionFailureCode.cloudDeleteFailed,
        );
      }
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) throw const FormatException();
      return CloudDeletionReceipt(
        receiptId: json['receiptId'] as String,
        ownerId: json['ownerId'] as String,
        firebaseUid: json['firebaseUid'] as String,
        idempotencyKey: json['idempotencyKey'] as String,
        completedAtUtc: DateTime.parse(json['completedAtUtc'] as String),
      );
    } on AccountDeletionException {
      rethrow;
    } on TimeoutException catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.cloudDeleteFailed,
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.cloudDeleteFailed,
        cause: error,
      );
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.invalidCloudReceipt,
        cause: error,
      );
    }
  }
}
