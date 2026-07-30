import 'package:flutter/material.dart';

import 'mastery_dashboard_screen.dart';
import 'quiz_screen.dart';
import 'select_category_for_quiz.dart';
import '../navigation/app_routes.dart';
import 'srs_flashcards_screen.dart';
import 'weakness_clinic_screen.dart';

class ChooseModeScreen extends StatelessWidget {
  const ChooseModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เลือกกิจกรรมการเรียน')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Text(
              'กิจกรรมกล้อง เสียง AI และเกมที่ยังไม่เชื่อมข้อมูลจริงจะไม่แสดงในรุ่นทดสอบนี้',
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
