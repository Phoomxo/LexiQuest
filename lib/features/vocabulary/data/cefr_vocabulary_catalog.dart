import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'cefr_editorial_catalog.dart';
import 'cefr_editorial_manifest.dart';
import 'cefr_sense_review.dart';

final class CefrVocabularyCatalog {
  CefrVocabularyCatalog._(this.words, {this.editorialLoadFailed = false});
  static const asset = 'assets/content/cefr_starter/catalog.json';
  static const edition = 'cefr-starter-3000-r1';
  static const checksum =
      'b1af6f5c444650d39d6873bf7db7632585b2220b69bce323327693c021641140';
  static const notice =
      'ระดับอ้างอิงจาก CEFR-J / Octanove เป็นข้อมูลระดับคำ ไม่ใช่การรับรองทุกความหมายหรือระดับของผู้เรียน';
  static const expansionChecksums = {
    'assets/content/cefr_expanded/core-extension.json':
        'da83baf5ecfb8b64a486da6e784c7ca3d5ae373e18e7fccc02d09179cf7bf6bf',
    'assets/content/cefr_expanded/advanced-profile.json':
        '694a96a5cd413aa41c8547691d54eabed8f8746ca08dcf970e3dd288fc7ebe05',
    'assets/content/cefr_expanded/advanced-translations.json':
        '3e25d52af96d5524ca786c07cc840772ee6862cb381e7b2cda96c16a1d116130',
  };
  final List<CefrCatalogWord> words;
  final bool editorialLoadFailed;
  int get editorialCount =>
      words.where((word) => word.editorial != null).length;

  CefrVocabularyCatalog withSenseReviews(List<CefrSenseReviewEntry> entries) {
    final originals = {for (final word in words) word.id: word};
    final selected = <String, CefrSenseReviewEntry>{};
    for (final entry in entries) {
      final word = originals[entry.id];
      final indices = {
        ...entry.acceptedSourceMeaningIndices,
        ...entry.excludedSourceMeanings.keys,
      };
      if (word == null ||
          selected.containsKey(entry.id) ||
          indices.length != word.meanings.length ||
          indices.any((index) => index < 0 || index >= word.meanings.length)) {
        throw const FormatException('Sense review coverage mismatch');
      }
      selected[entry.id] = entry;
    }
    return CefrVocabularyCatalog._(
      List.unmodifiable([
        for (final word in words) word._withSenseReview(selected[word.id]),
      ]),
    );
  }

  CefrVocabularyCatalog withEditorial(List<CefrEditorialEntry> entries) {
    final originals = {for (final word in words) word.id: word};
    final selected = <String, CefrEditorialEntry>{};
    for (final entry in entries) {
      final word = originals[entry.id];
      final index = entry.sourceMeaningIndex;
      if (word == null ||
          selected.containsKey(entry.id) ||
          (index != null && (index < 0 || index >= word.meanings.length))) {
        throw const FormatException('Editorial word or source sense mismatch');
      }
      final target = RegExp(
        '(?<![A-Za-z])${RegExp.escape(word.word)}(?![A-Za-z])',
        caseSensitive: false,
      );
      if (!target.hasMatch(entry.example) ||
          !RegExp(r'[\u0e00-\u0e7f]').hasMatch(entry.meaning) ||
          !RegExp(r'[\u0e00-\u0e7f]').hasMatch(entry.translation)) {
        throw const FormatException('Editorial example or Thai text mismatch');
      }
      selected[entry.id] = entry;
    }
    return CefrVocabularyCatalog._(
      List.unmodifiable([
        for (final word in words) word._withEditorial(selected[word.id]),
      ]),
    );
  }

  static Future<CefrVocabularyCatalog> load({
    AssetBundle? bundle,
    Future<List<CefrEditorialEntry>> Function()? editorialLoader,
  }) async {
    final assets = <String, Uint8List>{};
    for (final path in [asset, ...expansionChecksums.keys]) {
      final bytes = await (bundle ?? rootBundle).load(path);
      assets[path] = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
    }
    final base = fromAssets(assets);
    Future<List<CefrEditorialEntry>> loadPackagedEditorial() async {
      final entries = <CefrEditorialEntry>[];
      for (final pin in cefrEditorialChecksums.entries) {
        final data = await (bundle ?? rootBundle).load(pin.key);
        entries.addAll(
          CefrEditorialCatalog.fromBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            expectedSha256: pin.value,
          ),
        );
      }
      if (entries.length != cefrEditorialExpectedCount) {
        throw const FormatException('Incomplete editorial coverage');
      }
      return entries;
    }

    try {
      final curated = base.withEditorial(
        await (editorialLoader ?? loadPackagedEditorial)(),
      );
      if (cefrSenseReviewChecksums.isEmpty) return curated;
      final reviews = <CefrSenseReviewEntry>[];
      for (final pin in cefrSenseReviewChecksums.entries) {
        final data = await (bundle ?? rootBundle).load(pin.key);
        reviews.addAll(
          CefrSenseReview.fromBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            expectedSha256: pin.value,
          ),
        );
      }
      if (reviews.length != base.words.length) {
        throw const FormatException('Incomplete packaged sense review');
      }
      return curated.withSenseReviews(reviews);
    } catch (_) {
      // Optional presentation content must not make ordinary learning unusable.
      // Return no curated entries, never a partially validated overlay.
      return CefrVocabularyCatalog._(base.words, editorialLoadFailed: true);
    }
  }

  static CefrVocabularyCatalog fromAssets(Map<String, Uint8List> assets) {
    final legacy = assets[asset];
    if (legacy == null) throw const FormatException('Missing base catalog');
    final words = [...fromBytes(legacy).words];
    final expanded = <String, List<dynamic>>{};
    for (final entry in expansionChecksums.entries) {
      final bytes = assets[entry.key];
      if (bytes == null || sha256.convert(bytes).toString() != entry.value) {
        throw const FormatException('CEFR extension integrity mismatch');
      }
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (root['schemaVersion'] != 1) {
        throw const FormatException('Unsupported extension');
      }
      expanded[entry.key.split('/').last] = root['entries'] as List;
    }
    for (final row in expanded['core-extension.json']!) {
      words.add(
        CefrCatalogWord._(
          row['id'],
          row['word'],
          row['partOfSpeech'],
          row['cefrLevel'],
          List<String>.unmodifiable(row['meanings']),
          row['cefrjRow'],
          List<String>.unmodifiable(row['lexitronIds']),
          importNamespace: 'cefr-expanded-r1',
        ),
      );
    }
    final translations = {
      for (final row in expanded['advanced-translations.json']!) row['id']: row,
    };
    for (final row in expanded['advanced-profile.json']!) {
      final translation = translations[row['id']];
      if (translation == null ||
          translation['word'] != row['word'] ||
          translation['partOfSpeech'] != row['partOfSpeech']) {
        throw const FormatException('Advanced dictionary join mismatch');
      }
      words.add(
        CefrCatalogWord._(
          row['id'],
          row['word'],
          row['partOfSpeech'],
          row['cefrLevel'],
          List<String>.unmodifiable(translation['meanings']),
          row['sourceRow'],
          List<String>.unmodifiable(translation['lexitronIds']),
          importNamespace: 'cefr-expanded-r1',
          levelSource: 'Octanove 1.0',
        ),
      );
    }
    if (words.length != 5500 ||
        words.where((w) => w.cefrLevel == 'C2').length != 500 ||
        words.map((w) => w.id).toSet().length != 5500 ||
        words.map((w) => w.word.toLowerCase()).toSet().length != 5500) {
      throw const FormatException('Invalid expanded inventory');
    }
    return CefrVocabularyCatalog._(List.unmodifiable(words));
  }

  static CefrVocabularyCatalog fromBytes(Uint8List bytes) {
    if (sha256.convert(bytes).toString() != checksum) {
      throw const FormatException('CEFR catalog integrity mismatch');
    }
    final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (root['schemaVersion'] != 1 ||
        root['edition'] != edition ||
        root['count'] != 3000) {
      throw const FormatException('Unsupported CEFR catalog');
    }
    final words = (root['entries'] as List)
        .map((value) {
          final row = value as Map<String, dynamic>;
          return CefrCatalogWord._(
            row['id'] as String,
            row['word'] as String,
            row['partOfSpeech'] as String,
            row['cefrLevel'] as String,
            List<String>.unmodifiable(row['meanings'] as List),
            row['cefrjRow'] as int,
            List<String>.unmodifiable(row['lexitronIds'] as List),
          );
        })
        .toList(growable: false);
    if (words.length != 3000 ||
        words.map((word) => word.id).toSet().length != 3000) {
      throw const FormatException('Invalid CEFR inventory');
    }
    return CefrVocabularyCatalog._(List.unmodifiable(words));
  }

  List<CefrCatalogWord> search({String query = '', String? level}) {
    final term = query.trim().toLowerCase();
    return words
        .where(
          (word) =>
              (level == null
                  ? word.cefrLevel != 'C2'
                  : level == word.cefrLevel) &&
              (term.isEmpty ||
                  word.word.toLowerCase().contains(term) ||
                  (word.editorial?.meaning.toLowerCase().contains(term) ??
                      false) ||
                  word.selectableMeaningIndices.any(
                    (index) =>
                        word.meanings[index].toLowerCase().contains(term),
                  )),
        )
        .toList(growable: false);
  }
}

final class CefrCatalogWord {
  const CefrCatalogWord._(
    this.id,
    this.word,
    this.partOfSpeech,
    this.cefrLevel,
    this.meanings,
    this.cefrjRow,
    this.lexitronIds, {
    this.importNamespace = CefrVocabularyCatalog.edition,
    this.levelSource = 'CEFR-J 1.5',
    this.editorial,
    this.senseReview,
  });
  final String id, word, partOfSpeech, cefrLevel;
  final String importNamespace, levelSource;
  final List<String> meanings, lexitronIds;
  final int cefrjRow;
  final CefrEditorialEntry? editorial;
  final CefrSenseReviewEntry? senseReview;
  // Retain the source inventory for understanding unfamiliar text, but do not
  // seed productive drills with this severe racial slur.
  String? get practiceUsageNotice => id == 'cefrj15:gook'
      ? 'คำเหยียดเชื้อชาติรุนแรง · แสดงเพื่อให้รู้ความหมายเมื่อพบในข้อความ ไม่ควรใช้เรียกคน และไม่เปิดให้เพิ่มจากคลังนี้ไปฝึกใช้'
      : null;
  List<int> get selectableMeaningIndices =>
      senseReview?.acceptedSourceMeaningIndices ??
      List<int>.generate(meanings.length, (index) => index, growable: false);
  CefrCatalogWord _withSenseReview(CefrSenseReviewEntry? value) =>
      CefrCatalogWord._(
        id,
        word,
        partOfSpeech,
        cefrLevel,
        meanings,
        cefrjRow,
        lexitronIds,
        importNamespace: importNamespace,
        levelSource: levelSource,
        editorial: editorial,
        senseReview: value,
      );
  CefrCatalogWord _withEditorial(CefrEditorialEntry? value) =>
      CefrCatalogWord._(
        id,
        word,
        partOfSpeech,
        cefrLevel,
        meanings,
        cefrjRow,
        lexitronIds,
        importNamespace: importNamespace,
        levelSource: levelSource,
        editorial: value,
        senseReview: senseReview,
      );
  String get partOfSpeechThai =>
      _thaiPartOfSpeech(editorial?.partOfSpeechOverride ?? partOfSpeech);
  String get sourcePartOfSpeechThai => _thaiPartOfSpeech(partOfSpeech);
  static String _thaiPartOfSpeech(String value) => switch (value) {
    'noun' => 'คำนาม',
    'verb' => 'คำกริยา',
    'adjective' => 'คำคุณศัพท์',
    'adverb' => 'คำกริยาวิเศษณ์',
    'pronoun' => 'คำสรรพนาม',
    'preposition' => 'คำบุพบท',
    'determiner' => 'คำกำกับนาม',
    'conjunction' => 'คำสันธาน',
    'number' => 'คำบอกจำนวน',
    'interjection' => 'คำอุทาน',
    'modal auxiliary' => 'กริยาช่วย',
    'be-verb' || 'do-verb' || 'have-verb' => 'คำกริยา / กริยาช่วย',
    _ => value,
  };
}
