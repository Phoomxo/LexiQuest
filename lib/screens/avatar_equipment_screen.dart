import 'package:flutter/material.dart';

import '../features/rewards/application/reward_use_cases.dart';
import '../features/progress/presentation/progress_host_binding.dart';
import 'shop_page.dart';

class AvatarEquipmentScreen extends StatelessWidget {
  const AvatarEquipmentScreen({super.key, this.rewards, this.progressLoader});

  final RewardUseCases? rewards;
  final ProgressLoader? progressLoader;

  @override
  Widget build(BuildContext context) {
    return ShopPage(rewards: rewards, progressLoader: progressLoader);
  }
}
