import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/accessibility/presentation/accessibility_scope.dart';
import 'package:vocab_learning_app/features/companion/presentation/contextual_companion_widget.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/application/pair_review_deferral.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/features/voice/presentation/route_voice_session_mixin.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import '../application/pair_matching_atomic_start.dart';
import '../application/pair_matching_session_coordinator.dart';
import '../application/pair_matching_unavailable_session.dart';
import '../application/pair_matching_source_composer.dart';
import '../application/pair_practice_replay.dart';
import '../data/drift_pair_matching_session_purpose_reader.dart';
import '../data/pair_matching_checkpoint_codec.dart';
import '../domain/pair_active_clock.dart';
import '../domain/pair_matching_engine.dart';
import '../domain/pair_matching_history_projection.dart';
import '../domain/pair_matching_launch.dart';
import '../domain/pair_matching_session_purpose.dart';
import 'pair_board_view.dart';
import 'pair_matching_result_view.dart';

/// Explicit internal composition; no production navigation or default gate is
/// changed. Every dependency uses the caller's existing canonical database.
final class PairMatchingExperienceRuntime {
  PairMatchingExperienceRuntime({
    required this.database,
    required this.learning,
    required this.currentActivityEvidence,
    required this.registry,
    required this.createController,
    required this.composer,
    required this.start,
    this.protocols,
    this.configurations,
    this.voice,
    this.reviewDeferral,
    this.features,
    this.monotonicMicros,
    this.resultReader,
    bool Function()? canStart,
  }) : canStart = canStart ?? _disabled {
    if (!identical(currentActivityEvidence.learning, learning)) {
      throw ArgumentError(
        'Pair evidence must use the composed learning authority',
      );
    }
    final registration = registry.resolve(LessonMode.matching);
    if (registration?.adapter is! MatchingModeAdapter ||
        !(registration!.adapter as MatchingModeAdapter).internalPairMatching) {
      throw ArgumentError(
        'Pair requires explicitly selected internal registration',
      );
    }
  }
  static bool _disabled() => false;
  final AppDatabase database;
  final LearningUseCases learning;
  final CurrentActivityEvidenceAdapter currentActivityEvidence;
  final LessonModeRegistry registry;
  final UnifiedLessonControllerFactory createController;
  final PairMatchingSourceComposer composer;
  final PairMatchingAtomicStartAdapter start;
  final SessionConfigurationProtocolProvider? protocols;
  final ActiveOwnerSessionConfigurationStore? configurations;
  final VoiceUseCases? voice;
  final PairReviewDeferral? reviewDeferral;
  final FeatureRegistry? features;
  final int Function()? monotonicMicros;
  final bool Function() canStart;
  final PairMatchingSessionPurposeReader? resultReader;
  LessonModeRegistration get registration =>
      registry.resolve(LessonMode.matching)!;
  DriftPairMatchingSessionPurposeReader get reader =>
      DriftPairMatchingSessionPurposeReader(database);
  Future<String> requireOwner() async {
    final owners =
        await (database.select(database.localOwners)
              ..where((row) => row.isActive.equals(true))
              ..limit(2))
            .get();
    if (owners.length != 1) throw StateError('Pair active owner unavailable');
    return owners.single.id;
  }

  bool get newStartsAllowed =>
      canStart() && (features?.isEnabled(Feature.quiz) ?? true);
  Future<SessionConfiguration> revalidate(
    SessionConfiguration configuration,
  ) async {
    final owner = await requireOwner();
    final provider = protocols;
    if (provider == null) {
      throw StateError('Pair configuration provider unavailable');
    }
    final limits = await provider.resolveForOwner(owner);
    final validated = const SessionConfigurationPolicy().revalidate(
      configuration: configuration,
      registration: registration,
      limits: limits,
      ownerId: owner,
      availablePackIdentities: const [],
    );
    if (await requireOwner() != owner) throw StateError('Pair owner changed');
    return validated;
  }
}

enum PairDecorationFailure { unavailable }

typedef PairBoardDecoration =
    Widget Function(
      BuildContext context,
      PairBoardModel model,
      Widget standardBoard,
      ValueChanged<PairDecorationFailure> reportFailure,
    );

/// Owns setup and per-session shell identity. Presentation replacement keeps
/// the exact same child/coordinator; replay alone mounts a fresh controller.
final class PairMatchingExperienceHost extends StatefulWidget {
  const PairMatchingExperienceHost({
    super.key,
    required this.runtime,
    required PairMatchingLaunchIntent this.launch,
    required PairSourceSnapshot this.source,
    required PairDensityPreferences this.preferences,
    required this.onExit,
    this.shuffleSeed = 42,
    this.onReview,
    this.decoration,
    this.canAdmitLaunch,
    this.onOwnerInvalidated,
  }) : recoveryOperation = null,
       historyReplaySource = null,
       historyReplayOperationId = null;
  const PairMatchingExperienceHost.recover({
    super.key,
    required this.runtime,
    required PairMatchingStartOperation operation,
    required this.onExit,
    this.onReview,
    this.decoration,
    this.onOwnerInvalidated,
  }) : recoveryOperation = operation,
       canAdmitLaunch = null,
       launch = null,
       source = null,
       preferences = null,
       shuffleSeed = 42,
       historyReplaySource = null,
       historyReplayOperationId = null;
  const PairMatchingExperienceHost.practiceReplay({
    super.key,
    required this.runtime,
    required PairMatchingHistoryProjection source,
    required String launchOperationId,
    required this.onExit,
    this.onReview,
    this.decoration,
    this.onOwnerInvalidated,
  }) : historyReplaySource = source,
       canAdmitLaunch = null,
       historyReplayOperationId = launchOperationId,
       recoveryOperation = null,
       launch = null,
       source = null,
       preferences = null,
       shuffleSeed = 42;
  final PairMatchingExperienceRuntime runtime;
  final PairMatchingLaunchIntent? launch;
  final PairSourceSnapshot? source;
  final PairDensityPreferences? preferences;
  final PairMatchingStartOperation? recoveryOperation;
  final PairMatchingHistoryProjection? historyReplaySource;
  final String? historyReplayOperationId;
  final int shuffleSeed;
  final VoidCallback onExit;
  final ValueChanged<List<ReviewQueueItem>>? onReview;
  final PairBoardDecoration? decoration;

  /// Captured entry validity until a new exact start operation is reserved.
  /// An accepted or uncertain start keeps its identity through later rebuilds.
  final bool Function()? canAdmitLaunch;

  /// Presentation cleanup only; canonical owner admission remains in this host.
  final VoidCallback? onOwnerInvalidated;
  @override
  State<PairMatchingExperienceHost> createState() =>
      _PairMatchingExperienceHostState();
}

final class _PairMatchingExperienceHostState
    extends State<PairMatchingExperienceHost> {
  PairMatchingStartOperation? _operation, _pendingStart;
  SessionConfiguration? _recoveredConfiguration;
  String? _recoveryOwner;
  bool _preparingRecovery = false, _recoveryBindingFailed = false;
  int _attachmentRevision = 0;
  late PairDirection _direction =
      widget.launch?.requestedDirection ?? PairDirection.enToTh;
  PairDensity? _density;
  PairTimerPreset _preset = PairTimerPreset.off;
  bool _busy = false,
      _error = false,
      _confirmCompact = false,
      _recoveryOnly = false;
  int? _setupMaximumSeconds;
  bool _loadingSetupPolicy = false;
  @override
  void initState() {
    super.initState();
    _operation = widget.recoveryOperation;
    _recoveryOnly = _operation != null;
    if (_recoveryOnly) unawaited(_prepareRecoveryBinding());
    _density = widget.preferences?.resolve(
      requested: widget.launch?.requestedDensity,
      canPrompt: true,
    );
    if (widget.historyReplaySource != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_replay());
      });
    } else if (_operation == null) {
      unawaited(_loadPreference());
      unawaited(_loadSetupPolicy());
    }
  }

  String copy(String th, String en) =>
      Localizations.localeOf(context).languageCode == 'en' ? en : th;

  Future<void> _prepareRecoveryBinding() async {
    _preparingRecovery = true;
    try {
      final owner = await widget.runtime.requireOwner();
      _recoveryOwner ??= owner;
      if (_recoveryOwner != owner) throw StateError('Pair owner changed');
      final accepted = await widget.runtime.reader.read(
        ownerId: owner,
        sessionId: _operation!.plan.learningSessionId,
      );
      if (await widget.runtime.requireOwner() != owner ||
          accepted.snapshot?.startOperation !=
              _operation!.stableSerialization) {
        throw StateError('Pair accepted recovery changed');
      }
      _recoveredConfiguration =
          PairMatchingSessionPurpose.projectConfigurationOwner(
            _operation!.configuration,
            owner,
          );
      _recoveryBindingFailed = false;
    } catch (_) {
      _recoveryBindingFailed = true;
    } finally {
      if (mounted) setState(() => _preparingRecovery = false);
    }
  }

  Future<void> _loadPreference() async {
    final store = widget.runtime.configurations;
    if (store == null) return;
    try {
      final owner = await widget.runtime.requireOwner();
      if (owner != widget.launch!.ownerId) {
        throw StateError('Pair owner changed');
      }
      final value = await store.read(ownerId: owner, mode: LessonMode.matching);
      if (!mounted || _busy || _pendingStart != null) return;
      setState(() {
        _density ??= value?.pairDensityInputs.learnerPreference;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _loadSetupPolicy() async {
    final provider = widget.runtime.protocols;
    if (provider == null) return;
    _loadingSetupPolicy = true;
    try {
      final owner = await widget.runtime.requireOwner();
      if (owner != widget.launch!.ownerId) {
        throw StateError('Pair owner changed');
      }
      final limits = await provider.resolveForOwner(owner);
      final timing = const SessionConfigurationPolicy()
          .defaultsFor(
            registration: widget.runtime.registration,
            limits: limits,
          )
          .timing;
      if (await widget.runtime.requireOwner() != owner) {
        throw StateError('Pair owner changed');
      }
      if (mounted) {
        setState(
          () => _setupMaximumSeconds =
              (timing.timedLimit ?? timing.maximumActiveEffort)?.inSeconds,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loadingSetupPolicy = false);
    }
  }

  String _sourceDescription() {
    final reasons = {
      for (final item in widget.source!.items) ...item.sourceReasons,
    };
    return [
      for (final reason in PairSourceReason.values)
        if (reasons.contains(reason))
          switch (reason) {
            PairSourceReason.dueSrs => copy('ถึงเวลาทบทวน', 'Due for review'),
            PairSourceReason.incorrectAnswer => copy(
              'คำที่เคยตอบผิด',
              'Previously missed words',
            ),
            PairSourceReason.weakness => copy(
              'คำที่ควรฝึกเพิ่ม',
              'Words needing practice',
            ),
            PairSourceReason.saved => copy('คำที่บันทึกไว้', 'Saved words'),
            PairSourceReason.newContent => copy('คำใหม่', 'New words'),
            PairSourceReason.reported => copy(
              'คำจากรายการตรวจทาน',
              'Words from review requests',
            ),
          },
    ].join(' · ');
  }

  Future<void> _start({bool acceptCompact = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final runtime = widget.runtime;
      if (_pendingStart == null) {
        if (!runtime.newStartsAllowed ||
            widget.canAdmitLaunch?.call() == false) {
          throw StateError('Pair new starts unavailable');
        }
        final original = widget.launch!;
        final owner = await runtime.requireOwner();
        if (owner != original.ownerId) throw StateError('Pair owner changed');
        final launch = PairMatchingLaunchIntent(
          ownerId: owner,
          sourceSurface: original.sourceSurface,
          sourceSnapshotRef: original.sourceSnapshotRef,
          operationId: original.operationId,
          createdAtUtc: original.createdAtUtc,
          requestedDirection: _direction,
          requestedDensity: _density,
          timerPreset: _preset,
        );
        final resolution = runtime.composer.compose(
          launch: launch,
          source: widget.source!,
          preferences: widget.preferences!,
          shuffleSeed: widget.shuffleSeed,
          canPrompt: true,
          acceptCompactFallback: acceptCompact,
        );
        if (resolution is PairPlanNeedsDensityConfirmation) {
          setState(() => _confirmCompact = true);
          return;
        }
        if (resolution is! PairPlanReady) {
          throw StateError('Pair content unavailable');
        }
        final plan = resolution.plan;
        SessionConfiguration? configuration;
        final provider = runtime.protocols;
        if (provider != null) {
          final limits = await provider.resolveForOwner(owner);
          const policy = SessionConfigurationPolicy();
          configuration = policy.validate(
            draft: policy
                .defaultsFor(registration: runtime.registration, limits: limits)
                .copyWith(
                  itemCount: plan.orderedLexicalItems.length,
                  direction: plan.direction == PairDirection.enToTh
                      ? SessionDirection.forward
                      : SessionDirection.reverse,
                ),
            registration: runtime.registration,
            limits: limits,
            ownerId: owner,
            availablePackIdentities: const [],
          );
          configuration = configuration.withPairDensityPreference(
            PairDensityPreference(
              density: plan.density,
              provenance: PairDensityProvenance.oneTimeChoice,
            ),
          );
          if (runtime.configurations != null) {
            await runtime.configurations!.saveForActiveOwner(
              configuration,
              updatedAtUtc: runtime.learning.nowUtc(),
            );
          }
        }
        if (await runtime.requireOwner() != owner ||
            widget.canAdmitLaunch?.call() == false) {
          throw StateError('Pair owner changed');
        }
        _pendingStart = PairMatchingStartOperation(
          plan: plan,
          launchOperationId: original.operationId,
          appVersion: runtime.learning.buildInfo.version,
          buildId: runtime.learning.buildInfo.buildId,
          configuration: configuration,
        );
      }
      await widget.runtime.start.startMeasured(_pendingStart!);
      if (mounted) {
        setState(() {
          _operation = _pendingStart;
          _pendingStart = null;
          _recoveryOnly = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replay() async {
    if (_busy || (_pendingStart == null && !widget.runtime.newStartsAllowed)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final runtime = widget.runtime, current = _operation;
      final owner = await runtime.requireOwner();
      _pendingStart ??=
          await PairPracticeReplay(
            reader: runtime.reader,
            start: runtime.start,
          ).prepare(
            ownerId: owner,
            sourceSessionId:
                current?.plan.learningSessionId ??
                widget.historyReplaySource!.sessionId,
            launchOperationId: current == null
                ? widget.historyReplayOperationId!
                : runtime.learning.generateId(),
            createdAtUtc: runtime.learning.nowUtc(),
            appVersion: runtime.learning.buildInfo.version,
            buildId: runtime.learning.buildInfo.buildId,
          );
      await runtime.start.startMeasured(_pendingStart!);
      if (mounted) {
        setState(() {
          _operation = _pendingStart;
          _pendingStart = null;
          _recoveryOnly = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final operation = _operation;
    if (_preparingRecovery || _recoveryBindingFailed) {
      return Scaffold(
        body: Center(
          child: _preparingRecovery
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      copy(
                        'ไม่สามารถเปิดเซสชันที่บันทึกไว้ได้',
                        'Saved session is unavailable',
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        unawaited(_prepareRecoveryBinding());
                      }),
                      child: Text(copy('ลองอีกครั้ง', 'Retry')),
                    ),
                    TextButton(
                      onPressed: widget.onExit,
                      child: Text(copy('กลับจุดเดิม', 'Return')),
                    ),
                  ],
                ),
        ),
      );
    }
    if (operation == null && widget.historyReplaySource != null) {
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(copy('ฝึกซ้ำชุดเดิม', 'Practice Replay')),
                Text(
                  copy(
                    'เป็นการฝึกเพิ่มเติม ไม่นับคะแนนเรียนหรือรางวัลซ้ำ',
                    'Additional practice does not add learning credit or rewards.',
                  ),
                ),
                if (_busy)
                  const CircularProgressIndicator()
                else
                  FilledButton(
                    onPressed:
                        widget.runtime.newStartsAllowed || _pendingStart != null
                        ? _replay
                        : null,
                    child: Text(
                      copy(
                        _error ? 'ลองเปิดชุดเดิมอีกครั้ง' : 'เริ่มฝึกซ้ำ',
                        _error
                            ? 'Retry saved session'
                            : 'Start practice replay',
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: widget.onExit,
                  child: Text(copy('กลับจุดเดิม', 'Return')),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (operation != null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: UnifiedLessonModeHost(
          key: ValueKey(
            '${operation.plan.learningSessionId}:$_attachmentRevision',
          ),
          adapter: widget.runtime.registration.adapter,
          createController: widget.runtime.createController,
          learning: widget.runtime.learning,
          feature: _recoveryOnly ? null : Feature.quiz,
          featureRegistry: widget.runtime.features,
          nowUtc: widget.runtime.learning.nowUtc,
          configuration: _recoveryOnly
              ? _recoveredConfiguration
              : operation.configuration,
          revalidateConfiguration: operation.configuration == null
              ? null
              : widget.runtime.revalidate,
          preservePreacceptedSessionOnAttachmentFailure: true,
          companionBuilder: (builderContext, controller) =>
              ContextualCompanionWidget(
                reaction: controller.companionReaction,
                languageCode: Localizations.localeOf(
                  builderContext,
                ).languageCode,
              ),
          builder: (_) => _PairSessionPane(
            runtime: widget.runtime,
            operation: operation,
            runtimeOwnerId: _recoveryOnly
                ? _recoveryOwner!
                : operation.plan.ownerId,
            onRetryAttachment: () {
              if (mounted) setState(() => _attachmentRevision++);
            },
            decoration: widget.decoration,
            onOwnerInvalidated: widget.onOwnerInvalidated,
            onExit: widget.onExit,
            onReview: widget.onReview,
            onReplay: widget.runtime.newStartsAllowed && !_busy
                ? _replay
                : null,
            replayError: _error,
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(copy('จับคู่คำ–ความหมาย', 'Match words and meanings')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                copy(
                  '${widget.source!.items.length} คำจากชุดที่เลือก',
                  '${widget.source!.items.length} words from your selected source',
                ),
              ),
              Text(
                _sourceDescription(),
                key: const ValueKey('pair-source-reason'),
              ),
              if (_density != null)
                Text(
                  copy(
                    '${_confirmCompact ? 4 : _density!.pairCount} คู่ในรอบนี้',
                    '${_confirmCompact ? 4 : _density!.pairCount} pairs this session',
                  ),
                  key: const ValueKey('pair-resolved-count'),
                ),
              const SizedBox(height: 16),
              if (widget.preferences!.guardianOverride != null)
                Text(
                  copy(
                    'จำนวนคู่ตามการตั้งค่าของผู้ปกครอง',
                    'Pair count follows guardian settings',
                  ),
                )
              else
                Wrap(
                  spacing: 12,
                  children: [
                    for (final density in PairDensity.values)
                      ChoiceChip(
                        key: ValueKey('pair-density-${density.pairCount}'),
                        label: Text(
                          copy(
                            '${density.pairCount} คู่',
                            '${density.pairCount} pairs',
                          ),
                        ),
                        selected: _density == density,
                        onSelected: _busy || _pendingStart != null
                            ? null
                            : (_) => setState(() => _density = density),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  for (final direction in PairDirection.values)
                    ChoiceChip(
                      key: ValueKey('pair-direction-${direction.name}'),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            direction == PairDirection.enToTh
                                ? 'English'
                                : 'ไทย',
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.arrow_forward, size: 18),
                          ),
                          Text(
                            direction == PairDirection.enToTh
                                ? 'ไทย'
                                : 'English',
                          ),
                        ],
                      ),
                      selected: _direction == direction,
                      onSelected: _busy || _pendingStart != null
                          ? null
                          : (_) => setState(() => _direction = direction),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  for (final preset in PairTimerPreset.values)
                    ChoiceChip(
                      key: ValueKey('pair-timer-${preset.name}'),
                      label: Text(switch (preset) {
                        PairTimerPreset.off => copy('ไม่จับเวลา', 'Timer off'),
                        PairTimerPreset.seconds60 => '60 s',
                        PairTimerPreset.seconds90 => '90 s',
                        PairTimerPreset.seconds120 => '120 s',
                      }),
                      selected: _preset == preset,
                      onSelected: _busy || _pendingStart != null
                          ? null
                          : (_) => setState(() => _preset = preset),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (_setupMaximumSeconds case final seconds?)
                Text(
                  copy(
                    'เซสชันนี้ฝึกได้สูงสุด $seconds วินาที การปิดตัวจับเวลาจับคู่ไม่เพิ่มเวลาสูงสุดนี้',
                    'Session effort is limited to $seconds seconds. Turning off the matching timer does not extend this limit.',
                  ),
                  key: const ValueKey('pair-configured-limit'),
                ),
              if (_confirmCompact) ...[
                Text(
                  copy(
                    'ชุดนี้มีคำที่พร้อม 4 คู่ ต้องการเริ่มด้วย 4 คู่หรือไม่',
                    'Four safe pairs are available. Confirm a four-pair session.',
                  ),
                ),
                FilledButton(
                  key: const ValueKey('pair-confirm-compact'),
                  onPressed: _busy ? null : () => _start(acceptCompact: true),
                  child: Text(copy('ยืนยัน 4 คู่', 'Confirm four pairs')),
                ),
              ],
              if (_error)
                Text(
                  copy(
                    'ยังเริ่มไม่ได้ โปรดลองอีกครั้งหรือเลือกกิจกรรมอื่น',
                    'Unable to start. Retry or choose another activity.',
                  ),
                  semanticsLabel: copy('ยังเริ่มไม่ได้', 'Unable to start'),
                ),
              if (!_confirmCompact)
                FilledButton(
                  key: const ValueKey('pair-start'),
                  onPressed: _busy || _loadingSetupPolicy || _density == null
                      ? null
                      : _start,
                  child: Text(
                    copy(
                      _pendingStart != null
                          ? 'ลองบันทึกอีกครั้ง'
                          : 'เริ่มจับคู่',
                      _pendingStart != null
                          ? 'Retry saved start'
                          : 'Start matching',
                    ),
                  ),
                ),
              TextButton(
                onPressed: _busy ? null : widget.onExit,
                child: Text(copy('ไว้ภายหลัง', 'Later')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _PairSessionPane extends StatefulWidget
    implements AccessibilityModeFeedbackSurface {
  const _PairSessionPane({
    required this.runtime,
    required this.operation,
    required this.runtimeOwnerId,
    required this.onExit,
    required this.onRetryAttachment,
    this.onReview,
    this.onReplay,
    this.decoration,
    this.onOwnerInvalidated,
    this.feedback,
    this.replayError = false,
  });
  final PairMatchingExperienceRuntime runtime;
  final PairMatchingStartOperation operation;
  final String runtimeOwnerId;
  final VoidCallback onExit;
  final VoidCallback onRetryAttachment;
  final ValueChanged<List<ReviewQueueItem>>? onReview;
  final Future<void> Function()? onReplay;
  final PairBoardDecoration? decoration;
  final VoidCallback? onOwnerInvalidated;
  final Widget? feedback;
  final bool replayError;
  @override
  Widget withShellFeedback(Widget? feedback) => _PairSessionPane(
    runtime: runtime,
    onRetryAttachment: onRetryAttachment,
    operation: operation,
    runtimeOwnerId: runtimeOwnerId,
    onExit: onExit,
    onReview: onReview,
    onReplay: onReplay,
    decoration: decoration,
    onOwnerInvalidated: onOwnerInvalidated,
    feedback: feedback,
    replayError: replayError,
  );
  @override
  State<_PairSessionPane> createState() => _PairSessionPaneState();
}

final class _PairSessionPaneState extends State<_PairSessionPane>
    with WidgetsBindingObserver, RouteVoiceSessionMixin<_PairSessionPane> {
  PairMatchingSessionCoordinator? _coordinator;
  UnifiedLessonSessionLifecycle? _lifecycle;
  Future<void>? _initialization;
  StreamSubscription<Object?>? _ownerSubscription;
  Timer? _displayTick;
  String? _liveOwner;
  bool _ownerInvalidated = false;
  bool _busy = true,
      _error = false,
      _audioFailed = false,
      _decorationFailed = false;
  bool _limitEnded = false;
  bool _configurationUnavailable = false, _unrecordedPending = false;
  PairMatchingUnavailableSession? _unavailableSession;
  bool _attached = false;
  int? _responseStart;
  PairMatchingHistoryProjection? _result;
  PairPauseLease? _coverPause;
  PairPauseLease? _narrationPause;
  bool _routeWantsInteraction = true;
  @override
  VoiceUseCases? get routeVoiceUseCases => widget.runtime.voice;
  String copy(String th, String en) =>
      Localizations.localeOf(context).languageCode == 'en' ? en : th;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lifecycle ??= UnifiedLessonSessionLifecycleScope.maybeOf(context);
    _initialization ??= _initialize();
  }

  Future<void> _checkOwner() async {
    final owner = await widget.runtime.requireOwner();
    if (_ownerInvalidated || owner != widget.runtimeOwnerId) {
      _liveOwner = null;
      _ownerInvalidated = true;
      widget.onOwnerInvalidated?.call();
      throw StateError('Pair owner changed');
    }
    _liveOwner = owner;
  }

  Future<void> _initialize() async {
    try {
      await _checkOwner();
      final prior = await widget.runtime.learning.loadExactActivityRecovery(
        ownerId: _liveOwner!,
        sessionId: widget.operation.plan.learningSessionId,
        activityType: 'matching',
      );
      await _checkOwner();
      if (prior?.session.state == 'abandoned') {
        final stopped = await widget.runtime.reader.read(
          ownerId: _liveOwner!,
          sessionId: widget.operation.plan.learningSessionId,
        );
        if (mounted) {
          setState(() {
            _limitEnded = true;
            _unrecordedPending = stopped.snapshot?.frozenEvidence != null;
          });
        }
        return;
      }
      _ownerSubscription = widget.runtime.database
          .select(widget.runtime.database.localOwners)
          .watch()
          .listen((rows) {
            final active = rows.where((r) => r.isActive).toList();
            final owner = active.length == 1 ? active.single.id : null;
            if (_liveOwner != owner) {
              _ownerInvalidated =
                  _ownerInvalidated || owner != widget.runtimeOwnerId;
              _liveOwner = _ownerInvalidated ? null : owner;
              if (_liveOwner == null) widget.onOwnerInvalidated?.call();
              if (mounted) setState(() => _error = _liveOwner == null);
            }
          });
      final lifecycle = _lifecycle;
      if (lifecycle == null) throw StateError('Pair route owner unavailable');
      final runtime = widget.runtime;
      final c = await (runtime.registration.adapter as MatchingModeAdapter)
          .preparePairSession(
            operation: widget.operation,
            learning: runtime.learning,
            evidence: runtime.currentActivityEvidence,
            activeOwnerId: () => _liveOwner,
            acceptsOperation: () => lifecycle.acceptsPairContinuation,
            runAdmittedOperation: lifecycle.runPairAdmittedOperation,
            runRecoveryOperation: lifecycle.runRecoveryOperation,
            completeSession: lifecycle.completeRecovery,
            ownClose: lifecycle.ownRecoveryClose,
            monotonicMicros: runtime.monotonicMicros,
          );
      _coordinator = c;
      lifecycle.reservePairSession(c);
      final recovery = await runtime.learning.loadExactActivityRecovery(
        ownerId: _liveOwner!,
        sessionId: widget.operation.plan.learningSessionId,
        activityType: 'matching',
      );
      if (recovery == null) {
        throw StateError('Pair accepted session unavailable');
      }
      await lifecycle.initializeSession(
        runtime.learning.reconstructPinnedQuizSession(
          session: recovery.session,
          content: [
            for (final item in widget.operation.plan.orderedLexicalItems)
              ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: item.wordId,
                revision: item.contentRevision,
              ),
          ],
          contentChecksumsSha256: {
            for (final item in widget.operation.plan.orderedLexicalItems)
              item.wordId: item.checksum,
          },
        ),
      );
      _attached = true;
      await _checkOwner();
      if (c.hostStatus.canRetry) await c.retryPending();
      if (c.state.complete) {
        await _finish();
      } else if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              !identical(_coordinator, c) ||
              _liveOwner == null ||
              _result != null) {
            return;
          }
          try {
            c.resumeInteraction();
          } on StateError {
            // Resume can synchronously install the existing capacity pause.
            // Other domain/lifecycle failures must not be swallowed here.
            if (!c.hostStatus.canResumeInteraction ||
                !c.timer.reasons.contains(PairPauseReason.capacity)) {
              rethrow;
            }
            setState(() {});
          }
          _responseStart = c.timer.interactiveElapsedMs;
        });
      }
      if (!mounted) return;
      _displayTick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || _busy || _result != null || _liveOwner == null) return;
        final timer = c.timer;
        if (timer.timed &&
            timer.remainingActiveMs == 0 &&
            c.timerAvailability.expire.available) {
          unawaited(_run(c.expire));
        } else {
          setState(() {});
        }
      });
    } catch (error) {
      if (error is SessionConfigurationResetRequired && !_attached) {
        _configurationUnavailable = true;
        try {
          await _lifecycle?.detachPairPresentation();
          final unavailable = _unavailableSession ??=
              PairMatchingUnavailableSession(
                operation: widget.operation,
                learning: widget.runtime.learning,
                currentActivityEvidence: widget.runtime.currentActivityEvidence,
                requireOwner: () async {
                  await _checkOwner();
                  return widget.runtimeOwnerId;
                },
              );
          final resolved = await unavailable.resolve(abandonIncomplete: false);
          _showUnavailableResolution(resolved);
        } catch (_) {
          // Exact saved-session retry remains available. Corrupt/uncertain
          // receipts never become permission to abandon or fabricate success.
        }
      }
      if (mounted) setState(() => _error = _result == null && !_limitEnded);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reconcileRoutePause();
      }
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool recoveringNarration = false,
  }) async {
    if (_busy ||
        _coordinator == null ||
        (_narrationPause != null && !recoveringNarration)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      await _checkOwner();
      await action();
      if (_coordinator!.state.complete) await _finish();
      _responseStart = _coordinator!.timer.interactiveElapsedMs;
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reconcileRoutePause();
      }
    }
  }

  PairMatchingCommand _command(
    PairTile? tile,
    String? reveal,
    String? guided,
    int? supportRevision,
    PairTimerAction? timerAction,
  ) {
    final c = _coordinator!, state = c.state, plan = c.operation.plan;
    final id =
        '${state.operationRevision}:${widget.runtime.learning.generateId()}';
    final elapsed = c.timer.interactiveElapsedMs;
    final response = elapsed == null || _responseStart == null
        ? 0
        : (elapsed - _responseStart!).clamp(0, 2147483647);
    if (tile != null) {
      return PairSelectTile(
        operationId: id,
        ownerId: plan.ownerId,
        sessionId: plan.learningSessionId,
        roundOrdinal: state.roundOrdinal,
        expectedRevision: state.operationRevision,
        tile: tile,
        responseTimeMs: response,
      );
    }
    if (reveal != null) {
      return PairRevealMapping(
        operationId: id,
        ownerId: plan.ownerId,
        sessionId: plan.learningSessionId,
        roundOrdinal: state.roundOrdinal,
        expectedRevision: state.operationRevision,
        wordId: reveal,
      );
    }
    if (guided != null) {
      return PairConfirmGuidedMapping(
        operationId: id,
        ownerId: plan.ownerId,
        sessionId: plan.learningSessionId,
        roundOrdinal: state.roundOrdinal,
        expectedRevision: state.operationRevision,
        wordId: guided,
        shownSupportRevision: supportRevision!,
        responseTimeMs: response,
      );
    }
    return PairTimerDecision(
      operationId: id,
      ownerId: plan.ownerId,
      sessionId: plan.learningSessionId,
      roundOrdinal: state.roundOrdinal,
      expectedRevision: state.operationRevision,
      action: timerAction!,
    );
  }

  Future<void> _finish() async {
    final c = _coordinator!;
    await c.finish();
    await _checkOwner();
    final purpose = await (widget.runtime.resultReader ?? widget.runtime.reader)
        .read(
          ownerId: _liveOwner!,
          sessionId: c.operation.plan.learningSessionId,
        );
    await _checkOwner();
    final snapshot = purpose.snapshot;
    if (snapshot == null || snapshot.terminal?.acknowledged != true) {
      throw StateError('Pair result receipt unavailable');
    }
    if (!mounted) return;
    setState(() => _result = PairMatchingHistoryProjection(snapshot));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _result == null) return;
      unawaited(_acknowledgeResult());
    });
  }

  Future<void> _endAtConfigurationLimit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      await _checkOwner();
      await _lifecycle!.endPairAtConfigurationLimit();
      await _checkOwner();
      if (_coordinator!.state.complete) {
        await _finish();
      } else if (mounted) {
        setState(() => _limitEnded = true);
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showUnavailableResolution(PairAcceptedDispositionSnapshot resolved) {
    if (!mounted) return;
    final snapshot = PairMatchingCheckpointCodec.decode(
      resolved.recovery.checkpoint!.state,
    );
    if (resolved.kind == PairAcceptedDispositionKind.stopped) {
      setState(() {
        _limitEnded = true;
        _unrecordedPending = snapshot.frozenEvidence != null;
      });
    } else if (resolved.kind == PairAcceptedDispositionKind.complete &&
        snapshot.terminal?.acknowledged == true) {
      setState(() {
        _result = PairMatchingHistoryProjection(snapshot);
        _error = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _result != null) unawaited(_acknowledgeResult());
      });
    }
  }

  Future<void> _disposeUnavailable() async {
    if (_busy || !_configurationUnavailable || _unavailableSession == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      await _checkOwner();
      final result = await _unavailableSession!.resolve(
        abandonIncomplete: true,
      );
      _showUnavailableResolution(result);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryAttachment() async {
    if (_busy || _attached) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      await _checkOwner();
      await _lifecycle?.detachPairPresentation();
      if (mounted) widget.onRetryAttachment();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = true;
        });
      }
    }
  }

  Widget _timerActionButton(
    PairMatchingSessionCoordinator c,
    PairTimerAction action,
  ) {
    final choices = c.timerAvailability;
    final available = switch (action) {
      PairTimerAction.continueUntimed => choices.continueUntimed.available,
      PairTimerAction.extend => choices.extend.available,
      _ => choices.restart.available,
    };
    final VoidCallback? press = _busy || !available
        ? null
        : () =>
              _run(() => c.dispatch(_command(null, null, null, null, action)));
    final label = Text(switch (action) {
      PairTimerAction.continueUntimed => copy(
        'ทำต่อโดยไม่จับเวลา',
        'Continue untimed',
      ),
      PairTimerAction.extend => copy('เพิ่ม 30 วินาที', 'Add 30 seconds'),
      _ => copy('เริ่มรอบใหม่ด้วยคำชุดเดิม', 'Restart this set'),
    });
    final key = ValueKey('pair-timer-action-${action.name}');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: action == PairTimerAction.continueUntimed
          ? FilledButton(
              key: key,
              onPressed: press,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: label,
            )
          : OutlinedButton(
              key: key,
              onPressed: press,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: label,
            ),
    );
  }

  Future<void> _acknowledgeResult() async {
    try {
      await _checkOwner();
      final unavailable = _unavailableSession;
      if (unavailable == null) {
        await _coordinator!.markSummaryPresented();
      } else {
        await unavailable.markPresented();
      }
      if (mounted) setState(() => _error = false);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _review() async {
    final unavailable = _unavailableSession;
    if (unavailable != null) {
      if (_busy) return;
      setState(() => _busy = true);
      try {
        await _checkOwner();
        final adapter = widget.runtime.reviewDeferral;
        final rows = adapter == null
            ? <ReviewQueueItem>[]
            : await unavailable.deferredReview(adapter);
        if (mounted) widget.onReview?.call(rows);
      } catch (_) {
        if (mounted) setState(() => _error = true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    await _run(() async {
      final adapter = widget.runtime.reviewDeferral;
      final rows = adapter == null
          ? <ReviewQueueItem>[]
          : await _coordinator!.deferredReview(adapter);
      if (mounted) widget.onReview?.call(rows);
    });
  }

  Future<void> _pronounce(PairTile tile) async {
    final session = routeVoiceSession, c = _coordinator;
    if (_busy || session == null || c == null) return;
    final item = widget.operation.plan.orderedLexicalItems.singleWhere(
      (i) => i.wordId == tile.wordId,
    );
    final english =
        (widget.operation.plan.direction == PairDirection.enToTh) ==
        (tile.side == PairTileSide.prompt);
    await _run(() async {
      final pause = _narrationPause = c.pause(PairPauseReason.narration);
      var playbackEnded = true;
      try {
        await c.flush();
        await session.speakUntilCompleted(
          VoiceRequest.create(
            text: english ? item.spelling : item.meaning,
            language: english ? 'en' : 'th',
            voiceId: 'default',
            speed: 1,
            contentId: const Uuid().v4(),
            contentType: 'pairPronunciation',
            mode: VoiceMode.practice,
            localOnly: true,
          ),
        );
      } on VoiceFailure catch (error) {
        playbackEnded =
            error.category != VoiceFailureCategory.cleanupIncomplete;
        if (mounted) setState(() => _audioFailed = true);
      } finally {
        if (playbackEnded && mounted && _liveOwner != null) {
          c.releasePause(pause);
          if (identical(_narrationPause, pause)) _narrationPause = null;
        }
      }
    });
  }

  Future<void> _recoverNarrationStop() async {
    final session = routeVoiceSession, pause = _narrationPause;
    if (session == null || !session.isCurrent || pause == null) return;
    await _run(() async {
      await session.stop();
      await _checkOwner();
      // A stale handle's stop deliberately does nothing. Only the still-current
      // route can attest that this stop completed for its playback ownership.
      if (!session.isCurrent) {
        throw StateError('Voice route changed during stop');
      }
      _coordinator!.releasePause(pause);
      if (identical(_narrationPause, pause)) _narrationPause = null;
    }, recoveringNarration: true);
  }

  @override
  Future<void> onVoiceRouteCovered() async {
    _routeWantsInteraction = false;
    final c = _coordinator;
    if (!_attached || c == null || _liveOwner == null) return;
    _coverPause ??= c.pause(PairPauseReason.boardUnavailable);
    if (!_busy) await c.flush();
  }

  @override
  Future<void> onVoiceRouteResumed() async {
    _routeWantsInteraction = true;
    _reconcileRoutePause();
  }

  void _reconcileRoutePause() {
    final c = _coordinator, pause = _coverPause;
    if (!mounted ||
        !_routeWantsInteraction ||
        !_attached ||
        c == null ||
        pause == null ||
        _busy ||
        _liveOwner == null) {
      return;
    }
    c.releasePause(pause);
    _coverPause = null;
  }

  @override
  void dispose() {
    _displayTick?.cancel();
    _unavailableSession?.dispose();
    final handoff = _lifecycle?.detachPairPresentation();
    if (handoff == null) {
      unawaited(_ownerSubscription?.cancel());
    } else {
      unawaited(
        handoff.then<void>(
          (_) => _ownerSubscription?.cancel(),
          onError: (Object _, StackTrace _) => _ownerSubscription?.cancel(),
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _coordinator;
    if (_limitEnded) {
      return Scaffold(
        body: Center(
          child: Padding(
            key: const ValueKey('pair-incomplete-ended'),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  copy(
                    'รอบนี้จบแล้วโดยยังจับคู่ไม่ครบ เก็บคำตอบที่บันทึกแล้วไว้ในระบบ',
                    'This session ended before all pairs were matched. Saved answers are retained.',
                  ),
                ),
                if (_unrecordedPending)
                  Text(
                    copy(
                      'คำตอบที่ค้างยังไม่ได้บันทึก และจะไม่ถูกส่งภายหลัง',
                      'The pending answer was not recorded and will not be submitted later.',
                    ),
                  ),
                TextButton(
                  onPressed: widget.onExit,
                  child: Text(copy('กลับจุดเดิม', 'Return')),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_lifecycle?.pairConfigurationLimitReached == true &&
        c != null &&
        _result == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  copy(
                    'ถึงเวลาสูงสุดของเซสชันแล้ว',
                    'Session effort limit reached',
                  ),
                ),
                Text(
                  copy(
                    'ตัวจับเวลาจับคู่ไม่เพิ่มเวลาสูงสุดของเซสชัน คำตอบที่รับไว้จะถูกบันทึกก่อนจบรอบ',
                    'The matching timer does not extend the session limit. Accepted answers will be saved before ending.',
                  ),
                ),
                if (_error)
                  Text(
                    copy(
                      'ยังยืนยันการจบไม่ได้ ลองอีกครั้ง',
                      'Ending is not yet confirmed. Retry.',
                    ),
                  ),
                FilledButton(
                  key: const ValueKey('pair-end-at-limit'),
                  onPressed: _busy ? null : _endAtConfigurationLimit,
                  child: Text(copy('บันทึกและจบรอบ', 'Save and end session')),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if ((c == null || !_attached) && _result == null) {
      return Center(
        child: _error
            ? SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      copy(
                        'เปิดชุดเดิมไม่ได้ โปรดลองอีกครั้ง',
                        'Unable to open the saved session.',
                      ),
                    ),
                    FilledButton(
                      key: const ValueKey('pair-retry-attachment'),
                      onPressed: _busy ? null : _retryAttachment,
                      child: Text(
                        copy('ลองเปิดชุดเดิมอีกครั้ง', 'Retry saved session'),
                      ),
                    ),
                    if (_configurationUnavailable &&
                        _unavailableSession != null) ...[
                      Text(
                        copy(
                          'การตั้งค่าเดิมใช้ต่อไม่ได้ คุณเลือกจบรอบนี้โดยเก็บคำตอบที่บันทึกแล้วได้',
                          'These saved settings are no longer available. You can end this session and retain recorded answers.',
                        ),
                      ),
                      OutlinedButton(
                        key: const ValueKey('pair-dispose-unavailable'),
                        onPressed: _busy ? null : _disposeUnavailable,
                        child: Text(
                          copy(
                            'จบรอบที่เปิดต่อไม่ได้',
                            'End unavailable session',
                          ),
                        ),
                      ),
                    ],
                    TextButton(
                      onPressed: _busy ? null : widget.onExit,
                      child: Text(copy('กลับจุดเดิม', 'Return')),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      );
    }
    final result = _result;
    if (result != null) {
      return Scaffold(
        key: const ValueKey('pair-result'),
        appBar: AppBar(title: Text(copy('จับคู่ครบแล้ว', 'Matching complete'))),
        body: Column(
          children: [
            if (_error || widget.replayError)
              Text(
                copy(
                  'ยังบันทึกไม่ได้ คำตอบของคุณยังอยู่',
                  'Unable to save. Your answers are retained.',
                ),
              ),
            if (_error)
              TextButton(
                onPressed: _acknowledgeResult,
                child: Text(copy('ลองอีกครั้ง', 'Retry')),
              ),
            Expanded(
              child: PairMatchingResultView(
                result: result,
                locale: Localizations.localeOf(context),
                onReturn: widget.onExit,
                onPracticeReplay: widget.onReplay,
                onReview:
                    widget.onReview == null ||
                        widget.runtime.reviewDeferral == null
                    ? null
                    : _review,
              ),
            ),
          ],
        ),
      );
    }
    final timer = c!.timer;
    final status = c.hostStatus;
    final model = PairBoardModel(
      state: c.state,
      timer: timer,
      busy:
          _busy ||
          _narrationPause != null ||
          !status.canDispatch ||
          timer.mode == PairTimerMode.timeoutDecision,
      audioAvailable: widget.runtime.voice != null && !_audioFailed,
      audioFallback: _narrationPause != null && !_busy
          ? copy(
              'ยังยืนยันการหยุดเสียงไม่ได้ ลองหยุดเสียงอีกครั้ง',
              'Audio stop is unconfirmed. Retry stopping audio.',
            )
          : widget.runtime.voice == null || _audioFailed
          ? copy(
              'ใช้ข้อความที่แสดงเพื่อฝึกต่อได้',
              'Continue using the visible text.',
            )
          : null,
      statusMessage: _error
          ? copy(
              'ยังบันทึกไม่ได้ คำตอบของคุณยังอยู่',
              'Unable to save. Your answers are retained.',
            )
          : null,
    );
    final board = PairBoardView(
      model: model,
      shellFeedback: widget.feedback,
      onSelectTile: (tile) =>
          _run(() => c.dispatch(_command(tile, null, null, null, null))),
      onRevealMapping: (id) =>
          _run(() => c.dispatch(_command(null, id, null, null, null))),
      onConfirmGuidedMapping: (id, revision) =>
          _run(() => c.dispatch(_command(null, null, id, revision, null))),
      onPronounce: _pronounce,
    );
    Widget presentation = board;
    final decoration = widget.decoration;
    if (decoration != null && !_decorationFailed) {
      try {
        presentation = decoration(context, model, board, (_) {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _decorationFailed = true);
          });
        });
      } catch (_) {
        _decorationFailed = true;
        presentation = board;
      }
    }
    final timeout =
        timer.mode == PairTimerMode.timeoutDecision ||
        timer.reasons.contains(PairPauseReason.capacity) ||
        timer.reasons.contains(PairPauseReason.clockFault);
    return Scaffold(
      appBar: AppBar(
        title: Text(copy('จับคู่คำ–ความหมาย', 'Match words and meanings')),
      ),
      body: Column(
        children: [
          if (_narrationPause != null && !_busy)
            FilledButton(
              key: const ValueKey('pair-retry-audio-stop'),
              onPressed: _recoverNarrationStop,
              child: Text(
                copy('หยุดเสียงแล้วทำต่อ', 'Stop audio and continue'),
              ),
            ),
          if (_error &&
              !status.unavailable &&
              status.recovery != PairHostRecovery.none)
            FilledButton(
              key: const ValueKey('pair-retry'),
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      if (c.hostStatus.recovery ==
                          PairHostRecovery.retryPending) {
                        await c.retryPending();
                      }
                      // _run finishes a completed board and authenticates its
                      // result before any post-render presentation receipt.
                    }),
              child: Text(copy('ลองบันทึกอีกครั้ง', 'Retry saving')),
            ),
          if (timeout)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      copy(
                        'ยังไม่ทันเป้าหมาย แต่ทำต่อได้',
                        'Time target reached. You can continue.',
                      ),
                    ),
                  ),
                  Text(
                    copy(
                      'จับคู่สำเร็จแล้ว ${c.state.matchedWordIds.length} จาก ${c.state.plan.orderedLexicalItems.length} คู่',
                      '${c.state.matchedWordIds.length} of ${c.state.plan.orderedLexicalItems.length} pairs matched',
                    ),
                  ),
                  for (final action in [
                    PairTimerAction.continueUntimed,
                    PairTimerAction.extend,
                    PairTimerAction.restart,
                  ])
                    _timerActionButton(c, action),
                  Text(
                    copy(
                      timer.extensionUsed
                          ? 'ใช้การเพิ่มเวลาแล้ว'
                          : 'เพิ่มเวลาได้ 1 ครั้ง',
                      timer.extensionUsed
                          ? 'Extension already used'
                          : 'One extension available',
                    ),
                  ),
                  Text(
                    copy(
                      'สลับตำแหน่งใหม่ แต่ประวัติรอบนี้ยังอยู่',
                      'Restart reshuffles positions and retains this session’s history.',
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(child: presentation),
        ],
      ),
    );
  }
}
