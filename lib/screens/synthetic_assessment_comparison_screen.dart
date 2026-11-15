import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/research/domain/synthetic_assessment_comparison.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';

class SyntheticAssessmentComparisonScreen extends StatelessWidget {
  const SyntheticAssessmentComparisonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final comparison = SyntheticAssessmentComparison.example;
    final questionCount = comparison.answers.length;
    return _assessmentPage(context, 'ก่อนและหลังฝึก', [
      const Text('ข้อมูลสมมติ · ชุดคำเดียวกัน'),
      const SizedBox(height: 12),
      Card(
        child: Column(
          children: [
            ListTile(
              title: const Text('ก่อนฝึก'),
              trailing: Text('${comparison.beforeCorrect} / $questionCount'),
            ),
            ListTile(
              title: const Text('หลังฝึก'),
              trailing: Text('${comparison.afterCorrect} / $questionCount'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const Text('ตัวเลขนี้อธิบายคำตอบของผู้เรียนสมมติในสองรอบ'),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () {
          if (ModalRoute.isCurrentOf(context) != true) return;
          AppNavigator.pushPage<void>(
            context,
            AppPage<void>(
              name: 'research/synthetic-assessment/answers',
              builder: (context) => _assessmentPage(context, 'เทียบคำตอบรายคำ', [
                Text(
                  'ตัวอย่างคู่ฝึก 01 · ชุดการเดินทาง ฉบับ ${comparison.pins.formRevision}',
                ),
                const SizedBox(height: 12),
                for (final answer in comparison.answers)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${answer.item.word} · เลือกความหมาย',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text('ก่อนฝึก ตอบว่า${answer.before}'),
                          Text('หลังฝึก ตอบว่า${answer.after}'),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('คำตอบตัวอย่างสร้างจากข้อมูลสมมติ'),
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('กลับไปดูผลเปรียบเทียบ'),
                ),
              ]),
            ),
          );
        },
        child: const Text('ดูคำตอบที่ใช้เปรียบเทียบ'),
      ),
      TextButton(
        onPressed: () => Navigator.maybePop(context),
        child: const Text('กลับไปดูตัวเลือกงานวิจัย'),
      ),
    ]);
  }
}

Widget _assessmentPage(
  BuildContext context,
  String title,
  List<Widget> items,
) => Scaffold(
  appBar: AppBar(
    toolbarHeight: M3Theme.appBarToolbarHeight(context),
    title: M3Theme.appBarTitle(context, title),
  ),
  body: SafeArea(
    child: AdaptiveContentPane(
      maxWidth: AdaptiveContentPane.formMaxWidth,
      child: ListView(padding: const EdgeInsets.all(16), children: items),
    ),
  ),
);
