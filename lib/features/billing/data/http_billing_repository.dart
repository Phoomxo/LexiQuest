import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/billing_contracts.dart';

final class HttpBillingRepository implements BillingRepository {
  HttpBillingRepository({
    required this.client,
    required Uri baseUri,
    required this.loadIdToken,
    required this.isCurrent,
    this.timeout = const Duration(seconds: 20),
    bool allowInsecureLoopback = false,
  }) : baseUri = _base(baseUri, allowInsecureLoopback);

  final http.Client client;
  final Uri baseUri;
  final Future<String?> Function(BillingAccount account) loadIdToken;
  final bool Function(BillingAccount account) isCurrent;
  final Duration timeout;
  static const maximumResponseBytes = 512 * 1024;
  static final _codePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');

  @override
  Future<BillingCatalog> loadCatalog(
    BillingAccount account, {
    required bool Function() stillCurrent,
  }) async {
    final data = await _request(
      'GET',
      '/v1/billing/catalog',
      account,
      stillCurrent,
    );
    try {
      _keys(data, {
        'schemaVersion',
        'packageName',
        'policyRevision',
        'accountIdentifier',
        'managedContentRequired',
        'products',
      });
      if (data['schemaVersion'] is! int ||
          data['schemaVersion'] != 2 ||
          data['managedContentRequired'] != true) {
        _invalid();
      }
      final packageName = _code(data['packageName']);
      if (packageName != 'com.lexiquest.app') _invalid();
      final accountIdentifier = _text(data['accountIdentifier'], 64);
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(accountIdentifier)) _invalid();
      final raw = _list(data['products'], 64);
      if (raw.isEmpty) _invalid();
      final seen = <String>{};
      final products = <BillingProduct>[];
      for (final value in raw) {
        final row = _map(value);
        _keys(row, {
          'productId',
          'basePlanId',
          'entitlements',
          'dailyManagedUnits',
        });
        final productId = _code(row['productId']);
        final basePlanId = _code(row['basePlanId']);
        if (!seen.add('$productId/$basePlanId')) _invalid();
        final entries = _list(row['entitlements'], 32).map(_code).toList();
        if (entries.length != 1 || entries.single != 'managedContent') {
          _invalid();
        }
        final units = row['dailyManagedUnits'];
        if (units is! int || units < 1 || units > 1000000) _invalid();
        products.add(
          BillingProduct(
            productId: productId,
            basePlanId: basePlanId,
            entitlements: entries.toSet(),
            dailyManagedUnits: units,
          ),
        );
      }
      return BillingCatalog(
        packageName: packageName,
        policyRevision: _code(data['policyRevision']),
        accountIdentifier: accountIdentifier,
        products: products,
      );
    } on BillingException {
      rethrow;
    } on Object {
      _invalid();
    }
  }

  @override
  Future<BillingSnapshot> loadEntitlements(
    BillingAccount account, {
    required bool Function() stillCurrent,
  }) async => _snapshot(
    await _request('GET', '/v1/billing/entitlements', account, stillCurrent),
  );

  @override
  Future<BillingSnapshot> verify(
    BillingAccount account,
    BillingVerification command, {
    required bool Function() stillCurrent,
  }) async {
    if (command.purchaseToken.isEmpty ||
        command.purchaseToken.length > 4096 ||
        command.purchaseToken != command.purchaseToken.trim() ||
        !_codePattern.hasMatch(command.requestId)) {
      throw const BillingException(BillingFailureCode.purchaseDenied);
    }
    return _snapshot(
      await _request(
        'POST',
        '/v1/billing/play/verify',
        account,
        stillCurrent,
        body: {
          'purchaseToken': command.purchaseToken,
          'requestId': command.requestId,
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    BillingAccount account,
    bool Function() stillCurrent, {
    Map<String, Object?>? body,
  }) async {
    void requireCurrent() {
      if (account.isAnonymous || account.firebaseUid.isEmpty) {
        throw const BillingException(BillingFailureCode.accountRequired);
      }
      if (!stillCurrent() || !isCurrent(account)) {
        throw const BillingException(BillingFailureCode.ownerChanged);
      }
    }

    requireCurrent();
    final abort = Completer<void>();
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final token = await loadIdToken(account).timeout(timeout);
      requireCurrent();
      if (token == null ||
          token.isEmpty ||
          token.length > 16384 ||
          token.contains(RegExp(r'[\s\x00-\x1f]'))) {
        throw const BillingException(BillingFailureCode.accountRequired);
      }
      final request =
          http.AbortableRequest(
              method,
              baseUri.resolve(path),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers['authorization'] = 'Bearer $token'
            ..headers['accept'] = 'application/json';
      if (body != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      requireCurrent();
      final response = await client.send(request).timeout(timeout);
      requireCurrent();
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(timeout)) {
        requireCurrent();
        if (bytes.length + chunk.length > maximumResponseBytes) _invalid();
        bytes.addAll(chunk);
      }
      requireCurrent();
      if (response.statusCode != 200) {
        if (response.statusCode == 429) {
          var quota = false;
          try {
            final error = jsonDecode(utf8.decode(bytes));
            quota =
                error is Map &&
                error['detail'] is Map &&
                (error['detail'] as Map)['code'] == 'BILLING_QUOTA_EXHAUSTED';
          } on Object {
            // An unreadable error body still receives the bounded rate limit.
          }
          if (quota) throw const BillingException(BillingFailureCode.quota);
          final seconds =
              int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
          throw BillingException(
            BillingFailureCode.retryLater,
            retryAfter: Duration(
              seconds: seconds >= 1 && seconds <= 3600 ? seconds : 60,
            ),
          );
        }
        throw BillingException(switch (response.statusCode) {
          401 => BillingFailureCode.accountRequired,
          402 => BillingFailureCode.verificationRequired,
          403 => BillingFailureCode.purchaseDenied,
          _ => BillingFailureCode.unavailable,
        });
      }
      if (!(response.headers['content-type'] ?? '').toLowerCase().startsWith(
        'application/json',
      )) {
        _invalid();
      }
      return _map(jsonDecode(utf8.decode(bytes)));
    } on BillingException {
      rethrow;
    } on Object {
      throw const BillingException(BillingFailureCode.unavailable);
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  BillingSnapshot _snapshot(Map<String, dynamic> data) {
    try {
      _keys(data, {
        'schemaVersion',
        'serverTimeUtc',
        'acknowledgementPending',
        'refreshRequired',
        'grants',
      });
      if (data['schemaVersion'] != 1 ||
          data['acknowledgementPending'] is! bool ||
          data['refreshRequired'] is! bool) {
        _invalid();
      }
      final serverTime = _utc(data['serverTimeUtc']);
      final grants = <BillingGrant>[];
      for (final value in _list(data['grants'], 2048)) {
        final row = _map(value);
        _keys(row, {
          'entitlement',
          'expiresAtUtc',
          'checkedAtUtc',
          'dailyManagedUnits',
        });
        final name = _code(row['entitlement']);
        final checked = _utc(row['checkedAtUtc']);
        final expires = _utc(row['expiresAtUtc']);
        final units = row['dailyManagedUnits'];
        if (checked.isAfter(serverTime) ||
            !expires.isAfter(serverTime) ||
            units is! int ||
            units < 0 ||
            units > 1000000) {
          _invalid();
        }
        grants.add(
          BillingGrant(
            entitlement: name,
            expiresAtUtc: expires,
            checkedAtUtc: checked,
            dailyManagedUnits: units,
          ),
        );
      }
      return BillingSnapshot(
        serverTimeUtc: serverTime,
        acknowledgementPending: data['acknowledgementPending']! as bool,
        refreshRequired: data['refreshRequired']! as bool,
        grants: grants,
      );
    } on BillingException {
      rethrow;
    } on Object {
      _invalid();
    }
  }

  static Uri _base(Uri value, bool allowLoopback) {
    final loopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
    }.contains(value.host);
    if ((value.scheme != 'https' &&
            !(allowLoopback && value.scheme == 'http' && loopback)) ||
        value.host.isEmpty ||
        value.userInfo.isNotEmpty ||
        value.hasQuery ||
        value.hasFragment ||
        (value.path.isNotEmpty && value.path != '/')) {
      throw ArgumentError('Billing requires an HTTPS service origin');
    }
    return value;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map<String, dynamic>) _invalid();
    return value;
  }

  static List<Object?> _list(Object? value, int maximum) {
    if (value is! List || value.length > maximum) _invalid();
    return value.cast<Object?>();
  }

  static String _text(Object? value, int maximum) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maximum ||
        value != value.trim() ||
        value.contains(RegExp(r'[\x00-\x1f]'))) {
      _invalid();
    }
    return value;
  }

  static String _code(Object? value) {
    final result = _text(value, 128);
    if (!_codePattern.hasMatch(result)) _invalid();
    return result;
  }

  static DateTime _utc(Object? value) {
    final text = _text(value, 40);
    if (!text.endsWith('Z') && !text.endsWith('+00:00')) _invalid();
    final parsed = DateTime.tryParse(text);
    if (parsed == null || !parsed.isUtc || parsed.millisecondsSinceEpoch < 0) {
      _invalid();
    }
    return parsed;
  }

  static void _keys(Map<String, dynamic> value, Set<String> keys) {
    if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
      _invalid();
    }
  }

  static Never _invalid() =>
      throw const BillingException(BillingFailureCode.invalidResponse);
}
