import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/application/content_report_use_cases.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

import 'content_report_test_support.dart';

void main() {
  test(
    'missing session authority fails closed without queue or ID allocation',
    () async {
      final queue = MemoryContentReportQueue();
      var ids = 0;
      final reports = ContentReportUseCases(
        queue: queue,
        generateId: () => '${++ids}',
        nowUtc: () => DateTime.utc(2026),
      );
      await expectLater(
        reports.requireOrdinarySession(
          expectedOwnerId: 'owner',
          sessionId: 'synthetic-session',
          stillCurrent: () => true,
        ),
        throwsA(
          isA<ContentReportException>().having(
            (error) => error.code,
            'code',
            ContentReportFailureCode.unavailable,
          ),
        ),
      );
      expect(queue.rows, isEmpty);
      expect(ids, 0);
    },
  );
  test(
    'session read guard receives exact binding and rechecks the live lease after await',
    () async {
      var current = true;
      final reports = ContentReportUseCases(
        queue: MemoryContentReportQueue(),
        generateId: () => 'unused',
        nowUtc: () => DateTime.utc(2026),
        ordinarySessionGuard:
            ({
              required String expectedOwnerId,
              required String sessionId,
              required bool Function() stillCurrent,
            }) async {
              expect(expectedOwnerId, 'owner');
              expect(sessionId, 'synthetic-session');
              expect(stillCurrent(), isTrue);
              current = false;
            },
      );
      await expectLater(
        reports.requireOrdinarySession(
          expectedOwnerId: 'owner',
          sessionId: 'synthetic-session',
          stillCurrent: () => current,
        ),
        throwsA(
          isA<ContentReportException>().having(
            (error) => error.code,
            'code',
            ContentReportFailureCode.ownerChanged,
          ),
        ),
      );
    },
  );
  test(
    'unrecorded origin is explicit and does not alter accepted AI source facts',
    () {
      final target = ContentReportTarget.aiOutput(
        text: 'The synthetic source.',
        isExcerpt: false,
        sessionId: 'synthetic-session',
        acceptedPlanId: 'synthetic-plan',
        contentKind: 'sentence',
        modelVersion: 'synthetic-model',
        cached: true,
        origin: ContentReportAiOrigin.unrecorded,
      );
      final source =
          (jsonDecode(target.snapshotJson) as Map<String, dynamic>)['source'];
      expect(source, {
        'sessionId': 'synthetic-session',
        'acceptedPlanId': 'synthetic-plan',
        'contentKind': 'sentence',
        'modelVersion': 'synthetic-model',
        'cached': true,
        'origin': 'unrecorded',
      });
    },
  );
  test(
    'runtime revalidation callbacks do not change the legacy nine-field snapshot or replay identity',
    () {
      final json = jsonEncode({
        'version': 'owned-word-report-v1',
        'wordId': 'synthetic-word',
        'categoryId': 'synthetic-category',
        'wordRevision': 1,
        'spelling': 'word',
        'meaning': 'คำ',
        'partOfSpeech': 'noun',
        'source': 'manual',
        'cefrLevel': null,
      });
      final target = WordReportTarget.fromSnapshot(
        snapshotJson: json,
        snapshotSha256: contentReportDigest(json),
      );
      final at = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);
      final command = WordReportCommand(
        id: 'word-report:synthetic',
        expectedOwnerId: 'owner',
        target: target,
        reason: ReportReason.spelling,
        comment: null,
        queuedAtUtc: at,
        revalidate: () async {},
      );
      final stored = StoredWordReport(
        id: command.id,
        ownerId: 'owner',
        target: target,
        reason: command.reason,
        comment: null,
        queuedAtUtc: at,
      );
      expect(stored.matchesCommand(command), isTrue);
      expect(stored.target.snapshotJson, json);
      expect(jsonDecode(stored.target.snapshotJson).length, 9);
      expect(stored.toStorage().containsKey('revalidate'), isFalse);
    },
  );
}
