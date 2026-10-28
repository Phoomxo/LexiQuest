# PM8 final whole-branch review — UI / Voice partition

## Scope and source identity

- Reviewed read-only in `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`; base `ca123dddc1349acc4ed67bdd8f5476b02165307c`, HEAD `3bdb5f5605e670e8b30628f3f237cd9c0d660ad9` plus frozen uncommitted PM8. No source/test edit, Flutter/Dart/pub/test/build/scanner, Git mutation or other-worktree operation. This assigned report is the only write.
- Applied `C:/Users/Phet/.codex/skills/requesting-code-review/code-reviewer.md`, `pm8-final-review-common-brief.md`, integration brief, full owner contract including engine P/runtime R and PM6 cap addenda, current task-final-review, PM8 implementation report, approved Checkpoint 7 PM6–PM8 and Pair specification sections. Current authorization supersedes historical approval/status language.
- Packet `.superpowers/sdd/pm8-branch-20260907T031355833-ui.diff`: 50 files, 541361 bytes, independently verified SHA256 `7a7addf1b3e7411a6917cc4fb58ba174d255eda715ab78003a1c185968e31cf7`. Read the flattened packet in sequential chunks; reread only clipped portions after output truncation. Global manifest `.superpowers/sdd/pm8-branch-20260907T031355833.manifest.json` has 122 paths / 122 unique paths; UI owns 50, including 15 PNGs. Independently hashed all 50 actual files: zero differences from this manifest.
- Scope includes Standard/Adventure/Today presentation, registry, controller/shell reservation and retirement, legacy wrapper extraction, history, native Voice/privacy and assigned tests. Narrow external checks: coordinator operation/status and clock lease APIs; unavailable disposition helper; History purpose use case; existing route-Voice mixin and Voice facade completion contract. No broad crawl.
- All 15 PNGs are byte-identical to accepted PM7 source `631b518bbb9c79f30b4f7ad4237551cdc09432a1` (`git diff` on PNGs empty). Reused the documented actual PNG inspection/comparisons in `pm6-report.md:125` and `pm7-report.md:98,122`; no new visual generation/physical-device claim. The findings below are lifecycle/clock defects, not visual judgments.

## Strengths

- Standard and Adventure share the same captured Today source and canonical board callbacks; decoration does not create a second command/evidence/reward authority. Exact parity fixtures exercise both densities, both directions, all presets, repair, guided support, lost acknowledgements and same-host fallback.
- Recovery binds a runtime owner separately from immutable plan commands. The corrected first-disposition callback at `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart:986` invokes the pane's sticky owner check before returning its fixed runtime owner. Current source matches the corrective task-review identity.
- Legacy matching body remains equivalent to the base after class/import relocation, formatter whitespace and the explicit shell-feedback insertion; independently compared the normalized body (14018 characters on each side). Default registry remains legacy/implemented-off and no new bottom-tab identity is introduced.
- Voice local-only routing excludes remote providers and checks installed, non-network native voices before speaking. Full-facade tests include an enabled remote positive control, zero remote/auth calls for local requests and redacted opaque telemetry. History uses authenticated Pair projections and a separate typed replay callback rather than generic replay.

## Issues

### Critical

None demonstrated in this partition.

### Important I1 — Returning while an accepted operation is busy leaves the Pair clock permanently paused

- **File:** `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart:1316–1326`, especially the `_busy` early return at line1321; acquisition at line1311.
- **Trigger:** Hold an accepted answer/checkpoint operation; push another observed PageRoute over the Pair route, then pop it while that operation is still pending. `onVoiceRouteCovered` acquires `_coverPause` even when `_busy`; `onVoiceRouteResumed` returns because `_busy` is true. Once the operation finishes, `_run` only clears `_busy` and does not reconcile the requested route state or release that lease.
- **Impact:** `boardUnavailable` remains in `PairActiveClock` although the board is visible. Subsequent matching commands remain accepted (`coordinator.hostStatus` does not use pause reasons to disable dispatch), but challenge remaining time and full interactive duration stop advancing. Results can therefore retain a plausible yet incomplete measured duration and timed play can avoid timeout until another cover/resume or recovery. This violates the approved active-interaction clock contract.
- **Evidence:** Existing `RouteVoiceSessionMixin` emits resumed hooks on route/lifecycle transitions, not on later host operation completion (`lib/features/voice/presentation/route_voice_session_mixin.dart:127–143`). `PairActiveClock.release` removes only the exact lease and `fold` does no accounting while paused (`lib/features/learning/pair_matching/domain/pair_active_clock.dart:202–234`). Coordinator operation cleanup releases its own `_operationPause`, not the pane's `_coverPause` (`pair_matching_session_coordinator.dart:443–451`). The changed host tests exercise app background after settled work, not this overlapping route-return case.
- **Fix / acceptance:** Track whether the pane currently wants interaction and reconcile after busy work settles, with owner/disposal and repeated-cover protection; retain the existing exact lease. Add a real host regression with `appRouteObserver`, held canonical write, cover+return before acknowledgement, release, then advance monotonic time and assert the board-unavailable lease clears and both relevant clocks advance only during visible interaction. Root was notified; no reviewer test was run.

### Important I2 — Narration pause ends at playback start rather than playback completion

- **File:** `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart:1287–1302`.
- **Trigger:** Tap pronunciation while using the actual native provider. `_pronounce` acquires narration pause, awaits `VoiceSession.speak`, then immediately releases pause in `finally`. The existing Voice facade explicitly defines a successful speak Future as **playback started, not playback ended** (`lib/features/voice/application/voice_use_cases.dart:149–152`). `FlutterTtsAdapter.speak` simply awaits `_resolved.speak(text)` (`lib/voice/native_tts_provider.dart:90–91`) and this adapter does not enable completion waiting.
- **Impact:** Native audio can still be playing when the Pair clock resumes. Listening time consumes challenge time and enters full interactive duration; a learner can time out during narration, contrary to approved PM4 step2 (`docs/superpowers/plans/2026-09-01-adventure-motivation-mode-implementation.md:763`). Opaque metadata and zero-network routing do not establish correct playback duration. Host tests use a provider that returns immediate success and cannot expose this mismatch.
- **Fix / acceptance:** Keep the Pair narration lease until an explicit playback-completed or stopped/cancelled event, using a bounded route-owned completion path that preserves existing Voice takeover and late-operation safety. Do not reinterpret the existing general facade's start acknowledgement as completion. Add a provider/host test separating start acknowledgement from audible completion, advance monotonic time while playback continues, and assert no challenge/interactive increment until completion or confirmed stop; also cover route takeover/disposal. Physical audio quality remains a separate NotRun gate.

### Minor

No additional actionable Minor defect established. Nine inherited Drift fixture warnings remain disclosed in the covering run; this review neither suppresses them nor claims they were fixed.

## Covering evidence and cross-boundary disposition

- Independently read `.superpowers/sdd/pm8-host-race-affected-20260907T031244596.metadata.json` and final log lines: **971 passed / 0 failed, exit0**, reporter233s / wall239.3704179s, UTC `2026-09-07T03:12:45.0243207+00:00`–`03:16:44.3947386+00:00`. Exact17-entry argv covers all Pair tests, identity/research owner, matching/evidence/use cases/repository/controller, export/deletion, Adventure parity/experience, research sync authorizer, gates and Matching wrapper. All1045 lib/test input hashes unchanged; `inputDifferences: []`; before/after SHA256 `3271873c56aacfd7666dc6b734e2c7517e5926eed7c6347288fcb856c7764a1e`.
- Independently read `.superpowers/sdd/pm8-host-race-analyze-20260907T031131371.metadata.json` and log: exact `analyze --no-pub lib test`, no issues, exit0, reporter15.3s / wall18.1092873s. This does not cover the two missing behavioral interleavings above. The 971 selection is not the final full default/serial result and does not directly select all changed Voice, Today/history or navigation tests; root's final release gates remain necessary.
- The engine/boundary reviewers reported the canonical normal-close transaction owner-authentication gap. This UI inspection found no enclosing database owner transaction in shell lease/reservation/completeRecovery that would negate their finding. Engine owns that finding to avoid duplication; UI does not independently approve that boundary.
- Part(b) generators, full default+serial/policy/local-audit gates and reproducible verified internal APK/minimum-reader artifact remain root-owned. Physical TalkBack/Switch/Voice/performance/learner UAT, external G4P role signatures, research authority and rollout remain NotRun/pending. No merge/push/deploy/enrollment/upload authorization is inferred.

## Assessment

**Ready to merge / accept this source partition: With fixes.** Current owner-bound correction, presentation parity, default-off behavior and local-only routing are sound within the inspected seams, but I1 and I2 leave concrete clock correctness gaps in the real presentation/Voice integration. Root should resolve these two bounded issues and the separate engine/boundary findings, then run the required frozen-source release gates; passing971 alone is not end-to-end or production readiness. Reviewer ownership released; no reviewer process remains.
