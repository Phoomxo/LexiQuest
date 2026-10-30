import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/features/learning/domain/cloze_content.dart';

void main() {
  test(
    'accepts actual HF backend model-id at immutable revision response shape',
    () {
      // ServingSettings permits ASCII underscore repo IDs and emits id@40hex.
      const version =
          'synthetic_owner/lexiquest_lm@0123456789abcdef0123456789abcdef01234567';
      final content = ClozeContent.parse(
        targetSpelling: 'cat',
        response: _response(modelVersion: version),
      );
      expect(content.modelVersion, version);
      expect(content.cefr, CefrLevel.unknown);
      expect(content.cached, isTrue);
      expect(content.gapText, 'cat');
    },
  );

  test(
    'keeps bounded opaque revision punctuation accepted by ContentProvider',
    () {
      const version = 'synthetic_revision#0123456789abcdef';
      expect(
        ClozeContent.parse(
          targetSpelling: 'cat',
          response: _response(modelVersion: version),
        ).modelVersion,
        version,
      );
    },
  );

  for (final version in [
    '',
    ' ',
    '<model>',
    'owner/model<script>',
    'owner/model>',
    'm\nv1',
    'm\u0000v1',
    'm\u007fv1',
    'm\u0085v1',
    'm\u200bv1',
    'm\u202ev1',
    'm\u2066v1',
    'm\ufeffv1',
    String.fromCharCode(0xd800),
    'm' * (ClozeContent.maxModelVersionRunes + 1),
    '界' * 100,
  ]) {
    test(
      'model metadata retains size HTML and control rejection (${version.codeUnits})',
      () {
        expect(
          () => ClozeContent.parse(
            targetSpelling: 'cat',
            response: _response(modelVersion: version),
          ),
          throwsFormatException,
        );
      },
    );
  }

  for (final text in [
    '# The cat sleeps.',
    '_The cat sleeps._',
    '**The cat sleeps.**',
    '<b>The cat sleeps.</b>',
  ]) {
    test(
      'metadata punctuation admission does not relax sentence markup ($text)',
      () {
        expect(
          () => ClozeContent.parse(
            targetSpelling: 'cat',
            response: _response(
              text: text,
              modelVersion: 'synthetic_revision#abc',
            ),
          ),
          throwsFormatException,
        );
      },
    );
  }
}

ContentResponse _response({
  String text = 'The cat sleeps.',
  required String modelVersion,
}) => ContentResponse(
  text: text,
  kind: ContentKind.sentence,
  cefr: CefrLevel.unknown,
  language: 'en',
  modelVersion: modelVersion,
  cached: true,
);
