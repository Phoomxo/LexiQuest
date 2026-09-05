import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../accessibility/domain/accessibility_policy.dart';
import '../../../accessibility/presentation/accessibility_scope.dart';
import '../../../../config/m3_theme.dart';
import '../domain/pair_active_clock.dart';
import '../domain/pair_matching_engine.dart';
import '../domain/pair_matching_launch.dart';
import '../domain/pair_matching_plan.dart';
import '../domain/pair_repair_policy.dart';
import 'pair_matching_copy.dart';

/// Immutable presentation input. All learning decisions remain in the owner.
final class PairBoardModel {
  const PairBoardModel({
    required this.state,
    required this.timer,
    this.busy = false,
    this.focusedTraversal = false,
    this.audioAvailable = false,
    this.statusMessage,
    this.audioFallback,
  });

  final PairMatchingState state;
  final PairTimerState timer;
  final bool busy;
  final bool focusedTraversal;
  final bool audioAvailable;
  final String? statusMessage;
  final String? audioFallback;
}

/// Pure Pair board renderer. It emits identities and never evaluates answers.
final class PairBoardView extends StatefulWidget
    implements AccessibilityModeFeedbackSurface {
  const PairBoardView({
    super.key,
    required this.model,
    required this.onSelectTile,
    required this.onRevealMapping,
    required this.onConfirmGuidedMapping,
    required this.onPronounce,
    this.shellFeedback,
  });

  final PairBoardModel model;
  final ValueChanged<PairTile> onSelectTile;
  final ValueChanged<String> onRevealMapping;
  final void Function(String wordId, int shownSupportRevision)
  onConfirmGuidedMapping;
  final ValueChanged<PairTile> onPronounce;
  final Widget? shellFeedback;

  @override
  Widget withShellFeedback(Widget? feedback) => PairBoardView(
    key: key,
    model: model,
    onSelectTile: onSelectTile,
    onRevealMapping: onRevealMapping,
    onConfirmGuidedMapping: onConfirmGuidedMapping,
    onPronounce: onPronounce,
    shellFeedback: feedback,
  );

  @override
  State<PairBoardView> createState() => _PairBoardViewState();
}

final class _PairBoardViewState extends State<PairBoardView> {
  final Map<String, FocusNode> _tileFocusNodes = <String, FocusNode>{};
  final Set<
    ({String sessionId, int roundOrdinal, PairTimerMode mode, int thresholdMs})
  >
  _announcedTimerThresholds = {};
  bool _timerAnnouncementLive = false;

  PairMatchingState get _state => widget.model.state;

  String _focusKey(PairTileSide side, String wordId) => '${side.name}:$wordId';

  FocusNode _focusNode(PairTileSide side, String wordId) =>
      _tileFocusNodes.putIfAbsent(_focusKey(side, wordId), _createFocusNode);

  FocusNode _createFocusNode() {
    final node = FocusNode();
    node.addListener(_handleFocusChanged);
    return node;
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _synchronizeFocusNodes();
  }

  @override
  void didUpdateWidget(PairBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTimerAnnouncement(oldWidget.model);
    _synchronizeFocusNodes();
    final oldMatched = oldWidget.model.state.matchedWordIds;
    final newMatched = widget.model.state.matchedWordIds;
    if (newMatched.length > oldMatched.length &&
        newMatched.containsAll(oldMatched)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusFirstActionableUnmatchedPrompt();
      });
    }
  }

  void _updateTimerAnnouncement(PairBoardModel oldModel) {
    _timerAnnouncementLive = false;
    final oldTimer = oldModel.timer;
    final timer = widget.model.timer;
    final samePhase =
        oldModel.state.plan.learningSessionId ==
            widget.model.state.plan.learningSessionId &&
        oldModel.state.roundOrdinal == widget.model.state.roundOrdinal &&
        oldTimer.mode == timer.mode;
    if (!samePhase || !oldTimer.timed || !timer.timed) return;

    for (final thresholdMs in const <int>[30000, 10000]) {
      if (oldTimer.remainingActiveMs <= thresholdMs ||
          timer.remainingActiveMs > thresholdMs) {
        continue;
      }
      final announcement = (
        sessionId: widget.model.state.plan.learningSessionId,
        roundOrdinal: widget.model.state.roundOrdinal,
        mode: timer.mode,
        thresholdMs: thresholdMs,
      );
      if (_announcedTimerThresholds.add(announcement)) {
        _timerAnnouncementLive = true;
      }
    }
  }

  void _synchronizeFocusNodes() {
    final retained = <String>{
      for (final item in _state.plan.orderedLexicalItems)
        for (final side in PairTileSide.values) _focusKey(side, item.wordId),
    };
    for (final key in retained) {
      _tileFocusNodes.putIfAbsent(key, _createFocusNode);
    }
    final removed = _tileFocusNodes.keys
        .where((key) => !retained.contains(key))
        .toList(growable: false);
    for (final key in removed) {
      final node = _tileFocusNodes.remove(key);
      node?.removeListener(_handleFocusChanged);
      node?.dispose();
    }
  }

  void _focusFirstActionableUnmatchedPrompt() {
    for (final id in _state.orderFor(PairTileSide.prompt)) {
      if (_isActionable(id)) {
        _focusNode(PairTileSide.prompt, id).requestFocus();
        return;
      }
    }
  }

  bool _isActionable(String wordId) {
    if (widget.model.busy ||
        _state.pending != null ||
        _state.matchedWordIds.contains(wordId)) {
      return false;
    }
    final repair = _state.repairFor(wordId)?.status;
    return repair != PairRepairStatus.waiting &&
        repair != PairRepairStatus.guidedRequired &&
        !_state.supportedWordIds.contains(wordId);
  }

  @override
  void dispose() {
    for (final node in _tileFocusNodes.values) {
      node.removeListener(_handleFocusChanged);
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = PairMatchingCopy.forLocale(Localizations.localeOf(context));
    final accessibility = AccessibilityScope.of(context);
    final mediaQuery = MediaQuery.of(context);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final constrainedWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : mediaQuery.size.width;
          final effectiveWidth = math.min(
            constrainedWidth,
            mediaQuery.size.width,
          );
          final focused =
              widget.model.focusedTraversal ||
              mediaQuery.accessibleNavigation ||
              accessibility.textScale >= 2 ||
              effectiveWidth < 360;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: SizedBox(
                  key: const ValueKey<String>('pair-board-content'),
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      AccessibilitySemanticRegion(
                        role: AccessibilitySemanticRole.contextAndProgress,
                        child: _buildContext(context, copy),
                      ),
                      const SizedBox(height: 12),
                      AccessibilitySemanticRegion(
                        role: AccessibilitySemanticRole.prompt,
                        child: Text(
                          copy.instruction,
                          softWrap: true,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      const SizedBox(height: 16),
                      AccessibilitySemanticRegion(
                        role: AccessibilitySemanticRole.responseAndInput,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            focused
                                ? _buildFocused(context, copy)
                                : _buildRegular(context, copy),
                            for (final id in _guidedWordIds) ...<Widget>[
                              const SizedBox(height: 12),
                              _buildGuidedCard(context, copy, id),
                            ],
                          ],
                        ),
                      ),
                      if (_hasFeedback) ...<Widget>[
                        const SizedBox(height: 16),
                        AccessibilitySemanticRegion(
                          role: AccessibilitySemanticRole.feedback,
                          child: _buildFeedback(context, copy),
                        ),
                      ],
                      if (_hasNavigation) ...<Widget>[
                        const SizedBox(height: 16),
                        AccessibilitySemanticRegion(
                          role: AccessibilitySemanticRole.navigation,
                          child: _buildNavigation(context, copy),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContext(BuildContext context, PairMatchingCopy copy) {
    final total = _state.plan.orderedLexicalItems.length;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            copy.title,
            softWrap: true,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        Semantics(
          label: copy.progress(_state.matchedWordIds.length, total),
          child: ExcludeSemantics(
            child: Text(
              copy.progress(_state.matchedWordIds.length, total),
              softWrap: true,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        if (widget.model.timer.mode != PairTimerMode.off)
          _PairTimerLabel(
            timer: widget.model.timer,
            copy: copy,
            liveRegion: _timerAnnouncementLive,
          ),
      ],
    );
  }

  Widget _buildRegular(BuildContext context, PairMatchingCopy copy) {
    final gap = MediaQuery.sizeOf(context).width >= 600 ? 16.0 : 12.0;
    return Row(
      key: const ValueKey<String>('pair-board-regular'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: _buildColumn(context, copy, PairTileSide.prompt)),
        SizedBox(width: gap),
        Expanded(child: _buildColumn(context, copy, PairTileSide.target)),
      ],
    );
  }

  Widget _buildColumn(
    BuildContext context,
    PairMatchingCopy copy,
    PairTileSide side,
  ) => Column(
    key: ValueKey<String>('pair-column:${side.name}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final (index, id) in _state.orderFor(side).indexed) ...<Widget>[
        if (index > 0) const SizedBox(height: 12),
        _buildTile(context, copy, PairTile(side, id)),
      ],
    ],
  );

  Widget _buildFocused(BuildContext context, PairMatchingCopy copy) {
    final selected = _state.selected;
    if (selected == null) {
      return Column(
        key: const ValueKey<String>('pair-board-focused'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            copy.chooseSource,
            softWrap: true,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final id in _state.orderFor(PairTileSide.prompt)) ...<Widget>[
            _buildTile(context, copy, PairTile(PairTileSide.prompt, id)),
            const SizedBox(height: 12),
          ],
        ],
      );
    }

    final candidateSide = selected.side == PairTileSide.prompt
        ? PairTileSide.target
        : PairTileSide.prompt;
    return Column(
      key: const ValueKey<String>('pair-board-focused'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          copy.selectedSource,
          softWrap: true,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _buildSelectedContext(context, copy, selected),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: const ValueKey<String>('pair-change-source'),
            onPressed: widget.model.busy || _state.pending != null
                ? null
                : () => widget.onSelectTile(selected),
            child: Text(copy.changeSource, softWrap: true),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _languageFor(candidateSide) == 'th'
              ? copy.chooseTarget
              : copy.choosePrompt,
          softWrap: true,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final id in _state.orderFor(candidateSide)) ...<Widget>[
          _buildTile(context, copy, PairTile(candidateSide, id)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildSelectedContext(
    BuildContext context,
    PairMatchingCopy copy,
    PairTile tile,
  ) {
    final language = _languageFor(tile.side);
    final value = _valueFor(tile.side, tile.wordId);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey<String>('pair-focused-source'),
      container: true,
      label: copy.tileLabel(
        languageCode: language,
        value: value,
        selected: true,
        repairAvailable: false,
      ),
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.secondary, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              value,
              softWrap: true,
              style: TextStyle(color: colors.onSecondaryContainer),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    PairMatchingCopy copy,
    PairTile tile,
  ) {
    final repair = _state.repairFor(tile.wordId)?.status;
    final hidden =
        _state.matchedWordIds.contains(tile.wordId) ||
        repair == PairRepairStatus.waiting ||
        repair == PairRepairStatus.guidedRequired ||
        _state.supportedWordIds.contains(tile.wordId);
    final minimumHeight = _state.plan.density == PairDensity.compact4
        ? 64.0
        : 56.0;
    if (hidden) {
      return ExcludeSemantics(
        child: SizedBox(
          key: ValueKey<String>(
            'pair-placeholder:${tile.side.name}:${tile.wordId}',
          ),
          height: minimumHeight,
        ),
      );
    }
    final selected = _sameTile(_state.selected, tile);
    final repairAvailable = repair == PairRepairStatus.available;
    final enabled = !widget.model.busy && _state.pending == null;
    final language = _languageFor(tile.side);
    final value = _valueFor(tile.side, tile.wordId);
    final focusNode = _focusNode(tile.side, tile.wordId);
    final accessibility = AccessibilityScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final borderWidth =
        selected || repairAvailable || accessibility.highContrast ? 2.0 : 1.0;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      focusable: enabled,
      focused: focusNode.hasFocus,
      selected: selected,
      label: copy.tileLabel(
        languageCode: language,
        value: value,
        selected: selected,
        repairAvailable: repairAvailable,
      ),
      onTap: enabled ? () => widget.onSelectTile(tile) : null,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: M3Theme.motionDuration(
            const Duration(milliseconds: 100),
            mediaQuery: MediaQuery.of(context),
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.secondaryContainer
                : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected || repairAvailable
                  ? colors.secondary
                  : colors.outlineVariant,
              width: borderWidth,
            ),
          ),
          child: OutlinedButton(
            key: ValueKey<String>('pair-tile:${tile.side.name}:${tile.wordId}'),
            focusNode: focusNode,
            onPressed: enabled ? () => widget.onSelectTile(tile) : null,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, minimumHeight),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              foregroundColor: colors.onSurface,
              backgroundColor: Colors.transparent,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(value, softWrap: true, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  bool _sameTile(PairTile? a, PairTile b) =>
      a != null && a.side == b.side && a.wordId == b.wordId;

  PairLexicalItem _item(String wordId) => _state.plan.orderedLexicalItems
      .singleWhere((item) => item.wordId == wordId);

  String _languageFor(PairTileSide side) => side == PairTileSide.prompt
      ? _state.plan.promptLocale
      : _state.plan.targetLocale;

  String _valueFor(PairTileSide side, String wordId) {
    final item = _item(wordId);
    final prompt = side == PairTileSide.prompt;
    return switch (_state.plan.direction) {
      PairDirection.enToTh => prompt ? item.spelling : item.meaning,
      PairDirection.thToEn => prompt ? item.meaning : item.spelling,
    };
  }

  List<String> get _guidedWordIds => List<String>.unmodifiable(
    _state
        .orderFor(PairTileSide.prompt)
        .where(
          (id) =>
              !_state.matchedWordIds.contains(id) &&
              _state.supportAtRevision[id] != null &&
              (_state.supportedWordIds.contains(id) ||
                  _state.repairFor(id)?.status ==
                      PairRepairStatus.guidedRequired),
        ),
  );

  Widget _buildGuidedCard(
    BuildContext context,
    PairMatchingCopy copy,
    String wordId,
  ) {
    final colors = Theme.of(context).colorScheme;
    final prompt = _valueFor(PairTileSide.prompt, wordId);
    final target = _valueFor(PairTileSide.target, wordId);
    final revision = _state.supportAtRevision[wordId]!;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${copy.guidedTail}. $prompt. $target',
      child: DecoratedBox(
        key: ValueKey<String>('pair-guided:$wordId'),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.tertiary, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.lightbulb_outline,
                      color: colors.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        copy.guidedTail,
                        softWrap: true,
                        style: TextStyle(color: colors.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ExcludeSemantics(
                child: Text(
                  prompt,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onTertiaryContainer),
                ),
              ),
              ExcludeSemantics(
                child: Icon(
                  Icons.arrow_downward,
                  color: colors.onTertiaryContainer,
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  target,
                  softWrap: true,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onTertiaryContainer),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: ValueKey<String>('pair-confirm-guided:$wordId'),
                onPressed: widget.model.busy || _state.pending != null
                    ? null
                    : () => widget.onConfirmGuidedMapping(wordId, revision),
                child: Text(copy.confirmGuided, softWrap: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasFeedback =>
      widget.shellFeedback != null ||
      widget.model.statusMessage != null ||
      (_state.attempts.isNotEmpty && !_state.attempts.last.isCorrect);

  Widget _buildFeedback(BuildContext context, PairMatchingCopy copy) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (widget.shellFeedback != null) widget.shellFeedback!,
      if (widget.shellFeedback != null &&
          (widget.model.statusMessage != null ||
              (_state.attempts.isNotEmpty && !_state.attempts.last.isCorrect)))
        const SizedBox(height: 12),
      if (_state.attempts.isNotEmpty && !_state.attempts.last.isCorrect)
        _buildWrongFeedback(context, copy),
      if (_state.attempts.isNotEmpty &&
          !_state.attempts.last.isCorrect &&
          widget.model.statusMessage != null)
        const SizedBox(height: 12),
      if (widget.model.statusMessage case final status?)
        Semantics(
          key: const ValueKey<String>('pair-status'),
          container: true,
          liveRegion: true,
          label: status,
          child: ExcludeSemantics(child: Text(status, softWrap: true)),
        ),
    ],
  );

  Widget _buildWrongFeedback(BuildContext context, PairMatchingCopy copy) {
    final last = _state.attempts.last;
    final status = _state.repairFor(last.promptWordId)?.status;
    final secondary = status == PairRepairStatus.waiting
        ? copy.repairQueued
        : copy.semanticHelp;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${copy.wrong}. $secondary',
      child: ExcludeSemantics(
        child: DecoratedBox(
          key: const ValueKey<String>('pair-feedback:wrong'),
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.secondary, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.info_outline, color: colors.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        copy.wrong,
                        softWrap: true,
                        style: TextStyle(color: colors.onSecondaryContainer),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        secondary,
                        softWrap: true,
                        style: TextStyle(color: colors.onSecondaryContainer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasNavigation {
    final selected = _state.selected;
    return selected != null &&
        (widget.model.audioAvailable ||
            widget.model.audioFallback != null ||
            !_state.supportedWordIds.contains(selected.wordId));
  }

  Widget _buildNavigation(BuildContext context, PairMatchingCopy copy) {
    final selected = _state.selected!;
    final language = _languageFor(selected.side);
    final controls = <Widget>[];
    if (widget.model.audioAvailable) {
      controls.add(
        OutlinedButton.icon(
          key: ValueKey<String>(
            'pair-pronounce:${selected.side.name}:${selected.wordId}',
          ),
          onPressed: widget.model.busy
              ? null
              : () => widget.onPronounce(selected),
          icon: const Icon(Icons.volume_up_outlined),
          label: Text(copy.pronounce(language), softWrap: true),
        ),
      );
    } else if (widget.model.audioFallback case final fallback?) {
      controls.add(
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${copy.audioUnavailable}: $fallback', softWrap: true),
          ),
        ),
      );
    }
    if (!_state.supportedWordIds.contains(selected.wordId)) {
      controls.add(
        TextButton.icon(
          key: ValueKey<String>('pair-reveal:${selected.wordId}'),
          onPressed: widget.model.busy || _state.pending != null
              ? null
              : () => widget.onRevealMapping(selected.wordId),
          icon: const Icon(Icons.lightbulb_outline),
          label: Text(copy.revealMapping, softWrap: true),
        ),
      );
    }
    return Wrap(spacing: 12, runSpacing: 12, children: controls);
  }
}

final class _PairTimerLabel extends StatelessWidget {
  const _PairTimerLabel({
    required this.timer,
    required this.copy,
    required this.liveRegion,
  });

  final PairTimerState timer;
  final PairMatchingCopy copy;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final seconds = (timer.remainingActiveMs + 999) ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    final clock =
        '${minutes.toString().padLeft(2, '0')}:'
        '${remainder.toString().padLeft(2, '0')}';
    final label = switch (timer.mode) {
      PairTimerMode.timeoutDecision => copy.timeoutReached,
      PairTimerMode.continuedUntimed => copy.continuedUntimed,
      _ => copy.timerRemaining(clock),
    };
    return Semantics(
      key: const ValueKey<String>('pair-timer'),
      container: true,
      liveRegion: liveRegion,
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                const Icon(Icons.timer_outlined, size: 18),
                Text(label, softWrap: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
