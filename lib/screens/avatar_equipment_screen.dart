import 'package:flutter/material.dart';

import '../features/rewards/application/reward_use_cases.dart';
import '../navigation/app_routes.dart';
import 'owned_appearance_screen.dart';
import 'select_wallpaper_screen.dart';

class AvatarEquipmentScreen extends StatelessWidget {
  const AvatarEquipmentScreen({
    super.key,
    this.rewards,
    this.initialItemId,
    this.returnLabel = 'กลับไปดูของสะสม',
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
      rewards: rewards,
      initialItemId: initialItemId,
      returnLabel: returnLabel,
      expectedOwnerId: expectedOwnerId,
      onOpenOther: (context, ownerId) => AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'appearance/wallpaper',
          builder: (_) => SelectWallpaperScreen(
            rewards: rewards,
            returnLabel: 'กลับไปแต่งตัวละคร',
            onOpenShop: onOpenShop,
            expectedOwnerId: ownerId,
          ),
        ),
      ),
    );
  }
}
