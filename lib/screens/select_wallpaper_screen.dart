import 'package:flutter/material.dart';

import '../features/rewards/application/reward_use_cases.dart';
import 'owned_appearance_screen.dart';

class SelectWallpaperScreen extends StatelessWidget {
  const SelectWallpaperScreen({
    super.key,
    this.rewards,
    this.initialItemId,
    this.returnLabel = 'กลับไปที่การแสดงผล',
    this.onOpenShop,
    this.expectedOwnerId,
  });

  final RewardUseCases? rewards;
  final String? initialItemId;
  final String returnLabel;
  final Future<void> Function(BuildContext)? onOpenShop;
  final String? expectedOwnerId;

  @override
  Widget build(BuildContext context) {
    return OwnedAppearanceScreen(
      wallpaper: true,
      rewards: rewards,
      initialItemId: initialItemId,
      returnLabel: returnLabel,
      expectedOwnerId: expectedOwnerId,
      onOpenOther: onOpenShop == null
          ? null
          : (context, _) => onOpenShop!(context),
    );
  }
}
