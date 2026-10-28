# P5 Camera and Speech Gate Record

> **Historical gate record.** The statement that no Android device was
> connected describes this gate only. Current camera/speech status and later
> physical-device evidence are reconciled in
> `docs/superpowers/specs/2026-07-31-p8-hybrid-voice-field-release-design.md`,
> section 3.1.

**Date:** 2026-07-30

**Result:** PASS

**Scope:** Camera permission, preview, capture and lifecycle; verified-model
object scanning; microphone permission; platform speech recognition; transcript
assessment; device TTS; and Android packaging.

## Accepted behavior

- Camera and microphone permissions are requested through platform adapters,
  with denied, permanently denied, restricted, and unavailable states kept
  distinct.
- The rear camera preview and capture use the maintained camera plugin. Captured
  temporary files are removed after their bytes are read.
- Camera initialization is serialized. Pause/dispose invalidates pending work,
  waits for its cleanup, and resume creates a current-generation session.
- Captured images are decoded and deterministically converted to the verified
  model's 224x224 RGB input contract.
- Object labels and confidence come from the activated P4 LiteRT runtime. The
  result records model ID, model version, and capture time.
- Accepting a recognized object writes through the standard local vocabulary
  use cases, creates outbox operations, and reuses an existing normalized word
  instead of duplicating it.
- A missing model produces an explicit unavailable state and offers the P4
  checksum-verified, cancellable, resumable download path.
- Speech recognition uses microphone permission and the platform recognizer.
  Callback routing follows the current screen when the singleton adapter is
  reused.
- Both speech screens cancel the microphone when the application becomes
  inactive, paused, hidden, detached, or the route is disposed.
- Pronunciation feedback is limited to transcript edit distance and records
  recognizer, locale, time, and method provenance. It does not invent pitch,
  phoneme alignment, or acoustic confidence.
- TTS uses the existing on-device voice adapter. A completed pronunciation
  attempt can persist learning evidence without storing raw audio or transcript.
- Android declares camera and microphone as optional hardware so installation
  is not unnecessarily blocked, while runtime availability remains explicit.
- The iOS deployment target is aligned with the current camera package minimum.

## Removed simulation paths

The P5 implementation deleted the random/simulated image-label, accent pitch,
phoneme-alignment, pronunciation-score, and pitch-contour services, widgets,
and their simulation tests.

## Defects resolved during review

The review found and the implementation corrected:

1. stale speech status callbacks after reusing the singleton recognizer;
2. a camera left active when route disposal raced pending initialization;
3. concurrent camera initialization creating multiple sessions;
4. resume attaching to a camera initialization invalidated by pause;
5. microphone capture continuing after the application left the foreground;
6. captured temporary images not being deleted;
7. missing Android recognizer and TTS service visibility declarations; and
8. an iOS deployment target below the selected camera package minimum;
9. a displayed confidence paired with a different classification than the
   mapped vocabulary; and
10. a failed recapture leaving the previous result available for acceptance.

## Bounded verification

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-camera-speech.ps1
```

Recorded result:

- P5 CLI and pinned-model contracts: PASS
- Dart format, 19 scoped files: PASS
- `flutter analyze`: PASS, no issues
- Focused Flutter suite: PASS, 53 tests
- Android debug APK build: PASS
- Exact APK model-runtime integrity: PASS
- `git diff --check`: PASS
- Follow-up read-only code review: PASS

Artifact:

- Path: `build/app/outputs/flutter-apk/app-debug.apk`
- Size: 235,263,973 bytes
- SHA-256:
  `A51B59AB939424D3A5BA35D4446E914BA40F8BDF87C31ADDA309E1544D9383D0`

## Deferred device evidence

No Android device is connected to the development host. P8 therefore retains
the mandatory low-, mid-, and high-tier checks for:

- camera orientation, lifecycle, capture quality, and model usefulness;
- microphone permission, recognition availability, locale behavior, and audio
  interruption handling;
- TTS/STT latency and failure behavior;
- CPU/XNNPACK and any allowlisted GPU delegate;
- 30-minute memory, battery, and thermal stability; and
- release-signed install, upgrade, restart, background, and foreground journeys.

The debug APK proves the implementation and packaging gates only. It is not the
participant release APK.
