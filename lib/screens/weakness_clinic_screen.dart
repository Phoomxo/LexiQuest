import 'package:flutter/material.dart';

import '../features/progress/domain/progress_models.dart';
import '../runtime/app_dependencies.dart';
import 'mastery_dashboard_screen.dart';
import 'srs_flashcards_screen.dart';

class WeaknessClinicScreen extends StatefulWidget {
  const WeaknessClinicScreen({super.key, this.loader});

  final ProgressLoader? loader;

  @override
  State<WeaknessClinicScreen> createState() => _WeaknessClinicScreenState();
}

class _WeaknessClinicScreenState extends State<WeaknessClinicScreen> {
  Future<ProgressSnapshot>? _load;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load != null) return;
    final loader =
        widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;
    _load = loader == null
        ? Future<ProgressSnapshot>.error(
            StateError('progress dependency unavailable'),
          )
        : loader();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('คลินิกจุดอ่อน')),
      body: FutureBuilder<ProgressSnapshot>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _WeaknessMessage(
              'ไม่สามารถอ่านประวัติคำตอบในเครื่องได้',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final progress = snapshot.data!;
          if (progress.sampleSize == 0) {
            return const _WeaknessMessage(
              'ยังไม่มีคำตอบสำหรับวิเคราะห์\nจำนวนตัวอย่าง: 0',
            );
          }
          if (progress.weaknesses.isEmpty) {
            return _WeaknessMessage(
              'ยังไม่พบคำที่ตอบผิด\nจำนวนตัวอย่าง: ${progress.sampleSize}',
            );
          }
          return _WeaknessBody(progress);
        },
      ),
    );
  }
}

class _WeaknessBody extends StatelessWidget {
  const _WeaknessBody(this.progress);

  final ProgressSnapshot progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'จัดอันดับจากสัดส่วนคำตอบผิด จำนวนตัวอย่างทั้งหมด ${progress.sampleSize}',
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: progress.weaknesses.length,
            itemBuilder: (context, index) {
              final item = progress.weaknesses[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(item.spelling),
                  subtitle: Text(
                    '${item.meaning}\nตอบผิด ${item.incorrectCount}/${item.sampleSize} ครั้ง '
                    '(${(item.errorRate * 100).toStringAsFixed(0)}%)',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: progress.dueReviewCount == 0
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SrsFlashcardsScreen(),
                    ),
                  ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.event_repeat),
            label: Text(
              progress.dueReviewCount == 0
                  ? 'ยังไม่มีคำที่ถึงกำหนดทบทวน'
                  : 'ทบทวนคำที่ถึงกำหนด (${progress.dueReviewCount})',
            ),
          ),
        ),
      ],
    );
  }
}

class _WeaknessMessage extends StatelessWidget {
  const _WeaknessMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
