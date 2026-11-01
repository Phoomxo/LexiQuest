import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart' as archive;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';

void main() {
  test(
    'a one-byte lexical payload change is rejected by its declared checksum',
    () {
      final original = _package();
      final changed = Uint8List.fromList(
        utf8.encode(
          utf8
              .decode(original)
              .replaceFirst('"spelling":"cat"', '"spelling":"bat"'),
        ),
      );
      expect(changed, hasLength(original.length));
      expect(
        () => const LearningPackCodec().decode(changed),
        throwsA(
          isA<LearningPackException>().having(
            (error) => error.code,
            'code',
            LearningPackFailureCode.integrityMismatch,
          ),
        ),
      );
    },
  );

  test(
    'valid authored content round trips with detached bytes and unreviewed provenance',
    () {
      final bytes = _quizPackage();
      final pack = const LearningPackCodec().decode(
        bytes,
        expectedPackageSha256: sha256.convert(bytes).toString(),
      );
      expect(pack.manifest.packId, 'synthetic-animals');
      expect(pack.manifest.version, '1.0.0');
      expect(pack.manifest.entryCount, 2);
      expect(pack.manifest.quality, LearningPackQuality.userProvidedUnreviewed);
      expect(pack.manifest.provenance.author, 'Synthetic test author');
      expect(
        pack.entriesByCode['cat']!.definition,
        'A small animal often kept as a pet.',
      );
      expect(pack.entriesByCode['cat']!.meaning, 'แมว');
      final question = pack.entriesByCode['cat']!.definitionQuestion!;
      expect(question.correctOptionCode, 'cat-option');
      expect(
        question.options.last.contrastiveExplanation,
        'The authored dog option names a different animal.',
      );
      expect(pack.entriesByCode['dog']!.definitionQuestion, isNull);
      final encoded = const LearningPackCodec().encode(
        metadata: pack.manifest,
        entries: pack.entries,
        images: pack.images,
      );
      final restored = const LearningPackCodec().decode(encoded);
      expect(restored.manifest.toJson(), pack.manifest.toJson());
      expect(
        restored.entries.map((entry) => entry.canonicalJson),
        pack.entries.map((entry) => entry.canonicalJson),
      );
      expect(
        restored.entries.first.contentSha256,
        sha256
            .convert(utf8.encode(restored.entries.first.canonicalJson))
            .toString(),
      );
      expect(
        const LearningPackCodec().encode(
          metadata: restored.manifest,
          entries: restored.entries,
        ),
        encoded,
      );
      final copy = pack.bytes..[0] = 0;
      expect(copy, isNot(pack.bytes));
      bytes[0] = 0;
      expect(pack.bytes.first, 123);
      expect(pack.packageSha256, sha256.convert(pack.bytes).toString());
      expect(() => pack.entries.clear(), throwsUnsupportedError);
      expect(() => pack.entriesByCode.clear(), throwsUnsupportedError);
      expect(() => pack.manifest.objectives.clear(), throwsUnsupportedError);
      expect(() => question.options.clear(), throwsUnsupportedError);
    },
  );

  test(
    'pretty JSON and reordered keys retain payload integrity and exact source bytes',
    () {
      final raw = jsonDecode(utf8.decode(_package())) as Map<String, dynamic>;
      final pretty = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(raw)),
      );
      final pack = const LearningPackCodec().decode(pretty);
      expect(pack.bytes, pretty);
      expect(pack.packageSha256, sha256.convert(pretty).toString());
      final payload = raw['payload'] as Map<String, dynamic>;
      raw['payload'] = {
        'images': payload['images'],
        'entries': payload['entries'],
      };
      expect(
        const LearningPackCodec()
            .decode(Uint8List.fromList(utf8.encode(jsonEncode(raw))))
            .entries
            .single
            .spelling,
        'cat',
      );
    },
  );

  test(
    'equivalent escaped strings retain payload integrity and exact source bytes',
    () {
      final original = _quizPackage();
      final expected = const LearningPackCodec().decode(original);
      final source = utf8.decode(original);
      final variants = [
        source.replaceFirst('"spelling":"cat"', r'"spelling":"\u0063at"'),
        source.replaceFirst('"schemaVersion":', r'"\u0073chemaVersion":'),
        source.replaceFirst('"spelling":', r'"\u0073pelling":'),
        source.codeUnits
            .map(
              (code) => code > 127
                  ? r'\u' + code.toRadixString(16).padLeft(4, '0')
                  : String.fromCharCode(code),
            )
            .join(),
      ];
      for (final variant in variants) {
        final bytes = Uint8List.fromList(utf8.encode(variant));
        expect(bytes, isNot(original));
        final pack = const LearningPackCodec().decode(
          bytes,
          expectedPackageSha256: sha256.convert(bytes).toString(),
        );
        expect(pack.manifest.payloadSha256, expected.manifest.payloadSha256);
        expect(
          pack.entries.first.canonicalJson,
          expected.entries.first.canonicalJson,
        );
        expect(pack.entries.first.meaning, 'แมว');
        expect(pack.bytes, bytes);
        expect(pack.packageSha256, isNot(expected.packageSha256));
      }
    },
  );

  test(
    'escaped duplicate object keys are rejected at envelope and entry depth',
    () {
      final source = utf8.decode(_quizPackage());
      for (final variant in [
        source.replaceFirst(
          '"schemaVersion":1',
          r'"schemaVersion":1,"\u0073chemaVersion":1',
        ),
        source.replaceFirst(
          '"spelling":"cat"',
          r'"spelling":"cat","\u0073pelling":"cat"',
        ),
      ]) {
        _reject(
          Uint8List.fromList(utf8.encode(variant)),
          LearningPackFailureCode.invalidFormat,
        );
      }
    },
  );

  test(
    'the caller supplied package digest pins metadata as well as payload',
    () {
      final original = _package();
      final changed = _mutate(
        (raw) => (raw['manifest'] as Map)['title'] = 'Different authored title',
      );
      _reject(
        changed,
        LearningPackFailureCode.integrityMismatch,
        expected: sha256.convert(original).toString(),
      );
      expect(
        const LearningPackCodec().decode(changed).manifest.title,
        'Different authored title',
      );
      _reject(
        original,
        LearningPackFailureCode.invalidFormat,
        expected: 'A' * 64,
      );
    },
  );

  for (final mutation in <String, void Function(Map<String, dynamic>)>{
    'envelope': (raw) => raw['secret'] = 'synthetic-only',
    'manifest': (raw) => (raw['manifest'] as Map)['reviewStatus'] = 'approved',
    'provenance': (raw) =>
        ((raw['manifest'] as Map)['provenance'] as Map)['issuerSignature'] =
            'not-trusted',
    'payload': (raw) => (raw['payload'] as Map)['script'] = 'not-executable',
    'entry': (raw) =>
        _entries(raw).first['imageUrl'] = 'https://example.invalid/tracker',
    'missing nullable key': (raw) => _entries(raw).first.remove('hint'),
  }.entries) {
    test('closed package format rejects ${mutation.key}', () {
      _reject(_mutate(mutation.value), LearningPackFailureCode.invalidFormat);
    });
  }

  for (final version in <Object?>[0, 2, 1.0, '1', null]) {
    test(
      'unsupported schema version $version cannot create a verified pack',
      () {
        _reject(
          _mutate((raw) => raw['schemaVersion'] = version),
          LearningPackFailureCode.unsupportedVersion,
        );
      },
    );
  }

  test('count, byte count and payload digest are independently checked', () {
    for (final field in ['entryCount', 'payloadBytes', 'payloadSha256']) {
      _reject(
        _mutate((raw) {
          final manifest = raw['manifest'] as Map;
          manifest[field] = field == 'payloadSha256'
              ? 'f' * 64
              : (manifest[field] as int) + 1;
        }, rehash: false),
        LearningPackFailureCode.integrityMismatch,
      );
    }
  });

  test(
    'duplicate codes and canonical spelling collisions fail before import',
    () {
      for (final duplicateCode in [false, true]) {
        _reject(
          _mutate((raw) {
            _entries(raw).add({
              ..._entries(raw).first,
              'code': duplicateCode ? 'cat' : 'other-cat',
              'spelling': duplicateCode ? 'kitten' : 'CAT',
            });
            (raw['manifest'] as Map)['entryCount'] = 2;
          }),
          LearningPackFailureCode.duplicateIdentity,
        );
      }
    },
  );

  test('entry and objective limits are enforced before materialization', () {
    _reject(
      _mutate((raw) {
        (raw['payload'] as Map)['entries'] = <Object?>[];
        (raw['manifest'] as Map)['entryCount'] = 0;
      }),
      LearningPackFailureCode.invalidFormat,
    );
    _reject(
      _mutate((raw) {
        final base = _entries(raw).first;
        (raw['payload'] as Map)['entries'] = [
          for (var i = 0; i < 51; i++)
            {...base, 'code': 'entry-$i', 'spelling': 'sample$i'},
        ];
        (raw['manifest'] as Map)['entryCount'] = 51;
      }),
      LearningPackFailureCode.tooLarge,
    );
    _reject(
      _mutate(
        (raw) => (raw['manifest'] as Map)['objectives'] = List.filled(
          11,
          'Synthetic',
        ),
      ),
      LearningPackFailureCode.tooLarge,
    );
    _reject(
      _mutate(
        (raw) =>
            (raw['manifest'] as Map)['objectives'] = ['Synthetic', 'Synthetic'],
      ),
      LearningPackFailureCode.duplicateIdentity,
    );
    _reject(
      _mutate((raw) => _entries(raw).first['definition'] = 'a' * 1001),
      LearningPackFailureCode.invalidFormat,
    );
  });

  for (final spelling in [
    ' cat',
    'cat ',
    'two  words',
    'cat\nword',
    'cat\u0000',
  ]) {
    test('canonical vocabulary spelling rejects ${jsonEncode(spelling)}', () {
      _reject(
        _mutate((raw) => _entries(raw).first['spelling'] = spelling),
        LearningPackFailureCode.invalidFormat,
      );
    });
  }

  test('unsupported languages, CEFR and path-like identities are rejected', () {
    for (final change in <(String, Object?)>[
      ('language', 'english'),
      ('meaningLanguage', 'th_th'),
      ('cefrLevel', 'A9'),
      ('packId', '../synthetic'),
      ('version', '1/2'),
      ('packId', 'synthetic..pack'),
    ]) {
      _reject(
        _mutate((raw) => (raw['manifest'] as Map)[change.$1] = change.$2),
        LearningPackFailureCode.invalidFormat,
      );
    }
  });

  test('pack vocabulary bounds match canonical import UTF16 limits', () {
    for (final change in <(String, int)>[
      ('spelling', 61),
      ('meaning', 251),
      ('partOfSpeech', 31),
    ]) {
      _reject(
        _mutate((raw) => _entries(raw).first[change.$1] = '😀' * change.$2),
        LearningPackFailureCode.invalidFormat,
      );
    }
  });

  for (final uri in [
    'http://example.com/source',
    'javascript:alert(1)',
    'file:///secret',
    'https://user:secret@example.com/source',
    'https://127.0.0.1/source',
    'https://[::1]/source',
    'https://localhost/source',
    'https://host.internal/source',
    'https://example.com:8443/source',
  ]) {
    test('source URI cannot introduce unsafe authority $uri', () {
      _reject(
        _mutate(
          (raw) =>
              ((raw['manifest'] as Map)['provenance'] as Map)['sourceUri'] =
                  uri,
        ),
        LearningPackFailureCode.unsafeUri,
      );
    });
  }

  for (final mode in [
    'unknown entry',
    'wrong correct',
    'unknown correct',
    'duplicate option',
    'duplicate entry',
    'correct explanation',
    'no definition',
    'wrong language',
  ]) {
    test('definition question rejects $mode', () {
      final raw =
          jsonDecode(utf8.decode(_quizPackage())) as Map<String, dynamic>;
      final cat = _entries(raw).first;
      final question = cat['definitionQuestion'] as Map;
      final options = question['options'] as List;
      switch (mode) {
        case 'unknown entry':
          (options.last as Map)['entryCode'] = 'missing';
        case 'wrong correct':
          question['correctOptionCode'] = 'dog-option';
        case 'unknown correct':
          question['correctOptionCode'] = 'missing';
        case 'duplicate option':
          (options.last as Map)['code'] = 'cat-option';
        case 'duplicate entry':
          (options.last as Map)['entryCode'] = 'cat';
        case 'correct explanation':
          (options.first as Map)['contrastiveExplanation'] = 'Synthetic';
        case 'no definition':
          cat['definition'] = null;
        case 'wrong language':
          (raw['manifest'] as Map)['language'] = 'th';
      }
      _reject(
        _encodeRaw(raw),
        const {'duplicate option', 'duplicate entry'}.contains(mode)
            ? LearningPackFailureCode.duplicateIdentity
            : LearningPackFailureCode.invalidReference,
      );
    });
  }

  test('missing authored explanation remains absent rather than invented', () {
    final raw = jsonDecode(utf8.decode(_quizPackage())) as Map<String, dynamic>;
    final options =
        (_entries(raw).first['definitionQuestion'] as Map)['options'] as List;
    (options.last as Map)['contrastiveExplanation'] = null;
    final pack = const LearningPackCodec().decode(_encodeRaw(raw));
    expect(
      pack
          .entries
          .first
          .definitionQuestion!
          .options
          .last
          .contrastiveExplanation,
      isNull,
    );
  });

  test('declared regional English definitions retain their language pin', () {
    final raw = jsonDecode(utf8.decode(_quizPackage())) as Map<String, dynamic>;
    (raw['manifest'] as Map)['language'] = 'en-US';
    final pack = const LearningPackCodec().decode(_encodeRaw(raw));
    expect(pack.manifest.language, 'en-US');
    expect(pack.entries.first.definitionQuestion, isNotNull);
  });

  test(
    'invalid JSON, repeated keys, UTF-8 and excessive nesting return typed failure',
    () {
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList([0xff]),
        Uint8List.fromList(utf8.encode('{')),
      ]) {
        _reject(bytes, LearningPackFailureCode.invalidFormat);
      }
      final duplicate = utf8
          .decode(_package())
          .replaceFirst(
            '"schemaVersion":1',
            '"schemaVersion":1,"schemaVersion":1',
          );
      _reject(
        Uint8List.fromList(utf8.encode(duplicate)),
        LearningPackFailureCode.invalidFormat,
      );
      _reject(
        Uint8List.fromList(
          utf8.encode(
            '${List.filled(17, '[').join()}0${List.filled(17, ']').join()}',
          ),
        ),
        LearningPackFailureCode.tooLarge,
      );
      _reject(
        Uint8List(maxLearningPackBytes + 1),
        LearningPackFailureCode.tooLarge,
      );
    },
  );

  for (final mime in ['image/png', 'image/jpeg']) {
    test(
      'verified embedded $mime preserves its bounded pixels and detached bytes',
      () {
        final source = image.Image(width: 2, height: 1)
          ..setPixelRgb(0, 0, 20, 50, 80);
        final bytes = Uint8List.fromList(
          mime == 'image/png'
              ? image.encodePng(source)
              : image.encodeJpg(source),
        );
        final encoded = _withImages([_asset(bytes, mime: mime, width: 2)]);
        final pack = const LearningPackCodec().decode(encoded);
        final asset = pack.images.single;
        expect(asset.mimeType, mime);
        expect((asset.width, asset.height), (2, 1));
        expect(asset.altText, 'Synthetic animal illustration');
        expect(asset.sha256, sha256.convert(bytes).toString());
        asset.bytes[0] = 0;
        expect(asset.bytes, bytes);
        expect(pack.imagesById[pack.entries.single.imageId], same(asset));
        expect(
          const LearningPackCodec()
              .decode(
                const LearningPackCodec().encode(
                  metadata: pack.manifest,
                  entries: pack.entries,
                  images: pack.images,
                ),
              )
              .images
              .single
              .bytes,
          bytes,
        );
      },
    );
  }

  test(
    'embedded media requires exact bytes, MIME, alt text and every reference',
    () {
      final png = Uint8List.fromList(
        image.encodePng(image.Image(width: 1, height: 1)),
      );
      for (final mode in [
        'digest',
        'length',
        'mime',
        'alt',
        'missing reference',
        'orphan',
        'extra field',
        'duplicate',
      ]) {
        final asset = _asset(png);
        final raw =
            jsonDecode(utf8.decode(_withImages([asset])))
                as Map<String, dynamic>;
        final media = ((raw['payload'] as Map)['images'] as List).first as Map;
        switch (mode) {
          case 'digest':
            media['sha256'] = '0' * 64;
          case 'length':
            media['byteCount'] = png.length + 1;
          case 'mime':
            media['mimeType'] = 'image/svg+xml';
          case 'alt':
            media['altText'] = '';
          case 'missing reference':
            _entries(raw).first['imageId'] = 'missing';
          case 'orphan':
            _entries(raw).first['imageId'] = null;
          case 'extra field':
            media['url'] = 'https://example.invalid/tracker';
          case 'duplicate':
            ((raw['payload'] as Map)['images'] as List).add({...media});
        }
        final code = switch (mode) {
          'digest' || 'length' => LearningPackFailureCode.integrityMismatch,
          'mime' => LearningPackFailureCode.invalidMedia,
          'missing reference' ||
          'orphan' => LearningPackFailureCode.invalidReference,
          'duplicate' => LearningPackFailureCode.duplicateIdentity,
          _ => LearningPackFailureCode.invalidFormat,
        };
        _reject(_encodeRaw(raw), code);
      }
    },
  );

  test(
    'image byte, pixel and declared geometry bounds precede native decoding',
    () {
      _reject(
        _withImages([_asset(Uint8List(maxLearningPackImageBytes + 1))]),
        LearningPackFailureCode.tooLarge,
      );
      final png = Uint8List.fromList(
        image.encodePng(image.Image(width: 1, height: 1)),
      );
      _reject(
        _withImages([_asset(png, width: maxLearningPackImageDimension + 1)]),
        LearningPackFailureCode.tooLarge,
      );
      _reject(
        _withImages([_asset(png, width: 2048, height: 2048)]),
        LearningPackFailureCode.tooLarge,
      );
      _reject(
        _withImages([_asset(png, width: 2)]),
        LearningPackFailureCode.invalidMedia,
      );
      _reject(
        _withImages([_asset(png, mime: 'image/jpeg')]),
        LearningPackFailureCode.invalidMedia,
      );
      final hugeHeader = Uint8List.fromList(png);
      ByteData.sublistView(hugeHeader).setUint32(16, 0x7fffffff);
      ByteData.sublistView(
        hugeHeader,
      ).setUint32(29, archive.getCrc32(hugeHeader.sublist(12, 29)));
      _reject(
        _withImages([_asset(hugeHeader)]),
        LearningPackFailureCode.invalidMedia,
      );
    },
  );

  test('PNG compressed output cannot exceed the declared scanline size', () {
    final header = ByteData(13)
      ..setUint32(0, 1)
      ..setUint32(4, 1)
      ..setUint8(8, 8)
      ..setUint8(9, 6);
    final bomb = _png([
      _chunk('IHDR', header.buffer.asUint8List()),
      _chunk(
        'IDAT',
        Uint8List.fromList(
          const archive.ZLibEncoder().encode(Uint8List(100000)),
        ),
      ),
      _chunk('IEND', Uint8List(0)),
    ]);
    _reject(_withImages([_asset(bomb)]), LearningPackFailureCode.invalidMedia);
  });

  test(
    'PNG metadata, animation, interlace, invalid CRC and trailing bytes are rejected',
    () {
      final png = Uint8List.fromList(
        image.encodePng(image.Image(width: 1, height: 1)),
      );
      for (final kind in ['iCCP', 'tEXt', 'acTL']) {
        final changed = Uint8List.fromList([
          ...png.sublist(0, 33),
          ..._chunk(kind, Uint8List.fromList([0, 0])),
          ...png.sublist(33),
        ]);
        _reject(
          _withImages([_asset(changed)]),
          LearningPackFailureCode.invalidMedia,
        );
      }
      final interlaced = Uint8List.fromList(png)..[28] = 1;
      ByteData.sublistView(
        interlaced,
      ).setUint32(29, archive.getCrc32(interlaced.sublist(12, 29)));
      _reject(
        _withImages([_asset(interlaced)]),
        LearningPackFailureCode.invalidMedia,
      );
      final corrupt = Uint8List.fromList(png)..[29] ^= 1;
      _reject(
        _withImages([_asset(corrupt)]),
        LearningPackFailureCode.invalidMedia,
      );
      _reject(
        _withImages([
          _asset(Uint8List.fromList([...png, 0])),
        ]),
        LearningPackFailureCode.invalidMedia,
      );
    },
  );

  test(
    'JPEG unsafe metadata and oversized frame headers are rejected before decode',
    () {
      final jpeg = Uint8List.fromList(
        image.encodeJpg(image.Image(width: 1, height: 1)),
      );
      final metadata = Uint8List.fromList([
        ...jpeg.sublist(0, 2),
        0xff,
        0xe1,
        0,
        8,
        69,
        120,
        105,
        102,
        0,
        0,
        ...jpeg.sublist(2),
      ]);
      _reject(
        _withImages([_asset(metadata, mime: 'image/jpeg')]),
        LearningPackFailureCode.invalidMedia,
      );
      final oversized = Uint8List.fromList(jpeg);
      for (var index = 0; index < oversized.length - 8; index++) {
        if (oversized[index] == 0xff && oversized[index + 1] == 0xc0) {
          ByteData.sublistView(oversized).setUint16(index + 7, 65535);
          break;
        }
      }
      _reject(
        _withImages([_asset(oversized, mime: 'image/jpeg')]),
        LearningPackFailureCode.invalidMedia,
      );
    },
  );

  test(
    'aggregate decoded pixels are bounded even for small compressed packages',
    () {
      final png = Uint8List.fromList(
        image.encodePng(image.Image(width: 1024, height: 1024)),
      );
      _reject(
        _withImages([
          for (var index = 0; index < 5; index++)
            _asset(png, id: 'image-$index', width: 1024, height: 1024),
        ]),
        LearningPackFailureCode.tooLarge,
      );
    },
  );
}

void _reject(
  Uint8List bytes,
  LearningPackFailureCode code, {
  String? expected,
}) {
  expect(
    () => const LearningPackCodec().decode(
      bytes,
      expectedPackageSha256: expected,
    ),
    throwsA(
      isA<LearningPackException>().having((error) => error.code, 'code', code),
    ),
  );
}

Uint8List _mutate(
  void Function(Map<String, dynamic>) change, {
  bool rehash = true,
}) {
  final raw = jsonDecode(utf8.decode(_package())) as Map<String, dynamic>;
  change(raw);
  return _encodeRaw(raw, rehash: rehash);
}

List<dynamic> _entries(Map<String, dynamic> raw) =>
    (raw['payload'] as Map)['entries'] as List<dynamic>;
Uint8List _encodeRaw(Map<String, dynamic> raw, {bool rehash = true}) {
  if (rehash) {
    final bytes = utf8.encode(jsonEncode(_sort(raw['payload'])));
    (raw['manifest'] as Map)['payloadSha256'] = sha256
        .convert(bytes)
        .toString();
    (raw['manifest'] as Map)['payloadBytes'] = bytes.length;
  }
  return Uint8List.fromList(utf8.encode(jsonEncode(raw)));
}

Object? _sort(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _sort(value[key])};
  }
  if (value is List) return [for (final item in value) _sort(item)];
  return value;
}

Uint8List _quizPackage() => _mutate((raw) {
  final cat = _entries(raw).first as Map<String, dynamic>;
  _entries(raw).add({
    ...cat,
    'code': 'dog',
    'spelling': 'dog',
    'meaning': 'สุนัข',
    'definition': 'Another small animal often kept as a pet.',
  });
  cat['examples'] = [
    {'text': 'The cat is here.', 'translation': 'แมวอยู่ที่นี่'},
  ];
  cat['hint'] = 'Use the authored definition.';
  cat['strategy'] = 'Compare the words against the definition.';
  cat['memoryCue'] = 'Synthetic memory cue';
  cat['definitionQuestion'] = {
    'correctOptionCode': 'cat-option',
    'options': [
      {
        'code': 'cat-option',
        'entryCode': 'cat',
        'contrastiveExplanation': null,
      },
      {
        'code': 'dog-option',
        'entryCode': 'dog',
        'contrastiveExplanation':
            'The authored dog option names a different animal.',
      },
    ],
  };
  (raw['manifest'] as Map)['entryCount'] = 2;
});
Map<String, Object?> _asset(
  Uint8List bytes, {
  String id = 'cat-image',
  String mime = 'image/png',
  int width = 1,
  int height = 1,
}) => {
  'id': id,
  'mimeType': mime,
  'width': width,
  'height': height,
  'altText': 'Synthetic animal illustration',
  'byteCount': bytes.length,
  'sha256': sha256.convert(bytes).toString(),
  'dataBase64': base64.encode(bytes),
};
Uint8List _withImages(List<Map<String, Object?>> images) => _mutate((raw) {
  final base = _entries(raw).first;
  (raw['payload'] as Map)['entries'] = [
    for (var index = 0; index < images.length; index++)
      {
        ...base,
        'code': 'entry-$index',
        'spelling': 'sample$index',
        'imageId': images[index]['id'],
      },
  ];
  (raw['manifest'] as Map)['entryCount'] = images.length;
  (raw['payload'] as Map)['images'] = images;
});
Uint8List _chunk(String kind, Uint8List bytes) {
  final result = Uint8List(bytes.length + 12);
  final view = ByteData.sublistView(result)..setUint32(0, bytes.length);
  result.setRange(4, 8, ascii.encode(kind));
  result.setRange(8, 8 + bytes.length, bytes);
  view.setUint32(
    bytes.length + 8,
    archive.getCrc32(result.sublist(4, bytes.length + 8)),
  );
  return result;
}

Uint8List _png(List<Uint8List> chunks) => Uint8List.fromList([
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  for (final chunk in chunks) ...chunk,
]);

Uint8List _package() {
  final payload = <String, Object?>{
    'entries': [
      {
        'code': 'cat',
        'definition': 'A small animal often kept as a pet.',
        'definitionQuestion': null,
        'examples': <Object?>[],
        'hint': null,
        'imageId': null,
        'meaning': 'แมว',
        'memoryCue': null,
        'partOfSpeech': 'noun',
        'spelling': 'cat',
        'strategy': null,
      },
    ],
    'images': <Object?>[],
  };
  final payloadBytes = utf8.encode(jsonEncode(payload));
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'schema': 'lexiquest.learning-pack.v1',
        'schemaVersion': 1,
        'manifest': {
          'packId': 'synthetic-animals',
          'version': '1.0.0',
          'title': 'Synthetic animals',
          'objectives': ['Read explicitly synthetic lexical examples.'],
          'cefrLevel': 'A1',
          'language': 'en',
          'meaningLanguage': 'th',
          'provenance': {
            'author': 'Synthetic test author',
            'source': 'Synthetic fixtures only',
            'sourceUri': 'https://example.invalid/synthetic-animals',
            'license': 'Author-declared synthetic test use only',
            'attribution': 'Not an approved curriculum or licensed dictionary.',
          },
          'entryCount': 1,
          'payloadSha256': sha256.convert(payloadBytes).toString(),
          'payloadBytes': payloadBytes.length,
        },
        'payload': payload,
      }),
    ),
  );
}
