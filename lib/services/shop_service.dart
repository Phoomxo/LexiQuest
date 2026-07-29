import 'package:flutter/material.dart';
import '../models/card_theme.dart';

class ShopService {
  List<CardThemeItem> getAvailableThemes() {
    return const [
      CardThemeItem(
        id: 'default_purple',
        title: 'Deep Purple Classic',
        price: 0,
        primaryColor: Colors.deepPurple,
        secondaryColor: Colors.indigo,
        isUnlocked: true,
      ),
      CardThemeItem(
        id: 'cyberpunk',
        title: 'Cyberpunk Neon',
        price: 100,
        primaryColor: Colors.cyan,
        secondaryColor: Colors.pink,
        isUnlocked: false,
      ),
      CardThemeItem(
        id: 'sakura',
        title: 'Sakura Blossom',
        price: 150,
        primaryColor: Colors.pinkAccent,
        secondaryColor: Colors.purpleAccent,
        isUnlocked: false,
      ),
    ];
  }

  bool canPurchase(int currentCoins, int price) {
    return currentCoins >= price;
  }
}
