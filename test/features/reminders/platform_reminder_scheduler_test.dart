import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/features/reminders/data/platform_reminder_scheduler.dart';
import 'package:vocab_learning_app/features/reminders/domain/reminder_scheduler.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  test('Android schedules with inexact allow-while-idle semantics', () async {
    final native = _NativeGateway();
    final scheduler = PlatformReminderScheduler(
      native,
      targetPlatform: ReminderTargetPlatform.android,
    );
    final request = _request();

    await scheduler.initialize();
    await scheduler.schedule(request);
    await scheduler.schedule(request);

    expect(native.initializeCalls, 1);
    expect(native.schedules, hasLength(2));
    expect(
      native.schedules.map((entry) => entry.precision),
      everyElement(ReminderSchedulePrecision.inexactAllowWhileIdle),
    );
    expect(native.schedules.map((entry) => entry.platformId).toSet(), {991});
  });

  test('iOS enforces the pending notification cap of 64', () async {
    final native = _NativeGateway();
    for (var index = 0; index < maxPendingIosNotifications; index += 1) {
      native.pending[index] = ReminderPlatformEntry(
        platformId: index,
        ownerId: 'owner-a',
        reminderId: 'reminder:$index',
      );
    }
    final scheduler = PlatformReminderScheduler(
      native,
      targetPlatform: ReminderTargetPlatform.ios,
    );

    await expectLater(
      scheduler.schedule(_request()),
      throwsA(isA<ReminderScheduleCapacityExceeded>()),
    );
    native.pending[991] = const ReminderPlatformEntry(
      platformId: 991,
      ownerId: 'owner-a',
      reminderId: 'reminder:due-review',
    );
    await scheduler.schedule(_request());
    expect(native.schedules, hasLength(1));
  });

  test('permission queries never request permission implicitly', () async {
    final native = _NativeGateway()
      ..permission = ReminderPermissionState.unknown
      ..requestResult = ReminderPermissionState.denied;
    final scheduler = PlatformReminderScheduler(
      native,
      targetPlatform: ReminderTargetPlatform.android,
    );

    expect(await scheduler.permissionState(), ReminderPermissionState.unknown);
    expect(native.requestCalls, 0);
    expect(await scheduler.requestPermission(), ReminderPermissionState.denied);
    expect(native.requestCalls, 1);
  });

  test(
    'failed initialization can recover on the next explicit attempt',
    () async {
      final native = _NativeGateway()..initializeFailuresRemaining = 1;
      final scheduler = PlatformReminderScheduler(
        native,
        targetPlatform: ReminderTargetPlatform.android,
      );

      await expectLater(scheduler.initialize(), throwsStateError);
      await scheduler.initialize();

      expect(native.initializeCalls, 2);
    },
  );

  test('payload identities round-trip and malformed entries fail closed', () {
    const entry = ReminderPlatformEntry(
      platformId: 42,
      ownerId: 'owner-a',
      reminderId: 'reminder:goal:ielts',
    );
    final payload = encodeReminderPlatformPayload(entry);

    expect(decodeReminderPlatformPayload(42, payload), entry);
    expect(decodeReminderPlatformPayload(42, 'unrelated'), isNull);
    expect(decodeReminderPlatformPayload(42, 'lexiquest-reminder:'), isNull);
  });

  test('platform notification ids are stable and owner-isolated', () {
    expect(
      studyReminderPlatformId('owner-a', 'reminder:1'),
      studyReminderPlatformId('owner-a', 'reminder:1'),
    );
    expect(
      studyReminderPlatformId('owner-a', 'reminder:1'),
      isNot(studyReminderPlatformId('owner-b', 'reminder:1')),
    );
    expect(
      studyReminderPlatformId('owner-a', 'reminder:1'),
      inInclusiveRange(1, 0x7fffffff),
    );
  });
}

ReminderScheduleRequest _request() => ReminderScheduleRequest(
  platformId: 991,
  ownerId: 'owner-a',
  reminderId: 'reminder:due-review',
  scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
  timezoneId: 'Asia/Bangkok',
  title: 'A gentle study reminder',
  body: 'A few reviews are ready whenever you are.',
);

final class _NativeGateway implements ReminderNativeGateway {
  int initializeCalls = 0;
  int initializeFailuresRemaining = 0;
  int requestCalls = 0;
  ReminderPermissionState permission = ReminderPermissionState.granted;
  ReminderPermissionState requestResult = ReminderPermissionState.granted;
  final Map<int, ReminderPlatformEntry> pending = {};
  final List<NativeReminderSchedule> schedules = [];

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    if (initializeFailuresRemaining > 0) {
      initializeFailuresRemaining -= 1;
      throw StateError('injected initialization failure');
    }
  }

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<ReminderPermissionState> permissionState() async => permission;

  @override
  Future<ReminderPermissionState> requestPermission() async {
    requestCalls += 1;
    permission = requestResult;
    return requestResult;
  }

  @override
  Future<List<ReminderPlatformEntry>> pendingEntries() async =>
      pending.values.toList(growable: false);

  @override
  Future<void> schedule(NativeReminderSchedule request) async {
    schedules.add(request);
    pending[request.platformId] = ReminderPlatformEntry(
      platformId: request.platformId,
      ownerId: request.ownerId,
      reminderId: request.reminderId,
    );
  }

  @override
  Future<void> cancel(int platformId) async {
    pending.remove(platformId);
  }
}
