import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../identity/data/drift_owner_write_coordinator.dart';
import '../domain/study_reminder.dart';

final class MethodChannelStudyReminderPlatform
    implements StudyReminderPlatform {
  const MethodChannelStudyReminderPlatform({
    required this.ownerWrites,
    this.isAndroid,
  });
  static const _channel = MethodChannel('com.lexiquest.app/study_reminder');
  // The private Android process may need a cold start before opening SQLite.
  static const _requestTimeout = Duration(seconds: 15);
  final DriftOwnerWriteCoordinator ownerWrites;
  final bool? isAndroid;
  bool get _supportedPlatform => isAndroid ?? Platform.isAndroid;

  @override
  Future<StudyReminderPlatformStatus> inspect() async {
    if (!_supportedPlatform) {
      return const StudyReminderPlatformStatus.unsupported();
    }
    try {
      final value = await _channel
          .invokeMapMethod<String, Object?>('inspect')
          .timeout(_requestTimeout);
      if (value?['supported'] != true ||
          value?['notificationsAllowed'] is! bool) {
        return const StudyReminderPlatformStatus.unsupported();
      }
      return StudyReminderPlatformStatus(
        supported: true,
        notificationsAllowed: value!['notificationsAllowed'] == true,
      );
    } on Object {
      return const StudyReminderPlatformStatus.unsupported();
    }
  }

  @override
  Future<StudyReminderPlatformStatus> requestPermission() async {
    final before = await inspect();
    if (!before.supported || before.notificationsAllowed) return before;
    await Permission.notification.request();
    return inspect();
  }

  @override
  Future<String> bindScope({
    required String databasePath,
    required String ownerId,
  }) async {
    final value = await _call('bindScope', {
      'databasePath': databasePath,
      'ownerId': ownerId,
    });
    final token = value['scopeToken'];
    if (token is! String || token.isEmpty || token.length > 256) {
      throw const StudyReminderException(
        StudyReminderFailureCode.platformUnavailable,
      );
    }
    return token;
  }

  @override
  Future<StudyReminderRequestAck> schedule({
    required String scopeToken,
    required int revision,
  }) => _request('schedule', scopeToken, revision);

  @override
  Future<StudyReminderRequestAck> cancel({
    required String scopeToken,
    required int revision,
  }) => _request('cancel', scopeToken, revision);

  Future<StudyReminderRequestAck> _request(
    String method,
    String token,
    int revision,
  ) async {
    final value = await _call(method, {
      'scopeToken': token,
      'revision': revision,
    });
    if (value['accepted'] != true || value['revision'] != revision) {
      throw const StudyReminderException(
        StudyReminderFailureCode.requestUnconfirmed,
      );
    }
    final next = value['nextAtUtcMs'];
    if (method == 'schedule' &&
        (next is! int || next < 0 || next > 8640000000000000)) {
      throw const StudyReminderException(
        StudyReminderFailureCode.requestUnconfirmed,
      );
    }
    return StudyReminderRequestAck(
      revision: revision,
      nextAtUtc: next is int
          ? DateTime.fromMillisecondsSinceEpoch(next, isUtc: true)
          : null,
    );
  }

  @override
  Future<void> retire({String? scopeToken}) async {
    if (!_supportedPlatform) return;
    await _call('retire', {'scopeToken': scopeToken});
  }

  Future<Map<String, Object?>> _call(
    String method,
    Map<String, Object?> args,
  ) async {
    if (!_supportedPlatform) {
      throw const StudyReminderException(
        StudyReminderFailureCode.platformUnavailable,
      );
    }
    try {
      if (await ownerWrites.hasAmbientTransaction()) {
        throw const StudyReminderException(
          StudyReminderFailureCode.platformUnavailable,
        );
      }
      // Pause Drift writers without holding SQLite's writer across native IPC.
      final value = await ownerWrites.database.exclusively(
        () => _channel
            .invokeMapMethod<String, Object?>(method, args)
            .timeout(_requestTimeout),
      );
      if (value == null) {
        throw const StudyReminderException(
          StudyReminderFailureCode.platformUnavailable,
        );
      }
      return value;
    } on StudyReminderException catch (error) {
      debugPrint(
        'LexiQuestReminder platform $method rejected ${error.code.name}',
      );
      rethrow;
    } on PlatformException catch (error) {
      final failure = switch (error.code) {
        'OWNER_CHANGED' => StudyReminderFailureCode.ownerChanged,
        'PERMISSION_DENIED' => StudyReminderFailureCode.permissionDenied,
        _ => StudyReminderFailureCode.platformUnavailable,
      };
      debugPrint(
        'LexiQuestReminder platform $method PlatformException ${failure.name}',
      );
      throw StudyReminderException(failure);
    } on Object catch (error) {
      debugPrint(
        'LexiQuestReminder platform $method failed ${error.runtimeType}',
      );
      throw const StudyReminderException(
        StudyReminderFailureCode.platformUnavailable,
      );
    }
  }
}
