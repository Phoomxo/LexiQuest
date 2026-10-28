import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/application/content_report_use_cases.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report_repository.dart';

void main() {
  test(
    'reason codes are the exact bounded text audio answer explanation set',
    () {
      expect(ContentReportReason.values, const <ContentReportReason>[
        ContentReportReason.text,
        ContentReportReason.audio,
        ContentReportReason.answer,
        ContentReportReason.explanation,
      ]);
      expect(
        ContentReportReason.values.map((reason) => reason.name),
        const <String>['text', 'audio', 'answer', 'explanation'],
      );
    },
  );

  test(
    'freezes generated id pinned identity UTC time and optional comment',
    () async {
      final repository = _CapturingRepository();
      final submittedAt = DateTime.utc(2026, 8, 24, 12);
      final useCases = ContentReportUseCases(
        repository: repository,
        generateId: () => 'report:one',
        nowUtc: () => submittedAt,
      );

      await useCases.report(
        identity: _identity,
        reason: ContentReportReason.audio,
      );

      expect(repository.reports, hasLength(1));
      final report = repository.reports.single;
      expect(report.id, 'report:one');
      expect(report.contentIdentity, _identity);
      expect(report.reason, ContentReportReason.audio);
      expect(report.comment, isNull);
      expect(report.submittedAtUtc, submittedAt);
    },
  );

  test(
    'requires a positive pinned revision before repository invocation',
    () async {
      final repository = _CapturingRepository();
      final useCases = ContentReportUseCases(
        repository: repository,
        generateId: () => 'report:invalid',
        nowUtc: () => DateTime.utc(2026, 8, 24, 12),
      );

      await expectLater(
        useCases.report(
          identity: const ContentIdentity(
            type: ContentType.lexicalMetadata,
            id: 'word:station',
            revision: 0,
          ),
          reason: ContentReportReason.text,
        ),
        throwsArgumentError,
      );
      expect(repository.reports, isEmpty);
    },
  );

  test(
    'rejects control text in report and pinned content identities',
    () async {
      final repository = _CapturingRepository();
      final invalidReportId = ContentReportUseCases(
        repository: repository,
        generateId: () => 'report:\ninvalid',
        nowUtc: () => DateTime.utc(2026, 8, 24, 12),
      );

      await expectLater(
        invalidReportId.report(
          identity: _identity,
          reason: ContentReportReason.text,
        ),
        throwsArgumentError,
      );
      await expectLater(
        ContentReportUseCases(
          repository: repository,
          generateId: () => 'report:valid',
          nowUtc: () => DateTime.utc(2026, 8, 24, 12),
        ).report(
          identity: const ContentIdentity(
            type: ContentType.lexicalMetadata,
            id: 'word:\tstation',
            revision: 1,
          ),
          reason: ContentReportReason.text,
        ),
        throwsArgumentError,
      );
      expect(repository.reports, isEmpty);
    },
  );

  test(
    'comment is canonical bounded Unicode and rejects control text',
    () async {
      final repository = _CapturingRepository();
      final useCases = ContentReportUseCases(
        repository: repository,
        generateId: () => 'report:comment',
        nowUtc: () => DateTime.utc(2026, 8, 24, 12),
      );
      final maximum = List<String>.filled(
        ContentQualityReport.maxCommentRunes,
        'ก',
      ).join();

      await useCases.report(
        identity: _identity,
        reason: ContentReportReason.explanation,
        comment: maximum,
      );
      expect(repository.reports.single.comment, maximum);

      for (final invalid in <String>[
        ' padded ',
        'line one\nline two',
        '$maximumก',
        '',
      ]) {
        await expectLater(
          useCases.report(
            identity: _identity,
            reason: ContentReportReason.text,
            comment: invalid,
          ),
          throwsArgumentError,
          reason: invalid.length.toString(),
        );
      }
      expect(repository.reports, hasLength(1));
    },
  );

  test(
    'redacts labeled provider and device secrets before persistence',
    () async {
      final repository = _CapturingRepository();
      final useCases = ContentReportUseCases(
        repository: repository,
        generateId: () => 'report:redacted',
        nowUtc: () => DateTime.utc(2026, 8, 24, 12),
      );

      await useCases.report(
        identity: _identity,
        reason: ContentReportReason.audio,
        comment:
            'Audio failed providerToken=provider-secret-SENTINEL; '
            'deviceId=device-secret-SENTINEL',
      );

      final comment = repository.reports.single.comment!;
      expect(comment, contains('providerToken=[redacted]'));
      expect(comment, contains('deviceId=[redacted]'));
      expect(comment, isNot(contains('provider-secret-SENTINEL')));
      expect(comment, isNot(contains('device-secret-SENTINEL')));
    },
  );

  test('validates the redacted output length and all C1 controls', () {
    const secret = 'providerToken=x';
    final exactInput =
        '${List<String>.filled(500 - secret.runes.length, 'ก').join()}$secret';
    expect(exactInput.runes.length, ContentQualityReport.maxCommentRunes);

    expect(
      () => canonicalContentReportComment(exactInput),
      throwsArgumentError,
      reason: 'redaction must not expand persisted text past 500 runes',
    );
    expect(
      () => canonicalContentReportComment('invalid\u0085control'),
      throwsArgumentError,
    );
    expect(
      canonicalContentReportComment('xproviderToken=embedded-secret'),
      'xproviderToken=[redacted]',
      reason: 'embedded provider/device labels must not bypass redaction',
    );
    expect(
      () => ContentQualityReport(
        id: 'report\u0085invalid',
        contentIdentity: _identity,
        reason: ContentReportReason.text,
        comment: null,
        submittedAtUtc: DateTime.utc(2026, 8, 24, 12),
      ),
      throwsArgumentError,
    );
  });
}

const _identity = ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: 'word:station',
  revision: 4,
);

final class _CapturingRepository implements ContentQualityReportRepository {
  final List<ContentQualityReport> reports = <ContentQualityReport>[];

  @override
  Future<void> submit(ContentQualityReport report) async {
    reports.add(report);
  }
}
