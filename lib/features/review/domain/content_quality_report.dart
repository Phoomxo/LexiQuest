import '../../learning_packs/domain/content_manifest.dart';

enum ContentReportReason { text, audio, answer, explanation }

typedef ReportContentAction =
    Future<void> Function({
      required ContentIdentity identity,
      required ContentReportReason reason,
      String? comment,
    });

final class ContentQualityReport {
  ContentQualityReport({
    required this.id,
    required this.contentIdentity,
    required this.reason,
    required String? comment,
    required this.submittedAtUtc,
  }) : comment = canonicalContentReportComment(comment) {
    _requireCanonicalText(id, 'id');
    _requireCanonicalText(contentIdentity.id, 'contentIdentity.id');
    if (contentIdentity.revision <= 0) {
      throw ArgumentError.value(
        contentIdentity.revision,
        'contentIdentity.revision',
        'must be positive',
      );
    }
    if (!submittedAtUtc.isUtc || submittedAtUtc.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(
        submittedAtUtc,
        'submittedAtUtc',
        'must be a nonnegative UTC time',
      );
    }
  }

  static const int maxCommentRunes = 500;

  final String id;
  final ContentIdentity contentIdentity;
  final ContentReportReason reason;
  final String? comment;
  final DateTime submittedAtUtc;
}

String? canonicalContentReportComment(String? value) {
  if (value == null) return null;
  if (value.isEmpty || value != value.trim() || _controlText.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'comment',
      'must be canonical single-line text of at most '
          '${ContentQualityReport.maxCommentRunes} Unicode characters',
    );
  }
  final redacted = redactContentReportSecrets(value);
  if (redacted.runes.length > ContentQualityReport.maxCommentRunes) {
    throw ArgumentError.value(
      value,
      'comment',
      'redacted output must contain at most '
          '${ContentQualityReport.maxCommentRunes} Unicode characters',
    );
  }
  return redacted;
}

String redactContentReportSecrets(String value) {
  return value.replaceAllMapped(_labeledSecret, (match) {
    return '${match.group(1)}${match.group(2)}[redacted]';
  });
}

final RegExp _controlText = RegExp(
  r'[\u0000-\u001f\u007f-\u009f]',
  unicode: true,
);
final RegExp _labeledSecret = RegExp(
  r'(provider(?:token|key|secret)|device(?:id|identifier|token))'
  r'\s*([:=])\s*([^,;\s]+)',
  caseSensitive: false,
);

void _requireCanonicalText(String value, String name) {
  if (!isCanonicalContentReportIdentityText(value)) {
    throw ArgumentError.value(value, name, 'must be canonical nonblank text');
  }
}

bool isCanonicalContentReportIdentityText(String value) =>
    value.isNotEmpty &&
    value == value.trim() &&
    value.runes.length <= 256 &&
    !_controlText.hasMatch(value);
