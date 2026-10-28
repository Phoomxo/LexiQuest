import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/soundscape_audio_service.dart';

void main() {
  final service = SoundscapeAudioService();

  test('SoundscapeAudioService manages current background audio type', () {
    expect(service.currentType, SoundscapeType.off);

    service.setSoundscape(SoundscapeType.alphaWaves);
    expect(service.currentType, SoundscapeType.alphaWaves);

    service.stop();
    expect(service.currentType, SoundscapeType.off);
  });
}
