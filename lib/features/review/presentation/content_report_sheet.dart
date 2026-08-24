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

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _submitting) return;
    final trimmed = _comment.text.trim();
    final comment = trimmed.isEmpty ? null : trimmed;
    if (comment != null &&
        comment.runes.length > ContentQualityReport.maxCommentRunes) {
      setState(() => _error = 'Comment is too long');
      return;
    }
    try {
      canonicalContentReportComment(comment);
    } on ArgumentError {
      setState(() => _error = 'Comment contains unsupported text');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(reason: reason, comment: comment);
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Unable to submit report');
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
                    'Report content',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Close content report',
                  child: ExcludeSemantics(
                    child: IconButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ],
            ),
            Text('Revision ${widget.identity.revision}'),
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
                labelText: 'Optional comment',
                helperText: 'Do not include account, provider, or device data.',
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
              child: Text(_submitting ? 'Submitting…' : 'Submit report'),
            ),
          ],
        ),
      ),
    );
  }
}

String _reasonLabel(ContentReportReason reason) => switch (reason) {
  ContentReportReason.text => 'Text problem',
  ContentReportReason.audio => 'Audio problem',
  ContentReportReason.answer => 'Answer problem',
  ContentReportReason.explanation => 'Explanation problem',
};
