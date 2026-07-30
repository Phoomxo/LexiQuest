import 'dart:typed_data';

import 'package:image/image.dart' as image;

import '../domain/media_practice_contracts.dart';

abstract interface class ImagePreprocessor {
  Uint8List toRawRgb224(Uint8List encodedBytes);
}

final class DartImagePreprocessor implements ImagePreprocessor {
  const DartImagePreprocessor();

  @override
  Uint8List toRawRgb224(Uint8List encodedBytes) {
    image.Image? decoded;
    try {
      decoded = image.decodeImage(encodedBytes);
    } catch (_) {
      throw const CameraPracticeException(CameraFailureCode.invalidImage);
    }
    if (decoded == null) {
      throw const CameraPracticeException(CameraFailureCode.invalidImage);
    }
    final oriented = image.bakeOrientation(decoded);
    final resized = image.copyResizeCropSquare(
      oriented,
      size: 224,
      interpolation: image.Interpolation.linear,
    );
    final rgb = Uint8List(224 * 224 * 3);
    var offset = 0;
    for (final pixel in resized) {
      rgb[offset++] = pixel.r.toInt();
      rgb[offset++] = pixel.g.toInt();
      rgb[offset++] = pixel.b.toInt();
    }
    return rgb;
  }
}
