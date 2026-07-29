class ZpdAutoTunerService {
  final List<String> levels = const ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  const ZpdAutoTunerService();

  String tuneLevel({
    required String currentLevel,
    required int consecutiveCorrect,
  }) {
    final index = levels.indexOf(currentLevel);
    if (index == -1) return 'A1';

    if (consecutiveCorrect >= 3 && index < levels.length - 1) {
      return levels[index + 1];
    }
    return currentLevel;
  }
}
