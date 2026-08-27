import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../../runtime/registries/feature_registry.dart';
import '../application/contrastive_feedback_use_cases.dart';
import '../domain/answer_feedback.dart';
import '../domain/contrastive_explanation.dart';

/// Resolves optional f18 content only for an already committed f17 feedback
/// value and while the live broad quiz gate remains enabled.
final class CommittedContrastiveFeedbackPanel extends StatefulWidget {
  const CommittedContrastiveFeedbackPanel({
    super.key,
    required this.feedback,
    this.useCases,
    this.featureRegistry,
  });

  final AnswerFeedback feedback;
  final ContrastiveFeedbackUseCases? useCases;
  final FeatureRegistry? featureRegistry;

  @override
  State<CommittedContrastiveFeedbackPanel> createState() =>
      _CommittedContrastiveFeedbackPanelState();
}

final class _CommittedContrastiveFeedbackPanelState
    extends State<CommittedContrastiveFeedbackPanel> {
  ContrastiveFeedbackUseCases? _useCases;
  FeatureRegistry? _features;
  Listenable? _featureChanges;
  String? _attemptFingerprint;
  ContrastiveExplanation? _explanation;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _bind(
      useCases: widget.useCases ?? dependencies?.contrastiveFeedback,
      features: widget.featureRegistry ?? dependencies?.features,
    );
  }

  @override
  void didUpdateWidget(CommittedContrastiveFeedbackPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.feedback, widget.feedback) ||
        !identical(oldWidget.useCases, widget.useCases) ||
        !identical(oldWidget.featureRegistry, widget.featureRegistry)) {
      final dependencies = AppDependenciesScope.maybeOf(context);
      _bind(
        useCases: widget.useCases ?? dependencies?.contrastiveFeedback,
        features: widget.featureRegistry ?? dependencies?.features,
      );
    }
  }

  void _bind({
    required ContrastiveFeedbackUseCases? useCases,
    required FeatureRegistry? features,
  }) {
    if (!identical(_features, features)) {
      _featureChanges?.removeListener(_onFeatureChanged);
      _features = features;
      final changes = features is Listenable ? features as Listenable : null;
      _featureChanges = changes;
      changes?.addListener(_onFeatureChanged);
    }
    _useCases = useCases;
    _resolveIfEligible();
  }

  void _onFeatureChanged() {
    if (!mounted) return;
    if (!_gateEnabled) {
      _generation += 1;
      _attemptFingerprint = null;
      _explanation = null;
    }
    setState(() {});
    if (_gateEnabled) _resolveIfEligible();
  }

  bool get _gateEnabled => _features?.isEnabled(Feature.quiz) ?? false;

  void _resolveIfEligible() {
    final useCases = _useCases;
    final attempt = widget.feedback.committedContrastiveAttempt;
    if (!_gateEnabled || useCases == null || attempt == null) {
      _generation += 1;
      _attemptFingerprint = null;
      _explanation = null;
      return;
    }
    final fingerprint = attempt.stableFingerprint;
    if (_attemptFingerprint == fingerprint) return;
    _generation += 1;
    final generation = _generation;
    _attemptFingerprint = fingerprint;
    _explanation = null;
    unawaited(
      useCases
          .resolveAfterCommit(committedFeedback: widget.feedback)
          .then<void>((explanation) {
            if (!mounted || generation != _generation || !_gateEnabled) return;
            setState(() => _explanation = explanation);
          }),
    );
  }

  @override
  void dispose() {
    _featureChanges?.removeListener(_onFeatureChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final explanation = _gateEnabled ? _explanation : null;
    return explanation == null
        ? const SizedBox.shrink()
        : ContrastiveFeedbackPanel(explanation: explanation);
  }
}

final class ContrastiveFeedbackPanel extends StatelessWidget {
  const ContrastiveFeedbackPanel({super.key, required this.explanation});

  final ContrastiveExplanation explanation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maximumHeight = (MediaQuery.sizeOf(context).height * 0.25).clamp(
      96.0,
      280.0,
    );
    return Semantics(
      key: const ValueKey<String>('contrastive-feedback-panel'),
      container: true,
      explicitChildNodes: true,
      label: 'Contrastive feedback',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maximumHeight),
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _RationaleRow(
                    icon: Icons.lightbulb_outline,
                    title: 'Why the correct answer works',
                    rationale: explanation.correctRationale,
                  ),
                  const SizedBox(height: 12),
                  _RationaleRow(
                    icon: Icons.compare_arrows,
                    title: 'Why your choice differs',
                    rationale: explanation.distractorRationale,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _RationaleRow extends StatelessWidget {
  const _RationaleRow({
    required this.icon,
    required this.title,
    required this.rationale,
  });

  final IconData icon;
  final String title;
  final String rationale;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(icon),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(rationale),
          ],
        ),
      ),
    ],
  );
}
