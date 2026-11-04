import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../features/learning/domain/learning_models.dart';
import '../features/learning_packs/domain/learning_pack_repository.dart';

final class ReadingMaterial {
  ReadingMaterial(List<({QuizWord word, CurrentLexicalContent? lexical})> items)
    : items = List.unmodifiable(items);

  final List<({QuizWord word, CurrentLexicalContent? lexical})> items;

  String? _example(QuizWord word, CurrentLexicalContent? lexical) {
    if (lexical == null) return null;
    final target = RegExp(
      '(^|[^A-Za-z0-9])${RegExp.escape(word.spelling)}(?=\$|[^A-Za-z0-9])',
      caseSensitive: false,
    );
    for (final example in lexical.entry.examples) {
      if (target.hasMatch(example.text)) return example.text;
    }
    return null;
  }

  String get contentId =>
      'offline-reading:${sha256.convert(utf8.encode(jsonEncode([
        for (final item in items) [item.word.id, item.word.contentRevision, item.word.spelling, item.word.meaning, item.lexical?.pack.packageSha256, item.lexical?.binding.snapshotId, item.lexical?.binding.wordRevision, item.lexical?.entry.contentSha256, _example(item.word, item.lexical)],
      ])))}';

  String get passageText => [
    for (final item in items)
      _example(item.word, item.lexical) ?? item.word.spelling,
  ].join('\n\n');

  String get supportedText => [
    for (final item in items)
      if (_example(item.word, item.lexical) case final example?)
        '$example\n${item.word.spelling}: ${item.word.meaning}'
      else
        '${item.word.spelling}: ${item.word.meaning}\nไม่มีประโยคตัวอย่าง',
  ].join('\n\n');
}
