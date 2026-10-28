# Prototype Architecture + Device Compute Foundation final fix report

## Status

Implemented the complete final-review finding set in one bounded correction
wave. Production inference selection is CPU-only, capability probing is
separate from inference readiness, inventory reachability is source-derived,
privacy/error codes and analysis frequency are closed types, and the governing
plan/report language is limited to compilation and API wiring.

Committed as `b379668` (`fix: close device foundation review findings`) on
`release/v0.1-complete-system`.

No LiteRT/TensorFlow dependency, model, camera path, network path, hardware
identifier, sensitive logging, broad suppression, security workflow, or
physical-device execution was added or claimed.

## Root causes and fixes

### 1. Caller assertions could select executable GPU

Root cause: `InferencePolicy.select` treated public caller-asserted benchmark
identity/provenance as sufficient to construct an
`InferenceBackend.gpuDelegate` decision.

Fix:

- retained bounded advisory validation for candidate, benchmark success,
  provenance shape, exact model metadata match, and the latency threshold;
- removed the executable GPU return path;
- otherwise qualifying metadata now returns Balanced XNNPACK CPU with the
  stable reason `gpu-adapter-unverified`;
- removed the former qualified-GPU production reason;
- made `InferenceDecision` a final class exposing only
  `InferenceDecision.cpu`, with no public backend parameter, generic
  constructor, or GPU factory;
- retained a production-composition source contract that rejects direct
  production `InferenceDecision` GPU construction;
- left real adapter/model implementation to the later device-feature phase.

### 2. Capability probing and inference readiness were collapsed

Root cause: bootstrap mapped any non-null snapshot to a single
`deviceCompute: ready` value, even when required signals were null, and that
single status implied inference readiness.

Fix:

- replaced `deviceCompute` with independent `deviceCapabilities` and
  `onDeviceInference` statuses;
- null snapshot maps to capability `unavailable`;
- partial snapshot maps to capability `degraded`;
- complete required evidence maps to capability `ready`;
- on-device inference remains `unavailable` in production throughout this
  phase;
- `isFullyReady` requires cloud statuses, capabilities, and inference;
- `isCoreLearningAvailable` remains true;
- drawer copy distinguishes unavailable/degraded capabilities from unavailable
  on-device inference.

Runtime state matrix:

| Probe result | `deviceCapabilities` | `onDeviceInference` | `isFullyReady` in current production | Core learning |
| --- | --- | --- | --- | --- |
| null/unavailable | unavailable | unavailable | false | available |
| partial snapshot | degraded | unavailable | false | available |
| complete snapshot | ready | unavailable | false | available |

### 3. Reachability authority was a literal path list

Root cause: the inventory contract compared Markdown evidence against a
hand-maintained list of 43 paths, so navigation could drift without changing
the asserted authority.

Fix: the PowerShell contract now builds a bounded in-memory graph from tracked
Dart sources and these roots:

- `lib/navigation/app_router.dart`
- `lib/screens/main_navigation_screen.dart`
- `lib/screens/choose_mode_screen.dart`
- `lib/screens/profile_settings_screen.dart`
- `lib/screens/setting_screen.dart`

For each visited source it:

1. parses Dart imports;
2. resolves both relative imports and this application's
   `package:vocab_learning_app/` imports to repository-relative tracked paths;
3. considers only imported `lib/screens/*.dart` sources;
4. parses public classes declared by the imported screen file without assuming
   a particular widget base class;
5. adds an edge only when the current source constructs one of those classes;
6. recursively walks newly reached screens with ordinal de-duplication;
7. compares the derived set with paths parsed only from actual Markdown table
   row Evidence cells.

The current graph still derives 43 reachable screens. No exclusion list is
needed: hidden legacy/research/device screens remain absent because no
constructor edge from the bounded roots reaches them.

An in-memory negative fixture matrix uses `ConsumerWidget`, `HookWidget`, and
an arbitrary project-base destination. Each adds
`lib/screens/new_destination_screen.dart` as a constructed child while the
fixture inventory contains only its root row. The coverage helper must return
exactly `Inventory omits reachable screen:
lib/screens/new_destination_screen.dart`.

### 4. Probe unavailability accepted arbitrary strings

Root cause: `DeviceCapabilityUnavailable` exposed a public positional `String`
constructor and rendered that value.

Fix:

- added closed `DeviceCapabilityUnavailableCode`;
- exposed only four no-argument named constructors;
- kept the underlying constructor private;
- retained the stable string `code` getter for consumers;
- `toString()` renders only the enum-owned stable code;
- runtime test proves dynamically supplying an arbitrary sentinel to a named
  constructor tear-off fails and the sentinel cannot render.

### 5. Analysis frequency was free-form

Root cause: `InferenceDecision.analysisFrequency` accepted any `String`.

Fix: replaced it with
`AnalysisFrequency { low, standard, enhanced }` and updated all decisions,
tests, and call sites. A dynamic negative test proves arbitrary text is
rejected by the runtime type boundary.

## RED/GREEN evidence

### GPU closure and type safety

RED command:

```powershell
flutter test test/device/device_capability_models_test.dart test/device/inference_policy_test.dart test/device/production_inference_composition_contract_test.dart --reporter compact
```

Exit `1`: the compiler reported undefined `AnalysisFrequency`, and the static
composition test found the existing executable GPU decision.

GREEN:

```text
flutter test test/device --reporter compact
exit 0
42 passed, 0 failed
```

### Runtime split

RED command:

```powershell
flutter test test/runtime/app_runtime_status_test.dart test/runtime/app_bootstrap_test.dart test/screens/production_shell_navigation_test.dart --reporter compact
```

Exit `1`: the compiler reported the missing `deviceCapabilities` and
`onDeviceInference` API and the missing named unavailable constructor.

GREEN:

```text
same command
exit 0
28 passed, 0 failed
```

### Closed unavailable error

RED command:

```powershell
flutter test test/device/device_capability_probe_test.dart --reporter compact
```

Exit `1`: the compiler reported that
`DeviceCapabilityUnavailable.channelUnavailable` did not exist.

The test passed within the 42-test device GREEN after named constructors and
the closed enum were implemented.

### Source-derived inventory

RED command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1
```

Exit `1`: `Get-SourceDerivedReachableScreenPaths` was not defined.

GREEN:

```text
exit 0
candidateFiles=199
knownDebt=18
matches=29
new=0
stale=0
source-derived reachable screens=43
```

## Exact claim-boundary edits

- Plan goal now says executable selection remains CPU/XNNPACK until a future
  adapter owns real model/delegate evidence.
- Caller benchmark identity and provenance are described as advisory asserted
  metadata, not proof of execution or loaded-model SHA.
- Plan policy cases now close the otherwise qualifying branch with
  `gpu-adapter-unverified`.
- Runtime plan language distinguishes capability profile readiness from
  inference readiness.
- Android acceptance says the plugin is wired to real Android APIs and
  compiles; it does not say physical handset values were observed.
- Task reports were corrected to remove the obsolete executable-GPU claim,
  describe source-derived reachability, and record the runtime split.
- No physical Android device was connected. No XNNPACK/GPU execution, model
  load, delegate initialization, scanner result, camera lifecycle, or speech
  device gate was observed.

## Final consolidated gate

1. Prototype production-path contract: exit `0`
   - `candidateFiles=199`
   - `knownDebt=18`
   - `matches=29`
   - `new=0`
   - `stale=0`
2. Android capability contract: exit `0`
   - `29 passed, 0 failed`
3. Device/runtime/status/navigation Flutter tests: exit `0`
   - `71 passed, 0 failed`
4. Scoped Flutter analysis: exit `0`
   - `No issues found`
5. Debug APK build: exit `0`
   - path:
     `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-v0.1-complete-system\build\app\outputs\flutter-apk\app-debug.apk`
   - size: `203,362,667` bytes (`193.94 MiB`)
   - SHA-256:
     `cd344d6729d7617f5e9ead88ef8dfeb6c9878114f0445c85f341eeb7d385fadf`

Build command:

```powershell
flutter build apk --debug --dart-define=LEXIQUEST_VERSION=0.1.0+1 --dart-define=LEXIQUEST_BUILD_ID=device-compute-foundation
```

The build emitted the existing future-support warnings for Android Gradle
Plugin 8.9.1 and Kotlin 2.1.0. These dependency upgrades are outside this
bounded correction.

## Files changed

Tracked implementation/contract files:

- `docs/superpowers/plans/2026-07-30-prototype-architecture-device-compute-foundation.md`
- `lib/device/device_capability_models.dart`
- `lib/device/device_capability_probe.dart`
- `lib/device/inference_policy.dart`
- `lib/runtime/app_bootstrap.dart`
- `lib/runtime/app_runtime_status.dart`
- `lib/screens/main_navigation_screen.dart`
- `test/device/device_capability_models_test.dart`
- `test/device/device_capability_probe_test.dart`
- `test/device/inference_policy_test.dart`
- `test/device/production_inference_composition_contract_test.dart`
- `test/runtime/app_bootstrap_test.dart`
- `test/runtime/app_runtime_status_test.dart`
- `test/screens/production_shell_navigation_test.dart`
- `tool/cli/tests/prototype-production-paths.tests.ps1`

Worktree-local SDD reports updated/written:

- `.superpowers/sdd/prototype-contract-task-1-report.md`
- `.superpowers/sdd/device-policy-task-2-report.md`
- `.superpowers/sdd/android-capability-task-3-report.md`
- `.superpowers/sdd/prototype-device-final-fix-report.md`

## Self-review

- Confirmed there is no remaining `deviceCompute` identifier in tracked code,
  tests, or the governing plan.
- Confirmed the obsolete qualified-GPU reason is absent from the corrected
  implementation, tests, plan, and task reports.
- Confirmed every production `InferenceDecision` backend remains XNNPACK CPU.
- Confirmed the only public decision factory is `InferenceDecision.cpu`, it has
  no backend parameter, and only the private generative constructor can create
  a decision.
- Confirmed the probe preserves nullable capability values and bootstrap uses
  `hasRequiredPolicyEvidence` without inventing defaults.
- Confirmed unavailable exceptions retain no native exception object, message,
  stack, details, or arbitrary caller text.
- Confirmed the reachability walker reads tracked `lib/` Dart sources only and
  does not enumerate build output or caches.
- Confirmed the current 43-screen parity comes from source traversal, not a
  literal path baseline.
- Confirmed the navigation fixture detects constructed `ConsumerWidget`,
  `HookWidget`, and arbitrary project-base destinations, so traversal is not
  coupled to widget inheritance.
- Confirmed no unrelated production behavior was changed.
- `git diff --check` exited `0`.

## Concerns

- `InferenceBenchmark` remains an advisory caller-asserted shape. It must not be
  reused as adapter authenticity evidence in a future phase.
- GPU execution must remain closed until a future adapter-owned result is
  coupled to actual model loading, SHA-256 verification, delegate
  initialization, and bounded benchmark completion.
- APK size and hash are build-artifact metadata only. The build is compilation
  evidence, not physical-device or inference evidence.
- Existing AGP/Kotlin future-support warnings remain for later dependency
  maintenance.

## Bounded independent review remediation

An independent read-only diff review reported 0 Critical findings, 1 Important
finding, and 1 Minor finding before commit:

- Important: the literal static regex could be evaded by aliasing
  `InferenceBackend.gpuDelegate`.
- Minor: the graph recognized only direct `StatefulWidget`/`StatelessWidget`
  subclasses.

Both were reproduced RED. The decision API now exposes only a CPU factory with
no backend parameter or GPU factory. The inventory fixture matrix now covers
`ConsumerWidget`, `HookWidget`, and an arbitrary project base while the walker
recognizes constructed public classes declared by tracked screen files. Focused
GREEN passed before the final consolidated gate was rerun.

The final API-contract RED reported that `InferenceDecision.cpu` did not exist.
After replacing the generic factory and updating policy composition, the
focused decision/model/policy set passed 34 tests. The definitive consolidated
gate then passed 71 tests and rebuilt the APK metadata recorded above.
