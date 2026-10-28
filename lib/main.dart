import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'config/m3_theme.dart';
import 'navigation/account_link_coordinator.dart';
import 'navigation/app_route.dart';
import 'navigation/app_router.dart';
import 'runtime/app_bootstrap.dart';
import 'runtime/app_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppBootstrap.production().initialize();
  final appLinks = AppLinks();
  final linkCoordinator = AccountLinkCoordinator(
    appLinks: appLinks,
    navigate: (route, arguments) {
      AppRouter.navigatorKey.currentState?.pushNamed(
        route.path,
        arguments: arguments,
      );
    },
  );
  runApp(MyApp(dependencies: dependencies));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(linkCoordinator.start());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AppDependenciesScope(
      dependencies: dependencies,
      child: MaterialApp(
        navigatorKey: AppRouter.navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'LexiQuest - AI Vocab Learning',
        theme: M3Theme.lightTheme,
        darkTheme: M3Theme.darkTheme,
        themeMode: ThemeMode.system,
        initialRoute: AppRoute.sessionGate.path,
        onGenerateRoute: AppRouter(dependencies).generateRoute,
      ),
    );
  }
}
