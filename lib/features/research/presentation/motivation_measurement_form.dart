import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import '../domain/motivation_instrument.dart';
import '../domain/motivation_measurement.dart';
import '../domain/motivation_measurement_repository.dart';

class MotivationMeasurementForm extends StatefulWidget {
  const MotivationMeasurementForm({
    super.key,
    required this.repository,
    required this.ownerId,
    required this.runId,
    required this.timepoint,
    required this.current,
    required this.onFinished,
    this.languageCode = 'th',
  });

  final MotivationMeasurementRepository repository;
  final String ownerId;
  final String runId;
  final MotivationTimepoint timepoint;
  final ValueListenable<bool> current;
  final Future<void> Function(MotivationMeasurementRun run) onFinished;
  final String languageCode;

  @override
  State<MotivationMeasurementForm> createState() =>
      _MotivationMeasurementFormState();
}

enum _Failure { load, answer, close, delivery }

class _MotivationMeasurementFormState extends State<MotivationMeasurementForm> {
  final _questionFocus = FocusNode();
  final _questionKey = GlobalKey();
  MotivationMeasurementRun? _run;
  MotivationResponse? _pendingAnswer;
  MotivationMeasurementClose? _pendingClose;
  MotivationMeasurementRun? _pendingDelivery;
  _Failure? _failure;
  var _generation = 0;
  var _busy = false;
  var _reloadAfterBusy = false;
  var _withdrawIntent = false;
  var _delivered = false;

  bool get _thai => widget.languageCode != 'en';
  String _text(String th, String en) => _thai ? th : en;
  bool _current(int generation) =>
      mounted && generation == _generation && widget.current.value;
  List<MotivationItem> get _items =>
      _run?.instrument.itemsAt(widget.timepoint) ?? const [];
  MotivationItem? get _item {
    final answered =
        _run?.responses.map((response) => response.itemId).toSet() ??
        const <String>{};
    for (final item in _items) {
      if (!answered.contains(item.id)) {
        return item;
      }
    }
    return null;
  }

  bool get _collecting =>
      _run?.state == MotivationMeasurementRunState.started &&
      !_withdrawIntent &&
      _pendingClose == null &&
      !_delivered;

  @override
  void initState() {
    super.initState();
    widget.current.addListener(_visibilityChanged);
    if (widget.current.value) {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant MotivationMeasurementForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.current, widget.current)) {
      oldWidget.current.removeListener(_visibilityChanged);
      widget.current.addListener(_visibilityChanged);
    }
    if (oldWidget.ownerId != widget.ownerId ||
        oldWidget.runId != widget.runId ||
        oldWidget.timepoint != widget.timepoint ||
        !identical(oldWidget.repository, widget.repository)) {
      _invalidate(bindingReplaced: true);
    } else if (!identical(oldWidget.current, widget.current)) {
      _visibilityChanged();
    }
  }

  void _visibilityChanged() => _invalidate(bindingReplaced: false);

  void _invalidate({required bool bindingReplaced}) {
    _generation++;
    _reloadAfterBusy = false;
    setState(() {
      _run = null;
      _pendingAnswer = null;
      if (bindingReplaced || !_withdrawIntent) {
        _pendingClose = null;
        _withdrawIntent = false;
      }
      _pendingDelivery = null;
      _failure = null;
      _delivered = false;
    });
    if (widget.current.value) {
      if (_busy) {
        _reloadAfterBusy = true;
      } else {
        unawaited(_load());
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.current.removeListener(_visibilityChanged);
    _questionFocus.dispose();
    super.dispose();
  }

  Future<void> _perform(
    _Failure operation,
    Future<void> Function(int generation) action,
  ) async {
    if (_busy || !widget.current.value) {
      return;
    }
    final generation = _generation;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await action(generation);
    } on Object {
      if (_current(generation)) {
        setState(() => _failure = operation);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_reloadAfterBusy && widget.current.value) {
          _reloadAfterBusy = false;
          unawaited(_load());
        }
      }
    }
  }

  Future<void> _load() => _perform(_Failure.load, (generation) async {
    final result = await widget.repository.load(widget.ownerId, widget.runId);
    if (!_current(generation)) {
      return;
    }
    if (result == null) {
      throw StateError('Measurement run unavailable');
    }
    _binding(result);
    setState(() {
      _run = result;
      if (_withdrawIntent && _pendingClose != null) {
        _failure = _Failure.close;
      }
    });
  });

  Future<void> _answer(String itemId, String code) async {
    if (_busy || !_collecting || _item?.id != itemId || !widget.current.value) {
      return;
    }
    final previous = _pendingAnswer;
    if (previous != null &&
        (previous.itemId != itemId || previous.responseCode != code)) {
      return;
    }
    _pendingAnswer ??= MotivationResponse(
      ownerId: widget.ownerId,
      runId: widget.runId,
      itemId: itemId,
      responseCode: code,
    );
    await _saveAnswer(_pendingAnswer!);
  }

  Future<void> _saveAnswer(MotivationResponse command) =>
      _perform(_Failure.answer, (generation) async {
        final before = _run!;
        final result = await widget.repository.record(command);
        if (!_current(generation)) {
          return;
        }
        _binding(result);
        _preserved(before, result);
        final response = result.responses
            .where((response) => response.itemId == command.itemId)
            .single;
        if (response.responseCode != command.responseCode ||
            response.ordinalValue !=
                result.instrument
                    .response(command.itemId, command.responseCode)
                    .ordinalValue) {
          throw StateError('Measurement acknowledgement mismatch');
        }
        setState(() {
          _run = result;
          _pendingAnswer = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_current(generation)) {
            return;
          }
          final question = _questionKey.currentContext;
          if (question != null) {
            _questionFocus.requestFocus();
            unawaited(Scrollable.ensureVisible(question));
          }
        });
      });

  Future<void> _close(MotivationMeasurementRunState state) async {
    if (_busy || !widget.current.value || _run == null || _delivered) {
      return;
    }
    _pendingAnswer = null;
    _pendingClose = MotivationMeasurementClose(
      ownerId: widget.ownerId,
      runId: widget.runId,
      state: state,
    );
    if (state == MotivationMeasurementRunState.withdrawn) {
      _withdrawIntent = true;
    }
    await _saveClose(_pendingClose!);
  }

  Future<void> _saveClose(MotivationMeasurementClose command) async {
    MotivationMeasurementRun? acknowledged;
    final generation = _generation;
    await _perform(_Failure.close, (operationGeneration) async {
      final before = _run!;
      final result = await widget.repository.close(command);
      if (!_current(operationGeneration)) {
        return;
      }
      _binding(result);
      _preserved(before, result);
      if (result.state != command.state) {
        throw StateError('Unconfirmed measurement close');
      }
      setState(() {
        _run = result;
        _pendingClose = null;
      });
      acknowledged = result;
    });
    if (acknowledged != null && _current(generation)) {
      await _deliver(acknowledged!);
    }
  }

  Future<void> _deliver(MotivationMeasurementRun run) async {
    if (_busy || _delivered || !widget.current.value) {
      return;
    }
    _pendingDelivery = run;
    await _perform(_Failure.delivery, (generation) async {
      await widget.onFinished(run);
      if (!_current(generation)) {
        return;
      }
      setState(() {
        _pendingDelivery = null;
        _delivered = true;
      });
    });
  }

  void _retry() {
    if (_busy) {
      return;
    }
    switch (_failure) {
      case _Failure.load:
        unawaited(_load());
      case _Failure.answer:
        final command = _pendingAnswer;
        if (command != null) {
          unawaited(_saveAnswer(command));
        }
      case _Failure.close:
        final command = _pendingClose;
        if (command != null) {
          unawaited(_saveClose(command));
        }
      case _Failure.delivery:
        final run = _pendingDelivery;
        if (run != null) {
          unawaited(_deliver(run));
        }
      case null:
        break;
    }
  }

  void _binding(MotivationMeasurementRun run) {
    if (run.ownerId != widget.ownerId || run.id != widget.runId) {
      throw StateError('Measurement owner changed');
    }
  }

  static void _preserved(
    MotivationMeasurementRun before,
    MotivationMeasurementRun after,
  ) {
    if (before.permitId != after.permitId ||
        before.permitPayloadSha256 != after.permitPayloadSha256 ||
        before.assignmentId != after.assignmentId ||
        before.consentVersion != after.consentVersion ||
        before.instrument.checksumSha256 != after.instrument.checksumSha256 ||
        before.responses.any(
          (old) => !after.responses.any(
            (next) =>
                next.id == old.id &&
                next.itemId == old.itemId &&
                next.responseCode == old.responseCode &&
                next.ordinalValue == old.ordinalValue &&
                next.answeredAtUtc == old.answeredAtUtc &&
                next.localRevision == old.localRevision,
          ),
        )) {
      throw StateError('Recorded measurement facts changed');
    }
  }

  String get _status {
    if (_failure == _Failure.delivery) {
      return _text(
        'บันทึกแล้ว แต่ยังไปต่อไม่ได้ ลองไปต่ออีกครั้ง',
        'Saved. Could not continue. Retry continuing.',
      );
    }
    if (_failure == _Failure.answer) {
      return _text(
        'ยังยืนยันการบันทึกไม่ได้ ลองบันทึกคำตอบเดิมอีกครั้ง',
        'Save not confirmed. Retry the same answer.',
      );
    }
    if (_failure == _Failure.close && _withdrawIntent) {
      return _text(
        'ยังยืนยันการถอนตัวไม่ได้ ลองอีกครั้งได้',
        'Withdrawal not confirmed. You can retry.',
      );
    }
    if (_failure != null) {
      return _text(
        'ทำรายการไม่สำเร็จ ลองอีกครั้งได้',
        'Could not complete this action. You can retry.',
      );
    }
    if (_busy) {
      return _text('กำลังดำเนินการ กรุณารอสักครู่', 'Working. Please wait.');
    }
    if (_delivered) {
      return _text('เสร็จสิ้นแล้ว', 'Finished.');
    }
    if (!_collecting &&
        _run?.state != MotivationMeasurementRunState.completed) {
      return _text(
        'แบบบันทึกนี้หยุดแล้ว คุณเรียนต่อได้',
        'This form has stopped. You can continue learning.',
      );
    }
    if (_item == null) {
      return _text('บันทึกส่วนนี้แล้ว', 'This part has been recorded.');
    }
    return _text(
      'เลือกคำตอบที่ตรงกับคุณ',
      'Choose the response that fits you.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.current.value) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _text(
            'แบบบันทึกไม่พร้อมใช้งาน คุณเรียนต่อได้',
            'This form is unavailable. You can continue learning.',
          ),
        ),
      );
    }
    final run = _run;
    final item = _item;
    final pointComplete = run != null && _items.isNotEmpty && item == null;
    final stopped =
        run != null && run.state != MotivationMeasurementRunState.started;
    final canFinish =
        run != null && (pointComplete || stopped) && _pendingClose == null;
    final actionStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
    return FocusTraversalGroup(
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      widget.timepoint == MotivationTimepoint.baseline
                          ? _text(
                              'ช่วยบอกความรู้สึกก่อนเรียน',
                              'How do you feel before learning?',
                            )
                          : _text(
                              'ช่วยบอกความรู้สึกหลังเรียน',
                              'How do you feel after learning?',
                            ),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _text(
                      'การตอบเป็นทางเลือก คุณข้ามหรือถอนตัวได้ การเรียนยังใช้ได้ตามปกติ',
                      'Responding is optional. You can skip or withdraw and continue learning.',
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (run == null && _failure == null)
                    const LinearProgressIndicator(),
                  if (run != null && item != null && _collecting) ...[
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
                    const SizedBox(height: 8),
                    RadioGroup<String>(
                      groupValue: _pendingAnswer?.responseCode,
                      onChanged: (code) {
                        if (code != null) {
                          unawaited(_answer(item.id, code));
                        }
                      },
                      child: Column(
                        children: [
                          for (final option in item.options)
                            RadioListTile<String>(
                              key: ValueKey(
                                'measurement-${item.id}-${option.code}',
                              ),
                              value: option.code,
                              enabled: !_busy && _pendingAnswer == null,
                              title: Text(option.labels[_thai ? 'th' : 'en']!),
                              contentPadding: EdgeInsets.zero,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Semantics(
                    key: const ValueKey('measurement-status'),
                    liveRegion: true,
                    label: _status,
                    child: ExcludeSemantics(child: Text(_status)),
                  ),
                  if (_failure != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const ValueKey('measurement-retry'),
                      style: actionStyle,
                      onPressed: _busy ? null : _retry,
                      child: Text(
                        _failure == _Failure.delivery
                            ? _text('ลองไปต่ออีกครั้ง', 'Retry continuing')
                            : _text('ลองอีกครั้ง', 'Retry'),
                      ),
                    ),
                  ],
                  if (_failure == _Failure.close) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      key: const ValueKey('measurement-back-to-learning'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: _busy
                          ? null
                          : () => Navigator.maybePop(context),
                      child: Text(_text('กลับไปเรียน', 'Back to learning')),
                    ),
                  ],
                  if (canFinish) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('measurement-finish'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onPressed:
                          _busy || _delivered || _failure == _Failure.delivery
                          ? null
                          : () => unawaited(_deliver(run)),
                      child: Text(_text('เรียนต่อ', 'Continue learning')),
                    ),
                  ],
                  if (run != null && !stopped && !_delivered) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const ValueKey('measurement-skip'),
                      style: actionStyle,
                      onPressed:
                          _busy || _withdrawIntent || _pendingClose != null
                          ? null
                          : () => unawaited(
                              _close(MotivationMeasurementRunState.skipped),
                            ),
                      child: Text(_text('ข้ามแบบบันทึก', 'Skip questionnaire')),
                    ),
                  ],
                  if (run != null &&
                      run.state != MotivationMeasurementRunState.withdrawn &&
                      !_delivered) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: const ValueKey('measurement-withdraw'),
                      style: actionStyle,
                      onPressed: _busy || _withdrawIntent
                          ? null
                          : () => unawaited(
                              _close(MotivationMeasurementRunState.withdrawn),
                            ),
                      child: Text(
                        _text('ถอนตัวจากการวิจัย', 'Withdraw from research'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
