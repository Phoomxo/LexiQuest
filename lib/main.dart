import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'config/m3_theme.dart';
import 'runtime/app_bootstrap.dart';
import 'runtime/app_dependencies.dart';
import 'features/sync/application/sync_trigger.dart';
import 'features/sync/platform/background_sync_scheduler.dart';
import 'features/sync/platform/workmanager_sync_scheduler.dart';
import 'navigation/app_route_factory.dart';
import 'navigation/app_routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  final dependencies = await AppBootstrap.production().initialize();
  runApp(MyApp(dependencies: dependencies));
  final owners = dependencies.localOwners;
  if (owners != null) {
    final scheduler = WorkmanagerSyncScheduler(
      client: const PluginWorkmanagerClient(),
      isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      cloudSyncEnabled: const bool.fromEnvironment(
        'LEXIQUEST_CLOUD_SYNC_ENABLED',
        defaultValue: true,
      ),
    );
    unawaited(
      scheduleBackgroundSyncSafely(scheduler: scheduler, owners: owners),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final trigger = widget.dependencies.syncTrigger;
      if (trigger != null) {
        trigger.requestDetached(SyncTriggerReason.startup);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final trigger = widget.dependencies.syncTrigger;
      if (trigger != null) {
        trigger.requestDetached(SyncTriggerReason.appResume);
      }
    }
  }

  @override
  void didUpdateWidget(covariant MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dependencies, widget.dependencies)) {
      oldWidget.dependencies.dispose().ignore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.dependencies.dispose().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDependenciesScope(
      dependencies: widget.dependencies,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LexiQuest - AI Vocab Learning',
        theme: M3Theme.lightTheme,
        darkTheme: M3Theme.darkTheme,
        themeMode: ThemeMode.system,
        navigatorObservers: <NavigatorObserver>[appRouteObserver],
        initialRoute: widget.dependencies.initialRoute.path,
        onGenerateInitialRoutes: (platformRoute) {
          final routeName = AppRouteFactory.supportsInitialRoute(platformRoute)
              ? platformRoute
              : widget.dependencies.initialRoute.path;
          return <Route<dynamic>>[
            AppRouteFactory.onGenerateRoute(RouteSettings(name: routeName)),
          ];
        },
        onGenerateRoute: AppRouteFactory.onGenerateRoute,
      ),
    );
  }
}
