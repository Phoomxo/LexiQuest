import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/native_tts_provider.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

void main() {
  for (final stage in ['language', 'rate', 'volume', 'pitch']) {
    test(
      'stop during $stage configuration prevents late native speech',
      () async {
        final adapter = _DelayedNativeAdapter(stage);
        final provider = NativeTtsProvider(adapter);
        final pending = provider.speak(_request('retired'));
        final cancelled = expectLater(pending, throwsA(_cancelled));
        await adapter.entered.future;
        await provider.stop();
        adapter.release.complete();
        await cancelled;
        expect(adapter.spoken, isEmpty);
        expect(adapter.stops, 1);
      },
    );
  }

  test('a newer request supersedes speech waiting on configuration', () async {
    final adapter = _DelayedNativeAdapter('language');
    final provider = NativeTtsProvider(adapter);
    final first = provider.speak(_request('retired'));
    final cancelled = expectLater(first, throwsA(_cancelled));
    await adapter.entered.future;
    final current = await provider.speak(_request('current'));
    adapter.release.complete();
    await cancelled;
    expect(adapter.spoken, ['current']);
    expect(current.actualEngine, VoiceEngine.nativeTts);
  });

  test(
    'stop retires an utterance whose start acknowledgement is pending',
    () async {
      final adapter = _DelayedNativeAdapter('speak');
      final provider = NativeTtsProvider(adapter);
      final pending = provider.speak(_request('started'));
      final cancelled = expectLater(pending, throwsA(_cancelled));
      await adapter.entered.future;
      expect(adapter.spoken, ['started']);
      await provider.stop();
      adapter.release.complete();
      await cancelled;
      expect(adapter.stops, 1);
      expect(adapter.spoken, ['started']);
    },
  );

  test('a failed stop still retires speech waiting on configuration', () async {
    final adapter = _DelayedNativeAdapter('language', stopFails: true);
    final provider = NativeTtsProvider(adapter);
    final pending = provider.speak(_request('retired'));
    final cancelled = expectLater(pending, throwsA(_cancelled));
    await adapter.entered.future;
    await expectLater(
      provider.stop(),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.playback,
        ),
      ),
    );
    adapter.release.complete();
    await cancelled;
    expect(adapter.spoken, isEmpty);
  });

  test(
    'an uninterrupted configuration starts exactly the requested utterance',
    () async {
      final adapter = _DelayedNativeAdapter('pitch');
      final pending = NativeTtsProvider(adapter).speak(_request('current'));
      await adapter.entered.future;
      expect(adapter.spoken, isEmpty);
      adapter.release.complete();
      final result = await pending;
      expect(adapter.spoken, ['current']);
      expect(result.actualEngine, VoiceEngine.nativeTts);
      expect(result.usedFallback, isFalse);
      expect(adapter.stops, 0);
    },
  );
}

final _cancelled = isA<VoiceFailure>().having(
  (failure) => failure.category,
  'category',
  VoiceFailureCategory.cancelled,
);

VoiceRequest _request(String text) => VoiceRequest.create(
  text: text,
  language: 'en',
  voiceId: 'teacher_female',
  speed: 1,
  contentId: 'synthetic-native-cancellation',
  contentType: 'word',
  mode: VoiceMode.practice,
);

final class _DelayedNativeAdapter implements NativeTtsAdapter {
  _DelayedNativeAdapter(this.delayedStage, {this.stopFails = false});

  final String delayedStage;
  final bool stopFails;
  final entered = Completer<void>();
  final release = Completer<void>();
  final spoken = <String>[];
  var stops = 0;
  var _delayed = false;

  Future<void> _configure(String stage) async {
    if (stage == delayedStage && !_delayed) {
      _delayed = true;
      entered.complete();
      await release.future;
    }
  }

  @override
  Future<void> setLanguage(String language) => _configure('language');
  @override
  Future<void> setSpeechRate(double rate) => _configure('rate');
  @override
  Future<void> setVolume(double volume) => _configure('volume');
  @override
  Future<void> setPitch(double pitch) => _configure('pitch');
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    await _configure('speak');
  }

  @override
  Future<void> stop() async {
    stops++;
    if (stopFails) throw StateError('Synthetic stop failure');
  }
}
