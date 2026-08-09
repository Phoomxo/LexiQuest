import 'dart:async';

typedef ResourceDisposer = FutureOr<void> Function();

/// Owns composed resources and releases them in reverse construction order.
final class ResourceDisposerStack {
  final List<ResourceDisposer> _disposers = <ResourceDisposer>[];
  Future<void>? _disposeFuture;

  void own(ResourceDisposer disposer) {
    _disposers.add(disposer);
  }

  Future<void> dispose() {
    return _disposeFuture ??= _disposeAll();
  }

  Future<void> disposeAfterFailure() async {
    try {
      await dispose();
    } catch (_) {
      // Preserve the initialization failure after exhausting cleanup.
    }
  }

  Future<void> _disposeAll() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final disposer in _disposers.reversed) {
      try {
        await Future<void>.sync(disposer);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}
