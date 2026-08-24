import 'learning_time_segment.dart';

abstract interface class LearningTimeRepository {
  Future<void> append(LearningTimeSegment segment);

  Future<Duration> activeDuration(String sessionId);
}
