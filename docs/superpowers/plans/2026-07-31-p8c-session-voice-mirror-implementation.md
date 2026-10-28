# LexiQuest P8-C Session Voice Mirror Implementation Plan

**Status:** READY FOR EXECUTION

**Scope:** A separately consented, temporary VoxCPM2 voice-mirror session for
approved learning targets, including microphone enrollment, authenticated
server leases, account isolation, playback-only output, and cleanup.

**Out of scope:** Pronunciation scoring, permanent voice profiles, cross-device
restore, audio sharing/export, model/GPU field certification, and production
rollout. Those remain P8-D onward.

**Upstream:** P8-B through `26758c2`.

## Delivery rules

- Work one bounded file at a time and run the focused contract after each
  coherent slice.
- GLM may only receive a one-file task. Stop GLM after repeated timeout or
  no-progress; Codex remains the authoritative implementer and reviewer.
- Use only authenticated HTTPS in release.
- The full model and participant audio never enter the APK, Firebase, Drift,
  analytics, research export, backup, or ordinary media storage.
- Raw enrollment and generated audio are bounded, session-only, never cached,
  never downloadable, and erased on every termination path.
- Backend ownership comes only from the verified Firebase token. A session
  token from another account must never work.
- Lease is five minutes, absolute lifetime is twenty minutes, and no client
  clock can extend either server boundary.
- No retries loop. Heartbeats and cleanup are bounded and idempotent.
- The public VoxCPM2 cloning API uses `reference_wav_path`; the worker keeps
  reference bytes only in volatile session memory, creates a randomized work
  file for one inference call, and deletes that file in `finally`.
- Do not claim real model, GPU, audio quality, or physical-device acceptance
  until those paths run with recorded evidence.

## Dependency order

1. Backend session and retention contracts.
2. VoxCPM2 mirror engine adapter.
3. Authenticated mirror HTTP lifecycle.
4. Flutter mirror gateway and controller.
5. Microphone enrollment recorder and startup cleanup.
6. Dynamic policy/provider/factory wiring.
7. Consent and playback journey in Shadowing Challenge.
8. P8-C bounded gate and evidence.

## Task 1: Add backend volatile session storage

**Files, one at a time:**

- Create `backend/voice_api/tests/test_mirror_sessions.py`
- Create `backend/voice_api/src/lexiquest_voice/mirror_sessions.py`
- Modify `backend/voice_api/src/lexiquest_voice/config.py`
- Modify `backend/voice_api/tests/test_config.py`

The store owns randomized opaque session IDs and mutable reference bytes. It
binds each record to the verified UID, tracks creation, five-minute lease,
twenty-minute absolute expiry, request/character quota, and one active
synthesis. Create, heartbeat, acquire, release, delete, and purge are
thread-safe. Delete and purge overwrite the mutable bytes before removing the
record. Missing delete is success. Cross-account access, expired lease,
withdrawn consent, quota, and concurrency fail with typed internal errors that
carry no ID, audio, or text.

**Commit:** `feat(voice-api): manage volatile mirror sessions`

## Task 2: Add the real VoxCPM2 mirror adapter

**Files, one at a time:**

- Create `backend/voice_api/tests/test_voxcpm_mirror_engine.py`
- Create
  `backend/voice_api/src/lexiquest_voice/engines/voxcpm_mirror_engine.py`

The adapter shares an injected/lazy model provider, accepts only a bounded WAV
reference held in memory, writes one randomized private work file, calls
`model.generate(text=..., reference_wav_path=...)`, encodes 48 kHz WAV, and
deletes the work file in `finally` after success or failure. Loading and
generation are serialized. Empty/non-finite output fails closed. Tests inject
the model, temp-file boundary, and WAV writer; no optional model is installed.

**Commit:** `feat(voice-api): add transient VoxCPM2 mirror engine`

## Task 3: Expose authenticated lease endpoints

**Files, one at a time:**

- Create `backend/voice_api/tests/test_mirror_app.py`
- Modify `backend/voice_api/src/lexiquest_voice/models.py`
- Modify `backend/voice_api/src/lexiquest_voice/errors.py`
- Modify `backend/voice_api/src/lexiquest_voice/app.py`
- Modify `backend/voice_api/src/lexiquest_voice/main.py`
- Modify `backend/voice_api/README.md`

Add create/enroll, heartbeat, speech, and delete endpoints under
`/v1/voice-mirror/sessions`. Enrollment accepts only `audio/wav`, requires the
versioned consent header, and rejects missing length, oversized payload, and
invalid WAV. Speech requires content ID and bounded English/Thai target text.
Every operation verifies Firebase auth and session ownership. Responses use
`Cache-Control: no-store`; error bodies use fixed codes. Delete is idempotent.
Every request purges expired records once without background retry.

**Commit:** `feat(voice-api): expose private mirror leases`

## Task 4: Add the Flutter mirror gateway and controller

**Files, one at a time:**

- Create `test/voice/voice_mirror_gateway_test.dart`
- Create `lib/voice/voice_mirror_gateway.dart`
- Create `test/voice/voice_mirror_session_controller_test.dart`
- Create `lib/voice/voice_mirror_session_controller.dart`

The gateway uses the existing Firebase token provider, one forced refresh after
the first 401, fixed timeout, typed safe failures, and no logs. The controller
owns consent, active session metadata, heartbeat, request quota, and an
idempotent end operation. It ends on withdrawal, explicit end, account change,
activity leave, app detach, absolute expiry, or five continuous background
minutes. A failed delete leaves no usable local session and is reported only
as `cleanupIncomplete`.

**Commit:** `feat(voice): manage private mirror leases`

## Task 5: Record and erase enrollment audio

**Files, one at a time:**

- Modify `pubspec.yaml` and lock dependency `record` at one reviewed version
- Create `test/voice/voice_mirror_recorder_test.dart`
- Create `lib/voice/voice_mirror_recorder.dart`

Record mono PCM WAV with a bounded duration into the application cache
directory after microphone permission. Startup deletes stale files in the
dedicated enrollment directory. Stop reads bounded bytes and deletes the file
before returning; cancel, error, lifecycle stop, and dispose delete it as well.
No public media path, backup path, or user filename is used.

**Commit:** `feat(voice): capture ephemeral mirror enrollment`

## Task 6: Route mirror playback without cache

**Files, one at a time:**

- Create `test/voice/vox_cpm_mirror_provider_test.dart`
- Create `lib/voice/vox_cpm_mirror_provider.dart`
- Modify `test/voice/voice_service_factory_test.dart`
- Modify `lib/voice/voice_service_factory.dart`
- Modify `lib/runtime/app_bootstrap.dart`
- Modify `lib/runtime/app_dependencies.dart`
- Modify affected bootstrap/account tests

Register `VoiceEngine.voxCpmMirror` only when Cloud configuration and the
mirror controller are present. Policy state is loaded dynamically from the
controller. Participant-transient audio is never placed in a cache. Provider
output is played and then released; stop/cancel ends playback. Application
dispose and account transition call controller cleanup exactly once.

**Commit:** `feat(voice): route uncached session mirror playback`

## Task 7: Deliver the separate consent journey

**Files, one at a time:**

- Modify `test/screens/shadowing_challenge_screen_test.dart`
- Modify `lib/screens/shadowing_challenge_screen.dart`

Add a clearly optional section labelled as AI-generated target speech. Show the
purpose, five/twenty-minute lifetime, server processing, deletion, no
download/share/export, and standard-speech fallback. Consent is unchecked by
default. Enrollment requires an explicit action and microphone permission.
The participant can end/withdraw at any time. Leaving the screen ends the
session. Only the current local learning target can be synthesized; the screen
does not expose free-text input.

**Commit:** `feat(voice): add temporary mirror consent journey`

## Task 8: Close the bounded P8-C gate

**Files, one at a time:**

- Create `tool/cli/tests/verify-session-voice-mirror.tests.ps1`
- Create `tool/cli/verify-session-voice-mirror.ps1`
- Create `docs/development/p8c-session-voice-mirror-gate-2026-07-31.md`
- Mark P8-C complete in the authoritative design only after PASS

The gate runs each phase once: format, analyze, focused Flutter voice/runtime/
screen tests, all backend tests without optional model installation, privacy
boundary scans, debug APK, and `git diff --check`. Evidence records exact
commits, versions, counts, APK hash, and explicit non-certifications.

**Commit:** `test(voice): close P8-C session mirror gate`

## P8-C completion boundary

P8-C is complete only after the accepted CLI gate proves server lease/expiry/
owner isolation, client consent/lifecycle cleanup, uncached playback, and a
buildable Android path. A fixture-backed gate does not certify real VoxCPM2
model quality, GPU latency, production deployment, or a physical microphone.
