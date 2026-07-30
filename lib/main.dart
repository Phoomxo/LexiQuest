import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final trigger = widget.dependencies.syncTrigger;
      if (trigger != null) {
        unawaited(trigger.request(SyncTriggerReason.appResume));
      }
    }
  }

  @override
  void didUpdateWidget(covariant MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dependencies, widget.dependencies)) {
      unawaited(oldWidget.dependencies.dispose());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.dependencies.dispose());
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
        initialRoute: _initialRoute(),
        onGenerateRoute: AppRouteFactory.onGenerateRoute,
      ),
    );
  }

  String _initialRoute() {
    final platformRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    return platformRoute == '/' ? AppRoute.login.path : platformRoute;
  }
}
