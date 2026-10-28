# Prototype Architecture and Device Compute Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a truthful, machine-checked Prototype feature inventory and
an Android 10+ device-capability foundation whose executable policy remains on
CPU/XNNPACK until a later adapter owns real model and delegate evidence.

**Architecture:** A bounded repository contract records every visible feature
and prevents undocumented mock/simulation paths from entering production.
Provider-independent Dart capability models and policy consume a typed Android
API snapshot through one MethodChannel. Hardware/API capability and
caller-asserted benchmark metadata are advisory only: this phase has no model or
inference adapter, so production policy cannot select executable GPU inference.

**Tech Stack:** Flutter 3.44.7, Dart 3.12.2, Android SDK 29+, Kotlin,
PowerShell 5.1, Flutter MethodChannel, SharedPreferences.

## Global Constraints

- Android 10 / API 29 is the minimum supported Android version.
- Policy thresholds target the approved 4 GB RAM / 2 GB free-storage class;
  this phase does not claim that values from a physical handset were observed.
- Drift/SQLite remains the local source of truth; this foundation does not
  introduce a second data store.
- CPU is the fail-safe backend. GPU may be selected only when the device API
  probe says it is a candidate and a real model-specific GPU initialization
  and benchmark succeeds through future adapter-owned evidence. Because that
  adapter does not exist in this phase, current production decisions remain
  CPU/XNNPACK.
- OpenGL/Vulkan presence alone never means the GPU delegate is ready.
- Battery Saver, severe/critical thermal state, low-memory state, malformed
  native data, channel failure, or missing benchmark evidence produce CPU
  fallback or a truthful unavailable result.
- No hardware identifier, model name, benchmark sample, file path, exception
  text, email, token, image, audio, or key is logged or synchronized.
- Production feature debt is explicit in a versioned allowlist. New debt and
  stale allowlist entries fail the bounded contract; strict mode fails while
  any debt remains.
- Test fakes stay under `test/`; production code contains no mock provider.
- Do not add a TensorFlow/LiteRT package or claim real inference until a
  checksummed model and model-specific adapter are implemented in the later
  object-scanner work package.
- Use focused TDD during tasks and one consolidated section gate; do not run
  the full repository suite after every subheading.
- No branch name contains `codex`.
- Do not invoke Codex Security workflows.
- Stop on a repeated filesystem/tool failure as required by `AGENTS.md`.

---

### Task 1: Freeze the truthful Prototype feature contract

**Files:**

- Create: `docs/prototype/feature-inventory.md`
- Create: `tool/cli/prototype-production-paths.allowlist.json`
- Create: `tool/cli/tests/prototype-production-paths.tests.ps1`
- Modify: `README.md`

**Interfaces:**

- Consumes: tracked `lib/**/*.dart`, `lib/navigation/app_route.dart`,
  `lib/navigation/app_router.dart`, `lib/screens/main_navigation_screen.dart`,
  `lib/screens/choose_mode_screen.dart`, and the approved Real Local-First
  Prototype design.
- Produces: an inventory with one row per visible entry point and an exact
  `{path, rule}` production-debt allowlist consumed by the PowerShell contract.

- [ ] **Step 1: Write the inventory schema**

Create `docs/prototype/feature-inventory.md` with these required columns:

```text
Feature ID | Visible entry | Screen/route | Current data/device/provider
Offline behavior | Permission/configuration | Truthful unavailable state
Known blocker | Target phase | Evidence
```

The document must:

- enumerate all five primary destinations, drawer entries, settings entries,
  account routes, learning/practice entries, scanner/speech entries, economy,
  research/export, and hidden/disabled entries;
- distinguish typed routes from direct `MaterialPageRoute` construction;
- identify direct screen imports of Firebase, HTTP, speech, or other plugins;
- classify curated product content separately from fabricated user history;
- state `ready`, `degraded`, `blocked`, or `not exposed` without claiming that
  a menu label proves the feature works.

- [ ] **Step 2: Create the exact known-debt allowlist**

Create JSON with this shape:

```json
{
  "schemaVersion": 1,
  "entries": [
    {
      "path": "lib/screens/object_scanner_screen.dart",
      "rule": "simulated-device-result",
      "targetPhase": 3,
      "featureId": "device.object-scanner"
    }
  ]
}
```

Include only confirmed production blockers from the bounded scan. Do not
allowlist statistical terms such as `sampleStandardDeviation`, legitimate quiz
shuffling, test-only classes, or documented curated packs.

- [ ] **Step 3: Write the bounded production-path contract**

`tool/cli/tests/prototype-production-paths.tests.ps1` must:

1. obtain candidate paths from `git ls-files` under `lib/` only;
2. scan file contents for named rules covering sample user history, mock
   production provider, simulated device result, random fabricated
   measurement, placeholder transaction/feature, canned AI response, direct
   screen Firebase/HTTP access, and direct screen plugin access;
3. emit only relative path, rule, target phase, and counts—never matching
   source text;
4. compare exact `{path, rule}` pairs to the JSON allowlist;
5. fail on malformed JSON, duplicate entries, unknown rule names, missing
   files, new findings, or stale entries;
6. support `-Strict`, which also fails if any allowlisted debt remains;
7. derive the reachable screen set recursively from tracked relative/self-package
   imports and constructed destinations rooted in `app_router.dart`,
   `main_navigation_screen.dart`, `choose_mode_screen.dart`,
   `profile_settings_screen.dart`, and `setting_screen.dart`, then assert actual
   inventory table-row evidence names every derived screen;
8. include an in-memory negative fixture proving a newly reachable constructed
   destination without an inventory row fails.

- [ ] **Step 4: Verify the baseline contract**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1
```

Expected: exit `0`, no new/stale findings, and a non-zero explicit known-debt
count.

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1 -Strict
```

Expected: exit `1` only because the documented known-debt count is non-zero.

- [ ] **Step 5: Link the active inventory and commit**

Add `docs/prototype/feature-inventory.md` to README's Current prototype
direction block.

```powershell
git add -- README.md docs/prototype/feature-inventory.md tool/cli/prototype-production-paths.allowlist.json tool/cli/tests/prototype-production-paths.tests.ps1
git commit -m "docs: freeze the prototype feature contract"
```

---

### Task 2: Implement capability models and fail-safe inference policy

**Files:**

- Create: `lib/device/device_capability_models.dart`
- Create: `lib/device/inference_policy.dart`
- Create: `test/device/device_capability_models_test.dart`
- Create: `test/device/inference_policy_test.dart`

**Interfaces:**

- Produces:
  - `enum DevicePerformanceTier { lite, balanced, enhanced }`
  - `enum DeviceThermalState { nominal, fair, serious, critical, unknown }`
  - `enum InferenceBackend { xnnpackCpu, gpuDelegate }`
  - `enum AnalysisFrequency { low, standard, enhanced }`
  - `DeviceCapabilitySnapshot`
  - `InferenceBenchmark`
  - `InferenceDecision`
  - `InferencePolicy.select(...)`

- [ ] **Step 1: Write failing model-validation tests**

Cover:

- SDK must be at least 29 for a supported snapshot;
- ABI is normalized to one non-empty value;
- memory/storage values reject negatives;
- unknown native enum values map to `unknown`, never throw;
- `toString()` exposes only type/tier/backend/reason codes and never raw
  hardware values.

Run:

```powershell
flutter test test/device/device_capability_models_test.dart --reporter compact
```

Expected: RED because the device models do not exist.

- [ ] **Step 2: Implement immutable models**

`DeviceCapabilitySnapshot` contains:

```text
sdkInt, primaryAbi, memoryClassMb, availableMemoryMb, freeStorageBytes,
lowMemory, batterySaverEnabled, thermalState, gpuApiCandidate
```

`InferenceBenchmark` contains validated-shape, caller-asserted metadata:

```text
backend, successful, medianLatencyMicros, completedRuns, failureCode,
modelId, modelVersion, modelSha256, provenance
```

Only stable non-sensitive `failureCode` values are accepted:
`delegate-unavailable`, `delegate-init-failed`, `model-unsupported`,
`benchmark-failed`, and `benchmark-missing`.

- [ ] **Step 3: Write failing policy tests**

Prove these cases:

1. no GPU benchmark -> CPU;
2. GPU API candidate without successful delegate benchmark -> CPU;
3. caller-asserted GPU benchmark metadata on an otherwise qualifying candidate
   -> Balanced CPU with `gpu-adapter-unverified`;
4. GPU slower than CPU by more than 10 percent -> CPU;
5. Battery Saver -> Lite CPU;
6. serious/critical/unknown thermal state -> Lite CPU;
7. low-memory flag, available memory below 768 MB, or free storage below
   512 MB -> Lite CPU;
8. available memory 768–2047 MB -> Balanced CPU;
9. available memory at least 2048 MB, free storage at least 1 GB, and no
   safety constraint still remain CPU without adapter-owned evidence;
10. an unsuccessful CPU benchmark still returns CPU with a degraded reason,
    never GPU.

Run:

```powershell
flutter test test/device/inference_policy_test.dart --reporter compact
```

Expected: RED because the policy does not exist.

- [ ] **Step 4: Implement the deterministic policy**

`InferencePolicy.select` receives one snapshot, one CPU benchmark, and an
optional GPU benchmark. It returns exactly one tier, backend, closed
`AnalysisFrequency`, and stable reason code. It may evaluate advisory benchmark
shape and compatibility, but it has no production path to
`InferenceBackend.gpuDelegate` until an adapter-owned loaded-model evidence type
is implemented. `InferenceDecision` itself rejects a caller-selected GPU
backend by exposing only `InferenceDecision.cpu`, with no public backend
parameter or GPU factory. It does not inspect device brand/model names and
contains no randomness.

- [ ] **Step 5: Run focused GREEN and commit**

```powershell
flutter test test/device/device_capability_models_test.dart test/device/inference_policy_test.dart --reporter compact
dart format --set-exit-if-changed lib/device test/device
git add -- lib/device test/device
git commit -m "feat: add fail-safe device inference policy"
```

Expected: tests pass and formatter exits `0`.

---

### Task 3: Connect the Android-API-backed capability probe

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
- nullable snapshot plus separate capability-profile and inference runtime
  availability in
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

`AppBootstrap` invokes the injected probe once. A complete snapshot records
`deviceCapabilities: ready`, a partial snapshot records `degraded`, and a null
snapshot records `unavailable`. `onDeviceInference` remains `unavailable`
throughout this phase because no model or adapter exists. Firebase, local
learning, and account startup continue independently.

Add bootstrap and drawer tests for complete, partial, unavailable,
capability-ready/inference-unavailable, and exception-redaction paths.

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
- Android 10+ capability inputs are wired to real Android APIs and compile; no
  physical-handset values were observed in this phase;
- advisory backend evaluation is deterministic, and executable production
  selection remains CPU/XNNPACK with `gpu-adapter-unverified` when otherwise
  qualifying caller metadata is not adapter-authenticated;
- capability-profile readiness is distinct from on-device inference readiness,
  which remains unavailable in this phase;
- the debug APK compiles with the native capability plugin.

It may not yet claim:

- XNNPACK or GPU delegate executed a real model;
- camera object labeling is implemented;
- optional model download/activation is implemented;
- scanner/speech physical-device gates passed.

Those claims require the checksummed model, inference adapter, camera lifecycle,
and physical Android validation in the subsequent Device Feature work package.
