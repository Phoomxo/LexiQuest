import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'voice_models.dart';

const _timeout = VoiceFailure(
  category: VoiceFailureCategory.timeout,
  message: 'The voice service took too long to respond.',
);
const _oversized = VoiceFailure(
  category: VoiceFailureCategory.synthesis,
  message: 'The voice response exceeded its byte budget.',
);

/// One deadline covers token acquisition, authentication retry and body reads.
/// Abortable clients terminate transport work; even clients without abort
/// support cannot attach a late response or accumulate an unbounded body.
final class VoiceHttpOperation {
  final _abort = Completer<void>();
  StreamIterator<List<int>>? _body;
  bool _closed = false;

  void checkActive() {
    if (_closed) throw _timeout;
  }

  Future<T> run<T>(Duration timeout, Future<T> Function() action) async {
    try {
      return await action().timeout(timeout, onTimeout: () => throw _timeout);
    } finally {
      _closed = true;
      if (!_abort.isCompleted) _abort.complete();
      await _body?.cancel();
    }
  }

  Future<http.Response> post(
    http.Client client,
    Uri uri,
    Map<String, String> headers,
    String body,
  ) async {
    checkActive();
    final request =
        http.AbortableRequest('POST', uri, abortTrigger: _abort.future)
          ..headers.addAll(headers)
          ..body = body;
    final response = await client.send(request);
    if (_closed) {
      await response.stream.listen(null).cancel();
      throw _timeout;
    }
    final budget = response.statusCode == 200 ? 8 * 1024 * 1024 : 64 * 1024;
    if ((response.contentLength ?? 0) > budget) {
      // StreamIterator subscribes lazily: cancelling it before moveNext would
      // leave an unopened response stream (and its transport) undisposed.
      await response.stream.listen(null).cancel();
      throw _oversized;
    }
    final iterator = StreamIterator<List<int>>(response.stream);
    _body = iterator;
    try {
      final bytes = BytesBuilder(copy: false);
      while (await iterator.moveNext()) {
        checkActive();
        final chunk = iterator.current;
        if (chunk.length > budget - bytes.length) throw _oversized;
        bytes.add(chunk);
      }
      checkActive();
      return http.Response.bytes(
        bytes.takeBytes(),
        response.statusCode,
        headers: response.headers,
        request: response.request,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } finally {
      await iterator.cancel();
      if (identical(_body, iterator)) _body = null;
    }
  }
}
