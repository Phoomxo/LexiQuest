enum RewardItemKind { theme, wallpaper, headgear, weapon, armor, relic }

final class RewardCatalogItem {
  const RewardCatalogItem({
    required this.id,
    required this.catalogVersion,
    required this.kind,
    required this.name,
    required this.description,
    required this.price,
  });

  final String id;
  final int catalogVersion;
  final RewardItemKind kind;
  final String name;
  final String description;
  final int price;

  String get slot => switch (kind) {
    RewardItemKind.theme => 'theme',
    RewardItemKind.wallpaper => 'wallpaper',
    RewardItemKind.headgear => 'headgear',
    RewardItemKind.weapon => 'weapon',
    RewardItemKind.armor => 'armor',
    RewardItemKind.relic => 'relic',
  };
}

abstract final class RewardCatalog {
  static const version = 1;

  static const items = <RewardCatalogItem>[
    RewardCatalogItem(
      id: 'theme_default',
      catalogVersion: version,
      kind: RewardItemKind.theme,
      name: 'ธีมมาตรฐาน',
      description: 'ธีม Material 3 มาตรฐานของ LexiQuest',
      price: 0,
    ),
    RewardCatalogItem(
      id: 'theme_ocean',
      catalogVersion: version,
      kind: RewardItemKind.theme,
      name: 'ธีมมหาสมุทร',
      description: 'ชุดสีฟ้าเข้มที่อ่านง่ายทั้งโหมดสว่างและมืด',
      price: 80,
    ),
    RewardCatalogItem(
      id: 'wallpaper_focus',
      catalogVersion: version,
      kind: RewardItemKind.wallpaper,
      name: 'พื้นหลังสมาธิ',
      description: 'พื้นหลังเรียบ ลดสิ่งรบกวนระหว่างเรียน',
      price: 60,
    ),
    RewardCatalogItem(
      id: 'headgear_ipa',
      catalogVersion: version,
      kind: RewardItemKind.headgear,
      name: 'หมวก IPA',
      description: 'อุปกรณ์ตกแต่งที่ได้รับจากคะแนนการเรียนจริง',
      price: 100,
    ),
    RewardCatalogItem(
      id: 'weapon_cefr',
      catalogVersion: version,
      kind: RewardItemKind.weapon,
      name: 'ดาบ CEFR',
      description: 'อุปกรณ์ตกแต่งสำหรับโปรไฟล์ผู้เรียน',
      price: 120,
    ),
    RewardCatalogItem(
      id: 'armor_srs',
      catalogVersion: version,
      kind: RewardItemKind.armor,
      name: 'เกราะ SRS',
      description: 'อุปกรณ์ตกแต่งสำหรับโปรไฟล์ผู้เรียน',
      price: 120,
    ),
  ];

  static RewardCatalogItem? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}

final class RewardAccount {
  const RewardAccount({
    required this.balance,
    required this.catalogVersion,
    required this.ownedItemIds,
    required this.equippedBySlot,
    required this.transactionCount,
  });

  final int balance;
  final int catalogVersion;
  final Set<String> ownedItemIds;
  final Map<String, String> equippedBySlot;
  final int transactionCount;
}

enum PurchaseStatus { purchased, alreadyOwned, replayed }

final class PurchaseResult {
  const PurchaseResult({required this.status, required this.account});

  final PurchaseStatus status;
  final RewardAccount account;
}

enum RewardFailureCode {
  unknownItem,
  staleCatalog,
  insufficientBalance,
  invalidIdempotencyKey,
  notOwned,
  slotMismatch,
}

final class RewardException implements Exception {
  const RewardException(this.code);

  final RewardFailureCode code;
}
