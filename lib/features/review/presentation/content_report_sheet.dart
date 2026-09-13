import 'package:flutter/material.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../domain/content_quality_report.dart';

typedef ContentReportSheetSubmit =
    Future<void> Function({
      required ContentReportReason reason,
      String? comment,
    });

final class ContentReportSheet extends StatefulWidget {
  const ContentReportSheet({
    super.key,
    required this.identity,
    required this.onSubmit,
  });

  final ContentIdentity identity;
  final ContentReportSheetSubmit onSubmit;

  @override
  State<ContentReportSheet> createState() => _ContentReportSheetState();
}

final class _ContentReportSheetState extends State<ContentReportSheet> {
  final TextEditingController _comment = TextEditingController();
  ContentReportReason? _reason;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _close() {
    if (_submitting) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _submitting) return;
    final trimmed = _comment.text.trim();
    final comment = trimmed.isEmpty ? null : trimmed;
    if (comment != null &&
        comment.runes.length > ContentQualityReport.maxCommentRunes) {
      setState(() => _error = 'ความคิดเห็นยาวเกินกำหนด');
      return;
    }
    try {
      canonicalContentReportComment(comment);
    } on ArgumentError {
      setState(() => _error = 'ความคิดเห็นมีข้อความที่ไม่รองรับ');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(reason: reason, comment: comment);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'บันทึกรายงานในเครื่องแล้ว ยังไม่ยืนยันการส่งถึงปลายทาง',
          ),
        ),
      );
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'ยังยืนยันการส่งรายงานไม่ได้');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'รายงานเนื้อหา',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'ปิดการรายงานเนื้อหา',
                  enabled: !_submitting,
                  onTap: _submitting ? null : _close,
                  child: ExcludeSemantics(
                    child: IconButton(
                      onPressed: _submitting ? null : _close,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ],
            ),
            Text('รุ่น ${widget.identity.revision}'),
            const SizedBox(height: 8),
            RadioGroup<ContentReportReason>(
              groupValue: _reason,
              onChanged: (value) {
                if (!_submitting) setState(() => _reason = value);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final reason in ContentReportReason.values)
                    RadioListTile<ContentReportReason>(
                      value: reason,
                      enabled: !_submitting,
                      title: Text(_reasonLabel(reason)),
                    ),
                ],
              ),
            ),
            TextField(
              controller: _comment,
              enabled: !_submitting,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'ความคิดเห็นเพิ่มเติม (ไม่จำเป็น)',
                helperText: 'ไม่ระบุข้อมูลบัญชี ผู้ให้บริการ หรืออุปกรณ์',
              ),
            ),
            if (_error case final error?) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _reason == null || _submitting ? null : _submit,
              child: Text(_submitting ? 'กำลังบันทึกรายงาน…' : 'ส่งรายงาน'),
            ),
          ],
        ),
      ),
    );
  }
}

String _reasonLabel(ContentReportReason reason) => switch (reason) {
  ContentReportReason.text => 'ปัญหาข้อความ',
  ContentReportReason.audio => 'ปัญหาเสียง',
  ContentReportReason.answer => 'ปัญหาคำตอบ',
  ContentReportReason.explanation => 'ปัญหาคำอธิบาย',
};
