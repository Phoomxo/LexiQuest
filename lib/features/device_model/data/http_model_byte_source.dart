import 'dart:async';

import 'package:http/http.dart' as http;

import '../application/model_download_manager.dart';
import '../domain/model_lifecycle.dart';

final class HttpModelByteSource implements ModelByteSource {
  HttpModelByteSource(
    this._client, {
    this.requestTimeout = const Duration(seconds: 30),
  });

  final http.Client _client;
  final Duration requestTimeout;

  @override
  Future<ModelByteResponse> open(
    Uri uri, {
    required int start,
    ModelCancellation? cancellation,
  }) async {
    if (start < 0) {
      throw ArgumentError.value(start, 'start', 'must not be negative');
    }
    if (cancellation?.isCancelled ?? false) {
      throw const ModelLifecycleException(ModelFailureCode.cancelled);
    }
    final abort = Completer<void>();
    cancellation?.whenCancelled.then((_) {
      if (!abort.isCompleted) abort.complete();
    });
    final request = http.AbortableRequest(
      'GET',
      uri,
      abortTrigger: abort.future,
    );
    if (start > 0) {
      request.headers['Range'] = 'bytes=$start-';
    }
    final connectTimer = Timer(requestTimeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final response = await _client.send(request);
      connectTimer.cancel();
      final contentRangeStart = _parseContentRangeStart(
        response.headers['content-range'],
      );
      return ModelByteResponse(
        statusCode: response.statusCode,
        contentRangeStart: contentRangeStart,
        bytes: response.stream
            .timeout(
              requestTimeout,
              onTimeout: (sink) {
                if (!abort.isCompleted) abort.complete();
                sink
                  ..addError(
                    const ModelLifecycleException(ModelFailureCode.network),
                  )
                  ..close();
              },
            )
            .transform(
              StreamTransformer<List<int>, List<int>>.fromHandlers(
                handleError: (error, stackTrace, sink) {
                  if (error is ModelLifecycleException) {
                    sink.addError(error, stackTrace);
                    return;
                  }
                  final code = cancellation?.isCancelled ?? false
                      ? ModelFailureCode.cancelled
                      : ModelFailureCode.network;
                  sink.addError(ModelLifecycleException(code), stackTrace);
                },
              ),
            ),
      );
    } on http.RequestAbortedException {
      final code = cancellation?.isCancelled ?? false
          ? ModelFailureCode.cancelled
          : ModelFailureCode.network;
      throw ModelLifecycleException(code);
    } on http.ClientException {
      throw const ModelLifecycleException(ModelFailureCode.network);
    } finally {
      connectTimer.cancel();
    }
  }

  void close() {
    _client.close();
  }

  static int? _parseContentRangeStart(String? value) {
    if (value == null) return null;
    final match = RegExp(
      r'^bytes ([0-9]+)-([0-9]+)/([0-9]+|\*)$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}
