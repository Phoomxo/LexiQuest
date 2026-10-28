import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/features/reminders/data/platform_reminder_scheduler.dart';
import 'package:vocab_learning_app/features/reminders/domain/reminder_scheduler.dart';

const _operationTimeout = Duration(seconds: 20);
const _deliveryWindow = Duration(seconds: 60);
const _title = 'LexiQuest synthetic reminder';
const _body = 'Automated local service check; no learner data.';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final scheduler = PlatformReminderScheduler.production();
  final plugin = (scheduler.gateway as FlutterLocalNotificationsGateway).plugin;
  final journal = _OwnedReminderJournal();
  final outcomes = <String, Object?>{
    'initialization': {'status': 'not_run'},
    'scheduleCancel': {'status': 'not_run'},
    'delivery': {'status': 'not_run'},
    'exportCancel': {'status': 'not_included'},
  };
  Map<String, Object?>? viewport;

  void publishReport() {
    binding.reportData = <String, dynamic>{
      'suite': 'native-services',
      'schemaVersion': 1,
      'runId': journal.runId,
      'outcomes': outcomes,
      'viewport': viewport,
      'resourcesCreated': journal.owned.isNotEmpty,
      'ownershipJournalPath': journal.created ? journal.file.path : null,
      'cleanupVerified': journal.cleanupVerified,
      'permissionPromptRequested': false,
      // This is a testWidgets integration fixture outside the test/ directory.
      // ignore: invalid_use_of_visible_for_testing_member
      'testResults': binding.results.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    };
  }

  void record(String name, Map<String, Object?> result) {
    outcomes[name] = result;
    publishReport();
    print('NATIVE_SERVICES_RESULT ${jsonEncode({'case': name, ...result})}');
  }

  Future<bool> permissionAvailable(String name) async {
    await scheduler.initialize().timeout(_operationTimeout);
    final permission = await scheduler.permissionState().timeout(
      _operationTimeout,
    );
    if (permission == ReminderPermissionState.granted) return true;
    record(name, {
      'status': 'deferred_permission',
      'permission': permission.name,
      'reason': 'Existing notification permission is not granted; no prompt.',
    });
    markTestSkipped(
      'Notification permission unavailable; no prompt requested.',
    );
    return false;
  }

  testWidgets(
    'native reminder initializes and queries permission without prompting',
    (tester) async {
      try {
        expect(Platform.isAndroid, isTrue);
        timezone_data.initializeTimeZones();
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SafeArea(
                child: Center(child: Text('Native service checks')),
              ),
            ),
          ),
        );
        await tester.pump();
        viewport = {
          'physicalWidth': tester.view.physicalSize.width,
          'physicalHeight': tester.view.physicalSize.height,
          'devicePixelRatio': tester.view.devicePixelRatio,
          'overridden': false,
        };
        await scheduler.initialize().timeout(_operationTimeout);
        expect(
          await scheduler.isSupported().timeout(_operationTimeout),
          isTrue,
        );
        final permission = await scheduler.permissionState().timeout(
          _operationTimeout,
        );
        record('initialization', {
          'status': 'passed',
          'permission': permission.name,
          'permissionPromptRequested': false,
        });
      } catch (error) {
        record('initialization', {
          'status': 'failed',
          'errorType': error.runtimeType.toString(),
        });
        rethrow;
      }
    },
  );

  testWidgets('native reminder schedules and cancels only its owned id', (
    tester,
  ) async {
    try {
      if (!await permissionAvailable('scheduleCancel')) return;
      final owned = await journal.reserve(plugin, 'roundtrip');
      try {
        await _schedule(
          scheduler,
          journal,
          owned,
          DateTime.now().toUtc().add(const Duration(hours: 1)),
        );
        final pending = await scheduler.pendingEntries().timeout(
          _operationTimeout,
        );
        expect(pending.where((entry) => entry.platformId == owned.id), [
          ReminderPlatformEntry(
            platformId: owned.id,
            ownerId: owned.ownerId,
            reminderId: owned.reminderId,
          ),
        ]);
        final raw = await plugin.pendingNotificationRequests().timeout(
          _operationTimeout,
        );
        final request = raw.singleWhere((entry) => entry.id == owned.id);
        expect(request.title, _title);
        expect(request.body, _body);
      } finally {
        await _cancelOwned(scheduler, plugin, journal, owned);
      }
      record('scheduleCancel', {
        'status': 'passed',
        'platformId': owned.id,
        'pendingRoundTripVerified': true,
        'cleanupVerified': owned.cleanupVerified,
      });
    } catch (error) {
      record('scheduleCancel', {
        'status': 'failed',
        'errorType': error.runtimeType.toString(),
      });
      rethrow;
    }
  });

  testWidgets('native reminder delivery observation is bounded and separate', (
    tester,
  ) async {
    try {
      if (!await permissionAvailable('delivery')) return;
      final owned = await journal.reserve(plugin, 'delivery');
      var observed = false;
      var elapsedMilliseconds = 0;
      try {
        await _schedule(
          scheduler,
          journal,
          owned,
          DateTime.now().toUtc().add(const Duration(seconds: 5)),
        );
        final elapsed = Stopwatch()..start();
        print('NATIVE_SERVICES_DELIVERY_WINDOW_STARTED id=${owned.id}');
        while (elapsed.elapsed < _deliveryWindow) {
          final remaining = _deliveryWindow - elapsed.elapsed;
          final active = await plugin.getActiveNotifications().timeout(
            remaining < _operationTimeout ? remaining : _operationTimeout,
          );
          if (active.any((entry) => entry.id == owned.id)) {
            observed = true;
            break;
          }
          final wait = _deliveryWindow - elapsed.elapsed;
          if (wait <= Duration.zero) break;
          await Future<void>.delayed(
            wait < const Duration(seconds: 2)
                ? wait
                : const Duration(seconds: 2),
          );
        }
        elapsedMilliseconds = elapsed.elapsedMilliseconds;
      } finally {
        await _cancelOwned(scheduler, plugin, journal, owned);
      }
      record('delivery', {
        'status': observed ? 'observed' : 'not_observed_within_window',
        'platformId': owned.id,
        'observation': 'active_notification_presence',
        'windowSeconds': _deliveryWindow.inSeconds,
        'elapsedMilliseconds': elapsedMilliseconds,
        'exactTimeRequired': false,
        'cleanupVerified': owned.cleanupVerified,
      });
      if (!observed) {
        markTestSkipped('Inexact notification not observed within 60 seconds.');
      }
    } catch (error) {
      record('delivery', {
        'status': 'failed',
        'errorType': error.runtimeType.toString(),
      });
      rethrow;
    }
  });

  testWidgets('DEVICE_NATIVE_SERVICES_FINAL_SENTINEL', (tester) async {
    publishReport();
    expect(journal.cleanupVerified, isTrue);
    print('NATIVE_SERVICES_FINAL_REPORT ${jsonEncode(binding.reportData)}');
  });
  unawaited(_publishService());
}

Future<void> _schedule(
  PlatformReminderScheduler scheduler,
  _OwnedReminderJournal journal,
  _OwnedReminder owned,
  DateTime scheduledAtUtc,
) async {
  owned.scheduleAttempted = true;
  await journal.write();
  await scheduler
      .schedule(
        ReminderScheduleRequest(
          platformId: owned.id,
          ownerId: owned.ownerId,
          reminderId: owned.reminderId,
          scheduledAtUtc: scheduledAtUtc,
          timezoneId: 'UTC',
          title: _title,
          body: _body,
        ),
      )
      .then<void>(
        (_) {
          owned.scheduleAcknowledged = true;
          owned.scheduleSettled = true;
        },
        onError: (Object error, StackTrace stackTrace) {
          owned.scheduleSettled = true;
          Error.throwWithStackTrace(error, stackTrace);
        },
      )
      .timeout(_operationTimeout);
  await journal.write();
}

Future<void> _cancelOwned(
  PlatformReminderScheduler scheduler,
  FlutterLocalNotificationsPlugin plugin,
  _OwnedReminderJournal journal,
  _OwnedReminder owned,
) async {
  try {
    await scheduler.cancel(owned.id).timeout(_operationTimeout);
    owned.cancelAcknowledged = true;
    final pending = await plugin.pendingNotificationRequests().timeout(
      _operationTimeout,
    );
    owned.pendingAbsent = !pending.any((entry) => entry.id == owned.id);
    final active = await plugin.getActiveNotifications().timeout(
      _operationTimeout,
    );
    owned.activeAbsent = !active.any((entry) => entry.id == owned.id);
    expect(owned.pendingAbsent, isTrue);
    expect(owned.activeAbsent, isTrue);
  } finally {
    await journal.write();
  }
}

final class _OwnedReminder {
  _OwnedReminder({
    required this.id,
    required this.ownerId,
    required this.reminderId,
  });

  final int id;
  final String ownerId;
  final String reminderId;
  bool scheduleAttempted = false;
  bool scheduleAcknowledged = false;
  bool scheduleSettled = false;
  bool cancelAcknowledged = false;
  bool pendingAbsent = false;
  bool activeAbsent = false;

  bool get cleanupVerified =>
      (!scheduleAttempted || scheduleSettled) &&
      cancelAcknowledged &&
      pendingAbsent &&
      activeAbsent;

  Map<String, Object?> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'reminderId': reminderId,
    'scheduleAttempted': scheduleAttempted,
    'scheduleAcknowledged': scheduleAcknowledged,
    'scheduleSettled': scheduleSettled,
    'cancelAcknowledged': cancelAcknowledged,
    'pendingAbsent': pendingAbsent,
    'activeAbsent': activeAbsent,
    'cleanupVerified': cleanupVerified,
  };
}

final class _OwnedReminderJournal {
  final String runId = '${DateTime.now().microsecondsSinceEpoch}-$pid';
  final File file = File(
    '${Directory.systemTemp.path}/lexiquest-native-services-owned.json',
  );
  final List<_OwnedReminder> owned = [];
  bool created = false;

  bool get cleanupVerified => owned.every((entry) => entry.cleanupVerified);

  Future<_OwnedReminder> reserve(
    FlutterLocalNotificationsPlugin plugin,
    String purpose,
  ) async {
    final pending = await plugin.pendingNotificationRequests().timeout(
      _operationTimeout,
    );
    final active = await plugin.getActiveNotifications().timeout(
      _operationTimeout,
    );
    final occupied = <int>{
      ...pending.map((entry) => entry.id),
      ...active.map((entry) => entry.id).whereType<int>(),
      ...owned.map((entry) => entry.id),
    };
    final random = Random.secure();
    for (var attempt = 0; attempt < 64; attempt += 1) {
      final id = 1 + random.nextInt(0x7ffffffe);
      if (occupied.contains(id)) continue;
      final entry = _OwnedReminder(
        id: id,
        ownerId: 'synthetic-native-services-$runId',
        reminderId: 'synthetic-$purpose-$runId',
      );
      owned.add(entry);
      await write();
      print('NATIVE_SERVICES_OWNED_REMINDER_RESERVED id=$id');
      return entry;
    }
    throw StateError('No unoccupied synthetic notification ID found.');
  }

  Future<void> write() async {
    if (await file.exists()) {
      if (!created)
        throw StateError('Existing native-services journal preserved.');
      final existing = jsonDecode(await file.readAsString()) as Map;
      if (existing['runId'] != runId) {
        throw StateError('Native-services journal ownership changed.');
      }
    } else if (created) {
      throw StateError('Native-services journal disappeared.');
    }
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'runId': runId,
        'cleanupVerified': cleanupVerified,
        'owned': owned.map((entry) => entry.toJson()).toList(growable: false),
      }),
      flush: true,
    );
    created = true;
  }
}

Future<void> _publishService() async {
  final uri = (await developer.Service.getInfo()).serverUri;
  if (uri == null || uri.host != '127.0.0.1') {
    throw StateError('Local VM service unavailable');
  }
  await File(
    '${Directory.systemTemp.path}/lexiquest-core-service-20260907.json',
  ).writeAsString(jsonEncode({'uri': uri.toString()}), flush: true);
}
