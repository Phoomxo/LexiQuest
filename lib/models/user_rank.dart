enum RankTier {
  bronze('Bronze', 'ทองแดง', 0),
  silver('Silver', 'เงิน', 500),
  gold('Gold', 'ทอง', 1500),
  platinum('Platinum', 'พลาตินัม', 3500),
  diamond('Diamond', 'เพชร', 7500);

  final String nameEn;
  final String nameTh;
  final int minXp;

  const RankTier(this.nameEn, this.nameTh, this.minXp);
}

class UserRank {
  final int totalXp;
  final RankTier tier;

  const UserRank({required this.totalXp, required this.tier});

  int get xpToNextTier {
    final nextTierIndex = tier.index + 1;
    if (nextTierIndex >= RankTier.values.length) return 0;
    return RankTier.values[nextTierIndex].minXp - totalXp;
  }
}
