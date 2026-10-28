### Task 3: Connect the real Android capability probe

**Files:**

- Create: `lib/device/device_capability_probe.dart`
- Create: `android/app/src/main/kotlin/com/lexiquest/app/DeviceCapabilityPlugin.kt`
- Modify: `android/app/src/main/kotlin/com/lexiquest/app/MainActivity.kt`
- Modify: `android/app/build.gradle.kts`
- Modify: `lib/runtime/app_dependencies.dart`
- Modify: `lib/runtime/app_bootstrap.dart`
- Modify: `lib/runtime/app_runtime_status.dart`
- Create: `test/device/device_capability_probe_test.dart`
- Modify: `test/runtime/app_bootstrap_test.dart`
- Create: `tool/cli/tests/android-device-capability-contract.tests.ps1`

**Interfaces:**

- Consumes: `DeviceCapabilitySnapshot` from Task 2.
- Produces:
  - `abstract interface class DeviceCapabilityProbe`
  - `MethodChannelDeviceCapabilityProbe`
  - channel `com.lexiquest.app/device_capabilities`
  - method `snapshot`
  - nullable snapshot plus truthful runtime availability in
    `AppDependencies`.

- [ ] **Step 1: Write failing Dart channel tests**

Use Flutter's mock binary messenger to cover:

- exact channel/method;
- successful typed map parsing;
- malformed/missing fields -> `DeviceCapabilityUnavailable`;
- `PlatformException`, missing plugin, and unsupported SDK -> unavailable
  without exposing native exception text;
- `toString()` redaction.

Run:

```powershell
flutter test test/device/device_capability_probe_test.dart --reporter compact
```

Expected: RED because the probe does not exist.

- [ ] **Step 2: Implement the Dart probe**

Invoke only `snapshot`, validate every field, and map errors to stable codes:
`unsupported-platform`, `channel-unavailable`, `malformed-snapshot`, and
`android-version-unsupported`.

- [ ] **Step 3: Write the Android host contract**

The PowerShell contract must assert:

- `minSdk = 29`;
- the exact channel and method names match Dart;
- `MainActivity.configureFlutterEngine` calls `super` and registers one
  `DeviceCapabilityPlugin`;
- the plugin uses `ActivityManager.MemoryInfo`, `memoryClass`,
  `StatFs`, `PowerManager.isPowerSaveMode`, `PowerManager.currentThermalStatus`,
  `Build.SUPPORTED_ABIS`, and device configuration GPU API data;
- the returned map contains exactly the Dart snapshot keys;
- no `Build.MODEL`, `Build.MANUFACTURER`, Android ID, serial, logging call, or
  network API appears.

- [ ] **Step 4: Implement the Kotlin plugin**

Return the snapshot synchronously through `MethodChannel.Result`. Convert
bytes to whole MiB only at the channel boundary. Map Android thermal constants
to the stable Dart enum names. `gpuApiCandidate` means only that the Android
graphics API is a possible candidate; it never claims a LiteRT delegate
initialized.

- [ ] **Step 5: Integrate non-blocking bootstrap**

`AppBootstrap` invokes the injected probe once. A successful snapshot is
retained in `AppDependencies`; failure records
`RuntimeAvailability.unavailable` for device compute while Firebase, local
learning, and account startup continue independently.

Add bootstrap tests for ready, unavailable, and exception-redaction paths.

- [ ] **Step 6: Run the consolidated section gate**

Run once after Tasks 1–3:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/android-device-capability-contract.tests.ps1
flutter test test/device test/runtime/app_bootstrap_test.dart test/runtime/app_runtime_status_test.dart --reporter compact
flutter analyze lib/device lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/runtime/app_runtime_status.dart
flutter build apk --debug --dart-define=LEXIQUEST_VERSION=0.1.0+1 --dart-define=LEXIQUEST_BUILD_ID=device-compute-foundation
```

Expected: every command exits `0`. The APK build proves Android/Kotlin
compilation only; it does not claim that a real model or GPU delegate has run.

- [ ] **Step 7: Commit**

```powershell
git add -- android/app/build.gradle.kts android/app/src/main/kotlin/com/lexiquest/app/DeviceCapabilityPlugin.kt android/app/src/main/kotlin/com/lexiquest/app/MainActivity.kt lib/device lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/runtime/app_runtime_status.dart test/device test/runtime/app_bootstrap_test.dart tool/cli/tests/android-device-capability-contract.tests.ps1
git commit -m "feat: connect Android device capability probing"
```

---

## Section acceptance boundary

After Task 3, the repository may claim:

- every current visible feature has an explicit inventory/status/dependency
  record;
- new or stale fabricated production paths are detected by a bounded contract;
- Android 10+ CPU/GPU capability inputs come from the real phone;
- backend selection is deterministic and always falls back to CPU safely;
- the debug APK compiles with the native capability plugin.

It may not yet claim:

- XNNPACK or GPU delegate executed a real model;
- camera object labeling is implemented;
- optional model download/activation is implemented;
- scanner/speech physical-device gates passed.

Those claims require the checksummed model, inference adapter, camera lifecycle,
and physical Android validation in the subsequent Device Feature work package.
