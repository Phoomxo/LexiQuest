import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';

void main() {
  test('fully ready requires cloud, capabilities, and inference readiness', () {
    const ready = AppRuntimeStatus(
      firebase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
      deviceCapabilities: RuntimeAvailability.ready,
      onDeviceInference: RuntimeAvailability.ready,
    );
    const offlineCapable = AppRuntimeStatus(
      firebase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    );

    expect(ready.isFullyReady, isTrue);
    expect(offlineCapable.isFullyReady, isFalse);
    expect(offlineCapable.isCoreLearningAvailable, isTrue);
  });

  test('capability readiness cannot imply on-device inference readiness', () {
    const status = AppRuntimeStatus(
      firebase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
      deviceCapabilities: RuntimeAvailability.ready,
      onDeviceInference: RuntimeAvailability.unavailable,
    );

    expect(status.isFullyReady, isFalse);
    expect(status.isCoreLearningAvailable, isTrue);
  });

  test('degraded capability evidence prevents aggregate full readiness', () {
    const status = AppRuntimeStatus(
      firebase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
      deviceCapabilities: RuntimeAvailability.degraded,
      onDeviceInference: RuntimeAvailability.unavailable,
    );

    expect(status.isFullyReady, isFalse);
    expect(status.isCoreLearningAvailable, isTrue);
  });
}
