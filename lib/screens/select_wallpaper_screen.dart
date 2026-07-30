import 'package:flutter/material.dart';

import '../features/rewards/application/reward_use_cases.dart';
import 'shop_page.dart';

class SelectWallpaperScreen extends StatelessWidget {
  const SelectWallpaperScreen({super.key, this.rewards});

  final RewardUseCases? rewards;

  @override
  Widget build(BuildContext context) {
    return ShopPage(rewards: rewards);
  }
}
