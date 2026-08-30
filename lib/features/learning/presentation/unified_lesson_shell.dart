import 'dart:async';

import 'package:flutter/material.dart';

import '../../accessibility/domain/accessibility_policy.dart';
import '../../accessibility/presentation/accessibility_scope.dart';
import '../../companion/presentation/contextual_companion_widget.dart';
import '../application/current_activity_evidence.dart';
import '../application/unified_lesson_controller.dart';
import '../application/learning_use_cases.dart';
import '../application/contrastive_feedback_use_cases.dart';
import '../domain/learning_models.dart';
import '../domain/answer_feedback.dart';
import '../domain/lesson_mode.dart';
import '../domain/lesson_session_state.dart';
import '../domain/session_configuration.dart';
import '../domain/hint_policy.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../../runtime/app_dependencies.dart';
import '../../../runtime/production_feature_gate.dart';
import '../../../runtime/registries/feature_registry.dart';
import '../../time_tracking/presentation/focus_timer_widget.dart';
import 'answer_feedback_panel.dart';
import 'hint_panel.dart';
import 'session_configuration_sheet.dart';

typedef LessonUtcNow = DateTime Function();
typedef LessonLifecycleStateReader = AppLifecycleState? Function();
typedef RecoveredLessonCloseReader = PendingLearningSessionClose? Function();

/// Local-only child state that must be purged whenever a lesson crosses a
/// privacy, terminal, or route-retirement boundary.
abstract interface class EphemeralLessonState {
  void clearEphemeralState();
}

final class LessonEphemeralStateRegistry {
  final Set<EphemeralLessonState> _states = <EphemeralLessonState>{};

  void register(EphemeralLessonState state) => _states.add(state);
  void unregister(EphemeralLessonState state) => _states.remove(state);
  void clear() {
    for (final state in _states.toList(growable: false)) {
      state.clearEphemeralState();
    }
  }
}

final class UnifiedLessonSessionLifecycle {
  const UnifiedLessonSessionLifecycle._(
    this._controller,
    this._nowUtc,
    this._routeLifecycle,
    this._ephemeralStates,
  );

  final UnifiedLessonController _controller;
  final LessonUtcNow _nowUtc;
  final UnifiedLessonRouteLifecycle? _routeLifecycle;
  final LessonEphemeralStateRegistry _ephemeralStates;

  bool get acceptsOperations =>
      _controller.configurationAcceptsOperations &&
      (_routeLifecycle?.acceptsOperations ?? true);
  bool get sessionCompletionRetryRequired =>
      _controller.sessionCompletionRetryRequired;
  SessionConfiguration? get configuration => _controller.sessionConfiguration;

  void registerEphemeralState(EphemeralLessonState state) =>
      _ephemeralStates.register(state);

  void unregisterEphemeralState(EphemeralLessonState state) =>
      _ephemeralStates.unregister(state);

  HintUsageSnapshot snapshotHintUsage() =>
      _controller.snapshotHintUsageForAcceptedEvidence();

  void resetHintsAfterCommittedEvidence() =>
      _controller.resetHintsAfterAcceptedEvidence();

  Future<T> runAcceptedOperation<T>(Future<T> Function() operation) {
    final routeLifecycle = _routeLifecycle;
    return routeLifecycle == null
        ? Future<T>.sync(operation)
        : routeLifecycle.runAcceptedOperation(operation);
  }

  Future<AnswerRecordResult> recordCapturedEvidence(
    PendingCurrentActivityEvidence pending, {
    required AnswerFeedbackContext feedbackContext,
  }) => runAcceptedOperation(
    () => _controller.recordCapturedEvidence(
      pending,
      feedbackContext: feedbackContext,
    ),
  );

  Future<void> start({
    required String sessionId,
    required DateTime startedAtUtc,
    required int itemCount,
    String? ownerId,
  }) {
    final command = LessonStartCommand(
      sessionId: sessionId,
      mode: _controller.state.mode,
      itemCount: itemCount,
      startedAtUtc: startedAtUtc,
      configuration: _controller.sessionConfiguration,
      ownerId: ownerId,
    );
    return _routeLifecycle?.start(command) ?? _controller.start(command);
  }

  Future<QuizSession> initializeSession(
    Future<QuizSession> load, {
    RecoveredLessonCloseReader? recoveredClose,
  }) {
    final routeLifecycle = _routeLifecycle;
    if (routeLifecycle != null) {
      return routeLifecycle.initializeSession(
        load,
        recoveredClose: recoveredClose,
      );
    }
    return _initializeWithoutRouteOwner(load);
  }

  Future<QuizSession> _initializeWithoutRouteOwner(
    Future<QuizSession> load,
  ) async {
    final session = await load;
    final startedAtUtc = session.startedAtUtc;
    if (!session.isEmpty && startedAtUtc != null) {
      await start(
        sessionId: session.id,
        startedAtUtc: startedAtUtc,
        itemCount: session.questions.length,
        ownerId: session.ownerId,
      );
    }
    return session;
  }

  Future<LearningSessionSummary> complete(PendingLearningSessionClose close) {
    _ephemeralStates.clear();
    return _routeLifecycle?.complete(close) ??
        _controller.completeCapturedSession(close, _nowUtc());
  }

  Future<LearningSessionSummary> completeRecovery(
    PendingLearningSessionClose close,
  ) =>
      _routeLifecycle?.completeRecovery(close) ??
      _controller.completeCapturedSession(close, _nowUtc());

  void ownRecoveryClose(
    PendingLearningSessionClose close,
    Future<void> Function() ensureDurable,
  ) {
    final route = _routeLifecycle;
    if (route != null) {
      route.ownRecoveryClose(close, ensureDurable);
      return;
    }
    if (close.sessionId != _controller.state.sessionId) {
      throw StateError('Captured close does not belong to this lesson.');
    }
  }

  Future<void> abandon() {
    _ephemeralStates.clear();
    return _routeLifecycle?.retire() ?? _controller.abandon(_nowUtc());
  }

  Future<T> runAdmittedOperation<T>(Future<T> Function() operation) {
    if (!acceptsOperations) {
      return Future<T>.error(
        _controller.configurationLimitReached
            ? const SessionConfigurationLimitReached()
            : StateError('The lesson route is no longer accepting actions.'),
      );
    }
    Future<T> admitted() async {
      await _controller.recordActiveLearningInteraction(_nowUtc());
      return operation();
    }

    return _routeLifecycle?.runAcceptedOperation(admitted) ?? admitted();
  }

  Future<T> runRecoveryOperation<T>(Future<T> Function() operation) =>
      _routeLifecycle?.runRecoveryOperation(operation) ??
      Future<T>.sync(operation);

  void recordInteraction() {
    if (!acceptsOperations) return;
    _controller.noteActiveLearningInteraction(_nowUtc());
  }
}

final class UnifiedLessonSessionLifecycleScope extends InheritedWidget {
  const UnifiedLessonSessionLifecycleScope({
    super.key,
    required this.ephemeralStates,
    this.lifecycle,
    required super.child,
  });

  final LessonEphemeralStateRegistry ephemeralStates;
  final UnifiedLessonSessionLifecycle? lifecycle;

  static UnifiedLessonSessionLifecycleScope? maybeScopeOf(
    BuildContext context,
  ) => context
      .dependOnInheritedWidgetOfExactType<UnifiedLessonSessionLifecycleScope>();

  static UnifiedLessonSessionLifecycle? maybeOf(BuildContext context) =>
      maybeScopeOf(context)?.lifecycle;

  void registerEphemeralState(EphemeralLessonState state) =>
      ephemeralStates.register(state);

  void unregisterEphemeralState(EphemeralLessonState state) =>
      ephemeralStates.unregister(state);

  @override
  bool updateShouldNotify(UnifiedLessonSessionLifecycleScope oldWidget) =>
      !identical(lifecycle, oldWidget.lifecycle) ||
      !identical(ephemeralStates, oldWidget.ephemeralStates);
}

/// One route-owned arbiter for initialization, accepted terminal work, and
/// runtime retirement. Closing acceptance is synchronous; durable mutation is
/// serialized behind work that crossed the boundary first.
final class UnifiedLessonRouteLifecycle {
  static final Object _acceptedLeaseZoneKey = Object();

  UnifiedLessonRouteLifecycle(this._controller, this._learning, this._nowUtc);

  final UnifiedLessonController _controller;
  final LearningUseCases? _learning;
  final LessonUtcNow _nowUtc;
  final Map<String, Future<void>> _unattachedCompensations =
      <String, Future<void>>{};

  bool _accepting = true;
  Future<QuizSession>? _initialization;
  String? _loadedSessionId;
  String? _loadedOwnerId;
  Future<void>? _startInFlight;
  Future<LearningSessionSummary>? _completionInFlight;
  PendingLearningSessionClose? _acceptedClose;
  LessonTerminalCutoff? _acceptedCloseCutoff;
  Future<void>? _acceptedCloseConfigurationClose;
  Future<void> Function()? _acceptedClosePreparation;
  LessonTerminalCutoff? _retirementCutoff;
  Future<void>? _terminal;
  final Set<Future<void>> _acceptedOperations = <Future<void>>{};
  final LessonEphemeralStateRegistry _ephemeralStates =
      LessonEphemeralStateRegistry();

  LessonEphemeralStateRegistry get _ephemeralStateRegistry => _ephemeralStates;

  bool get acceptsOperations =>
      _accepting && _controller.configurationAcceptsOperations;

  Future<T> runAcceptedOperation<T>(Future<T> Function() operation) {
    if (!acceptsOperations) {
      return Future<T>.error(
        _controller.configurationLimitReached
            ? const SessionConfigurationLimitReached()
            : StateError('The lesson route is no longer accepting operations.'),
      );
    }
    return _trackOperation(operation);
  }

  Future<T> runRecoveryOperation<T>(Future<T> Function() operation) =>
      _accepting || _insideAcceptedLease
      ? _trackOperation(operation)
      : Future<T>.error(
          StateError('The lesson route is no longer accepting recovery.'),
        );

  bool get _insideAcceptedLease =>
      switch (Zone.current[_acceptedLeaseZoneKey]) {
        _UnifiedLessonOperationLease lease =>
          identical(lease.owner, this) && lease.active,
        _ => false,
      };

  Future<T> _trackOperation<T>(Future<T> Function() operation) {
    late final Future<T> accepted;
    final lease = _UnifiedLessonOperationLease(this);
    try {
      accepted = runZoned<Future<T>>(
        () => Future<T>.sync(operation),
        zoneValues: <Object?, Object?>{_acceptedLeaseZoneKey: lease},
      );
    } catch (error, stackTrace) {
      return Future<T>.error(error, stackTrace);
    }
    final settled = accepted.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _acceptedOperations.add(settled);
    unawaited(
      settled.whenComplete(() {
        lease.active = false;
        _acceptedOperations.remove(settled);
      }),
    );
    return accepted;
  }

  Future<QuizSession> initializeSession(
    Future<QuizSession> load, {
    RecoveredLessonCloseReader? recoveredClose,
    String? ownerId,
  }) {
    final existing = _initialization;
    if (existing != null) return existing;
    final initialization = _initializeSession(
      load,
      recoveredClose: recoveredClose,
      ownerId: ownerId,
    );
    _initialization = initialization;
    return initialization;
  }

  Future<QuizSession> _initializeSession(
    Future<QuizSession> load, {
    required RecoveredLessonCloseReader? recoveredClose,
    required String? ownerId,
  }) async {
    final loaded = await load;
    final session = loaded;
    final startedAtUtc = session.startedAtUtc;
    if (session.isEmpty) return session;
    final sessionOwnerId = session.ownerId;
    if (ownerId != null &&
        sessionOwnerId != null &&
        ownerId != sessionOwnerId) {
      await _compensateUnattached(session.id, sessionOwnerId);
      throw StateError('Loaded lesson session owner identity changed.');
    }
    final pinnedOwnerId = ownerId ?? sessionOwnerId;
    _loadedSessionId = session.id;
    _loadedOwnerId = pinnedOwnerId;
    final restoredClose = recoveredClose?.call();
    if (restoredClose != null) {
      _reserveLoadedRecoveryClose(restoredClose, session.id);
    }
    if (session.sessionConfiguration != _controller.sessionConfiguration) {
      if (restoredClose == null) await _compensateUnattached(session.id);
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.tampered,
        'loaded session is not bound to the shell configuration',
      );
    }
    if (startedAtUtc == null) {
      if (restoredClose == null) await _compensateUnattached(session.id);
      throw StateError('A durable lesson session has no start occurrence.');
    }
    final command = LessonStartCommand(
      sessionId: session.id,
      mode: _controller.state.mode,
      itemCount: session.questions.length,
      startedAtUtc: startedAtUtc,
      configuration: _controller.sessionConfiguration,
      ownerId: pinnedOwnerId,
    );
    try {
      if (restoredClose == null) {
        await start(command);
      } else {
        final operation = _startController(command);
        _activateReservedClose(restoredClose);
        await operation;
      }
    } catch (_) {
      if (_controller.state.sessionId != session.id &&
          _acceptedClose?.sessionId != session.id) {
        await _compensateUnattached(session.id);
      }
      rethrow;
    }
    return session;
  }

  Future<void> start(LessonStartCommand command) {
    if (!_accepting) return _compensateUnattached(command.sessionId);
    return _startController(command);
  }

  Future<void> _startController(LessonStartCommand command) {
    final operation = _controller.start(command);
    _startInFlight = operation;
    unawaited(
      operation.then<void>(
        (_) => _clearStart(operation),
        onError: (Object _, StackTrace _) => _clearStart(operation),
      ),
    );
    return operation;
  }

  void _clearStart(Future<void> operation) {
    if (identical(_startInFlight, operation)) _startInFlight = null;
  }

  Future<LearningSessionSummary> complete(PendingLearningSessionClose close) {
    if (!_accepting) {
      return Future<LearningSessionSummary>.error(
        StateError('The lesson route is no longer accepting operations.'),
      );
    }
    return _complete(close, recovery: false);
  }

  Future<LearningSessionSummary> completeRecovery(
    PendingLearningSessionClose close,
  ) {
    if (!_accepting &&
        !_insideAcceptedLease &&
        !identical(_acceptedClose, close)) {
      return Future<LearningSessionSummary>.error(
        StateError('The lesson route is no longer accepting recovery.'),
      );
    }
    return _complete(close, recovery: true);
  }

  void ownRecoveryClose(
    PendingLearningSessionClose close, [
    Future<void> Function()? ensureDurable,
  ]) {
    if (!_accepting &&
        !_insideAcceptedLease &&
        !identical(_acceptedClose, close)) {
      throw StateError('The lesson route is no longer accepting recovery.');
    }
    _ownClose(close, ensureDurable);
  }

  void _ownClose(
    PendingLearningSessionClose close, [
    Future<void> Function()? ensureDurable,
  ]) {
    if (close.sessionId != _controller.state.sessionId) {
      throw StateError('Captured close does not belong to this lesson.');
    }
    _reserveLoadedRecoveryClose(close, close.sessionId);
    _activateReservedClose(close, ensureDurable);
  }

  void _reserveLoadedRecoveryClose(
    PendingLearningSessionClose close,
    String loadedSessionId,
  ) {
    if (close.sessionId != loadedSessionId) {
      throw StateError('Recovered close does not belong to the loaded lesson.');
    }
    final acceptedClose = _acceptedClose;
    if (acceptedClose != null && !identical(acceptedClose, close)) {
      throw StateError('A different terminal close is already accepted.');
    }
    _acceptedClose = close;
  }

  void _activateReservedClose(
    PendingLearningSessionClose close, [
    Future<void> Function()? ensureDurable,
  ]) {
    if (!identical(_acceptedClose, close)) {
      throw StateError('Recovered close identity was not reserved.');
    }
    _acceptedClosePreparation ??= ensureDurable;
    final cutoff = _acceptedCloseCutoff ??=
        _retirementCutoff ?? _controller.captureTerminalCutoff(_nowUtc());
    final configurationClose = _acceptedCloseConfigurationClose ??= _controller
        .closeConfigurationEffortAtCutoff(cutoff);
    unawaited(
      configurationClose.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
  }

  Future<LearningSessionSummary> _complete(
    PendingLearningSessionClose close, {
    required bool recovery,
  }) {
    if (!recovery && !_accepting) {
      return Future<LearningSessionSummary>.error(
        StateError('The lesson route is no longer accepting operations.'),
      );
    }
    try {
      _ownClose(close);
    } catch (error, stackTrace) {
      return Future<LearningSessionSummary>.error(error, stackTrace);
    }
    final cutoff = _acceptedCloseCutoff!;
    final operation = _acceptedCloseConfigurationClose!.then(
      (_) => _controller.completeCapturedSessionAtCutoff(close, cutoff),
    );
    _completionInFlight = operation;
    unawaited(
      operation.then<void>(
        (_) => _clearCompletion(operation),
        onError: (Object _, StackTrace _) => _clearCompletion(operation),
      ),
    );
    return operation;
  }

  void _clearCompletion(Future<LearningSessionSummary> operation) {
    if (identical(_completionInFlight, operation)) {
      _completionInFlight = null;
    }
  }

  Future<void> retire() {
    _accepting = false;
    _ephemeralStates.clear();
    final existing = _terminal;
    if (existing != null) return existing;
    final cutoff = _retirementCutoff ??= _controller.captureTerminalCutoff(
      _nowUtc(),
    );
    final configurationClose = _controller.closeConfigurationEffortAtCutoff(
      cutoff,
    );
    final timeClose = _controller.closeTimeAtCutoff(cutoff);
    return _terminal ??= _retire(cutoff, configurationClose, timeClose);
  }

  Future<void> _retire(
    LessonTerminalCutoff cutoff,
    Future<void> configurationClose,
    Future<void> timeClose,
  ) async {
    final settledTimeClose = timeClose.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      await _initialization;
    } catch (_) {
      // Initialization either never created a session or compensated the
      // returned identity before surfacing its original failure.
    }
    final loadedSessionId = _loadedSessionId;
    if (loadedSessionId != null &&
        _controller.state.sessionId != loadedSessionId &&
        _acceptedClose?.sessionId != loadedSessionId) {
      await _compensateUnattached(loadedSessionId);
    }
    try {
      await _startInFlight;
    } catch (_) {
      // A failed attach is compensated by initialization before this point.
    }
    while (_acceptedOperations.isNotEmpty) {
      await Future.wait<void>(_acceptedOperations.toList(growable: false));
    }
    await _acceptedClosePreparation?.call();
    await _acceptedCloseConfigurationClose;
    await configurationClose;
    await settledTimeClose;
    final completion = _completionInFlight;
    if (completion != null) {
      try {
        await completion;
      } catch (_) {
        // The exact accepted close gets one bounded reconciliation below.
      }
    }
    final status = _controller.state.status;
    if (status == LessonSessionStatus.completed ||
        status == LessonSessionStatus.abandoned) {
      return;
    }
    final close = _acceptedClose;
    if (close != null) {
      await _controller.completeCapturedSessionAtCutoff(
        close,
        _acceptedCloseCutoff ?? cutoff,
      );
      return;
    }
    await _controller.abandonAtCutoff(cutoff);
  }

  Future<void> _compensateUnattached(String sessionId, [String? ownerId]) {
    final existing = _unattachedCompensations[sessionId];
    if (existing != null) return existing;
    final learning = _learning;
    if (learning == null) {
      return Future<void>.error(
        StateError('Route session compensation authority is unavailable.'),
      );
    }
    final operation = learning.abandonSession(
      ownerId: ownerId ?? _loadedOwnerId,
      sessionId: sessionId,
      abandonedAtUtc: _nowUtc(),
    );
    _unattachedCompensations[sessionId] = operation;
    return operation;
  }
}

final class _UnifiedLessonOperationLease {
  _UnifiedLessonOperationLease(this.owner);

  final UnifiedLessonRouteLifecycle owner;
  bool active = true;
}

/// One preflighted, route-owned Unified Lesson destination. The lease takes
/// ownership of its controller before any durable session is created, binds
/// exactly one returned session, and retires through canonical lifecycle
/// authority when navigation fails, races, or completes.
final class UnifiedLessonShellLease {
  factory UnifiedLessonShellLease({
    required UnifiedLessonController controller,
    required LearningUseCases learning,
    required LessonUtcNow nowUtc,
    required WidgetBuilder builder,
    ContrastiveFeedbackUseCases? contrastiveFeedback,
  }) {
    if (!controller.usesLearningAuthority(learning) ||
        controller.state.status != LessonSessionStatus.planned) {
      controller.dispose();
      throw StateError(
        'Unified Lesson destination must own one planned canonical controller.',
      );
    }
    return UnifiedLessonShellLease._(
      controller: controller,
      learning: learning,
      nowUtc: nowUtc,
      builder: builder,
      contrastiveFeedback: contrastiveFeedback,
    );
  }

  UnifiedLessonShellLease._({
    required this.controller,
    required LearningUseCases learning,
    required this.nowUtc,
    required this.builder,
    required this.contrastiveFeedback,
  }) : _learning = learning,
       _routeLifecycle = UnifiedLessonRouteLifecycle(
         controller,
         learning,
         nowUtc,
       );

  final UnifiedLessonController controller;
  final LearningUseCases _learning;
  final LessonUtcNow nowUtc;
  final WidgetBuilder builder;
  final ContrastiveFeedbackUseCases? contrastiveFeedback;
  final UnifiedLessonRouteLifecycle _routeLifecycle;

  Future<void>? _attachment;
  Future<void>? _retirement;
  String? _sessionId;
  bool _attached = false;
  bool _controllerDisposed = false;

  bool usesLearningAuthority(Object authorityIdentity) =>
      identical(_learning, authorityIdentity);

  Future<void> attach(
    QuizSession session, {
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> expectedContent,
  }) {
    if (ownerId.isEmpty || ownerId != ownerId.trim()) {
      return Future<void>.error(
        ArgumentError.value(ownerId, 'ownerId', 'must be canonical'),
      );
    }
    if (_retirement != null) {
      return _rejectAndCompensate(
        session: session,
        ownerId: ownerId,
        message: 'Unified Lesson destination is already retiring.',
      );
    }
    final existing = _attachment;
    if (existing != null) {
      if (_sessionId != session.id) {
        return _rejectAndCompensate(
          session: session,
          ownerId: ownerId,
          message: 'Unified Lesson destination already owns another session.',
        );
      }
      return existing;
    }
    _sessionId = session.id;
    return _attachment = _attach(
      session,
      ownerId: ownerId,
      expectedContent: expectedContent,
    );
  }

  Future<void> _rejectAndCompensate({
    required QuizSession session,
    required String ownerId,
    required String message,
  }) async {
    await _routeLifecycle._compensateUnattached(session.id, ownerId);
    throw StateError(message);
  }

  Future<void> _attach(
    QuizSession session, {
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> expectedContent,
  }) async {
    final attached = await _routeLifecycle.initializeSession(
      Future<QuizSession>.value(session),
      ownerId: ownerId,
    );
    final state = controller.state;
    if (!identical(attached, session) ||
        session.isEmpty ||
        session.ownerId != ownerId ||
        session.startedAtUtc == null ||
        controller.sessionConfiguration != session.sessionConfiguration ||
        state.status != LessonSessionStatus.active ||
        state.sessionId != session.id ||
        state.startedAtUtc != session.startedAtUtc ||
        state.itemCount != session.questions.length ||
        !_matchesReviewedContent(session, expectedContent)) {
      throw StateError(
        'Unified Lesson destination did not attach the exact durable session.',
      );
    }
    _attached = true;
  }

  bool _matchesReviewedContent(
    QuizSession session,
    List<ReviewedLexicalContentSnapshot> expected,
  ) {
    if (session.questions.length != expected.length) return false;
    for (var index = 0; index < expected.length; index += 1) {
      final snapshot = expected[index];
      final word = session.questions[index].word;
      if (snapshot.identity.id != word.id ||
          snapshot.identity.revision != word.contentRevision ||
          snapshot.categoryId != word.categoryId ||
          snapshot.spelling != word.spelling ||
          snapshot.normalizedSpelling != word.normalizedSpelling ||
          snapshot.meaning != word.meaning ||
          snapshot.normalizedMeaning != word.normalizedMeaning ||
          snapshot.partOfSpeech != word.partOfSpeech ||
          snapshot.cefrLevel != word.cefrLevel ||
          snapshot.coreChecksumSha256 != word.contentChecksumSha256) {
        return false;
      }
    }
    return true;
  }

  Widget get shell {
    if (!_attached || _retirement != null) {
      throw StateError('Unified Lesson destination is not attached.');
    }
    return UnifiedLessonShell(
      controller: controller,
      nowUtc: nowUtc,
      routeLifecycle: _routeLifecycle,
      configuration: controller.sessionConfiguration,
      contrastiveFeedback: contrastiveFeedback,
      builder: builder,
    );
  }

  Future<void> retire() => _retirement ??= _retire();

  Future<void> _retire() async {
    try {
      await _routeLifecycle.retire();
    } finally {
      if (!_controllerDisposed) {
        _controllerDisposed = true;
        controller.dispose();
      }
    }
  }
}

final class UnifiedLessonModeHost extends StatefulWidget {
  const UnifiedLessonModeHost({
    super.key,
    required this.adapter,
    required this.createController,
    required this.builder,
    this.feature,
    this.featureRegistry,
    this.learning,
    this.nowUtc,
    this.configuration,
    this.revalidateConfiguration,
    this.contrastiveFeedback,
  });

  final LessonModeAdapter adapter;
  final UnifiedLessonControllerFactory createController;
  final WidgetBuilder builder;
  final Feature? feature;
  final FeatureRegistry? featureRegistry;
  final LearningUseCases? learning;
  final LessonUtcNow? nowUtc;
  final SessionConfiguration? configuration;
  final SessionConfigurationRevalidator? revalidateConfiguration;
  final ContrastiveFeedbackUseCases? contrastiveFeedback;

  @override
  State<UnifiedLessonModeHost> createState() => _UnifiedLessonModeHostState();
}

final class _UnifiedLessonModeHostState extends State<UnifiedLessonModeHost> {
  late final UnifiedLessonController _controller = _createController();
  FeatureRegistry? _features;
  Listenable? _featureChanges;
  bool _routeEnabled = true;
  FeatureState? _disabledState;
  Future<void>? _terminalCompensation;
  UnifiedLessonRouteLifecycle? _routeLifecycle;
  bool _controllerDisposed = false;

  UnifiedLessonController _createController() {
    final controller = widget.createController(widget.adapter);
    final configuration = widget.configuration;
    final revalidate = widget.revalidateConfiguration;
    if ((configuration == null) != (revalidate == null)) {
      throw ArgumentError(
        'configuration and revalidateConfiguration must be composed together',
      );
    }
    if (configuration != null && revalidate != null) {
      controller.bindSessionConfiguration(
        configuration,
        revalidate: revalidate,
      );
    }
    return controller;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeLifecycle ??= UnifiedLessonRouteLifecycle(
      _controller,
      widget.learning ?? AppDependenciesScope.maybeOf(context)?.learning,
      widget.nowUtc ?? _systemUtcNow,
    );
    _observeFeatures(
      widget.featureRegistry ?? AppDependenciesScope.maybeOf(context)?.features,
    );
  }

  @override
  void didUpdateWidget(UnifiedLessonModeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.featureRegistry, widget.featureRegistry) ||
        oldWidget.feature != widget.feature) {
      _observeFeatures(
        widget.featureRegistry ??
            AppDependenciesScope.maybeOf(context)?.features,
      );
    }
  }

  void _observeFeatures(FeatureRegistry? features) {
    if (identical(features, _features)) {
      _reconcileFeatureState();
      return;
    }
    _featureChanges?.removeListener(_onFeatureChanged);
    _features = features;
    final changes = features is Listenable ? features as Listenable : null;
    _featureChanges = changes;
    changes?.addListener(_onFeatureChanged);
    _reconcileFeatureState();
  }

  void _onFeatureChanged() => _reconcileFeatureState();

  void _reconcileFeatureState() {
    final feature = widget.feature;
    final features = _features;
    if (feature == null || features == null) return;
    if (_routeEnabled && !features.isEnabled(feature)) {
      _routeEnabled = false;
      _disabledState = features.stateOf(feature);
      if (mounted) setState(() {});
      _beginTerminalCompensation();
    }
  }

  void _beginTerminalCompensation() {
    if (_terminalCompensation != null) return;
    final compensation = _routeLifecycle!.retire();
    _terminalCompensation = compensation;
    unawaited(
      compensation.then<void>(
        (_) => _disposeController(),
        onError: (Object _, StackTrace _) => _disposeController(),
      ),
    );
  }

  static DateTime _systemUtcNow() => DateTime.now().toUtc();

  void _disposeController() {
    if (_controllerDisposed) return;
    _controllerDisposed = true;
    _controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;
    if (!_routeEnabled && feature != null) {
      return ProductionFeatureUnavailable(
        feature: feature,
        reason: ProductionFeatureUnavailableReason.unavailableState,
        state: _disabledState,
      );
    }
    final shell = UnifiedLessonShell(
      controller: _controller,
      nowUtc: widget.nowUtc,
      routeLifecycle: _routeLifecycle,
      configuration: widget.configuration,
      contrastiveFeedback: widget.contrastiveFeedback,
      builder: widget.builder,
    );
    final features = _features;
    if (feature == null || features == null) return shell;
    return ProductionFeatureGate(
      feature: feature,
      registry: features,
      builder: (_) => shell,
    );
  }

  @override
  void dispose() {
    _featureChanges?.removeListener(_onFeatureChanged);
    final routeLifecycle = _routeLifecycle;
    if (routeLifecycle == null) {
      _disposeController();
    } else {
      final compensation = _terminalCompensation ?? routeLifecycle.retire();
      _terminalCompensation = compensation;
      unawaited(
        compensation.then<void>(
          (_) => _disposeController(),
          onError: (Object _, StackTrace _) => _disposeController(),
        ),
      );
    }
    super.dispose();
  }
}

final class UnifiedLessonShell extends StatefulWidget {
  const UnifiedLessonShell({
    super.key,
    required this.builder,
    this.controller,
    this.nowUtc,
    this.lifecycleStateReader,
    this.routeLifecycle,
    this.configuration,
    this.contrastiveFeedback,
  });

  final WidgetBuilder builder;
  final UnifiedLessonController? controller;
  final LessonUtcNow? nowUtc;
  final LessonLifecycleStateReader? lifecycleStateReader;
  final UnifiedLessonRouteLifecycle? routeLifecycle;
  final SessionConfiguration? configuration;
  final ContrastiveFeedbackUseCases? contrastiveFeedback;

  @override
  State<UnifiedLessonShell> createState() => _UnifiedLessonShellState();
}

final class _UnifiedLessonShellState extends State<UnifiedLessonShell>
    with WidgetsBindingObserver {
  bool _pausedByLifecycle = false;
  late bool _lifecycleWantsActive;
  Future<void>? _lifecycleTransitionInFlight;
  Object? _lifecycleFailure;
  bool _pauseRetryRequired = false;
  Listenable? _focusFeatureChanges;
  UnifiedLessonController? _focusGateController;
  bool _focusGateEnabled = false;
  final LessonEphemeralStateRegistry _standaloneEphemeralStates =
      LessonEphemeralStateRegistry();

  LessonEphemeralStateRegistry get _ephemeralStates =>
      widget.routeLifecycle?._ephemeralStateRegistry ??
      _standaloneEphemeralStates;

  @override
  void initState() {
    super.initState();
    _lifecycleWantsActive = _bindingWantsActive(
      (widget.lifecycleStateReader ?? _bindingLifecycleState).call(),
    );
    WidgetsBinding.instance.addObserver(this);
    widget.controller?.addListener(_onControllerChanged);
    final initiallyAttachedController = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(widget.controller, initiallyAttachedController)) {
        return;
      }
      unawaited(_reconcileLifecycle());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observeFocusFeatureGate();
  }

  @override
  void didUpdateWidget(UnifiedLessonShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        !identical(oldWidget.routeLifecycle, widget.routeLifecycle)) {
      (oldWidget.routeLifecycle?._ephemeralStateRegistry ??
              _standaloneEphemeralStates)
          .clear();
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
      _pausedByLifecycle = false;
      _lifecycleTransitionInFlight = null;
      _lifecycleFailure = null;
      _pauseRetryRequired = false;
      _observeFocusFeatureGate();
      unawaited(_reconcileLifecycle());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleFailure = null;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        _lifecycleWantsActive = false;
        _ephemeralStates.clear();
        unawaited(_reconcileLifecycle());
      case AppLifecycleState.resumed:
        _lifecycleWantsActive = true;
        unawaited(_reconcileLifecycle());
    }
  }

  Future<void> _reconcileLifecycle() {
    final inFlight = _lifecycleTransitionInFlight;
    if (inFlight != null) return inFlight;
    final controller = widget.controller;
    if (controller == null) return Future<void>.value();
    var outcome = _LifecycleDriveOutcome.conflict;
    late final Future<void> future;
    future = _driveLifecycle(controller)
        .then<void>((result) => outcome = result)
        .whenComplete(() {
          if (!identical(_lifecycleTransitionInFlight, future)) return;
          _lifecycleTransitionInFlight = null;
          if (outcome != _LifecycleDriveOutcome.settled ||
              !mounted ||
              !identical(widget.controller, controller)) {
            return;
          }
          final status = controller.state.status;
          final needsPause =
              !_lifecycleWantsActive && status == LessonSessionStatus.active;
          final needsResume =
              _lifecycleWantsActive &&
              _pausedByLifecycle &&
              status == LessonSessionStatus.paused;
          if (needsPause || needsResume) unawaited(_reconcileLifecycle());
        });
    _lifecycleTransitionInFlight = future;
    return future;
  }

  Future<_LifecycleDriveOutcome> _driveLifecycle(
    UnifiedLessonController controller,
  ) async {
    while (mounted && identical(widget.controller, controller)) {
      if (!_lifecycleWantsActive) {
        if (controller.state.status != LessonSessionStatus.active) {
          return _LifecycleDriveOutcome.settled;
        }
        if (controller.terminalMutationInFlight) {
          return _LifecycleDriveOutcome.conflict;
        }
        try {
          await controller.pause(_now(), processBackground: true);
        } catch (error) {
          if (controller.state.status != LessonSessionStatus.active ||
              controller.terminalMutationInFlight) {
            return _LifecycleDriveOutcome.conflict;
          }
          _lifecycleFailure = error;
          _pauseRetryRequired = true;
          return _LifecycleDriveOutcome.failed;
        }
        if (!mounted || !identical(widget.controller, controller)) {
          return _LifecycleDriveOutcome.settled;
        }
        _pausedByLifecycle = true;
        _pauseRetryRequired = false;
        _lifecycleFailure = null;
        continue;
      }
      if (_pauseRetryRequired &&
          controller.state.status == LessonSessionStatus.active) {
        try {
          await controller.pause(_now(), processBackground: true);
        } catch (error) {
          if (controller.state.status != LessonSessionStatus.active ||
              controller.terminalMutationInFlight) {
            return _LifecycleDriveOutcome.conflict;
          }
          _lifecycleFailure = error;
          return _LifecycleDriveOutcome.failed;
        }
        _pausedByLifecycle = true;
        _pauseRetryRequired = false;
        _lifecycleFailure = null;
        continue;
      }
      if (!_pausedByLifecycle ||
          controller.state.status != LessonSessionStatus.paused) {
        return _LifecycleDriveOutcome.settled;
      }
      if (controller.terminalMutationInFlight) {
        return _LifecycleDriveOutcome.conflict;
      }
      try {
        await controller.resume(_now());
      } catch (error) {
        // A simultaneous user action may already have left the paused state.
        if (mounted &&
            identical(widget.controller, controller) &&
            controller.state.status != LessonSessionStatus.paused) {
          _pausedByLifecycle = false;
          return _LifecycleDriveOutcome.conflict;
        }
        _lifecycleFailure = error;
        return _LifecycleDriveOutcome.failed;
      }
      if (!mounted || !identical(widget.controller, controller)) {
        return _LifecycleDriveOutcome.settled;
      }
      _pausedByLifecycle = false;
      _lifecycleFailure = null;
    }
    return _LifecycleDriveOutcome.settled;
  }

  DateTime _now() => (widget.nowUtc ?? _systemUtcNow).call();

  static DateTime _systemUtcNow() => DateTime.now().toUtc();

  static AppLifecycleState? _bindingLifecycleState() =>
      WidgetsBinding.instance.lifecycleState;

  static bool _bindingWantsActive(AppLifecycleState? state) {
    return switch (state) {
      AppLifecycleState.paused ||
      AppLifecycleState.hidden ||
      AppLifecycleState.detached ||
      AppLifecycleState.inactive => false,
      AppLifecycleState.resumed || null => true,
    };
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final status = widget.controller?.state.status;
    if (status == LessonSessionStatus.completed ||
        status == LessonSessionStatus.abandoned) {
      _ephemeralStates.clear();
    }
    setState(() {});
    scheduleMicrotask(() {
      if (mounted && _lifecycleFailure == null) {
        unawaited(_reconcileLifecycle());
      }
    });
  }

  void _observeFocusFeatureGate() {
    final controller = widget.controller;
    final features = AppDependenciesScope.maybeOf(context)?.features;
    final Listenable? changes = features is Listenable
        ? features as Listenable
        : null;
    if (!identical(changes, _focusFeatureChanges)) {
      _focusFeatureChanges?.removeListener(_onFocusFeatureChanged);
      _focusFeatureChanges = changes;
      changes?.addListener(_onFocusFeatureChanged);
    }
    final wasEnabled = _focusGateEnabled;
    final controllerChanged = !identical(controller, _focusGateController);
    _focusGateController = controller;
    _focusGateEnabled = _isFocusGateEnabled();
    controller?.setFocusTimerGateEnabled(_focusGateEnabled);
    if (!_focusGateEnabled && (wasEnabled || controllerChanged)) {
      _disableFocusTimerForGate(controller);
    }
  }

  bool _isFocusGateEnabled() {
    final controller = widget.controller;
    final feature = controller?.focusTimerFeature;
    final features = AppDependenciesScope.maybeOf(context)?.features;
    return controller?.focusTimer != null &&
        feature != null &&
        features != null &&
        features.isEnabled(feature);
  }

  void _onFocusFeatureChanged() {
    if (!mounted) return;
    final controller = widget.controller;
    final wasEnabled = _focusGateEnabled;
    final isEnabled = _isFocusGateEnabled();
    if (wasEnabled == isEnabled) return;
    setState(() => _focusGateEnabled = isEnabled);
    controller?.setFocusTimerGateEnabled(isEnabled);
    if (wasEnabled && !isEnabled) {
      _disableFocusTimerForGate(controller);
    }
  }

  void _disableFocusTimerForGate(UnifiedLessonController? controller) {
    if (controller == null) return;
    unawaited(
      controller
          .disableFocusTimer(_now())
          .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) {
      return AccessibilityScope(
        child: UnifiedLessonSessionLifecycleScope(
          ephemeralStates: _ephemeralStates,
          child: Builder(builder: widget.builder),
        ),
      );
    }
    final hintState = controller.hintState;
    final dependencies = AppDependenciesScope.maybeOf(context);
    final bookmarkLearningItem = dependencies?.bookmarkLearningItem;
    final reportContent = dependencies?.reportContent;
    final resetRequired = controller.configurationResetRequired;
    return AccessibilityScope(
      child: UnifiedLessonSessionLifecycleScope(
        ephemeralStates: _ephemeralStates,
        lifecycle: UnifiedLessonSessionLifecycle._(
          controller,
          _now,
          widget.routeLifecycle,
          _ephemeralStates,
        ),
        child: Column(
          children: <Widget>[
            AccessibilitySemanticRegion(
              role: AccessibilitySemanticRole.contextAndProgress,
              label:
                  'Lesson ${controller.state.status.name}. '
                  'Progress '
                  '${(controller.state.progress * 100).round()} percent',
              child: LinearProgressIndicator(value: controller.state.progress),
            ),
            if (_focusGateEnabled)
              if (controller.focusTimer case final timer?)
                if (timer.snapshot.sessionId != null)
                  FocusTimerWidget(
                    controller: timer,
                    nowUtc: _now,
                    onStart: controller.startFocusTimer,
                    onPause: controller.pauseFocusTimer,
                    onResume: controller.resumeFocusTimer,
                    onFinish: controller.finishFocusTimer,
                  ),
            ContextualCompanionWidget(reaction: controller.companionReaction),
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) =>
                    controller.noteActiveLearningInteraction(_now()),
                child: Builder(
                  builder: (modeContext) {
                    final modeSurface = widget.builder(modeContext);
                    Widget? committedFeedback;
                    if (controller.feedback case final feedback?) {
                      committedFeedback = AccessibilitySemanticRegion(
                        role: AccessibilitySemanticRole.feedback,
                        child: AnswerFeedbackPanel(
                          feedback: feedback,
                          bookmarkIdentity: feedback.bookmarkIdentity,
                          onBookmark: bookmarkLearningItem,
                          reportIdentity: feedback.bookmarkIdentity,
                          onReport: reportContent,
                          contrastiveFeedback:
                              widget.contrastiveFeedback ??
                              dependencies?.contrastiveFeedback,
                          featureRegistry: dependencies?.features,
                        ),
                      );
                    }
                    final AccessibilityModeFeedbackSurface? accessibleSurface =
                        modeSurface is AccessibilityModeFeedbackSurface
                        ? modeSurface as AccessibilityModeFeedbackSurface
                        : null;
                    final placedModeSurface = accessibleSurface == null
                        ? modeSurface
                        : accessibleSurface.withShellFeedback(
                            committedFeedback,
                          );

                    return Column(
                      children: <Widget>[
                        if (controller.state.status ==
                                LessonSessionStatus.active &&
                            hintState != null)
                          HintPanel(
                            state: hintState,
                            onRevealNext: controller.revealNextHint,
                            enabled: controller.canRevealHint,
                          ),
                        if (accessibleSurface == null &&
                            committedFeedback != null)
                          committedFeedback,
                        if (resetRequired != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: SessionConfigurationResetPrompt(
                              error: resetRequired,
                              onReset: () => Navigator.of(context).maybePop(),
                            ),
                          ),
                        if (controller.configurationLimitReached)
                          Semantics(
                            key: const ValueKey(
                              'session-configuration-limit-reached',
                            ),
                            liveRegion: true,
                            label: 'Session limit reached',
                            child: const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Session limit reached'),
                            ),
                          ),
                        Expanded(child: placedModeSurface),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ephemeralStates.clear();
    _focusFeatureChanges?.removeListener(_onFocusFeatureChanged);
    widget.controller?.removeListener(_onControllerChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

enum _LifecycleDriveOutcome { settled, conflict, failed }
