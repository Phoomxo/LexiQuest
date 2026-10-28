# PM6 full Voice facade test handoff

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`.
Branch: `codex/pair-matching-pm0-pm8`.
Authoritative source owner and sole Flutter/Dart tool owner: `/root/pm6_implementation`.

## Changes

Only `test/voice/voice_service_factory_test.dart` was edited. Nine added cases
exercise `VoiceServiceFactory.create` through `VoiceUseCases.acquireSession()`
and the real policy/orchestrator/installed-pack/native providers:

- Both configured online remote engines (VoxCPM standard and OmniVoice rollback)
  are skipped for local-only pronunciation. A subsequent ordinary request on
  the same facade successfully performs authenticated HTTP, proving that the
  initial zero HTTP/token counts were not caused by unavailable remote routes.
- A verified real temporary installed pack plays through the real audio route
  without native voice selection, HTTP, or token reads.
- A missing manifest entry and an actual same-length corrupted pack file each
  fall back from the installed pack to a positively proven installed nonnetwork
  native voice, with the correct typed fallback reason.
- Missing native proof capability, an uninstalled language, a network-only voice
  inventory, and an unacknowledged voice selection each yield a typed synthesis
  `VoiceFailure`; none speak through native or call HTTP/token readers.

The native fixture implements the optional capability interface and checks the
actual proof/selection/speak sequence. This observes preservation of `localOnly`
through the orchestrator's copied request. All new requests use an explicitly
synthetic phrase, an opaque UUID content id, and bounded `pairPronunciation`
content type. Existing telemetry serialization is checked for those metadata
values and absence of spoken text/token/owner fields. No telemetry source or
schema change was made. Existing ordinary-routing cases remain unchanged;
the installed-pack fixture gained optional text/content-id parameters with the
same old defaults.

## First handoff evidence

- Test file SHA-256 before formatting:
  `8668ECF441855F4D0C4D83B595BCB1FCDC56A4AAFCA09A5E047D8037BDBF3780`.
- Scoped `git diff --check -- test/voice/voice_service_factory_test.dart`
  emitted no whitespace errors; Git reported its existing LF-to-CRLF checkout
  policy warning. The combined read-only shell command exited 0.
- This helper has not run Flutter, Dart, analysis, format, or tests. No RED or
  GREEN runtime evidence is claimed at this handoff. The APIs already existed;
  these are additional characterization/regression checks.

## Run request and ownership

The test source is frozen and handed to the sole tool owner for formatting and
the focused `test/voice/voice_service_factory_test.dart` run. The new group name
is `local-only Pair pronunciation through the full facade`. No extra setup or
external network is required: HTTP/auth/native/audio are recording fixtures,
and installed packs use the existing temporary-directory fixture. No tools or
processes are running from this helper. Root retains staging/commit ownership.

Runtime evidence and any bounded source corrections will be appended only
after the sole tool owner reports the actual result. This handoff proves no
physical-device, production, or Pair UI playback readiness.

## Actual focused result and final release

The sole tool owner executed:

`flutter test --no-pub test/voice/voice_service_factory_test.dart --reporter expanded`

Actual log: `.superpowers/sdd/pm6-voice-facade-green.log`. The helper read that
log after the owner's result message: all 21 tests passed, including the nine
new local-only cases and all 12 existing factory cases. The log ends with
`00:00 +21: All tests passed!`. No test-source correction was needed. This is
observed GREEN characterization evidence; no prior RED or mutation test is
claimed.

A second scoped diff check after the run showed no whitespace errors and
exited 0, with the same Git LF-to-CRLF policy warning. Formatting and analysis
are deferred to the main implementation's final stable source snapshot; neither
is claimed here. No production sources were edited by this helper.

Ownership of `test/voice/voice_service_factory_test.dart` and this report is
released to `/root/pm6_implementation` and root for final integration, formatting,
review, and staging. The helper has no active tools/processes or remaining
writes. The verified boundary is the platform-free full facade with recording
adapters and real temporary pack files, not a physical native TTS device or the
Pair screen's route lifecycle.
