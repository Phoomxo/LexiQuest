import 'package:flutter/material.dart';

import '../features/learning/application/lesson_mode_registry.dart';
import '../features/learning/application/unified_lesson_controller.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import 'associative_reading_launcher_screen.dart';
import 'quiz_screen.dart';
import 'srs_flashcards_screen.dart';

class ChooseModeScreen extends StatelessWidget {
  const ChooseModeScreen({super.key, this.featureRegistry, this.lessonModes});

  final FeatureRegistry? featureRegistry;
  final LessonModeRegistry? lessonModes;

  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final features = featureRegistry ?? dependencies?.features;
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
                (_) => const AssociativeReadingLauncherScreen(),
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
                (_) => const QuizScreen(),
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
                (_) => const SrsFlashcardsScreen(),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Text(
              'เกม Sentence Scramble และ Fill in the Blank จะเปิดในรุ่นถัดไป',
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
    WidgetBuilder builder,
  ) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final modes = lessonModes ?? dependencies?.lessonModes;
    final registration = modes?.find(mode);
    if (registration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This lesson mode is unavailable.')),
      );
      return Future<void>.value();
    }
    final features = featureRegistry ?? dependencies?.features;
    return AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: registration.routeName,
        builder: (_) => ProductionFeatureGate(
          feature: registration.feature,
          registry: features,
          builder: (_) {
            final createController = dependencies?.createLessonController;
            if (createController == null) {
              return ProductionFeatureUnavailable(
                feature: registration.feature,
                reason: ProductionFeatureUnavailableReason.missingDependency,
              );
            }
            return _ControllerBackedLessonMode(
              adapter: registration.adapter,
              createController: createController,
              builder: builder,
            );
          },
        ),
      ),
    );
  }
}

class _ControllerBackedLessonMode extends StatefulWidget {
  const _ControllerBackedLessonMode({
    required this.adapter,
    required this.createController,
    required this.builder,
  });

  final LessonModeAdapter adapter;
  final UnifiedLessonControllerFactory createController;
  final WidgetBuilder builder;

  @override
  State<_ControllerBackedLessonMode> createState() =>
      _ControllerBackedLessonModeState();
}

class _ControllerBackedLessonModeState
    extends State<_ControllerBackedLessonMode> {
  late final UnifiedLessonController _controller = widget.createController(
    widget.adapter,
  );

  @override
  Widget build(BuildContext context) =>
      UnifiedLessonShell(controller: _controller, builder: widget.builder);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
