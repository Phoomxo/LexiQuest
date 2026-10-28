import 'dart:async';

import 'package:flutter/material.dart';

import '../features/assessment/application/assessment_use_cases.dart';
import '../features/assessment/domain/assessment_models.dart';

/// G1 implementation surface. f42 owns the first assigned production entry.
final class PrePostAssessmentScreen extends StatefulWidget {
  const PrePostAssessmentScreen({
    super.key,
    required this.useCases,
    required this.command,
  });

  final AssessmentUseCases useCases;
  final AssessmentStartCommand command;

  @override
  State<PrePostAssessmentScreen> createState() =>
      _PrePostAssessmentScreenState();
}

final class _PrePostAssessmentScreenState extends State<PrePostAssessmentScreen>
    with WidgetsBindingObserver {
  AssessmentPresentation? _presentation;
  AssessmentPresentationCompletion? _completion;
  Object? _failure;
  var _itemIndex = 0;
  var _submitting = false;
  final Stopwatch _responseTime = Stopwatch();
  AppLifecycleState _lifecycleState =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _responseTime.stop();
    if (_completion == null) {
      unawaited(
        widget.useCases.setPresentationForeground(
          runId: widget.command.runId,
          isForeground: false,
        ),
      );
      unawaited(widget.useCases.detachPresentation(widget.command.runId));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (_completion != null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(
          widget.useCases.setPresentationForeground(
            runId: widget.command.runId,
            isForeground: true,
          ),
        );
        _responseTime.start();
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _responseTime.stop();
        unawaited(
          widget.useCases.setPresentationForeground(
            runId: widget.command.runId,
            isForeground: false,
          ),
        );
    }
  }

  Future<void> _load() async {
    try {
      await widget.useCases.setPresentationForeground(
        runId: widget.command.runId,
        isForeground: _lifecycleState == AppLifecycleState.resumed,
      );
      final presentation = await widget.useCases.beginPresentation(
        widget.command,
      );
      if (!mounted) {
        await widget.useCases.detachPresentation(widget.command.runId);
        return;
      }
      final next = presentation.items.indexWhere(
        (item) => !presentation.answeredItemIds.contains(item.itemId),
      );
      setState(() {
        _presentation = presentation;
        _itemIndex = next < 0 ? presentation.items.length : next;
        _failure = null;
      });
      _responseTime.reset();
      if (_lifecycleState == AppLifecycleState.resumed) {
        _responseTime.start();
      }
    } catch (error) {
      await _showFailure(error);
    }
  }

  Future<void> _submit(String response) async {
    final presentation = _presentation;
    if (presentation == null ||
        _submitting ||
        _itemIndex >= presentation.items.length) {
      return;
    }
    final item = presentation.items[_itemIndex];
    _responseTime.stop();
    setState(() => _submitting = true);
    try {
      await widget.useCases.submitPresentedResponse(
        runId: presentation.run.id,
        itemId: item.itemId,
        submittedResponse: response,
        responseTimeMs: _responseTime.elapsedMilliseconds,
      );
      final nextIndex = _itemIndex + 1;
      if (nextIndex == presentation.items.length) {
        await _finish();
        return;
      }
      if (!mounted) return;
      setState(() {
        _itemIndex = nextIndex;
        _submitting = false;
      });
      _responseTime
        ..reset()
        ..start();
    } catch (error) {
      await _showFailure(error);
    }
  }

  Future<void> _finish() async {
    try {
      final completion = await widget.useCases.completePresentation(
        widget.command.runId,
      );
      if (!mounted) return;
      setState(() {
        _completion = completion;
        _submitting = false;
      });
    } catch (error) {
      await _showFailure(error);
    }
  }

  Future<void> _showFailure(Object error) async {
    _responseTime.stop();
    try {
      await widget.useCases.setPresentationForeground(
        runId: widget.command.runId,
        isForeground: false,
      );
    } on Object {
      // The original operation failure remains the user-visible reason.
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _failure = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.command.phase) {
      AssessmentPhase.pre => 'Pre-assessment',
      AssessmentPhase.post => 'Post-assessment',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: _body(title)),
    );
  }

  Widget _body(String title) {
    if (_failure != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Assessment unavailable. Your saved work was not removed.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final completion = _completion;
    if (completion != null) return _completedBody(completion);
    final presentation = _presentation;
    if (presentation == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_itemIndex >= presentation.items.length) {
      return Center(
        child: FilledButton(
          onPressed: _submitting ? null : _finish,
          child: const Text('Finish assessment'),
        ),
      );
    }
    final item = presentation.items[_itemIndex];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Instrument ${presentation.run.instrumentVersion} · '
          'Form ${presentation.run.formVersion}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'Question ${_itemIndex + 1} of ${presentation.items.length}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(
            item.prompt,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 24),
        for (final option in item.options) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: _submitting ? null : () => _submit(option),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(option, textAlign: TextAlign.center),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_submitting) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _completedBody(AssessmentPresentationCompletion completion) {
    final comparisonMessage = switch (completion.comparison) {
      AssessmentComparisonReady result =>
        'Pre ${_percent(result.preOutcome.accuracy)} · '
            'Post ${_percent(result.postOutcome.accuracy)} · '
            'Change ${_signedPercent(result.comparison.accuracyDelta)}',
      AssessmentComparisonMissingPair() =>
        'Comparison will appear after both compatible assessments are complete.',
      AssessmentComparisonIncompatibleMetadata() =>
        'Comparison unavailable because the pinned metadata does not match.',
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Assessment complete',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(comparisonMessage, textAlign: TextAlign.center),
      ],
    );
  }
}

String _percent(double value) => '${(value * 100).round()}%';

String _signedPercent(double value) {
  final rounded = (value * 100).round();
  return '${rounded >= 0 ? '+' : ''}$rounded%';
}
