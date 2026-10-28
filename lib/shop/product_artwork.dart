sealed class ProductArtwork {
  const ProductArtwork();

  String? get storageValue;
}

final class DefaultProductArtwork extends ProductArtwork {
  const DefaultProductArtwork();

  @override
  String? get storageValue => null;

  @override
  bool operator ==(Object other) => other is DefaultProductArtwork;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class NetworkProductArtwork extends ProductArtwork {
  const NetworkProductArtwork(this.uri);

  final Uri uri;

  @override
  String get storageValue => uri.toString();

  @override
  bool operator ==(Object other) =>
      other is NetworkProductArtwork && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

ProductArtwork resolveProductArtwork(Map<String, Object?> product) {
  final rawUrl = product['image_url'];
  if (rawUrl is! String) return const DefaultProductArtwork();
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return const DefaultProductArtwork();
  }
  return NetworkProductArtwork(uri);
}
