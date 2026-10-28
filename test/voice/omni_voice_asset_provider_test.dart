import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/omni_voice_asset_provider.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

class TestAssetBundle extends CachingAssetBundle {
  final Map<String, Uint8List> assets = {};

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes != null) {
      return ByteData.sublistView(bytes);
    }
    throw Exception('Asset not found: $key');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestAssetBundle bundle;
  late OmniVoiceAssetProvider provider;

  setUp(() {
    bundle = TestAssetBundle();
    provider = OmniVoiceAssetProvider(bundle: bundle);
  });

  test('getAssetPath formats canonical asset key correctly', () {
    final request = VoiceRequest.create(
      text: 'apple',
      language: 'en',
      voiceId: 'us-female-1',
      speed: 1.0,
      contentId: 'word_apple',
      contentType: 'word',
      mode: VoiceMode.practice,
    );
    expect(
      provider.getAssetPath(request),
      'assets/audio/omni_voice/us-female-1_word_apple.wav',
    );
  });

  test('synthesize loads bytes successfully when asset exists', () async {
    final request = VoiceRequest.create(
      text: 'apple',
      language: 'en',
      voiceId: 'us-female-1',
      speed: 1.0,
      contentId: 'apple',
      contentType: 'word',
      mode: VoiceMode.practice,
    );
    final path = provider.getAssetPath(request);
    bundle.assets[path] = Uint8List.fromList([1, 2, 3, 4]);

    final audio = await provider.synthesize(request);
    expect(audio.bytes, Uint8List.fromList([1, 2, 3, 4]));
    expect(audio.modelVersion, 'offline_v1');
    expect(audio.requestId, 'asset_apple');
  });

  test('synthesize throws VoiceFailure when asset is missing', () async {
    final request = VoiceRequest.create(
      text: 'missing',
      language: 'en',
      voiceId: 'us-female-1',
      speed: 1.0,
      contentId: 'missing_vocab',
      contentType: 'word',
      mode: VoiceMode.practice,
    );

    expect(
      () => provider.synthesize(request),
      throwsA(
        isA<VoiceFailure>().having(
          (f) => f.category,
          'category',
          VoiceFailureCategory.network,
        ),
      ),
    );
  });
}
