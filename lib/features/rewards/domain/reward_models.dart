enum RewardItemKind { theme, wallpaper, headgear, weapon, armor, relic }

final class RewardCatalogItem {
  const RewardCatalogItem({
    required this.id,
    required this.catalogVersion,
    required this.kind,
    required this.name,
    required this.description,
    required this.price,
    required this.requiredAvatarLevel,
  });

  final String id;
  final int catalogVersion;
  final RewardItemKind kind;
  final String name;
  final String description;
  final int price;
  final int requiredAvatarLevel;

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
  static const catalogV1Version = 1;
  static const catalogV2Version = 2;
  static const legacyVersion = catalogV1Version;
  static const version = catalogV2Version;

  // Frozen f32 catalog snapshot. Persisted catalog-v2 transactions always
  // resolve through this list even after a future current-catalog bump.
  static const catalogV2Items = <RewardCatalogItem>[
    RewardCatalogItem(
      id: 'theme_default',
      catalogVersion: catalogV2Version,
      kind: RewardItemKind.theme,
      name: 'ธีมมาตรฐาน',
      description: 'ธีม Material 3 มาตรฐานของ LexiQuest',
      price: 0,
      requiredAvatarLevel: 1,
    ),
    RewardCatalogItem(
      id: 'theme_ocean',
      catalogVersion: catalogV2Version,
      kind: RewardItemKind.theme,
      name: 'ธีมมหาสมุทร',
      description: 'ชุดสีฟ้าเข้มที่อ่านง่ายทั้งโหมดสว่างและมืด',
      price: 80,
      requiredAvatarLevel: 3,
    ),
    RewardCatalogItem(
      id: 'wallpaper_focus',
      catalogVersion: catalogV2Version,
      kind: RewardItemKind.wallpaper,
      name: 'พื้นหลังสมาธิ',
      description: 'พื้นหลังเรียบ ลดสิ่งรบกวนระหว่างเรียน',
      price: 60,
      requiredAvatarLevel: 2,
    ),
    RewardCatalogItem(
      id: 'headgear_ipa',
      catalogVersion: catalogV2Version,
      kind: RewardItemKind.headgear,
      name: 'หมวก IPA',
      description: 'อุปกรณ์ตกแต่งที่ได้รับจากคะแนนการเรียนจริง',
      price: 100,
      requiredAvatarLevel: 4,
    ),
    RewardCatalogItem(
      id: 'weapon_cefr',
      catalogVersion: catalogV2Version,
      kind: RewardItemKind.weapon,
      name: 'ดาบ CEFR',
      description: 'อุปกรณ์ตกแต่งสำหรับโปรไฟล์ผู้เรียน',
      price: 120,
      requiredAvatarLevel: 5,
    ),
    RewardCatalogItem(
      id: 'armor_srs',
      catalogVersion: catalogV2Version,
      kind: RewardItemKind.armor,
      name: 'เกราะ SRS',
      description: 'อุปกรณ์ตกแต่งสำหรับโปรไฟล์ผู้เรียน',
      price: 120,
      requiredAvatarLevel: 5,
    ),
  ];
  static const items = catalogV2Items;

  // Frozen pre-f32 catalog snapshot. These definitions remain readable only
  // so an explicitly grandfathered v1 transaction can be reconstructed after
  // upgrade; new writers always use [items] and [version].
  static const catalogV1Items = <RewardCatalogItem>[
    RewardCatalogItem(
      id: 'theme_default',
      catalogVersion: catalogV1Version,
      kind: RewardItemKind.theme,
      name: 'ธีมมาตรฐาน',
      description: 'ธีม Material 3 มาตรฐานของ LexiQuest',
      price: 0,
      requiredAvatarLevel: 1,
    ),
    RewardCatalogItem(
      id: 'theme_ocean',
      catalogVersion: catalogV1Version,
      kind: RewardItemKind.theme,
      name: 'ธีมมหาสมุทร',
      description: 'ชุดสีฟ้าเข้มที่อ่านง่ายทั้งโหมดสว่างและมืด',
      price: 80,
      requiredAvatarLevel: 3,
    ),
    RewardCatalogItem(
      id: 'wallpaper_focus',
      catalogVersion: catalogV1Version,
      kind: RewardItemKind.wallpaper,
      name: 'พื้นหลังสมาธิ',
      description: 'พื้นหลังเรียบ ลดสิ่งรบกวนระหว่างเรียน',
      price: 60,
      requiredAvatarLevel: 2,
    ),
    RewardCatalogItem(
      id: 'headgear_ipa',
      catalogVersion: catalogV1Version,
      kind: RewardItemKind.headgear,
      name: 'หมวก IPA',
      description: 'อุปกรณ์ตกแต่งที่ได้รับจากคะแนนการเรียนจริง',
      price: 100,
      requiredAvatarLevel: 4,
    ),
    RewardCatalogItem(
      id: 'weapon_cefr',
      catalogVersion: catalogV1Version,
      kind: RewardItemKind.weapon,
      name: 'ดาบ CEFR',
      description: 'อุปกรณ์ตกแต่งสำหรับโปรไฟล์ผู้เรียน',
      price: 120,
      requiredAvatarLevel: 5,
    ),
    RewardCatalogItem(
      id: 'armor_srs',
      catalogVersion: catalogV1Version,
      kind: RewardItemKind.armor,
      name: 'เกราะ SRS',
      description: 'อุปกรณ์ตกแต่งสำหรับโปรไฟล์ผู้เรียน',
      price: 120,
      requiredAvatarLevel: 5,
    ),
  ];
  static const legacyItems = catalogV1Items;

  static RewardCatalogItem? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static RewardCatalogItem? byIdAtVersion(String id, int catalogVersion) {
    final catalog = switch (catalogVersion) {
      catalogV1Version => catalogV1Items,
      catalogV2Version => catalogV2Items,
      _ => const <RewardCatalogItem>[],
    };
    for (final item in catalog) {
      if (item.id == id) return item;
    }
    return null;
  }
}

final class RewardAccount {
  const RewardAccount({
    required this.coinBalance,
    required this.catalogVersion,
    required this.ownedItemIds,
    required this.equippedBySlot,
    required this.transactionCount,
  });

  final int coinBalance;
  int get balance => coinBalance;
  final int catalogVersion;
  final Set<String> ownedItemIds;
  final Map<String, String> equippedBySlot;
  final int transactionCount;
}

enum PurchaseStatus { purchased, alreadyOwned, replayed }

enum EquipStatus { equipped, replayed }

enum CoinGrantResult { inserted, replayed, capturedByLegacyBackfill }

enum QuestEconomyGrantResult { inserted, replayed }

final class PurchaseResult {
  const PurchaseResult({required this.status, required this.account});

  final PurchaseStatus status;
  final RewardAccount account;
}

final class EquipResult {
  const EquipResult({required this.status, required this.account});

  final EquipStatus status;
  final RewardAccount account;
}

enum RewardFailureCode {
  unknownItem,
  staleCatalog,
  insufficientBalance,
  lockedByProgression,
  invalidIdempotencyKey,
  notOwned,
  slotMismatch,
  evidenceUnavailable,
}

final class RewardException implements Exception {
  const RewardException(this.code);

  final RewardFailureCode code;
}
