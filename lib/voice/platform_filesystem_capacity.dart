import 'dart:io';

import 'package:flutter/services.dart';

final class PlatformFilesystemCapacity {
  const PlatformFilesystemCapacity();

  static const _channel = MethodChannel('com.lexiquest.app/storage');

  Future<int> availableBytes(Directory directory) async {
    final path = directory.absolute.path;
    if (path.isEmpty) throw StateError('Filesystem root is unavailable.');
    final bytes = await _channel.invokeMethod<int>(
      'availableBytes',
      <String, Object>{'path': path},
    );
    if (bytes == null || bytes < 0) {
      throw StateError('Filesystem capacity is unavailable.');
    }
    return bytes;
  }
}
