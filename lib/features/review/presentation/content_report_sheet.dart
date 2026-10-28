import 'package:flutter/material.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../domain/content_quality_report.dart';
import '../domain/review_mutation_context.dart';
import 'review_mutation_state.dart';

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
    this.canSubmit,
    this.expectedOwnerId,
  });

  final ContentIdentity identity;
  final ContentReportSheetSubmit onSubmit;
  final bool Function()? canSubmit;
  final String? expectedOwnerId;

  @override
  State<ContentReportSheet> createState() => _ContentReportSheetState();
}

final class _ContentReportSheetState
    extends ReviewMutationState<ContentReportSheet> {
  final TextEditingController _comment = TextEditingController();
  ContentReportReason? _reason;
  bool _submitting = false;
  String? _error;

  bool get _canEdit =>
      mutationVisible && !_submitting && widget.canSubmit?.call() != false;

  @override
  void retireMutation() {
    super.retireMutation();
    _submitting = false;
    _error = null;
  }

  @override
  void didUpdateWidget(ContentReportSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.onSubmit != widget.onSubmit ||
        oldWidget.expectedOwnerId != widget.expectedOwnerId) {
      retireMutation();
      _reason = null;
      _comment.clear();
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _close() {
    if (!_canEdit) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (!mutationVisible ||
        reason == null ||
        _submitting ||
        widget.canSubmit?.call() == false)
      return;
    final generation = mutationGeneration;
    final canSubmit = widget.canSubmit;
    final action = widget.onSubmit;
    final expectedOwnerId = widget.expectedOwnerId;
    bool current() => mutationCurrent(generation) && canSubmit?.call() != false;
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
      await ReviewMutationContext.run(
        () => action(reason: reason, comment: comment),
        isCurrent: current,
        expectedOwnerId: expectedOwnerId,
      );
      if (!current()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'บันทึกรายงานในเครื่องแล้ว ยังไม่ยืนยันการส่งถึงปลายทาง',
          ),
        ),
      );
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (_) {
      if (!current()) return;
      setState(() => _error = 'ยังยืนยันการส่งรายงานไม่ได้');
    } finally {
      if (mounted && generation == mutationGeneration)
        setState(() => _submitting = false);
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
                if (_canEdit) setState(() => _reason = value);
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
