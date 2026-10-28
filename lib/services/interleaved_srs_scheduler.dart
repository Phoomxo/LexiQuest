import 'package:vocab_learning_app/models/srs_item.dart';

/// Implements an Interleaved Spaced Repetition algorithm (Lafleur 2024 & Settles 2016)
/// that mixes vocabulary items across distinct categories based on Half-Life Regression decay.
final class InterleavedSrsScheduler {
  const InterleavedSrsScheduler._();

  /// Interleaves a list of [items] across different categories so no two consecutive
  /// items belong to the same category when possible, sorted by decay urgency.
  static List<SrsItem> interleave(List<SrsItem> items) {
    if (items.isEmpty) return const [];
    if (items.length == 1) return List<SrsItem>.from(items);

    // Group items by category / difficulty box
    final map = <String, List<SrsItem>>{};
    for (final item in items) {
      final key = item.boxLevel.toString();
      map.putIfAbsent(key, () => []).add(item);
    }

    // Sort each bucket by due date / interval
    for (final bucket in map.values) {
      bucket.sort((a, b) => a.intervalDays.compareTo(b.intervalDays));
    }

    final result = <SrsItem>[];
    String? lastCategory;

    while (map.isNotEmpty) {
      // Find a key different from lastCategory with non-empty list
      String? targetKey;
      for (final k in map.keys) {
        if (k != lastCategory && map[k]!.isNotEmpty) {
          targetKey = k;
          break;
        }
      }

      // Fallback to any key if no distinct category remains
      targetKey ??= map.keys.first;

      final list = map[targetKey]!;
      final nextItem = list.removeAt(0);
      result.add(nextItem);
      lastCategory = targetKey;

      if (list.isEmpty) {
        map.remove(targetKey);
      }
    }

    return result;
  }
}
