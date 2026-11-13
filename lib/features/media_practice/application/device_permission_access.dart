import '../domain/media_practice_contracts.dart';

abstract interface class DevicePermissionAccess {
  Future<MediaPermissionState> cameraStatus();

  Future<MediaPermissionState> microphoneStatus();

  Future<bool> openAndroidSettings();
}
