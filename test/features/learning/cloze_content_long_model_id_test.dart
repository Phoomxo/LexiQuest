import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/features/learning/domain/cloze_content.dart';

void main() {
  test('accepts metadata exactly at the finite UTF8 boundary', () {
    final version = 'm' * ClozeContent.maxModelVersionUtf8Bytes;
    final content = ClozeContent.parse(
      targetSpelling: 'cat',
      response: ContentResponse(
        text: 'The cat sleeps.',
        kind: ContentKind.sentence,
        cefr: CefrLevel.unknown,
        language: 'en',
        modelVersion: version,
        cached: false,
      ),
    );
    expect(content.modelVersion, version);
  });

  test(
    'accepts the maximum model identity emitted by the existing HF backend',
    () {
      final owner = List.filled(96, 'o').join();
      final repository = List.filled(96, 'r').join();
      final revision = List.filled(40, 'a').join();
      final version = '$owner/$repository@$revision';
      expect(version.length, 234);
      final content = ClozeContent.parse(
        targetSpelling: 'cat',
        response: ContentResponse(
          text: 'The cat sleeps.',
          kind: ContentKind.sentence,
          cefr: CefrLevel.unknown,
          language: 'en',
          modelVersion: version,
          cached: false,
        ),
      );
      expect(content.modelVersion, version);
      expect(content.gapText, 'cat');
    },
  );
}
