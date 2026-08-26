import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../application/lesson_mode_registry.dart';
import '../application/session_configuration_policy.dart';
import '../domain/lesson_mode.dart';
import '../domain/session_configuration.dart';

final class SessionConfigurationPackOption {
  const SessionConfigurationPackOption({
    required this.identity,
    required this.label,
  });

  final ContentIdentity identity;
  final String label;
}

enum SessionConfigurationRecoveryDecision { resume, discard }

Future<SessionConfigurationRecoveryDecision?>
showSessionConfigurationRecoveryPrompt({
  required BuildContext context,
  bool canResume = true,
  required bool canDiscard,
}) => showDialog<SessionConfigurationRecoveryDecision>(
  context: context,
  builder: (context) => AlertDialog(
    key: const ValueKey('session-configuration-recovery-prompt'),
    title: const Text('Saved session found'),
    content: Text(
      canResume
          ? 'Resume with the configuration pinned to that session, or '
                'discard the unfinished session before using a new '
                'configuration.'
          : 'This older unfinished session has no pinned configuration. '
                'Discard it before using a configured session.',
    ),
    actions: <Widget>[
      if (canResume)
        TextButton(
          key: const ValueKey('session-config-recovery-resume'),
          onPressed: () => Navigator.of(
            context,
          ).pop(SessionConfigurationRecoveryDecision.resume),
          child: const Text('Resume saved session'),
        ),
      if (canDiscard)
        FilledButton(
          key: const ValueKey('session-config-recovery-discard'),
          onPressed: () => Navigator.of(
            context,
          ).pop(SessionConfigurationRecoveryDecision.discard),
          child: const Text('Discard and start new'),
        ),
    ],
  ),
);

class SessionConfigurationResetPrompt extends StatelessWidget {
  const SessionConfigurationResetPrompt({
    super.key,
    required this.error,
    required this.onReset,
    this.buttonLabel = 'Reset configuration',
  });

  final SessionConfigurationResetRequired error;
  final VoidCallback onReset;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('session-configuration-reset-prompt'),
    container: true,
    liveRegion: true,
    label: 'Session configuration must be reset',
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            error.promptTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(error.promptMessage),
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('session-config-reset'),
            onPressed: onReset,
            child: Text(buttonLabel),
          ),
        ],
      ),
    ),
  );
}

Future<SessionConfiguration?> showSessionConfigurationSheet({
  required BuildContext context,
  required LessonModeRegistration registration,
  required SessionConfigurationPolicy policy,
  required SessionConfigurationProtocolLimits limits,
  required String ownerId,
  required List<SessionConfigurationPackOption> packs,
  SessionConfiguration? initialConfiguration,
  SessionConfigurationResetRequired? initialResetRequired,
  bool initialResetCanUseDefaults = true,
}) => showModalBottomSheet<SessionConfiguration>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => SessionConfigurationSheet(
    registration: registration,
    policy: policy,
    limits: limits,
    ownerId: ownerId,
    packs: packs,
    initialConfiguration: initialConfiguration,
    initialResetRequired: initialResetRequired,
    initialResetCanUseDefaults: initialResetCanUseDefaults,
  ),
);

class SessionConfigurationSheet extends StatefulWidget {
  const SessionConfigurationSheet({
    super.key,
    required this.registration,
    required this.policy,
    required this.limits,
    required this.ownerId,
    required this.packs,
    this.initialConfiguration,
    this.initialResetRequired,
    this.initialResetCanUseDefaults = true,
  });

  final LessonModeRegistration registration;
  final SessionConfigurationPolicy policy;
  final SessionConfigurationProtocolLimits limits;
  final String ownerId;
  final List<SessionConfigurationPackOption> packs;
  final SessionConfiguration? initialConfiguration;
  final SessionConfigurationResetRequired? initialResetRequired;
  final bool initialResetCanUseDefaults;

  @override
  State<SessionConfigurationSheet> createState() =>
      _SessionConfigurationSheetState();
}

class _SessionConfigurationSheetState extends State<SessionConfigurationSheet> {
  late SessionConfigurationCapabilities _capabilities;
  late SessionConfigurationDraft _draft;
  late final TextEditingController _itemCount;
  late final TextEditingController _timeLimitSeconds;
  SessionConfigurationResetRequired? _resetRequired;
  bool _submitting = false;

  List<ContentIdentity> get _availablePackIdentities =>
      widget.packs.map((pack) => pack.identity).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _capabilities = const SessionConfigurationCapabilities(
      minimumItemCount: 1,
      maximumItemCount: 1,
      defaultItemCount: 1,
      directions: <SessionDirection>{SessionDirection.forward},
      difficulties: <SessionDifficulty>{SessionDifficulty.standard},
      maximumHintBudget: 0,
      supportsTimed: true,
      supportsUntimedAlternative: false,
      supportsPackSelection: false,
    );
    _draft = const SessionConfigurationDraft(
      itemCount: 1,
      direction: SessionDirection.forward,
      difficulty: SessionDifficulty.standard,
      hintBudget: 0,
      timing: SessionTiming.timed(Duration(minutes: 10)),
    );
    _resetRequired = widget.initialResetRequired;
    try {
      final adapter = widget.registration.adapter;
      if (adapter is! SessionConfigurableLessonModeAdapter) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.unsupportedOption,
        );
      }
      _capabilities = adapter.sessionConfigurationCapabilities;
      _draft = widget.policy.defaultsFor(
        registration: widget.registration,
        limits: widget.limits,
      );
      if (widget.limits.pinnedPackIdentities.isNotEmpty &&
          widget.packs.isNotEmpty) {
        _draft = _draft.copyWith(packIdentity: widget.packs.first.identity);
      }
      final initial = widget.initialConfiguration;
      if (_resetRequired == null && initial != null) {
        _draft = widget.policy
            .revalidate(
              configuration: initial,
              registration: widget.registration,
              limits: widget.limits,
              ownerId: widget.ownerId,
              availablePackIdentities: _availablePackIdentities,
            )
            .draft;
      }
    } on SessionConfigurationResetRequired catch (error) {
      _resetRequired = error;
    }
    _itemCount = TextEditingController(text: '${_draft.itemCount}');
    _timeLimitSeconds = TextEditingController(
      text: '${_draft.timing.timedLimit?.inSeconds ?? 600}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final reset = _resetRequired;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Configure ${widget.registration.mode.id} session',
      child: Material(
        key: const ValueKey('session-configuration-sheet'),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: reset == null ? _buildForm(context) : _buildReset(reset),
          ),
        ),
      ),
    );
  }

  Widget _buildReset(SessionConfigurationResetRequired reset) =>
      SessionConfigurationResetPrompt(
        error: reset,
        onReset: widget.initialResetCanUseDefaults
            ? _resetDefaults
            : () => Navigator.of(context).maybePop(),
        buttonLabel: widget.initialResetCanUseDefaults
            ? 'Reset configuration'
            : 'Close configuration',
      );

  Widget _buildForm(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Session configuration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Semantics(
            button: true,
            label: 'Close session configuration',
            child: ExcludeSemantics(
              child: IconButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('session-item-count'),
        controller: _itemCount,
        enabled: !_submitting,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          labelText: 'Item count',
          helperText:
              '${widget.limits.minimumItemCount}–${widget.limits.maximumItemCount} items; protocol limits apply',
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<SessionDirection>(
        key: const ValueKey('session-direction'),
        initialValue: _draft.direction,
        decoration: const InputDecoration(labelText: 'Direction'),
        items: <DropdownMenuItem<SessionDirection>>[
          for (final value in _capabilities.directions)
            DropdownMenuItem(value: value, child: Text(_directionLabel(value))),
        ],
        onChanged: _submitting
            ? null
            : (value) {
                if (value != null) {
                  setState(() => _draft = _draft.copyWith(direction: value));
                }
              },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<SessionDifficulty>(
        key: const ValueKey('session-difficulty'),
        initialValue: _draft.difficulty,
        decoration: const InputDecoration(labelText: 'Difficulty'),
        items: <DropdownMenuItem<SessionDifficulty>>[
          for (final value in _capabilities.difficulties)
            DropdownMenuItem(
              value: value,
              child: Text(_difficultyLabel(value)),
            ),
        ],
        onChanged: _submitting
            ? null
            : (value) {
                if (value != null) {
                  setState(() => _draft = _draft.copyWith(difficulty: value));
                }
              },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        key: const ValueKey('session-hint-budget'),
        initialValue: _draft.hintBudget,
        decoration: const InputDecoration(labelText: 'Hint budget'),
        items: <DropdownMenuItem<int>>[
          for (
            var value = 0;
            value <=
                _capabilities.maximumHintBudget.clamp(
                  0,
                  widget.limits.maximumHintBudget,
                );
            value += 1
          )
            DropdownMenuItem(value: value, child: Text('$value')),
        ],
        onChanged: _submitting
            ? null
            : (value) {
                if (value != null) {
                  setState(() => _draft = _draft.copyWith(hintBudget: value));
                }
              },
      ),
      const SizedBox(height: 12),
      Text('Timing', style: Theme.of(context).textTheme.titleMedium),
      RadioGroup<SessionTimingKind>(
        groupValue: _draft.timing.kind,
        onChanged: (value) {
          if (!_submitting) _setTiming(value);
        },
        child: Column(
          children: <Widget>[
            const RadioListTile<SessionTimingKind>(
              key: ValueKey('session-timing-timed'),
              value: SessionTimingKind.timed,
              title: Text('Timed'),
              subtitle: Text('Uses the bounded protocol time limit'),
            ),
            if (_capabilities.supportsUntimedAlternative &&
                widget.limits.allowsUntimedAlternative)
              const RadioListTile<SessionTimingKind>(
                key: ValueKey('session-timing-untimed'),
                value: SessionTimingKind.untimedAlternative,
                title: Text('Untimed accessibility alternative'),
                subtitle: Text('No countdown; active effort remains bounded'),
              ),
          ],
        ),
      ),
      if (_draft.timing.kind == SessionTimingKind.timed) ...<Widget>[
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('session-time-limit-seconds'),
          controller: _timeLimitSeconds,
          enabled: !_submitting,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: 'Time limit in seconds',
            helperText:
                '${widget.limits.minimumTimedSeconds}–'
                '${widget.limits.maximumTimedSeconds} seconds; '
                'protocol limits apply',
          ),
        ),
      ],
      if (_capabilities.supportsPackSelection &&
          widget.packs.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        DropdownButtonFormField<ContentIdentity>(
          key: const ValueKey('session-pack'),
          initialValue: _draft.packIdentity,
          decoration: const InputDecoration(labelText: 'Learning pack'),
          items: <DropdownMenuItem<ContentIdentity>>[
            for (final pack in widget.packs)
              DropdownMenuItem(value: pack.identity, child: Text(pack.label)),
          ],
          onChanged: _submitting
              ? null
              : (value) {
                  if (value != null) {
                    setState(
                      () => _draft = _draft.copyWith(packIdentity: value),
                    );
                  }
                },
        ),
      ] else if (_capabilities.supportsPackSelection) ...<Widget>[
        const SizedBox(height: 12),
        const InputDecorator(
          key: ValueKey('session-pack'),
          decoration: InputDecoration(labelText: 'Learning pack'),
          child: Text('Local vocabulary library'),
        ),
      ],
      const SizedBox(height: 24),
      FilledButton.icon(
        key: const ValueKey('session-config-start'),
        onPressed: _submitting ? null : _submit,
        icon: const Icon(Icons.play_arrow),
        label: Text(_submitting ? 'Starting…' : 'Start session'),
      ),
    ],
  );

  void _setTiming(SessionTimingKind? kind) {
    if (kind == null) return;
    final timing = switch (kind) {
      SessionTimingKind.timed => SessionTiming.timed(
        Duration(
          seconds:
              int.tryParse(_timeLimitSeconds.text) ??
              widget.limits.maximumTimedSeconds.clamp(60, 600),
        ),
      ),
      SessionTimingKind.untimedAlternative => SessionTiming.untimedAlternative(
        maximumActiveEffort: Duration(
          seconds: widget.limits.maximumUntimedActiveEffortSeconds,
        ),
      ),
    };
    setState(() => _draft = _draft.copyWith(timing: timing));
  }

  void _resetDefaults() {
    try {
      final defaults = widget.policy.defaultsFor(
        registration: widget.registration,
        limits: widget.limits,
      );
      setState(() {
        _resetRequired = null;
        _draft =
            widget.limits.pinnedPackIdentities.isNotEmpty &&
                widget.packs.isNotEmpty
            ? defaults.copyWith(packIdentity: widget.packs.first.identity)
            : defaults;
        _itemCount.text = '${_draft.itemCount}';
        _timeLimitSeconds.text = '${_draft.timing.timedLimit!.inSeconds}';
      });
    } on SessionConfigurationResetRequired catch (error) {
      setState(() => _resetRequired = error);
    }
  }

  void _submit() {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final requestedCount = int.tryParse(_itemCount.text) ?? 0;
      final requestedDraft = _draft.timing.kind == SessionTimingKind.timed
          ? _draft.copyWith(
              itemCount: requestedCount,
              timing: SessionTiming.timed(
                Duration(seconds: int.tryParse(_timeLimitSeconds.text) ?? 0),
              ),
            )
          : _draft.copyWith(itemCount: requestedCount);
      final configuration = widget.policy.validate(
        draft: requestedDraft,
        registration: widget.registration,
        limits: widget.limits,
        ownerId: widget.ownerId,
        availablePackIdentities: _availablePackIdentities,
      );
      Navigator.of(context).pop(configuration);
    } on SessionConfigurationResetRequired catch (error) {
      setState(() {
        _submitting = false;
        _resetRequired = error;
      });
    }
  }

  static String _directionLabel(SessionDirection value) => switch (value) {
    SessionDirection.forward => 'Prompt to answer',
    SessionDirection.reverse => 'Answer to prompt',
    SessionDirection.mixed => 'Mixed directions',
  };

  static String _difficultyLabel(SessionDifficulty value) => switch (value) {
    SessionDifficulty.supported => 'Supported',
    SessionDifficulty.standard => 'Standard',
    SessionDifficulty.challenge => 'Challenge',
  };

  @override
  void dispose() {
    _itemCount.dispose();
    _timeLimitSeconds.dispose();
    super.dispose();
  }
}
