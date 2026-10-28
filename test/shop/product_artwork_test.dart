import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/shop/product_artwork.dart';

void main() {
  group('resolveProductArtwork', () {
    test('accepts a trimmed HTTPS product image URL', () {
      final artwork = resolveProductArtwork({
        'image_url': '  https://cdn.example.test/wallpapers/forest.webp  ',
      });

      expect(
        artwork,
        NetworkProductArtwork(
          Uri.parse('https://cdn.example.test/wallpapers/forest.webp'),
        ),
      );
    });

    test('rejects malformed HTTPS URLs', () {
      expect(
        resolveProductArtwork(const {'image_url': 'https://[unclosed'}),
        const DefaultProductArtwork(),
      );
    });

    test('rejects HTTPS URLs with an empty host or missing authority', () {
      expect(
        resolveProductArtwork(const {'image_url': 'https://'}),
        const DefaultProductArtwork(),
      );
      expect(
        resolveProductArtwork(const {'image_url': 'https:///wallpaper.webp'}),
        const DefaultProductArtwork(),
      );
    });

    test('rejects credential-bearing HTTPS URLs', () {
      expect(
        resolveProductArtwork(const {
          'image_url': 'https://user:pass@cdn.example.test/wallpaper.webp',
        }),
        const DefaultProductArtwork(),
      );
    });

    test('uses the built-in default for legacy and non-HTTPS URLs', () {
      expect(
        resolveProductArtwork(const {'image_name': 'legacy.png'}),
        const DefaultProductArtwork(),
      );
      expect(
        resolveProductArtwork(const {
          'image_url': 'http://cdn.example.test/legacy.png',
        }),
        const DefaultProductArtwork(),
      );
    });
  });
}
