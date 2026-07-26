import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../services/guest_session_service.dart';
import 'app_runtime_status.dart';

final class AppDependencies {
  const AppDependencies({
    required this.runtimeStatus,
    required this.config,
    required this.guestSessionService,
  });

  final AppRuntimeStatus runtimeStatus;
  final AppConfig? config;
  final GuestSessionService guestSessionService;

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
