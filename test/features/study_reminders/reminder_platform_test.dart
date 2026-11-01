import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/study_reminders/data/method_channel_study_reminder_platform.dart';
import 'package:vocab_learning_app/features/study_reminders/domain/study_reminder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.lexiquest.app/study_reminder');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(permissions, null);
  });

  test(
    'unsupported platform is explicit and never prompts or calls native scheduling',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return null;
      });
      messenger.setMockMethodCallHandler(permissions, (_) async {
        calls++;
        return null;
      });
      const platform = MethodChannelStudyReminderPlatform(isAndroid: false);
      expect((await platform.inspect()).supported, isFalse);
      expect(
        (await platform.requestPermission()).notificationsAllowed,
        isFalse,
      );
      await expectLater(
        platform.schedule(scopeToken: 'synthetic', revision: 1),
        throwsA(isA<StudyReminderException>()),
      );
      expect(calls, 0);
    },
  );

  test(
    'permission result is reread from actual native status rather than the plugin grant',
    () async {
      final steps = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        steps.add(call.method);
        return {'supported': true, 'notificationsAllowed': false};
      });
      messenger.setMockMethodCallHandler(permissions, (call) async {
        steps.add(call.method);
        final requested = call.arguments as List;
        return {for (final permission in requested) permission: 1};
      });
      const platform = MethodChannelStudyReminderPlatform(isAndroid: true);
      expect(
        (await platform.requestPermission()).notificationsAllowed,
        isFalse,
      );
      expect(steps, ['inspect', 'requestPermissions', 'inspect']);
    },
  );

  test(
    'native scope and accepted request carry exact committed revision',
    () async {
      final steps = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        steps.add(call.method);
        if (call.method == 'bindScope') {
          expect(call.arguments, {
            'databasePath': '/synthetic/private/actual.sqlite',
            'ownerId': 'synthetic-owner',
          });
          return {'scopeToken': 'synthetic-scope'};
        }
        expect(call.arguments, {
          'scopeToken': 'synthetic-scope',
          'revision': 7,
        });
        return {
          'accepted': true,
          'revision': 7,
          if (call.method == 'schedule') 'nextAtUtcMs': 1793534400000,
        };
      });
      const platform = MethodChannelStudyReminderPlatform(isAndroid: true);
      final token = await platform.bindScope(
        databasePath: '/synthetic/private/actual.sqlite',
        ownerId: 'synthetic-owner',
      );
      final ack = await platform.schedule(scopeToken: token, revision: 7);
      expect(ack.revision, 7);
      expect(
        ack.nextAtUtc,
        DateTime.fromMillisecondsSinceEpoch(1793534400000, isUtc: true),
      );
      expect(
        (await platform.cancel(scopeToken: token, revision: 7)).nextAtUtc,
        isNull,
      );
      expect(steps, ['bindScope', 'schedule', 'cancel']);
    },
  );

  test(
    'missing native implementation and wrong revision never become accepted requests',
    () async {
      const platform = MethodChannelStudyReminderPlatform(isAndroid: true);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException(),
      );
      expect((await platform.inspect()).supported, isFalse);
      await expectLater(
        platform.bindScope(
          databasePath: '/synthetic/private.sqlite',
          ownerId: 'synthetic',
        ),
        throwsA(isA<StudyReminderException>()),
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'accepted': true, 'revision': 2, 'nextAtUtcMs': 1},
      );
      await expectLater(
        platform.schedule(scopeToken: 'synthetic', revision: 1),
        throwsA(
          isA<StudyReminderException>().having(
            (e) => e.code,
            'code',
            StudyReminderFailureCode.requestUnconfirmed,
          ),
        ),
      );
    },
  );
}
