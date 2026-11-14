import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'config/app_appearance_preferences.dart';
import 'config/m3_theme.dart';
import 'features/account/domain/account_contracts.dart';
import 'features/motivation/domain/focus_models.dart';
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
  const MyApp({super.key, required this.dependencies, this.appearance});

  final AppDependencies dependencies;
  final AppAppearanceController? appearance;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  Stream<RewardAppearance>? _appearanceStream;
  final _streakRecoveries = Map<AppDependencies, Future<void>>.identity();
  final _focusLifecycle = Map<AppDependencies, Future<void>>.identity();
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
    final startupDependencies = widget.dependencies;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (identical(startupDependencies, widget.dependencies)) {
        unawaited(_recoverStreak(startupDependencies));
        _updateFocus(startupDependencies, foreground: true);
      }
      final trigger = widget.dependencies.syncTrigger;
      if (trigger != null) {
        unawaited(trigger.request(SyncTriggerReason.startup));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updateFocus(
      widget.dependencies,
      foreground: state == AppLifecycleState.resumed,
    );
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverStreak(widget.dependencies));
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
      _appearanceStream = widget.dependencies.rewards?.watchAppearance();
      unawaited(_disposeAfterRecovery(oldWidget.dependencies));
      unawaited(_recoverStreak(widget.dependencies));
      _updateFocus(
        widget.dependencies,
        foreground:
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
    }
  }

  Future<void> _recoverStreak(AppDependencies scope) {
    if (!mounted || !identical(scope, widget.dependencies)) {
      return Future<void>.value();
    }
    return _streakRecoveries.putIfAbsent(
      scope,
      () => _settleActiveOwner(scope).whenComplete(() {
        _streakRecoveries.remove(scope);
      }),
    );
  }

  Future<void> _settleActiveOwner(AppDependencies scope) async {
    final owners = scope.localOwners;
    final streak = scope.streak;
    if (owners == null || streak == null) {
      return;
    }
    try {
      final owner = await owners.getOrCreateActiveOwner();
      if (mounted && identical(scope, widget.dependencies)) {
        await streak.settle(expectedOwnerId: owner.id);
      }
    } on Object {
      // A later resume can recover the committed attendance.
    }
  }

  void _updateFocus(AppDependencies scope, {required bool foreground}) {
    final focus = scope.focus;
    final owners = scope.localOwners;
    if (focus == null || owners == null) return;
    final FocusSample? sample;
    try {
      sample = foreground ? null : focus.clock.sample();
    } on Object {
      return;
    }
    final earlier = _focusLifecycle[scope] ?? Future<void>.value();
    late final Future<void> next;
    next = earlier
        .then((_) async {
          if (!mounted || !identical(widget.dependencies, scope)) return;
          try {
            final owner = await owners.getOrCreateActiveOwner();
            if (!mounted || !identical(widget.dependencies, scope)) return;
            if (foreground) {
              await focus.recover(expectedOwnerId: owner.id);
            } else {
              await focus.background(expectedOwnerId: owner.id, sample: sample);
            }
          } on Object {
            // Opening the timer reconciles any incomplete checkpoint.
          }
        })
        .whenComplete(() {
          if (identical(_focusLifecycle[scope], next)) {
            _focusLifecycle.remove(scope);
          }
        });
    _focusLifecycle[scope] = next;
  }

  Future<void> _disposeAfterRecovery(AppDependencies scope) async {
    final recovery = _streakRecoveries[scope];
    if (recovery != null) {
      await recovery;
      if (mounted && identical(widget.dependencies, scope)) {
        return;
      }
    }
    await _focusLifecycle[scope];
    if (mounted && identical(widget.dependencies, scope)) return;
    await scope.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsAppAppearance) _appAppearance.dispose();
    unawaited(_disposeAfterRecovery(widget.dependencies));
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
              return MaterialApp(
                navigatorKey: _navigatorKey,
                debugShowCheckedModeBanner: false,
                title: 'LexiQuest - AI Vocab Learning',
                builder: (context, child) => DisplayFeatureSubScreen(
                  child: SizedBox.expand(
                    key: const ValueKey<String>('adaptive-app-surface'),
                    child: child,
                  ),
                ),
                theme: M3Theme.lightThemeFor(
                  themeId: equipped['theme'],
                  wallpaperId: equipped['wallpaper'],
                ),
                darkTheme: M3Theme.darkThemeFor(
                  themeId: equipped['theme'],
                  wallpaperId: equipped['wallpaper'],
                ),
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
