import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/content_report.dart';
import '../domain/content_report_transport.dart';

final class HttpContentReportTransport implements ContentReportTransport {
  HttpContentReportTransport({
    required this.client,
    required Uri baseUri,
    required this.identity,
    this.enabled = false,
    this.timeout = const Duration(seconds: 20),
  }) : baseUri = _origin(baseUri) {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 2)) {
      throw ArgumentError('A bounded content report timeout is required');
    }
  }
  final http.Client client;
  final Uri baseUri;
  final ContentReportIdentityPorts identity;
  @override
  final bool enabled;
  final Duration timeout;

  @override
  ContentReportIdentityBinding? get currentBinding =>
      enabled ? identity.currentBinding() : null;

  void _current(ContentReportIdentityBinding binding) {
    if (!enabled) {
      throw const ContentReportException(ContentReportFailureCode.disabled);
    }
    if (identity.currentBinding() != binding) {
      throw const ContentReportException(ContentReportFailureCode.ownerChanged);
    }
  }

  @override
  Future<void> requireCurrent(ContentReportIdentityBinding binding) async {
    _current(binding);
    await identity.requireCurrent(binding);
    _current(binding);
  }

  @override
  Future<ContentReportAcknowledgement> submit(
    ContentReportIdentityBinding binding,
    ContentReportPayload payload,
  ) async {
    final body = jsonEncode(payload.toSubmissionJson());
    if (utf8.encode(body).length > 100000) {
      throw const ContentReportException(ContentReportFailureCode.rejected);
    }
    final response = await _request(
      'POST',
      '/v1/content-reports',
      binding,
      body: body,
    );
    return _acknowledgement(response!, binding, payload);
  }

  @override
  Future<ContentReportAcknowledgement?> readReceipt(
    ContentReportIdentityBinding binding,
    ContentReportPayload payload,
  ) async {
    final response = await _request(
      'GET',
      '/v1/content-reports/receipt',
      binding,
      query: {'reportId': payload.reportId},
      allowAbsent: true,
    );
    return response == null
        ? null
        : _acknowledgement(response, binding, payload);
  }

  ContentReportAcknowledgement _acknowledgement(
    String body,
    ContentReportIdentityBinding binding,
    ContentReportPayload payload,
  ) {
    try {
      _current(binding);
      final acknowledgement = ContentReportAcknowledgement.fromResponseJson(
        body,
      );
      acknowledgement.requireMatches(payload);
      final key = contentReportDigest(
        jsonEncode([binding.firebaseUid, payload.reportId]),
      );
      if (acknowledgement.receipt.receiptId != 'content-report-receipt:$key') {
        throw const FormatException('Wrong content report receipt identity');
      }
      return acknowledgement;
    } on FormatException {
      throw const ContentReportException(
        ContentReportFailureCode.invalidResponse,
      );
    }
  }

  Future<String?> _request(
    String method,
    String path,
    ContentReportIdentityBinding binding, {
    String? body,
    Map<String, String>? query,
    bool allowAbsent = false,
  }) async {
    _current(binding);
    final abort = Completer<void>();
    var finished = false;
    void cancel() {
      if (!abort.isCompleted) abort.complete();
    }

    final ownerWatch = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!finished && identity.currentBinding() != binding) cancel();
    });
    Future<String?> execute() async {
      await requireCurrent(binding);
      if (finished) {
        throw const ContentReportException(
          ContentReportFailureCode.unavailable,
        );
      }
      final token = await identity.loadIdToken(binding);
      await requireCurrent(binding);
      if (token == null ||
          token.isEmpty ||
          token != token.trim() ||
          token.length > 16384 ||
          token.contains(RegExp(r'\s'))) {
        throw const ContentReportException(
          ContentReportFailureCode.accountRequired,
        );
      }
      final uri = baseUri.resolve(path).replace(queryParameters: query);
      final request = _OwnerBoundReportRequest(
        method,
        uri,
        abortTrigger: abort.future,
        requireCurrent: () {
          _current(binding);
          if (finished) {
            throw const ContentReportException(
              ContentReportFailureCode.unavailable,
            );
          }
        },
      )..followRedirects = false;
      request.headers.addAll({
        'authorization': 'Bearer $token',
        'accept': 'application/json',
        'cache-control': 'no-store',
      });
      if (body != null) {
        request.headers['content-type'] = 'application/json; charset=utf-8';
        request.body = body;
      }
      await requireCurrent(binding);
      if (finished) {
        throw const ContentReportException(
          ContentReportFailureCode.unavailable,
        );
      }
      _current(binding);
      final response = await client.send(request);
      await requireCurrent(binding);
      if (response.contentLength != null && response.contentLength! > 16384) {
        throw const ContentReportException(
          ContentReportFailureCode.invalidResponse,
        );
      }
      final bytes = BytesBuilder(copy: false);
      var count = 0;
      await for (final chunk in response.stream) {
        _current(binding);
        if (finished) {
          throw const ContentReportException(
            ContentReportFailureCode.unavailable,
          );
        }
        count += chunk.length;
        if (count > 16384) {
          throw const ContentReportException(
            ContentReportFailureCode.invalidResponse,
          );
        }
        bytes.add(chunk);
      }
      await requireCurrent(binding);
      if (allowAbsent && response.statusCode == 404) return null;
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ContentReportException(
          ContentReportFailureCode.accountRequired,
        );
      }
      if (response.statusCode == 409) {
        throw const ContentReportException(ContentReportFailureCode.collision);
      }
      if (response.statusCode == 429) {
        throw const ContentReportException(ContentReportFailureCode.retryLater);
      }
      if (response.statusCode == 400 ||
          response.statusCode == 413 ||
          response.statusCode == 422) {
        throw const ContentReportException(ContentReportFailureCode.rejected);
      }
      if (response.statusCode != 200) {
        throw ContentReportException(
          method == 'POST'
              ? ContentReportFailureCode.unconfirmed
              : ContentReportFailureCode.unavailable,
        );
      }
      return utf8.decode(bytes.takeBytes());
    }

    try {
      return await Future.any<String?>([
        execute(),
        abort.future.then(
          (_) => throw const ContentReportException(
            ContentReportFailureCode.ownerChanged,
          ),
        ),
      ]).timeout(timeout);
    } on ContentReportException {
      rethrow;
    } on FormatException {
      throw const ContentReportException(
        ContentReportFailureCode.invalidResponse,
      );
    } on Object {
      _current(binding);
      throw ContentReportException(
        method == 'POST'
            ? ContentReportFailureCode.unconfirmed
            : ContentReportFailureCode.unavailable,
      );
    } finally {
      finished = true;
      ownerWatch.cancel();
      cancel();
    }
  }
}

final class _OwnerBoundReportRequest extends http.Request with http.Abortable {
  _OwnerBoundReportRequest(
    super.method,
    super.url, {
    required this.abortTrigger,
    required this.requireCurrent,
  });
  @override
  final Future<void>? abortTrigger;
  final void Function() requireCurrent;
  @override
  http.ByteStream finalize() => http.ByteStream(
    super.finalize().map((bytes) {
      requireCurrent();
      return bytes;
    }),
  );
}

Uri _origin(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw ArgumentError(
      'Content report transport requires a configured HTTPS origin',
    );
  }
  return uri;
}
