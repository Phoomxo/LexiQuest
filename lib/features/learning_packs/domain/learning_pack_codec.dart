part of 'learning_pack.dart';

final class LearningPackCodec {
  const LearningPackCodec();

  LearningPackManifest decodeManifest(String text) {
    final manifest = _object(_storedJson(text, 65536), _manifestKeys);
    return LearningPackManifest._(
      metadata: _metadata(manifest),
      entryCount: _integer(manifest['entryCount'], 1, maxLearningPackEntries),
      payloadSha256: _hash(manifest['payloadSha256']),
      payloadBytes: _integer(manifest['payloadBytes'], 1, maxLearningPackBytes),
    );
  }

  LearningPackEntry decodeEntry(String text) =>
      _entry(_storedJson(text, 65536));

  LearningPackRetainedMedia decodeRetainedMedia(String text) {
    final value = _object(_storedJson(text, maxLearningPackBytes), const {
      'schemaVersion',
      'entryCodes',
      'images',
    });
    if (value['schemaVersion'] != 1 || value['schemaVersion'] is! int) {
      _packFail(LearningPackFailureCode.unsupportedVersion);
    }
    final codes = [
      for (final code in _list(value['entryCodes'], 1, maxLearningPackEntries))
        _code(code),
    ];
    if (codes.toSet().length != codes.length) {
      _packFail(LearningPackFailureCode.duplicateIdentity);
    }
    final images = <LearningPackImage>[];
    final ids = <String>{};
    var pixels = 0;
    for (final raw in _list(value['images'], 0, maxLearningPackImages)) {
      final asset = _image(
        raw,
        maximumPixels: maxLearningPackTotalImagePixels - pixels,
      );
      if (!ids.add(asset.id)) {
        _packFail(LearningPackFailureCode.duplicateIdentity);
      }
      pixels += asset.width * asset.height;
      images.add(asset);
    }
    return LearningPackRetainedMedia._(entryCodes: codes, images: images);
  }

  LearningPack restoreContent({
    required LearningPackManifest manifest,
    required List<LearningPackEntry> entries,
    required LearningPackRetainedMedia media,
  }) {
    final byCode = {for (final entry in entries) entry.code: entry};
    if (entries.length != byCode.length ||
        media.entryCodes.length != manifest.entryCount ||
        byCode.length != media.entryCodes.length ||
        media.entryCodes.any((code) => !byCode.containsKey(code))) {
      _packFail(LearningPackFailureCode.invalidReference);
    }
    return decode(
      Uint8List.fromList(
        utf8.encode(
          _canonicalJson({
            'schema': 'lexiquest.learning-pack.v1',
            'schemaVersion': 1,
            'manifest': manifest.toJson(),
            'payload': {
              'entries': [
                for (final code in media.entryCodes) byCode[code]!.toJson(),
              ],
              'images': [for (final asset in media.images) asset.toJson()],
            },
          }),
        ),
      ),
    );
  }

  Uint8List encode({
    required LearningPackMetadata metadata,
    required List<LearningPackEntry> entries,
    List<LearningPackImage> images = const [],
  }) {
    if (entries.isEmpty) _packFail(LearningPackFailureCode.invalidFormat);
    if (entries.length > maxLearningPackEntries ||
        images.length > maxLearningPackImages) {
      _packFail(LearningPackFailureCode.tooLarge);
    }
    _metadata(_metadataJson(metadata));
    for (final entry in entries) {
      _entry(entry.toJson());
    }
    for (final asset in images) {
      if (asset.byteCount > maxLearningPackImageBytes) {
        _packFail(LearningPackFailureCode.tooLarge);
      }
    }
    final payload = <String, Object?>{
      'entries': [for (final entry in entries) entry.toJson()],
      'images': [for (final asset in images) asset.toJson()],
    };
    final payloadBytes = utf8.encode(_canonicalJson(payload));
    final encoded = Uint8List.fromList(
      utf8.encode(
        _canonicalJson({
          'schema': 'lexiquest.learning-pack.v1',
          'schemaVersion': 1,
          'manifest': {
            ..._metadataJson(metadata),
            'entryCount': entries.length,
            'payloadBytes': payloadBytes.length,
            'payloadSha256': _digest(payloadBytes),
          },
          'payload': payload,
        }),
      ),
    );
    decode(encoded);
    return encoded;
  }

  LearningPack decode(Uint8List bytes, {String? expectedPackageSha256}) {
    if (bytes.isEmpty) _packFail(LearningPackFailureCode.invalidFormat);
    if (bytes.length > maxLearningPackBytes) {
      _packFail(LearningPackFailureCode.tooLarge);
    }
    if (expectedPackageSha256 != null) {
      _hash(expectedPackageSha256);
      if (_digest(bytes) != expectedPackageSha256) {
        _packFail(LearningPackFailureCode.integrityMismatch);
      }
    }
    late final Object? decoded;
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      _checkJsonKeysAndDepth(text);
      decoded = jsonDecode(text);
    } on LearningPackException {
      rethrow;
    } on Object {
      _packFail(LearningPackFailureCode.invalidFormat);
    }
    final envelope = _object(decoded, const {
      'schema',
      'schemaVersion',
      'manifest',
      'payload',
    });
    if (envelope['schema'] != 'lexiquest.learning-pack.v1' ||
        envelope['schemaVersion'] != 1 ||
        envelope['schemaVersion'] is! int) {
      _packFail(LearningPackFailureCode.unsupportedVersion);
    }
    final manifest = _object(envelope['manifest'], _manifestKeys);
    final payload = _object(envelope['payload'], const {'entries', 'images'});
    final rawEntries = _list(payload['entries'], 1, maxLearningPackEntries);
    final rawImages = _list(payload['images'], 0, maxLearningPackImages);
    final count = _integer(manifest['entryCount'], 1, maxLearningPackEntries);
    final byteCount = _integer(
      manifest['payloadBytes'],
      1,
      maxLearningPackBytes,
    );
    final payloadHash = _hash(manifest['payloadSha256']);
    final payloadBytes = utf8.encode(_canonicalJson(payload));
    if (count != rawEntries.length ||
        payloadBytes.length != byteCount ||
        _digest(payloadBytes) != payloadHash) {
      _packFail(LearningPackFailureCode.integrityMismatch);
    }
    final metadata = _metadata(manifest);
    final entries = [for (final entry in rawEntries) _entry(entry)];
    final codes = <String>{};
    final spellings = <String>{};
    for (final entry in entries) {
      if (!codes.add(entry.code) ||
          !spellings.add(_normalize(entry.spelling))) {
        _packFail(LearningPackFailureCode.duplicateIdentity);
      }
    }
    var totalPixels = 0;
    final images = <LearningPackImage>[];
    final imageIds = <String>{};
    for (final raw in rawImages) {
      final asset = _image(
        raw,
        maximumPixels: maxLearningPackTotalImagePixels - totalPixels,
      );
      if (!imageIds.add(asset.id)) {
        _packFail(LearningPackFailureCode.duplicateIdentity);
      }
      totalPixels += asset.width * asset.height;
      if (totalPixels > maxLearningPackTotalImagePixels) {
        _packFail(LearningPackFailureCode.tooLarge);
      }
      images.add(asset);
    }
    final referencedImages = <String>{};
    for (final entry in entries) {
      if (entry.imageId case final imageId?) {
        if (!imageIds.contains(imageId)) {
          _packFail(LearningPackFailureCode.invalidReference);
        }
        referencedImages.add(imageId);
      }
      final question = entry.definitionQuestion;
      if (question == null) continue;
      if (entry.definition == null ||
          metadata.language.split('-').first != 'en') {
        _packFail(LearningPackFailureCode.invalidReference);
      }
      final optionCodes = <String>{};
      final optionEntries = <String>{};
      LearningPackDefinitionOption? correct;
      for (final option in question.options) {
        if (!optionCodes.add(option.code) ||
            !optionEntries.add(option.entryCode)) {
          _packFail(LearningPackFailureCode.duplicateIdentity);
        }
        if (!codes.contains(option.entryCode)) {
          _packFail(LearningPackFailureCode.invalidReference);
        }
        if (option.code == question.correctOptionCode) correct = option;
      }
      if (correct == null ||
          correct.entryCode != entry.code ||
          correct.contrastiveExplanation != null) {
        _packFail(LearningPackFailureCode.invalidReference);
      }
    }
    if (referencedImages.length != imageIds.length) {
      _packFail(LearningPackFailureCode.invalidReference);
    }
    return LearningPack._(
      manifest: LearningPackManifest._(
        metadata: metadata,
        entryCount: count,
        payloadSha256: payloadHash,
        payloadBytes: byteCount,
      ),
      entries: entries,
      images: images,
      packageBytes: bytes,
    );
  }
}

const _manifestKeys = {
  'packId',
  'version',
  'title',
  'objectives',
  'cefrLevel',
  'language',
  'meaningLanguage',
  'provenance',
  'entryCount',
  'payloadSha256',
  'payloadBytes',
};

Object? _storedJson(String text, int maximumBytes) {
  if (utf8.encode(text).length > maximumBytes) {
    _packFail(LearningPackFailureCode.tooLarge);
  }
  try {
    _checkJsonKeysAndDepth(text);
    return jsonDecode(text);
  } on LearningPackException {
    rethrow;
  } on Object {
    _packFail(LearningPackFailureCode.invalidFormat);
  }
}

LearningPackMetadata _metadata(Map<String, Object?> value) {
  final provenance = _object(value['provenance'], const {
    'author',
    'source',
    'sourceUri',
    'license',
    'attribution',
  });
  final cefr = _text(value['cefrLevel'], 2);
  if (!const {'A1', 'A2', 'B1', 'B2', 'C1', 'C2'}.contains(cefr)) {
    _packFail(LearningPackFailureCode.invalidFormat);
  }
  final objectives = [
    for (final objective in _list(value['objectives'], 1, 10))
      _text(objective, 300),
  ];
  if (objectives.toSet().length != objectives.length) {
    _packFail(LearningPackFailureCode.duplicateIdentity);
  }
  return LearningPackMetadata(
    packId: _code(value['packId']),
    version: _code(value['version'], max: 40),
    title: _text(value['title'], 160),
    objectives: objectives,
    cefrLevel: cefr,
    language: _language(value['language']),
    meaningLanguage: _language(value['meaningLanguage']),
    provenance: LearningPackProvenance(
      author: _text(provenance['author'], 200),
      source: _text(provenance['source'], 500),
      sourceUri: provenance['sourceUri'] == null
          ? null
          : _sourceUri(provenance['sourceUri']),
      license: _text(provenance['license'], 200),
      attribution: _text(provenance['attribution'], 1000),
    ),
  );
}

LearningPackEntry _entry(Object? raw) {
  final value = _object(raw, const {
    'code',
    'spelling',
    'meaning',
    'partOfSpeech',
    'definition',
    'examples',
    'imageId',
    'memoryCue',
    'hint',
    'strategy',
    'definitionQuestion',
  });
  final examples = <LearningPackExample>[];
  for (final rawExample in _list(value['examples'], 0, 5)) {
    final example = _object(rawExample, const {'text', 'translation'});
    examples.add(
      LearningPackExample(
        text: _text(example['text'], 500),
        translation: _optionalText(example['translation'], 500),
      ),
    );
  }
  LearningPackDefinitionQuestion? question;
  if (value['definitionQuestion'] case final rawQuestion?) {
    final object = _object(rawQuestion, const {'correctOptionCode', 'options'});
    question = LearningPackDefinitionQuestion(
      correctOptionCode: _code(object['correctOptionCode']),
      options: [
        for (final rawOption in _list(object['options'], 2, 4))
          _option(rawOption),
      ],
    );
  }
  return LearningPackEntry(
    code: _code(value['code']),
    spelling: _canonicalText(value['spelling'], 120),
    meaning: _canonicalText(value['meaning'], 500),
    partOfSpeech: _canonicalText(value['partOfSpeech'], 60),
    definition: _optionalText(value['definition'], 1000),
    examples: examples,
    imageId: value['imageId'] == null ? null : _code(value['imageId']),
    memoryCue: _optionalText(value['memoryCue'], 500),
    hint: _optionalText(value['hint'], 500),
    strategy: _optionalText(value['strategy'], 1000),
    definitionQuestion: question,
  );
}

LearningPackDefinitionOption _option(Object? raw) {
  final value = _object(raw, const {
    'code',
    'entryCode',
    'contrastiveExplanation',
  });
  return LearningPackDefinitionOption(
    code: _code(value['code']),
    entryCode: _code(value['entryCode']),
    contrastiveExplanation: _optionalText(
      value['contrastiveExplanation'],
      1000,
    ),
  );
}

LearningPackImage _image(Object? raw, {required int maximumPixels}) {
  final value = _object(raw, const {
    'id',
    'mimeType',
    'width',
    'height',
    'altText',
    'sha256',
    'byteCount',
    'dataBase64',
  });
  final width = _integer(value['width'], 1, maxLearningPackImageDimension);
  final height = _integer(value['height'], 1, maxLearningPackImageDimension);
  if (width * height > maxLearningPackImagePixels ||
      width * height > maximumPixels) {
    _packFail(LearningPackFailureCode.tooLarge);
  }
  final byteCount = _integer(value['byteCount'], 1, maxLearningPackImageBytes);
  final hash = _hash(value['sha256']);
  final mime = value['mimeType'];
  if (mime != 'image/png' && mime != 'image/jpeg') {
    _packFail(LearningPackFailureCode.invalidMedia);
  }
  final encoded = value['dataBase64'];
  if (encoded is! String ||
      encoded.length > ((maxLearningPackImageBytes + 2) ~/ 3) * 4) {
    _packFail(LearningPackFailureCode.tooLarge);
  }
  late final Uint8List bytes;
  try {
    bytes = base64.decode(encoded);
    if (base64.encode(bytes) != encoded) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
  } on LearningPackException {
    rethrow;
  } on Object {
    _packFail(LearningPackFailureCode.invalidMedia);
  }
  if (bytes.length != byteCount || _digest(bytes) != hash) {
    _packFail(LearningPackFailureCode.integrityMismatch);
  }
  try {
    if (mime == 'image/png') {
      _verifyPng(bytes, width, height);
    } else {
      _verifyJpeg(bytes, width, height);
    }
    final decoded = mime == 'image/png'
        ? image.PngDecoder().decode(bytes)
        : image.JpegDecoder().decode(bytes);
    if (decoded == null ||
        decoded.width != width ||
        decoded.height != height ||
        decoded.numFrames != 1) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
  } on LearningPackException {
    rethrow;
  } on Object {
    _packFail(LearningPackFailureCode.invalidMedia);
  }
  return LearningPackImage(
    id: _code(value['id']),
    mimeType: mime as String,
    width: width,
    height: height,
    altText: _text(value['altText'], 300),
    bytes: bytes,
  );
}

void _verifyPng(Uint8List bytes, int width, int height) {
  if (bytes.length < 33 ||
      !_sameBytes(bytes.sublist(0, 8), const [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ])) {
    _packFail(LearningPackFailureCode.invalidMedia);
  }
  final data = ByteData.sublistView(bytes);
  var offset = 8;
  var chunks = 0;
  var rawLength = 0;
  var ended = false;
  var dataStarted = false;
  var dataEnded = false;
  final seen = <String>{};
  final compressed = BytesBuilder(copy: false);
  while (offset < bytes.length) {
    if (++chunks > 256 || offset + 12 > bytes.length) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    final length = data.getUint32(offset);
    if (length > bytes.length - offset - 12) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    final kind = ascii.decode(bytes.sublist(offset + 4, offset + 8));
    if (!const {
      'IHDR',
      'PLTE',
      'tRNS',
      'IDAT',
      'IEND',
      'gAMA',
      'cHRM',
      'sRGB',
      'pHYs',
    }.contains(kind)) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    if (chunks == 1 && kind != 'IHDR') {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    if (kind != 'IDAT' && !seen.add(kind)) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    if (kind != 'IDAT' && dataStarted) dataEnded = true;
    if (kind == 'IDAT' && dataEnded) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    if (dataStarted && kind != 'IDAT' && kind != 'IEND') {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    if ((kind == 'gAMA' && length != 4) ||
        (kind == 'cHRM' && length != 32) ||
        (kind == 'sRGB' && length != 1) ||
        (kind == 'pHYs' && length != 9) ||
        (kind == 'PLTE' && (length < 3 || length > 768 || length % 3 != 0)) ||
        (kind == 'tRNS' && length > 256)) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    if (archive.getCrc32(bytes.sublist(offset + 4, offset + 8 + length)) !=
        data.getUint32(offset + 8 + length)) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    if (kind == 'IHDR') {
      if (chunks != 1 ||
          length != 13 ||
          data.getUint32(offset + 8) != width ||
          data.getUint32(offset + 12) != height ||
          bytes[offset + 18] != 0 ||
          bytes[offset + 19] != 0 ||
          bytes[offset + 20] != 0) {
        _packFail(LearningPackFailureCode.invalidMedia);
      }
      final depth = bytes[offset + 16];
      final color = bytes[offset + 17];
      final channels = switch (color) {
        0 => 1,
        2 => 3,
        3 => 1,
        4 => 2,
        6 => 4,
        _ => 0,
      };
      final validDepth = color == 0
          ? const {1, 2, 4, 8, 16}.contains(depth)
          : color == 3
          ? const {1, 2, 4, 8}.contains(depth)
          : const {8, 16}.contains(depth);
      if (channels == 0 || !validDepth) {
        _packFail(LearningPackFailureCode.invalidMedia);
      }
      rawLength = height * (1 + ((width * channels * depth + 7) ~/ 8));
    } else if (kind == 'IDAT') {
      dataStarted = true;
      compressed.add(
        Uint8List.sublistView(bytes, offset + 8, offset + 8 + length),
      );
    } else if (kind == 'IEND') {
      if (length != 0 || offset + 12 != bytes.length) {
        _packFail(LearningPackFailureCode.invalidMedia);
      }
      ended = true;
    }
    offset += length + 12;
  }
  final zlib = compressed.takeBytes();
  if (!ended ||
      zlib.length < 6 ||
      rawLength == 0 ||
      (zlib[0] & 15) != 8 ||
      (zlib[0] >> 4) > 7 ||
      (zlib[1] & 32) != 0 ||
      ((zlib[0] << 8) + zlib[1]) % 31 != 0) {
    _packFail(LearningPackFailureCode.invalidMedia);
  }
  final output = _BoundedPngOutput(rawLength);
  final input = archive.InputMemoryStream(
    Uint8List.sublistView(zlib, 2, zlib.length - 4),
  );
  archive.Inflate.stream(input, output: output);
  if (!input.isEOS ||
      output.length != rawLength ||
      archive.getAdler32(output.getBytes()) !=
          ByteData.sublistView(zlib).getUint32(zlib.length - 4)) {
    _packFail(LearningPackFailureCode.invalidMedia);
  }
}

void _verifyJpeg(Uint8List bytes, int width, int height) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) {
    _packFail(LearningPackFailureCode.invalidMedia);
  }
  var offset = 2;
  var frames = 0;
  var scans = 0;
  var segments = 0;
  var ended = false;
  final data = ByteData.sublistView(bytes);
  while (offset < bytes.length) {
    if (++segments > 256 || bytes[offset] != 0xff) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) _packFail(LearningPackFailureCode.invalidMedia);
    final marker = bytes[offset++];
    if (marker == 0xd9) {
      if (offset != bytes.length) {
        _packFail(LearningPackFailureCode.invalidMedia);
      }
      ended = true;
      break;
    }
    if (offset + 2 > bytes.length ||
        !const {
          0xc0,
          0xc1,
          0xc2,
          0xc4,
          0xdb,
          0xdd,
          0xda,
          0xe0,
          0xee,
        }.contains(marker)) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    final length = data.getUint16(offset);
    if (length < 2 || length > bytes.length - offset) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    if (const {0xc0, 0xc1, 0xc2}.contains(marker)) {
      if (++frames != 1 ||
          length < 11 ||
          bytes[offset + 2] != 8 ||
          data.getUint16(offset + 3) != height ||
          data.getUint16(offset + 5) != width) {
        _packFail(LearningPackFailureCode.invalidMedia);
      }
      final components = bytes[offset + 7];
      if ((components != 1 && components != 3) ||
          length != 8 + 3 * components) {
        _packFail(LearningPackFailureCode.invalidMedia);
      }
      var sampleBlocks = 0;
      for (var component = 0; component < components; component++) {
        final sampling = bytes[offset + 9 + 3 * component];
        final h = sampling >> 4;
        final v = sampling & 15;
        if (h < 1 || h > 4 || v < 1 || v > 4) {
          _packFail(LearningPackFailureCode.invalidMedia);
        }
        sampleBlocks += h * v;
      }
      if (sampleBlocks > 10) _packFail(LearningPackFailureCode.invalidMedia);
    }
    offset += length;
    if (marker == 0xda) {
      if (frames != 1 || ++scans > 16) {
        _packFail(LearningPackFailureCode.invalidMedia);
      }
      while (offset < bytes.length) {
        if (bytes[offset] != 0xff) {
          offset++;
          continue;
        }
        if (offset + 1 >= bytes.length) {
          _packFail(LearningPackFailureCode.invalidMedia);
        }
        final next = bytes[offset + 1];
        if (next == 0 || (next >= 0xd0 && next <= 0xd7)) {
          offset += 2;
          continue;
        }
        break;
      }
    }
  }
  if (!ended || frames != 1 || scans == 0) {
    _packFail(LearningPackFailureCode.invalidMedia);
  }
}

final class _BoundedPngOutput extends archive.OutputMemoryStream {
  _BoundedPngOutput(this.maximum)
    : super(size: maximum < 32768 ? maximum : 32768);
  final int maximum;
  @override
  void writeByte(int value) {
    if (length >= maximum) _packFail(LearningPackFailureCode.invalidMedia);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    if (this.length + (length ?? bytes.length) > maximum) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(archive.InputStream stream) {
    if (length + stream.length > maximum) {
      _packFail(LearningPackFailureCode.invalidMedia);
    }
    super.writeStream(stream);
  }
}

Map<String, Object?> _metadataJson(LearningPackMetadata metadata) => {
  'packId': metadata.packId,
  'version': metadata.version,
  'title': metadata.title,
  'objectives': metadata.objectives,
  'cefrLevel': metadata.cefrLevel,
  'language': metadata.language,
  'meaningLanguage': metadata.meaningLanguage,
  'provenance': metadata.provenance.toJson(),
};

Map<String, Object?> _object(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !value.keys.toSet().containsAll(keys)) {
    _packFail(LearningPackFailureCode.invalidFormat);
  }
  return value;
}

List<Object?> _list(Object? value, int minimum, int maximum) {
  if (value is! List) _packFail(LearningPackFailureCode.invalidFormat);
  if (value.length > maximum) _packFail(LearningPackFailureCode.tooLarge);
  if (value.length < minimum) _packFail(LearningPackFailureCode.invalidFormat);
  return value;
}

String _text(Object? value, int maximum) {
  if (value is! String ||
      value.isEmpty ||
      value.trim() != value ||
      value.runes.length > maximum ||
      value.runes.any(
        (rune) =>
            rune < 32 || rune == 127 || (rune >= 0xd800 && rune <= 0xdfff),
      )) {
    _packFail(LearningPackFailureCode.invalidFormat);
  }
  return value;
}

String _canonicalText(Object? value, int maximum) {
  final text = _text(value, maximum);
  if (text.length > maximum) _packFail(LearningPackFailureCode.invalidFormat);
  if (text.replaceAll(RegExp(r'\s+'), ' ') != text) {
    _packFail(LearningPackFailureCode.invalidFormat);
  }
  return text;
}

String? _optionalText(Object? value, int maximum) =>
    value == null ? null : _text(value, maximum);
String _code(Object? value, {int max = 80}) {
  final text = _text(value, max);
  if (!RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(text) ||
      text.contains('..')) {
    _packFail(LearningPackFailureCode.invalidFormat);
  }
  return text;
}

String _language(Object? value) {
  final text = _text(value, 12);
  if (!RegExp(r'^[a-z]{2,3}(?:-[A-Z]{2})?$').hasMatch(text)) {
    _packFail(LearningPackFailureCode.invalidFormat);
  }
  return text;
}

String _hash(Object? value) {
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    _packFail(LearningPackFailureCode.invalidFormat);
  }
  return value;
}

int _integer(Object? value, int min, int max) {
  if (value is! int || value < min) {
    _packFail(LearningPackFailureCode.invalidFormat);
  }
  if (value > max) _packFail(LearningPackFailureCode.tooLarge);
  return value;
}

Uri _sourceUri(Object? value) {
  final text = _text(value, 2048);
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443) {
    _packFail(LearningPackFailureCode.unsafeUri);
  }
  final host = uri.host.toLowerCase();
  final labels = host.split('.');
  if (labels.length < 2 ||
      !RegExp(r'^[a-z]{2,63}$').hasMatch(labels.last) ||
      labels.any(
        (label) =>
            !RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(label),
      ) ||
      const {
        'localhost',
        'local',
        'internal',
        'lan',
        'home',
      }.contains(labels.last)) {
    _packFail(LearningPackFailureCode.unsafeUri);
  }
  return uri;
}

String _normalize(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
String _digest(List<int> bytes) => crypto.sha256.convert(bytes).toString();
String _canonicalJson(Object? value) => jsonEncode(_sortedJson(value));
Object? _sortedJson(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _sortedJson(value[key])};
  }
  if (value is List) return [for (final item in value) _sortedJson(item)];
  return value;
}

void _checkJsonKeysAndDepth(String value) {
  final containers = <_JsonObjectKeys?>[];
  var quoteStart = -1;
  var escaped = false;
  for (var index = 0; index < value.length; index++) {
    final rune = value.codeUnitAt(index);
    if (quoteStart >= 0) {
      if (escaped) {
        escaped = false;
      } else if (rune == 92) {
        escaped = true;
      } else if (rune == 34) {
        final object = containers.isEmpty ? null : containers.last;
        if (object != null && object.expectingKey) {
          final key =
              jsonDecode(value.substring(quoteStart, index + 1)) as String;
          if (!object.keys.add(key)) {
            _packFail(LearningPackFailureCode.invalidFormat);
          }
          object.expectingKey = false;
        }
        quoteStart = -1;
      }
    } else if (rune == 34) {
      quoteStart = index;
    } else if (rune == 91 || rune == 123) {
      if (containers.length == 16) {
        _packFail(LearningPackFailureCode.tooLarge);
      }
      containers.add(rune == 123 ? _JsonObjectKeys() : null);
    } else if (rune == 93 || rune == 125) {
      if (containers.isEmpty || (rune == 125) != (containers.last != null)) {
        _packFail(LearningPackFailureCode.invalidFormat);
      }
      containers.removeLast();
    } else if (rune == 44 && containers.isNotEmpty) {
      containers.last?.expectingKey = true;
    }
  }
  if (quoteStart >= 0 || containers.isNotEmpty) {
    _packFail(LearningPackFailureCode.invalidFormat);
  }
}

final class _JsonObjectKeys {
  final keys = <String>{};
  bool expectingKey = true;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

Never _packFail(LearningPackFailureCode code) =>
    throw LearningPackException(code);
