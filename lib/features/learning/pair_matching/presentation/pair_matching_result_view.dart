import 'package:flutter/material.dart';
import '../../../../widgets/learning_summary_card.dart';
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
    this.onReturn,
    this.locale = const Locale('th'),
  });
  final Locale locale;
  final PairMatchingHistoryProjection result;
  final VoidCallback? onPracticeReplay, onReview, onReturn;
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Focus(
            autofocus: true,
            debugLabel: 'pair-result-heading',
            child: Semantics(
              header: true,
              child: Text(
                replay
                    ? copy('ผลการฝึกซ้ำ', 'Practice Replay result')
                    : copy('ผลการจับคู่', 'Pair Matching result'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          if (replay) ...[
            const SizedBox(height: 8),
            Text(
              copy(
                'การฝึกซ้ำไม่เพิ่มความก้าวหน้าหรือรางวัล',
                'Practice Replay does not add progress or rewards',
              ),
            ),
          ],
          const SizedBox(height: 24),
          LearningSummaryCard(
            title: copy('จำนวนคู่ที่จับได้', 'Matched pairs'),
            value: '${result.result.matched}',
            caption: copy(
              'จับคู่แล้ว ${result.result.matched} คู่',
              'Matched ${result.result.matched} pairs',
            ),
          ),
          if (stars == null)
            Text(
              copy('ยังไม่มีผลดาว', 'Not scored'),
              textAlign: TextAlign.center,
            )
          else
            Semantics(
              label: copy('ดาว $stars จาก 3', '$stars of 3 stars'),
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Icon(
                            i < stars ? Icons.star : Icons.star_border,
                            size: 40,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      ],
                    ),
                    Text(copy('ดาว $stars/3', 'Stars $stars/3')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            copy(
              'ทำได้เอง ${result.result.independent} คู่',
              'Independent ${result.result.independent} pairs',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            copy(
              'ใช้ตัวช่วย ${result.result.assisted} คู่',
              'Assisted ${result.result.assisted} pairs',
            ),
          ),
          const SizedBox(height: 12),
          Text(timer),
          const SizedBox(height: 8),
          Text(
            result.timer.interactiveElapsedMs == null
                ? copy(
                    'ไม่มีข้อมูลเวลาเรียนจริงครบทั้งรอบ',
                    'Full interactive duration unavailable',
                  )
                : replay
                ? copy(
                    'เวลาฝึกซ้ำ ${result.timer.interactiveElapsedMs! ~/ 1000} วินาที',
                    'Practice Replay duration ${result.timer.interactiveElapsedMs! ~/ 1000} seconds',
                  )
                : copy(
                    'ใช้เวลาเรียนจริง ${result.timer.interactiveElapsedMs! ~/ 1000} วินาที',
                    'Interactive duration ${result.timer.interactiveElapsedMs! ~/ 1000} seconds',
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            copy(
              'ดาวเป็นผลการทำรอบนี้ ไม่ใช่ระดับความเก่ง',
              'Stars describe this session, not mastery.',
            ),
          ),
          if (result.timer.mode != PairTimerMode.off) ...[
            const SizedBox(height: 8),
            Text(
              copy(
                'เวลาที่ตัวจับเวลานับ ${result.timer.elapsedActiveMs ~/ 1000} วินาที',
                'Challenge timer elapsed ${result.timer.elapsedActiveMs ~/ 1000} seconds',
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            result.reviewNext
                ? copy(
                    'ทบทวนคำที่ใช้ตัวช่วยหรือเคยตอบผิดได้ต่อไป',
                    'Review assisted or previously missed words next',
                  )
                : copy('ไปทบทวนคำที่ถึงเวลาได้ต่อไป', 'Review due words next'),
          ),
          const SizedBox(height: 24),
          if (onReturn != null)
            FilledButton(
              key: const ValueKey('pair-result-return'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: onReturn,
              child: Text(copy('กลับไปเรียนต่อ', 'Return to learning')),
            ),
          if (onReview != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onReview,
              child: Text(copy('ไปทบทวน', 'Review next')),
            ),
          ],
          if (onPracticeReplay != null) ...[
            const SizedBox(height: 12),
            Text(
              copy(
                'ฝึกซ้ำได้โดยไม่เพิ่มความก้าวหน้าหรือรางวัล',
                'Practice again without additional progress or rewards.',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: onPracticeReplay,
              child: Text(copy('ฝึกซ้ำชุดเดิม', 'Practice Replay')),
            ),
          ],
        ],
      ),
    );
  }
}
