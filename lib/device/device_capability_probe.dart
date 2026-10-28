import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_capability_models.dart';

abstract interface class DeviceCapabilityProbe {
  Future<DeviceCapabilitySnapshot> snapshot();
}

final class MethodChannelDeviceCapabilityProbe
    implements DeviceCapabilityProbe {
  const MethodChannelDeviceCapabilityProbe();

  static const MethodChannel _channel = MethodChannel(
    'com.lexiquest.app/device_capabilities',
  );
  static const String _snapshotMethod = 'snapshot';
  static const Set<String> _snapshotKeys = <String>{
    'sdkInt',
    'primaryAbi',
    'memoryClassMb',
    'availableMemoryMb',
    'freeStorageBytes',
    'lowMemory',
    'batterySaverEnabled',
    'thermalState',
    'gpuApiCandidate',
  };

  @override
  Future<DeviceCapabilitySnapshot> snapshot() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const DeviceCapabilityUnavailable.unsupportedPlatform();
    }

    final Object? payload;
    try {
      payload = await _channel.invokeMethod<Object?>(_snapshotMethod);
    } on MissingPluginException {
      throw const DeviceCapabilityUnavailable.channelUnavailable();
    } on PlatformException {
      throw const DeviceCapabilityUnavailable.channelUnavailable();
    } on Object {
      throw const DeviceCapabilityUnavailable.channelUnavailable();
    }

    try {
      final snapshot = _parseSnapshot(payload);
      if (!snapshot.isSupported) {
        throw const DeviceCapabilityUnavailable.androidVersionUnsupported();
      }
      return snapshot;
    } on DeviceCapabilityUnavailable {
      rethrow;
    } on Object {
      throw const DeviceCapabilityUnavailable.malformedSnapshot();
    }
  }

  DeviceCapabilitySnapshot _parseSnapshot(Object? payload) {
    if (payload is! Map<Object?, Object?> ||
        payload.length != _snapshotKeys.length ||
        payload.keys.any((key) => key is! String) ||
        !payload.keys.cast<String>().toSet().containsAll(_snapshotKeys)) {
      throw const DeviceCapabilityUnavailable.malformedSnapshot();
    }

    final sdkInt = payload['sdkInt'];
    final primaryAbi = payload['primaryAbi'];
    final memoryClassMb = payload['memoryClassMb'];
    final availableMemoryMb = payload['availableMemoryMb'];
    final freeStorageBytes = payload['freeStorageBytes'];
    final lowMemory = payload['lowMemory'];
    final batterySaverEnabled = payload['batterySaverEnabled'];
    final thermalState = payload['thermalState'];
    final gpuApiCandidate = payload['gpuApiCandidate'];

    if (sdkInt is! int ||
        primaryAbi is! String ||
        memoryClassMb is! int ||
        !_isNullable<int>(availableMemoryMb) ||
        !_isNullable<int>(freeStorageBytes) ||
        !_isNullable<bool>(lowMemory) ||
        !_isNullable<bool>(batterySaverEnabled) ||
        thermalState is! String ||
        !_isNullable<bool>(gpuApiCandidate)) {
      throw const DeviceCapabilityUnavailable.malformedSnapshot();
    }

    final normalizedThermalState = switch (thermalState) {
      'nominal' => DeviceThermalState.nominal,
      'fair' => DeviceThermalState.fair,
      'serious' => DeviceThermalState.serious,
      'critical' => DeviceThermalState.critical,
      'unknown' => DeviceThermalState.unknown,
      _ => throw const DeviceCapabilityUnavailable.malformedSnapshot(),
    };

    return DeviceCapabilitySnapshot(
      sdkInt: sdkInt,
      primaryAbi: primaryAbi,
      memoryClassMb: memoryClassMb,
      availableMemoryMb: availableMemoryMb as int?,
      freeStorageBytes: freeStorageBytes as int?,
      lowMemory: lowMemory as bool?,
      batterySaverEnabled: batterySaverEnabled as bool?,
      thermalState: normalizedThermalState,
      gpuApiCandidate: gpuApiCandidate as bool?,
    );
  }

  bool _isNullable<T>(Object? value) => value == null || value is T;
}

enum DeviceCapabilityUnavailableCode {
  unsupportedPlatform('unsupported-platform'),
  channelUnavailable('channel-unavailable'),
  malformedSnapshot('malformed-snapshot'),
  androidVersionUnsupported('android-version-unsupported');

  const DeviceCapabilityUnavailableCode(this.code);

  final String code;
}

final class DeviceCapabilityUnavailable implements Exception {
  const DeviceCapabilityUnavailable.unsupportedPlatform()
    : this._(DeviceCapabilityUnavailableCode.unsupportedPlatform);

  const DeviceCapabilityUnavailable.channelUnavailable()
    : this._(DeviceCapabilityUnavailableCode.channelUnavailable);

  const DeviceCapabilityUnavailable.malformedSnapshot()
    : this._(DeviceCapabilityUnavailableCode.malformedSnapshot);

  const DeviceCapabilityUnavailable.androidVersionUnsupported()
    : this._(DeviceCapabilityUnavailableCode.androidVersionUnsupported);

  const DeviceCapabilityUnavailable._(this.reason);

  final DeviceCapabilityUnavailableCode reason;

  String get code => reason.code;

  @override
  String toString() => 'DeviceCapabilityUnavailable($code)';
}
