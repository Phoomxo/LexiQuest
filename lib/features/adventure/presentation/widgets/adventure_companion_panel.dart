import 'package:flutter/material.dart';

import '../../../../config/m3_theme.dart';
import '../../../learning/application/unified_lesson_controller.dart';
import '../../../learning/domain/lesson_session_state.dart';
import '../../../rewards/domain/reward_models.dart';
import '../../application/adventure_reaction_selector.dart';
import '../../domain/adventure_reaction.dart';

AdventureReactionTrigger? resolveAdventureLessonReactionTrigger({
  required LessonSessionStatus status,
  required LessonSessionStatus? previousStatus,
  required bool? committedAnswerCorrect,
  required int revealedHintLevel,
  bool skippedItem = false,
}) {
  if (status == LessonSessionStatus.completed) {
    return AdventureReactionTrigger.completed;
  }
  if (status == LessonSessionStatus.paused ||
      status == LessonSessionStatus.abandoned) {
    return null;
  }
  if (previousStatus == LessonSessionStatus.paused &&
      status == LessonSessionStatus.active) {
    return AdventureReactionTrigger.resumed;
  }
  if (skippedItem) return AdventureReactionTrigger.skipped;
  if (committedAnswerCorrect == false) {
    return AdventureReactionTrigger.incorrect;
  }
  if (committedAnswerCorrect == true && revealedHintLevel > 0) {
    return AdventureReactionTrigger.guidedCorrect;
  }
  return committedAnswerCorrect == true
      ? AdventureReactionTrigger.independentCorrect
      : AdventureReactionTrigger.missionReady;
}

/// Read-only adapter from the canonical lesson lifecycle to scripted reactions.
final class AdventureLessonCompanionPanel extends StatefulWidget {
  const AdventureLessonCompanionPanel({
    super.key,
    required this.controller,
    required this.rewardOwnership,
    required this.catalogVersion,
    this.language,
  });

  final UnifiedLessonController controller;
  final RewardAccount rewardOwnership;
  final String catalogVersion;
  final AdventureReactionLanguage? language;

  @override
  State<AdventureLessonCompanionPanel> createState() =>
      _AdventureLessonCompanionPanelState();
}

final class _AdventureLessonCompanionPanelState
    extends State<AdventureLessonCompanionPanel> {
  static const AdventureReactionSelector _selector =
      AdventureReactionSelector();

  LessonSessionStatus? _previousStatus;
  late int _committedResponseCount;
  late int _revealedHintLevel;
  late int _skippedItemCount;
  AdventureReactionTrigger? _trigger;
  AdventureReaction? _reaction;

  @override
  void initState() {
    super.initState();
    _initializeObservation();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(AdventureLessonCompanionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _initializeObservation();
    } else if (oldWidget.catalogVersion != widget.catalogVersion) {
      _select(_trigger);
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(_observeController);
  }

  void _initializeObservation() {
    final controller = widget.controller;
    final status = controller.state.status;
    _previousStatus = status;
    _committedResponseCount = controller.state.committedResponseCount;
    _revealedHintLevel = controller.hintState?.hintLevel ?? 0;
    _skippedItemCount = controller.skippedItemCount;
    _select(
      resolveAdventureLessonReactionTrigger(
        status: status,
        previousStatus: null,
        committedAnswerCorrect: controller.feedback?.isCorrect,
        revealedHintLevel: _revealedHintLevel,
      ),
    );
  }

  void _observeController() {
    final controller = widget.controller;
    final state = controller.state;
    final status = state.status;
    final currentHintLevel = controller.hintState?.hintLevel ?? 0;
    final committedNewAnswer =
        state.committedResponseCount > _committedResponseCount;
    final skippedNewItem = controller.skippedItemCount > _skippedItemCount;
    AdventureReactionTrigger? nextTrigger;

    if (status == LessonSessionStatus.completed ||
        status == LessonSessionStatus.abandoned ||
        (_previousStatus == LessonSessionStatus.paused &&
            status == LessonSessionStatus.active)) {
      nextTrigger = resolveAdventureLessonReactionTrigger(
        status: status,
        previousStatus: _previousStatus,
        committedAnswerCorrect: controller.feedback?.isCorrect,
        revealedHintLevel: _revealedHintLevel,
      );
    } else if (skippedNewItem || committedNewAnswer) {
      nextTrigger = resolveAdventureLessonReactionTrigger(
        status: status,
        previousStatus: _previousStatus,
        committedAnswerCorrect: controller.feedback?.isCorrect,
        revealedHintLevel: _revealedHintLevel,
        skippedItem: skippedNewItem,
      );
    }

    _previousStatus = status;
    _committedResponseCount = state.committedResponseCount;
    _skippedItemCount = controller.skippedItemCount;
    _revealedHintLevel = committedNewAnswer ? 0 : currentHintLevel;
    if (status == LessonSessionStatus.abandoned) {
      _trigger = null;
      _reaction = null;
    } else if (nextTrigger != null) {
      _select(nextTrigger);
    }
  }

  void _select(AdventureReactionTrigger? trigger) {
    _trigger = trigger;
    _reaction = trigger == null
        ? null
        : _selector.select(
            catalogVersion: widget.catalogVersion,
            trigger: trigger,
            variantSeed: widget.controller.state.committedResponseCount,
          );
  }

  @override
  Widget build(BuildContext context) => AdventureCompanionPanel(
    reaction: _reaction,
    rewardOwnership: widget.rewardOwnership,
    language: widget.language,
  );

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }
}

/// Passive companion presentation for an already selected scripted reaction.
final class AdventureCompanionPanel extends StatelessWidget {
  const AdventureCompanionPanel({
    super.key,
    required this.reaction,
    required this.rewardOwnership,
    this.language,
  });

  final AdventureReaction? reaction;
  final RewardAccount rewardOwnership;
  final AdventureReactionLanguage? language;

  @override
  Widget build(BuildContext context) {
    final current = reaction;
    if (current == null) return const SizedBox.shrink();
    final languageCode =
        language?.name ??
        Localizations.maybeLocaleOf(context)?.languageCode ??
        'en';
    final copy = current.copy.forLanguage(languageCode);
    final accessible = current.accessibilityText.forLanguage(languageCode);
    final cosmetics = _equippedCosmetics(rewardOwnership);
    final content = Semantics(
      key: ValueKey<String>(current.reactionId),
      container: true,
      liveRegion: true,
      explicitChildNodes: true,
      label: accessible,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const ExcludeSemantics(child: Icon(Icons.auto_awesome_outlined)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ExcludeSemantics(child: Text(copy)),
                    if (cosmetics.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      for (final cosmetic in cosmetics)
                        Semantics(
                          label: languageCode == 'th'
                              ? 'ของตกแต่งที่สวมใส่: ${cosmetic.name}'
                              : 'Equipped cosmetic: ${cosmetic.name}',
                          child: ExcludeSemantics(
                            child: Chip(label: Text(cosmetic.name)),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final duration = M3Theme.motionDuration(
      Durations.short2,
      mediaQuery: MediaQuery.maybeOf(context) ?? const MediaQueryData(),
    );
    if (duration == Duration.zero ||
        current.motion == AdventureReactionMotion.none) {
      return content;
    }
    return AnimatedSwitcher(duration: duration, child: content);
  }
}

List<RewardCatalogItem> _equippedCosmetics(RewardAccount ownership) {
  final slots = ownership.equippedBySlot.keys.toList()..sort();
  return <RewardCatalogItem>[
    for (final slot in slots)
      ?RewardCatalog.byIdAtVersion(
        ownership.equippedBySlot[slot]!,
        ownership.catalogVersion,
      ),
  ];
}
