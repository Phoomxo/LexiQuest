import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/reading_content_source.dart';
import 'package:vocab_learning_app/voice/reading_voice_enrichment.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

final class _StubVoiceProvider implements VoiceProvider {
  _StubVoiceProvider({this.result, this.failure});

  final VoicePlaybackResult? result;
  final Object? failure;
  VoiceRequest? lastRequest;
  int stopCalls = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    lastRequest = request;
    if (failure case final failure?) {
      throw failure;
    }
    return result!;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

const _content = ReadingContent(
  contentId: 'reading-a2',
  contentVersion: 'curated-v1',
  cefrLevel: 'A2',
  passage: 'A learner can adapt when a familiar plan suddenly changes.',
  targetWords: ['adapt'],
  provenance: ReadingContentProvenance.curated,
);

void main() {
  test('delegates practice playback to the locked voice port', () async {
    final playback = VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: true,
      cacheHit: false,
    );
    final provider = _StubVoiceProvider(result: playback);
    final enrichment = ReadingVoiceEnrichment(provider: provider);

    final result = await enrichment.speak(_content);

    expect(result, isA<ReadingVoicePlayed>());
    expect((result as ReadingVoicePlayed).playback, same(playback));
    expect(provider.lastRequest?.mode, VoiceMode.practice);
    expect(provider.lastRequest?.contentId, _content.contentId);
    expect(provider.lastRequest?.contentType, 'associative-reading');
    expect(provider.lastRequest?.language, 'en');
  });

  test('provider failure is typed and never reported as playback', () async {
    for (final category in VoiceFailureCategory.values) {
      final enrichment = ReadingVoiceEnrichment(
        provider: _StubVoiceProvider(
          failure: VoiceFailure(category: category, message: 'safe'),
        ),
      );

      final result = await enrichment.speak(_content);

      expect(result, isA<ReadingVoiceUnavailable>(), reason: category.name);
      expect(
        (result as ReadingVoiceUnavailable).failure,
        ReadingVoiceFailure.providerFailure,
        reason: category.name,
      );
    }
  });

  test(
    'disabled voice is deterministic and does not require provider',
    () async {
      final result = await const ReadingVoiceEnrichment.disabled().speak(
        _content,
      );

      expect(result, isA<ReadingVoiceUnavailable>());
      expect(
        (result as ReadingVoiceUnavailable).failure,
        ReadingVoiceFailure.disabled,
      );
    },
  );

  test(
    'unexpected provider error is reduced to typed unavailability',
    () async {
      final enrichment = ReadingVoiceEnrichment(
        provider: _StubVoiceProvider(failure: StateError('private detail')),
      );

      final result = await enrichment.speak(_content);

      expect(result, isA<ReadingVoiceUnavailable>());
      expect(
        (result as ReadingVoiceUnavailable).failure,
        ReadingVoiceFailure.providerFailure,
      );
    },
  );
}
