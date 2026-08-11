import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/ai_tutor_contracts.dart';

const _maximumResponseBytes = 256 * 1024;

Uri normalizeAiApiBaseUri(Uri baseUri) {
  final path = baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/';
  return baseUri.replace(path: path);
}

String normalizeAiApiKey(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > 512 ||
      normalized != value ||
      normalized.contains(RegExp(r'[\s\x00-\x1F\x7F]'))) {
    throw const AiTutorException(AiFailureCode.invalidKey);
  }
  return normalized;
}

AiTutorException aiFailureForHttpStatus(int statusCode) => switch (statusCode) {
  401 || 403 => const AiTutorException(AiFailureCode.invalidKey),
  402 => const AiTutorException(AiFailureCode.quota),
  408 => const AiTutorException(AiFailureCode.timeout),
  429 => const AiTutorException(AiFailureCode.rateLimited),
  >= 400 && < 500 => const AiTutorException(AiFailureCode.requestRejected),
  _ => const AiTutorException(AiFailureCode.providerUnavailable),
};

/// Sends and drains one request under a single absolute, abortable budget.
Future<http.Response> sendAbortableAiRequest({
  required http.Client client,
  required http.Request request,
  required Duration timeout,
  AiCancellation? cancellation,
}) async {
  if (cancellation?.isCancelled ?? false) {
    throw const AiTutorException(AiFailureCode.cancelled);
  }
  final abort = Completer<void>();
  _AiHttpAbortCause? abortCause;
  void requestAbort(_AiHttpAbortCause cause) {
    if (abortCause != null) return;
    abortCause = cause;
    if (!abort.isCompleted) abort.complete();
  }

  final abortable =
      http.AbortableRequest(
          request.method,
          request.url,
          abortTrigger: abort.future,
        )
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes;
  if (cancellation != null) {
    unawaited(
      cancellation.whenCancelled.then((_) {
        requestAbort(_AiHttpAbortCause.caller);
      }),
    );
  }
  try {
    final operation = () async {
      final streamed = await client.send(abortable);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream) {
        if (bytes.length + chunk.length > _maximumResponseBytes) {
          throw const AiTutorException(AiFailureCode.malformedResponse);
        }
        bytes.add(chunk);
      }
      return http.Response.bytes(
        Uint8List.fromList(bytes.takeBytes()),
        streamed.statusCode,
        headers: streamed.headers,
        request: streamed.request,
        reasonPhrase: streamed.reasonPhrase,
      );
    }();
    final response = await operation.timeout(
      timeout,
      onTimeout: () {
        requestAbort(
          cancellation?.isCancelled ?? false
              ? _AiHttpAbortCause.caller
              : _AiHttpAbortCause.timeout,
        );
        throw AiTutorException(
          abortCause == _AiHttpAbortCause.caller
              ? AiFailureCode.cancelled
              : AiFailureCode.timeout,
        );
      },
    );
    return response;
  } on http.RequestAbortedException {
    if (abortCause == _AiHttpAbortCause.timeout) {
      throw const AiTutorException(AiFailureCode.timeout);
    }
    if (abortCause == _AiHttpAbortCause.caller) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    throw const AiTutorException(AiFailureCode.offline);
  } on TimeoutException {
    throw const AiTutorException(AiFailureCode.timeout);
  } on http.ClientException {
    throw const AiTutorException(AiFailureCode.offline);
  } on AiTutorException {
    rethrow;
  } on Object {
    throw const AiTutorException(AiFailureCode.providerUnavailable);
  }
}

enum _AiHttpAbortCause { caller, timeout }
