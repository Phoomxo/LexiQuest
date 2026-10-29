import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';

import '../../support/study_runtime_harness.dart';

String switchAttempt(int n) =>
    '00000000-0000-4000-8000-${(200 + n).toString().padLeft(12, '0')}';
Matcher get _denied => throwsA(isA<ResearchCaptureDenied>());

Future<StudyView> _prepare(
  StudyRuntimeFixture f,
  StudyView view,
  int n, {
  bool Function()? current,
}) async =>
    await (f.runtime as dynamic).preparePresentationChange(
          f.ownerId,
          view.opportunity!.id,
          attemptId: switchAttempt(n),
          expectedRevision: view.opportunity!.localRevision,
          target: oppositePresentation(view.opportunity!.currentPresentation),
          stillCurrent: current ?? () => true,
        )
        as StudyView;
void _mark(StudyRuntimeFixture f, StudyView view, int n) =>
    (f.runtime as dynamic).markPresentationChangeMayRender(
      f.ownerId,
      view.opportunity!.id,
      attemptId: switchAttempt(n),
    );
Future<StudyView> _capture(
  StudyRuntimeFixture f,
  StudyView view,
  int n, {
  bool Function()? visible,
}) async =>
    await (f.runtime as dynamic).recordPresentationChanged(
          f.ownerId,
          view.opportunity!.id,
          attemptId: switchAttempt(n),
          stillVisible: visible ?? () => true,
        )
        as StudyView;

void main() {
  late StudyRuntimeFixture f;
  tearDown(() async => f.database.close());

  test(
    'a new target frame cannot refresh its expired original display lease',
    () async {
      f = await StudyRuntimeFixture.open(longLived: true);
      final prepared = await _prepare(f, await f.ready(), 1);
      _mark(f, prepared, 1);
      final before = await f.researchRows();
      f.participation.clock.now = prepared.promptExpiresAtUtc!;
      await expectLater(_capture(f, prepared, 1), _denied);
      expect(await f.researchRows(), before);
    },
  );

  test(
    'prepare stores only pending intent and original handle captures one actual target frame',
    () async {
      f = await StudyRuntimeFixture.open(longLived: true);
      final base = await f.ready();
      final before = await f.rows('events_v2');
      final prepared = await _prepare(f, base, 1);
      expect(
        prepared.opportunity!.currentPresentation,
        TodayExperiencePresentation.standard,
      );
      expect(
        prepared.opportunity!.pendingPresentationChange!.to,
        TodayExperiencePresentation.adventure,
      );
      expect(prepared.evaluatedAtUtc, base.evaluatedAtUtc);
      expect(prepared.promptExpiresAtUtc, base.promptExpiresAtUtc);
      expect(await f.rows('events_v2'), before);
      expect((await f.runtime.load(f.ownerId)).phase, StudyPhase.unavailable);
      _mark(f, prepared, 1);
      final committed = await _capture(f, prepared, 1);
      expect(
        committed.opportunity!.currentPresentation,
        TodayExperiencePresentation.adventure,
      );
      expect(committed.opportunity!.pendingPresentationChange, isNull);
      expect(
        committed.opportunity!.assignedTreatment,
        TodayExperiencePresentation.standard,
      );
      expect(
        (await f.rows('events_v2')).where(
          (r) => r['event_type'] == measurementPresentationChangedEventType,
        ),
        hasLength(1),
      );
      expect(await f.rows('learning_sessions'), isEmpty);
      expect(await f.rows('outbox_operations'), isEmpty);
    },
  );

  test(
    'unmarked capture and lifecycle invalidation cannot fabricate a Changed fact',
    () async {
      f = await StudyRuntimeFixture.open(longLived: true);
      final prepared = await _prepare(f, await f.ready(), 1);
      final before = await f.researchRows();
      await expectLater(_capture(f, prepared, 1), _denied);
      expect(await f.researchRows(), before);
      (f.runtime as dynamic).invalidatePresentationChange(
        f.ownerId,
        prepared.opportunity!.id,
        attemptId: switchAttempt(1),
      );
      expect(() => _mark(f, prepared, 1), _denied);
      expect((await f.runtime.load(f.ownerId)).phase, StudyPhase.unavailable);
    },
  );

  test(
    'exact public ACK rejects a foreign attempt owner opportunity and restarted process',
    () async {
      f = await StudyRuntimeFixture.open(longLived: true);
      final prepared = await _prepare(f, await f.ready(), 1);
      _mark(f, prepared, 1);
      final committed = await _capture(f, prepared, 1);
      final before = await f.researchRows();
      expect(
        (await _capture(f, prepared, 1)).opportunity!.localRevision,
        committed.opportunity!.localRevision,
      );
      await expectLater(_capture(f, prepared, 2), _denied);
      for (final binding in [
        ('owner-b', prepared.opportunity!.id),
        (f.ownerId, 'foreign-opportunity'),
      ]) {
        await expectLater(
          (f.runtime as dynamic).recordPresentationChanged(
                binding.$1,
                binding.$2,
                attemptId: switchAttempt(1),
                stillVisible: () => true,
              )
              as Future,
          binding.$1 == f.ownerId
              ? _denied
              : throwsA(
                  isA<AccountDeletionException>().having(
                    (error) => error.code,
                    'code',
                    AccountDeletionFailureCode.ownerChanged,
                  ),
                ),
        );
      }
      expect(await f.researchRows(), before);
      f.restartRuntime();
      await expectLater(_capture(f, prepared, 1), _denied);
      expect(await f.researchRows(), before);
    },
  );

  test(
    'suppression eleven and twelve retain exact process ACK and one canonical index',
    () async {
      f = await StudyRuntimeFixture.open(longLived: true);
      var view = await f.ready();
      final index = await f.runtime.startIndex(
        f.ownerId,
        view.opportunity!.id,
        stillVisible: () => true,
      );
      view = await f.runtime.load(f.ownerId);
      final started = (await f.rows('events_v2')).singleWhere(
        (r) => r['event_type'] == measurementMissionStartedEventType,
      );
      for (var n = 1; n <= 12; n++) {
        final prepared = await _prepare(f, view, n);
        _mark(f, prepared, n);
        view = await _capture(f, prepared, n);
        final rows = await f.researchRows();
        expect(
          (await _capture(f, prepared, n)).opportunity!.localRevision,
          view.opportunity!.localRevision,
        );
        await expectLater(_capture(f, prepared, n + 100), _denied);
        expect(await f.researchRows(), rows);
        expect(view.index!.sessionId, index.sessionId);
      }
      expect(view.opportunity!.lastSwitchOrdinal, 10);
      expect(view.opportunity!.suppressedSwitchCount, 2);
      expect(
        view.opportunity!.currentPresentation,
        TodayExperiencePresentation.standard,
      );
      expect(
        view.opportunity!.startedEffectivePresentation,
        TodayExperiencePresentation.standard,
      );
      expect(
        (await f.rows('events_v2')).where(
          (r) => r['event_type'] == measurementPresentationChangedEventType,
        ),
        hasLength(10),
      );
      expect(
        (await f.rows('events_v2')).singleWhere(
          (r) => r['event_type'] == measurementMissionStartedEventType,
        ),
        started,
      );
      expect(await f.rows('learning_sessions'), hasLength(1));
    },
  );

  test(
    'a prepare response cannot grant render permission before its outer transaction commits',
    () async {
      final queries = _SwitchQueries();
      f = await StudyRuntimeFixture.open(
        database: AppDatabase(NativeDatabase.memory().interceptWith(queries)),
        longLived: true,
      );
      final base = await f.ready();
      final entered = Completer<void>();
      final release = Completer<void>();
      queries.holdPrepare = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      var acknowledged = false;
      final pending = _prepare(f, base, 1).then((value) {
        acknowledged = true;
        return value;
      });
      pending.ignore();
      try {
        await entered.future.timeout(const Duration(seconds: 3));
        expect(acknowledged, isFalse);
        expect(() => _mark(f, base, 1), _denied);
        release.complete();
        final prepared = await pending;
        expect(acknowledged, isTrue);
        _mark(f, prepared, 1);
      } finally {
        if (!release.isCompleted) release.complete();
        await pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      }
    },
  );

  test(
    'ambient transaction cannot prepare or create a recoverable process handle',
    () async {
      f = await StudyRuntimeFixture.open(longLived: true);
      final base = await f.ready();
      final before = await f.researchRows();
      await f.database.transaction(
        () async => expectLater(_prepare(f, base, 1), _denied),
      );
      expect(() => _mark(f, base, 1), _denied);
      expect(await f.researchRows(), before);
    },
  );

  test(
    'capture failure leaves pending unavailable without blocking ordinary learning',
    () async {
      f = await StudyRuntimeFixture.open(longLived: true);
      final prepared = await _prepare(f, await f.ready(), 1);
      _mark(f, prepared, 1);
      f.participation.states.revoked = true;
      await expectLater(_capture(f, prepared, 1), _denied);
      f.participation.states.revoked = false;
      expect((await f.runtime.load(f.ownerId)).phase, StudyPhase.unavailable);
      await expectLater(_capture(f, prepared, 1), _denied);
      final ordinary = await f.learning.startQuiz(limit: 1);
      expect(ordinary.questions, isNotEmpty);
      expect(
        (await f.rows('events_v2')).where(
          (r) => r['event_type'] == measurementPresentationChangedEventType,
        ),
        isEmpty,
      );
      expect(await f.rows('learning_sessions'), hasLength(1));
      expect(
        jsonDecode(
          (await f.rows(
                'measurement_opportunities',
              )).single['pending_presentation_change_json']!
              as String,
        )['attemptId'],
        switchAttempt(1),
      );
    },
  );

  test(
    'restart cannot resume an uncommitted target from a stored pending receipt',
    () async {
      f = await StudyRuntimeFixture.open(longLived: true);
      final prepared = await _prepare(f, await f.ready(), 1);
      final before = await f.researchRows();
      f.restartRuntime();
      await expectLater(_prepare(f, prepared, 1), _denied);
      expect(() => _mark(f, prepared, 1), _denied);
      await expectLater(_capture(f, prepared, 1), _denied);
      expect((await f.runtime.load(f.ownerId)).phase, StudyPhase.unavailable);
      expect(await f.researchRows(), before);
    },
  );
}

final class _SwitchQueries extends drift.QueryInterceptor {
  Future<void> Function()? holdPrepare;
  @override
  Future<void> runCustom(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    if (statement.contains('pending_presentation_change_json') &&
        args.any((value) => value is String && value.contains('"attemptId"'))) {
      await holdPrepare?.call();
    }
  }
}
