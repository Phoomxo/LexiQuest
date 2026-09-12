import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Presentation-only editorial content; this does not certify learning evidence.
final class CefrEditorialCatalog {
  static List<CefrEditorialEntry> fromBytes(
    List<int> bytes, {
    required String expectedSha256,
  }) {
    if (sha256.convert(bytes).toString() != expectedSha256) {
      throw const FormatException('Editorial checksum mismatch');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != 1 ||
        decoded['entries'] is! List) {
      throw const FormatException('Unsupported editorial catalog');
    }
    final entries = <CefrEditorialEntry>[];
    final ids = <String>{};
    const keys = {
      'id',
      'senseKey',
      'sourceMeaningIndex',
      'meaning',
      'example',
      'translation',
      'reviewNote',
      'status',
    };
    for (final value in decoded['entries'] as List) {
      if (value is! Map<String, dynamic> ||
          value.keys.toSet().difference({
            ...keys,
            'partOfSpeechOverride',
          }).isNotEmpty ||
          keys.difference(value.keys.toSet()).isNotEmpty) {
        throw const FormatException('Invalid editorial entry fields');
      }
      final id = _text(value['id'], 160);
      final senseKey = _text(value['senseKey'], 32);
      final index = value['sourceMeaningIndex'];
      final pos = value['partOfSpeechOverride'];
      const allowedPos = {
        'noun',
        'verb',
        'adjective',
        'adverb',
        'pronoun',
        'preposition',
        'determiner',
        'conjunction',
        'number',
        'interjection',
        'modal auxiliary',
        'be-verb',
        'do-verb',
        'have-verb',
      };
      if (!ids.add(id) ||
          senseKey != 'primary-v1' ||
          (index != null && (index is! int || index < 0)) ||
          value['status'] != 'ai-reviewed' ||
          (pos != null && (!allowedPos.contains(pos) || index != null))) {
        throw const FormatException(
          'Invalid editorial identity or review state',
        );
      }
      entries.add(
        CefrEditorialEntry._(
          id: id,
          senseKey: senseKey,
          sourceMeaningIndex: index as int?,
          meaning: _text(value['meaning'], 500),
          example: _text(value['example'], 400),
          translation: _text(value['translation'], 500),
          reviewNote: _text(value['reviewNote'], 500),
          status: value['status'],
          partOfSpeechOverride: pos as String?,
        ),
      );
    }
    return List.unmodifiable(entries);
  }

  static String _text(dynamic value, int limit) {
    if (value is! String ||
        value.trim().isEmpty ||
        value != value.trim() ||
        value.length > limit ||
        RegExp(r'[\x00-\x1f\x7f\ufffd]').hasMatch(value)) {
      throw const FormatException('Invalid editorial text');
    }
    return value;
  }
}

final class CefrEditorialEntry {
  const CefrEditorialEntry._({
    required this.id,
    required this.senseKey,
    required this.sourceMeaningIndex,
    required this.meaning,
    required this.example,
    required this.translation,
    required this.reviewNote,
    required this.status,
    this.partOfSpeechOverride,
  });
  final String id, senseKey, meaning, example, translation, reviewNote, status;
  final int? sourceMeaningIndex;
  final String? partOfSpeechOverride;
}
