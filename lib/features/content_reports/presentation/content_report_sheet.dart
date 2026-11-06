import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../widgets/word_report_sheet.dart';
import '../../vocabulary/domain/word_report.dart';
import '../application/content_report_use_cases.dart';
import '../domain/content_report.dart';

Future<void> showContentReportModal(
  BuildContext context, {
  required WidgetBuilder builder,
  void Function(Route<dynamic>? route, bool current)? onRouteChanged,
}) async {
  assert(debugCheckHasMediaQuery(context));
  assert(debugCheckHasMaterialLocalizations(context));
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final route = ModalBottomSheetRoute<void>(
    builder: (sheetContext) {
      onRouteChanged?.call(
        ModalRoute.of(sheetContext),
        ModalRoute.isCurrentOf(sheetContext) == true,
      );
      return builder(sheetContext);
    },
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    isScrollControlled: true,
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
  );
  try {
    onRouteChanged?.call(route, true);
    await navigator.push<void>(route);
  } finally {
    onRouteChanged?.call(null, false);
  }
}

Future<void> showContentReportComposer(
  BuildContext context, {
  required String expectedOwnerId,
  required String sourceText,
  required ContentReportTarget Function(String selectedText, bool isExcerpt)
  targetForSelection,
  required ContentReportUseCases reports,
  required Stream<String?> ownerChanges,
  ValueListenable<bool>? sourceLease,
  Future<void> Function()? revalidate,
  void Function(Route<dynamic>? route, bool current)? onRouteChanged,
  String languageCode = 'th',
}) => showContentReportModal(
  context,
  onRouteChanged: onRouteChanged,
  builder: (_) => _ContentReportComposer(
    expectedOwnerId: expectedOwnerId,
    sourceText: sourceText,
    targetForSelection: targetForSelection,
    reports: reports,
    ownerChanges: ownerChanges,
    sourceLease: sourceLease,
    revalidate: revalidate,
    languageCode: languageCode,
  ),
);

class _ContentReportComposer extends StatefulWidget {
  const _ContentReportComposer({
    required this.expectedOwnerId,
    required this.sourceText,
    required this.targetForSelection,
    required this.reports,
    required this.ownerChanges,
    required this.languageCode,
    this.sourceLease,
    this.revalidate,
  });
  final String expectedOwnerId;
  final String sourceText;
  final ContentReportTarget Function(String, bool) targetForSelection;
  final ContentReportUseCases reports;
  final Stream<String?> ownerChanges;
  final String languageCode;
  final ValueListenable<bool>? sourceLease;
  final Future<void> Function()? revalidate;
  @override
  State<_ContentReportComposer> createState() => _ContentReportComposerState();
}

class _ContentReportComposerState extends State<_ContentReportComposer> {
  late final TextEditingController _selection;
  late final Stream<String?> _owners;
  ContentReportTarget? _target;
  String? _error;
  @override
  void initState() {
    super.initState();
    final text = widget.sourceText;
    _selection = TextEditingController(
      text: text.runes.length <= 4096 && utf8.encode(text).length <= 16384
          ? text
          : '',
    );
    _owners = widget.ownerChanges;
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  String _text(String th, String en) => widget.languageCode == 'en' ? en : th;
  @override
  Widget build(BuildContext context) {
    return ContentReportOwnerGuard(
      expectedOwnerId: widget.expectedOwnerId,
      ownerChanges: _owners,
      sourceLease: widget.sourceLease,
      languageCode: widget.languageCode,
      builder: (context, current) {
        if (_target case final target?) {
          return ContentReportSheet._withinOwnerScope(
            expectedOwnerId: widget.expectedOwnerId,
            target: target,
            reports: widget.reports,
            ownerChanges: _owners,
            languageCode: widget.languageCode,
            scopeCurrent: () => ContentReportOwnerGuard.currentOf(context),
            revalidate: widget.revalidate,
          );
        }
        return _sheetBody(context, [
          Text(
            _text('เลือกข้อความที่จะรายงาน', 'Choose content to report'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            _text(
              'เลือกเฉพาะเนื้อหาที่พบปัญหา ไม่ใส่คำถาม ประวัติสนทนา หรือคำตอบของคุณ',
              'Choose the problematic content only. Exclude your prompts, history and answers.',
            ),
          ),
          ExpansionTile(
            title: Text(_text('ดูข้อความต้นทาง', 'View source text')),
            children: [SelectableText(widget.sourceText)],
          ),
          TextField(
            key: const ValueKey('content-report-selection'),
            controller: _selection,
            minLines: 3,
            maxLines: 8,
            enabled: current,
            decoration: InputDecoration(
              labelText: _text(
                'ข้อความเต็มหรือข้อความบางส่วนที่เลือก',
                'Full text or selected excerpt',
              ),
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            key: const ValueKey('content-report-selection-review'),
            onPressed: !current
                ? null
                : () async {
                    if (!ContentReportOwnerGuard.currentOf(context)) return;
                    try {
                      await widget.revalidate?.call();
                    } on Object {
                      if (mounted) {
                        setState(
                          () => _error = _text(
                            'ข้อมูลต้นทางไม่พร้อม กรุณาปิดรายงานนี้',
                            'The source is unavailable. Close this report.',
                          ),
                        );
                      }
                      return;
                    }
                    if (!mounted ||
                        !context.mounted ||
                        !ContentReportOwnerGuard.currentOf(context)) {
                      return;
                    }
                    final text = _selection.text;
                    if (text.trim().isEmpty ||
                        !widget.sourceText.contains(text) ||
                        text.runes.length > 4096 ||
                        utf8.encode(text).length > 16384) {
                      setState(
                        () => _error = _text(
                          'เลือกข้อความจากต้นทางไม่เกิน 4,096 ตัวอักษร โดยไม่แก้ข้อความ',
                          'Choose unchanged source text up to 4,096 characters.',
                        ),
                      );
                      return;
                    }
                    try {
                      final target = widget.targetForSelection(
                        text,
                        text != widget.sourceText,
                      );
                      if (target.text != text ||
                          target.isExcerpt != (text != widget.sourceText)) {
                        throw ArgumentError('Selection does not match target');
                      }
                      setState(() {
                        _target = target;
                        _error = null;
                      });
                    } on Object {
                      setState(
                        () => _error = _text(
                          'สร้างรายงานจากข้อความนี้ไม่ได้ กรุณาปิดแล้วตรวจต้นทาง',
                          'This content cannot be reported. Close and check its source.',
                        ),
                      );
                    }
                  },
            child: Text(_text('ใช้ข้อความนี้', 'Use this content')),
          ),
        ]);
      },
    );
  }
}

class ContentReportSheet extends StatefulWidget {
  const ContentReportSheet({
    super.key,
    required this.expectedOwnerId,
    required this.target,
    required this.reports,
    required this.ownerChanges,
    this.languageCode = 'th',
    this.revalidate,
  }) : _scopeCurrent = null;
  const ContentReportSheet._withinOwnerScope({
    required this.expectedOwnerId,
    required this.target,
    required this.reports,
    required this.ownerChanges,
    required this.languageCode,
    required bool Function() this._scopeCurrent,
    this.revalidate,
  });
  final String expectedOwnerId;
  final ContentReportTarget target;
  final ContentReportUseCases reports;
  final Stream<String?> ownerChanges;
  final String languageCode;
  final bool Function()? _scopeCurrent;
  final Future<void> Function()? revalidate;
  @override
  State<ContentReportSheet> createState() => _ContentReportSheetState();
}

class _ContentReportSheetState extends State<ContentReportSheet> {
  final _comment = TextEditingController();
  ReportReason? _reason;
  ContentReportPayload? _payload;
  ContentReportRecord? _record;
  bool _reviewing = false;
  bool _busy = false;
  bool _saveAttempted = false;
  String? _error;
  int _operation = 0;
  bool _invalidated = false;
  String _text(String th, String en) => widget.languageCode == 'en' ? en : th;
  @override
  void dispose() {
    _operation++;
    _comment.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ContentReportSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        oldWidget.target.snapshotJson != widget.target.snapshotJson ||
        !identical(oldWidget.reports, widget.reports) ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges)) {
      _invalidated = true;
      _operation++;
    }
  }

  Future<void> _run(
    bool Function() current,
    Future<ContentReportRecord> Function() action,
  ) async {
    if (_busy || !current()) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.revalidate?.call();
      if (!mounted || !current()) return;
      final row = await action();
      if (mounted && operation == _operation && current()) {
        setState(() => _record = row);
      }
    } on Object {
      if (_record != null && current()) {
        try {
          final row = await widget.reports.queue.read(
            expectedOwnerId: widget.expectedOwnerId,
            reportId: _payload!.reportId,
          );
          if (mounted && operation == _operation && current() && row != null) {
            setState(() => _record = row);
          }
        } on Object {
          /* Keep the reviewed payload for an exact retry. */
        }
      }
      if (mounted && operation == _operation && current()) {
        setState(
          () => _error = _text(
            'ยังยืนยันผลไม่ได้ เปิดรายการรายงานเพื่อตรวจ หรือลองคำสั่งเดิมอีกครั้ง',
            'The result is unconfirmed. Check report history or retry the same report.',
          ),
        );
      }
    } finally {
      if (mounted && operation == _operation && current()) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invalidated) {
      return _sheetBody(context, [
        Text(
          _text(
            'ข้อมูลเปลี่ยนแล้ว กรุณาปิดแล้วเปิดรายงานใหม่',
            'The context changed. Close and reopen this report.',
          ),
        ),
      ]);
    }
    if (widget._scopeCurrent case final current?) {
      return _content(context, current());
    }
    return ContentReportOwnerGuard(
      expectedOwnerId: widget.expectedOwnerId,
      ownerChanges: widget.ownerChanges,
      languageCode: widget.languageCode,
      builder: _content,
    );
  }

  bool _current(BuildContext context) =>
      !_invalidated &&
      (widget._scopeCurrent?.call() ??
          ContentReportOwnerGuard.currentOf(context));
  List<Widget> _sourceDetails(ContentReportTarget target) => [
    Text(
      target.isExcerpt
          ? _text('ข้อความบางส่วนที่เลือก', 'Selected excerpt')
          : _text('เนื้อหาที่เลือก', 'Selected content'),
    ),
    SelectableText(target.text),
    Text(
      _text(
        'ข้อมูลต้นทางเป็นข้อมูลที่รายงาน ไม่ใช่การรับรองเนื้อหา',
        'Source facts are reported information, not an endorsement.',
      ),
    ),
    ExpansionTile(
      title: Text(_text('ข้อมูลต้นทางที่แนบ', 'Attached source facts')),
      children: [SelectableText(target.snapshotJson)],
    ),
  ];

  Widget _content(BuildContext context, bool current) => _sheetBody(context, [
    Text(
      _record == null
          ? _text('รายงานปัญหาเนื้อหา', 'Report content')
          : _text('บันทึกรายงานเนื้อหาแล้ว', 'Content report saved'),
      style: Theme.of(context).textTheme.titleLarge,
    ),
    if (_record == null) ..._sourceDetails(widget.target),
    if (!_reviewing) ...[
      Text(_text('ปัญหาที่พบ', 'Issue')),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final reason in ReportReason.values)
            ChoiceChip(
              key: ValueKey('content-report-reason:${reason.name}'),
              selected: _reason == reason,
              label: Text(
                wordReportReasonLabel(reason, widget.languageCode),
                softWrap: true,
              ),
              onSelected: !current || _busy
                  ? null
                  : (_) => setState(() => _reason = reason),
            ),
        ],
      ),
      TextField(
        key: const ValueKey('content-report-comment'),
        controller: _comment,
        minLines: 2,
        maxLines: 5,
        enabled: current && !_busy,
        decoration: InputDecoration(
          labelText: _text(
            'รายละเอียดเพิ่มเติม ไม่ใส่ข้อมูลส่วนตัว',
            'Comment, exclude personal information',
          ),
        ),
      ),
      FilledButton(
        key: const ValueKey('content-report-review'),
        onPressed: !current || _busy
            ? null
            : () async {
                try {
                  await widget.revalidate?.call();
                  if (!mounted || !context.mounted || !_current(context)) {
                    return;
                  }
                  if (_reason == null) throw ArgumentError('Reason required');
                  final payload = widget.reports.prepare(
                    target: widget.target,
                    reason: _reason!,
                    comment: _comment.text,
                  );
                  setState(() {
                    _payload = payload;
                    _reviewing = true;
                    _error = null;
                  });
                } on Object {
                  if (!mounted || !context.mounted || !_current(context)) {
                    return;
                  }
                  setState(
                    () => _error = _text(
                      'เลือกปัญหาและตรวจรายละเอียดไม่เกิน 500 ตัวอักษร ปัญหาอื่นต้องมีรายละเอียด',
                      'Choose an issue and check the comment limit of 500 characters. Other requires a comment.',
                    ),
                  );
                }
              },
        child: Text(_text('ตรวจรายงานก่อนบันทึก', 'Review report')),
      ),
    ] else ...[
      if (_record == null) ...[
        Text(wordReportReasonLabel(_payload!.reason, widget.languageCode)),
        if (_payload!.comment != null) SelectableText(_payload!.comment!),
        Text(
          widget.reports.transport.enabled
              ? _text(
                  'บันทึกในเครื่องก่อน การส่งต้องกดส่งแยกอีกครั้ง',
                  'Save locally first. Sending requires a separate action.',
                )
              : _text(
                  'ขณะนี้บันทึกรายงานได้เฉพาะในเครื่อง ผู้จัดจะยังไม่ได้รับรายงาน',
                  'Sending is unavailable. The report stays on this device and the organizer will not receive it.',
                ),
        ),
        if (!_saveAttempted)
          OutlinedButton(
            onPressed: !current || _busy
                ? null
                : () => setState(() {
                    _reviewing = false;
                    _payload = null;
                  }),
            child: Text(_text('กลับไปแก้ไข', 'Back to edit')),
          ),
        FilledButton(
          key: const ValueKey('content-report-save'),
          onPressed: !current || _busy
              ? null
              : () {
                  _saveAttempted = true;
                  unawaited(
                    _run(
                      () => context.mounted && _current(context),
                      () => widget.reports.save(
                        expectedOwnerId: widget.expectedOwnerId,
                        payload: _payload!,
                      ),
                    ),
                  );
                },
          child: Text(_text('ยืนยันบันทึกในเครื่อง', 'Confirm local report')),
        ),
      ] else ...[
        ContentReportStatus(
          record: _record!,
          languageCode: widget.languageCode,
        ),
        ExpansionTile(
          key: const ValueKey('content-report-saved-details'),
          title: Text(
            _text('ดูรายงานเนื้อหาที่บันทึกไว้', 'View saved content report'),
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._sourceDetails(_record!.payload.target),
            Text(
              wordReportReasonLabel(
                _record!.payload.reason,
                widget.languageCode,
              ),
            ),
            if (_record!.payload.comment case final comment?)
              SelectableText(comment),
          ],
        ),
        if (widget.reports.transport.enabled &&
            _record!.acknowledgement == null)
          FilledButton(
            key: const ValueKey('content-report-send'),
            onPressed: !current || _busy || !widget.reports.transport.enabled
                ? null
                : () => _run(
                    () => context.mounted && _current(context),
                    () => widget.reports.send(
                      expectedOwnerId: widget.expectedOwnerId,
                      reportId: _record!.payload.reportId,
                    ),
                  ),
            child: Text(
              _text('ส่งเนื้อหาที่ตรวจแล้ว', 'Send reviewed content'),
            ),
          ),
        if (!widget.reports.transport.enabled)
          Text(
            _text(
              'การส่งยังไม่เปิดใช้งาน รายงานยังเก็บในเครื่อง',
              'Sending is unavailable. Your report remains on this device.',
            ),
          ),
      ],
    ],
    if (_busy) const LinearProgressIndicator(),
    if (_error != null)
      Text(
        _error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
  ]);
}

String contentReportDeliveryLabel(
  ContentReportDelivery delivery,
  String languageCode,
) => switch (delivery) {
  ContentReportDelivery.queued =>
    languageCode == 'en'
        ? 'Saved locally. No server receipt.'
        : 'บันทึกในเครื่อง ยังไม่มีใบรับเรื่องจากเซิร์ฟเวอร์',
  ContentReportDelivery.unconfirmed =>
    languageCode == 'en'
        ? 'Delivery unconfirmed. Check receipt before retrying.'
        : 'ยังยืนยันการส่งไม่ได้ ตรวจใบรับเรื่องก่อนลองส่งอีกครั้ง',
  ContentReportDelivery.received =>
    languageCode == 'en'
        ? 'Received by the server.'
        : 'เซิร์ฟเวอร์รับเรื่องแล้ว',
};

class ContentReportStatus extends StatelessWidget {
  const ContentReportStatus({
    super.key,
    required this.record,
    this.languageCode = 'th',
    this.showReportId = true,
    this.showDelivery = true,
  });
  final ContentReportRecord record;
  final String languageCode;
  final bool showReportId;
  final bool showDelivery;
  @override
  Widget build(BuildContext context) {
    final en = languageCode == 'en';
    final ack = record.acknowledgement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDelivery)
          Text(contentReportDeliveryLabel(record.delivery, languageCode)),
        if (showReportId) SelectableText(record.payload.reportId),
        if (ack != null) ...[
          SelectableText(ack.receipt.receiptId),
          Text(ack.receipt.receivedAtUtc.toIso8601String()),
          Text(switch (ack.moderation.status) {
            ContentReportModerationStatus.received =>
              en ? 'Awaiting moderation.' : 'รอตรวจสอบรายงาน',
            ContentReportModerationStatus.resolved =>
              en ? 'Review closed, resolved.' : 'ตรวจสอบเสร็จ ปิดรายงานแล้ว',
            ContentReportModerationStatus.dismissed =>
              en ? 'Review closed, dismissed.' : 'ตรวจสอบเสร็จ ไม่ดำเนินการ',
          }),
          if (ack.moderation.publicNote != null)
            SelectableText(ack.moderation.publicNote!),
          Text(
            en
                ? 'A review status does not confirm that source content changed.'
                : 'สถานะตรวจสอบไม่ได้ยืนยันว่าเนื้อหาต้นทางถูกเปลี่ยนแล้ว',
          ),
        ],
      ],
    );
  }
}

Widget _sheetBody(BuildContext context, List<Widget> children) => SafeArea(
  child: SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children
          .map(
            (child) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: child,
            ),
          )
          .toList(),
    ),
  ),
);

class ContentReportOwnerGuard extends StatefulWidget {
  const ContentReportOwnerGuard({
    super.key,
    required this.expectedOwnerId,
    required this.ownerChanges,
    required this.builder,
    required this.languageCode,
    this.sourceLease,
    this.resumeSameOwner = false,
  });
  final String expectedOwnerId;
  final Stream<String?> ownerChanges;
  final Widget Function(BuildContext, bool) builder;
  final String languageCode;
  final ValueListenable<bool>? sourceLease;
  final bool resumeSameOwner;
  static bool currentOf(BuildContext context) =>
      context.findAncestorStateOfType<_ReportOwnerGuardState>()?._current ==
      true;
  @override
  State<ContentReportOwnerGuard> createState() => _ReportOwnerGuardState();
}

class _ReportOwnerGuardState extends State<ContentReportOwnerGuard>
    with WidgetsBindingObserver {
  WordReportOwnerScope? _scope;
  bool _invalidated = false;
  bool _everCurrent = false;
  bool _foreground = false;
  bool _paneVisible = false;
  int _generation = -1;
  ModalRoute<dynamic>? _route;
  bool get _current => !_invalidated && _scope?.current == true;
  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _scope = WordReportOwnerScope(
      expectedOwnerId: widget.expectedOwnerId,
      ownerChanges: widget.ownerChanges,
      visible: () =>
          mounted &&
          !_invalidated &&
          _foreground &&
          _paneVisible &&
          widget.sourceLease?.value != false &&
          _route?.isCurrent == true,
    )..addListener(_changed);
    widget.sourceLease?.addListener(_sourceChanged);
  }

  void _sourceChanged() {
    if (widget.sourceLease?.value == false) _invalidated = true;
    _scope?.synchronize();
  }

  void _changed() {
    final scope = _scope!;
    if (_everCurrent &&
        (_generation != scope.ownerGeneration ||
            (!scope.current &&
                (!widget.resumeSameOwner ||
                    _foreground ||
                    !_paneVisible ||
                    _route?.isCurrent != true ||
                    widget.sourceLease?.value == false)))) {
      _invalidated = true;
    }
    if (scope.current) {
      _everCurrent = true;
      _generation = scope.ownerGeneration;
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _paneVisible =
        ModalRoute.isCurrentOf(context) == true && Visibility.of(context);
    _scope?.synchronize();
  }

  @override
  void didUpdateWidget(covariant ContentReportOwnerGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges) ||
        !identical(oldWidget.sourceLease, widget.sourceLease) ||
        oldWidget.resumeSameOwner != widget.resumeSameOwner) {
      oldWidget.sourceLease?.removeListener(_sourceChanged);
      widget.sourceLease?.addListener(_sourceChanged);
      _invalidated = true;
      _scope?.invalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground &&
        (!widget.resumeSameOwner || state == AppLifecycleState.detached)) {
      _invalidated = true;
    }
    _scope?.synchronize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.sourceLease?.removeListener(_sourceChanged);
    _scope?.removeListener(_changed);
    unawaited(_scope?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) {
      return _sheetBody(context, [
        Text(
          widget.languageCode == 'en'
              ? 'Checking owner. If the account changed, close and reopen this report.'
              : 'กำลังตรวจเจ้าของ หากเปลี่ยนบัญชีแล้ว ให้ปิดแล้วเปิดรายงานใหม่',
        ),
      ]);
    }
    return Builder(builder: (context) => widget.builder(context, _current));
  }
}
