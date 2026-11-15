import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../navigation/app_routes.dart';
import '../widgets/adaptive_content_pane.dart';

const _sample = (
  questionCount: 5,
  before: (correct: 2, meanResponseMs: 2400),
  after: (correct: 3, meanResponseMs: 1600),
);

String _percent(int correct) =>
    '${(correct * 100 / _sample.questionCount).round()}%';

String _seconds(int milliseconds) =>
    '${(milliseconds / 1000).toStringAsFixed(1)} วินาที';

enum _ChartDetail {
  comparison('compare', 'เปรียบเทียบสองรอบ', 'ดูกราฟอีกครั้ง'),
  provenance('source', 'ที่มาของตัวเลข', 'กลับไปดูกราฟ');

  const _ChartDetail(this.routeName, this.title, this.chartLabel);

  final String routeName;
  final String title;
  final String chartLabel;
}

class ThesisChartScreen extends StatelessWidget {
  const ThesisChartScreen({super.key, required this.returnLabel});

  final String returnLabel;

  void _openDetail(BuildContext context, _ChartDetail detail) {
    final chart = ModalRoute.of(context);
    if (chart?.isCurrent != true) return;
    final navigator = Navigator.of(context);
    AppNavigator.pushPage<bool>(
      context,
      AppPage<bool>(
        name: 'learning/sample-chart/${detail.routeName}',
        builder: (context) => _SampleScaffold(
          title: detail.title,
          children: [
            if (detail == _ChartDetail.comparison) ...[
              Text('ข้อมูลสมมติ · คำชุดเดิม ${_sample.questionCount} ข้อ'),
              const SizedBox(height: 20),
              Text(
                'ตอบถูกเพิ่มขึ้น ${_sample.after.correct - _sample.before.correct} ข้อ',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${_sample.before.correct} จาก ${_sample.questionCount}  →  '
                '${_sample.after.correct} จาก ${_sample.questionCount}',
              ),
              Text(
                'ข้อที่ตอบถูกคิดเป็น ${_percent(_sample.before.correct)} '
                'และ ${_percent(_sample.after.correct)}',
              ),
              const SizedBox(height: 20),
              Text(
                'เวลาตอบเฉลี่ยต่อข้อ',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${_seconds(_sample.before.meanResponseMs)}  →  '
                '${_seconds(_sample.after.meanResponseMs)}',
              ),
              const Text('ตัวอย่างนี้บอกเฉพาะสิ่งที่เกิดในสองรอบ'),
            ] else ...[
              const Text('ตัวอย่างสำหรับฝึกอ่านกราฟ'),
              const SizedBox(height: 20),
              Text(
                'ตัวเลขทั้งหมดเป็นข้อมูลสมมติ',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text('ตัวอย่างนี้ไม่ลงทะเบียนหรือส่งข้อมูลวิจัย'),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(returnLabel, textAlign: TextAlign.center),
            ),
            OutlinedButton(
              onPressed: () => Navigator.maybePop(context),
              child: Text(detail.chartLabel, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    ).then((goToOrigin) {
      if (goToOrigin == true && navigator.mounted && chart?.isCurrent == true) {
        navigator.pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) => _SampleScaffold(
    title: 'อ่านกราฟตัวอย่าง',
    children: [
      const Text('ผู้เรียนสมมติหนึ่งคน · ชุดคำเดียวกัน'),
      const SizedBox(height: 20),
      _ScoreBar(label: 'ก่อนฝึก', correct: _sample.before.correct),
      const SizedBox(height: 12),
      _ScoreBar(label: 'หลังฝึก', correct: _sample.after.correct),
      const SizedBox(height: 20),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('เวลาในการตอบ'),
        subtitle: const Text('ดูผลรอบแรกและรอบหลัง'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openDetail(context, _ChartDetail.comparison),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('ข้อมูลนี้มาจากไหน'),
        subtitle: const Text('ดูขอบเขตของตัวอย่าง'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openDetail(context, _ChartDetail.provenance),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => Navigator.maybePop(context),
        child: Text(returnLabel, textAlign: TextAlign.center),
      ),
    ],
  );
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.label, required this.correct});

  final String label;
  final int correct;

  @override
  Widget build(BuildContext context) {
    final description = '$label $correct จาก ${_sample.questionCount} ข้อ';
    return Semantics(
      label: description,
      value: _percent(correct),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: correct / _sample.questionCount,
            minHeight: 8,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
        ],
      ),
    );
  }
}

class _SampleScaffold extends StatelessWidget {
  const _SampleScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: M3Theme.appBarToolbarHeight(context),
      title: M3Theme.appBarTitle(context, title),
    ),
    body: AdaptiveContentPane(
      maxWidth: AdaptiveContentPane.formMaxWidth,
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: children),
      ),
    ),
  );
}
