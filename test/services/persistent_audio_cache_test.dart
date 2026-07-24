import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/persistent_audio_cache.dart';

void main() {
  late Directory tempDir;
  late PersistentAudioCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_cache_test_');
    cache = PersistentAudioCache(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('PersistentAudioCache stores and retrieves WAV bytes', () async {
    final sampleBytes = Uint8List.fromList([82, 73, 70, 70, 0, 1, 2, 3]);
    expect(await cache.containsKey('apple'), false);

    await cache.put('apple', sampleBytes);
    expect(await cache.containsKey('apple'), true);

    final retrieved = await cache.get('apple');
    expect(retrieved, isNotNull);
    expect(retrieved, sampleBytes);
  });
}
