import 'dart:async';

import 'package:flutter/material.dart';

import '../../accessibility/domain/accessibility_policy.dart';
import '../../accessibility/presentation/accessibility_scope.dart';
import '../../learning/application/current_activity_evidence.dart';
import '../../learning/application/learning_use_cases.dart';
import '../../learning/application/lesson_mode_registry.dart';
import '../../learning/domain/answer_feedback.dart';
import '../../learning/domain/hint_policy.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../learning/presentation/unified_lesson_shell.dart';
import '../../../navigation/app_routes.dart';
import '../application/adventure_mixed_review_controller.dart';
import '../application/adventure_mixed_review_prompt_catalog.dart';
import '../application/adventure_recovery_use_cases.dart';

typedef AdventureMixedReviewCompletionPageBuilder =
    Widget Function(
      BuildContext context,
      LearningSessionSummary summary,
      AdventureLearningPresentation presentation,
    );

final class AdventureMixedReviewScreen extends StatefulWidget
    implements AccessibilityModeFeedbackSurface {
  const AdventureMixedReviewScreen({
    super.key,
    required this.recovery,
    required this.catalog,
    required this.registry,
    required this.completionPageBuilder,
    this.lessonHost,
  });

  final AdventureRecoveryUseCases recovery;
  final AdventureMixedReviewPromptCatalog catalog;
  final LessonModeRegistry registry;
  final AdventureMixedReviewCompletionPageBuilder completionPageBuilder;
  final AdventureMixedReviewLessonHost? lessonHost;

  @override
  Widget withShellFeedback(Widget? feedback) =>
      AccessibilityModeFeedbackSlot(feedback: feedback, child: this);

  @override
  State<AdventureMixedReviewScreen> createState() =>
      _AdventureMixedReviewScreenState();
}

final class _AdventureMixedReviewScreenState
    extends State<AdventureMixedReviewScreen> {
  final TextEditingController _typedController = TextEditingController();
  final Stopwatch _responseStopwatch = Stopwatch();
  AdventureMixedReviewController? _controller;
  AdventureMixedReviewLessonHost? _host;
  String? _promptKey;
  bool _resultScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final injected = widget.lessonHost;
    final lifecycle = UnifiedLessonSessionLifecycleScope.maybeOf(context);
    if (injected == null && lifecycle == null) return;
    _host = injected ?? _UnifiedLessonMixedReviewHost(lifecycle!);
    final controller = AdventureMixedReviewController(
      recovery: widget.recovery,
      catalog: widget.catalog,
      registry: widget.registry,
      host: _host!,
    );
    _controller = controller;
    controller.addListener(_onControllerChanged);
    unawaited(_initialize(controller));
  }

  Future<void> _initialize(AdventureMixedReviewController controller) async {
    try {
      await controller.initialize();
    } catch (_) {
      // The controller publishes a typed failure and the retry-safe UI below.
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final controller = _controller!;
    final prompt = controller.prompt;
    final key = prompt == null
        ? null
        : '${controller.occurrenceOrdinal}:${prompt.identity.id}:'
              '${prompt.mode.name}:${prompt.promptVariant}';
    if (key != null && key != _promptKey) {
      _promptKey = key;
      _typedController.clear();
      _responseStopwatch
        ..reset()
        ..start();
    }
    setState(() {});
    if (controller.phase == AdventureMixedReviewPhase.completed) {
      _scheduleResult(controller);
    }
  }

  void _scheduleResult(AdventureMixedReviewController controller) {
    if (_resultScheduled || controller.summary == null) return;
    _resultScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_presentResult(controller));
    });
  }

  Future<void> _presentResult(AdventureMixedReviewController controller) async {
    final summary = controller.summary;
    final run = widget.recovery.currentRun;
    if (summary == null || run == null || !mounted) {
      _resultScheduled = false;
      return;
    }
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      unawaited(
        AppNavigator.pushPage<void>(
          context,
          AppPage<void>(
            name: 'learning/mixed-review-result',
            builder: (context) => _SummaryPresentedBoundary(
              onPresented: controller.acknowledgeSummaryPresented,
              child: widget.completionPageBuilder(
                context,
                summary,
                run.presentation,
              ),
            ),
          ),
          replace: true,
        ),
      );
    } catch (_) {
      _resultScheduled = false;
    }
  }

  bool get _persistenceLocked {
    final phase = _controller?.phase;
    return phase == AdventureMixedReviewPhase.savingFlashcard ||
        phase == AdventureMixedReviewPhase.savingEvidence ||
        phase == AdventureMixedReviewPhase.evidenceRetryRequired ||
        phase == AdventureMixedReviewPhase.savingSkip ||
        phase == AdventureMixedReviewPhase.skipRetryRequired ||
        phase == AdventureMixedReviewPhase.completing ||
        phase == AdventureMixedReviewPhase.completionRetryRequired;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope(
      canPop: controller?.phase == AdventureMixedReviewPhase.completed,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_persistenceLocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('กำลังบันทึกความคืบหน้า กรุณาลองอีกครั้ง'),
            ),
          );
          return;
        }
        unawaited(_confirmExit());
      },
      child: AccessibilityModeScaffold(
        appBar: AppBar(
          title: Text(
            widget.recovery.currentRun?.presentation ==
                    AdventureLearningPresentation.adventure
                ? 'ภารกิจทบทวน'
                : 'ทบทวนคำศัพท์',
          ),
        ),
        body: SafeArea(
          child: controller == null
              ? const _MixedReviewMessage(
                  icon: Icons.extension_off_outlined,
                  message: 'เปิดบทเรียนต่อไม่ได้ในขณะนี้',
                )
              : _buildBody(controller),
        ),
      ),
    );
  }

  Widget _buildBody(AdventureMixedReviewController controller) {
    if (controller.phase == AdventureMixedReviewPhase.failed) {
      return const _MixedReviewMessage(
        icon: Icons.sync_problem_outlined,
        message: 'กู้คืนบทเรียนไม่สำเร็จ ความคืบหน้าเดิมยังไม่ถูกเปลี่ยนแปลง',
      );
    }
    if (controller.phase == AdventureMixedReviewPhase.completed) {
      return const Center(child: CircularProgressIndicator());
    }
    final prompt = controller.prompt;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _QuestProgressCard(controller: controller),
                const SizedBox(height: 16),
                if (prompt == null)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...<Widget>[
                  _PromptCard(controller: controller, prompt: prompt),
                  const SizedBox(height: 16),
                  _responseArea(controller, prompt),
                  if (controller.isBusy) ...<Widget>[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(
                      key: ValueKey<String>('mixed-review-saving'),
                    ),
                  ],
                  ..._retryControls(controller),
                  if (controller.phase ==
                      AdventureMixedReviewPhase.answered) ...<Widget>[
                    if (AccessibilityModeFeedbackSlot.maybeOf(context)
                        case final feedback?) ...<Widget>[
                      const SizedBox(height: 12),
                      feedback,
                    ],
                    if (controller.supportMessage case final message?) ...[
                      const SizedBox(height: 12),
                      _SupportNotice(message: message),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey<String>('mixed-review-next'),
                      onPressed: () => _perform(controller.next),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(_nextLabel(controller)),
                    ),
                  ],
                  if (controller.canSkip) ...<Widget>[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      key: const ValueKey<String>('mixed-review-skip'),
                      onPressed: () => _perform(controller.skip),
                      icon: const Icon(Icons.skip_next_outlined),
                      label: const Text('ข้ามข้อนี้'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _responseArea(
    AdventureMixedReviewController controller,
    AdventureMixedReviewPrompt prompt,
  ) {
    final enabled = controller.canSubmit;
    if (prompt.mode == LessonMode.typedRecall) {
      return AccessibilitySemanticRegion(
        role: AccessibilitySemanticRole.responseAndInput,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              key: const ValueKey<String>('mixed-review-typed-input'),
              controller: _typedController,
              enabled: enabled,
              maxLength: 120,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                controller.noteInteraction();
                setState(() {});
              },
              onSubmitted: (_) => _submitTyped(controller),
              decoration: const InputDecoration(
                labelText: 'พิมพ์คำศัพท์ภาษาอังกฤษ',
                hintText: 'นึกจากความหมายแล้วพิมพ์คำตอบ',
                prefixIcon: Icon(Icons.keyboard_alt_outlined),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey<String>('mixed-review-submit'),
              onPressed: enabled && _typedController.text.trim().isNotEmpty
                  ? () => _submitTyped(controller)
                  : null,
              child: const Text('ตรวจคำตอบ'),
            ),
          ],
        ),
      );
    }
    if (prompt.mode == LessonMode.flashcard) {
      final revealed =
          controller.phase == AdventureMixedReviewPhase.flashcardRevealed;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (revealed)
            Card(
              key: const ValueKey<String>('mixed-review-flashcard-answer'),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  prompt.answer!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: ValueKey<String>(
              revealed
                  ? 'mixed-review-flashcard-continue'
                  : 'mixed-review-flashcard-reveal',
            ),
            onPressed: controller.isBusy
                ? null
                : revealed
                ? () => _perform(controller.continueAfterFlashcard)
                : controller.revealFlashcard,
            icon: Icon(
              revealed ? Icons.arrow_forward_rounded : Icons.visibility,
            ),
            label: Text(revealed ? 'ไปต่อ' : 'ดูคำแปล'),
          ),
        ],
      );
    }
    return AccessibilitySemanticRegion(
      role: AccessibilitySemanticRole.responseAndInput,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final option in prompt.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FilledButton.tonal(
                key: ValueKey<String>(
                  'mixed-review-option-${prompt.identity.id}-$option',
                ),
                onPressed: enabled
                    ? () => _perform(
                        () => controller.submitChoice(
                          option: option,
                          responseTimeMs: _elapsedMilliseconds,
                        ),
                      )
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: Text(option, textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _retryControls(AdventureMixedReviewController controller) {
    final phase = controller.phase;
    final (label, action) = switch (phase) {
      AdventureMixedReviewPhase.evidenceRetryRequired => (
        'ลองบันทึกคำตอบเดิมอีกครั้ง',
        controller.retryEvidence,
      ),
      AdventureMixedReviewPhase.skipRetryRequired => (
        'ลองบันทึกการข้ามอีกครั้ง',
        controller.retrySkip,
      ),
      AdventureMixedReviewPhase.completionRetryRequired => (
        'ลองจบบทเรียนอีกครั้ง',
        controller.retryCompletion,
      ),
      _ => (null, null),
    };
    if (label == null || action == null) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 12),
      _SupportNotice(
        message:
            'เชื่อมต่อการบันทึกไม่สำเร็จ คำตอบเดิมยังถูกล็อกไว้อย่างปลอดภัย',
        technical: true,
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey<String>('current-evidence-retry'),
        onPressed: () => _perform(action),
        icon: const Icon(Icons.refresh),
        label: Text(label),
      ),
    ];
  }

  String _nextLabel(AdventureMixedReviewController controller) {
    final run = widget.recovery.currentRun!;
    final originalsDone =
        run.state.currentOriginalIndex >= run.state.content.length;
    final noDueRepair = run.repairPolicy.dueRepairs.isEmpty;
    return originalsDone && noDueRepair ? 'ดูผลการเรียน' : 'ไปข้อต่อไป';
  }

  int get _elapsedMilliseconds {
    final elapsed = _responseStopwatch.elapsedMilliseconds;
    return elapsed < 0 ? 0 : elapsed;
  }

  void _submitTyped(AdventureMixedReviewController controller) {
    final response = _typedController.text;
    if (!mounted || !controller.canSubmit || response.trim().isEmpty) return;
    if (_typedController.value.composing.isValid &&
        !_typedController.value.composing.isCollapsed) return;
    unawaited(
      _perform(
        () => controller.submitTyped(
          response: response,
          responseTimeMs: _elapsedMilliseconds,
        ),
      ),
    );
  }

  Future<void> _perform(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      // Retry controls are driven by the controller's exact pending state.
    }
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ออกจากบทเรียน?'),
        content: const Text(
          'เซสชันนี้จะสิ้นสุด แต่คำตอบที่บันทึกแล้วจะยังอยู่ครบ',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('เล่นต่อ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ออกจากบทเรียน'),
          ),
        ],
      ),
    );
    if (shouldExit == true && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _typedController.dispose();
    _responseStopwatch.stop();
    super.dispose();
  }
}

final class _UnifiedLessonMixedReviewHost
    implements AdventureMixedReviewLessonHost {
  const _UnifiedLessonMixedReviewHost(this.lifecycle);

  final UnifiedLessonSessionLifecycle lifecycle;

  @override
  bool get acceptsOperations => lifecycle.acceptsOperations;

  @override
  Future<T> runRecoveryOperation<T>(Future<T> Function() operation) =>
      lifecycle.runRecoveryOperation(operation);

  @override
  Future<QuizSession> initializeSession(
    QuizSession session, {
    PendingLearningSessionClose? recoveredClose,
  }) => lifecycle.initializeSession(
    Future<QuizSession>.value(session),
    recoveredClose: recoveredClose == null ? null : () => recoveredClose,
  );

  @override
  void noteSkippedItem() => lifecycle.noteSkippedItem();

  @override
  void recordInteraction() => lifecycle.recordInteraction();

  @override
  void ownRecoveryClose(
    PendingLearningSessionClose close,
    Future<void> Function() ensureDurable,
  ) => lifecycle.ownRecoveryClose(close, ensureDurable);

  @override
  Future<AnswerRecordResult> recordCapturedEvidence(
    PendingCurrentActivityEvidence pending, {
    required AnswerFeedbackContext feedbackContext,
    required LessonModeAdapter occurrenceAdapter,
  }) async {
    final result = await lifecycle.recordCapturedEvidence(
      pending,
      feedbackContext: feedbackContext,
      occurrenceAdapter: occurrenceAdapter,
    );
    lifecycle.resetHintsAfterCommittedEvidence();
    return result;
  }

  @override
  HintUsageSnapshot snapshotHintUsage() => lifecycle.snapshotHintUsage();

  @override
  Future<LearningSessionSummary> completeRecovery(
    PendingLearningSessionClose close,
  ) => lifecycle.completeRecovery(close);
}

final class _QuestProgressCard extends StatelessWidget {
  const _QuestProgressCard({required this.controller});

  final AdventureMixedReviewController controller;

  @override
  Widget build(BuildContext context) {
    final adventure =
        controller.recovery.currentRun?.presentation ==
        AdventureLearningPresentation.adventure;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label:
          'ความคืบหน้า ${controller.completedOriginalItems} จาก ${controller.originalItemCount}',
      child: Card(
        key: const ValueKey<String>('mixed-review-context-strip'),
        color: colors.primaryContainer,
        child: _ContainerForeground(
          color: colors.onPrimaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  child: Icon(
                    adventure ? Icons.explore_rounded : Icons.school_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        adventure ? 'Playful Quest' : 'ทบทวนต่อจากเดิม',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: colors.onPrimaryContainer),
                      ),
                      Text(
                        'ผ่านแล้ว ${controller.completedOriginalItems} จาก ${controller.originalItemCount} คำ',
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: controller.progress),
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
}

final class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.controller, required this.prompt});

  final AdventureMixedReviewController controller;
  final AdventureMixedReviewPrompt prompt;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = _modeLabel(prompt.mode);
    return AccessibilitySemanticRegion(
      role: AccessibilitySemanticRole.prompt,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: _ContainerForeground(
          color: colors.onTertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: <Widget>[
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    Chip(
                      avatar: Icon(_modeIcon(prompt.mode), size: 18),
                      label: Text(label),
                    ),
                    if (controller.isRepair)
                      const Chip(
                        key: ValueKey<String>('mixed-review-repair-badge'),
                        avatar: Icon(Icons.auto_fix_high, size: 18),
                        label: Text('ทบทวนช่วยจำ'),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  prompt.promptText,
                  key: const ValueKey<String>('mixed-review-prompt'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: colors.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  prompt.word.partOfSpeech,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _instruction(prompt.mode),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _SupportNotice extends StatelessWidget {
  const _SupportNotice({required this.message, this.technical = false});

  final String message;
  final bool technical;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Card(
        key: ValueKey<String>(
          technical ? 'mixed-review-technical-notice' : 'mixed-review-support',
        ),
        color: technical ? colors.errorContainer : colors.secondaryContainer,
        child: _ContainerForeground(
          color: technical
              ? colors.onErrorContainer
              : colors.onSecondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  technical ? Icons.cloud_off_outlined : Icons.favorite_outline,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(message)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _ContainerForeground extends StatelessWidget {
  const _ContainerForeground({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: TextStyle(color: color),
    child: IconTheme.merge(
      data: IconThemeData(color: color),
      child: child,
    ),
  );
}

final class _MixedReviewMessage extends StatelessWidget {
  const _MixedReviewMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

final class _SummaryPresentedBoundary extends StatefulWidget {
  const _SummaryPresentedBoundary({
    required this.onPresented,
    required this.child,
  });

  final Future<void> Function() onPresented;
  final Widget child;

  @override
  State<_SummaryPresentedBoundary> createState() =>
      _SummaryPresentedBoundaryState();
}

final class _SummaryPresentedBoundaryState
    extends State<_SummaryPresentedBoundary> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.onPresented().catchError((_) {}));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String _modeLabel(LessonMode mode) => switch (mode) {
  LessonMode.typedRecall => 'พิมพ์จากความจำ',
  LessonMode.meaningQuiz => 'เลือกความหมาย',
  LessonMode.cloze => 'เติมคำในประโยค',
  LessonMode.definitionQuiz => 'เลือกจากคำจำกัดความ',
  LessonMode.flashcard => 'การ์ดช่วยจำ',
  _ => 'ทบทวนคำศัพท์',
};

IconData _modeIcon(LessonMode mode) => switch (mode) {
  LessonMode.typedRecall => Icons.keyboard_alt_outlined,
  LessonMode.meaningQuiz => Icons.translate_rounded,
  LessonMode.cloze => Icons.space_bar_rounded,
  LessonMode.definitionQuiz => Icons.menu_book_outlined,
  LessonMode.flashcard => Icons.style_outlined,
  _ => Icons.school_outlined,
};

String _instruction(LessonMode mode) => switch (mode) {
  LessonMode.typedRecall => 'พิมพ์คำศัพท์ที่ตรงกับความหมายนี้',
  LessonMode.meaningQuiz => 'เลือกคำตอบที่ตรงที่สุด',
  LessonMode.cloze => 'เลือกคำที่เติมประโยคให้สมบูรณ์',
  LessonMode.definitionQuiz => 'เลือกคำศัพท์ที่ตรงกับคำจำกัดความ',
  LessonMode.flashcard => 'ลองนึกความหมายก่อนเปิดดูคำตอบ',
  _ => 'เลือกคำตอบ',
};
