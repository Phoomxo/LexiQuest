import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/features/reminders/data/platform_reminder_scheduler.dart';
import 'package:vocab_learning_app/features/reminders/domain/reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(timezone_data.initializeTimeZones);
  setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);

  group('current OS notification permission through the plugin channel', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');

    // The platform interface has a late singleton with no default test value.
    // Establish this file's baseline, then restore it after every case.

    for (final scenario in [
      (
        name: 'Android grant then OS revoke',
        target: TargetPlatform.android,
        priorGrant: true,
        response: false,
        expected: ReminderPermissionState.denied,
      ),
      (
        name: 'Android grant then unavailable OS status',
        target: TargetPlatform.android,
        priorGrant: true,
        response: null,
        expected: ReminderPermissionState.unknown,
      ),
      (
        name: 'Android fresh OS denial',
        target: TargetPlatform.android,
        priorGrant: false,
        response: false,
        expected: ReminderPermissionState.denied,
      ),
      (
        name: 'iOS grant then OS revoke',
        target: TargetPlatform.iOS,
        priorGrant: true,
        response: <String, bool>{
          'isEnabled': false,
          'isAlertEnabled': false,
          'isProvisionalEnabled': false,
        },
        expected: ReminderPermissionState.denied,
      ),
      (
        name: 'iOS grant then unavailable OS status',
        target: TargetPlatform.iOS,
        priorGrant: true,
        response: null,
        expected: ReminderPermissionState.unknown,
      ),
      (
        name: 'iOS provisional status permits notifications',
        target: TargetPlatform.iOS,
        priorGrant: true,
        response: <String, bool>{
          'isEnabled': true,
          'isAlertEnabled': false,
          'isProvisionalEnabled': true,
        },
        expected: ReminderPermissionState.granted,
      ),
      (
        name: 'iOS fresh OS denial',
        target: TargetPlatform.iOS,
        priorGrant: false,
        response: <String, bool>{
          'isEnabled': false,
          'isAlertEnabled': false,
          'isProvisionalEnabled': false,
        },
        expected: ReminderPermissionState.denied,
      ),
    ]) {
      test(scenario.name, () async {
        final originalTarget = debugDefaultTargetPlatformOverride;
        final originalPlugin = FlutterLocalNotificationsPlatform.instance;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        addTearDown(() {
          messenger.setMockMethodCallHandler(channel, null);
          debugDefaultTargetPlatformOverride = originalTarget;
          FlutterLocalNotificationsPlatform.instance = originalPlugin;
        });
        final android = scenario.target == TargetPlatform.android;
        debugDefaultTargetPlatformOverride = scenario.target;
        if (android) {
          AndroidFlutterLocalNotificationsPlugin.registerWith();
        } else {
          IOSFlutterLocalNotificationsPlugin.registerWith();
        }
        final requestMethod = android
            ? 'requestNotificationsPermission'
            : 'requestPermissions';
        final queryMethod = android
            ? 'areNotificationsEnabled'
            : 'checkPermissions';
        final calls = <String>[];
        Object? currentStatus = android
            ? true
            : <String, bool>{
                'isEnabled': true,
                'isAlertEnabled': true,
                'isProvisionalEnabled': false,
              };
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == requestMethod) return true;
          if (call.method == queryMethod) return currentStatus;
          throw StateError('Unexpected notification method ${call.method}');
        });
        final scheduler = PlatformReminderScheduler(
          FlutterLocalNotificationsGateway(
            targetPlatform: android
                ? ReminderTargetPlatform.android
                : ReminderTargetPlatform.ios,
          ),
          targetPlatform: android
              ? ReminderTargetPlatform.android
              : ReminderTargetPlatform.ios,
        );
        if (scenario.priorGrant) {
          expect(
            await scheduler.requestPermission(),
            ReminderPermissionState.granted,
          );
          expect(
            await scheduler.permissionState(),
            ReminderPermissionState.granted,
          );
        }

        currentStatus = scenario.response;
        final current = await scheduler.permissionState();
        final repeated = await scheduler.permissionState();

        expect(
          calls,
          [
            if (scenario.priorGrant) requestMethod,
            if (scenario.priorGrant) queryMethod,
            queryMethod,
            queryMethod,
          ],
          reason: 'Reading OS permission must never prompt or use cached truth',
        );
        expect(current, scenario.expected);
        expect(repeated, scenario.expected);
      });
    }
  });

  test(
    'native enumeration retains actual reminder ID and ignores foreign or malformed payloads',
    () async {
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final originalTarget = debugDefaultTargetPlatformOverride;
      final originalPlugin = FlutterLocalNotificationsPlatform.instance;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = originalTarget;
        FlutterLocalNotificationsPlatform.instance = originalPlugin;
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const actual = ReminderPlatformEntry(
        platformId: 717171,
        ownerId: 'retired-owner',
        reminderId: 'deleted-reminder',
      );
      expect(
        actual.platformId,
        isNot(studyReminderPlatformId(actual.ownerId, actual.reminderId)),
      );
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        expect(call.method, 'pendingNotificationRequests');
        return [
          {
            'id': actual.platformId,
            'title': 'Synthetic',
            'body': 'Synthetic',
            'payload': encodeReminderPlatformPayload(actual),
          },
          {'id': 11, 'payload': 'foreign-notification'},
          {'id': 12, 'payload': 'lexiquest-reminder:{'},
          {
            'id': 13,
            'payload': 'lexiquest-reminder:{"ownerId":9,"reminderId":"x"}',
          },
          {'id': 14, 'payload': null},
        ];
      });
      final scheduler = PlatformReminderScheduler(
        FlutterLocalNotificationsGateway(
          targetPlatform: ReminderTargetPlatform.android,
        ),
        targetPlatform: ReminderTargetPlatform.android,
      );
      expect(await scheduler.pendingEntries(), [actual]);
      expect(calls, ['pendingNotificationRequests']);
    },
  );

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
