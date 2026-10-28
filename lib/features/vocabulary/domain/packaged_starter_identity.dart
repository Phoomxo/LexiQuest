/// Fixed public identities of the internally reviewed, read-only starter set.
/// Identity reserves mutation/UI behavior; reads additionally verify integrity.
abstract final class PackagedStarterIdentity {
  static const ownerId = 'packaged:lexiquest-starter-v1';
  static const categoryId = 'category:starter-everyday-r1';
  static const wordKeys = <String>[
    'book',
    'pencil',
    'chair',
    'door',
    'window',
    'bottle',
    'cup',
    'spoon',
    'plate',
    'bag',
    'clock',
    'key',
  ];
  static bool isReservedCategoryId(String id) => id == categoryId;
  static bool isReservedId(String id) =>
      isReservedCategoryId(id) ||
      wordKeys.any((key) => id == 'word:starter-$key');
  static bool isReadOnly({
    required String ownerId,
    required String contentId,
  }) => ownerId == PackagedStarterIdentity.ownerId || isReservedId(contentId);
}
