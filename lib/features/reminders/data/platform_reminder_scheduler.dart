import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../domain/reminder_scheduler.dart';

const int maxPendingIosNotifications = 64;
const String _payloadPrefix = 'lexiquest-reminder:';

enum ReminderTargetPlatform { android, ios, unsupported }

enum ReminderSchedulePrecision { inexactAllowWhileIdle }

final class ReminderScheduleCapacityExceeded implements Exception {
  const ReminderScheduleCapacityExceeded();

  @override
  String toString() => 'ReminderScheduleCapacityExceeded';
}

final class NativeReminderSchedule {
  const NativeReminderSchedule({
    required this.platformId,
    required this.ownerId,
    required this.reminderId,
    required this.scheduledAtUtc,
    required this.timezoneId,
    required this.title,
    required this.body,
    required this.precision,
  });

  final int platformId;
  final String ownerId;
  final String reminderId;
  final DateTime scheduledAtUtc;
  final String timezoneId;
  final String title;
  final String body;
  final ReminderSchedulePrecision precision;
}

abstract interface class ReminderNativeGateway {
  Future<void> initialize();
  Future<bool> isSupported();
  Future<ReminderPermissionState> permissionState();
  Future<ReminderPermissionState> requestPermission();
  Future<List<ReminderPlatformEntry>> pendingEntries();
  Future<void> schedule(NativeReminderSchedule request);
  Future<void> cancel(int platformId);
}

final class PlatformReminderScheduler implements ReminderScheduler {
  PlatformReminderScheduler(this.gateway, {required this.targetPlatform});

  factory PlatformReminderScheduler.production() {
    final target = _currentTargetPlatform();
    return PlatformReminderScheduler(
      FlutterLocalNotificationsGateway(targetPlatform: target),
      targetPlatform: target,
    );
  }

  final ReminderNativeGateway gateway;
  final ReminderTargetPlatform targetPlatform;
  Future<void>? _initialization;

  @override
  Future<void> initialize() async {
    final existing = _initialization;
    if (existing != null) return existing;
    final attempt = gateway.initialize();
    _initialization = attempt;
    try {
      await attempt;
    } on Object {
      if (identical(_initialization, attempt)) _initialization = null;
      rethrow;
    }
  }

  @override
  Future<bool> isSupported() => gateway.isSupported();

  @override
  Future<ReminderPermissionState> permissionState() =>
      gateway.permissionState();

  @override
  Future<ReminderPermissionState> requestPermission() =>
      gateway.requestPermission();

  @override
  Future<List<ReminderPlatformEntry>> pendingEntries() =>
      targetPlatform == ReminderTargetPlatform.unsupported
      ? Future<List<ReminderPlatformEntry>>.value(const [])
      : gateway.pendingEntries();

  @override
  Future<void> schedule(ReminderScheduleRequest request) async {
    if (targetPlatform == ReminderTargetPlatform.unsupported) return;
    if (targetPlatform == ReminderTargetPlatform.ios) {
      final pending = await gateway.pendingEntries();
      final alreadyPending = pending.any(
        (entry) => entry.platformId == request.platformId,
      );
      if (!alreadyPending && pending.length >= maxPendingIosNotifications) {
        throw const ReminderScheduleCapacityExceeded();
      }
    }
    await gateway.schedule(
      NativeReminderSchedule(
        platformId: request.platformId,
        ownerId: request.ownerId,
        reminderId: request.reminderId,
        scheduledAtUtc: request.scheduledAtUtc,
        timezoneId: request.timezoneId,
        title: request.title,
        body: request.body,
        precision: ReminderSchedulePrecision.inexactAllowWhileIdle,
      ),
    );
  }

  @override
  Future<void> cancel(int platformId) =>
      targetPlatform == ReminderTargetPlatform.unsupported
      ? Future<void>.value()
      : gateway.cancel(platformId);
}

final class FlutterLocalNotificationsGateway implements ReminderNativeGateway {
  FlutterLocalNotificationsGateway({
    required this.targetPlatform,
    FlutterLocalNotificationsPlugin? plugin,
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final ReminderTargetPlatform targetPlatform;
  final FlutterLocalNotificationsPlugin plugin;
  bool _initialized = false;
  ReminderPermissionState? _lastRequestedPermission;

  @override
  Future<void> initialize() async {
    if (_initialized || targetPlatform == ReminderTargetPlatform.unsupported) {
      return;
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_lexiquest'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await plugin.initialize(settings: settings);
    _initialized = true;
  }

  @override
  Future<bool> isSupported() async =>
      targetPlatform != ReminderTargetPlatform.unsupported;

  @override
  Future<ReminderPermissionState> permissionState() async {
    if (targetPlatform == ReminderTargetPlatform.android) {
      final enabled = await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
      if (enabled == true) return ReminderPermissionState.granted;
      return _lastRequestedPermission ?? ReminderPermissionState.unknown;
    }
    if (targetPlatform == ReminderTargetPlatform.ios) {
      final permissions = await plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      if (permissions == null) return ReminderPermissionState.unknown;
      if (permissions.isAlertEnabled || permissions.isProvisionalEnabled) {
        return ReminderPermissionState.granted;
      }
      return _lastRequestedPermission ?? ReminderPermissionState.unknown;
    }
    return ReminderPermissionState.unknown;
  }

  @override
  Future<ReminderPermissionState> requestPermission() async {
    if (targetPlatform == ReminderTargetPlatform.android) {
      final granted = await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return _lastRequestedPermission = _permission(granted);
    }
    if (targetPlatform == ReminderTargetPlatform.ios) {
      final granted = await plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: false, sound: true);
      return _lastRequestedPermission = _permission(granted);
    }
    return ReminderPermissionState.unknown;
  }

  @override
  Future<List<ReminderPlatformEntry>> pendingEntries() async {
    final requests = await plugin.pendingNotificationRequests();
    return List<ReminderPlatformEntry>.unmodifiable(
      requests
          .map(
            (request) =>
                decodeReminderPlatformPayload(request.id, request.payload),
          )
          .whereType<ReminderPlatformEntry>(),
    );
  }

  @override
  Future<void> schedule(NativeReminderSchedule request) async {
    final location = timezone.getLocation(request.timezoneId);
    final scheduled = timezone.TZDateTime.from(
      request.scheduledAtUtc,
      location,
    );
    await plugin.zonedSchedule(
      id: request.platformId,
      title: request.title,
      body: request.body,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'lexiquest_study_reminders',
          'Study reminders',
          channelDescription: 'Optional reminders chosen by the learner',
          icon: 'ic_stat_lexiquest',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: encodeReminderPlatformPayload(
        ReminderPlatformEntry(
          platformId: request.platformId,
          ownerId: request.ownerId,
          reminderId: request.reminderId,
        ),
      ),
    );
  }

  @override
  Future<void> cancel(int platformId) => plugin.cancel(id: platformId);
}

String encodeReminderPlatformPayload(ReminderPlatformEntry entry) =>
    '$_payloadPrefix${jsonEncode(<String, Object>{'ownerId': entry.ownerId, 'reminderId': entry.reminderId})}';

ReminderPlatformEntry? decodeReminderPlatformPayload(
  int platformId,
  String? payload,
) {
  if (payload == null || !payload.startsWith(_payloadPrefix)) return null;
  try {
    final decoded = jsonDecode(payload.substring(_payloadPrefix.length));
    if (decoded is! Map) return null;
    final ownerId = decoded['ownerId'];
    final reminderId = decoded['reminderId'];
    if (ownerId is! String ||
        ownerId.isEmpty ||
        reminderId is! String ||
        reminderId.isEmpty) {
      return null;
    }
    return ReminderPlatformEntry(
      platformId: platformId,
      ownerId: ownerId,
      reminderId: reminderId,
    );
  } on Object {
    return null;
  }
}

ReminderPermissionState _permission(bool? granted) => switch (granted) {
  true => ReminderPermissionState.granted,
  false => ReminderPermissionState.denied,
  null => ReminderPermissionState.unknown,
};

ReminderTargetPlatform _currentTargetPlatform() {
  if (kIsWeb) return ReminderTargetPlatform.unsupported;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => ReminderTargetPlatform.android,
    TargetPlatform.iOS => ReminderTargetPlatform.ios,
    _ => ReminderTargetPlatform.unsupported,
  };
}
