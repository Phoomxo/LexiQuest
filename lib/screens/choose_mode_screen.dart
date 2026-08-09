import 'package:flutter/material.dart';

import '../runtime/app_dependencies.dart';
import '../runtime/registries/feature_registry.dart';
import 'associative_reading_launcher_screen.dart';
import 'cefr_diagnostic_test_screen.dart';
import 'game_launcher_screen.dart';
import 'learning_world_map_screen.dart';
import 'mastery_dashboard_screen.dart';
import 'phonetic_explorer_screen.dart';
import 'quiz_screen.dart';
import 'select_category_for_quiz.dart';
import 'shadowing_challenge_screen.dart';
import '../navigation/app_routes.dart';
import 'srs_flashcards_screen.dart';
import 'weakness_clinic_screen.dart';

class ChooseModeScreen extends StatelessWidget {
  const ChooseModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final features =
        AppDependenciesScope.maybeOf(context)?.features ??
        const BuildFeatureRegistry.fieldDefaults();
    return Scaffold(
      appBar: AppBar(title: const Text('เลือกกิจกรรมการเรียน')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (features.isVisible(Feature.reading))
            _LearningTile(
              icon: Icons.auto_stories_outlined,
              title: 'Associative Reading',
              subtitle:
                  'Build durable memory cues from words in your vocabulary.',
              onTap: () =>
                  _push(context, const AssociativeReadingLauncherScreen()),
            ),
          _LearningTile(
            icon: Icons.quiz_outlined,
            title: 'Quiz จากคลังคำศัพท์',
            subtitle: 'คำตอบ คะแนน และกำหนดทบทวนจะบันทึกในเครื่อง',
            onTap: () => _push(context, const QuizScreen()),
          ),
          _LearningTile(
            icon: Icons.category_outlined,
            title: 'Quiz ตามหมวดหมู่',
            subtitle: 'เลือกจากหมวดหมู่ที่บันทึกในเครื่อง',
            onTap: () => _openCategoryQuiz(context),
          ),
          _LearningTile(
            icon: Icons.event_repeat_outlined,
            title: 'ทบทวนคำศัพท์ที่ถึงกำหนด',
            subtitle: 'แสดงเฉพาะคำที่คำนวณจากประวัติคำตอบจริง',
            onTap: () => _push(context, const SrsFlashcardsScreen()),
          ),
          _LearningTile(
            icon: Icons.analytics_outlined,
            title: 'ภาพรวมการเรียน',
            subtitle: 'สถิติพร้อมจำนวนตัวอย่างจากข้อมูลจริง',
            onTap: () => _push(context, const MasteryDashboardScreen()),
          ),
          _LearningTile(
            icon: Icons.healing_outlined,
            title: 'ฝึกจุดอ่อน',
            subtitle: 'คัดคำจากคำตอบผิดและสถานะ SRS จริง',
            onTap: () => _push(context, const WeaknessClinicScreen()),
          ),
          _LearningTile(
            icon: Icons.record_voice_over_outlined,
            title: 'Shadowing Challenge',
            subtitle: 'ฝึกพูดตามแบบอย่าง',
            onTap: () => _push(context, const ShadowingChallengeScreen()),
          ),
          _LearningTile(
            icon: Icons.shuffle_on_outlined,
            title: 'Word Scramble',
            subtitle: 'เรียงตัวอักษรให้ถูกต้องจากคำศัพท์ของคุณ',
            onTap: () => _push(
              context,
              const GameLauncherScreen(gameMode: GameMode.wordScramble),
            ),
          ),
          _LearningTile(
            icon: Icons.mic_none_outlined,
            title: 'Dictation',
            subtitle: 'พิมพ์ตามที่ได้ยินจากคำศัพท์ของคุณ',
            onTap: () => _push(
              context,
              const GameLauncherScreen(gameMode: GameMode.dictation),
            ),
          ),
          _LearningTile(
            icon: Icons.sports_esports_outlined,
            title: 'Boss Battle',
            subtitle: 'ประลองความรู้กับบอสจากคำศัพท์ของคุณ',
            onTap: () => _push(
              context,
              const GameLauncherScreen(gameMode: GameMode.bossBattle),
            ),
          ),
          _LearningTile(
            icon: Icons.map_outlined,
            title: 'World Map',
            subtitle: 'แผนที่การเรียนรู้ตามระดับ CEFR',
            onTap: () => _push(context, const LearningWorldMapScreen()),
          ),
          _LearningTile(
            icon: Icons.assessment_outlined,
            title: 'CEFR Diagnostic',
            subtitle: 'ทดสอบวัดระดับภาษา',
            onTap: () => _push(context, const CefrDiagnosticTestScreen()),
          ),
          _LearningTile(
            icon: Icons.record_voice_over,
            title: 'Phonetic Explorer',
            subtitle: 'สำรวจสัทอักษรสากล (IPA)',
            onTap: () => _push(context, const PhoneticExplorerScreen()),
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

  Future<void> _openCategoryQuiz(BuildContext context) async {
    final categoryId = await AppNavigator.pushPage<String>(
      context,
      AppPage<String>(
        name: 'learning/category-selector',
        builder: (_) => const SelectCategoryForQuiz(),
      ),
    );
    if (categoryId != null && context.mounted) {
      await _push(context, QuizScreen(categoryId: categoryId));
    }
  }

  Future<void> _push(BuildContext context, Widget screen) {
    return AppNavigator.pushPage<void>(
      context,
      AppPage<void>(name: 'learning/activity', builder: (_) => screen),
    );
  }
}

class _LearningTile extends StatelessWidget {
  const _LearningTile({
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
