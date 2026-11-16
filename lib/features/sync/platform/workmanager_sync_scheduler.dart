import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../../runtime/app_bootstrap.dart';
import '../application/sync_engine.dart';
import 'background_sync_scheduler.dart';

const String lexiQuestBackgroundSyncTask = 'lexiquest.backgroundSync.v1';

final class BackgroundTaskRegistration {
  const BackgroundTaskRegistration({
    required this.uniqueName,
    required this.taskName,
    required this.inputData,
    required this.frequency,
    required this.requiresConnectedNetwork,
    required this.updateExisting,
    required this.exponentialBackoff,
  });

  final String uniqueName;
  final String taskName;
  final Map<String, dynamic> inputData;
  final Duration frequency;
  final bool requiresConnectedNetwork;
  final bool updateExisting;
  final bool exponentialBackoff;
}

abstract interface class WorkmanagerClient {
  Future<void> initialize();

  Future<void> registerPeriodic(BackgroundTaskRegistration registration);
}

final class PluginWorkmanagerClient implements WorkmanagerClient {
  const PluginWorkmanagerClient();

  @override
  Future<void> initialize() {
    return Workmanager().initialize(lexiQuestSyncCallbackDispatcher);
  }

  @override
  Future<void> registerPeriodic(BackgroundTaskRegistration registration) {
    return Workmanager().registerPeriodicTask(
      registration.uniqueName,
      registration.taskName,
      frequency: registration.frequency,
      inputData: registration.inputData,
      constraints: Constraints(
        networkType: registration.requiresConnectedNetwork
            ? NetworkType.connected
            : NetworkType.notRequired,
      ),
      existingWorkPolicy: registration.updateExisting
          ? ExistingPeriodicWorkPolicy.update
          : ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: registration.exponentialBackoff
          ? BackoffPolicy.exponential
          : BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(seconds: 30),
      tag: 'lexiquest-sync',
    );
  }
}

final class WorkmanagerSyncScheduler implements BackgroundSyncScheduler {
  factory WorkmanagerSyncScheduler({
    required WorkmanagerClient client,
    required bool isAndroid,
    required bool cloudSyncEnabled,
  }) => WorkmanagerSyncScheduler._(client, isAndroid, cloudSyncEnabled);

  WorkmanagerSyncScheduler._(
    this._client,
    this.isAndroid,
    this.cloudSyncEnabled,
  );

  final WorkmanagerClient _client;
  final bool isAndroid;
  final bool cloudSyncEnabled;
  Future<void>? _initialization;

  @override
  Future<BackgroundSyncScheduleResult> schedule({
    required String ownerId,
  }) async {
    final canonicalOwnerId = ownerId.trim();
    if (canonicalOwnerId.isEmpty || canonicalOwnerId.length > 256) {
      throw ArgumentError.value(
        ownerId,
        'ownerId',
        'must contain 1-256 characters',
      );
    }
    if (!isAndroid) return BackgroundSyncScheduleResult.unsupported;
    if (!cloudSyncEnabled) {
      return BackgroundSyncScheduleResult.cloudDisabled;
    }
    await (_initialization ??= _client.initialize());
    await _client.registerPeriodic(
      BackgroundTaskRegistration(
        uniqueName: 'lexiquest.sync.$canonicalOwnerId',
        taskName: lexiQuestBackgroundSyncTask,
        inputData: <String, dynamic>{'ownerId': canonicalOwnerId},
        frequency: const Duration(hours: 1),
        requiresConnectedNetwork: true,
        updateExisting: true,
        exponentialBackoff: true,
      ),
    );
    return BackgroundSyncScheduleResult.scheduled;
  }
}

bool workmanagerSuccess(SyncRunResult result) {
  return result.status != SyncRunStatus.partialFailure ||
      !result.retryRecommended;
}

@pragma('vm:entry-point')
void lexiQuestSyncCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != lexiQuestBackgroundSyncTask) return true;
    WidgetsFlutterBinding.ensureInitialized();
    final expectedOwnerId = inputData?['ownerId'];
    if (expectedOwnerId is! String || expectedOwnerId.trim().isEmpty) {
      return true;
    }

    try {
      final dependencies = await AppBootstrap.production().initialize();
      try {
        final owner = await dependencies.localOwners?.getOrCreateActiveOwner();
        if (owner == null || owner.id != expectedOwnerId) return true;
        final engine = dependencies.syncEngine;
        if (engine == null) return false;
        return workmanagerSuccess(await engine.run());
      } finally {
        await dependencies.dispose();
      }
    } catch (_) {
      return false;
    }
  });
}
