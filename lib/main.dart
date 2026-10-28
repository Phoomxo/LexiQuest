import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'config/app_appearance_preferences.dart';
import 'config/m3_theme.dart';
import 'features/account/domain/account_contracts.dart';
import 'runtime/app_bootstrap.dart';
import 'runtime/app_dependencies.dart';
import 'runtime/app_runtime_status.dart';
import 'features/rewards/domain/reward_models.dart';
import 'features/sync/application/sync_trigger.dart';
import 'features/sync/platform/background_sync_scheduler.dart';
import 'features/sync/platform/workmanager_sync_scheduler.dart';
import 'navigation/app_route_factory.dart';
import 'navigation/app_routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppBootstrap.production().initialize();
  final appearance = await loadAppAppearanceController();
  runApp(MyApp(dependencies: dependencies, appearance: appearance));
  final owners = dependencies.localOwners;
  if (owners != null && dependencies.syncEngine != null) {
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
  const MyApp({super.key, required this.dependencies, this.appearance});

  final AppDependencies dependencies;
  final AppAppearanceController? appearance;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  Stream<RewardAppearance>? _appearanceStream;
  late final AppAppearanceController _appAppearance;
  late final bool _ownsAppAppearance;
  late final String _platformRoute =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  late final RouteSettings _startupRoute = _initialRoute();

  @override
  void initState() {
    super.initState();
    _ownsAppAppearance = widget.appearance == null;
    _appAppearance = widget.appearance ?? AppAppearanceController.system();
    _appearanceStream = widget.dependencies.rewards?.watchAppearance();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final trigger = widget.dependencies.syncTrigger;
      if (trigger != null) {
        unawaited(trigger.request(SyncTriggerReason.startup));
      }
    });
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
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dependencies, widget.dependencies)) {
      _appearanceStream = widget.dependencies.rewards?.watchAppearance();
      unawaited(oldWidget.dependencies.dispose());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsAppAppearance) _appAppearance.dispose();
    unawaited(widget.dependencies.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppAppearanceScope(
      controller: _appAppearance,
      child: AnimatedBuilder(
        animation: _appAppearance,
        builder: (context, _) => AppDependenciesScope(
          dependencies: widget.dependencies,
          child: StreamBuilder<RewardAppearance>(
            stream: _appearanceStream,
            initialData: const RewardAppearance.empty(),
            builder: (context, snapshot) {
              final appearance =
                  snapshot.connectionState == ConnectionState.active &&
                      !snapshot.hasError
                  ? snapshot.data ?? const RewardAppearance.empty()
                  : const RewardAppearance.empty();
              final equipped = appearance.equippedBySlot;
              final system = WidgetsBinding
                  .instance
                  .platformDispatcher
                  .accessibilityFeatures;
              final reducedMotion =
                  _appAppearance.reducedMotion ||
                  (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
                  system.disableAnimations ||
                  system.reduceMotion;
              return MaterialApp(
                navigatorKey: _navigatorKey,
                debugShowCheckedModeBanner: false,
                title: 'LexiQuest - AI Vocab Learning',
                builder: (context, child) {
                  final media = MediaQuery.of(context);
                  return MediaQuery(
                    data: media.copyWith(
                      disableAnimations:
                          media.disableAnimations || reducedMotion,
                    ),
                    child: DisplayFeatureSubScreen(
                      child: SizedBox.expand(
                        key: const ValueKey<String>('adaptive-app-surface'),
                        child: child,
                      ),
                    ),
                  );
                },
                theme: _motionTheme(
                  M3Theme.lightThemeFor(
                    themeId: equipped['theme'],
                    wallpaperId: equipped['wallpaper'],
                  ),
                  reducedMotion,
                ),
                darkTheme: _motionTheme(
                  M3Theme.darkThemeFor(
                    themeId: equipped['theme'],
                    wallpaperId: equipped['wallpaper'],
                  ),
                  reducedMotion,
                ),
                themeAnimationDuration: reducedMotion
                    ? Duration.zero
                    : kThemeAnimationDuration,
                themeMode: _appAppearance.themeMode,
                initialRoute: _startupRoute.name,
                onGenerateInitialRoutes: _platformRoute == '/'
                    ? (_) => [
                        if (_startupRoute.arguments is EmailVerificationArgs)
                          AppRouteFactory.onGenerateRoute(
                            RouteSettings(name: AppRoute.login.path),
                          ),
                        AppRouteFactory.onGenerateRoute(_startupRoute),
                      ]
                    : null,
                onGenerateRoute: AppRouteFactory.onGenerateRoute,
              );
            },
          ),
        ),
      ),
    );
  }

  RouteSettings _initialRoute() {
    if (_platformRoute != '/') return RouteSettings(name: _platformRoute);
    if (widget.dependencies.runtimeStatus.firebase ==
        RuntimeAvailability.ready) {
      try {
        final session = widget.dependencies.account?.currentSession;
        if (session != null) {
          if (session.isAnonymous || session.emailVerified) {
            return RouteSettings(name: AppRoute.home.path);
          }
          return RouteSettings(
            name: AppRoute.emailVerification.path,
            arguments: EmailVerificationArgs(session.email ?? ''),
          );
        }
      } catch (_) {
        // A failed session read must leave the local Guest entry available.
      }
    }
    return RouteSettings(name: AppRoute.login.path);
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    if (EmailAction.parse(routeInformation.uri) == null) return false;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return false;
    unawaited(navigator.pushNamed<void>(routeInformation.uri.toString()));
    return true;
  }
}

ThemeData _motionTheme(ThemeData theme, bool reducedMotion) {
  if (!reducedMotion) return theme;
  const defaults = PageTransitionsTheme();
  return theme.copyWith(
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: _ReducedMotionPageTransitionsBuilder(
            theme.pageTransitionsTheme.builders[platform] ??
                defaults.builders[platform] ??
                const ZoomPageTransitionsBuilder(),
          ),
      },
    ),
  );
}

final class _ReducedMotionPageTransitionsBuilder
    extends PageTransitionsBuilder {
  const _ReducedMotionPageTransitionsBuilder(this._delegate);

  final PageTransitionsBuilder _delegate;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _delegate.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _delegate.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    child,
  );

  @override
  bool operator ==(Object other) =>
      other is _ReducedMotionPageTransitionsBuilder &&
      other._delegate == _delegate;

  @override
  int get hashCode => _delegate.hashCode;
}
