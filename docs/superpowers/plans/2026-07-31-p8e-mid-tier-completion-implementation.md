# LexiQuest P8-E Mid-tier Completion Implementation Plan

**Status:** READY FOR EXECUTION

**Scope:** Close every mandatory field journey on the mid-tier vivo V2041 for
the new release-signed APK that integrates P8-A through P8-D. Produce honest
physical-device evidence for the 14 required journeys, decide whether the
30.44-minute endurance record can be retained, and run the bounded P8-E gate.

**Out of scope:** Low- and high-tier physical devices (P8-F), App Check
production enforcement (P8-F), private support/research references (P8-F/G),
and the 3→10→30 participant rollout (P8-G).

**Upstream:** P8-D through `3c59b2f`.

## Baseline state

The signed `1.0.0+9` APK (SHA-256 `FB9C39...`, source `6a42c9a`) recorded
seven mid-tier journeys: offline vocabulary, offline restart/sync, model
lifecycle, camera inference, clean install, version-8→9 upgrade, and the
CPU/XNNPACK benchmark (CPU preferred; GPU not allowlisted). It also recorded a
30.44-minute endurance run with zero crash/ANR.

That APK is now stale: P8-A through P8-D added the hybrid voice architecture,
session voice mirror, and real speech evidence. Every mid-tier journey must be
re-run on a newly signed APK tied to a new SHA-256, because the final
field-release gate rejects any device record whose APK hash differs from the
released artifact.

## Delivery rules

- Every journey is executed on the physical vivo V2041 running Android 13 with
  the exact release-signed APK produced in Task E1. No simulated or emulated
  device evidence is accepted.
- Each journey produces one evidence record carrying the APK SHA-256, the
  device model, the source commit, the journey name, pass/fail, and any
  measured metrics (latency, crash/ANR counts, RSS, battery, temperature).
- Silence, permission denial, cancellation, unavailable locale, and provider
  failure produce honest unavailable states, never a fabricated score.
- The endurance result is retained only if a bounded profiling comparison shows
  the voice changes do not materially alter sustained resource use. Otherwise it
  is re-run for the new APK.
- Gemini BYOK (Task E6) and speech/pronunciation (Task E5) require a real
  owner-provided Gemini key and a physical microphone. If the owner does not
  provide the key, those journeys remain pending and P8-E cannot close.
- No data loss, ownership crossover, consent regression, or voice retention
  violation is tolerated. Any such defect is a release blocker.

## Required field journeys (14)

`consentGuestStartup`, `offlineVocabulary`, `learningCore`, `offlineRestartSync`,
`accountLifecycle`, `modelLifecycle`, `cameraScanner`,
`speechTtsPronunciation`, `geminiByok`, `cleanInstall`, `upgradeInstall`,
`rebootForegroundBackground`, `cloudKillSwitch`, `dataExport`.

## Dependency order

1. Build and install the release-signed APK.
2. Clean install and Guest/consent startup.
3. Offline vocabulary and restart/sync.
4. Learning core.
5. Account lifecycle.
6. Model lifecycle and camera scanner.
7. Speech, TTS, and pronunciation.
8. Gemini BYOK.
9. Reboot and foreground/background.
10. Cloud kill switch.
11. Data export.
12. Endurance profiling decision.
13. Bounded P8-E gate and evidence.

## Task E1: Build and install the release-signed APK

Run `tool/cli/initialize-release-signing.ps1` (if no keystore exists at
`%USERPROFILE%\.lexiquest\signing\lexiquest-release.p12`), then
`tool/cli/package-field-release.ps1`. Record the manifest fields:
`apkSha256`, `signingCertificateSha256`, `sourceCommit`/`buildId`,
`modelSha256`. Install the APK on the vivo V2041 with
`adb install -r build/field-release/lexiquest-<version>.apk` and capture
`adb shell getprop ro.product.model` to confirm the device.

**Owner action:** provide or confirm the signing keystore.

## Task E2: consentGuestStartup and cleanInstall

Clean install (uninstall any prior version), launch with airplane mode on, walk
the research-consent flow, and start a Guest session without network. Confirm
no crash and that local data initializes. This also satisfies `cleanInstall`.

## Task E3: offlineVocabulary and offlineRestartSync

Add vocabulary offline, force-stop the app, cold-restart with airplane mode on,
reconnect, and confirm synchronization is idempotent. Record crash/ANR counts.

## Task E4: learningCore

Quiz, SRS, reading, progress, and rewards on the device. Record the number of
items attempted and confirm evidence persists locally.

## Task E5: accountLifecycle

Convert the Guest owner to an authenticated account without losing local data,
then sign out and confirm ownership does not cross over.

## Task E6: modelLifecycle and cameraScanner

Run the LiteRT model lifecycle and a real camera object inference. Record CPU
latency and confirm GPU remains not allowlisted unless explicitly tested.

## Task E7: speechTtsPronunciation

Speak a word, capture the transcript, observe the pronunciation similarity,
and confirm a `SpeechEvidence` row persists (query the local database via
`adb shell run-as`). Silence must produce an unavailable state, not a zero
score.

**Owner action:** grant microphone permission; confirm the recognizer locale is
available on the device.

## Task E8: geminiByok

Enter a real owner Gemini key, run one AI Tutor request, confirm a response,
and confirm no project-funded usage. Key handling must remain secret/no-log.

**Owner action:** provide a real Gemini API key.

## Task E9: rebootForegroundBackground

Reboot the device, relaunch, background the app for several minutes, return to
foreground, and confirm no crash/ANR. Confirm the voice-mirror session ends on
background and offline learning resumes.

## Task E10: cloudKillSwitch

With the Cloud kill switch disabled, confirm offline learning continues, then
re-enable and confirm safe synchronization returns. Record the exact
`cloudKillSwitch` journey.

## Task E11: dataExport

Trigger a real data export on the device via the document provider and confirm
the exported file is complete and readable.

## Task E12: Endurance profiling decision

Profile sustained resource use on the new APK and compare to the baseline
30.44-minute record. If the voice changes materially alter resource use, re-run
a ≥30-minute endurance session on the device with zero crash/ANR. Otherwise,
record the retention rationale tied to the new APK hash.

## Task E13: Close the bounded P8-E gate

- Create `tool/cli/tests/verify-mid-tier-completion.tests.ps1`
- Create `tool/cli/verify-mid-tier-completion.ps1`
- Create `docs/development/p8e-mid-tier-completion-gate-2026-07-31.md`
- Mark P8-E complete in the authoritative design only after PASS

The gate runs each phase once: format, analyze, the existing focused voice and
data tests, a check that the mid-tier evidence record covers all 14 journeys
tied to the exact APK hash, and `git diff --check`. Evidence records exact
commits, APK hash, journey counts, and explicit non-certifications.

**Commit:** `test(field): close P8-E mid-tier completion gate`

## P8-E completion boundary

P8-E is complete only after the accepted gate proves all 14 journeys pass on
the vivo V2041 for the exact release-signed APK, endurance is either retained
with rationale or re-run, and no release blocker remains. A passing gate does
not certify low/high devices, App Check production enforcement, or the
participant rollout.
