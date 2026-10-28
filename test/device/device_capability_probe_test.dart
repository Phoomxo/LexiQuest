import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/device/device_capability_models.dart';
import 'package:vocab_learning_app/device/device_capability_probe.dart';

const _channel = MethodChannel('com.lexiquest.app/device_capabilities');

Map<String, Object?> _validSnapshot({
  int sdkInt = 35,
  Object? availableMemoryMb = 3072,
  Object? freeStorageBytes = 4294967296,
  Object? lowMemory = false,
  Object? batterySaverEnabled = false,
  Object? gpuApiCandidate = true,
}) {
  return <String, Object?>{
    'sdkInt': sdkInt,
    'primaryAbi': 'arm64-v8a',
    'memoryClassMb': 512,
    'availableMemoryMb': availableMemoryMb,
    'freeStorageBytes': freeStorageBytes,
    'lowMemory': lowMemory,
    'batterySaverEnabled': batterySaverEnabled,
    'thermalState': 'fair',
    'gpuApiCandidate': gpuApiCandidate,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'uses the exact Android capability channel and snapshot method',
    () async {
      MethodCall? receivedCall;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        receivedCall = call;
        return _validSnapshot();
      });

      await const MethodChannelDeviceCapabilityProbe().snapshot();

      expect(receivedCall, isNotNull);
      expect(receivedCall!.method, 'snapshot');
      expect(receivedCall!.arguments, isNull);
    },
  );

  test(
    'parses a complete typed platform map without inventing signals',
    () async {
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => _validSnapshot(
          availableMemoryMb: null,
          freeStorageBytes: null,
          lowMemory: null,
          batterySaverEnabled: null,
          gpuApiCandidate: null,
        ),
      );

      final snapshot = await const MethodChannelDeviceCapabilityProbe()
          .snapshot();

      expect(snapshot.sdkInt, 35);
      expect(snapshot.primaryAbi, 'arm64-v8a');
      expect(snapshot.memoryClassMb, 512);
      expect(snapshot.availableMemoryMb, isNull);
      expect(snapshot.freeStorageBytes, isNull);
      expect(snapshot.lowMemory, isNull);
      expect(snapshot.batterySaverEnabled, isNull);
      expect(snapshot.thermalState, DeviceThermalState.fair);
      expect(snapshot.gpuApiCandidate, isNull);
      expect(snapshot.hasRequiredPolicyEvidence, isFalse);
    },
  );

  test(
    'rejects malformed and missing snapshot fields with a stable code',
    () async {
      for (final payload in <Object?>[
        <String, Object?>{..._validSnapshot()}..remove('primaryAbi'),
        <String, Object?>{..._validSnapshot(), 'memoryClassMb': '512'},
        <String, Object?>{..._validSnapshot(), 'thermalState': 'hot'},
        <String, Object?>{..._validSnapshot(), 'unexpected': true},
      ]) {
        messenger.setMockMethodCallHandler(_channel, (_) async => payload);

        await expectLater(
          const MethodChannelDeviceCapabilityProbe().snapshot(),
          throwsA(
            isA<DeviceCapabilityUnavailable>().having(
              (error) => error.code,
              'code',
              'malformed-snapshot',
            ),
          ),
        );
      }
    },
  );

  test(
    'maps a native PlatformException without exposing its details',
    () async {
      const sentinel = 'NATIVE-CAPABILITY-SECRET-7c9f3a';
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw PlatformException(
          code: 'capability-unavailable',
          message: sentinel,
          details: <String, Object?>{'secret': sentinel},
        ),
      );

      Object? captured;
      try {
        await const MethodChannelDeviceCapabilityProbe().snapshot();
      } catch (error) {
        captured = error;
      }

      expect(captured, isA<DeviceCapabilityUnavailable>());
      expect(
        (captured! as DeviceCapabilityUnavailable).code,
        'channel-unavailable',
      );
      expect(captured.toString(), isNot(contains(sentinel)));
      expect(
        captured.toString(),
        'DeviceCapabilityUnavailable(channel-unavailable)',
      );
    },
  );

  test('maps a missing plugin to channel-unavailable', () async {
    await expectLater(
      const MethodChannelDeviceCapabilityProbe().snapshot(),
      throwsA(
        isA<DeviceCapabilityUnavailable>().having(
          (error) => error.code,
          'code',
          'channel-unavailable',
        ),
      ),
    );
  });

  test('rejects a valid pre-Android-10 snapshot', () async {
    messenger.setMockMethodCallHandler(
      _channel,
      (_) async => _validSnapshot(sdkInt: 28),
    );

    await expectLater(
      const MethodChannelDeviceCapabilityProbe().snapshot(),
      throwsA(
        isA<DeviceCapabilityUnavailable>().having(
          (error) => error.code,
          'code',
          'android-version-unsupported',
        ),
      ),
    );
  });

  test('rejects non-Android platforms before invoking the channel', () async {
    var invoked = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(_channel, (_) async {
      invoked = true;
      return _validSnapshot();
    });

    await expectLater(
      const MethodChannelDeviceCapabilityProbe().snapshot(),
      throwsA(
        isA<DeviceCapabilityUnavailable>().having(
          (error) => error.code,
          'code',
          'unsupported-platform',
        ),
      ),
    );
    expect(invoked, isFalse);
  });

  test('unavailable errors cannot accept or render arbitrary caller text', () {
    const sentinel = 'NATIVE-CAPABILITY-SECRET-7c9f3a';
    dynamic channelUnavailable = DeviceCapabilityUnavailable.channelUnavailable;

    expect(() => channelUnavailable(sentinel), throwsA(anything));

    const error = DeviceCapabilityUnavailable.channelUnavailable();
    expect(error.code, 'channel-unavailable');
    expect(
      error.toString(),
      'DeviceCapabilityUnavailable(channel-unavailable)',
    );
    expect(error.toString(), isNot(contains(sentinel)));
  });
}
