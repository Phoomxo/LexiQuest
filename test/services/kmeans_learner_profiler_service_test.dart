import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/kmeans_learner_profiler_service.dart';

void main() {
  test('profileLearners categorizes learners into 3 distinct personas', () {
    final points = [
      const LearnerDataPoint(
        userId: 'u1',
        accuracyRate: 0.90,
        responseTimeMs: 1800,
        sessionMinutes: 15,
      ),
      const LearnerDataPoint(
        userId: 'u2',
        accuracyRate: 0.75,
        responseTimeMs: 3500,
        sessionMinutes: 25,
      ),
      const LearnerDataPoint(
        userId: 'u3',
        accuracyRate: 0.45,
        responseTimeMs: 4000,
        sessionMinutes: 10,
      ),
    ];

    final clusters = KMeansLearnerProfilerService.profileLearners(points);

    expect(clusters.length, 3);
    expect(clusters[0].members.map((m) => m.userId), contains('u1'));
    expect(clusters[1].members.map((m) => m.userId), contains('u2'));
    expect(clusters[2].members.map((m) => m.userId), contains('u3'));
  });
}
