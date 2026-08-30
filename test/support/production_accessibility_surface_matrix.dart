import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/presentation/handwriting_scratchpad.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/screens/cefr_article_reader_screen.dart';
import 'package:vocab_learning_app/screens/definition_quiz_screen.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/matching_mode_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/screens/speak_to_text_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';

/// Exact production widget types exercised by the f38 runtime release gate.
///
/// This is test evidence only. It owns no delivery, session, or accessibility
/// policy decision; the runtime smoke gate must still mount every listed type.
const productionAccessibilitySurfaceTypes = <LessonMode, Type>{
  LessonMode.associativeReading: AssociativeReadingSessionScreen,
  LessonMode.meaningQuiz: QuizScreen,
  LessonMode.typedRecall: QuizScreen,
  LessonMode.definitionQuiz: DefinitionQuizScreen,
  LessonMode.cloze: FillInTheBlanksScreen,
  LessonMode.matching: MatchingModeScreen,
  LessonMode.flashcard: SrsFlashcardsScreen,
  LessonMode.handwritingScratchpad: HandwritingScratchpad,
  LessonMode.dictation: DictationQuizScreen,
  LessonMode.speaking: SpeakToTextScreen,
  LessonMode.shadowing: ShadowingChallengeScreen,
  LessonMode.cefrReading: CefrArticleReaderScreen,
  LessonMode.sentenceScramble: SentenceScrambleScreen,
  LessonMode.wordScramble: WordScrambleScreen,
};
