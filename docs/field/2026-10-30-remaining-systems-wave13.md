# Wave13: owned contextual Cloze and owner-watch isolation

2026-10-30. Application source `55f9c407c65e2b355c15b0f3bf73dbed213e6d9f`,
branch `codex/remaining-system-readiness`, existing cycle12-release worktree.
The full suite, analysis and normal debug APK agree on this source. This is
local engineering evidence, not production rollout, physical UAT or efficacy.

## Implemented behavior

The existing quiz-gated Thai learning hub offers an explicit typed/three-choice
Cloze variant, then an actual owned category. The application selects a real
word and revision and requests one sentence through the existing ContentProvider
outside SQL transactions. Missing service, insufficient real choices, invalid
content or stale owner creates no session. No invented fallback sentence or
unlinked CEFR example replaces missing owned content.

The bounded parser accepts one whole lexical target in English context and
rejects repeated/missing/partial targets, unsafe markup/controls and oversized
content. It preserves UTF-16 offsets and actual response metadata. The actual
backend's234-character repository/revision identity fits the finite256-byte
metadata boundary; compact provenance retains the frozen120-rune limit. A2 is
a requested generation setting, not proof of grammatical or CEFR validity.

One accepted immutable exercise binds owner, word/category/revision, generated
sentence/gap, variant and ordered owned choices. One shared sealed native
lifecycle replaces the old Dictation-only lifecycle APIs; all actual callers
migrate together. Original typed handles return after start ACK. Start, answer
and explicit finish reuse the canonical owner/deletion-fence transaction and
recheck the actual word/choice/category pins and final caller visibility.
Generic API bypasses, copied/restarted handles and outer transactions are denied.
Answer/finish retries retain original identity and times; raw typed responses
are not persisted. Native restart/resume remains unsupported.

Typed generated context is declared guided practice; selected context is
recognition. Both retain actual session/outcome/history/effort but add no
mastery/SRS, XP, coins, achievement, Quest or Streak eligibility. Current declared
native gates exclude corrupt native-only carry while preserving ordinary/inferred
legacy facts, mixed carry and an independent remote SRS baseline. No second
learning/reward authority, frozen metadata field, schema or Research writer is
introduced.

The UI shows the masked context and owned meaning cue, masking whole target
occurrences in text and semantics. Feedback names the target vocabulary rather
than declaring every other grammatical completion false. It appears after the
real save ACK; explicit finish returns the actual stored summary. Repeated taps,
IME, failed ACKs and back navigation retain their intended behavior. The English
320px/200% keyboard flow is exercised; default entry/copy is Thai. History labels
actual Cloze sessions. WordScramble's unsafe raw-word automatic next-screen edge
is removed; its game is otherwise unchanged.

Bootstrap owns one existing ManagedAiService per configured initialization and
passes it through the application boundary. Factory/configuration failure leaves
ordinary local learning available. Actual MyApp replacement/unmount closes the
old client once, before verifier cleanup; the replacement remains usable.
Later initialization failure closes the allocated client without replacing the
original error. It reuses existing client/provider classes and dependencies.

A production-watch race was reproduced with actual committed B/A owner changes
and deferred watch SQL: the original snapshot-only stream delivered only A and
accepted old pending generated content. The shared watcher now invalidates on
declared owner-table updates before re-reading. Raw reads and invalidations merge
before distinct; broadcast behavior and each listener's initial state remain.
Both upstream cancellations start before either is awaited. Actual no-op owner
writer acquisition publishes no declared update and remains usable. Real ABA,
late listeners, independent cancellation and active-watch database close pass.

## Verification

Evidence root: `D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`.
All results below were inspected; no Flutter test is skipped to obtain green.

| Evidence | Result |
| --- | --- |
| `wave13-full-flutter-final.log` |3633 pass,10m33s, frozen application source55f9c407 |
| `wave13-final-analysis.log` |0 issues |
| `cloze-shared-owner-system-regression.log` |1675 learning/sync/reward/progress/Assessment/Research/UI checks pass on the final production source |
| `cloze-production-owner-natural-red.log` / `cloze-production-owner-natural-shared-green.log` | Original watcher truly RED under real B/A commits; fixed owner/shared/history14 pass |
| `cloze-owner-broadcast-cancellation-green.log` |41 hub/history checks pass, including existing Study teardown |
| `cloze-composition-ui-green.log` / `cloze-runtime-lifecycle-green.log` |134 composition/UI and57 runtime/legacy-bootstrap checks pass before the shared-watch repair; full suite covers their final integration |
| `cloze-core-final-green.log` |118 core checks pass; earlier category and final pre-provider owner races reproduced and corrected |
| `cloze-content-compatibility-final-green.log` |102 bounded content/metadata checks pass |
| `wave13-cli-manifest.json` / `wave13-cli-root-review.json` |23/23 Windows PowerShell5.1 local fixture/config suites; root read all23 logs and verified their hashes |
| `wave13-backend-manifest.json` | AI186 + Voice64 + LM140 =390 offline CPU passes; one existing opt-in real Firebase/OmniVoice E2E skip |
| `wave13-source-verification-final.json` |0/679 Dart,0/54 CLI and0/92 backend input mismatches through checks/build; no untracked Dart |
| `wave13-normal-debug-build.log` | Normal Android debug build passes,122.4s; process-local heap3G/workers2/daemonfalse, previous environment restored |

The first targeted UI failures were off-screen tile-center taps, nonexistent
fixture back buttons and an assertion during a route transition. The replacement
fixture needed its fake widget clock advanced while awaiting widget-started
disposal. An early owner probe incorrectly expected unannounced raw SQL/no-op
updates to publish; it was corrected before any ABA claim. A first cancellation
implementation exposed a real teardown wait, fixed by starting both cancels.
The final natural ABA proof contains no synthetic transition notification.
These failures/logs remain evidence; assertions were not weakened or skipped.

Backend imports resolve to current C sources using existing Python3.11.15 and
pytest9.1.1, with92 unchanged inputs and no installs/downloads/GPU/live credentials.
The offline audit records113 standard-library Windows socketpairs and0 denied
external calls. CLI results are fixture checks, not actual deployment/scanner
runs. Unchanged policy sources retain earlier45/3/15 policy evidence; this wave
does not relabel it as a fresh live policy run.

## Retained artifact

`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest\build\app\outputs\flutter-apk\app-debug.apk`

- Normal `lib/main.dart`, debug `1.0.0+1`, build ID `55f9c407`; not installed or published.
- Bytes251965448; SHA256 `7dec44762f83f0fc8cc28b2b61d6ed427b42b59751b503d0bb430153b12b944a`.
- Actual ZIP kernel identity checked at `assets/flutter_assets/kernel_blob.bin`.
- lib tree `45c800d27f4d61132dcef284621ca72bc4402a0f`;
  test tree `fc9225a4c7f77326273416e7b1288db68e8a6f1e`;
  Android tree `c9abd4fd1187a4af13b306f1f077127f96884bac`.
- APK manifest SHA256 `ae2e01e0277058c1dc63b93228a21979b1374309d285390794faa98e17a480a3`;
  frozen Dart manifest `ddee02a12c4e388ad1847b1b2e63bbf76012bbea6d7d6a3b8608605908d70a07`.
- Final source proof SHA256 `ca5590266f826170f4cf116e0fe879cc7189a031a5f77998b5da8b9049d6e83e`.

Existing future-KGP and SDK XML3/4 warnings remain; dependency/toolchain upgrades
were not mixed into this feature change. The same output path replaces wave12's
debug APK; no second full APK copy was created for this checkpoint.

## Readiness and next work

Independent content/core/UI/composition/owner reviews are accepted. The frozen
catalog remains8/44 with contract digest
`41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`.
Schema remains v18/35 tables; v19+ is unreserved. Local runtime coverage is now
11 connected /18 partial /15 missing after connecting f09. Native integration,
shared shell, durable recovery, broader accessibility and the other matrix
entries remain partial/missing; this is not whole-system readiness.

Continue [canonical Quest integrity](../superpowers/plans/2026-10-30-quest-integrity.md),
then the existing remaining-feature sequence. Quest prototypes on D are excluded
from this application source/APK. No recurrence, grants, bootstrap activation,
Pair Matching task, real research enrollment/upload or deployment is authorized
by this checkpoint. Research remains default-off. Real service availability,
content/efficacy validation, trusted production authority and physical UAT remain
separate dependencies.

SentenceService/Model were removed only after zero-caller proof and exact blobs
already present in pushed1821e741. No net reclaimed-space claim is made for this
feature wave. Previously rejected emulator/preview and four feedback-PNG cleanup
remain rejected by automatic approval (`blocked by policy`), retained and not
retried. The two pre-existing critique files and untracked feedback PNGs remain.
