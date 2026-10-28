# Task 3 — Android device capability probe report

## Status

Implemented an Android-API-backed capability input probe, connected it through the
Flutter bootstrap, and passed the bounded Tasks 1–3 consolidated section gate.
The build proves Android/Dart/Kotlin compilation only. No model, inference
backend, GPU delegate, camera path, or physical-device execution was added or
claimed.

Implementation commit: `409bbfa` (`feat: connect Android device capability
probing`).

## TDD evidence

### Dart channel probe

RED:

```text
flutter test test/device/device_capability_probe_test.dart --reporter compact
exit 1
Error when reading 'lib/device/device_capability_probe.dart':
The system cannot find the file specified
```

GREEN:

```text
flutter test test/device/device_capability_probe_test.dart --reporter compact
exit 0
7 tests passed
```

The tests cover the exact channel/method, complete typed parsing, explicit
nullable capability signals, missing/malformed fields, extra fields,
`PlatformException`, missing plugin, Android SDK below 29, unsupported
platforms, and exception-string redaction.

### Android host contract

RED, before the Kotlin host existed:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/android-device-capability-contract.tests.ps1
exit 1
6 passed, 14 failed
```

The failures included the absent explicit API 29 minimum, Kotlin channel and
method, `configureFlutterEngine` registration, required Android capability
APIs, and returned snapshot keys. This demonstrates that the static contract
detects the missing implementation.

The first implementation run reached 19 passed and 1 failed. Investigation
showed that the contract's lazy map parser stopped at the first nested Kotlin
parenthesis after `primaryAbi`; the production map contained all nine keys.
Anchoring the parser to the outer `mapOf` close corrected the test itself.

GREEN:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/android-device-capability-contract.tests.ps1
exit 0
20 passed, 0 failed
```

### Bootstrap integration

RED:

```text
flutter test test/runtime/app_bootstrap_test.dart --reporter compact
exit 1
No named parameter with the name 'deviceCapabilityProbe'
```

GREEN:

```text
flutter test test/runtime/app_bootstrap_test.dart --reporter compact
exit 0
15 tests passed
```

The added scenarios prove one successful invocation and exact snapshot
retention, unavailable-device-compute fallback without blocking Firebase,
configuration, or local repository startup, and redaction of an unexpected
probe exception sentinel.

## Channel contract

- Channel: `com.lexiquest.app/device_capabilities`
- Method: `snapshot`
- Arguments: none
- Success result: a map containing exactly these nine keys:

| Key | Channel type | Nullable |
| --- | --- | --- |
| `sdkInt` | integer | no |
| `primaryAbi` | string | no |
| `memoryClassMb` | integer | no |
| `availableMemoryMb` | integer | yes |
| `freeStorageBytes` | integer | yes |
| `lowMemory` | boolean | yes |
| `batterySaverEnabled` | boolean | yes |
| `thermalState` | `nominal`, `fair`, `serious`, `critical`, or `unknown` | no |
| `gpuApiCandidate` | boolean | yes |

The Dart adapter validates the complete key set and every value type. It
preserves nullable signals so `DeviceCapabilitySnapshot` continues to fail safe
when required policy evidence is absent. It maps failures to only these stable
codes:

- `unsupported-platform`
- `channel-unavailable`
- `malformed-snapshot`
- `android-version-unsupported`

`DeviceCapabilityUnavailable.toString()` renders only the stable code and never
native exception messages or details.

## Android API mappings

The application explicitly binds `minSdk = 29`.

| Snapshot field | Android source/mapping |
| --- | --- |
| `sdkInt` | `Build.VERSION.SDK_INT` |
| `primaryAbi` | first entry in `Build.SUPPORTED_ABIS`, normalized lowercase |
| `memoryClassMb` | `ActivityManager.memoryClass` |
| `availableMemoryMb` | `ActivityManager.MemoryInfo.availMem`, converted from bytes to whole MiB at the channel boundary |
| `freeStorageBytes` | `StatFs(context.filesDir.absolutePath).availableBytes`, retained in bytes to match the Dart schema |
| `lowMemory` | `ActivityManager.MemoryInfo.lowMemory` |
| `batterySaverEnabled` | `PowerManager.isPowerSaveMode` |
| `thermalState` | `NONE` → `nominal`; `LIGHT`/`MODERATE` → `fair`; `SEVERE` → `serious`; `CRITICAL`/`EMERGENCY`/`SHUTDOWN` → `critical`; other/unavailable → `unknown` |
| `gpuApiCandidate` | device `ConfigurationInfo.reqGlEsVersion >= 0x00030000`; nullable if configuration data is unavailable |

`gpuApiCandidate` is graphics API candidacy only. It is not evidence that a
LiteRT/TensorFlow Lite GPU delegate initialized or executed.

`MainActivity.configureFlutterEngine` calls `super` once and registers one
`DeviceCapabilityPlugin` through `flutterEngine.plugins.add`. The plugin
responds synchronously through `MethodChannel.Result` and redacts caught native
exception details.

## Bootstrap behavior

`AppBootstrap` accepts an injected `DeviceCapabilityProbe`, with
`MethodChannelDeviceCapabilityProbe` as the production default, and invokes it
once. `AppDependencies.deviceCapabilitySnapshot` retains any parsed snapshot.
`runtimeStatus.deviceCapabilities` is `ready` only for complete policy
evidence, `degraded` for a partial snapshot, and `unavailable` for a null
snapshot. `runtimeStatus.onDeviceInference` remains `unavailable` because this
phase has no model or adapter. Firebase status, backend configuration, account
construction, local progress loading, and learning startup keep their
independent outcomes.

No native exception object, message, stack, or details are retained in
`AppDependencies` or `AppRuntimeStatus`.

## Consolidated section gate

The specified commands ran sequentially once after implementation:

1. Prototype production-path contract — exit `0`
   - `candidateFiles=198`
   - `knownDebt=18`
   - `matches=29`
   - `new=0`
   - `stale=0`
2. Android capability contract — exit `0`
   - `20 passed, 0 failed`
3. Targeted Flutter tests — exit `0`
   - `54 passed, 0 failed`
4. Scoped Flutter analysis — exit `0`
   - `No issues found`
5. Debug APK build — exit `0`
   - artifact:
     `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-v0.1-complete-system\build\app\outputs\flutter-apk\app-debug.apk`
   - size: `182,757,320` bytes (approximately `174.29 MiB`)
   - SHA-256:
     `fc6776533803c43b75bd939899d664fb5bb820f27555ef66800eb353e9f14dbf`

The build emitted existing forward-compatibility warnings for Android Gradle
Plugin 8.9.1, Kotlin 2.1.0, and an Android SDK XML tool-version mismatch. It
still exited `0`; dependency upgrades were outside this bounded task.

## Files changed

- `android/.gitignore`
- `android/app/build.gradle.kts`
- `android/app/src/main/kotlin/com/lexiquest/app/DeviceCapabilityPlugin.kt`
- `android/app/src/main/kotlin/com/lexiquest/app/MainActivity.kt`
- `lib/device/device_capability_probe.dart`
- `lib/runtime/app_dependencies.dart`
- `lib/runtime/app_bootstrap.dart`
- `lib/runtime/app_runtime_status.dart`
- `test/device/device_capability_probe_test.dart`
- `test/runtime/app_bootstrap_test.dart`
- `tool/cli/tests/android-device-capability-contract.tests.ps1`
- `.superpowers/sdd/android-capability-task-3-report.md`

The debug build created an untracked `android/.kotlin/` cache. A verified,
worktree-local deletion command was rejected by shell policy before execution,
so it was not retried. The parent-approved non-destructive alternative was
used: `/.kotlin/` was added narrowly to `android/.gitignore`. The cache contents
were not enumerated and are not committed.

## Self-review

- Confirmed the Kotlin result map and Dart parser share exactly nine keys.
- Confirmed API 29 is explicit and every API used is available at that level.
- Confirmed nullable Android services/signals remain nullable or map to
  `unknown`, preserving the fail-safe policy.
- Confirmed no `Build.MODEL`, `Build.MANUFACTURER`, Android ID, serial,
  hardware identifier, logging call, or network API appears in the plugin.
- Confirmed no TensorFlow/LiteRT dependency, model, camera work, optional
  download path, or production inference claim was introduced.
- Confirmed channel/native failures are caught, mapped to stable availability,
  and do not expose native exception text.
- Confirmed the scoped diff contains no unrelated production changes.

## Physical-device limitation

No physical Android device was connected for this task. Therefore the work
does not claim that real handset values were observed, a GPU delegate or CPU
inference backend ran, a model loaded, camera labeling worked, or scanner/speech
physical-device gates passed. Those require the subsequent device-feature work
package and physical Android validation.

---

## Reviewer remediation follow-up

The Task 3 review findings were addressed in a bounded follow-up after commit
`409bbfa`.

Follow-up commit: `765d726` (`fix: harden Android capability readiness`).

### Runtime truthfulness and navigation RED/GREEN

RED:

```text
flutter test test/runtime/app_runtime_status_test.dart test/runtime/app_bootstrap_test.dart test/screens/production_shell_navigation_test.dart --reporter compact
exit 1
22 passed, 3 failed
```

The three expected failures showed that device compute unavailability still
left `isFullyReady == true`, bootstrap reported aggregate readiness despite an
unavailable probe, and the drawer still rendered the all-systems-ready summary.

GREEN:

```text
flutter test test/runtime/app_runtime_status_test.dart test/runtime/app_bootstrap_test.dart test/screens/production_shell_navigation_test.dart --reporter compact
exit 0
25 passed, 0 failed
```

`AppRuntimeStatus.isFullyReady` now requires Firebase, configured online
backends, the capability profile, and on-device inference to all be ready.
`isCoreLearningAvailable` remains true when either device status is unavailable.
`MainNavigationScreen` distinguishes `Device capabilities (degraded)` from
`On-device inference` and retains the truthful local offline-learning message
instead of claiming the whole system is ready.

### Contract parity and missing ActivityManager RED/GREEN

RED after adding the focused contract assertions:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/android-device-capability-contract.tests.ps1
exit 1
20 passed, 4 failed
```

The failures demonstrated the missing Dart-schema parser/mismatch self-test,
the synthetic `memoryClassMb = 0` behavior when `ActivityManager` was missing,
and the insufficiently exact available-memory conversion assertion.

GREEN:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/android-device-capability-contract.tests.ps1
exit 0
25 passed, 0 failed
```

The contract now:

- parses `_snapshotKeys` directly from Dart source;
- parses the Kotlin `mapOf<String, Any?>` result independently;
- compares non-empty, unique, case-sensitive exact sets;
- has no duplicate hard-coded production key list;
- includes a two-key Dart/Kotlin mismatch fixture and proves parity rejects it;
- requires a missing `ActivityManager` to fail through a private exception and
  the stable redacted `capability-unavailable` platform error;
- requires `MemoryInfo.availMem` to pass through the exact whole-MiB conversion;
- requires `StatFs(...).availableBytes` to remain bytes;
- checks every Android thermal constant against its exact stable Dart name.

The Kotlin plugin no longer substitutes `memoryClassMb = 0`.
`ActivityManager` absence aborts the snapshot, and the channel exposes only
`capability-unavailable` with null message/details. The Dart channel test uses
that exact native error code and verifies it maps to
`channel-unavailable` without leaking native details.

### Expanded consolidated gate

The complete follow-up gate ran sequentially once:

1. Prototype production-path contract — exit `0`
   - `candidateFiles=199`
   - `knownDebt=18`
   - `matches=29`
   - `new=0`
   - `stale=0`
2. Strengthened Android capability contract — exit `0`
   - `25 passed, 0 failed`
3. Focused device/runtime/status/navigation tests — exit `0`
   - command included `test/device`, bootstrap/status tests,
     `main_navigation_screen_test.dart`, and
     `production_shell_navigation_test.dart`
   - `64 passed, 0 failed`
4. Scoped Flutter analysis — exit `0`
   - device/runtime files plus `main_navigation_screen.dart`
   - `No issues found`
5. Debug APK build — exit `0`
   - artifact:
     `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-v0.1-complete-system\build\app\outputs\flutter-apk\app-debug.apk`
   - size: `203,361,288` bytes (approximately `193.94 MiB`)
   - SHA-256:
     `29f99929662d01bfc7f35d8b870956490fb60d398d2570cb7893c07e82472c75`

The build again emitted existing forward-compatibility warnings for Android
Gradle Plugin 8.9.1 and Kotlin 2.1.0. It exited `0`; upgrading those project
dependencies remains outside this bounded follow-up.

### Follow-up self-review and limitations

- Aggregate readiness, detailed drawer messaging, and local-learning
  availability now distinguish capability probing from inference readiness.
- Dart is the only schema authority; Kotlin is compared to it rather than to a
  second production key list.
- Unknown `ActivityManager` evidence is never represented as numeric zero.
- The strengthened contract checks exact transformations rather than only API
  name presence.
- No LiteRT/TensorFlow dependency, model, camera, hardware identifier, network
  call, sensitive log, or inference-execution claim was introduced.
- Physical-device validation remains pending, so this follow-up still makes no
  handset execution, delegate initialization, inference, camera, scanner, or
  speech-gate claim.

---

## Static MemoryInfo contract follow-up

The final static-contract review identified that API-name presence did not
prove `MemoryInfo` was populated or that `memoryClassMb` came from the Android
manager. This test-only follow-up adds exact, formatting-tolerant assertions for:

Follow-up commit: `bf61062` (`test: harden Android memory capability
contract`).

```text
ActivityManager.MemoryInfo().also(activityManager::getMemoryInfo)
"memoryClassMb" to activityManager.memoryClass
```

It also adds in-memory Kotlin fixtures proving that the contract rejects:

- `ActivityManager.MemoryInfo()` construction without
  `activityManager::getMemoryInfo`; and
- a hard-coded `"memoryClassMb" to 512` mapping.

RED:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/android-device-capability-contract.tests.ps1
exit 1
27 passed, 2 failed
```

Both negative-fixture checks failed before `Test-KotlinMemoryMappings` existed.
The first helper run remained at `27 passed, 2 failed`; a focused diagnostic
showed that Windows PowerShell interpreted a standalone `return` as an
immediate null return. Wrapping the boolean expression in `return (...)`
corrected the helper without changing production code.

GREEN:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/android-device-capability-contract.tests.ps1
exit 0
29 passed, 0 failed
```

`git diff --check` also exited `0`. No Flutter test, analysis, APK build, or
production file was rerun or changed because this follow-up modifies only the
PowerShell contract.
