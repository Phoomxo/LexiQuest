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
    String? token;
    try {
      token = (await _idToken())?.trim();
    } catch (error) {
      return _recover(
        ownerId: ownerId,
        firebaseUid: firebaseUid,
        idempotencyKey: idempotencyKey,
        missingIdentity: true,
        cause: error,
      );
    }
    if (token == null || token.isEmpty) {
      return _recover(
        ownerId: ownerId,
        firebaseUid: firebaseUid,
        idempotencyKey: idempotencyKey,
        missingIdentity: true,
      );
    }
    try {
      final response = await _client
          .post(
            _baseUri.resolve('/v1/account-deletions'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
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
        return _recover(
          ownerId: ownerId,
          firebaseUid: firebaseUid,
          idempotencyKey: idempotencyKey,
          missingIdentity: true,
        );
      }
      if (response.statusCode != 200) {
        return _recover(
          ownerId: ownerId,
          firebaseUid: firebaseUid,
          idempotencyKey: idempotencyKey,
        );
      }
      return _parseReceipt(response.body);
    } on AccountDeletionException {
      rethrow;
    } on TimeoutException catch (error) {
      return _recover(
        ownerId: ownerId,
        firebaseUid: firebaseUid,
        idempotencyKey: idempotencyKey,
        cause: error,
      );
    } on http.ClientException catch (error) {
      return _recover(
        ownerId: ownerId,
        firebaseUid: firebaseUid,
        idempotencyKey: idempotencyKey,
        cause: error,
      );
    } catch (error) {
      throw AccountDeletionException(
        AccountDeletionFailureCode.invalidCloudReceipt,
        cause: error,
      );
    }
  }

  Future<CloudDeletionReceipt> _recover({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    bool missingIdentity = false,
    Object? cause,
  }) async {
    try {
      final response = await _client
          .post(
            _baseUri.resolve('/v1/account-deletions/recover'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'ownerId': ownerId,
              'firebaseUid': firebaseUid,
              'idempotencyKey': idempotencyKey,
            }),
          )
          .timeout(timeout);
      if (response.statusCode == 200) return _parseReceipt(response.body);
      throw AccountDeletionException(
        missingIdentity
            ? AccountDeletionFailureCode.reauthenticationRequired
            : AccountDeletionFailureCode.cloudDeleteFailed,
        cause: cause,
      );
    } on AccountDeletionException {
      rethrow;
    } catch (error) {
      throw AccountDeletionException(
        missingIdentity
            ? AccountDeletionFailureCode.reauthenticationRequired
            : AccountDeletionFailureCode.cloudDeleteFailed,
        cause: cause ?? error,
      );
    }
  }

  CloudDeletionReceipt _parseReceipt(String body) {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) throw const FormatException();
    return CloudDeletionReceipt(
      receiptId: json['receiptId'] as String,
      ownerId: json['ownerId'] as String,
      firebaseUid: json['firebaseUid'] as String,
      idempotencyKey: json['idempotencyKey'] as String,
      completedAtUtc: DateTime.parse(json['completedAtUtc'] as String),
    );
  }
}
