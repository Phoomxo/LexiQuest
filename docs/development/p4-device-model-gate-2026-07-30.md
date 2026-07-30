# P4 Device Model Gate Record

**Date:** 2026-07-30

**Result:** PASS

**Scope:** Verified model lifecycle, resumable download, LiteRT inference,
CPU/XNNPACK benchmark, runtime packaging integrity, and safe application
shutdown.

## Accepted behavior

- The selected MobileNet V1 model has a frozen HTTPS source, Apache-2.0
  license, byte count, SHA-256, application version, tensor contract, raw RGB
  input encoding, embedded label asset, and supported delegate set.
- Downloads resume from a partial file only when the server returns the exact
  requested `Content-Range`; a full response restarts safely.
- Connect and response-stream cancellation abort the HTTP request. Both phases
  also have bounded timeouts.
- A model becomes active only after exact size, streaming SHA-256, interpreter,
  tensor, and label validation.
- An operating-system file lock serializes foreground/background download
  managers for the same model version.
- A valid final file is recovered without downloading again if the process
  stopped after atomic rename but before database activation.
- Application disposal cancels and awaits active model work before closing the
  HTTP client and Drift database.
- Real host inference and bounded CPU/XNNPACK benchmarks report model/version,
  delegate, sample size, median, p90, observed peak working set, and device
  tier using a monotonic clock.
- GPU selection and LiteRT Next accelerator packaging remain disabled until
  the P8 Android hardware matrix passes.
- The downloaded LiteRT Next AAR and all 12 packaged LiteRT/TensorFlow Lite
  native libraries have project-pinned SHA-256 values. The APK gate rejects a
  missing, altered, extra, or unexpected-ABI runtime library.

## Defects resolved during review

The P4 review found and the implementation corrected:

1. same-model races across independent download-manager instances;
2. cancellation that could not interrupt stalled HTTP connect or body streams;
3. resumed responses accepted without exact `Content-Range` validation;
4. repeated download after a crash between rename and database activation;
5. resource shutdown racing active repository writes;
6. a GPU policy path without a production GPU adapter;
7. wall-clock benchmark measurements;
8. an unverified build-time LiteRT Next AAR;
9. incomplete APK native-library checksum and ABI coverage; and
10. an incomplete model manifest and benchmark provenance contract.

The follow-up review found no remaining Critical or Important issue in the P4
diff.

## Bounded verification

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-device-model.ps1
```

Recorded result:

- P4 CLI, model-source, and APK-integrity contracts: PASS
- Model fixture source, byte count, and SHA-256: PASS
- Dart format, 23 scoped paths: PASS
- `flutter analyze`: PASS, no issues
- Focused Flutter suite: PASS, 43 tests
- Real CPU/XNNPACK host inference: PASS
- Android debug APK build: PASS
- Exact AAR/native-library integrity and ABI set: PASS
- `git diff --check`: PASS
- Follow-up read-only code review: PASS

Artifact:

- Path: `build/app/outputs/flutter-apk/app-debug.apk`
- Size: 207,303,253 bytes
- SHA-256:
  `ECE32D821C68A02D8C76BDFF7B6D8137C509CBBC07EC653BFDB49C92A9FAD650`

## Deferred hardware evidence

No Android device is connected to the development host. P8 therefore retains
the mandatory low-, mid-, and high-tier Android checks for:

- on-device CPU/XNNPACK latency and memory;
- optional GPU correctness only after an exact device/driver allowlist;
- camera/model integration, lifecycle, battery, and temperature; and
- 30-minute continuous-use stability.

The debug APK proves packaging and host implementation only. It is not the
participant release APK.
