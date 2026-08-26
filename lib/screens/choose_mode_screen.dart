import 'package:flutter/material.dart';

import '../features/learning/application/flashcard_mode_adapter.dart';
import '../features/learning/application/cloze_mode_adapter.dart';
import '../features/learning/application/definition_quiz_mode_adapter.dart';
import '../features/learning/application/lesson_mode_registry.dart';
import '../features/learning/application/meaning_quiz_mode_adapter.dart';
import '../features/learning/application/matching_mode_adapter.dart';
import '../features/learning/application/typed_recall_mode_adapter.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import 'associative_reading_launcher_screen.dart';
import 'definition_quiz_screen.dart';
import 'fill_in_the_blanks_screen.dart';
import 'quiz_screen.dart';
import 'matching_mode_screen.dart';
import 'srs_flashcards_screen.dart';

class ChooseModeScreen extends StatelessWidget {
  const ChooseModeScreen({super.key, this.featureRegistry, this.lessonModes});

  final FeatureRegistry? featureRegistry;
  final LessonModeRegistry? lessonModes;

  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final features = featureRegistry ?? dependencies?.features;
    final modes = lessonModes ?? dependencies?.lessonModes;
    final matching = modes?.resolve(LessonMode.matching);
    final typedRecall = modes?.resolveTypedRecall();
    return Scaffold(
      appBar: AppBar(title: const Text('เลือกกิจกรรมการเรียน')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (features?.isVisible(Feature.reading) == true)
            _LearningTile(
              key: const ValueKey<String>('home/learn/associative-reading'),
              icon: Icons.auto_stories_outlined,
              title: 'Associative Reading',
              subtitle:
                  'Build durable memory cues from words in your vocabulary.',
              onTap: () => _openMode(
                context,
                LessonMode.associativeReading,
                (_, _) => const AssociativeReadingLauncherScreen(),
              ),
            ),
          if (features?.isVisible(Feature.quiz) == true)
            _LearningTile(
              key: const ValueKey<String>('home/learn/quiz'),
              icon: Icons.quiz_outlined,
              title: 'Quiz จากคลังคำศัพท์',
              subtitle: 'คำตอบ คะแนน และกำหนดทบทวนจะบันทึกในเครื่อง',
              onTap: () => _openMode(
                context,
                LessonMode.meaningQuiz,
                (_, adapter) =>
                    QuizScreen(modeAdapter: adapter as MeaningQuizModeAdapter),
              ),
            ),
          if (features?.isVisible(Feature.quiz) == true && typedRecall != null)
            _LearningTile(
              key: const ValueKey<String>('home/learn/quiz/typed-recall'),
              icon: Icons.keyboard_outlined,
              title: 'Typed Recall',
              subtitle: 'Recall and type the vocabulary spelling from memory.',
              onTap: () => _openMode(
                context,
                LessonMode.typedRecall,
                (_, adapter) => QuizScreen.typedRecall(
                  modeAdapter: adapter as TypedRecallModeAdapter,
                ),
              ),
            ),
          if (features?.isVisible(Feature.quiz) == true && matching != null)
            _LearningTile(
              key: const ValueKey<String>('home/learn/quiz/matching'),
              icon: Icons.compare_arrows_outlined,
              title: 'Matching',
              subtitle: 'Match each vocabulary word with its meaning.',
              onTap: () => _openMode(
                context,
                LessonMode.matching,
                (_, adapter) => MatchingModeScreen(
                  modeAdapter: adapter as MatchingModeAdapter,
                ),
              ),
            ),
          if (features?.isVisible(Feature.quiz) == true)
            _LearningTile(
              key: const ValueKey<String>('home/learn/quiz/cloze'),
              icon: Icons.space_bar_outlined,
              title: 'Cloze Test',
              subtitle: 'Choose or type a word in a reviewed sentence.',
              onTap: () => _openMode(
                context,
                LessonMode.cloze,
                (_, adapter) => FillInTheBlanksScreen(
                  modeAdapter: adapter as ClozeModeAdapter,
                ),
              ),
            ),
          if (features?.isVisible(Feature.quiz) == true)
            _LearningTile(
              key: const ValueKey<String>('home/learn/quiz/definition'),
              icon: Icons.menu_book_outlined,
              title: 'Definition Quiz',
              subtitle: 'Choose a word from a reviewed English definition.',
              onTap: () => _openMode(
                context,
                LessonMode.definitionQuiz,
                (_, adapter) => DefinitionQuizScreen(
                  modeAdapter: adapter as DefinitionQuizModeAdapter,
                ),
              ),
            ),
          if (features?.isVisible(Feature.srs) == true)
            _LearningTile(
              key: const ValueKey<String>('home/learn/srs'),
              icon: Icons.event_repeat_outlined,
              title: 'ทบทวนคำศัพท์ที่ถึงกำหนด',
              subtitle: 'แสดงเฉพาะคำที่คำนวณจากประวัติคำตอบจริง',
              onTap: () => _openMode(
                context,
                LessonMode.flashcard,
                (_, adapter) => SrsFlashcardsScreen(
                  modeAdapter: adapter as FlashcardModeAdapter,
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Text(
              'เกม Sentence Scramble จะเปิดในรุ่นถัดไป',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMode(
    BuildContext context,
    LessonMode mode,
    Widget Function(BuildContext context, LessonModeAdapter adapter) builder,
  ) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final modes = lessonModes ?? dependencies?.lessonModes;
    final registration = modes?.resolve(mode);
    if (registration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This lesson mode is unavailable.')),
      );
      return Future<void>.value();
    }
    if (mode == LessonMode.flashcard &&
        registration.adapter is! FlashcardModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This flashcard mode is unavailable.')),
      );
      return Future<void>.value();
    }
    final typedRecall = modes?.resolveTypedRecall();
    if (mode == LessonMode.associativeReading && typedRecall == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This typed recall mode is unavailable.')),
      );
      return Future<void>.value();
    }
    if (mode == LessonMode.meaningQuiz &&
        registration.adapter is! MeaningQuizModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This meaning quiz is unavailable.')),
      );
      return Future<void>.value();
    }
    if (mode == LessonMode.typedRecall &&
        registration.adapter is! TypedRecallModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This typed recall mode is unavailable.')),
      );
      return Future<void>.value();
    }
    if (mode == LessonMode.definitionQuiz &&
        registration.adapter is! DefinitionQuizModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This definition quiz is unavailable.')),
      );
      return Future<void>.value();
    }
    if (mode == LessonMode.cloze && registration.adapter is! ClozeModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This cloze mode is unavailable.')),
      );
      return Future<void>.value();
    }
    if (mode == LessonMode.matching &&
        registration.adapter is! MatchingModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This matching mode is unavailable.')),
      );
      return Future<void>.value();
    }
    final features = featureRegistry ?? dependencies?.features;
    return AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: registration.routeName,
        builder: (_) {
          final createController = dependencies?.createLessonController;
          if (createController == null) {
            return ProductionFeatureGate(
              feature: registration.feature,
              registry: features,
              builder: (_) => ProductionFeatureUnavailable(
                feature: registration.feature,
                reason: ProductionFeatureUnavailableReason.missingDependency,
              ),
            );
          }
          if (mode == LessonMode.associativeReading) {
            // The launcher can create multiple durable sessions. Each
            // pushed session owns a fresh shell/controller instance.
            return ProductionFeatureGate(
              feature: registration.feature,
              registry: features,
              builder: (_) => builder(context, registration.adapter),
            );
          }
          return UnifiedLessonModeHost(
            adapter: registration.adapter,
            createController: createController,
            feature: registration.feature,
            featureRegistry: features,
            learning: dependencies?.learning,
            builder: (context) => builder(context, registration.adapter),
          );
        },
      ),
    );
  }
}

class _LearningTile extends StatelessWidget {
  const _LearningTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        minVerticalPadding: 16,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
