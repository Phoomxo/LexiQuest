import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning_time/application/learning_time_use_cases.dart';
import 'package:vocab_learning_app/features/learning_time/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_calendar.dart';

import '../../support/review_center_harness.dart';

void main() {
  test(
    'calendar attributes confirmed duration to end date across midnight and reversed UTC',
    () async {
      final h = await _TimeHarness.open();
      addTearDown(h.close);
      h.base.now = DateTime(2026, 11, 1, 23, 59, 59).toUtc();
      await h.record(
        end: DateTime(2026, 11, 2, 0, 0, 1).toUtc(),
        durationUs: 2000000,
      );
      h.base.now = DateTime(2026, 11, 3, 12).toUtc();
      await h.record(
        end: DateTime(2026, 11, 1, 12).toUtc(),
        durationUs: 4000000,
      );
      await h.time.setEnabled(
        false,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      h.base.now = DateTime(2026, 11, 7, 12).toUtc();
      final before = await h.base.snapshotAllTables();
      final result = await h.base.progress.loadCalendarForOwner(
        period: LearningCalendarPeriod.weekEnding(DateTime(2026, 11, 7)),
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
        learningTime: h.time,
      );
      expect(h.time.captureEnabled, isFalse);
      expect(result.days.first.recordedTime.activeDurationUs, 4000000);
      expect(result.days[1].recordedTime.activeDurationUs, 2000000);
      expect(result.recordedTime.activeDurationUs, 6000000);
      expect(
        result.recordedTime.activeDurationUs,
        (await h.time.read(const OwnerTimeRead())).activeDurationUs,
      );
      expect(
        result.days
            .skip(2)
            .every(
              (day) =>
                  day.recordedTime.status == RecordedTimeStatus.noneRecorded,
            ),
        isTrue,
      );
      expect(await h.base.snapshotAllTables(), before);
    },
  );

  test(
    'range is half open and rejects invalid UTC bounds or a different captured owner',
    () async {
      final h = await _TimeHarness.open();
      addTearDown(h.close);
      h.base.now = DateTime.utc(2026, 11, 1, 12);
      final end = h.base.now.add(const Duration(seconds: 1));
      await h.record(end: end, durationUs: 1000000);
      Future<RecordedTimeRead> read(DateTime start, DateTime finish) =>
          h.time.readForOwner(
            ObservedEndRangeTimeRead(
              startInclusiveUtc: start,
              endExclusiveUtc: finish,
            ),
            expectedOwnerId: configuredOwnerId,
            stillCurrent: () => true,
          );
      expect(
        (await read(
          end,
          end.add(const Duration(milliseconds: 1)),
        )).activeDurationUs,
        1000000,
      );
      expect(
        (await read(end.subtract(const Duration(milliseconds: 1)), end)).status,
        RecordedTimeStatus.noneRecorded,
      );
      for (final range in [
        (end, end),
        (end.add(const Duration(seconds: 1)), end),
        (end.toLocal(), end.add(const Duration(seconds: 1))),
        (DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true), end),
        (
          end.add(const Duration(microseconds: 1)),
          end.add(const Duration(seconds: 1)),
        ),
      ]) {
        expect(
          (await read(range.$1, range.$2)).status,
          RecordedTimeStatus.unavailable,
        );
      }
      expect(
        (await h.time.readForOwner(
          const OwnerTimeRead(),
          expectedOwnerId: 'another-owner',
          stillCurrent: () => true,
        )).status,
        RecordedTimeStatus.unavailable,
      );
      expect(
        (await h.time.readForOwner(
          const OwnerTimeRead(),
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => false,
        )).status,
        RecordedTimeStatus.unavailable,
      );
    },
  );
}

class _TimeHarness {
  _TimeHarness(this.base) {
    time = LearningTimeUseCases(
      repository: DriftLearningTimeRepository(
        database: base.database,
        ownerWrites: base.ownerWrites,
        learning: base.learningRepository,
      ),
      ownerChanges: base.ownerChanges,
      monotonicMicros: () => micros,
      nowUtc: () => base.now,
      generateId: () => 'synthetic-calendar-time-${++sequence}',
    );
  }
  final ReviewCenterHarness base;
  late final LearningTimeUseCases time;
  int micros = 0;
  int sequence = 0;
  static Future<_TimeHarness> open() async {
    final result = _TimeHarness(await ReviewCenterHarness.open());
    if (result.time.preference == null) {
      await result.time.changes
          .firstWhere((_) => result.time.preference != null)
          .timeout(const Duration(seconds: 5));
    }
    await result.time.setEnabled(
      true,
      expectedOwnerId: configuredOwnerId,
      stillCurrent: () => true,
    );
    return result;
  }

  Future<void> record({required DateTime end, required int durationUs}) async {
    final lease = await time.attach(
      ReadingTimeSource(
        documentId: 'synthetic-calendar-${++sequence}',
        documentRevision: 1,
        snapshotSha256: 'a' * 64,
        targetPinsSha256: 'b' * 64,
        readingStage: 1,
        callerContext: LearningTimeCallerContext.ordinary,
      ),
      stillCurrent: () => true,
    );
    expect(lease, isNotNull);
    expect(await time.ready(lease!), isTrue);
    micros += durationUs;
    base.now = end;
    time.interacted(lease);
    time.detach(lease);
    await time.retryPending();
    expect(time.hasPending, isFalse);
  }

  Future<void> close() async {
    await time.dispose();
    await base.close();
  }
}
