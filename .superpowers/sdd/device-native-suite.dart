import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:camera/camera.dart';
import 'package:vocab_learning_app/voice/native_tts_provider.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import '../../test/features/device_model/litert_image_classifier_test.dart' as classifier;
import '../../test/features/device_model/litert_benchmark_test.dart' as benchmark;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('real LiteRT classifier', classifier.main);
  group('real LiteRT benchmark', benchmark.main);
  testWidgets('native camera inventory is available', (tester) async {
    final cameras = await availableCameras().timeout(const Duration(seconds: 20));
    expect(cameras, isNotEmpty);
    print('NATIVE_CAMERA_INVENTORY count=${cameras.length} directions=${cameras.map((c) => c.lensDirection.name).join(",")}');
  });
  for (final language in ['en', 'th']) {
    testWidgets('native local-only TTS completes $language', (tester) async {
      final adapter = FlutterTtsAdapter();
      final provider = NativeTtsProvider(adapter);
      try {
        final locale = language == 'en' ? 'en-US' : 'th-TH';
        final installed = await adapter.isLanguageInstalled(locale).timeout(const Duration(seconds: 20));
        final voices = await adapter.loadVoices().timeout(const Duration(seconds: 20));
        final offlineCount = voices is Iterable ? voices.where((voice) => voice is Map && voice['locale'].toString().toLowerCase() == locale.toLowerCase() && voice['network_required'] == '0').length : 0;
        print('NATIVE_TTS_CAPABILITY language=$language installed=$installed offline_voices=$offlineCount');
        final result = await provider.speak(VoiceRequest.create(
          text: language == 'en' ? 'Hello. This is a LexiQuest voice test.' : 'สวัสดี นี่คือการทดสอบเสียง',
          language: language, voiceId: 'device-test', speed: 1,
          contentId: 'synthetic-device-test', contentType: 'test',
          mode: VoiceMode.practice, localOnly: true,
        ));
        expect(result.playbackCompleted, isNotNull);
        await result.playbackCompleted!.timeout(const Duration(seconds: 40));
      } finally {
        await provider.stop();
      }
    });
  }
  testWidgets('DEVICE_SUITE_FINAL_SENTINEL', (tester) async {
    binding.reportData = {'suite': 'native-model-and-voice',
      'testResults': binding.results.map((key, value) => MapEntry(key, value.toString()))};
  });
  unawaited(publishService());
}

Future<void> publishService() async {
  final uri = (await developer.Service.getInfo()).serverUri;
  if (uri == null || uri.host != '127.0.0.1') throw StateError('Local VM service unavailable');
  await File('${Directory.systemTemp.path}/lexiquest-core-service-20260907.json')
      .writeAsString(jsonEncode({'uri': uri.toString()}), flush: true);
}
