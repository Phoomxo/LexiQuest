import 'package:flutter/material.dart';

class CardThemeItem {
  final String id;
  final String title;
  final int price;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isUnlocked;

  const CardThemeItem({
    required this.id,
    required this.title,
    required this.price,
    required this.primaryColor,
    required this.secondaryColor,
    this.isUnlocked = false,
  });

  CardThemeItem copyWith({bool? isUnlocked}) {
    return CardThemeItem(
      id: id,
      title: title,
      price: price,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      isUnlocked: isUnlocked ?? this.isUnlocked,
    );
  }
}
