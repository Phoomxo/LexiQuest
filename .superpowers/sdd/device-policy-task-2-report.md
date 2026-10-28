# Task 2 — Device Capability Models and Fail-Safe Inference Policy

## Result

Implemented the requested pure-Dart immutable capability models and deterministic
inference policy. The policy does not initialize LiteRT, claim hardware
execution, inspect device brand/model values, log hardware identifiers, or use
randomness.

## TDD evidence

### RED — models

Ran:

```powershell
flutter test test/device/device_capability_models_test.dart --reporter compact
```

The test failed as expected because
`lib/device/device_capability_models.dart` did not exist. The compiler reported
the missing import and the undefined model symbols.

### GREEN — models

After the minimal immutable model implementation, the same command passed all
6 model tests.

### RED — policy

Ran:

```powershell
flutter test test/device/inference_policy_test.dart --reporter compact
```

The test failed as expected because `lib/device/inference_policy.dart` did not
exist. The compiler reported the missing import and undefined `InferencePolicy`.

### GREEN — focused suite

Ran:

```powershell
flutter test test/device/device_capability_models_test.dart test/device/inference_policy_test.dart --reporter compact
dart format --set-exit-if-changed lib/device test/device
git diff --check
```

All 16 focused tests passed, formatting exited 0 after formatting, and the diff
check was clean.

## Policy thresholds and decision ordering

The policy evaluates capability and caller-asserted benchmark metadata in this
exact order while keeping executable selection on CPU/XNNPACK:

1. Missing/unsuccessful/non-CPU CPU benchmark: Lite CPU, `cpu-benchmark-degraded`.
2. SDK below 29: Lite CPU, `sdk-unsupported`.
3. Battery Saver: Lite CPU, `battery-saver`.
4. Thermal `serious`, `critical`, or `unknown`: Lite CPU, `thermal-constrained`.
5. Low-memory flag: Lite CPU, `low-memory`.
6. Available memory below 768 MB: Lite CPU, `available-memory-constrained`.
7. Free storage below 512 MiB: Lite CPU, `storage-constrained`.
8. Available memory from 768 through 2047 MB: Balanced CPU, `balanced-memory`.
9. Free storage from 512 MiB through less than 1 GiB: Balanced CPU,
   `storage-not-enhanced`.
10. No GPU API candidate: Balanced CPU, `gpu-not-candidate`.
11. Missing GPU benchmark: Balanced CPU, `gpu-benchmark-missing`.
12. Unsuccessful/wrong-backend GPU benchmark: Balanced CPU,
    `gpu-benchmark-failed`.
13. GPU median latency more than 10% over CPU: Balanced CPU,
    `gpu-slower-than-cpu`.
14. Otherwise: Balanced CPU with `gpu-adapter-unverified`.

The GPU comparison is integer-only: `gpuLatency * 10 <= cpuLatency * 11` is
required, so exactly 10% slower passes the advisory comparison and any greater
latency is rejected. Analysis frequency is the closed `AnalysisFrequency` enum;
current decisions use `low` for Lite and `standard` for Balanced.

## Files changed

- `lib/device/device_capability_models.dart`
- `lib/device/inference_policy.dart`
- `test/device/device_capability_models_test.dart`
- `test/device/inference_policy_test.dart`

## Self-review

- Models are immutable and normalize/validate input before construction.
- Native thermal values outside the known mapping return `unknown` without
  throwing.
- Benchmark failures accept only the five specified stable failure codes.
- `toString()` output never includes ABI, memory, storage, benchmark latency,
  or run-count values.
- GPU selection is closed in this phase. Candidate and benchmark fields are
  advisory inputs only until a later adapter owns loaded-model evidence.

## Concerns

None for this bounded pure-Dart task. Benchmark creation and platform signal
collection remain intentionally outside this policy layer.

---

## Reviewer-finding remediation

### Added RED/GREEN evidence

**Model hardening RED:** extended model tests first, then ran:

```powershell
flutter test test/device/device_capability_models_test.dart --reporter compact
```

This failed as expected because the capability fields were not nullable and
the model identity, provenance enum, decision-reason enum, and bounded
benchmark API did not exist. The compiler reported the missing parameters and
types.

**Model hardening GREEN:** after the minimal model changes, the same suite
passed 11 tests.

**Policy hardening RED:** extended policy tests first, then ran:

```powershell
flutter test test/device/inference_policy_test.dart --reporter compact
```

This failed as expected because the existing policy treated nullable signals as
ready values and still constructed decisions from raw strings. It could not
compile against the hardened model API.

**Semantic-version RED:** added a malformed-version assertion and reran the
model suite. It failed because `not a semantic version` was accepted.

**Final GREEN:**

```powershell
flutter test test/device/device_capability_models_test.dart test/device/inference_policy_test.dart --reporter compact
dart format --set-exit-if-changed lib/device test/device
git diff --check
```

All 28 focused tests passed; the formatter and diff check exited 0.

### Hardened evidence and safety rules

- Each benchmark carries normalized `modelId`, semantic `modelVersion`, and
  lowercase 64-hex `modelSha256`, plus nullable
  `InferenceBenchmarkProvenance`.
- Advisory GPU shape qualification requires successful CPU/XNNPACK and
  GPU-delegate benchmark metadata with matching model ID, version, and SHA-256.
  These fields remain caller assertions and cannot authenticate execution.
- The pure policy enforces metadata consistency only. No production inference
  adapter exists in this phase, so executable GPU selection remains closed.
- Battery Saver, low-memory, available-memory, free-storage, and GPU-candidate
  evidence are nullable. Any unavailable one returns Lite CPU with
  `capability-evidence-missing`; no unavailable signal is defaulted to false,
  zero, or ready.
- Decision reasons are the closed `InferenceDecisionReason` enum. The public
  `reasonCode` is derived from that enum, and `toString()` cannot interpolate
  caller-supplied reason text.
- Benchmark values are limited to 60,000,000 microseconds and 10,000 completed
  runs. The 10% comparison evaluates `(gpu - cpu) * 10 > cpu`; supplied bounds
  cap the product below 600,000,000, avoiding overflow-prone unbounded math.

### Revised decision ordering

1. Any required capability signal unavailable: Lite CPU,
   `capability-evidence-missing`.
2. Missing/failed/wrong-backend CPU benchmark: Lite CPU,
   `cpu-benchmark-degraded`.
3. Unsupported SDK, Battery Saver, constrained thermal state, low-memory,
   available memory below 768 MB, or storage below 512 MiB: the corresponding
   Lite CPU reason.
4. Available memory below 2048 MB or storage below 1 GiB: Balanced CPU.
5. Missing/non-candidate/failed GPU evidence: Balanced CPU.
6. Missing adapter provenance: Balanced CPU,
   `gpu-evidence-provenance-missing`.
7. CPU/GPU model ID, version, or SHA mismatch: Balanced CPU,
   `gpu-evidence-mismatch`.
8. GPU latency greater than CPU by more than 10%: Balanced CPU,
   `gpu-slower-than-cpu`.
9. Otherwise qualifying caller metadata produces Balanced CPU with
   `gpu-adapter-unverified`.

### Additional focused coverage

- All known native thermal mappings plus unknown mappings.
- Missing signal fallback for each required capability input.
- Mismatched model evidence, missing adapter provenance, and malformed model
  identity/version/SHA values.
- Successful benchmark redaction, arbitrary reason-code impossibility, latency
  and run upper bounds, exact 10% latency, 2047 MB, 512 MiB, and 1 GiB edges.

---

## Final reviewer follow-up: asserted metadata boundary

### Correction to the prior report

The prior wording that adapter authenticity was enforced at production
composition is withdrawn. This task contains no production inference adapter,
no loaded-model SHA validation, and no mechanism that can prove XNNPACK or GPU
hardware execution.

`InferenceBenchmark` now documents its model identity and provenance as
**caller-asserted metadata**. The closed provenance member is named
`assertedOnDeviceInferenceAdapter` to make that declaration-versus-proof
boundary explicit. `InferencePolicy` documents that it verifies metadata
consistency only. Production adapter construction and validation of the SHA-256
of the model actually loaded by that adapter are explicit, unimplemented
integration requirements for Task 3/later inference-adapter work.

### Canonical version contract

The only accepted `modelVersion` form is canonical SemVer core:
`MAJOR.MINOR.PATCH`, where each component is either `0` or a non-zero digit
followed by digits. Pre-release/build suffixes, `v` prefixes, incomplete
versions, and leading-zero components are rejected.

### TDD evidence

- **SemVer RED:** the new canonical-version test failed because `01.2.3` was
  accepted. The regex was narrowed to the documented core-only form; the model
  suite then passed.
- **Independent mismatch RED:** the new model-ID and SHA tests were verified by
  temporarily mutating the shared comparator to compare only version. Each
  test independently failed by reaching the final qualifying branch, then
  passed after restoring ID, version, and SHA comparison.
- **Final GREEN:** focused model and policy tests passed 31 tests;
  `dart format --set-exit-if-changed lib/device test/device` and `git diff
  --check` exited 0.

### Acceptance boundary

This pure-Dart capability policy does **not** initialize LiteRT, XNNPACK, or a
GPU delegate, and it does **not** claim real XNNPACK/GPU execution. It evaluates
asserted, validated-shape metadata but returns only XNNPACK CPU decisions. The
otherwise qualifying branch is closed with `gpu-adapter-unverified` until a
future adapter-owned loaded-model evidence type exists.

`InferenceDecision.analysisFrequency` is now the closed
`AnalysisFrequency { low, standard, enhanced }` enum rather than an arbitrary
string. A static composition test scans production Dart sources and proves no
`InferenceDecision` construction selects `InferenceBackend.gpuDelegate`.
The only public decision factory is `InferenceDecision.cpu`; it accepts no
backend parameter, and there is no GPU factory. A model-layer caller therefore
cannot evade the boundary by passing the enum through an alias or helper. The
only generative decision constructor is private.
