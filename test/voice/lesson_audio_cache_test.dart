import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_audio_cache.dart';
import 'package:vocab_learning_app/voice/lesson_audio_cache.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

VoiceAudioCacheKey key(String id) => VoiceAudioCacheKey.create(
  request: VoiceRequest.create(
    text: id,
    language: 'en',
    voiceId: 'teacher',
    speed: 1,
    contentId: id,
    contentType: 'audioLesson',
    mode: VoiceMode.practice,
  ),
  engine: VoiceEngine.offlinePack,
  modelVersion: 'v1',
);

void main() {
  test('production cache policy and independent owners', () async {
    final a = LessonAudioCache(requireCurrent: () async {}), b = LessonAudioCache(requireCurrent: () async {});
    expect(a.maxBytes, 20 * 1024 * 1024); expect(a.maxLessons, 10);
    await a.lesson('same').put(key('same'), Uint8List(3));
    expect(await b.lesson('same').get(key('same')), isNull);
    a.retire(); expect(a.totalBytes, 0);
  });
  test('deterministic lesson LRU, byte bound and defensive copies', () async {
    final cache = LessonAudioCache(
      requireCurrent: () async {},
      maxLessons: 2,
      maxBytes: 8,
    );
    final a = cache.lesson('a'), b = cache.lesson('b'), c = cache.lesson('c');
    final bytes = Uint8List.fromList([1, 2, 3]);
    await a.put(key('a'), bytes);
    bytes[0] = 9;
    await b.put(key('b'), Uint8List(3));
    expect((await a.get(key('a')))!.first, 1);
    await c.put(key('c'), Uint8List(3));
    expect(await b.get(key('b')), isNull);
    expect(cache.lessonCount, 2);
    expect(cache.totalBytes, 6);
    await a.put(key('oversize'), Uint8List(9));
    expect(cache.totalBytes, 6);
    await cache.deleteLesson('a');
    await expectLater(a.put(key('late'), Uint8List(1)), throwsStateError);
    expect(cache.lessonCount, 1);
  });
  test('revocation during async admission prevents late cache write', () async {
    final barrier = Completer<void>();
    final cache = LessonAudioCache(requireCurrent: () => barrier.future);
    final scope = cache.lesson('a');
    final write = scope.put(key('a'), Uint8List(3));
    final failure = expectLater(write, throwsStateError);
    cache.retire();
    barrier.complete();
    await failure;
    expect(cache.totalBytes, 0);
  });
}
