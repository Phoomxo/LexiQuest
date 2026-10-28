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

`InferenceBenchmark` contains:

```text
backend, successful, medianLatencyMicros, completedRuns, failureCode
```

Only stable non-sensitive `failureCode` values are accepted:
`delegate-unavailable`, `delegate-init-failed`, `model-unsupported`,
`benchmark-failed`, and `benchmark-missing`.

- [ ] **Step 3: Write failing policy tests**

Prove these cases:

1. no GPU benchmark -> CPU;
2. GPU API candidate without successful delegate benchmark -> CPU;
3. successful GPU benchmark on an otherwise Enhanced candidate -> GPU;
4. GPU slower than CPU by more than 10 percent -> CPU;
5. Battery Saver -> Lite CPU;
6. serious/critical/unknown thermal state -> Lite CPU;
7. low-memory flag, available memory below 768 MB, or free storage below
   512 MB -> Lite CPU;
8. available memory 768–2047 MB -> Balanced CPU;
9. available memory at least 2048 MB, free storage at least 1 GB, and no
   safety constraint may become Enhanced only with successful GPU evidence;
10. an unsuccessful CPU benchmark still returns CPU with a degraded reason,
    never GPU.

Run:

```powershell
flutter test test/device/inference_policy_test.dart --reporter compact
```

Expected: RED because the policy does not exist.

- [ ] **Step 4: Implement the deterministic policy**

`InferencePolicy.select` receives one snapshot, one CPU benchmark, and an
optional GPU benchmark. It returns exactly one tier, backend, analysis
frequency (`low`, `standard`, or `enhanced`), and stable reason code. It does
not inspect device brand/model names and contains no randomness.

- [ ] **Step 5: Run focused GREEN and commit**

```powershell
flutter test test/device/device_capability_models_test.dart test/device/inference_policy_test.dart --reporter compact
dart format --set-exit-if-changed lib/device test/device
git add -- lib/device test/device
git commit -m "feat: add fail-safe device inference policy"
```

Expected: tests pass and formatter exits `0`.

---

