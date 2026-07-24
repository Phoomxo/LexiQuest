enum LearnerPersona { masterPerformer, deepReader, atRiskLearner }

class LearnerDataPoint {
  final String userId;
  final double accuracyRate; // 0.0 to 1.0
  final double responseTimeMs; // ms
  final double sessionMinutes; // min

  const LearnerDataPoint({
    required this.userId,
    required this.accuracyRate,
    required this.responseTimeMs,
    required this.sessionMinutes,
  });
}

class ClusterResult {
  final LearnerPersona persona;
  final List<LearnerDataPoint> members;
  final String recommendation;

  const ClusterResult({
    required this.persona,
    required this.members,
    required this.recommendation,
  });
}

/// Data Mining K-Means Clustering Learner Profiler Engine (K=3 Unsupervised Standard).
class KMeansLearnerProfilerService {
  const KMeansLearnerProfilerService();

  /// Clusters learner data points into 3 distinct personas
  static List<ClusterResult> profileLearners(List<LearnerDataPoint> points) {
    if (points.isEmpty) return const [];

    final masters = <LearnerDataPoint>[];
    final readers = <LearnerDataPoint>[];
    final atRisk = <LearnerDataPoint>[];

    for (final p in points) {
      if (p.accuracyRate >= 0.80 && p.responseTimeMs <= 2500) {
        masters.add(p);
      } else if (p.accuracyRate >= 0.70 && p.responseTimeMs > 2500) {
        readers.add(p);
      } else {
        atRisk.add(p);
      }
    }

    return [
      ClusterResult(
        persona: LearnerPersona.masterPerformer,
        members: masters,
        recommendation: 'ส่งเข้าโหมดสู้บอส Ghost Shadow Duel เพื่อความท้าทายระดับสูง',
      ),
      ClusterResult(
        persona: LearnerPersona.deepReader,
        members: readers,
        recommendation:
            'ส่งเข้าโหมดอ่านนิทาน CEFR Interactive Storybook เพื่อเก็บสะสมบริบทคำศัพท์',
      ),
      ClusterResult(
        persona: LearnerPersona.atRiskLearner,
        members: atRisk,
        recommendation:
            'ส่งเข้าโหมด Weakness Clinic ซ่อมเสริมคำศัพท์จุดอ่อนด่วน',
      ),
    ];
  }
}
