import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/motivation_instrument.dart';
import '../domain/motivation_measurement.dart';

/// Optional measurement UI. The caller owns persistence and run lifecycle.
class MotivationMeasurementForm extends StatefulWidget {
  const MotivationMeasurementForm({
    super.key,
    required this.run,
    required this.timepoint,
    required this.onAnswer,
    required this.onComplete,
    required this.onSkip,
    required this.onWithdraw,
    this.languageCode = 'th',
  });

  final MotivationMeasurementRun run;
  final MotivationTimepoint timepoint;
  final Future<MotivationMeasurementRun> Function(
    String itemId,
    String responseCode,
  )
  onAnswer;
  final Future<void> Function() onComplete;
  final Future<void> Function() onSkip;
  final Future<void> Function() onWithdraw;
  final String languageCode;

  @override
  State<MotivationMeasurementForm> createState() =>
      _MotivationMeasurementFormState();
}

enum _Operation { answer, complete, skip, withdraw }

class _MotivationMeasurementFormState extends State<MotivationMeasurementForm> {
  late MotivationMeasurementRun _run = widget.run;
  final _questionFocus = FocusNode();
  final _questionKey = GlobalKey();
  bool _busy = false;
  bool _finished = false;
  bool _left = false;
  int _generation = 0;
  _Operation? _failure;
  (String, String)? _pendingAnswer;
  String? _selected;

  bool get _thai => widget.languageCode != 'en';
  String _text(String th, String en) => _thai ? th : en;
  List<MotivationItem> get _items => _run.instrument.itemsAt(widget.timepoint);
  bool get _active =>
      _run.state == MotivationMeasurementRunState.started && !_left;
  MotivationItem? get _currentItem {
    final answered = _run.responses.map((response) => response.itemId).toSet();
    for (final item in _items) {
      if (!answered.contains(item.id)) return item;
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant MotivationMeasurementForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.run, widget.run) &&
        oldWidget.timepoint == widget.timepoint) {
      return;
    }

    final incoming = widget.run;
    final sameRun = _sameIdentity(_run, incoming);
    if (sameRun &&
        oldWidget.timepoint == widget.timepoint &&
        incoming.state == _run.state &&
        (!_preservesAnswers(_run, incoming) ||
            incoming.responses.length == _run.responses.length)) {
      // An equivalent or older snapshot is not an acknowledgement. Preserve
      // the exact answer and retry state across ordinary parent rebuilds.
      return;
    }
    _generation++;
    // Ordinary parent rebuilds must not resurrect editable recorded answers.
    if (!sameRun ||
        _preservesAnswers(_run, incoming) ||
        incoming.state != MotivationMeasurementRunState.started) {
      _run = incoming;
    }
    if (!sameRun || oldWidget.timepoint != widget.timepoint) {
      _finished = false;
      _left = false;
    }
    _failure = null;
    _pendingAnswer = null;
    _selected = null;
    // Keep an outstanding write serialized even if its display context changed.
  }

  @override
  void dispose() {
    _generation++;
    _pendingAnswer = null;
    _questionFocus.dispose();
    super.dispose();
  }

  bool _sameIdentity(MotivationMeasurementRun a, MotivationMeasurementRun b) =>
      a.id == b.id &&
      a.ownerId == b.ownerId &&
      a.permitId == b.permitId &&
      a.assignmentId == b.assignmentId &&
      a.instrument.checksumSha256 == b.instrument.checksumSha256;

  bool _preservesAnswers(
    MotivationMeasurementRun before,
    MotivationMeasurementRun after,
  ) => before.responses.every(
    (previous) => after.responses.any(
      (next) =>
          next.itemId == previous.itemId &&
          next.responseCode == previous.responseCode,
    ),
  );

  Future<void> _answer(String itemId, String code) async {
    if (_busy || !_active || _finished || _currentItem?.id != itemId) return;
    // A failed acknowledgement can hide a committed answer. Retry its exact
    // identity; never replace it with a different answer in this form.
    if (_pendingAnswer != null && _pendingAnswer != (itemId, code)) return;
    _pendingAnswer = (itemId, code);
    _selected = code;
    final before = _run;
    await _perform(_Operation.answer, () async {
      final updated = await widget.onAnswer(itemId, code);
      if (!_sameIdentity(before, updated) ||
          !_preservesAnswers(before, updated) ||
          !updated.responses.any(
            (answer) => answer.itemId == itemId && answer.responseCode == code,
          )) {
        throw const FormatException('Unconfirmed measurement update');
      }
      return updated;
    });
  }

  Future<void> _act(_Operation operation) async {
    if (_busy || _left) return;
    if (operation == _Operation.complete &&
        (!_active || _finished || _currentItem != null)) {
      return;
    }
    final callback = switch (operation) {
      _Operation.complete => widget.onComplete,
      _Operation.skip => widget.onSkip,
      _Operation.withdraw => widget.onWithdraw,
      _Operation.answer => throw StateError('Answer requires an item'),
    };
    await _perform(operation, () async {
      await callback();
      return null;
    });
  }

  Future<void> _perform(
    _Operation operation,
    Future<MotivationMeasurementRun?> Function() action,
  ) async {
    final generation = _generation;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final updated = await action();
      if (!mounted || generation != _generation) return;
      setState(() {
        if (updated != null) _run = updated;
        if (operation == _Operation.complete) _finished = true;
        if (operation == _Operation.skip || operation == _Operation.withdraw) {
          _left = true;
        }
        _pendingAnswer = null;
        _selected = null;
      });
      if (operation == _Operation.answer) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _generation) return;
          final context = _questionKey.currentContext;
          if (context != null) {
            _questionFocus.requestFocus();
            unawaited(Scrollable.ensureVisible(context));
          }
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failure = operation);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retry() {
    if (_busy) return;
    final failure = _failure;
    if (failure == _Operation.answer) {
      final pending = _pendingAnswer;
      if (pending != null) unawaited(_answer(pending.$1, pending.$2));
    } else if (failure != null) {
      unawaited(_act(failure));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _currentItem;
    final baseline = widget.timepoint == MotivationTimepoint.baseline;
    final heading = baseline
        ? _text(
            'ช่วยบอกความรู้สึกก่อนเรียน',
            'How do you feel before learning?',
          )
        : _text(
            'ช่วยบอกความรู้สึกหลังเรียน',
            'How do you feel after learning?',
          );
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
    final status = _busy
        ? _text('กำลังบันทึก กรุณารอสักครู่', 'Saving. Please wait.')
        : _failure != null
        ? _text(
            'บันทึกไม่สำเร็จ ลองอีกครั้งได้',
            'Could not save. You can retry.',
          )
        : !_active
        ? _text(
            'แบบบันทึกนี้หยุดแล้ว คุณเรียนต่อได้',
            'This form is closed. You can continue learning.',
          )
        : _finished
        ? _text('บันทึกส่วนนี้แล้ว', 'This part has been recorded.')
        : item == null
        ? _text(
            'ตอบครบส่วนนี้แล้ว',
            'All items in this part have been answered.',
          )
        : _text('ยังตอบไม่ครบ', 'Not all items have been answered.');

    return FocusTraversalGroup(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  heading,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _text(
                  'การตอบเป็นทางเลือก ใช้ศึกษาประสบการณ์แรงจูงใจ คุณข้ามหรือถอนตัวได้ ไม่กระทบการเรียน',
                  'Taking part is optional. Responses are used to study motivation. You may skip or withdraw; this does not affect learning.',
                ),
              ),
              const SizedBox(height: 16),
              if (item != null && _active && !_finished) ...[
                Text(
                  _text(
                    'คำถาม ${_items.indexOf(item) + 1} จาก ${_items.length}',
                    'Item ${_items.indexOf(item) + 1} of ${_items.length}',
                  ),
                ),
                const SizedBox(height: 8),
                Focus(
                  key: _questionKey,
                  focusNode: _questionFocus,
                  child: Semantics(
                    header: true,
                    child: Text(
                      item.prompts[_thai ? 'th' : 'en']!,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                RadioGroup<String>(
                  groupValue: _selected,
                  onChanged: (code) {
                    if (code != null) unawaited(_answer(item.id, code));
                  },
                  child: Column(
                    children: [
                      for (final option in item.options)
                        RadioListTile<String>(
                          key: ValueKey('${item.id}-${option.code}'),
                          value: option.code,
                          enabled: !_busy && _pendingAnswer == null,
                          title: Text(option.labels[_thai ? 'th' : 'en']!),
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Semantics(
                key: const ValueKey('research-measurement-status'),
                liveRegion: true,
                label: status,
                child: ExcludeSemantics(child: Text(status)),
              ),
              if (_failure != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('research-measurement-retry'),
                  style: buttonStyle,
                  onPressed: _busy ? null : _retry,
                  child: Text(_text('ลองอีกครั้ง', 'Retry')),
                ),
              ],
              if (item == null && _active) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('research-measurement-complete'),
                  style: buttonStyle,
                  onPressed: _busy || _finished
                      ? null
                      : () => unawaited(_act(_Operation.complete)),
                  child: Text(_text('เสร็จสิ้น', 'Finish')),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('research-measurement-skip'),
                style: buttonStyle,
                onPressed: _busy || _left
                    ? null
                    : () => unawaited(_act(_Operation.skip)),
                child: Text(_text('ข้าม', 'Skip')),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('research-measurement-withdraw'),
                style: buttonStyle,
                onPressed: _busy || _left
                    ? null
                    : () => unawaited(_act(_Operation.withdraw)),
                child: Text(
                  _text('ถอนตัวจากการวิจัย', 'Withdraw from research'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
