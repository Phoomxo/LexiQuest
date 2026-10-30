import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

void main() {
  final now = DateTime.utc(2026, 10, 30, 12);
  VocabularyWord word({String ownerId = 'synthetic-owner', int revision = 7}) =>
      VocabularyWord(
        id: 'synthetic-word',
        ownerId: ownerId,
        categoryId: 'synthetic-category',
        spelling: 'station',
        normalizedSpelling: 'station',
        meaning: 'synthetic meaning',
        normalizedMeaning: 'synthetic meaning',
        partOfSpeech: 'noun',
        source: 'manual',
        isGlobal: false,
        localRevision: revision,
        isDeleted: false,
        createdAtUtc: now,
        updatedAtUtc: now,
      );
  StoredWordReport report({String ownerId = 'synthetic-owner'}) =>
      StoredWordReport(
        id: 'word-report:synthetic',
        ownerId: ownerId,
        target: WordReportTarget.fromWord(word()),
        reason: ReportReason.incorrectMeaning,
        comment: 'synthetic detail',
        queuedAtUtc: now,
      );

  test(
    'pure displayed target has exactly nine ordered ownerless canonical keys',
    () {
      final target = WordReportTarget.fromWord(word());
      final json = jsonDecode(target.snapshotJson) as Map;
      expect(json.keys, [
        'version',
        'wordId',
        'categoryId',
        'wordRevision',
        'spelling',
        'meaning',
        'partOfSpeech',
        'source',
        'cefrLevel',
      ]);
      expect(json['version'], wordReportSnapshotVersion);
      expect(json['cefrLevel'], isNull);
      expect(
        target.snapshotSha256,
        sha256.convert(utf8.encode(target.snapshotJson)).toString(),
      );
      expect(
        target.sameTarget(
          WordReportTarget.fromWord(word(ownerId: 'another-owner')),
        ),
        isTrue,
      );
      expect(
        target.sameTarget(WordReportTarget.fromWord(word(revision: 8))),
        isFalse,
      );
      expect(json.containsKey('ownerId'), isFalse);
    },
  );

  test(
    'all visible content and source pins contribute to the target identity',
    () {
      final original = word();
      final target = WordReportTarget.fromWord(original);
      for (final changed in [
        original.copyWith(spelling: 'ticket'),
        original.copyWith(meaning: 'changed'),
        original.copyWith(partOfSpeech: 'verb'),
        original.copyWith(source: 'import'),
        original.copyWith(cefrLevel: 'A2'),
      ]) {
        expect(target.sameTarget(WordReportTarget.fromWord(changed)), isFalse);
      }
    },
  );

  for (final mutation in [
    'order',
    'whitespace',
    'duplicate',
    'owner',
    'double-revision',
    'version',
  ]) {
    test(
      'strict snapshot parser rejects recomputed-hash $mutation representation',
      () {
        final target = WordReportTarget.fromWord(word());
        final json = Map<String, Object?>.from(
          jsonDecode(target.snapshotJson) as Map,
        );
        final String altered;
        switch (mutation) {
          case 'order':
            altered = jsonEncode(
              Map.fromEntries(json.entries.toList().reversed),
            );
          case 'whitespace':
            altered = ' ${target.snapshotJson}';
          case 'duplicate':
            altered = target.snapshotJson.replaceFirst(
              '{',
              '{"wordId":"synthetic-word",',
            );
          case 'owner':
            json['ownerId'] = 'synthetic-private-owner';
            altered = jsonEncode(json);
          case 'double-revision':
            json['wordRevision'] = 7.0;
            altered = jsonEncode(json);
          case 'version':
            json['version'] = 'invented';
            altered = jsonEncode(json);
          default:
            throw StateError('synthetic case missing');
        }
        parse(String hash) => WordReportTarget.fromSnapshot(
          snapshotJson: altered,
          snapshotSha256: hash,
        );
        expect(
          () => parse(sha256.convert(utf8.encode(altered)).toString()),
          throwsFormatException,
        );
      },
    );
  }

  test('stored codec has exactly ten fields and immutable serialization', () {
    final original = report();
    final row = original.toStorage();
    expect(row.keys, [
      'id',
      'owner_id',
      'word_id',
      'category_id',
      'word_revision',
      'snapshot_json',
      'snapshot_sha256',
      'reason',
      'comment',
      'queued_at_utc_ms',
    ]);
    expect(() => row['reason'] = 'other', throwsUnsupportedError);
    expect(StoredWordReport.fromStorage(row).sameFacts(original), isTrue);
    final moved = report(ownerId: 'synthetic-new-owner');
    expect(moved.sameHistoricalPayload(original), isTrue);
    expect(moved.sameFacts(original), isFalse);
  });

  for (final pin in [
    'word_id',
    'category_id',
    'word_revision',
    'snapshot_sha256',
    'reason',
    'comment',
    'queued_at_utc_ms',
  ]) {
    test('stored codec rejects malformed or mismatched $pin', () {
      final row = Map<String, Object?>.from(report().toStorage());
      row[pin] = switch (pin) {
        'word_revision' => 8,
        'snapshot_sha256' => List.filled(64, 'A').join(),
        'reason' => 'invented',
        'comment' => ' not normalized ',
        'queued_at_utc_ms' => -1,
        _ => 'different-id',
      };
      expect(() => StoredWordReport.fromStorage(row), throwsFormatException);
    });
  }

  test(
    'stored parser rejects extra/missing columns and invalid JSON without disclosing it',
    () {
      final row = report().toStorage();
      expect(
        () => StoredWordReport.fromStorage({...row, 'status': 'sent'}),
        throwsFormatException,
      );
      expect(
        () => StoredWordReport.fromStorage(
          Map<String, Object?>.from(row)..remove('word_id'),
        ),
        throwsFormatException,
      );
      const private = 'SYNTHETIC_PRIVATE_REPORT_CANARY';
      try {
        WordReportTarget.fromSnapshot(
          snapshotJson: private,
          snapshotSha256: sha256.convert(utf8.encode(private)).toString(),
        );
        fail('invalid snapshot was admitted');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains(private)));
      }
    },
  );

  test(
    'canonical comment and opaque ID bounds include UTF8 and other detail',
    () {
      WordReportCommand command({
        String? id,
        String? comment = 'detail',
        ReportReason reason = ReportReason.other,
      }) => WordReportCommand(
        id: id ?? 'word-report:synthetic',
        expectedOwnerId: 'synthetic-owner',
        target: WordReportTarget.fromWord(word()),
        reason: reason,
        comment: comment,
        queuedAtUtc: now,
      );
      expect(() => command(comment: null), throwsArgumentError);
      expect(() => command(comment: '  '), throwsArgumentError);
      expect(
        () => command(comment: List.filled(501, 'a').join()),
        throwsArgumentError,
      );
      expect(
        () => command(id: 'word-report:${List.filled(62, '😀').join()}'),
        throwsArgumentError,
      );
      expect(
        command(reason: ReportReason.spelling, comment: null).comment,
        isNull,
      );
    },
  );
}
