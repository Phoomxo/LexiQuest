import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

void main() {
  ContentReportTarget target() => ContentReportTarget.tutorReply(
    text: 'Selected assistant reply only',
    isExcerpt: false,
    replyId: 'synthetic-reply',
    modelVersion: 'synthetic-model',
    generatedAtUtcMs: 1000,
  );

  test('new target has closed fields and immutable exact text digest', () {
    final value = target();
    final json = jsonDecode(value.snapshotJson) as Map<String, dynamic>;
    expect(json.keys.toSet(), {
      'version',
      'kind',
      'text',
      'textSha256',
      'isExcerpt',
      'source',
    });
    expect(
      json['textSha256'],
      sha256.convert(utf8.encode(value.text)).toString(),
    );
    expect(json['isExcerpt'], isFalse);
    expect(json['source'], {
      'replyId': 'synthetic-reply',
      'modelVersion': 'synthetic-model',
      'generatedAtUtcMs': 1000,
    });
  });

  test('long content requires explicit selection instead of truncation', () {
    expect(
      () => ContentReportTarget.tutorReply(
        text: 'x' * 4097,
        isExcerpt: false,
        replyId: 'synthetic-reply',
        modelVersion: 'synthetic-model',
        generatedAtUtcMs: 1000,
      ),
      throwsArgumentError,
    );
  });

  test(
    'payload replay preserves exact reviewed bytes and rejects duplicate keys',
    () {
      final payload = ContentReportPayload.create(
        reportId: 'content-report:synthetic',
        target: target(),
        reason: ReportReason.inappropriate,
        comment: null,
        queuedAtUtc: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
      );
      final restored = ContentReportPayload.fromStorage(
        reportJson: payload.reportJson,
        reportSha256: payload.reportSha256,
      );
      expect(restored.reportJson, payload.reportJson);
      expect(restored.reportSha256, payload.reportSha256);
      final duplicate = payload.reportJson.replaceFirst(
        '"schemaVersion":1',
        '"schemaVersion":1,"schemaVersion":1',
      );
      expect(
        () => ContentReportPayload.fromStorage(
          reportJson: duplicate,
          reportSha256: sha256.convert(utf8.encode(duplicate)).toString(),
        ),
        throwsFormatException,
      );
    },
  );

  test('all v2 targets preserve their exact closed source facts', () {
    final hash = 'a' * 64;
    final targets = [
      ContentReportTarget.packEntry(
        text: 'selected entry',
        isExcerpt: true,
        packId: 'synthetic-pack',
        packVersion: '1',
        packageSha256: hash,
        entryCode: 'entry',
        entrySha256: hash,
      ),
      ContentReportTarget.aiOutput(
        text: 'selected output',
        isExcerpt: false,
        sessionId: 'session',
        acceptedPlanId: 'plan',
        contentKind: 'hint',
        modelVersion: 'model',
        cached: true,
        origin: ContentReportAiOrigin.fallback,
      ),
      ContentReportTarget.readingDocument(
        text: 'selected passage',
        isExcerpt: true,
        documentId: hash,
        documentRevision: 2,
        documentSha256: hash,
        identityKind: ContentReportDocumentIdentity.contentDigest,
      ),
    ];
    for (final target in targets) {
      final restored = ContentReportTarget.fromSnapshot(
        snapshotJson: target.snapshotJson,
        snapshotSha256: target.snapshotSha256,
      );
      expect(restored.snapshotJson, target.snapshotJson);
      expect(restored.snapshotSha256, target.snapshotSha256);
      final edited = (jsonDecode(target.snapshotJson) as Map<String, dynamic>)
        ..['learnerPrompt'] = 'forbidden';
      final json = jsonEncode(edited);
      expect(
        () => ContentReportTarget.fromSnapshot(
          snapshotJson: json,
          snapshotSha256: contentReportDigest(json),
        ),
        throwsFormatException,
      );
    }
  });

  test('escaped duplicate receipt keys and malformed moderation fail closed', () {
    final receipt =
        '{"schemaVersion":1,"receipt":{"reportId":"content-report:x",'
        '"reportSha256":"${'a' * 64}","receiptId":"content-report-receipt:${'b' * 64}",'
        '"receivedAtUtc":"2026-11-01T00:00:00.000Z"},'
        '"moderation":{"revision":1,"status":"received","decisionId":null,"publicNote":null,"decidedAtUtc":null}}';
    expect(
      ContentReportAcknowledgement.fromResponseJson(
        receipt,
      ).moderation.revision,
      1,
    );
    final duplicate = receipt.replaceFirst(
      '"revision":1',
      '"revision":1,"revis\\u0069on":1',
    );
    expect(
      () => ContentReportAcknowledgement.fromResponseJson(duplicate),
      throwsFormatException,
    );
    expect(
      () => ContentReportAcknowledgement.fromResponseJson(
        receipt.replaceFirst('"revision":1', '"revision":2'),
      ),
      throwsFormatException,
    );
    expect(
      () => ContentReportAcknowledgement.fromResponseJson(
        receipt.replaceFirst('${'a' * 64}"', '${'a' * 64}\\n"'),
      ),
      throwsFormatException,
    );
  });
}
