import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vocab_learning_app/features/media_practice/data/plugin_device_permission_access.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';

void main() {
  test(
    'maps camera and microphone status without requesting permission',
    () async {
      var cameraReads = 0;
      var microphoneReads = 0;
      var settingsOpens = 0;
      final access = PluginDevicePermissionAccess(
        cameraStatusReader: () async {
          cameraReads++;
          return PermissionStatus.granted;
        },
        microphoneStatusReader: () async {
          microphoneReads++;
          return PermissionStatus.permanentlyDenied;
        },
        appSettingsOpener: () async {
          settingsOpens++;
          return true;
        },
      );

      expect(await access.cameraStatus(), MediaPermissionState.granted);
      expect(
        await access.microphoneStatus(),
        MediaPermissionState.permanentlyDenied,
      );
      expect(cameraReads, 1);
      expect(microphoneReads, 1);
      expect(settingsOpens, 0);

      expect(await access.openAndroidSettings(), isTrue);
      expect(settingsOpens, 1);
    },
  );

  for (final (plugin, expected) in <(PermissionStatus, MediaPermissionState)>[
    (PermissionStatus.granted, MediaPermissionState.granted),
    (PermissionStatus.denied, MediaPermissionState.denied),
    (
      PermissionStatus.permanentlyDenied,
      MediaPermissionState.permanentlyDenied,
    ),
    (PermissionStatus.restricted, MediaPermissionState.restricted),
    (PermissionStatus.limited, MediaPermissionState.unavailable),
    (PermissionStatus.provisional, MediaPermissionState.unavailable),
  ]) {
    test('maps ${plugin.name} to ${expected.name}', () async {
      final access = PluginDevicePermissionAccess(
        cameraStatusReader: () async => plugin,
        microphoneStatusReader: () async => plugin,
      );

      expect(await access.cameraStatus(), expected);
      expect(await access.microphoneStatus(), expected);
    });
  }
}
