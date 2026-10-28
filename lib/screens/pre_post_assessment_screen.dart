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
    this.responseClock,
  });

  final AssessmentUseCases useCases;
  final AssessmentStartCommand command;
  final Stopwatch? responseClock;

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
  late final Stopwatch _responseTime = widget.responseClock ?? Stopwatch();
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
          widget.useCases
              .setPresentationForeground(
                runId: widget.command.runId,
                isForeground: true,
              )
              .catchError(_showFailure),
        );
        _responseTime.start();
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _responseTime.stop();
        unawaited(
          widget.useCases
              .setPresentationForeground(
                runId: widget.command.runId,
                isForeground: false,
              )
              .catchError(_showFailure),
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
      _responseTime.reset();
      if (_lifecycleState == AppLifecycleState.resumed) {
        _responseTime.start();
      }
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
      AssessmentPhase.pre => 'แบบประเมินก่อนเรียน',
      AssessmentPhase.post => 'แบบประเมินหลังเรียน',
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
                'แบบประเมินไม่พร้อมใช้งาน งานที่บันทึกไว้ไม่ได้ถูกลบ',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('ลองอีกครั้ง')),
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
          child: const Text('จบแบบประเมิน'),
        ),
      );
    }
    final item = presentation.items[_itemIndex];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'เครื่องมือ ${presentation.run.instrumentVersion} · '
          'แบบประเมิน ${presentation.run.formVersion}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'ข้อ ${_itemIndex + 1} จาก ${presentation.items.length}',
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
        'ก่อนเรียน ${_percent(result.preOutcome.accuracy)} '
            '(${result.preOutcome.correctCount}/${result.preOutcome.sampleSize}) · '
            'หลังเรียน ${_percent(result.postOutcome.accuracy)} '
            '(${result.postOutcome.correctCount}/${result.postOutcome.sampleSize}) · '
            'เปลี่ยนแปลง ${_signedPercentagePoints(result.comparison.accuracyDelta)}',
      AssessmentComparisonMissingPair() =>
        'จะแสดงผลเปรียบเทียบเมื่อทำแบบประเมินก่อนและหลังที่ใช้เปรียบเทียบกันได้ครบแล้ว',
      AssessmentComparisonIncompatibleMetadata() =>
        'เปรียบเทียบไม่ได้ เนื่องจากข้อมูลรุ่นแบบประเมินที่กำหนดไว้ไม่ตรงกัน',
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
          'ทำแบบประเมินเสร็จแล้ว',
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

String _signedPercentagePoints(double value) {
  final rounded = (value * 100).round();
  return '${rounded >= 0 ? '+' : ''}$rounded จุดเปอร์เซ็นต์';
}
