import 'dart:collection';

import '../../learning/domain/lesson_mode.dart';
import 'learning_pack.dart';

/// Immutable content references for one verified, pinned learning-pack
/// revision. The references remain canonical vocabulary IDs; lexical display
/// data stays with the Vocabulary authority.
final class LearningPackDetail {
  LearningPackDetail({
    required this.summary,
    required Iterable<String> vocabularyWordIds,
  }) : vocabularyWordIds = UnmodifiableListView(
         List<String>.of(vocabularyWordIds, growable: false),
       );

  final LearningPackSummary summary;
  final List<String> vocabularyWordIds;
}

enum LearningPackActivityAvailability { available, unavailable }

extension LearningPackActivityAvailabilityLabel
    on LearningPackActivityAvailability {
  String get label => switch (this) {
    LearningPackActivityAvailability.available => 'Available',
    LearningPackActivityAvailability.unavailable => 'Unavailable',
  };
}

/// Presentation-ready availability for an existing typed lesson mode. This
/// is read-only metadata and never starts a lesson or writes progress.
final class LearningPackActivity {
  const LearningPackActivity({required this.mode, required this.availability});

  final LessonMode mode;
  final LearningPackActivityAvailability availability;

  String get label => switch (mode) {
    LessonMode.associativeReading => 'Associative reading',
    LessonMode.meaningQuiz => 'Meaning quiz',
    LessonMode.typedRecall => 'Typed recall',
    LessonMode.definitionQuiz => 'Definition quiz',
    LessonMode.cloze => 'Cloze test',
    LessonMode.matching => 'Matching',
    LessonMode.flashcard => 'Flashcards',
    LessonMode.handwritingScratchpad => 'Handwriting scratchpad',
    LessonMode.dictation => 'Dictation',
    LessonMode.speaking => 'Speaking',
    LessonMode.shadowing => 'Shadowing',
    LessonMode.cefrReading => 'CEFR reading',
    LessonMode.sentenceScramble => 'Sentence scramble',
    LessonMode.wordScramble => 'Word scramble',
  };
}
