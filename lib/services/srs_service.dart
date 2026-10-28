import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/srs_item.dart';

/// Single-user Spaced Repetition Service backed by SharedPreferences.
///
/// @deprecated Use [LearningUseCases.startDueReview] backed by Drift.
/// SharedPreferences storage is superseded by the `srs_states` Drift table.
/// Removal target: Phase 1.
@Deprecated(
  'Use LearningUseCases.startDueReview() '
  '(lib/features/learning/application/learning_use_cases.dart). '
  'Removal target: Phase 1.',
)
class SrsService {
  static const String _kSrsStorageKey = 'lexiquest_srs_items_v1';
  final SharedPreferences? prefs;

  SrsService({this.prefs});

  Future<SharedPreferences> _getPrefs() async {
    return prefs ?? await SharedPreferences.getInstance();
  }

  Future<Map<String, SrsItem>> loadItemsMap() async {
    final prefs = await _getPrefs();
    final rawJson = prefs.getString(_kSrsStorageKey);
    if (rawJson == null || rawJson.isEmpty) {
      return {};
    }
    try {
      final Map<String, dynamic> decoded = jsonDecode(rawJson);
      final result = <String, SrsItem>{};
      decoded.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          result[key] = SrsItem.fromJson(value);
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveItemsMap(Map<String, SrsItem> map) async {
    final prefs = await _getPrefs();
    final jsonMap = <String, dynamic>{};
    map.forEach((key, item) {
      jsonMap[key] = item.toJson();
    });
    await prefs.setString(_kSrsStorageKey, jsonEncode(jsonMap));
  }

  Future<SrsItem> recordReview(
    String word,
    bool isCorrect, {
    DateTime? now,
  }) async {
    final map = await loadItemsMap();
    final existing = map[word] ?? SrsItem.initial(word, now: now);
    final updated = existing.processReview(isCorrect: isCorrect, now: now);
    map[word] = updated;
    await saveItemsMap(map);
    return updated;
  }

  Future<List<SrsItem>> getDueItems({DateTime? now}) async {
    final map = await loadItemsMap();
    final current = now ?? DateTime.now();
    return map.values.where((item) => item.isDue(now: current)).toList();
  }
}
