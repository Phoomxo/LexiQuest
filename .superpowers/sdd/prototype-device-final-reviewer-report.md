# Final whole-scope review: Prototype Architecture + Device Compute Foundation

## Re-review verdict — head `b379668`

**Ready to continue to the next Prototype phase: Yes**

Re-review finding count:

- Critical: 0
- Important: 0
- Minor: 0

All three Important and both Minor findings from the original review are closed.
The correction keeps executable inference decisions CPU-only, separates device
capability-profile readiness from unavailable on-device inference, derives
reachable screens from a bounded source graph, closes error/frequency types, and
narrows plan/UI/report claims to the evidence actually obtained.

No replacement blocker or cross-task regression was identified.

## Original verdict — head `bf61062` (superseded)

**Ready to continue to the next Prototype phase: With fixes**

Original finding count:

- Critical: 0
- Important: 3
- Minor: 2

## Important findings

### I1. GPU qualification is caller-asserted, not evidence of real delegate initialization

The plan's global rule says GPU may be selected only after real delegate
initialization and benchmark evidence
(`docs/superpowers/plans/2026-07-30-prototype-architecture-device-compute-foundation.md:26-29`).
The plan architecture similarly says the policy cannot select GPU until an
inference adapter supplies the evidence, and the acceptance boundary claims
deterministic backend selection
(`docs/superpowers/plans/2026-07-30-prototype-architecture-device-compute-foundation.md:373-380`).

The implemented evidence object explicitly says provenance is caller-asserted
and cannot prove that a backend ran or a model was loaded
(`lib/device/device_capability_models.dart:37-38`,
`lib/device/device_capability_models.dart:136-142`). Its public factory allows
any caller to construct the sole provenance enum value
(`lib/device/device_capability_models.dart:143-154`). The policy then returns
`InferenceBackend.gpuDelegate` when two such caller-created values agree
(`lib/device/inference_policy.dart:62-85`). The positive policy test constructs
both benchmarks directly and obtains Enhanced GPU without an adapter
(`test/device/inference_policy_test.dart:28-71`,
`test/device/inference_policy_test.dart:96-103`).

The Task 2 report correctly withdraws its earlier authenticity claim, but that
correction exposes a plan/implementation contradiction rather than closing the
plan requirement. No current runtime invokes this policy, so this is not a
present hardware-execution or privacy defect. It is nevertheless an
architecture blocker: a future production caller could obtain a GPU decision
without proving delegate initialization or the SHA-256 of the actually loaded
model.

Required resolution:

- Prefer an adapter-owned evidence/result type whose successful construction is
  coupled to delegate initialization, bounded benchmark completion, and the
  SHA-256 of the loaded model. Production composition, not a caller-supplied
  enum, must establish authenticity.
- Until that type exists, either keep the production backend decision on CPU or
  name the current result as advisory/shape-qualified rather than
  `gpu-benchmark-qualified`.
- Add a composition-level test proving arbitrary model-layer callers cannot
  produce a production GPU selection.

### I2. Runtime/UI report partial capability snapshots as fully ready

The snapshot model explicitly permits five policy-critical signals to be null
and exposes `hasRequiredPolicyEvidence` to distinguish complete from incomplete
evidence (`lib/device/device_capability_models.dart:116-130`). The channel test
proves that a snapshot with every one of those values null is accepted and has
`hasRequiredPolicyEvidence == false`
(`test/device/device_capability_probe_test.dart:61-88`). The Android probe can
also emit a null Battery Saver value when `PowerManager` is unavailable
(`android/app/src/main/kotlin/com/lexiquest/app/DeviceCapabilityPlugin.kt:55-56`,
`android/app/src/main/kotlin/com/lexiquest/app/DeviceCapabilityPlugin.kt:69-70`).

Bootstrap ignores evidence completeness and marks device compute ready whenever
the snapshot object is non-null (`lib/runtime/app_bootstrap.dart:225-235`).
`isFullyReady` then treats that flag as sufficient
(`lib/runtime/app_runtime_status.dart:14-17`), and the drawer emits the
all-systems-ready message (`lib/screens/main_navigation_screen.dart:40-55`).
The tests cover a complete snapshot and a missing snapshot, but not a partial
snapshot (`test/runtime/app_bootstrap_test.dart:209-266`). The runtime enum
already has a `degraded` state, but this integration never uses it for device
compute.

This conflicts with the plan's requirement for truthful runtime availability
(`docs/superpowers/plans/2026-07-30-prototype-architecture-device-compute-foundation.md:338-345`)
and is especially misleading because the current phase has no model or
inference adapter. A successful capability API probe is not the same as
on-device inference readiness.

Required resolution:

- Map null snapshot to `unavailable`, incomplete snapshot to `degraded`, and
  complete capability evidence to capability-profile `ready`.
- Do not label the latter as inference/device-compute readiness. Expose a
  separate inference-adapter/model status that remains unavailable until the
  later work package.
- Add bootstrap and drawer tests for a partial snapshot and for the
  capability-ready/inference-unavailable state.

### I3. The inventory contract cannot detect newly reachable screens

The plan requires the contract to assert that the inventory names every
production screen reachable from current menu surfaces
(`docs/superpowers/plans/2026-07-30-prototype-architecture-device-compute-foundation.md:121-127`).
The implementation does validate the current 43-path baseline, but it obtains
that baseline from a literal array inside the test
(`tool/cli/tests/prototype-production-paths.tests.ps1:393-437`) and compares the
inventory only to that same array
(`tool/cli/tests/prototype-production-paths.tests.ps1:439-460`).

Nothing compares the literal array against
`lib/navigation/app_route.dart`, `lib/navigation/app_router.dart`,
`lib/screens/main_navigation_screen.dart`, `lib/screens/choose_mode_screen.dart`,
or their bounded navigation children. A new visible route or menu destination
can therefore be added without changing the inventory or this list, and the
contract will still pass unless the new file happens to match a debt regex.
That leaves the README claim that the inventory covers every current entry
point stronger than the machine check supporting it (`README.md:15-18`).

The current inventory appears internally consistent and truthfully records 63
rows, 43 reachable screen paths, and 18 exact debt pairs
(`docs/prototype/feature-inventory.md:18-25`). The defect is drift protection,
not an identified missing row in the present baseline.

Required resolution:

- Derive the bounded reachable screen set from the approved route/menu source
  graph, or add a source-derived parity check that fails when the manual
  manifest diverges from constructed/imported navigation destinations.
- Include a negative fixture proving that adding a new reachable destination
  without an inventory row fails.

## Minor findings

### M1. `DeviceCapabilityUnavailable` accepts and renders arbitrary caller text

The production probe itself maps failures to four fixed codes
(`lib/device/device_capability_probe.dart:31-56`), but the public exception
constructor accepts any string and `toString()` interpolates it
(`lib/device/device_capability_probe.dart:115-121`). A later caller can therefore
construct `DeviceCapabilityUnavailable(nativeException.toString())` and leak
that value if the exception is rendered. Current bootstrap catches and discards
all probe errors (`lib/runtime/app_bootstrap.dart:288-293`), so no leak is
present in the reviewed production path.

Use a closed enum or private named constructors for the four stable codes, and
add a test proving arbitrary text cannot enter the rendered exception.

### M2. Analysis frequency is an unconstrained public string

The plan specifies exactly `low`, `standard`, or `enhanced`, but
`InferenceDecision` exposes a public constructor with a free-form
`String analysisFrequency`
(`lib/device/device_capability_models.dart:250-262`). The policy currently emits
only the three intended values (`lib/device/inference_policy.dart:80-106`), so
this is not a current policy bug. A closed enum would preserve the architecture
if other callers construct decisions later.

## Cross-task integration assessment

### Truthful inventory and debt baseline

Pass for the current manually reviewed baseline, subject to I3. The inventory
clearly separates ready, degraded, blocked, and not-exposed states
(`docs/prototype/feature-inventory.md:7-16`), separates curated product content
from fabricated user history (`docs/prototype/feature-inventory.md:27-33`), and
names the known scanner, speech, AI, progress, economy, and direct-provider debt.
The allowlist contains 18 exact `{path, rule}` pairs and no wildcard suppression
(`tool/cli/prototype-production-paths.allowlist.json:1-113`). Contract output is
limited to path, rule, target phase, and counts, not matching source text
(`tool/cli/tests/prototype-production-paths.tests.ps1:485-508`).

### Dart/Android schema alignment

Pass. Dart declares nine exact keys
(`lib/device/device_capability_probe.dart:14-28`), validates the exact map size,
keys, and types (`lib/device/device_capability_probe.dart:60-109`), and Kotlin
returns the same nine fields
(`android/app/src/main/kotlin/com/lexiquest/app/DeviceCapabilityPlugin.kt:60-74`).
The Android contract derives Dart keys and independently parses Kotlin keys
before exact parity comparison
(`tool/cli/tests/android-device-capability-contract.tests.ps1:21-83`,
`tool/cli/tests/android-device-capability-contract.tests.ps1:238-241`).

### CPU fail-safe and GPU evidence rules

CPU fallback branch ordering and thresholds are coherent: missing capability
evidence, bad CPU evidence, unsupported SDK, Battery Saver, thermal pressure,
low memory, low available memory, and low storage all return CPU
(`lib/device/inference_policy.dart:21-50`). Missing, failed, mismatched, or slow
GPU evidence also returns CPU (`lib/device/inference_policy.dart:52-78`).
Boundary coverage includes missing signals, 10%, 2047 MiB, 512 MiB, and 1 GiB
edges (`test/device/inference_policy_test.dart:105-128`,
`test/device/inference_policy_test.dart:181-301`). Authenticity remains
insufficient as described in I1.

### Runtime status and UI

Failure/degraded cloud paths remain independent, local learning remains
available, and probe exceptions are discarded rather than rendered
(`lib/runtime/app_bootstrap.dart:205-248`,
`lib/runtime/app_bootstrap.dart:288-293`). The UI explicitly names unavailable
on-device compute and does not claim full readiness in that case
(`lib/screens/main_navigation_screen.dart:45-55`). Partial-evidence and
capability-vs-inference semantics remain incorrect as described in I2.

### Claim boundary

Pass in code comments and task-report wording, subject to I1/I2 naming. No
TensorFlow/LiteRT dependency, model, camera lifecycle, model download, or real
inference path appears in this diff. The model and policy explicitly state that
they cannot prove hardware execution or loaded-model identity
(`lib/device/device_capability_models.dart:136-142`,
`lib/device/inference_policy.dart:3-7`). The Android report also records that no
physical device was used and limits the APK claim to compilation. Therefore no
observed source claims camera labeling, delegate execution, or physical-device
validation.

### Privacy and suppression review

Pass for current production flow. The native plugin reads no model,
manufacturer, Android ID, serial, or network API, and contains no logging call;
the static checks enforce those exclusions
(`tool/cli/tests/android-device-capability-contract.tests.ps1:242-249`).
Native failures expose only a stable code with null message/details
(`android/app/src/main/kotlin/com/lexiquest/app/DeviceCapabilityPlugin.kt:36-46`).
Snapshot, benchmark, decision, dependencies, and runtime status string
representations omit hardware and benchmark values
(`lib/device/device_capability_models.dart:132-133`,
`lib/device/device_capability_models.dart:245-247`,
`lib/device/device_capability_models.dart:266-269`,
`lib/runtime/app_dependencies.dart:49-50`,
`lib/runtime/app_runtime_status.dart:21-22`). M1 is a future-proofing gap in the
exception API, not an observed leak.

### Android API 29, Kotlin lifecycle, and build configuration

Pass. `minSdk = 29` is explicit
(`android/app/build.gradle.kts:31-37`). The plugin attaches and detaches its
handler/context correctly
(`android/app/src/main/kotlin/com/lexiquest/app/DeviceCapabilityPlugin.kt:13-28`),
returns synchronously, and redacts failures. `MainActivity` calls `super` and
registers one plugin
(`android/app/src/main/kotlin/com/lexiquest/app/MainActivity.kt:6-10`).
MemoryInfo is populated through `getMemoryInfo`, memory class comes from
`ActivityManager`, available memory is converted to whole MiB, and storage
remains bytes
(`android/app/src/main/kotlin/com/lexiquest/app/DeviceCapabilityPlugin.kt:49-67`).
The reported debug APK build is valid compilation evidence only.

### Tests and contracts

The Dart tests meaningfully cover parsing, redaction, policy thresholds,
metadata mismatch, and fallback behavior. The Android static contract has
useful negative fixtures for key mismatch and incorrect memory mappings
(`tool/cli/tests/android-device-capability-contract.tests.ps1:111-171`). The
remaining test gaps are the adapter-authenticity boundary (I1), partial runtime
status (I2), and source-derived navigation drift (I3).

### Scope isolation

Pass. The combined diff changes only the inventory/contract, device models and
policy, Android probe/build wiring, directly affected runtime/UI status, and
their tests. Safe Cleanup and earlier account implementations are not changed.
The narrow `android/.gitignore` cache entry is build-related and does not expand
production behavior.

## Plan/design contradictions and clarifications

1. **Plan vs implementation — GPU authenticity:** the plan requires real
   delegate initialization before GPU selection, while the implementation and
   final Task 2 report explicitly limit provenance to caller assertion. This is
   I1 and must be resolved in code or by narrowing the plan claim.
2. **Plan wording vs runtime meaning:** the plan calls the snapshot outcome
   “device compute” availability, but the phase expressly has no inference
   adapter or model. The UI/runtime should name capability-profile availability
   and reserve compute/inference readiness for the later adapter phase.
3. **Design target vs current phase:** the design requires typed routes and real
   connected behavior for every included feature
   (`docs/superpowers/specs/2026-07-30-real-local-first-prototype-design.md:36-55`,
   `docs/superpowers/specs/2026-07-30-real-local-first-prototype-design.md:228-237`).
   The inventory truthfully records numerous direct routes and blocked/degraded
   features, so this foundation is not the completed prototype. This is an
   expected phase boundary, not a defect, provided no broader prototype-ready
   claim is made.
4. **Acceptance wording vs physical evidence:** the plan says capability inputs
   “come from the real phone”
   (`docs/superpowers/plans/2026-07-30-prototype-architecture-device-compute-foundation.md:373-380`),
   while the Task 3 report records that no physical phone was used. The code
   does use real Android APIs, but the defensible claim is that the adapter is
   wired to those APIs and compiles—not that handset values were observed.

## Verification disposition

I did not rerun the freshly reported consolidated section gate. The findings
above are visible contract/semantic issues that another successful run of the
same gate would not resolve. I performed read-only source/diff inspection,
confirmed the reviewed commit range is `45e8312..bf61062`, inspected all 22
changed paths, and ran `git diff --check 45e8312 bf61062`, which exited 0. No
security workflow, repository-wide scan, build/cache enumeration, or production
source modification was performed.

---

## Final fix-wave re-review — `bf61062..b379668`

This section supersedes the original blocking verdict above while retaining the
original findings as the historical review record.

### Closure matrix

#### I1 — Closed: executable GPU construction is unavailable

`InferenceDecision` is now `final`; its only public factory is
`InferenceDecision.cpu`, which accepts no backend parameter and hard-codes
`InferenceBackend.xnnpackCpu`
(`lib/device/device_capability_models.dart:252-274`). The only generative
constructor is library-private
(`lib/device/device_capability_models.dart:265-270`). Consequently, a caller
alias or helper can only invoke the CPU factory; it cannot pass, mutate, or
otherwise construct a GPU decision before an adapter-owned API is introduced.

The policy's otherwise qualifying advisory GPU branch now returns Balanced CPU
with `gpu-adapter-unverified`
(`lib/device/inference_policy.dart:63-81`), and both Lite and Balanced helpers
use the CPU-only factory (`lib/device/inference_policy.dart:89-101`). Focused
policy coverage verifies the qualifying metadata case remains Balanced CPU
(`test/device/inference_policy_test.dart:96-105`,
`test/device/inference_policy_test.dart:296-305`).

The composition contract checks the public factory shape and absence of another
decision factory (`test/device/production_inference_composition_contract_test.dart:7-37`).
Its source scan is supplementary; the private constructor, final fields, final
class, and CPU-only factory provide the executable language-level boundary.

The governing plan now accurately describes caller benchmarks as advisory,
keeps current decisions on CPU, and defers GPU to future adapter-owned
loaded-model evidence
(`docs/superpowers/plans/2026-07-30-prototype-architecture-device-compute-foundation.md:5-14`,
`docs/superpowers/plans/2026-07-30-prototype-architecture-device-compute-foundation.md:254-264`).

#### I2 — Closed: capabilities and inference readiness are independent

`AppRuntimeStatus` now has separate `deviceCapabilities` and
`onDeviceInference` fields, and aggregate readiness requires both
(`lib/runtime/app_runtime_status.dart:3-20`). Bootstrap maps:

- no snapshot to capability `unavailable`;
- incomplete required evidence to `degraded`;
- complete required evidence to `ready`;
- on-device inference to `unavailable` in every current production branch.

The mapping is explicit at `lib/runtime/app_bootstrap.dart:225-239`.
Tests cover complete, partial, absent, and exception paths while keeping
inference unavailable
(`test/runtime/app_bootstrap_test.dart:221-350`). Runtime-status tests prove
capability readiness alone cannot imply inference readiness
(`test/runtime/app_runtime_status_test.dart:22-43`).

Drawer copy separately names unavailable/degraded device capabilities and
unavailable on-device inference
(`lib/screens/main_navigation_screen.dart:40-59`), with UI tests for both
capability-ready/inference-unavailable and degraded-capability states
(`test/screens/production_shell_navigation_test.dart:212-247`). Current
production has no constructor that sets `onDeviceInference` ready:
`AppBootstrap` is the only production composition of `AppRuntimeStatus`.

The plan now states the same state matrix and limits the APK result to
compilation/API wiring rather than physical-device or inference evidence
(`docs/superpowers/plans/2026-07-30-prototype-architecture-device-compute-foundation.md:354-378`,
`docs/superpowers/plans/2026-07-30-prototype-architecture-device-compute-foundation.md:389-413`).

#### I3 — Closed: reachable inventory coverage is source-derived

The literal 43-screen authority is removed. The contract loads tracked
`lib/**/*.dart` sources from `git ls-files`
(`tool/cli/tests/prototype-production-paths.tests.ps1:411-435`) and walks a
bounded graph from the approved navigation/menu roots
(`tool/cli/tests/prototype-production-paths.tests.ps1:560-573`).

For each edge, it resolves relative and application-package imports, restricts
targets to tracked `lib/screens/*.dart`, parses any public class declared in
the imported screen file, and follows it only when the current source
constructs that class
(`tool/cli/tests/prototype-production-paths.tests.ps1:112-223`). This avoids a
`StatefulWidget`/`StatelessWidget` inheritance assumption and leaves no manual
reachable-screen or exclusion list as authority. The bounded roots define the
contract surface; descendants come from source.

Negative fixtures add a missing constructed destination using
`ConsumerWidget`, `HookWidget`, and an arbitrary project base class, and require
the exact missing-screen failure
(`tool/cli/tests/prototype-production-paths.tests.ps1:508-558`). Real inventory
coverage then compares table-row evidence against the derived graph
(`tool/cli/tests/prototype-production-paths.tests.ps1:575-599`).

#### M1 — Closed: unavailable codes are a closed type

`DeviceCapabilityUnavailableCode` owns the four stable strings, the exception
offers only four no-argument named constructors, and its underlying constructor
is private (`lib/device/device_capability_probe.dart:115-146`). The dynamic
negative test proves arbitrary caller text cannot be supplied or rendered
(`test/device/device_capability_probe_test.dart:201-214`).

#### M2 — Closed: analysis frequency is a closed type

`AnalysisFrequency` is now the enum `low`, `standard`, and `enhanced`
(`lib/device/device_capability_models.dart:35-40`), and
`InferenceDecision.analysisFrequency` uses that enum
(`lib/device/device_capability_models.dart:252-275`). Policy branches return
only enum members (`lib/device/inference_policy.dart:89-101`), and the dynamic
negative test rejects arbitrary caller text
(`test/device/device_capability_models_test.dart:266-277`).

### Cross-task regression and claim review

- The fix wave changes only the governing section plan, device model/policy,
  probe error API, runtime status/bootstrap, status UI, inventory contract, and
  directly associated tests. Android/Kotlin production code, feature debt,
  account work, and Safe Cleanup remain unchanged.
- No production path now constructs a GPU `InferenceDecision`; GPU benchmark
  objects remain explicitly advisory and cannot become executable decisions.
- No TensorFlow/LiteRT dependency, model, camera path, physical-device result,
  hardware identifier, sensitive logging, network path, matched source-text
  output, wildcard allowlist, or broad suppression was added.
- The updated plan and fix/task reports consistently state that no physical
  handset values, loaded model, XNNPACK/GPU execution, delegate initialization,
  camera lifecycle, scanner result, or speech device gate were observed.
- The original Dart/Kotlin nine-key schema, Android API 29 lifecycle, memory
  mappings, native redaction, and exact 18-pair debt baseline are unaffected by
  the fix wave.

### Re-review verification disposition

The reported final correction gate already covers the changed device,
runtime/status/navigation, inventory-contract, analysis, and APK-build surfaces:
71 focused tests passed, both PowerShell contracts passed, scoped analysis found
no issues, and the debug APK compiled. No concrete uncovered diff risk required
rerunning any gate command.

This re-review used read-only source and diff inspection for
`45e8312..b379668`; `git diff --check 45e8312 b379668` exited 0. No security
workflow, repository-wide scan, build/cache enumeration, or production source
modification was performed. The only write was this requested reviewer-report
update.

### Final re-review verdict

**Ready to continue to the next Prototype phase: Yes**

Final finding count:

- Critical: 0
- Important: 0
- Minor: 0
