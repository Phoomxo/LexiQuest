import 'dart:async';

import 'package:flutter/material.dart';

import '../../../navigation/app_routes.dart';
import '../application/voice_use_cases.dart';

/// Owns one opaque voice session only while the host page is current.
///
/// Screens supply the bootstrap-owned [VoiceUseCases] facade. The mixin never
/// creates or disposes that shared facade and a stale route can only release
/// its own session, so it cannot globally stop a replacement route.
mixin RouteVoiceSessionMixin<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver
    implements RouteAware {
  PageRoute<dynamic>? _observedRoute;
  VoiceUseCases? _sessionOwner;
  VoiceSession? _voiceSession;
  bool _routeCovered = false;
  bool _appForeground = true;
  int _routeGeneration = 0;

  VoiceUseCases? get routeVoiceUseCases;

  @override
  @mustCallSuper
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _appForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @protected
  VoiceSession? get routeVoiceSession {
    if (!_appForeground ||
        _routeCovered ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      return null;
    }
    _acquireForCurrentRoute();
    final session = _voiceSession;
    return session != null && session.isCurrent ? session : null;
  }

  @protected
  void refreshRouteVoiceSession() {
    if (ModalRoute.isCurrentOf(context) ?? true) _resume();
  }

  /// Hook for route-specific resources (for example recognition or a
  /// playlist) that must drain before the voice session is released.
  @protected
  FutureOr<void> onVoiceRouteCovered() {}

  /// Hook invoked after a fresh current-route voice session is acquired.
  @protected
  FutureOr<void> onVoiceRouteResumed() {}

  /// Hook for a screen-owned operation that must stop when the app leaves the
  /// foreground (for example a multi-item playlist run). Errors are consumed
  /// at the lifecycle boundary and cannot prevent session invalidation.
  @protected
  FutureOr<void> onVoiceAppBackgrounded() {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final pageRoute = route is PageRoute<dynamic> ? route : null;
    if (!identical(pageRoute, _observedRoute)) {
      final previous = _observedRoute;
      if (previous != null) appRouteObserver.unsubscribe(this);
      _observedRoute = pageRoute;
      if (pageRoute != null) appRouteObserver.subscribe(this, pageRoute);
    }
    if (route?.isCurrent ?? true) {
      _resume();
    } else {
      _cover();
    }
  }

  @override
  void didPush() => _resume();

  @override
  void didPopNext() => _resume();

  @override
  void didPushNext() => _cover();

  @override
  void didPop() => _cover();

  @override
  @mustCallSuper
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final wasForeground = _appForeground;
      _appForeground = true;
      if (!wasForeground && (ModalRoute.isCurrentOf(context) ?? true)) {
        // Route callbacks may cover and then resume this page while the app
        // is backgrounded. Actual current-route state is authoritative when
        // the app returns; [_resume] clears that stale cover generation.
        _resume();
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (!_appForeground) return;
      _appForeground = false;
      Future<void>.sync(onVoiceAppBackgrounded).ignore();
      _releaseVoiceSession().ignore();
    }
  }

  void _resume() {
    if (!_appForeground) return;
    _routeGeneration += 1;
    final wasCovered = _routeCovered;
    _routeCovered = false;
    if (wasCovered) {
      // A delayed cover hook still owns and will release the captured old
      // session. Detach it before acquiring so its completion can never clear
      // or release this resumed route's fresh session.
      _voiceSession = null;
      _sessionOwner = null;
    }
    _acquireForCurrentRoute();
    Future<void>.sync(onVoiceRouteResumed).ignore();
  }

  void _cover() {
    _routeCovered = true;
    final coverGeneration = ++_routeGeneration;
    final coveredSession = _voiceSession;
    _finishCover(
      coverGeneration: coverGeneration,
      coveredSession: coveredSession,
    ).ignore();
  }

  Future<void> _finishCover({
    required int coverGeneration,
    required VoiceSession? coveredSession,
  }) async {
    try {
      await Future<void>.sync(onVoiceRouteCovered);
    } finally {
      if (_routeGeneration == coverGeneration &&
          _routeCovered &&
          identical(_voiceSession, coveredSession)) {
        _voiceSession = null;
        _sessionOwner = null;
      }
      await coveredSession?.release();
    }
  }

  void _acquireForCurrentRoute() {
    if (!_appForeground || _routeCovered) {
      if (_voiceSession != null) _releaseVoiceSession().ignore();
      return;
    }
    final owner = routeVoiceUseCases;
    final existing = _voiceSession;
    if (owner == null) {
      if (existing != null) _releaseVoiceSession().ignore();
      return;
    }
    if (identical(owner, _sessionOwner) && existing?.isCurrent == true) return;
    if (existing != null) _releaseVoiceSession().ignore();
    _sessionOwner = owner;
    _voiceSession = owner.acquireSession();
  }

  Future<void> _releaseVoiceSession() async {
    final session = _voiceSession;
    _voiceSession = null;
    _sessionOwner = null;
    if (session != null) await session.release();
  }

  @override
  @mustCallSuper
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _observedRoute = null;
    _cover();
    super.dispose();
  }
}
