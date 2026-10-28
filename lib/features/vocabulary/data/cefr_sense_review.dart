import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Editorial selection only; original dictionary indices remain immutable.
final class CefrSenseReview {
  static List<CefrSenseReviewEntry> fromBytes(
    List<int> bytes, {
    required String expectedSha256,
  }) {
    if (sha256.convert(bytes).toString() != expectedSha256) {
      throw const FormatException('Sense review checksum mismatch');
    }
    final root = jsonDecode(utf8.decode(bytes));
    if (root is! Map<String, dynamic> ||
        root['schemaVersion'] != 1 ||
        root['entries'] is! List) {
      throw const FormatException('Unsupported sense review');
    }
    final result = <CefrSenseReviewEntry>[];
    final ids = <String>{};
    const keys = {
      'id',
      'acceptedSourceMeaningIndices',
      'excludedSourceMeanings',
      'status',
      'reviewNote',
    };
    for (final row in root['entries']) {
      if (row is! Map<String, dynamic> ||
          row.length != keys.length ||
          !row.keys.toSet().containsAll(keys) ||
          row['status'] != 'ai-reviewed' ||
          row['acceptedSourceMeaningIndices'] is! List ||
          row['excludedSourceMeanings'] is! List) {
        throw const FormatException('Invalid sense review fields');
      }
      final id = _text(row['id'], 160);
      if (!ids.add(id)) throw const FormatException('Duplicate sense review');
      final indices = <int>{};
      final accepted = <int>[];
      for (final index in row['acceptedSourceMeaningIndices']) {
        if (index is! int || index < 0 || !indices.add(index)) {
          throw const FormatException('Invalid accepted index');
        }
        accepted.add(index);
      }
      final excluded = <int, String>{};
      for (final item in row['excludedSourceMeanings']) {
        if (item is! Map<String, dynamic> ||
            item.length != 2 ||
            !item.containsKey('reason')) {
          throw const FormatException('Invalid excluded sense');
        }
        final index = item['index'];
        if (index is! int || index < 0 || !indices.add(index)) {
          throw const FormatException('Invalid excluded index');
        }
        excluded[index] = _text(item['reason'], 500);
      }
      result.add(
        CefrSenseReviewEntry._(
          id,
          List.unmodifiable(accepted),
          Map.unmodifiable(excluded),
          _text(row['reviewNote'], 500),
        ),
      );
    }
    return List.unmodifiable(result);
  }

  static String _text(dynamic value, int limit) {
    if (value is! String ||
        value.trim().isEmpty ||
        value != value.trim() ||
        value.length > limit ||
        RegExp(r'[\x00-\x1f\x7f\ufffd]').hasMatch(value)) {
      throw const FormatException('Invalid sense review text');
    }
    return value;
  }
}

final class CefrSenseReviewEntry {
  const CefrSenseReviewEntry._(
    this.id,
    this.acceptedSourceMeaningIndices,
    this.excludedSourceMeanings,
    this.reviewNote,
  );
  final String id, reviewNote;
  final List<int> acceptedSourceMeaningIndices;
  final Map<int, String> excludedSourceMeanings;
}
