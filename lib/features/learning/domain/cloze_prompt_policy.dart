import 'learning_evidence_contract.dart';
import 'learning_models.dart';

abstract final class ClozePromptPolicy {
  static const spellings = ['platform', 'ticket'];
  static const meanings = ['ชานชาลา', 'ตั๋ว'];

  static const _sourcePin =
      '21b34eaa:docs/design/2026-11-13-design-reset/learn_frames.py:157-171';

  // The authored alternatives complete this exact sentence grammatically.
  static const _typedAlternative = 'platform number';

  static bool supportsTarget(QuizWord word) =>
      _matches(word, 'platform', 'ชานชาลา') &&
      _key(word.partOfSpeech) == 'noun';

  static String? distractorMeaning(String? option) =>
      option != null && _key(option) == spellings[1] ? meanings[1] : null;

  static List<QuizQuestion> build({
    required List<QuizWord> words,
    required QuizPromptKind kind,
    Set<String>? targetWordIds,
  }) {
    if (kind != QuizPromptKind.clozeChoice &&
        kind != QuizPromptKind.clozeTyped) {
      return const [];
    }

    final seenIds = <String>{};
    final repeatedIds = <String>{};
    final byCategory = <String, List<QuizWord>>{};
    for (final word in words) {
      if (!seenIds.add(word.id)) repeatedIds.add(word.id);
      if (spellings.contains(_key(word.spelling)) ||
          meanings.contains(_key(word.meaning))) {
        byCategory.putIfAbsent(word.categoryId, () => []).add(word);
      }
    }

    final questions = <QuizQuestion>[];
    for (final entry in byCategory.entries) {
      final candidates = entry.value;
      if (candidates.length != 2 ||
          !LearningEvidenceContract.validIdentifier(entry.key) ||
          candidates.any(
            (word) =>
                repeatedIds.contains(word.id) ||
                !LearningEvidenceContract.validIdentifier(word.id) ||
                _key(word.partOfSpeech) != 'noun',
          )) {
        continue;
      }

      final platform = candidates.where(supportsTarget).firstOrNull;
      final ticket = candidates
          .where((word) => _matches(word, 'ticket', 'ตั๋ว'))
          .firstOrNull;
      if (platform == null ||
          ticket == null ||
          (targetWordIds != null && !targetWordIds.contains(platform.id))) {
        continue;
      }

      questions.add(
        QuizQuestion.cloze(
          word: platform,
          kind: kind,
          prompt: 'The train is at ____ two.',
          options: kind == QuizPromptKind.clozeChoice
              ? [platform.spelling, ticket.spelling]
              : const [],
          translation: 'รถไฟจอดอยู่ที่ชานชาลาสอง',
          acceptedAnswers: [
            platform.spelling,
            if (kind == QuizPromptKind.clozeTyped) _typedAlternative,
          ],
          sourcePin: _sourcePin,
        ),
      );
    }
    return List.unmodifiable(questions);
  }

  static bool _matches(QuizWord word, String spelling, String meaning) =>
      _key(word.spelling) == spelling && _key(word.meaning) == meaning;

  static String _key(String value) => value.trim().toLowerCase();
}
