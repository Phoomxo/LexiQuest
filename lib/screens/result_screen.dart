import 'package:flutter/material.dart';
import '../navigation/app_routes.dart';
import '../widgets/learning_summary_card.dart';

class ResultScreen extends StatelessWidget {
  final int score;

  const ResultScreen({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('ได้รับคะแนน'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LearningSummaryCard(
              title: 'ได้รับคะแนน',
              value: '$score',
              icon: Icons.school_outlined,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                AppNavigator.resetTo<void>(context, AppRoute.home);
              },
              child: const Text('กลับหน้าหลัก'),
            ),
          ],
        ),
      ),
    );
  }
}
