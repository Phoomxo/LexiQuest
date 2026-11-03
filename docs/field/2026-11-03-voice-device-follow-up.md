# Voice and device acceptance follow-up

Baseline: `6118e3ae`, application `dc740a8e`, installed offlineTrial 25.
Worktree: cycle12-release/LexiQuest; branch: codex/remaining-system-readiness.
Cloud A, Billing, payments, public rollout and real Research enrollment remain
excluded. The owner now authorizes listening and TalkBack on Vivo V2041.
Microphone recording is not part of this check.

## Execution plan

- Read poteto-mode principles. Done.
- Phase A: Frame. Verify actual voice composition, redirect handling and bounded
  screen-reader behavior; do not substitute fixtures for external approval.
- Phase B: Design the workflow. Root owns device actions and serial checks;
  acceptance_gap_review owns the provider and bootstrap fixes/tests.
- Phase C: Run the loop. Reproduce, make the smallest shared correction, run
  voice/bootstrap/caller tests, then inspect the updated artifact on the phone.
- Phase D: Keep the audit trail. Record decisions and exact evidence below.
- Phase E: Verify and hand back. Separate source, installed artifact, human
  listening, live provider and Research authority verdicts.

## Decisions and evidence

| Check | Observation | Decision |
|---|---|---|
| OmniVoice redirects | Actual loopback 303 reaches redirected target before the fix; four other redirect cases pass | Disable redirects in shared `_post`; retain typed failure |
| Voice regression | `flutter test test/voice --reporter expanded`: 221 pass after the one-line fix | Provider boundary corrected; not a live-provider verdict |
| Device flashcards | Installed 25 shows disabled Listen for `book`; bootstrap omits `AppDependencies.voice` | Fix runtime composition, not the widget guard |
| TalkBack | Owner confirms clear readout and successful double-tap to reveal `book`; capture confirms translated card | Bounded version25 workflow passes; restored services=null and enabled=0 |
| Research | Existing trusted issuer, protocol/instrument pins and default-off transport | No invented authority or enrollment; no speculative feature changes |

The shared voice service now belongs to bootstrap. Model the Domain keeps the
existing `ManagedVoiceService` and `VoiceUseCases` ownership instead of adding
screen-specific providers. Both normal disposal and failed initialization close
the service. Explicit absent configuration does not reread environment endpoints.
The constructor hook remains optional for existing platform-free test harnesses;
the production factory supplies it and has a regression against omission.

Current checks: 291 voice/bootstrap/SRS/recall tests pass; a separate test with
synthetic configured environment origins passes while sending no HTTP or auth
requests. Independent source review accepts the change. Analysis first reported
an empty cleanup catch; a one-line explanation preserves the original failure
without adding a suppression. The additional caller suite passes 114 tests and
final analysis reports no issues. This is focused current-source evidence, not
a new full 5,581-test run.

Provider environment-name discovery found no matching configuration variables in
this process. This is bounded evidence, not a claim that no approved service
exists elsewhere. The owner subsequently confirmed that no provider configuration
is available and directed native voice and internal testing only. Real provider
acceptance is therefore outside the current executable scope.

## Version26 package

Source: `00d6c8ea8be9f54acaad15a4ed8ce818bec5461a`.
Signed offlineTrial APK/AAB packaging and native/model integrity pass. Root
recomputed both artifact hashes against the generated manifest. APK SHA256:
`a53ca3c00b4ad0f413dffe8a9b4b446a138fb5cd4534a2efd5e5caa6af28a3d4`.
AAB SHA256:
`0134721c7dc9e98868fe39fbc0382c47786e09243b2d24bd1e3e4cd2f56fad2a`.
The package is under `critique35/voice36-package/lexiquest-1.0.0+26`.
Installation and audible acceptance are separate from this package result.

The in-place installation succeeds and the installed SHA256 matches the package.
Version26 starts and retains the previous local owner and resumable activity.
The actual `book` card exposes enabled Listen and Stop controls; version25
exposed them disabled. See `install26-result.json`, `voice36-device26.json` and
`audio36-v26-card.xml`. No microphone capture was started.

Independent artifact review accepts hashes, signing, package/version, embedded
build identity and model pin across all three ABIs, plus native runtime checks
for both archives. The pin does not establish the hash of a model downloaded on
the device. Offline configuration keeps remote services disabled. No actual
provider or Research service was invoked. Human native audio confirmation is
pending; do not infer audible quality from an enabled control.

Physical captures are retained under
`D:\LexiQuest-Storage\maintenance\2026-11-03\critique35\audio36-*`.
The `audio36-played` filename records an editor navigation, not audio playback.
No audible result is inferred from its name. A quiz was opened then left without
answering during navigation; its resumable session remains in local history.
