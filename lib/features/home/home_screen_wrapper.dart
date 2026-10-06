import 'package:flutter/material.dart';
import '../../core/config/feature_flags.dart';
import 'home_screen_redesign.dart';
import '../../screens/today_hub_screen.dart';

/// Wrapper that switches between old and new home screen based on feature flag
///
/// This allows gradual rollout of the redesigned UI without breaking existing functionality
class HomeScreenWrapper extends StatelessWidget {
  const HomeScreenWrapper({
    super.key,
    this.useCases,
    this.actions,
    this.features,
    this.assessmentAvailable,
    this.ownerIdentities,
    this.bindActions,
    this.onOpenPractice,
    this.manualPracticeAvailable = true,
    this.leadingContent,
  });

  // Pass-through parameters for TodayHubScreen
  final dynamic useCases;
  final dynamic actions;
  final dynamic features;
  final dynamic assessmentAvailable;
  final dynamic ownerIdentities;
  final dynamic bindActions;
  final dynamic onOpenPractice;
  final bool manualPracticeAvailable;
  final Widget? leadingContent;

  @override
  Widget build(BuildContext context) {
    if (FeatureFlags.useRedesignedUI) {
      // Use new redesigned home screen
      return const HomeScreenRedesign();
    }

    // Use original TodayHubScreen with all parameters
    return TodayHubScreen(
      useCases: useCases!,
      actions: actions!,
      features: features!,
      assessmentAvailable: assessmentAvailable!,
      ownerIdentities: ownerIdentities,
      bindActions: bindActions,
      onOpenPractice: onOpenPractice,
      manualPracticeAvailable: manualPracticeAvailable,
      leadingContent: leadingContent,
    );
  }
}
