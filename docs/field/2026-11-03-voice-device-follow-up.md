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
exists elsewhere. Real provider acceptance remains pending an actual endpoint.

Physical captures are retained under
`D:\LexiQuest-Storage\maintenance\2026-11-03\critique35\audio36-*`.
The `audio36-played` filename records an editor navigation, not audio playback.
No audible result is inferred from its name. A quiz was opened then left without
answering during navigation; its resumable session remains in local history.
