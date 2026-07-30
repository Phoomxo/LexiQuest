import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:vocab_learning_app/features/media_practice/application/image_preprocessor.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';

void main() {
  test('decodes and deterministically produces raw 224 RGB bytes', () {
    final source = image.Image(width: 2, height: 2);
    source.setPixelRgb(0, 0, 255, 0, 0);
    source.setPixelRgb(1, 0, 0, 255, 0);
    source.setPixelRgb(0, 1, 0, 0, 255);
    source.setPixelRgb(1, 1, 255, 255, 255);
    final encoded = Uint8List.fromList(image.encodePng(source));
    const preprocessor = DartImagePreprocessor();

    final first = preprocessor.toRawRgb224(encoded);
    final second = preprocessor.toRawRgb224(encoded);

    expect(first, hasLength(224 * 224 * 3));
    expect(first, second);
  });

  test('rejects undecodable capture bytes', () {
    expect(
      () => const DartImagePreprocessor().toRawRgb224(Uint8List(3)),
      throwsA(
        isA<CameraPracticeException>().having(
          (error) => error.code,
          'code',
          CameraFailureCode.invalidImage,
        ),
      ),
    );
  });
}
