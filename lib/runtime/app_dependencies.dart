import 'package:flutter/widgets.dart';

import '../account/account_gateway.dart';
import '../account/account_models.dart';
import '../account/account_profile_provisioner.dart';
import '../config/app_config.dart';
import '../config/remote_economy_policy.dart';
import '../device/device_capability_models.dart';
import '../progress/progress_repository.dart';
import '../progress/progress_sync_service.dart';
import '../progress/purchase_remote_writer.dart';
import '../services/guest_session_service.dart';
import 'app_build_info.dart';
import 'app_runtime_status.dart';
import 'learning_dependencies.dart';

final class AppDependencies {
  const AppDependencies({
    required this.runtimeStatus,
    required this.config,
    required this.accountGateway,
    required this.guestSessionService,
    required this.guestUpgradeHandoff,
    this.accountProfileProvisioning =
        const UnavailableAccountProfileProvisioner(),
    this.buildInfo = const AppBuildInfo.fromEnvironment(),
    this.remoteEconomyPolicy = const RemoteEconomyPolicy(),
    this.progressRepository,
    this.progressSyncService,
    this.purchaseRemoteWriter,
    this.learningDependencies,
    this.deviceCapabilitySnapshot,
  });

  final AppRuntimeStatus runtimeStatus;
  final AppConfig? config;
  final AccountGateway accountGateway;
  final GuestSessionService guestSessionService;
  final GuestUpgradeHandoff guestUpgradeHandoff;
  final AccountProfileProvisioning accountProfileProvisioning;
  final AppBuildInfo buildInfo;
  final RemoteEconomyPolicy remoteEconomyPolicy;
  final ProgressRepository? progressRepository;
  final ProgressSyncService? progressSyncService;
  final PurchaseRemoteWriter? purchaseRemoteWriter;
  final LearningDependencies? learningDependencies;
  final DeviceCapabilitySnapshot? deviceCapabilitySnapshot;

  @override
  String toString() => 'AppDependencies';
}

final class AppDependenciesScope extends InheritedWidget {
  const AppDependenciesScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  final AppDependencies dependencies;

  static AppDependencies? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppDependenciesScope>()
        ?.dependencies;
  }

  static AppDependencies of(BuildContext context) {
    final dependencies = maybeOf(context);
    assert(
      dependencies != null,
      'AppDependenciesScope was not found in the widget tree.',
    );
    return dependencies!;
  }

  @override
  bool updateShouldNotify(AppDependenciesScope oldWidget) {
    return !identical(dependencies, oldWidget.dependencies);
  }
}
