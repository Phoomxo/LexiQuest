import 'package:flutter/material.dart';

import '../../../widgets/word_report_sheet.dart';
import '../application/content_report_use_cases.dart';
import '../domain/content_report.dart';
import 'content_report_sheet.dart';

class ContentReportInbox extends StatefulWidget {
  const ContentReportInbox({
    super.key,
    required this.expectedOwnerId,
    required this.reports,
    required this.ownerChanges,
    this.languageCode = 'th',
  });
  final String expectedOwnerId;
  final ContentReportUseCases reports;
  final Stream<String?> ownerChanges;
  final String languageCode;
  @override
  State<ContentReportInbox> createState() => _ContentReportInboxState();
}

class _ContentReportInboxState extends State<ContentReportInbox> {
  late Stream<List<ContentReportRecord>> _rows;
  final _updated = <String, ContentReportRecord>{};
  String? _busyId;
  String? _error;
  bool _invalidated = false;
  String _text(String th, String en) => widget.languageCode == 'en' ? en : th;
  @override
  void initState() {
    super.initState();
    _rows = widget.reports.watchOwner(widget.expectedOwnerId);
  }

  @override
  void didUpdateWidget(covariant ContentReportInbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedOwnerId != widget.expectedOwnerId ||
        !identical(oldWidget.reports, widget.reports) ||
        !identical(oldWidget.ownerChanges, widget.ownerChanges)) {
      _invalidated = true;
      _updated.clear();
    }
  }

  Future<void> _operate(
    BuildContext scopeContext,
    ContentReportRecord row, {
    required bool send,
  }) async {
    if (_busyId != null || !ContentReportOwnerGuard.currentOf(scopeContext)) {
      return;
    }
    bool current() =>
        mounted &&
        !_invalidated &&
        scopeContext.mounted &&
        ContentReportOwnerGuard.currentOf(scopeContext);
    setState(() {
      _busyId = row.payload.reportId;
      _error = null;
    });
    try {
      final updated = await (send
          ? widget.reports.send(
              expectedOwnerId: widget.expectedOwnerId,
              reportId: row.payload.reportId,
            )
          : widget.reports.refresh(
              expectedOwnerId: widget.expectedOwnerId,
              reportId: row.payload.reportId,
            ));
      if (current()) setState(() => _updated[row.payload.reportId] = updated);
    } on Object {
      try {
        final updated = await widget.reports.queue.read(
          expectedOwnerId: widget.expectedOwnerId,
          reportId: row.payload.reportId,
        );
        if (current() && updated != null) {
          setState(() => _updated[row.payload.reportId] = updated);
        }
      } on Object {
        /* Preserve the original report when owner storage is unavailable. */
      }
      if (current()) {
        setState(
          () => _error = _text(
            'ตรวจผลไม่ได้ รายงานเดิมยังอยู่ ลองตรวจใบรับเรื่องอีกครั้งเมื่อพร้อม',
            'The result could not be checked. Keep the original report and check its receipt again.',
          ),
        );
      }
    } finally {
      if (current()) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_text('รายงานเนื้อหา', 'Content reports'))),
    body: _invalidated
        ? Center(
            child: Text(
              _text(
                'ข้อมูลเปลี่ยนแล้ว กรุณาปิดแล้วเปิดใหม่',
                'The context changed. Close and reopen.',
              ),
            ),
          )
        : ContentReportOwnerGuard(
            expectedOwnerId: widget.expectedOwnerId,
            ownerChanges: widget.ownerChanges,
            languageCode: widget.languageCode,
            builder: (scopeContext, current) =>
                StreamBuilder<List<ContentReportRecord>>(
                  stream: _rows,
                  builder: (context, snapshot) {
                    if (snapshot.hasError ||
                        (snapshot.hasData &&
                            snapshot.data!.any(
                              (row) => row.ownerId != widget.expectedOwnerId,
                            ))) {
                      return Center(
                        child: Text(
                          _text(
                            'อ่านรายงานไม่ได้ กรุณาปิดแล้วเปิดใหม่',
                            'Reports are unavailable. Close and reopen.',
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final rows = snapshot.data!;
                    return ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          _text(
                            'บันทึกในเครื่องและส่งแยกกัน การตรวจใบรับเรื่องจะไม่ส่งรายงาน',
                            'Saving and sending are separate actions. Checking receipts never sends a report.',
                          ),
                        ),
                        if (!widget.reports.transport.enabled)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _text(
                                'การส่งยังไม่เปิดใช้งาน',
                                'Sending is unavailable.',
                              ),
                            ),
                          ),
                        if (_error != null)
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              _text(
                                'ยังไม่มีรายงานเนื้อหาในเครื่องนี้',
                                'No content reports on this device.',
                              ),
                            ),
                          ),
                        for (final initial in rows)
                          _report(
                            scopeContext,
                            (_updated[initial.payload.reportId]
                                            ?.localRevision ??
                                        0) >
                                    initial.localRevision
                                ? _updated[initial.payload.reportId]!
                                : initial,
                            current,
                          ),
                      ],
                    );
                  },
                ),
          ),
  );

  Widget _report(
    BuildContext context,
    ContentReportRecord row,
    bool current,
  ) => ExpansionTile(
    key: ValueKey('content-report-row-${row.payload.reportId}'),
    title: Text(wordReportReasonLabel(row.payload.reason, widget.languageCode)),
    subtitle: Text(row.payload.queuedAtUtc.toIso8601String()),
    childrenPadding: const EdgeInsets.only(bottom: 16),
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        row.payload.target.isExcerpt
            ? _text('ข้อความบางส่วนที่เลือก', 'Selected excerpt')
            : _text('เนื้อหาที่เลือก', 'Selected content'),
      ),
      SelectableText(row.payload.target.text),
      if (row.payload.comment != null) SelectableText(row.payload.comment!),
      ContentReportStatus(record: row, languageCode: widget.languageCode),
      ExpansionTile(
        title: Text(_text('ข้อมูลต้นทางที่แนบ', 'Attached source facts')),
        children: [SelectableText(row.payload.target.snapshotJson)],
      ),
      if (_busyId == row.payload.reportId) const LinearProgressIndicator(),
      if (row.acknowledgement == null)
        FilledButton(
          key: ValueKey('content-report-send-${row.payload.reportId}'),
          onPressed:
              !current || _busyId != null || !widget.reports.transport.enabled
              ? null
              : () => _operate(context, row, send: true),
          child: Text(_text('ส่งเนื้อหาที่ตรวจแล้ว', 'Send reviewed content')),
        ),
      OutlinedButton(
        key: ValueKey('content-report-refresh-${row.payload.reportId}'),
        onPressed:
            !current || _busyId != null || !widget.reports.transport.enabled
            ? null
            : () => _operate(context, row, send: false),
        child: Text(
          _text('ตรวจใบรับเรื่องและสถานะ', 'Check receipt and review status'),
        ),
      ),
    ],
  );
}
