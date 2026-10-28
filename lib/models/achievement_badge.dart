class AchievementBadge {
  final String id;
  final String title;
  final String description;
  final int coinReward;
  final bool isUnlocked;

  const AchievementBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.coinReward,
    this.isUnlocked = false,
  });

  AchievementBadge copyWith({bool? isUnlocked}) {
    return AchievementBadge(
      id: id,
      title: title,
      description: description,
      coinReward: coinReward,
      isUnlocked: isUnlocked ?? this.isUnlocked,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'coinReward': coinReward,
    'isUnlocked': isUnlocked,
  };

  factory AchievementBadge.fromJson(Map<String, dynamic> json) =>
      AchievementBadge(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        coinReward: json['coinReward'] as int? ?? 50,
        isUnlocked: json['isUnlocked'] as bool? ?? false,
      );
}
