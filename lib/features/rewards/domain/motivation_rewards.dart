final class MotivationRewardTotals {
  MotivationRewardTotals({
    required this.questXp,
    required this.freezeCount,
    required Set<String> protectedDays,
    required Set<String> acceptedReceiptIds,
  }) : protectedDays = Set.unmodifiable(protectedDays),
       acceptedReceiptIds = Set.unmodifiable(acceptedReceiptIds);
  final int questXp;
  final int freezeCount;
  final Set<String> protectedDays;
  final Set<String> acceptedReceiptIds;
}

abstract final class MotivationRewardPolicy {
  static const int version = 1;
  static const String questXp = 'grantQuestXpV1';
  static const String weeklyFreeze = 'grantQuestFreezeV1';
  static const String protection = 'consumeFreezeProtectionV1';
}
