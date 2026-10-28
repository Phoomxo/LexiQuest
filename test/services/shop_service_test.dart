import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/shop_service.dart';

void main() {
  final service = ShopService();

  test('ShopService returns available card themes', () {
    final themes = service.getAvailableThemes();
    expect(themes.length, 3);
    expect(themes.first.isUnlocked, true);
  });

  test('canPurchase validates coin balance against item price', () {
    expect(service.canPurchase(200, 100), true);
    expect(service.canPurchase(50, 100), false);
  });
}
