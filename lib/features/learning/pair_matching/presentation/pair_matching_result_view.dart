import 'package:flutter/material.dart';
import '../domain/pair_matching_history_projection.dart';
import '../domain/pair_matching_launch.dart';
import '../domain/pair_active_clock.dart';

/// Read-only descriptive outcome; the owning host handles typed navigation.
final class PairMatchingResultView extends StatelessWidget {
  const PairMatchingResultView({
    super.key,
    required this.result,
    this.onPracticeReplay,
    this.onReview,
    this.locale = const Locale('th'),
  });
  final Locale locale;
  final PairMatchingHistoryProjection result;
  final VoidCallback? onPracticeReplay, onReview;
  @override
  Widget build(BuildContext context) {
    final english = locale.languageCode == 'en';
    String copy(String th, String en) => english ? en : th;
    final replay = result.purpose == PairSessionPurpose.practiceReplay;
    final stars = result.result.stars;
    final timer = switch (result.timer.mode) {
      PairTimerMode.off => copy('ไม่ได้จับเวลา', 'Timer off'),
      PairTimerMode.continuedUntimed => copy(
        'เล่นต่อแบบไม่จับเวลา',
        'Continued untimed',
      ),
      PairTimerMode.timeoutDecision => copy(
        'ถึงเวลาที่ตั้งไว้',
        'Time target reached',
      ),
      _ => copy('ทันเป้าหมายเวลา', 'Within time target'),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              replay
                  ? copy('ผลการฝึกซ้ำ', 'Practice Replay result')
                  : copy('ผลการจับคู่', 'Pair Matching result'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (replay)
            Text(
              copy(
                'การฝึกซ้ำไม่เพิ่มความก้าวหน้าหรือรางวัล',
                'Practice Replay does not add progress or rewards',
              ),
            ),
          const SizedBox(height: 16),
          Text(
            copy(
              'จับคู่แล้ว ${result.result.matched} คู่',
              'Matched ${result.result.matched} pairs',
            ),
          ),
          Text(
            copy(
              'ทำได้เอง ${result.result.independent} คู่',
              'Independent ${result.result.independent} pairs',
            ),
          ),
          Text(
            copy(
              'ใช้ตัวช่วย ${result.result.assisted} คู่',
              'Assisted ${result.result.assisted} pairs',
            ),
          ),
          Text(
            stars == null
                ? copy('ยังไม่มีผลดาว', 'Not scored')
                : copy('ดาว $stars/3', 'Stars $stars/3'),
          ),
          Text(timer),
          if (result.timer.mode != PairTimerMode.off)
            Text(
              copy(
                'เวลาที่ตัวจับเวลานับ ${result.timer.elapsedActiveMs ~/ 1000} วินาที',
                'Challenge timer elapsed ${result.timer.elapsedActiveMs ~/ 1000} seconds',
              ),
            ),
          Text(
            result.reviewNext
                ? copy(
                    'ทบทวนคำที่ใช้ตัวช่วยหรือเคยตอบผิดได้ต่อไป',
                    'Review assisted or previously missed words next',
                  )
                : copy('ไปทบทวนคำที่ถึงเวลาได้ต่อไป', 'Review due words next'),
          ),
          if (onReview != null)
            TextButton(
              onPressed: onReview,
              child: Text(copy('ไปทบทวน', 'Review next')),
            ),
          if (onPracticeReplay != null)
            FilledButton(
              onPressed: onPracticeReplay,
              child: Text(copy('ฝึกซ้ำชุดเดิม', 'Practice Replay')),
            ),
        ],
      ),
    );
  }
}
