# Spec Compliance

- **Issues found — one required owner-lifecycle cleanup gap.** The frozen Adventure/Today composition follows the approved source, launch, default-delegate, and same-host contracts. `lib/features/adventure/presentation/adventure_pair_experience.dart:83` retains its private diagnostics for the route lifetime, but `:173` only replaces them during route disposal; there is no owner-invalidation reset while the same route remains mounted. See I1 below.
- **Advisory scope only.** This is not final PM7 acceptance. Signed measurement, configured withdrawal/disposition, final formatting/regression, and full phase review are outside this seven-file package. PM8 owner rehome is explicitly outside this advisory scope.

# Strengths

- `lib/features/adventure/presentation/today_experience_host.dart:851` passes the exact resolved Today snapshot, decision, original delegate, and captured currentness closure to the optional synchronous factory. Null keeps the original delegate. The unchanged early return at `:291` still precedes journey composition and reward loading. Tests at `test/features/adventure/presentation/today_experience_host_test.dart:37` and `:73` assert one Today load, one original entry ID, no Adventure reads, and original delegate identity.
- `lib/features/adventure/presentation/adventure_pair_experience.dart:116` derives both presentations from `PairSourceSnapshot.today`; `:123` allocates identity only during route initialization after current-owner validation. The retained state and `:198` host keep the same launch across rebuilds and flag fallback. Tests at `test/features/adventure/presentation/adventure_pair_experience_test.dart:26` and `:56` assert this identity preservation.
- `lib/features/adventure/presentation/adventure_pair_experience.dart:211` validates the genuine review mission against the complete captured Today identities, owner, evaluated time, and supported mode. The existing journey reader at `lib/features/adventure/application/adventure_journey_reader.dart:274` creates exactly that complete review mission, including `sourceId = content.first.id`; the differing sorted mission order does not create a second content authority.
- `lib/features/adventure/presentation/adventure_pair_experience.dart:247` only captures inputs; `:260` shares one in-flight navigation across newly built delegates, and `:272` rechecks owner/currentness after the await. Unsupported actions forward unchanged. The Adventure button's existing `lib/features/adventure/presentation/adventure_mission_sheet.dart:21` guard holds `_starting` until the real navigation future completes.
- `lib/features/adventure/presentation/today_experience_host.dart:799` binds callbacks to owner, refresh/presentation generation, and the originating load future. The contextual guard passed at `lib/features/adventure/presentation/adventure_pair_experience.dart:198` is checked by the canonical host before and after fresh setup awaits (`lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart:314` and `:379`), only until `_pendingStart` is reserved. An already retained exact start retry does not depend on current Today presentation.
- `lib/features/adventure/presentation/adventure_pair_renderer.dart:130` embeds the supplied canonical board without a new answer, clock, repair, star, evidence, or reward authority. Health is a typed one-shot reason at `:72`; the host's existing synchronous/late fallback at `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart:1418` preserves its owning state/controller.
- Prior-route callback safety is present: renderer disposal removes the health listener (`lib/features/adventure/presentation/adventure_pair_renderer.dart:83`); its queued initial health check verifies `mounted` (`:65`); the canonical host's captured failure callback verifies `mounted` before scheduling and again inside the post-frame callback (`lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart:1421`). A callback retained from a disposed route cannot target a newly created host state. This does not satisfy owner-counter clearing on a still-mounted route.

# Issues

## Critical

- None confirmed in this bounded package.

## Important

- **I1 — Clear and close the diagnostic scope on owner invalidation, not only route disposal.** `lib/features/adventure/presentation/adventure_pair_experience.dart:83` creates the counter object and `:173` only replaces the field on disposal. `_current` at `:96` denies stale entry use, but does not clear diagnostic state; the canonical host's owner subscription (`lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart:792`) only updates its own live owner/error state. Existing `AdventureDiagnostics` has bounded enum counters (`lib/features/adventure/application/adventure_diagnostics.dart:101`) and a snapshot method at `:200`, with no clear/closed-owner lifecycle. Thus a failed-decoration count survives an actual active-owner change while its originating route remains mounted, contrary to the binding owner-and-route cleanup requirement. This is a specific acceptance gap, not evidence of a payload leak, cross-owner learning write, or stale callback mutating a new route. Close the originating diagnostic scope on owner invalidation and disposal, clear accumulated counters, and make any delayed callback for that closed scope inert. A bounded acceptance test should record a count, change the actual active owner without unmounting the route, assert counters are cleared, then deliver a captured old health/failure callback and assert the closed scope stays empty and a new host's diagnostics remain unchanged. Preserve existing canonical owner and retained-operation guards.

## Minor

- None separately raised. Missing final measurement/regression evidence is phase work, not a defect inferred from this advisory diff.

# Checks and evidence boundary

- Primary input: `.superpowers/sdd/pm7-adventure-advisory.diff`, baseline `cbc4541ff4ad058e11f056f2d06f7eada201e3f9`. The first combined tool output was truncated; only the omitted contiguous portions were recovered. No whole-branch Git scan was run.
- The three production files and three presentation tests still matched all six hashes in `.superpowers/sdd/pm7-adventure-advisory-hashes.json` at this review's check.
- The original parity fixture was an intermediate RED snapshot, not an engine finding. Root subsequently supplied corrected `test/features/adventure/adventure_pair_renderer_parity_test.dart`; this reviewer read that corrected file once and verified SHA-256 `6b343214adf0b6ad74bba679030bdcc11a6d2d094d15e03bf293c408d294e5d0`. It now waits for the required third intervening success with six pairs and cleans `_runScript` up in `finally`, retaining transcript and receipt assertions. Root independently verified `.superpowers/sdd/pm7-parity-matrix-green.log`: 25 passed (16 density/direction/timer cases and 9 held-write/fallback cases) in 49 seconds. This reviewer did not rerun tests or independently certify that log.
- Root independently inspected the three final PNGs and recorded `.superpowers/sdd/pm7-visual-qa.md`; this reviewer checked the corresponding renderer/test source, without duplicating root's visual inspection.
- Named contextual reads were limited to: canonical host launch admission versus pending retry and typed fallback; Today lifecycle/early return cut off by diff context; genuine journey review construction; existing Adventure mission double-tap handling; bounded diagnostics and owner/route callback lifetime. No additional production caller or broad repository exploration was used.
- No Flutter, Dart, pub, format, generator, build, or test command was run; no source/test/portable-document, Git, index, or branch mutation was made. The sole write is this advisory report. No reviewer-owned process remains.

# Assessment

**Task quality: Needs fixes — I1 only within the reviewed scope.**

The composition and renderer keep source lineage and canonical authority intact, and the corrected parity fixture exercises real durable behavior. Close the required owner diagnostic lifecycle gap, then include the fixed snapshot in root's final PM7 review and verification.
