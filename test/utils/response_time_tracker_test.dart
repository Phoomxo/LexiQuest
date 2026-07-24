import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/utils/response_time_tracker.dart';

void main() {
  test(
    'ResponseTimeTracker measures elapsed time and flags hesitation',
    () async {
      final tracker = ResponseTimeTracker();
      tracker.startTiming();
      await Future.delayed(const Duration(milliseconds: 50));
      final elapsed = tracker.stopTimingMs();

      expect(elapsed >= 40, true);
      expect(
        ResponseTimeTracker.isHesitantResponse(6000, thresholdMs: 5000),
        true,
      );
      expect(
        ResponseTimeTracker.isHesitantResponse(2000, thresholdMs: 5000),
        false,
      );
    },
  );
}
