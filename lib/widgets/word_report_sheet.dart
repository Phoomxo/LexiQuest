import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../features/vocabulary/application/word_report_use_cases.dart';
import '../features/vocabulary/domain/word_report.dart';
import '../runtime/app_dependencies.dart';

/// Reports-only UI scope. It deliberately does not require SavedWords.
final class WordReportOwnerScope extends ChangeNotifier {
  WordReportOwnerScope({
    required Stream<String?> ownerChanges,
    required this.visible,
    String? expectedOwnerId,
  }) : ownerId = expectedOwnerId {
    _subscription = ownerChanges.listen(
      _ownerChanged,
      onError: (Object _, StackTrace _) => _ownerChanged(null),
      onDone: () => _ownerChanged(null),
    );
  }
  final bool Function() visible;
  String? ownerId;
  bool known = false;
  bool observed = false;
  bool blocked = false;
  int generation = 0;
  int ownerGeneration = 0;
  bool _wasVisible = false;
  bool _closed = false;
  bool _notificationScheduled = false;
  StreamSubscription<String?>? _subscription;
  Future<void>? _closeFuture;
  bool get current =>
      !_closed && !blocked && known && ownerId != null && visible();
  bool isCurrent(int epoch) => current && generation == epoch;
  void _ownerChanged(String? next) {
    if (_closed) {
      return;
    }
    observed = true;
    if (next == null) {
      known = false;
      generation++;
      ownerGeneration++;
      _notify();
      return;
    }
    if (ownerId != null && next != ownerId) {
      blocked = true;
      known = false;
      generation++;
      ownerGeneration++;
      _notify();
      return;
    }
    if (blocked) {
      return;
    }
    if (!known) {
      ownerId = next;
      known = true;
      generation++;
      ownerGeneration++;
    }
    synchronize();
  }

  void synchronize() {
    if (_closed) {
      return;
    }
    final nowVisible = visible();
    if (_wasVisible && !nowVisible) {
      generation++;
    }
    _wasVisible = nowVisible;
    _notify();
  }

  void invalidate() {
    blocked = true;
    known = false;
    generation++;
    _notify();
  }

  void _notify() {
    if (_closed) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_notificationScheduled) {
        return;
      }
      _notificationScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notificationScheduled = false;
        if (!_closed) {
          notifyListeners();
        }
      });
    } else {
      notifyListeners();
    }
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closed = true;
    generation++;
    await _subscription?.cancel();
    super.dispose();
  }
}

String wordReportReasonLabel(ReportReason reason, String languageCode) {
  final english = languageCode == 'en';
  return switch (reason) {
    ReportReason.incorrectMeaning =>
      english ? 'Meaning is incorrect' : 'ความหมายไม่ถูกต้อง',
    ReportReason.spelling => english ? 'Spelling issue' : 'การสะกดคำ',
    ReportReason.partOfSpeech => english ? 'Part of speech issue' : 'ชนิดของคำ',
    ReportReason.inappropriate =>
      english ? 'Inappropriate content' : 'เนื้อหาไม่เหมาะสม',
    ReportReason.other => english ? 'Other issue' : 'อื่น ๆ',
  };
}

class WordReportDetails extends StatelessWidget {
  const WordReportDetails({
    super.key,
    required this.report,
    this.languageCode = 'th',
  });
  final StoredWordReport report;
  final String languageCode;
  @override
  Widget build(BuildContext context) {
    final en = languageCode == 'en';
    final target = report.target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          en
              ? 'Saved on this device. Not sent.'
              : 'บันทึกรายงานในเครื่องแล้ว ยังไม่ได้ส่ง',
        ),
        const SizedBox(height: 8),
        Text('${en ? 'Receipt' : 'เลขรายงาน'}: ${report.id}'),
        Text(
          '${en ? 'Queued (UTC)' : 'เวลาบันทึก (UTC)'}: ${report.queuedAtUtc.toIso8601String()}',
        ),
        Text(
          '${en ? 'Word version' : 'เวอร์ชันคำศัพท์'}: ${target.wordRevision}',
        ),
        Text('${target.spelling} — ${target.meaning}'),
        Text('${en ? 'Part of speech' : 'ชนิดของคำ'}: ${target.partOfSpeech}'),
        Text('${en ? 'Source' : 'แหล่งที่มา'}: ${target.source}'),
        if (target.cefrLevel != null) Text('CEFR: ${target.cefrLevel}'),
        Text(wordReportReasonLabel(report.reason, languageCode)),
        if (report.comment != null) Text(report.comment!),
      ],
    );
  }
}

class WordReportSheet extends StatefulWidget {
  const WordReportSheet({
    super.key,
    required this.expectedOwnerId,
    required this.target,
    this.wordReports,
    this.ownerChanges,
    this.languageCode = 'th',
  });
  final String expectedOwnerId;
  final WordReportTarget target;
  final WordReportUseCases? wordReports;
  final Stream<String?>? ownerChanges;
  final String languageCode;
  @override
  State<WordReportSheet> createState() => _WordReportSheetState();
}

class _WordReportSheetState extends State<WordReportSheet>
    with WidgetsBindingObserver {
  final _comment = TextEditingController();
  final _confirmFocus = FocusNode(debugLabel: 'Confirm local report');
  AppDependencies? _dependencies;
  WordReportUseCases? _reports;
  WordReportOwnerScope? _scope;
  ModalRoute<dynamic>? _route;
  bool _bound = false;
  bool _foreground = false;
  bool _paneVisible = false;
  bool _invalidated = false;
  bool _everCurrent = false;
  int _acceptedOwnerGeneration = -1;
  bool _reviewing = false;
  bool _submitting = false;
  bool _uncertain = false;
  ReportReason? _reason;
  ReportReason? _reviewReason;
  String? _reviewComment;
  String? _validation;
  WordReportFailureCode? _rejection;
  WordReportCommand? _command;
  StoredWordReport? _receipt;
  String _text(String th, String en) => widget.languageCode == 'en' ? en : th;
  bool get _visible =>
      mounted &&
      !_invalidated &&
      _foreground &&
      _paneVisible &&
      _route?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _paneVisible =
        ModalRoute.isCurrentOf(context) == true && Visibility.of(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    final reports = widget.wordReports ?? dependencies?.wordReports;
    if (!_bound) {
      _bound = true;
      _dependencies = dependencies;
      _reports = reports;
      final owners =
          widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
      if (reports != null && owners != null) {
        _scope = WordReportOwnerScope(
          ownerChanges: owners,
          expectedOwnerId: widget.expectedOwnerId,
          visible: () => _visible,
        )..addListener(_scopeChanged);
      }
    } else if (!identical(dependencies, _dependencies) ||
        !identical(reports, _reports)) {
      _invalidate();
    }
    _scope?.synchronize();
  }

  @override
  void didUpdateWidget(covariant WordReportSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        !oldWidget.target.sameTarget(widget.target) ||
        !identical(oldWidget.wordReports, widget.wordReports) ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges)) {
      _invalidate();
    }
  }

  void _invalidate() {
    _invalidated = true;
    _scope?.invalidate();
  }

  void _scopeChanged() {
    final scope = _scope;
    if (_everCurrent &&
        (scope?.current != true ||
            scope?.ownerGeneration != _acceptedOwnerGeneration)) {
      _invalidated = true;
    }
    if (scope?.current == true) {
      _everCurrent = true;
      _acceptedOwnerGeneration = scope!.ownerGeneration;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _invalidated = true;
    }
    _scope?.synchronize();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _invalidated = true;
    WidgetsBinding.instance.removeObserver(this);
    _scope?.removeListener(_scopeChanged);
    unawaited(_scope?.close());
    _comment.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  bool _validForm() {
    final comment = _comment.text.trim();
    if (_reason == null) {
      _validation = _text('เลือกปัญหาที่พบ', 'Choose an issue.');
      return false;
    }
    if (comment.runes.length > wordReportCommentMaxRunes ||
        utf8.encode(comment).length > wordReportCommentMaxBytes) {
      _validation = _text(
        'รายละเอียดเกินขนาดที่รองรับ',
        'The comment is too long.',
      );
      return false;
    }
    if (_reason == ReportReason.other && comment.isEmpty) {
      _validation = _text(
        'โปรดระบุรายละเอียดสำหรับปัญหาอื่น',
        'Describe the other issue.',
      );
      return false;
    }
    _validation = null;
    return true;
  }

  Future<void> _submit() async {
    final scope = _scope;
    final reports = _reports;
    if (scope == null ||
        reports == null ||
        !scope.current ||
        _submitting ||
        _receipt != null ||
        _rejection != null) {
      return;
    }
    final epoch = scope.generation;
    if (_command == null) {
      if (!_reviewing || _reviewReason == null) {
        return;
      }
      try {
        _command = reports.prepareSubmit(
          expectedOwnerId: widget.expectedOwnerId,
          target: widget.target,
          reason: _reviewReason!,
          comment: _reviewComment,
        );
      } on Object {
        setState(
          () => _validation = _text(
            'เตรียมรายงานไม่สำเร็จ',
            'Could not prepare this report.',
          ),
        );
        return;
      }
    }
    final command = _command!;
    setState(() {
      _submitting = true;
      _uncertain = false;
    });
    try {
      final result = await reports.submit(command);
      if (!mounted ||
          _invalidated ||
          !identical(reports, _reports) ||
          !scope.isCurrent(epoch)) {
        return;
      }
      if (!result.report.matchesCommand(command)) {
        throw const WordReportException(WordReportFailureCode.unavailable);
      }
      setState(() => _receipt = result.report);
    } on WordReportException catch (error) {
      if (mounted && !_invalidated && scope.isCurrent(epoch)) {
        setState(() {
          if (error.code == WordReportFailureCode.unavailable) {
            _uncertain = true;
          } else {
            _rejection = error.code;
          }
        });
      }
    } on Object {
      if (mounted && !_invalidated && scope.isCurrent(epoch)) {
        setState(() => _uncertain = true);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final available =
        !_invalidated && scope?.current == true && _reports != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _text('รายงานคำศัพท์', 'Report this word'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('word-report-close'),
                    tooltip: _text('ปิด', 'Close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (!available &&
                  (scope == null || scope.observed || _invalidated))
                Text(
                  _text(
                    'รายงานนี้ไม่พร้อมใช้งาน กรุณากลับแล้วเปิดใหม่',
                    'This report is unavailable. Go back and open it again.',
                  ),
                )
              else if (!available)
                const Center(child: CircularProgressIndicator())
              else if (_receipt != null) ...[
                Text(
                  _text('บันทึกรายงานแล้ว', 'Report saved'),
                  key: const ValueKey('word-report-queued'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                WordReportDetails(
                  report: _receipt!,
                  languageCode: widget.languageCode,
                ),
              ] else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.target.spelling,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(widget.target.meaning),
                        Text(widget.target.partOfSpeech),
                        Text(
                          '${_text('แหล่งที่มา', 'Source')}: ${widget.target.source}',
                        ),
                        Text(
                          '${_text('เวอร์ชันคำศัพท์', 'Word version')}: ${widget.target.wordRevision}',
                        ),
                        if (widget.target.cefrLevel != null)
                          Text('CEFR: ${widget.target.cefrLevel}'),
                      ],
                    ),
                  ),
                ),
                if (_command == null && !_reviewing) ...[
                  RadioGroup<ReportReason>(
                    groupValue: _reason,
                    onChanged: (value) => setState(() => _reason = value),
                    child: Column(
                      children: [
                        for (final reason in ReportReason.values)
                          RadioListTile<ReportReason>(
                            key: ValueKey('word-report-reason:${reason.name}'),
                            value: reason,
                            title: Text(
                              wordReportReasonLabel(
                                reason,
                                widget.languageCode,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextField(
                    key: const ValueKey('word-report-comment'),
                    controller: _comment,
                    minLines: 2,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      labelText: _text('รายละเอียดเพิ่มเติม', 'Comment'),
                      helperText: _text(
                        'สูงสุด 500 ตัวอักษร และ 2048 ไบต์',
                        'Up to 500 characters and 2048 bytes',
                      ),
                    ),
                  ),
                  if (_validation != null)
                    Semantics(liveRegion: true, child: Text(_validation!)),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('word-report-review'),
                    onPressed: () {
                      if (!scope!.current) {
                        return;
                      }
                      if (_validForm()) {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _reviewReason = _reason;
                          final comment = _comment.text.trim();
                          _reviewComment = comment.isEmpty ? null : comment;
                          _reviewing = true;
                        });
                      } else {
                        setState(() {});
                      }
                    },
                    child: Text(_text('ตรวจรายงานก่อนบันทึก', 'Review report')),
                  ),
                ] else ...[
                  Text(
                    wordReportReasonLabel(
                      _command?.reason ?? _reviewReason!,
                      widget.languageCode,
                    ),
                  ),
                  if ((_command == null ? _reviewComment : _command!.comment) !=
                      null)
                    Text(
                      (_command == null ? _reviewComment : _command!.comment)!,
                    ),
                  Text(
                    _text(
                      'รายงานจะเก็บในเครื่องนี้ ยังไม่ได้ส่ง',
                      'This report stays on this device. It is not sent.',
                    ),
                  ),
                  if (_command == null) ...[
                    OutlinedButton(
                      key: const ValueKey('word-report-edit'),
                      onPressed: () {
                        if (scope!.current) {
                          setState(() => _reviewing = false);
                        }
                      },
                      child: Text(_text('กลับไปแก้ไข', 'Back to edit')),
                    ),
                    FilledButton(
                      key: const ValueKey('word-report-confirm'),
                      focusNode: _confirmFocus,
                      onPressed: _submit,
                      child: Text(
                        _text('ยืนยันบันทึกในเครื่อง', 'Confirm local report'),
                      ),
                    ),
                  ],
                  if (_submitting)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: LinearProgressIndicator(),
                    ),
                  if (_uncertain && !_submitting) ...[
                    Text(
                      _text(
                        'ยังยืนยันผลไม่ได้ ลองคำสั่งเดิมอีกครั้ง หรือดูรายการรายงาน',
                        'The result is unconfirmed. Retry the same report or check report history.',
                      ),
                    ),
                    OutlinedButton(
                      key: const ValueKey('word-report-retry'),
                      onPressed: _submit,
                      child: Text(
                        _text('ลองคำสั่งเดิมอีกครั้ง', 'Retry original report'),
                      ),
                    ),
                  ],
                  if (_rejection != null)
                    Text(
                      _rejection == WordReportFailureCode.staleTarget
                          ? _text(
                              'คำศัพท์เปลี่ยนแล้ว กรุณาปิดแล้วเปิดคำล่าสุดเพื่อตรวจใหม่',
                              'The word changed. Close this form and review the current word.',
                            )
                          : _text(
                              'ยืนยันรายงานนี้ไม่ได้ กรุณาปิดแล้วตรวจรายการรายงาน',
                              'This report cannot be confirmed. Close it and check report history.',
                            ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
