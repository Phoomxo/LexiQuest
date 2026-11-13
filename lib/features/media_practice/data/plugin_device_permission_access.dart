import 'package:permission_handler/permission_handler.dart';

import '../application/device_permission_access.dart';
import '../domain/media_practice_contracts.dart';

typedef PermissionStatusReader = Future<PermissionStatus> Function();
typedef AppSettingsOpener = Future<bool> Function();

final class PluginDevicePermissionAccess implements DevicePermissionAccess {
  const PluginDevicePermissionAccess({
    this.cameraStatusReader,
    this.microphoneStatusReader,
    this.appSettingsOpener,
  });

  final PermissionStatusReader? cameraStatusReader;
  final PermissionStatusReader? microphoneStatusReader;
  final AppSettingsOpener? appSettingsOpener;

  @override
  Future<MediaPermissionState> cameraStatus() async {
    final reader = cameraStatusReader;
    return _map(
      reader == null ? await Permission.camera.status : await reader(),
    );
  }

  @override
  Future<MediaPermissionState> microphoneStatus() async {
    final reader = microphoneStatusReader;
    return _map(
      reader == null ? await Permission.microphone.status : await reader(),
    );
  }

  @override
  Future<bool> openAndroidSettings() {
    return appSettingsOpener?.call() ?? openAppSettings();
  }

  static MediaPermissionState _map(PermissionStatus status) {
    if (status.isGranted) return MediaPermissionState.granted;
    if (status.isPermanentlyDenied) {
      return MediaPermissionState.permanentlyDenied;
    }
    if (status.isRestricted) return MediaPermissionState.restricted;
    if (status.isDenied) return MediaPermissionState.denied;
    return MediaPermissionState.unavailable;
  }
}
