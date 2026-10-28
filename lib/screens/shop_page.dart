import 'package:flutter/material.dart';

import '../features/rewards/application/reward_use_cases.dart';
import 'avatar_equipment_screen.dart';

class ShopPage extends StatelessWidget {
  const ShopPage({super.key, this.rewards});

  final RewardUseCases? rewards;

  @override
  Widget build(BuildContext context) {
    return AvatarEquipmentScreen(rewards: rewards);
  }
}
