import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/study_reminders/application/study_reminder_runtime.dart';
import 'package:vocab_learning_app/features/study_reminders/domain/study_reminder.dart';

import '../quest/support/quest_repository_harness.dart';

void main() {
  test(
    'load never enables a preference or requests notification permission',
    () async {
      final f = await _Fixture.open();
      try {
        final before = await f.h.storage.snapshot();
        final view = await f.runtime.load(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        expect(view.setting.enabled, isFalse);
        expect(view.setting.revision, 0);
        expect(f.platform.permissionRequests, 0);
        expect(f.platform.alarm, isNull);
        expect(await f.h.storage.snapshot(), before);
      } finally {
        await f.close();
      }
    },
  );

  test(
    'denied explicit enable writes no preference and schedules nothing',
    () async {
      final f = await _Fixture.open();
      try {
        f.platform.allowed = false;
        f.platform.permissionResult = false;
        final intent = await f.intent(true);
        final before = await f.h.storage.snapshot();
        await expectLater(
          f.runtime.apply(intent),
          throwsA(
            isA<StudyReminderException>().having(
              (e) => e.code,
              'code',
              StudyReminderFailureCode.permissionDenied,
            ),
          ),
        );
        expect(f.platform.permissionRequests, 1);
        expect(f.platform.alarm, isNull);
        expect(await f.h.storage.snapshot(), before);
      } finally {
        await f.close();
      }
    },
  );

  test(
    'lost schedule acknowledgement retries the same revision and one actual alarm identity',
    () async {
      final f = await _Fixture.open();
      try {
        final intent = await f.intent(true);
        f.platform.loseScheduleAck = true;
        await expectLater(
          f.runtime.apply(intent),
          throwsA(
            isA<StudyReminderException>().having(
              (e) => e.code,
              'code',
              StudyReminderFailureCode.requestUnconfirmed,
            ),
          ),
        );
        final committed = await f.h.storage.snapshot();
        final firstAlarm = f.platform.alarm;
        final retried = await f.runtime.apply(intent);
        expect(retried.setting.revision, 1);
        expect(retried.requestAck?.revision, 1);
        expect(f.platform.alarm, firstAlarm);
        expect(f.platform.scheduleRequests, [firstAlarm, firstAlarm]);
        expect(await f.h.storage.snapshot(), committed);
        expect(f.platform.permissionRequests, 0);
      } finally {
        await f.close();
      }
    },
  );

  test(
    'disable is durable despite a lost native cancellation acknowledgement',
    () async {
      final f = await _Fixture.open();
      try {
        await f.runtime.apply(await f.intent(true));
        final disable = await f.intent(false);
        f.platform.loseCancelAck = true;
        await expectLater(
          f.runtime.apply(disable),
          throwsA(isA<StudyReminderException>()),
        );
        final disabled = await f.runtime.repository.readForOwner(
          ownerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        expect(disabled.enabled, isFalse);
        expect(disabled.revision, 2);
        expect(f.platform.alarm, isNull);
        final before = await f.h.storage.snapshot();
        await f.runtime.apply(disable);
        expect(await f.h.storage.snapshot(), before);
        expect(f.platform.permissionRequests, 0);
      } finally {
        await f.close();
      }
    },
  );

  test(
    'actual owner ABA during permission cannot enable any owner reminder',
    () async {
      final f = await _Fixture.open();
      try {
        f.platform.allowed = false;
        f.platform.permissionGate = Completer<bool>();
        final intent = await f.intent(true);
        final before = await f.h.storage.snapshot();
        final rejected = expectLater(
          f.runtime.apply(intent),
          throwsA(
            isA<StudyReminderException>().having(
              (e) => e.code,
              'code',
              StudyReminderFailureCode.ownerChanged,
            ),
          ),
        );
        await f.platform.requestStarted.future;
        await f.switchOwner(configuredOtherOwnerId);
        await f.switchOwner(configuredOwnerId);
        f.platform.permissionGate!.complete(true);
        await rejected;
        expect(f.platform.alarm, isNull);
        expect(await f.h.storage.snapshot(), before);
      } finally {
        await f.close();
      }
    },
  );

  test(
    'owned permission dialog waits for foreground then completes explicit enable',
    () async {
      final f = await _Fixture.open();
      try {
        f.platform.allowed = false;
        f.platform.permissionGate = Completer<bool>();
        final intent = await f.intent(true);
        StudyReminderView? result;
        Object? error;
        final completion = f.runtime
            .apply(intent)
            .then<void>(
              (value) {
                result = value;
              },
              onError: (Object failure, StackTrace stack) {
                error = failure;
              },
            );
        await f.platform.requestStarted.future;
        f.runtime.setForeground(false);
        f.platform.permissionGate!.complete(true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          await f.h.database
              .select(f.h.database.studyReminderPreferences)
              .get(),
          isEmpty,
        );
        expect(f.platform.alarm, isNull);
        f.runtime.setForeground(true);
        await completion.timeout(const Duration(seconds: 2));
        expect(
          error,
          isNull,
          reason: 'The owned permission dialog must retain its explicit intent',
        );
        expect(result?.setting.enabled, isTrue);
        expect(result?.setting.revision, 1);
        expect(f.platform.alarm?.revision, 1);
      } finally {
        await f.close();
      }
    },
  );

  test(
    'disposal cancels a held permission intent without preference or alarm effects',
    () async {
      final f = await _Fixture.open();
      try {
        f.platform.allowed = false;
        f.platform.permissionGate = Completer<bool>();
        final before = await f.h.storage.snapshot();
        final rejected = expectLater(
          f.runtime.apply(await f.intent(true)),
          throwsA(
            isA<StudyReminderException>().having(
              (e) => e.code,
              'code',
              StudyReminderFailureCode.ownerChanged,
            ),
          ),
        );
        await f.platform.requestStarted.future;
        await f.runtime.dispose().timeout(const Duration(seconds: 2));
        await rejected;
        f.platform.permissionGate!.complete(true);
        await Future<void>.delayed(Duration.zero);
        expect(f.platform.alarm, isNull);
        expect(await f.h.storage.snapshot(), before);
      } finally {
        await f.close();
      }
    },
  );

  test(
    'fresh runtime reconciles actual saved desire and missing permission without prompting',
    () async {
      final f = await _Fixture.open();
      StudyReminderRuntime? restarted;
      try {
        await f.runtime.apply(await f.intent(true));
        final before = await f.h.storage.snapshot();
        await f.runtime.dispose();
        f.platform.alarm = null;
        f.platform.allowed = false;
        final progress = ProgressUseCases(
          owners: f.h.storage.owners,
          queries: DriftProgressQueries(f.h.database),
          nowUtc: () => f.h.now,
        );
        final next = StudyReminderRuntime(
          database: f.h.database,
          ownerWrites: f.h.storage.ownerWrites,
          ownerChanges: progress.watchActiveOwnerId(),
          platform: f.platform,
          nowUtc: () => f.h.now,
        );
        restarted = next;
        next.setForeground(true);
        await _until(() => next.currentOwnerId == configuredOwnerId);
        await next.reconcileForeground();
        expect(f.platform.alarm, isNull);
        expect(f.platform.permissionRequests, 0);
        expect(await f.h.storage.snapshot(), before);
        f.platform.allowed = true;
        await next.reconcileForeground();
        expect(f.platform.alarm?.revision, 1);
        expect(f.platform.permissionRequests, 0);
        expect(await f.h.storage.snapshot(), before);
      } finally {
        await restarted?.dispose();
        await f.close();
      }
    },
  );

  test(
    'normal runtime disposal retains an explicitly accepted reminder preference',
    () async {
      final f = await _Fixture.open();
      try {
        await f.runtime.apply(await f.intent(true));
        final desired = await f.h.storage.snapshot();
        final alarm = f.platform.alarm;
        await f.runtime.dispose();
        expect(await f.h.storage.snapshot(), desired);
        expect(f.platform.alarm, alarm);
      } finally {
        await f.close();
      }
    },
  );
}

final class _Fixture {
  _Fixture(this.h, this.directory, this.platform, this.runtime);
  final QuestHarness h;
  final Directory directory;
  final _Platform platform;
  final StudyReminderRuntime runtime;
  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-reminder-',
    );
    final h = await QuestHarness.open(
      file: File('${directory.path}/synthetic.sqlite'),
    );
    final platform = _Platform(() => h.now);
    final progress = ProgressUseCases(
      owners: h.storage.owners,
      queries: DriftProgressQueries(h.database),
      nowUtc: () => h.now,
    );
    final runtime = StudyReminderRuntime(
      database: h.database,
      ownerWrites: h.storage.ownerWrites,
      ownerChanges: progress.watchActiveOwnerId(),
      platform: platform,
      nowUtc: () => h.now,
    );
    runtime.setForeground(true);
    await _until(() => runtime.currentOwnerId == configuredOwnerId);
    await runtime.reconcileForeground();
    return _Fixture(h, directory, platform, runtime);
  }

  Future<StudyReminderChangeIntent> intent(bool enabled) =>
      runtime.prepareChange(
        expectedOwnerId: configuredOwnerId,
        choice: StudyReminderChoice(
          enabled: enabled,
          minuteOfDay: 19 * 60,
          timezoneId: 'Asia/Bangkok',
        ),
        stillCurrent: () => true,
      );
  Future<void> switchOwner(String owner) async {
    await (h.database.update(h.database.localOwners)
          ..where((row) => row.isActive.equals(true)))
        .write(const db.LocalOwnersCompanion(isActive: Value(false)));
    await (h.database.update(h.database.localOwners)
          ..where((row) => row.id.equals(owner)))
        .write(const db.LocalOwnersCompanion(isActive: Value(true)));
    await _until(() => runtime.currentOwnerId == owner);
  }

  Future<void> close() async {
    await runtime.dispose();
    await h.close();
    await directory.delete(recursive: true);
  }
}

final class _Platform implements StudyReminderPlatform {
  _Platform(this.now);
  final DateTime Function() now;
  bool allowed = true,
      permissionResult = true,
      loseScheduleAck = false,
      loseCancelAck = false;
  int permissionRequests = 0, _scopes = 0;
  String? scope;
  ({String token, int revision})? alarm;
  final scheduleRequests = <({String token, int revision})>[];
  Completer<bool>? permissionGate;
  final requestStarted = Completer<void>();
  @override
  Future<StudyReminderPlatformStatus> inspect() async =>
      StudyReminderPlatformStatus(
        supported: true,
        notificationsAllowed: allowed,
      );
  @override
  Future<StudyReminderPlatformStatus> requestPermission() async {
    permissionRequests++;
    if (!requestStarted.isCompleted) requestStarted.complete();
    allowed = permissionGate == null
        ? permissionResult
        : await permissionGate!.future;
    return inspect();
  }

  @override
  Future<String> bindScope({
    required String databasePath,
    required String ownerId,
  }) async {
    expect(databasePath, isNotEmpty);
    alarm = null;
    return scope = 'synthetic-reminder-scope-${++_scopes}';
  }

  @override
  Future<StudyReminderRequestAck> schedule({
    required String scopeToken,
    required int revision,
  }) async {
    expect(scopeToken, scope);
    alarm = (token: scopeToken, revision: revision);
    scheduleRequests.add(alarm!);
    if (loseScheduleAck) {
      loseScheduleAck = false;
      throw StateError('synthetic lost schedule ack');
    }
    return StudyReminderRequestAck(
      revision: revision,
      nextAtUtc: now().add(const Duration(days: 1)),
    );
  }

  @override
  Future<StudyReminderRequestAck> cancel({
    required String scopeToken,
    required int revision,
  }) async {
    expect(scopeToken, scope);
    alarm = null;
    if (loseCancelAck) {
      loseCancelAck = false;
      throw StateError('synthetic lost cancel ack');
    }
    return StudyReminderRequestAck(revision: revision);
  }

  @override
  Future<void> retire({String? scopeToken}) async {
    if (scopeToken == null || scopeToken == scope) {
      alarm = null;
      scope = null;
    }
  }
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Actual reminder owner did not become ready');
}
