import 'dart:async';

import 'package:flutter/material.dart';

import '../application/learning_time_use_cases.dart';
import 'learning_time_binding.dart';

/// Acknowledged owner-scoped history. No read starts collection or an owner.
class RecordedTimeView extends StatefulWidget {
  const RecordedTimeView({
    super.key,
    required this.time,
    required this.expectedOwnerId,
    required this.target,
    this.showExplanation = true,
    this.collapseExplanation = false,
    this.languageCode,
  });
  final LearningTimeUseCases? time;
  final String expectedOwnerId;
  final TimeReadTarget target;
  final bool showExplanation;
  final bool collapseExplanation;
  final String? languageCode;
  @override
  State<RecordedTimeView> createState() => _RecordedTimeViewState();
}

class _RecordedTimeViewState extends State<RecordedTimeView> {
  late LearningTimeBinding _binding;
  bool _dependenciesReady = false;
  int? _ownerGeneration;
  int _readGeneration = 0;
  int _retryGeneration = 0;
  int _lastVisibilityGeneration = 0;
  RecordedTimeRead? _value;
  bool _loading = false;
  bool _retrying = false;
  bool _reloadRequested = false;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _binding.syncVisibility();
  }

  @override
  void didUpdateWidget(RecordedTimeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.time, oldWidget.time) ||
        widget.expectedOwnerId != oldWidget.expectedOwnerId ||
        _targetKey(widget.target) != _targetKey(oldWidget.target)) {
      _binding.removeListener(_bindingChanged);
      _binding.dispose();
      _bind();
    }
  }

  String _targetKey(TimeReadTarget target) => switch (target) {
    OwnerTimeRead(:final sourceKind) => 'owner:${sourceKind?.name ?? ''}',
    ScopeTimeRead(:final scopeId) => 'scope:$scopeId',
    SessionTimeRead(:final sessionId) => 'session:$sessionId',
    ObservedEndRangeTimeRead(
      :final startInclusiveUtc,
      :final endExclusiveUtc,
    ) =>
      'end-range:${startInclusiveUtc.microsecondsSinceEpoch}:${endExclusiveUtc.microsecondsSinceEpoch}',
  };

  bool _visible() =>
      _dependenciesReady &&
      mounted &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled;

  void _bind() {
    _readGeneration++;
    _retryGeneration++;
    _value = null;
    _loading = false;
    _retrying = false;
    _reloadRequested = false;
    _ownerGeneration = widget.time?.ownerGeneration;
    final wasReady = _dependenciesReady;
    _dependenciesReady = false;
    _binding = LearningTimeBinding(
      time: widget.time,
      expectedOwnerId: widget.expectedOwnerId,
      visible: _visible,
    );
    _dependenciesReady = wasReady;
    _lastVisibilityGeneration = _binding.visibilityGeneration;
    _binding.addListener(_bindingChanged);
  }

  void _bindingChanged() {
    if (!mounted) return;
    final visibilityChanged =
        _lastVisibilityGeneration != _binding.visibilityGeneration;
    _lastVisibilityGeneration = _binding.visibilityGeneration;
    if (!_binding.current || visibilityChanged) {
      _readGeneration++;
      _retryGeneration++;
      _value = null;
      _loading = false;
      _retrying = false;
      _reloadRequested = false;
    }
    setState(() {});
    if (_binding.current) unawaited(_load());
  }

  bool _capturedCurrent({
    required LearningTimeBinding binding,
    required LearningTimeUseCases? time,
    required String owner,
    required int? ownerGeneration,
    required int visibility,
    required int readGeneration,
    required String targetKey,
  }) =>
      mounted &&
      identical(_binding, binding) &&
      identical(widget.time, time) &&
      widget.expectedOwnerId == owner &&
      _ownerGeneration == ownerGeneration &&
      time?.ownerGeneration == ownerGeneration &&
      time?.ownerId == owner &&
      binding.current &&
      binding.visibilityGeneration == visibility &&
      _readGeneration == readGeneration &&
      _targetKey(widget.target) == targetKey;

  Future<void> _load() async {
    if (!_binding.current) return;
    if (_loading) {
      _reloadRequested = true;
      return;
    }
    final binding = _binding;
    final time = widget.time!;
    final owner = widget.expectedOwnerId;
    final ownerGeneration = _ownerGeneration;
    final visibility = binding.visibilityGeneration;
    final target = widget.target;
    final targetKey = _targetKey(target);
    final generation = ++_readGeneration;
    _loading = true;
    final result = await time.read(target);
    if (!_capturedCurrent(
      binding: binding,
      time: time,
      owner: owner,
      ownerGeneration: ownerGeneration,
      visibility: visibility,
      readGeneration: generation,
      targetKey: targetKey,
    )) {
      return;
    }
    setState(() {
      _loading = false;
      _value = result;
    });
    if (_reloadRequested) {
      _reloadRequested = false;
      unawaited(_load());
    }
  }

  Future<void> _retry({
    required LearningTimeBinding binding,
    required LearningTimeUseCases time,
    required String owner,
    required int? ownerGeneration,
    required int visibility,
    required int readGeneration,
    required String targetKey,
  }) async {
    bool current() => _capturedCurrent(
      binding: binding,
      time: time,
      owner: owner,
      ownerGeneration: ownerGeneration,
      visibility: visibility,
      readGeneration: readGeneration,
      targetKey: targetKey,
    );
    if (!current() || _retrying) return;
    final retry = ++_retryGeneration;
    setState(() => _retrying = true);
    await time.retryPending();
    if (current()) await _load();
    if (!mounted ||
        retry != _retryGeneration ||
        !identical(_binding, binding) ||
        !identical(widget.time, time) ||
        !binding.current ||
        binding.visibilityGeneration != visibility) {
      return;
    }
    setState(() => _retrying = false);
  }

  @override
  void dispose() {
    _readGeneration++;
    _retryGeneration++;
    _binding.removeListener(_bindingChanged);
    _binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _binding.syncVisibility();
    final binding = _binding;
    final time = widget.time;
    final owner = widget.expectedOwnerId;
    final ownerGeneration = _ownerGeneration;
    final visibility = binding.visibilityGeneration;
    final readGeneration = _readGeneration;
    final targetKey = _targetKey(widget.target);
    bool actionCurrent() => _capturedCurrent(
      binding: binding,
      time: time,
      owner: owner,
      ownerGeneration: ownerGeneration,
      visibility: visibility,
      readGeneration: readGeneration,
      targetKey: targetKey,
    );
    final thai =
        (widget.languageCode ?? Localizations.localeOf(context).languageCode) ==
        'th';
    final theme = Theme.of(context);
    final value = _value;
    final status = !binding.current
        ? RecordedTimeStatus.unavailable
        : value?.status;
    final String message;
    if (status == null) {
      message = thai ? 'กำลังอ่านเวลาที่บันทึก…' : 'Reading recorded time…';
    } else {
      message = switch (status) {
        RecordedTimeStatus.recorded =>
          value!.activeDurationUs! > 0 && value.segmentCount! > 0
              ? formatRecordedLearningTime(value.activeDurationUs!, thai: thai)
              : (thai
                    ? 'อ่านเวลาที่บันทึกไม่ได้ในขณะนี้'
                    : 'Recorded time is unavailable'),
        RecordedTimeStatus.noneRecorded =>
          thai ? 'ยังไม่มีเวลาที่บันทึกไว้' : 'No recorded time yet',
        RecordedTimeStatus.unsupported =>
          thai
              ? 'กิจกรรมนี้ไม่รองรับการบันทึกเวลา'
              : 'Time is unsupported for this activity',
        RecordedTimeStatus.unavailable =>
          thai
              ? 'อ่านเวลาที่บันทึกไม่ได้ในขณะนี้'
              : 'Recorded time is unavailable',
      };
    }
    final pending = binding.current
        ? time!.pendingState
        : LearningTimePendingState.none;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          thai ? 'เวลาจากการโต้ตอบที่บันทึกแล้ว' : 'Recorded interaction time',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Semantics(liveRegion: true, child: Text(message)),
        if (pending != LearningTimePendingState.none) ...[
          const SizedBox(height: 8),
          Text(
            pending == LearningTimePendingState.preference
                ? (thai
                      ? 'การตั้งค่ายังรอยืนยัน'
                      : 'Setting change awaiting confirmation')
                : (thai
                      ? 'บางช่วงยังรอบันทึก ไม่นับรวมในยอดนี้'
                      : 'Some time is pending and is excluded from this total'),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _retrying
                  ? null
                  : () {
                      if (!actionCurrent()) return;
                      unawaited(
                        _retry(
                          binding: binding,
                          time: time!,
                          owner: owner,
                          ownerGeneration: ownerGeneration,
                          visibility: visibility,
                          readGeneration: readGeneration,
                          targetKey: targetKey,
                        ),
                      );
                    },
              child: Text(thai ? 'ลองบันทึกอีกครั้ง' : 'Retry saving'),
            ),
          ),
        ] else if (status == RecordedTimeStatus.unavailable &&
            binding.current) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _loading
                  ? null
                  : () {
                      if (actionCurrent()) unawaited(_load());
                    },
              child: Text(thai ? 'ลองอ่านอีกครั้ง' : 'Read again'),
            ),
          ),
        ],
        if (widget.showExplanation) ...[
          const SizedBox(height: 8),
          if (widget.collapseExplanation)
            ExpansionTile(
              title: Text(thai ? 'วิธีนับเวลา' : 'How time is counted'),
              tilePadding: EdgeInsets.zero,
              children: [_explanation(thai, theme)],
            )
          else
            _explanation(thai, theme),
        ],
      ],
    );
  }

  Widget _explanation(bool thai, ThemeData theme) => Text(
    thai
        ? 'เก็บเฉพาะช่วงการโต้ตอบที่ยืนยันและบันทึกสำเร็จในเครื่อง ไม่รวมเวลารอ การอ่านเงียบเป็นเวลานานอาจนับได้น้อยกว่าจริง'
        : 'Includes locally saved, confirmed interaction windows. Waiting is excluded; long reading without input may be undercounted.',
    style: theme.textTheme.bodySmall,
  );
}

String formatRecordedLearningTime(int activeDurationUs, {required bool thai}) {
  if (activeDurationUs <= 0) {
    throw ArgumentError.value(activeDurationUs, 'activeDurationUs');
  }
  final seconds = (activeDurationUs / 1000000).round();
  if (seconds == 0) return thai ? 'น้อยกว่า 1 วินาที' : 'Less than 1 second';
  final hours = seconds ~/ 3600;
  final minutes = seconds ~/ 60 % 60;
  final remainder = seconds % 60;
  if (thai) {
    return [
      if (hours > 0) '$hours ชม.',
      if (minutes > 0) '$minutes นาที',
      if (remainder > 0) '$remainder วินาที',
    ].join(' ');
  }
  return [
    if (hours > 0) '$hours ${hours == 1 ? 'hour' : 'hours'}',
    if (minutes > 0) '$minutes ${minutes == 1 ? 'minute' : 'minutes'}',
    if (remainder > 0) '$remainder ${remainder == 1 ? 'second' : 'seconds'}',
  ].join(' ');
}
