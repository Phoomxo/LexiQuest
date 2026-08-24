import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../features/learning/application/learning_layer_adapter.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/unified_lesson_controller.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/domain/lesson_session_state.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/domain/vocabulary_word.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import 'associative_reading_session_screen.dart';
import 'categories_page.dart';

enum AssociativeReadingLauncherUnavailableReason {
  vocabulary,
  learning,
  associativeLearning,
  lessonLifecycle,
}

class AssociativeReadingLauncherScreen extends StatefulWidget {
  const AssociativeReadingLauncherScreen({
    super.key,
    this.vocabulary,
    this.learning,
    this.associativeLearning,
  });

  final VocabularyUseCases? vocabulary;
  final LearningUseCases? learning;
  final AssociativeLearningPort? associativeLearning;

  @override
  State<AssociativeReadingLauncherScreen> createState() =>
      _AssociativeReadingLauncherScreenState();
}

class _AssociativeReadingLauncherScreenState
    extends State<AssociativeReadingLauncherScreen> {
  bool _initialized = false;
  List<VocabularyWord>? _words;
  Object? _loadFailure;
  AssociativeReadingLauncherUnavailableReason? _unavailableReason;
  LearningUseCases? _learning;
  AssociativeLearningPort? _associativeLearning;
  CurrentActivityEvidenceAdapter? _currentActivityEvidence;
  LessonModeAdapter? _lessonAdapter;
  UnifiedLessonControllerFactory? _createLessonController;
  FeatureRegistry? _features;
  bool _starting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final dependencies = AppDependenciesScope.maybeOf(context);
    _features = dependencies?.features;
    _lessonAdapter = dependencies?.lessonModes
        ?.find(LessonMode.associativeReading)
        ?.adapter;
    _createLessonController = dependencies?.createLessonController;
    final vocabulary = widget.vocabulary ?? dependencies?.vocabulary;
    _learning = widget.learning ?? dependencies?.learning;
    _currentActivityEvidence = dependencies?.currentActivityEvidence;
    _associativeLearning =
        widget.associativeLearning ?? dependencies?.associativeLearning;

    if (vocabulary == null) {
      _unavailableReason =
          AssociativeReadingLauncherUnavailableReason.vocabulary;
      return;
    }
    if (_learning == null) {
      _unavailableReason = AssociativeReadingLauncherUnavailableReason.learning;
      return;
    }
    if (_associativeLearning == null) {
      _unavailableReason =
          AssociativeReadingLauncherUnavailableReason.associativeLearning;
      return;
    }
    if (dependencies != null &&
        (_lessonAdapter == null || _createLessonController == null)) {
      _unavailableReason =
          AssociativeReadingLauncherUnavailableReason.lessonLifecycle;
      return;
    }
    _loadWords(vocabulary);
  }

  Future<void> _loadWords(VocabularyUseCases vocabulary) async {
    try {
      final loaded = await vocabulary.getGameWords(limit: 10);
      if (!mounted) return;
      final spellings = <String>{};
      final words = loaded
          .where((word) => spellings.add(word.spelling))
          .toList(growable: false);
      setState(() => _words = List.unmodifiable(words));
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadFailure = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unavailableReason = _unavailableReason;
    if (unavailableReason != null) {
      return _LauncherUnavailable(reason: unavailableReason);
    }
    if (_loadFailure != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Associative Reading')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Vocabulary could not be loaded for associative reading.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final words = _words;
    if (words == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (words.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Associative Reading')),
        body: Center(
          key: const ValueKey('associative-reading-empty'),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.menu_book_outlined, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Save at least one vocabulary word before starting.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => AppNavigator.pushPage<void>(
                    context,
                    AppPage<void>(
                      name: 'vocabulary/create',
                      builder: (_) => CategoriesPage(),
                    ),
                    replace: true,
                  ),
                  child: const Text('Create vocabulary'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_starting,
      child: Scaffold(
        appBar: AppBar(title: const Text('Associative Reading')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${words.length} target word${words.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: words
                      .map(
                        (word) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(word.spelling),
                          subtitle: Text(word.meaning),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              FilledButton(
                onPressed: _starting ? null : () => _start(words),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(_starting ? 'Starting...' : 'Start reading'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _start(List<VocabularyWord> words) async {
    if (_starting) return;
    final learning = _learning!;
    final associativeLearning = _associativeLearning!;
    final lessonAdapter = _lessonAdapter;
    final createLessonController = _createLessonController;
    final features = _features;
    final wordIds = <String, String>{
      for (final word in words) word.spelling: word.id,
    };
    var cefrLevel = 'A2';
    for (final word in words) {
      final candidate = word.cefrLevel?.trim();
      if (candidate != null && candidate.isNotEmpty) {
        cefrLevel = candidate;
        break;
      }
    }
    final passage = words
        .map((word) => '${word.spelling} means ${word.meaning}.')
        .join(' ');
    final versionSeed = jsonEncode([
      for (final word in words) [word.id, word.localRevision],
    ]);
    final documentDigest = sha256.convert(utf8.encode(versionSeed)).toString();
    final documentRevision =
        int.parse(documentDigest.substring(0, 13), radix: 16) + 1;

    setState(() => _starting = true);
    String? createdSessionId;
    var compensationAttempted = false;
    try {
      final session = await learning.startAssociativeReadingSessionHandle();
      createdSessionId = session.id;
      if (!mounted) {
        await learning.abandonSession(
          sessionId: session.id,
          abandonedAtUtc: DateTime.now().toUtc(),
        );
        return;
      }
      final terminalAuthority = _AssociativeReadingSessionTerminalAuthority();
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/associative-reading/session',
          builder: (_) {
            Widget buildSession(BuildContext context) =>
                AssociativeReadingSessionScreen(
                  cefrLevel: cefrLevel,
                  targetWords: words
                      .map((word) => word.spelling)
                      .toList(growable: false),
                  targetWordIds: Map.unmodifiable(wordIds),
                  passageText: passage,
                  documentId: 'associative-reading:$documentDigest',
                  documentRevision: documentRevision,
                  learning: learning,
                  associativeLearning: associativeLearning,
                  sessionId: session.id,
                  sessionStartedAtUtc: session.startedAtUtc,
                  evidenceAdapter: _currentActivityEvidence,
                  claimTerminalCompensation:
                      terminalAuthority.claimTerminalCompensation,
                  retainsLifecycleOwnership:
                      terminalAuthority.retainsLifecycleOwnership,
                  mayPublishOwnedTerminalFailure:
                      terminalAuthority.mayPublishOwnedTerminalFailure,
                  onTerminalFailurePublished:
                      terminalAuthority.markTerminalFailurePublished,
                );

            if (lessonAdapter != null &&
                createLessonController != null &&
                features != null) {
              return _AssociativeReadingSessionRoute(
                features: features,
                learning: learning,
                sessionId: session.id,
                adapter: lessonAdapter,
                createController: createLessonController,
                terminalAuthority: terminalAuthority,
                builder: buildSession,
              );
            }
            return ProductionFeatureGate(
              feature: Feature.reading,
              registry: features,
              builder: buildSession,
            );
          },
        ),
      );
      final terminalCompensation = terminalAuthority.terminalCompensation;
      if (terminalCompensation != null) {
        try {
          await terminalCompensation;
        } catch (_) {
          // A single bounded launcher compensation remains below.
        }
      }
      if (!terminalAuthority.durableTerminal) {
        compensationAttempted = true;
        await learning.abandonSession(
          sessionId: session.id,
          abandonedAtUtc: DateTime.now().toUtc(),
        );
        terminalAuthority.markDurableTerminal();
      }
      createdSessionId = null;
    } catch (_) {
      final sessionId = createdSessionId;
      if (sessionId != null && !compensationAttempted) {
        try {
          compensationAttempted = true;
          await learning.abandonSession(
            sessionId: sessionId,
            abandonedAtUtc: DateTime.now().toUtc(),
          );
          createdSessionId = null;
        } catch (_) {
          // Keep the launcher fail-closed. The existing active-session
          // bootstrap recovery remains the final bounded compensator.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start associative reading. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
}

final class _AssociativeReadingSessionTerminalAuthority {
  bool durableTerminal = false;
  Future<void>? terminalCompensation;
  bool _rollbackRequested = false;
  final Set<VoidCallback> _claimListeners = <VoidCallback>{};
  final Set<VoidCallback> _failurePublishedListeners = <VoidCallback>{};

  void addClaimListener(VoidCallback listener) {
    _claimListeners.add(listener);
  }

  void removeClaimListener(VoidCallback listener) {
    _claimListeners.remove(listener);
  }

  void addFailurePublishedListener(VoidCallback listener) {
    _failurePublishedListeners.add(listener);
  }

  void removeFailurePublishedListener(VoidCallback listener) {
    _failurePublishedListeners.remove(listener);
  }

  void markTerminalFailurePublished() {
    for (final listener in List<VoidCallback>.of(_failurePublishedListeners)) {
      listener();
    }
  }

  void markDurableTerminal() {
    durableTerminal = true;
  }

  bool retainsLifecycleOwnership() =>
      terminalCompensation == null && !durableTerminal;

  bool mayPublishOwnedTerminalFailure() => !_rollbackRequested;

  void markRollbackRequested() {
    _rollbackRequested = true;
  }

  Future<AssociativeReadingTerminalCompensationResult>
  claimTerminalCompensation(Future<void> Function() operation) {
    if (durableTerminal) {
      return Future<AssociativeReadingTerminalCompensationResult>.value(
        const AssociativeReadingTerminalCompensationResult.success(
          ownsClaim: false,
        ),
      );
    }
    final existing = terminalCompensation;
    if (existing != null) return _claimResult(existing, ownsClaim: false);
    final completer = Completer<void>();
    terminalCompensation = completer.future;
    for (final listener in List<VoidCallback>.of(_claimListeners)) {
      listener();
    }
    unawaited(_runClaimedCompensation(operation, completer));
    return _claimResult(completer.future, ownsClaim: true);
  }

  Future<AssociativeReadingTerminalCompensationResult> _claimResult(
    Future<void> completion, {
    required bool ownsClaim,
  }) async {
    try {
      await completion;
      return AssociativeReadingTerminalCompensationResult.success(
        ownsClaim: ownsClaim,
      );
    } catch (error, stackTrace) {
      return AssociativeReadingTerminalCompensationResult.failure(
        ownsClaim: ownsClaim,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _runClaimedCompensation(
    Future<void> Function() operation,
    Completer<void> completer,
  ) async {
    try {
      await operation();
      markDurableTerminal();
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }
}

final class _AssociativeReadingSessionRoute extends StatefulWidget {
  const _AssociativeReadingSessionRoute({
    required this.features,
    required this.learning,
    required this.sessionId,
    required this.adapter,
    required this.createController,
    required this.terminalAuthority,
    required this.builder,
  });

  final FeatureRegistry features;
  final LearningUseCases learning;
  final String sessionId;
  final LessonModeAdapter adapter;
  final UnifiedLessonControllerFactory createController;
  final _AssociativeReadingSessionTerminalAuthority terminalAuthority;
  final WidgetBuilder builder;

  @override
  State<_AssociativeReadingSessionRoute> createState() =>
      _AssociativeReadingSessionRouteState();
}

final class _AssociativeReadingSessionRouteState
    extends State<_AssociativeReadingSessionRoute> {
  late final UnifiedLessonController _controller = widget.createController(
    widget.adapter,
  );
  Listenable? _featureChanges;
  late bool _routeEnabled;
  FeatureState? _disabledState;
  bool _controllerDisposed = false;

  @override
  void initState() {
    super.initState();
    _routeEnabled = widget.features.isEnabled(Feature.reading);
    _disabledState = _routeEnabled
        ? null
        : widget.features.stateOf(Feature.reading);
    final changes = widget.features is Listenable
        ? widget.features as Listenable
        : null;
    _featureChanges = changes;
    changes?.addListener(_onFeatureChanged);
    widget.terminalAuthority.addClaimListener(_onTerminalCompensationClaimed);
    widget.terminalAuthority.addFailurePublishedListener(
      _onTerminalFailurePublished,
    );
    if (!_routeEnabled) _beginRollback();
  }

  void _onFeatureChanged() {
    if (!_routeEnabled || widget.features.isEnabled(Feature.reading)) return;
    _routeEnabled = false;
    _disabledState = widget.features.stateOf(Feature.reading);
    if (mounted) setState(() {});
    _beginRollback();
  }

  void _beginRollback() {
    widget.terminalAuthority.markRollbackRequested();
    final claim = widget.terminalAuthority.claimTerminalCompensation(
      _abandonDurableSession,
    );
    unawaited(
      claim.then<void>((result) {
        if (!result.succeeded) _disposeController();
      }),
    );
  }

  void _onTerminalCompensationClaimed() {
    final terminalCompensation = widget.terminalAuthority.terminalCompensation;
    if (terminalCompensation == null) return;
    unawaited(
      terminalCompensation.then<void>(
        (_) => _disposeController(),
        onError: (Object _, StackTrace _) {},
      ),
    );
  }

  void _onTerminalFailurePublished() {
    _disposeController();
  }

  void _disposeController() {
    if (_controllerDisposed) return;
    _controllerDisposed = true;
    _controller.dispose();
  }

  Future<void> _abandonDurableSession() async {
    if (_controller.state.status == LessonSessionStatus.completed) return;
    final abandonedAtUtc = DateTime.now().toUtc();
    final wasBoundToSession = _controller.state.sessionId == widget.sessionId;
    try {
      await _controller.abandon(abandonedAtUtc);
      if (wasBoundToSession ||
          _controller.state.sessionId == widget.sessionId) {
        return;
      }
    } catch (_) {
      if (_controller.state.status == LessonSessionStatus.completed) return;
    }
    await widget.learning.abandonSession(
      sessionId: widget.sessionId,
      abandonedAtUtc: abandonedAtUtc,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_routeEnabled) {
      return ProductionFeatureUnavailable(
        feature: Feature.reading,
        reason: ProductionFeatureUnavailableReason.unavailableState,
        state: _disabledState,
      );
    }
    return ProductionFeatureGate(
      feature: Feature.reading,
      registry: widget.features,
      builder: (_) =>
          UnifiedLessonShell(controller: _controller, builder: widget.builder),
    );
  }

  @override
  void dispose() {
    _featureChanges?.removeListener(_onFeatureChanged);
    widget.terminalAuthority.removeClaimListener(
      _onTerminalCompensationClaimed,
    );
    widget.terminalAuthority.removeFailurePublishedListener(
      _onTerminalFailurePublished,
    );
    final state = _controller.state;
    if ((state.status == LessonSessionStatus.completed ||
            state.status == LessonSessionStatus.abandoned) &&
        state.sessionId == widget.sessionId) {
      widget.terminalAuthority.markDurableTerminal();
    }
    final terminalCompensation = widget.terminalAuthority.terminalCompensation;
    if (terminalCompensation == null) {
      _disposeController();
    } else {
      unawaited(
        terminalCompensation.then<void>(
          (_) => _disposeController(),
          onError: (Object _, StackTrace _) => _disposeController(),
        ),
      );
    }
    super.dispose();
  }
}

class _LauncherUnavailable extends StatelessWidget {
  const _LauncherUnavailable({required this.reason});

  final AssociativeReadingLauncherUnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    final detail = switch (reason) {
      AssociativeReadingLauncherUnavailableReason.vocabulary =>
        'Vocabulary is unavailable.',
      AssociativeReadingLauncherUnavailableReason.learning =>
        'Learning records are unavailable.',
      AssociativeReadingLauncherUnavailableReason.associativeLearning =>
        'Associative persistence is unavailable.',
      AssociativeReadingLauncherUnavailableReason.lessonLifecycle =>
        'Lesson lifecycle is unavailable.',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Associative Reading')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Associative reading is unavailable on this installation. '
            '$detail',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
