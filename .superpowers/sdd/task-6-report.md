# Task 6 Report — P3 Production Feature Delivery

## Scope and baseline

- Branch: `codex/runtime-convergence`
- Required base: `091ed30a1b602d4c81a258d14197e56a57ab2091`
- Planned commit: `feat(p3): enforce production feature delivery`
- Schema: remains 12; no Drift schema or generated file is changed.
- Scope boundary: Task 6 owns production feature invocation, Quest Status,
  bounded quest reads, game delivery honesty, and the five named media screens.
  AI Tutor/SRS/global voice composition remains Task 7.

The implementation followed the frozen acceptance capsule in ordered TDD
slices. Design was already approved, so brainstorming did not reopen product
choices. All implementation and verification were performed by the sole writer
in the assigned worktree.

## Root causes and repairs

### 1. Production delivery had two authorities

The V2 `FeatureRegistry` and a legacy field registry could both influence UI,
while several screens substituted `allEnabled` or field defaults when production
composition was absent. That made missing composition fail open and made the
delivery inventory advisory rather than executable.

Task 6 adds the exact 15-row `productionFeatureContract`, explicitly enumerates
all feature defaults, removes the production legacy adapter/field dependency,
and routes every production invocation through one shared
`ProductionFeatureGate`. The gate is lazy, listens to live runtime state, and
fails closed for missing, hidden, disabled, or emergency-off state. Entry
surfaces disappear; retained or direct invocations render the common typed
unavailable state.

Fresh `MyApp` journeys now table-drive all 14 enabled/limited rows by the exact
`productionEntryId`, first prove the intended destination is constructed, then
apply emergency-off and prove the same feature becomes unavailable. The hidden
shadow row is absent and direct invocation fails closed. Stable entry identity,
keys, and selection-by-ID preserve a later destination and its widget state when
an earlier entry disappears. If the selected entry disappears, its mounted view
becomes unavailable; the all-hidden Learning aggregate does the same. A
single-entry Profile fallback remains reachable without violating
`NavigationBar`'s two-destination invariant.

### 2. Quest UI gating was coupled to durable quest composition

Quest composition was optional under the UI switch, while the production
bootstrap still carried a shadow reward orchestrator path. This conflated a
learner-facing invocation switch with durable learning projection and left two
possible reward pipelines.

`QuestUseCases` is now required in `AppDependencies` and is always composed.
Quest seed, event projection, reward receipts, reconciliation, and scheduling
remain available when `questV2` is emergency-off. The switch controls only the
Quest Status UI invocation. Production bootstrap no longer constructs or
injects `ShadowRewardOrchestrator`, `_NoopShadowLogger`, or a
`shadowOrchestrator` dependency.

The new read-only Quest Status entry is exactly
`drawer/rewards/quests`, route setting `rewards/quests`. Repository and use-case
reads require a limit in 1..50, reject invalid limits before owner resolution or
SQL, filter by active owner, and order deterministically by start time and ID.
The screen performs one load per dependency identity and renders loading, empty,
all lifecycle states, failure, and missing-dependency states. It exposes no
internal IDs, retry mutation, or reward mutation.

### 3. Game launchers and demo routes overstated production behavior

Game launch could reload on inherited dependency changes and reschedule
navigation on rebuild. Boss Battle supplied synthetic questions/progress and
implied rank/reward mechanics not backed by participant data. Word Scramble
silently chained to another demo, and World Map/CEFR Diagnostic were visible
static production entries.

`GameLauncherScreen` now starts exactly one bounded
`getGameWords(limit: 10)` request, schedules at most one route, passes only
owned words, and distinguishes missing, empty, and failed dependencies. Boss
Battle derives its progress from supplied questions and grants no synthetic
rank, XP, coin, daily, CEFR, or fixed-damage result. Word Scramble completes in
place. World Map and CEFR Diagnostic no longer have production entries.

### 4. Media screens owned shared services and lacked lifecycle ownership

Object Scanner, Shadowing, Speak-to-Text, Dictation, and Phonetic Explorer each
could construct or dispose voice services locally. Missing sibling dependencies
could still trigger camera, microphone, durable quiz, or playback work behind an
unavailable UI. Once composition was shared, ordinary dispose/pause calls also
created takeover races: a stale route could pause/cancel a newer route, a pending
start could complete after backgrounding or disposal, and a covered route could
remain permanently stale after a pushed child popped.

All five screens now resolve injection first and then the runtime scope, render
`MediaDependencyUnavailable` when required composition is absent, and perform no
hidden provider/database work in that state. They do not create, own, stop, or
dispose a shared voice provider. Shadowing persists the actual
`assessment.method`. Speak-to-Text writes learning evidence only when both
session and word IDs exist; neither, session-only, and word-only inputs produce
zero writes. Speak-to-Text intentionally has no production entry.

Camera lifecycle is managed by a controller-scoped, monotonically leased,
error-resilient serialized queue. A newer route supersedes an older lease, its
takeover pause precedes new initialization, stale lease operations are no-ops,
and route cover/pop reacquires safely. App pause, late initialization, route
replacement, and controller disposal are fenced; disposal drains the queue and
closes a runtime that opens late.

Microphone lifecycle is managed by use-case-scoped opaque sessions with a
monotonic lease and per-attempt epoch over an error-resilient serialized queue.
A new session supersedes the old one and its takeover cancellation precedes the
new start. Stale sessions cannot cancel a replacement. Pending starts are
single-entry, callbacks are fenced, pushed-route return reacquires a session,
and use-case disposal drains superseded pending work before returning. The
legacy direct facade remains only for out-of-scope callers pending Task 7.

### 5. Native integrity pins treated host-built output as immutable input

The device gate raw-pinned the three locally compiled
`libtflite_custom_ops.so` files. Their executable content was unchanged, but
the GNU build-ID descriptor records build identity that varies with the
checkout/toolchain path. Raw comparison therefore rejected a clean rebuild
while the AAR and all nine immutable vendor libraries still matched their
exact raw SHA-256 pins. Repinning the checkout-specific bytes would only have
moved the false boundary.

The verifier now applies a narrow, deterministic policy. The AAR and all nine
vendor libraries remain raw-pinned. Only the exact three custom-op ABI paths
use an ELF canonical hash, and only the 20-byte descriptor of the sole
`.note.gnu.build-id` note is zeroed. The parser fails closed for malformed,
missing, duplicate, overlapping, wrong-type, wrong-machine, non-ET_DYN, or
unexpected-ABI inputs. It supports the actual ELF64 arm64/x86_64 and ELF32 ARM
formats, rejects case-mutated or duplicate ZIP paths, and keeps Debug and
Release pin maps separate. Release pins were derived from the stripped output
of the bounded `:flutter_litert:stripReleaseDebugSymbols` native task using the
pinned NDK; no signed release APK or bundle was produced.

## Semantic RED to GREEN evidence

| Slice | Semantic RED observed | GREEN evidence |
|---|---|---|
| Contract/defaults | The delivery contract lived only in test data and production had no exact 15-row executable map; missing default entries could inherit permissive behavior. | `production feature delivery contract is the exact frozen 15-row contract` and `field defaults explicitly enumerate every feature and fail closed` pass. |
| Shared gate | A disabled/missing-scope invocation could construct an enabled subtree, and an already-mounted enabled subtree did not react to emergency-off. | All three tests in `test/runtime/production_feature_gate_test.dart` pass. |
| Navigation identity | Numeric selection changed the selected feature/state when an earlier destination disappeared; selected-off and all-hidden Learning could retain enabled/empty content; one Profile destination asserted or trapped the learner. | `test/screens/main_navigation_screen_test.dart` covers stable identity, selected unavailable overlay, aggregate hiding, and one-entry Profile liveness. |
| Exact entries | Initial route coverage did not invoke every enabled destination before killing it and did not prove set equality with the contract. | `flutter test test/scenarios/production_feature_navigation_test.dart --reporter compact` passed 19/19, including all 14 exact IDs, concrete destinations, and live emergency-off. |
| Quest bound | Status reads lacked the required bounded owner-aware contract; invalid use-case limits could reach owner lookup. | Repository ordering/owner/limit tests and `invalid status limits fail before owner or repository lookup` pass. |
| Quest screen identity | A cached first Future could retain owner A after the mounted screen received dependency B. | `reloads once when the mounted quest dependency changes` passes with no owner-A data retained. |
| Quest durability | UI emergency-off could omit quest composition, and production bootstrap carried shadow construction. | Bootstrap emergency-off reconciliation and static absence assertions pass; Quest remains non-null and composed. |
| Game launcher | Inherited changes could call vocabulary repeatedly and rebuilds could schedule multiple routes. | `test/screens/game_launcher_screen_test.dart` proves one `getGameWords(limit: 10)`, at most one route, typed missing/empty/failure states, and owned inputs. |
| Boss/demo honesty | Boss used synthetic defaults/results; Word Scramble had a hidden follow-on; static World Map/CEFR entries were reachable. | Boss, Word Scramble, and production-entry boundary suites pass with no synthetic/follow-on/demo claim. |
| Missing media dependency | Scanner initialized camera without voice; Shadowing started a durable quiz without complete media composition; Speak auto-played without speech. | Fail-closed screen tests observe zero camera, learning, and voice calls. |
| Shared voice | Outgoing route disposal stopped a replacement route's shared voice. | Replacement tests prove zero outgoing shared-voice stop; no five-screen source owns `createDefault` or provider disposal. |
| Camera late init | A stale/disposed/backgrounded init could reactivate or pause the wrong preview; pending background resume left a spinner; push/pop left a stale lease. | Full scanner widget suite covers serialized replacement, background resume, route return, and stale fencing. |
| Camera in-flight ownership | A parent capture remained active when a pushed child acquired the same controller; because the parent stayed mounted, its late success/error and `finally` could publish stale state or clear another operation's cancellation slot. | Both blocking late-success and late-failure route-cover tests pass. Lease release cancels the exact capture, advances its epoch, and fences result/error/finally by scanner, lease, epoch, and cancellation identity while the child and restored-parent leases remain ready. Download now has an independent cancellation handle; benchmark never shared the slot. |
| Camera disposal tail | In `dispose drains lease initialization and closes a late runtime`, dispose completed while runtime open was blocked (`Expected: false`, `Actual: true`). | The exact test passed after manager close/drain and post-await runtime fencing; combined scanner/speech use-case selection passed 11/11. |
| Speech takeover | A pending route could complete after replacement and globally cancel the current microphone; a pushed route left the parent stale; double tap could start twice. | Shadowing/Speak replacement, push/pop, pending-start, and reentry tests pass with one active owner. |
| Speech disposal tail | In `dispose drains a superseded pending start before returning`, dispose completed before the blocked start (`Expected: false`, `Actual: true`). | The exact test passed after disposal awaited the serialized tail; combined scanner/speech use-case selection passed 11/11. |
| Provenance/IDs | Shadowing hard-coded provenance and Speak lacked a complete nullable-ID guard matrix. | Architecture plus full Speak selection passed 20/20; actual `assessment.method` and all four ID combinations are asserted. |
| Native verifier | Valid locally built custom-op ELFs failed raw SHA-256 solely because their GNU build-ID descriptors changed with checkout path; a marker-only test could not prove per-entry policy, mode separation, or raw-vendor retention. | Canonical-policy behavior suite passes 78/78, including ELF32/ELF64, wrong-machine rejection, build-ID-only equality, outside-note inequality, malformed/missing/duplicate/truncated note failures, exact nine vendor path/hash pairs, mode separation, per-entry mismatch throws, ordinal paths, and duplicate ZIP rejection. |
| Camera/speech contract | The first prescribed gate stopped before Flutter because a tracked zero-byte `visual_pitch_contour_widget.dart` placeholder remained on the explicit obsolete/fabricated-media denylist. | The unreferenced empty placeholder was deleted; the focused CLI contract and the controller-authorized changed-head camera/speech gate pass. No pitch/phoneme replacement UI was added. |

Additional stable inner-loop evidence captured before the final capsule:

- `flutter test test/scenarios/production_feature_navigation_test.dart --reporter compact`: 19/19.
- `flutter test test/architecture/production_feature_invocation_boundary_test.dart test/screens/speak_to_text_screen_voice_test.dart --reporter compact`: 20/20.
- `flutter test test/features/media_practice/speech_practice_use_cases_test.dart test/features/media_practice/object_scanner_use_cases_test.dart --reporter compact`: 11/11.
- `flutter test test/architecture/production_feature_invocation_boundary_test.dart --reporter compact`: 7/7 after ledger reconciliation.

## Ledger and durability truth

The runtime ledger now states that the primary dependency in each feature row
is the exact frozen contract `dependencyId`; supporting composition is listed
separately. `durable: true` means participant state or an output artifact is
backed by a durable subsystem. It is not a claim that every route writes or has
its own restart scenario. Rows cite existing same-file restart, owner-upgrade,
repository, model-file, or artifact evidence and explicitly identify any
route-specific gap. Shadow remains hidden/non-durable; Quest remains durable
and always composed while its learner UI is gated.

## Final verification record

The following entries are completed only from fresh output on the stable
substantive head:

| Verification | Result |
|---|---|
| Consolidated Task 6 focused architecture/gate/quest/navigation/game/media capsule | GREEN, 163/163 in 26.2 seconds across 21 test files |
| Native integrity policy behavior | GREEN, 78/78; existing and rebuilt debug APK both pass mixed raw/canonical verification |
| `tool/cli/verify-device-model.ps1` | GREEN on the authorized changed head: contracts, pinned fixture, 0-change format, clean full analysis, 58/58 tests, debug APK build, and rebuilt APK integrity all passed |
| `tool/cli/verify-camera-speech.ps1` | Initial attempt stopped at the obsolete zero-byte placeholder before Flutter; after the semantic fix, the controller-authorized changed-head run passed contract, fixture, 0-change format, clean full analysis, 91/91 tests, debug APK build, and APK integrity |
| Full `flutter analyze` | GREEN, no issues found |
| Dart format check and `git diff --check` | GREEN, 48 changed Dart files formatted with 0 changes; no whitespace errors |
| Exact staged-package inspection | GREEN, 55 intended paths; cached diff check clean; no progress, schema, generated Dart, or build output staged |
| Non-amend commit and clean-worktree verification | GREEN at prior stable evidence commit `0f81417516c15ea8d09a8843f4de16de69604364`; the worktree was clean before consolidated stable read-only review |
| Stable-review scanner follow-up | GREEN, final focused media/use-case capsule 25/25; two changed Dart files formatted with 0 further changes; full analysis clean. Broad APK gates intentionally retained from `0f814175` because verifier and packaging inputs did not change. |

Gate chronology is retained rather than collapsed. The first device-gate
attempt passed its PowerShell contracts and then could not resolve the script's
internal bare `dart`. A corrected-PATH run exposed 12 Task 6 analyzer findings.
After bounded lint fixes, the next changed-head run reached the raw custom-op
integrity false negative described above. The controller then authorized the
TDD canonical verifier policy; its first stable changed-head device run passed
end to end and reproduced the canonical Debug pins after rebuilding. The first
camera/speech attempt found the obsolete empty placeholder before starting
Flutter; deletion plus a focused contract GREEN preceded the explicitly
authorized changed-head full rerun. No unchanged failure was retried and no raw
checkout-specific custom-op pin was substituted.

### Stable review follow-up

Consolidated read-only review started from the clean stable commit
`0f81417516c15ea8d09a8843f4de16de69604364`. It found one remaining scanner
ownership gap: a capture is outside the serialized lease lifecycle, so route
cover released the camera lease but did not invalidate the capture continuation.
The follow-up preserves all earlier gate chronology and APK evidence. Its scope
is limited to the semantic scanner regression, capture ownership fencing,
focused media/use-case verification, static analysis, formatting, and diff
hygiene; native verifier inputs are unchanged, so the broad APK gates are not
rerun.

## Evidence boundary

All Task 6 evidence is host/widget/bootstrap/SQLite, file-backed, fake-provider,
or debug-script evidence. A host-built debug APK and its native contents were
verified; this does not certify a signed release package, physical camera or
microphone behavior, device performance, network provider, or field deployment.
No row is promoted to `field-certified`.

MaxPlus advisory review remains unavailable after repeated `invalidKey`; no
retry was attempted without changed external configuration. Codex Security was
not invoked, installed, resumed, or recommended.
