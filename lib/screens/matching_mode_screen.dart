import 'package:flutter/material.dart';
import '../features/accessibility/presentation/accessibility_scope.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/matching_mode_adapter.dart';
import '../features/learning/domain/session_configuration.dart';
import '../features/learning/presentation/legacy_matching_mode_screen.dart';
import '../features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
export '../features/learning/presentation/legacy_matching_mode_screen.dart'
    show MatchingSessionLoader;

/// Compatibility dispatch. Legacy schemas retain their original renderer and
/// lifecycle; explicitly injected Pair owns its own canonical internal host.
class MatchingModeScreen extends StatelessWidget
    implements AccessibilityModeFeedbackSurface {
  const MatchingModeScreen({
    super.key,
    this.categoryId,
    this.learning,
    this.evidenceAdapter,
    this.modeAdapter,
    this.loadSession,
    this.timeLimit = const Duration(minutes: 2),
    this.sessionConfiguration,
    this.showCountdown = true,
    this.shellFeedback,
  }) : pairExperience = null;
  const MatchingModeScreen.pair({
    super.key,
    required PairMatchingExperienceHost experience,
  }) : pairExperience = experience,
       categoryId = null,
       learning = null,
       evidenceAdapter = null,
       modeAdapter = null,
       loadSession = null,
       timeLimit = null,
       sessionConfiguration = null,
       showCountdown = false,
       shellFeedback = null;
  final String? categoryId;
  final LearningUseCases? learning;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;
  final MatchingModeAdapter? modeAdapter;
  final MatchingSessionLoader? loadSession;
  final Duration? timeLimit;
  final SessionConfiguration? sessionConfiguration;
  final bool showCountdown;
  final Widget? shellFeedback;
  final PairMatchingExperienceHost? pairExperience;
  @override
  Widget withShellFeedback(Widget? feedback) =>
      pairExperience ??
      MatchingModeScreen(
        key: key,
        categoryId: categoryId,
        learning: learning,
        evidenceAdapter: evidenceAdapter,
        modeAdapter: modeAdapter,
        loadSession: loadSession,
        timeLimit: timeLimit,
        sessionConfiguration: sessionConfiguration,
        showCountdown: showCountdown,
        shellFeedback: feedback,
      );
  @override
  Widget build(BuildContext context) =>
      pairExperience ??
      LegacyMatchingModeScreen(
        categoryId: categoryId,
        learning: learning,
        evidenceAdapter: evidenceAdapter,
        modeAdapter: modeAdapter,
        loadSession: loadSession,
        timeLimit: timeLimit,
        sessionConfiguration: sessionConfiguration,
        showCountdown: showCountdown,
        shellFeedback: shellFeedback,
      );
}
