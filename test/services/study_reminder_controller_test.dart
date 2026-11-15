import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/study_reminders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.lexiquest.app/study_reminder');
  const path = '/synthetic/files/lexiquest.sqlite';
  final calls = <MethodCall>[];
  var allowed = false;
  var reconcileFailed = false;
  String? preset;

  setUp(() {
    calls.clear();
    allowed = false;
    reconcileFailed = false;
    preset = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'enable':
              preset = (call.arguments as Map)['preset'] as String;
            case 'disable':
              preset = null;
            case 'reconcile':
              if (reconcileFailed) throw PlatformException(code: 'UNAVAILABLE');
              return null;
          }
          return {'allowed': allowed, 'preset': preset};
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'explicit opt-in denies before scheduling and supports disable',
    () async {
      var owner = 'synthetic-a';
      var permissionRequests = 0;
      final reminders = StudyReminders(
        databasePath: path,
        activeOwner: () async => owner,
        requestPermission: () async {
          allowed = ++permissionRequests == 2;
        },
      );
      final denied = await reminders.enable(
        ownerId: owner,
        preset: StudyReminderPreset.weekdaysEvening,
        isCurrent: () => true,
      );
      expect(denied.allowed, isFalse);
      expect(denied.preset, isNull);
      expect(calls.map((call) => call.method), isNot(contains('enable')));
      final enabled = await reminders.enable(
        ownerId: owner,
        preset: StudyReminderPreset.weekdaysEvening,
        isCurrent: () => true,
      );
      expect(enabled.preset, StudyReminderPreset.weekdaysEvening);
      expect(calls.last.arguments, {
        'databasePath': path,
        'ownerId': owner,
        'preset': 'weekdaysEvening',
      });
      expect((await reminders.disable(ownerId: owner)).preset, isNull);
      expect(calls.last.method, 'disable');
    },
  );

  test('a stale permission response cannot authorize an alarm', () async {
    var owner = 'synthetic-a';
    final reminders = StudyReminders(
      databasePath: path,
      activeOwner: () async => owner,
      requestPermission: () async {
        allowed = true;
        owner = 'synthetic-b';
      },
    );
    await expectLater(
      reminders.enable(
        ownerId: 'synthetic-a',
        preset: StudyReminderPreset.weekendMorning,
        isCurrent: () => true,
      ),
      throwsStateError,
    );
    expect(calls.map((call) => call.method), ['status']);
  });

  test('status cannot confirm an enrollment while scheduling fails', () async {
    allowed = true;
    preset = 'weekendMorning';
    reconcileFailed = true;
    final reminders = StudyReminders(
      databasePath: path,
      activeOwner: () async => 'synthetic-a',
      requestPermission: () async => fail('Inspection must not ask permission'),
    );
    await expectLater(
      reminders.status(ownerId: 'synthetic-a'),
      throwsA(isA<PlatformException>()),
    );
    expect(calls.map((call) => call.method), ['reconcile']);
    reconcileFailed = false;
    final recovered = await reminders.status(ownerId: 'synthetic-a');
    expect(recovered, (
      allowed: true,
      preset: StudyReminderPreset.weekendMorning,
    ));
  });

  test(
    'an invalidated owner scope cannot reuse a late permission grant',
    () async {
      final prompting = Completer<void>();
      final grant = Completer<void>();
      final reminders = StudyReminders(
        databasePath: path,
        activeOwner: () async => 'synthetic-a',
        requestPermission: () async {
          prompting.complete();
          await grant.future;
          allowed = true;
        },
      );
      final request = reminders.enable(
        ownerId: 'synthetic-a',
        preset: StudyReminderPreset.weekdaysEvening,
        isCurrent: () => true,
      );
      final rejected = expectLater(request, throwsStateError);
      await prompting.future;
      reminders.invalidateScope();
      grant.complete();
      await rejected;
      expect(calls.map((call) => call.method), ['status']);
    },
  );
}
