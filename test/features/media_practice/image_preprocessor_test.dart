import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:vocab_learning_app/features/media_practice/application/image_preprocessor.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';

void main() {
  test('R15.6 center crop excludes side bands and preserves raw RGB order', () {
    final source = image.Image(width: 448, height: 224);
    for (final pixel in source) {
      pixel.setRgb(
        pixel.x < 112 || pixel.x >= 336 ? 255 : 17,
        pixel.x < 112 || pixel.x >= 336 ? 0 : 83,
        pixel.x < 112 || pixel.x >= 336 ? 0 : 201,
      );
    }
    final rgb = const DartImagePreprocessor().toRawRgb224(
      Uint8List.fromList(image.encodePng(source)),
    );
    expect(rgb, hasLength(224 * 224 * 3));
    for (var offset = 0; offset < rgb.length; offset += 3) {
      expect(rgb.sublist(offset, offset + 3), [17, 83, 201]);
    }
  });

  test('R15.6 JPEG EXIF rotation is applied once before RGB conversion', () {
    final source = image.Image(width: 224, height: 224);
    for (final pixel in source) {
      pixel.setRgb(pixel.y < 112 ? 240 : 10, pixel.y < 112 ? 20 : 220, 30);
    }
    source.exif.imageIfd.orientation = 6;
    final encoded = Uint8List.fromList(image.encodeJpg(source, quality: 100));
    final rgb = const DartImagePreprocessor().toRawRgb224(encoded);
    // EXIF 6 rotates clockwise: the green bottom half becomes the left half.
    final left = (112 * 224 + 28) * 3;
    final right = (112 * 224 + 196) * 3;
    expect(rgb[left], closeTo(10, 3));
    expect(rgb[left + 1], closeTo(220, 3));
    expect(rgb[left + 2], closeTo(30, 3));
    expect(rgb[right], closeTo(240, 3));
    expect(rgb[right + 1], closeTo(20, 3));
    expect(rgb[right + 2], closeTo(30, 3));
  });

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
