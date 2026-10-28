import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/achievement_badge.dart';

class AchievementService {
  static const String _kAchievementsKey = 'lexiquest_achievements_v1';
  final SharedPreferences? prefs;

  AchievementService({this.prefs});

  Future<SharedPreferences> _getPrefs() async {
    return prefs ?? await SharedPreferences.getInstance();
  }

  static const List<AchievementBadge> defaultBadges = [
    AchievementBadge(
      id: 'pronunciation_master',
      title: 'Pronunciation Master',
      description: 'ออกเสียงคำศัพท์แม่นยำ 95%+ ครบ 10 ครั้ง',
      coinReward: 100,
    ),
    AchievementBadge(
      id: 'unstoppable_streak',
      title: 'Unstoppable Streak',
      description: 'ฝึกฝนคำศัพท์ต่อเนื่องครบ 7 วัน',
      coinReward: 150,
    ),
    AchievementBadge(
      id: 'dictation_expert',
      title: 'Dictation Expert',
      description: 'ฟังและสะกดคำศัพท์ถูกต้อง 15 ข้อ',
      coinReward: 120,
    ),
  ];

  Future<List<AchievementBadge>> loadBadges() async {
    final p = await _getPrefs();
    final jsonStr = p.getString(_kAchievementsKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      return defaultBadges;
    }
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      final loaded = decoded
          .map((e) => AchievementBadge.fromJson(e as Map<String, dynamic>))
          .toList();
      return loaded;
    } catch (_) {
      return defaultBadges;
    }
  }

  Future<bool> unlockBadge(String badgeId) async {
    final badges = await loadBadges();
    final index = badges.indexWhere((b) => b.id == badgeId);
    if (index == -1 || badges[index].isUnlocked) {
      return false; // Already unlocked or not found
    }

    final updated = List<AchievementBadge>.from(badges);
    updated[index] = updated[index].copyWith(isUnlocked: true);

    final p = await _getPrefs();
    await p.setString(
      _kAchievementsKey,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
    return true;
  }
}
