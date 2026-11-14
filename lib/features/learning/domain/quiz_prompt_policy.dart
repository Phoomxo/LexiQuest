import 'learning_models.dart';

abstract final class QuizPromptPolicy {
  static const definitionSpellings = ['platform', 'ticket'];
  static const definitionMeanings = ['ชานชาลา', 'ตั๋ว'];

  static List<QuizQuestion> build({
    required List<QuizWord> words,
    required QuizPromptKind kind,
    required int limit,
    List<QuizWord> optionWords = const [],
    Set<String>? targetWordIds,
  }) {
    if (limit < 0) throw ArgumentError.value(limit, 'limit');
    if (limit == 0 || words.isEmpty) return const [];
    if (kind == QuizPromptKind.meaningChoice) {
      final meanings = [
        ...words,
        ...optionWords,
      ].map((word) => word.meaning).toSet().toList()..sort();
      return List.unmodifiable(
        words.take(limit).map((word) {
          final options = [
            word.meaning,
            ...meanings.where((value) => value != word.meaning).take(3),
          ];
          return QuizQuestion(
            word: word,
            options: List.unmodifiable(_rotate(options, word.id)),
          );
        }),
      );
    }
    if (kind == QuizPromptKind.definitionChoice) {
      return List.unmodifiable(
        _definition(words)
            .where(
              (question) =>
                  targetWordIds == null ||
                  targetWordIds.contains(question.word.id),
            )
            .take(limit),
      );
    }
    final idCounts = <String, int>{};
    final spellingCounts = <String, int>{};
    final meaningCounts = <String, int>{};
    for (final word in words) {
      idCounts.update(word.id, (count) => count + 1, ifAbsent: () => 1);
      spellingCounts.update(
        _key(word.spelling),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      meaningCounts.update(
        _key(word.meaning),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final safe = words.where((word) {
      if (word.id.trim().isEmpty ||
          _key(word.spelling).isEmpty ||
          _key(word.meaning).isEmpty) {
        return false;
      }
      return idCounts[word.id] == 1 &&
          spellingCounts[_key(word.spelling)] == 1 &&
          meaningCounts[_key(word.meaning)] == 1;
    }).toList();
    final choices = [...safe]..sort((a, b) => a.spelling.compareTo(b.spelling));
    return List.unmodifiable(
      safe
          .where(
            (word) => targetWordIds == null || targetWordIds.contains(word.id),
          )
          .take(limit)
          .map((word) {
            final selected = [
              word,
              ...choices.where((other) => other.id != word.id).take(3),
            ];
            final options = _rotate(
              selected.map((entry) => entry.spelling).toList(),
              word.id,
            );
            return QuizQuestion.spellingChoice(
              word: word,
              options: options,
              optionWords: {
                for (final entry in selected) entry.spelling: entry,
              },
            );
          }),
    );
  }

  static List<QuizQuestion> _definition(List<QuizWord> words) {
    final results = <QuizQuestion>[];
    final categories = words.map((word) => word.categoryId).toSet();
    for (final category in categories) {
      final candidates = words
          .where(
            (word) =>
                word.categoryId == category &&
                (_key(word.spelling) == 'platform' ||
                    _key(word.spelling) == 'ticket'),
          )
          .toList();
      if (candidates.length != 2) continue;
      final platforms = candidates
          .where(
            (word) =>
                _key(word.spelling) == 'platform' &&
                word.meaning.trim() == 'ชานชาลา' &&
                _key(word.partOfSpeech) == 'noun',
          )
          .toList();
      final tickets = candidates
          .where(
            (word) =>
                _key(word.spelling) == 'ticket' &&
                word.meaning.trim() == 'ตั๋ว' &&
                _key(word.partOfSpeech) == 'noun',
          )
          .toList();
      if (platforms.length != 1 ||
          tickets.length != 1 ||
          platforms.single.id == tickets.single.id ||
          platforms.single.id.trim().isEmpty ||
          tickets.single.id.trim().isEmpty) {
        continue;
      }
      final platform = platforms.single;
      final ticket = tickets.single;
      if (words
              .where(
                (word) =>
                    word.categoryId == category &&
                    (_key(word.meaning) == _key(platform.meaning) ||
                        _key(word.meaning) == _key(ticket.meaning)),
              )
              .length !=
          2) {
        continue;
      }
      results.add(
        QuizQuestion.definitionChoice(
          word: platform,
          options: [platform.spelling, ticket.spelling],
          definition:
              'The place at a train station where you wait to get on a train.',
          optionWords: {platform.spelling: platform, ticket.spelling: ticket},
          optionExplanations: {
            platform.spelling: 'บริเวณที่ผู้โดยสารยืนรอขึ้นรถไฟ',
            ticket.spelling: 'หลักฐานที่ใช้โดยสาร',
          },
          sourcePin:
              '21b34eaa:docs/design/2026-11-13-design-reset/exam_routes.py:131-138',
        ),
      );
    }
    return results;
  }

  static String _key(String value) => value.trim().toLowerCase();

  static List<String> _rotate(List<String> options, String id) {
    final offset =
        id.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % options.length;
    return [...options.skip(offset), ...options.take(offset)];
  }
}
