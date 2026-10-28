import '../models/cefr_word.dart';
import 'cefr_service.dart';

class ZpdRecommenderService {
  final CefrService _cefrService;

  ZpdRecommenderService({CefrService? cefrService})
    : _cefrService = cefrService ?? CefrService();

  static const List<String> cefrHierarchy = [
    'A1',
    'A2',
    'B1',
    'B2',
    'C1',
    'C2',
  ];

  /// Recommends words from the next CEFR level (+1 level) if current accuracy >= threshold (default 80%).
  List<CefrWord> recommendZpdWords({
    required String currentLevel,
    required double currentAccuracyPercent,
    double thresholdPercent = 80.0,
  }) {
    final normalized = currentLevel.trim().toUpperCase();
    final index = cefrHierarchy.indexOf(normalized);

    if (index == -1 || index >= cefrHierarchy.length - 1) {
      // Return current level if already at C2 or invalid
      return _cefrService.getWordsByLevel(normalized);
    }

    if (currentAccuracyPercent >= thresholdPercent) {
      final nextLevel = cefrHierarchy[index + 1];
      return _cefrService.getWordsByLevel(nextLevel);
    }

    return _cefrService.getWordsByLevel(normalized);
  }
}
