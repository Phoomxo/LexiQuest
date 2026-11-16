final class SyncMutex {
  final Set<String> _activeKeys = <String>{};

  bool tryAcquire(String key) {
    final canonical = key.trim();
    if (canonical.isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be blank');
    }
    return _activeKeys.add(canonical);
  }

  void release(String key) {
    if (!_activeKeys.remove(key)) {
      throw StateError('sync mutex was not acquired');
    }
  }
}
