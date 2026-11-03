import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/study_reminders/data/method_channel_study_reminder_platform.dart';
import 'package:vocab_learning_app/features/study_reminders/domain/study_reminder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.lexiquest.app/study_reminder');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AppDatabase database;
  late DriftOwnerWriteCoordinator ownerWrites;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    ownerWrites = DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => DateTime.utc(2026, 11, 3),
    );
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(permissions, null);
    await database.close();
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
      final platform = MethodChannelStudyReminderPlatform(
        ownerWrites: ownerWrites,
        isAndroid: false,
      );
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
      final platform = MethodChannelStudyReminderPlatform(
        ownerWrites: ownerWrites,
        isAndroid: true,
      );
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
      final platform = MethodChannelStudyReminderPlatform(
        ownerWrites: ownerWrites,
        isAndroid: true,
      );
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
      final platform = MethodChannelStudyReminderPlatform(
        ownerWrites: ownerWrites,
        isAndroid: true,
      );
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

  test('native request waits for an earlier writer to commit', () async {
    final writerHeld = Completer<void>();
    final releaseWriter = Completer<void>();
    var nativeCalls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      nativeCalls++;
      return {'scopeToken': 'synthetic-scope'};
    });
    final platform = MethodChannelStudyReminderPlatform(
      ownerWrites: ownerWrites,
      isAndroid: true,
    );
    final writer = database.transaction(() async {
      await database.customStatement(
        'UPDATE runtime_flags SET bool_value = bool_value',
      );
      writerHeld.complete();
      await releaseWriter.future;
    });
    await writerHeld.future;
    final binding = platform.bindScope(
      databasePath: '/synthetic/private.sqlite',
      ownerId: 'synthetic-owner',
    );
    try {
      await Future<void>.delayed(Duration.zero);
      expect(nativeCalls, 0);
    } finally {
      releaseWriter.complete();
      await writer;
    }
    expect(await binding, 'synthetic-scope');
    expect(nativeCalls, 1);
  });

  test(
    'a later writer waits for native IPC without a SQL transaction',
    () async {
      final nativeEntered = Completer<void>();
      final releaseNative = Completer<void>();
      bool? nativeHasTransaction;
      var writerCommitted = false;
      messenger.setMockMethodCallHandler(channel, (_) async {
        nativeHasTransaction = await ownerWrites.hasAmbientTransaction();
        nativeEntered.complete();
        await releaseNative.future;
        return {'scopeToken': 'synthetic-scope'};
      });
      final platform = MethodChannelStudyReminderPlatform(
        ownerWrites: ownerWrites,
        isAndroid: true,
      );
      final binding = platform.bindScope(
        databasePath: '/synthetic/private.sqlite',
        ownerId: 'synthetic-owner',
      );
      await nativeEntered.future;
      final writer = database
          .transaction(() async {
            await database.customStatement(
              'UPDATE runtime_flags SET bool_value = bool_value',
            );
          })
          .then((_) => writerCommitted = true);
      try {
        await Future<void>.delayed(Duration.zero);
        expect(nativeHasTransaction, isFalse);
        expect(writerCommitted, isFalse);
      } finally {
        releaseNative.complete();
      }
      expect(await binding, 'synthetic-scope');
      await writer;
      expect(writerCommitted, isTrue);
    },
  );

  test(
    'an inherited SQL transaction rejects a native request before IPC',
    () async {
      var nativeCalls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        nativeCalls++;
        return {'scopeToken': 'synthetic-scope'};
      });
      final platform = MethodChannelStudyReminderPlatform(
        ownerWrites: ownerWrites,
        isAndroid: true,
      );
      await database.transaction(() async {
        await expectLater(
          platform.bindScope(
            databasePath: '/synthetic/private.sqlite',
            ownerId: 'synthetic-owner',
          ),
          throwsA(
            isA<StudyReminderException>().having(
              (error) => error.code,
              'code',
              StudyReminderFailureCode.platformUnavailable,
            ),
          ),
        );
      });
      expect(nativeCalls, 0);
    },
  );
}
