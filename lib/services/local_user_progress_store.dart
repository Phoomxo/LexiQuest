import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Provides offline-first local persistence for user progress, ZPD level,
/// streaks, and offline SRS flashcards without requiring Cloud DB access.
class LocalUserProgressStore {
  LocalUserProgressStore([SharedPreferences? prefs]) : _prefs = prefs;

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async =>
      _prefs ??= await SharedPreferences.getInstance();

  static const String _kZpdLevelKey = 'lexi_local_zpd_level';
  static const String _kStreakCountKey = 'lexi_local_streak_count';
  static const String _kMasteredWordsKey = 'lexi_local_mastered_words';
  static const String _kSrsProgressKey = 'lexi_local_srs_progress';

  /// Saves local ZPD level (e.g. 'A1', 'B2')
  Future<bool> saveZpdLevel(String level) async {
    final prefs = await _instance;
    return prefs.setString(_kZpdLevelKey, level);
  }

  /// Gets saved ZPD level, defaulting to 'A1'
  Future<String> getZpdLevel() async {
    final prefs = await _instance;
    return prefs.getString(_kZpdLevelKey) ?? 'A1';
  }

  /// Increments local daily streak count
  Future<int> incrementStreak() async {
    final prefs = await _instance;
    final current = prefs.getInt(_kStreakCountKey) ?? 0;
    final next = current + 1;
    await prefs.setInt(_kStreakCountKey, next);
    return next;
  }

  /// Gets current streak count
  Future<int> getStreakCount() async {
    final prefs = await _instance;
    return prefs.getInt(_kStreakCountKey) ?? 0;
  }

  /// Adds a word ID to mastered words list
  Future<void> addMasteredWord(String wordId) async {
    final prefs = await _instance;
    final set = (prefs.getStringList(_kMasteredWordsKey) ?? []).toSet();
    set.add(wordId);
    await prefs.setStringList(_kMasteredWordsKey, set.toList());
  }

  /// Gets list of mastered word IDs
  Future<List<String>> getMasteredWords() async {
    final prefs = await _instance;
    return prefs.getStringList(_kMasteredWordsKey) ?? [];
  }

  /// Saves SRS item progress map offline
  Future<bool> saveSrsProgress(Map<String, dynamic> progressData) async {
    final prefs = await _instance;
    final rawJson = jsonEncode(progressData);
    return prefs.setString(_kSrsProgressKey, rawJson);
  }

  /// Loads SRS item progress map offline
  Future<Map<String, dynamic>> loadSrsProgress() async {
    final prefs = await _instance;
    final rawJson = prefs.getString(_kSrsProgressKey);
    if (rawJson == null || rawJson.isEmpty) return {};
    try {
      return jsonDecode(rawJson) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Clears all local progress store entries
  Future<void> clearAll() async {
    final prefs = await _instance;
    await prefs.remove(_kZpdLevelKey);
    await prefs.remove(_kStreakCountKey);
    await prefs.remove(_kMasteredWordsKey);
    await prefs.remove(_kSrsProgressKey);
  }
}
