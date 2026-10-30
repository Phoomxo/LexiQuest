# Wave12: owned Dictation and projection isolation

2026-10-30. Application source `bfa766b331776cb809776f2d2cbb7197c254f8b7`,
branch `codex/remaining-system-readiness`, existing cycle12-release worktree.
Core `e6996b1a`; Thai hub `b86bbb6c`; explicit lifetime guards `bfa766b3`.
The full regression, analysis and normal APK checks below pass on this source.
This checkpoint does not
declare production readiness, physical UAT or research efficacy.

## Implemented behavior

The real quiz-gated learning hub selects an owned vocabulary category and one
actual word/revision, then opens Dictation. Empty or missing dependencies create
no session. VoiceUseCases supplies normal/slow playback. A successful current
playback request enables input; engine success is not proof that a learner
physically heard the audio. The target and correctness appear after save ACK.
The UI explicitly finishes and returns the canonical stored summary.

One original process handle binds owner, session, word/category/revision and
start time. The existing canonical writer performs start/save/finish under the
actual owner/deletion-fence transaction, rejects ambient outer transactions and
rechecks database facts plus final visibility. The native ID prefix closes
generic start/save/finish bypasses, including through a new repository object.
Copied/restarted handles cannot adopt a bare session. No new learning writer,
mode registry, package, schema or Research authority is introduced.

The answer and close intents freeze before awaits. Lost ACK retries keep their
original identity, evidence and timestamps. Correct/wrong input uses the existing
trim/case comparison; raw typed input is not persisted. Clock rollback is
rejected before a close intent is captured, so correcting the clock permits a
real retry. A valid captured close stays immutable. Interrupted sessions remain
unfinished and have no durable restart/resume offer; the source records this
limit with a shortcut comment.

Slow playback marks assistance before its first await, including failed
requests; later normal playback cannot clear it. The existing eligibility
policy applies only to current declared Dictation. Normal independent recall
can update SRS. Assisted guided practice retains session/history but does not
update mastery/SRS. The current false engagement flag denies XP, coins,
achievement, Quest and Streak for both. Other ordinary/inferred evidence retains
its compatibility behavior. The canonical projection gate is shared by learning,
reward/progress readers and optional hooks; no second reward authority is added.

Malformed native answer metadata cannot revive native-only session carry as XP
or coins. Genuine mixed ordinary and independent legacy carry remain valid.
New/replayed ineligible answers read an existing SRS state rather than rebuilding
older eligible facts over a newer remote baseline. Actual SyncStore uses retained
metadata after immutable replay reconciliation, preserves natural-key aliases
and the independent remote baseline, and still rejects Assessment declarations.

Owner null/error/done/A-to-B-to-A, route cover, lifecycle, dependency replacement
and disposal invalidate the pending screen epoch. Late continuations do not
reveal private feedback or navigate for a replacement owner. Retirement stops a
shared voice only once; an obsolete Hybrid stop cannot tail-cancel newer native
speech after awaiting the player. Default-owned disposal and shared service
ownership remain unchanged.

The new hub entry follows the existing Thai copy and Quiz/category/due-review
priority. Its actual 320px/200% route is reachable by scrolling and tapping its
visible label. The directly supplied Dictation screen still supports English.
The existing hub golden passes unchanged; no reference image was regenerated.

## Current-source evidence

Evidence root: D:/LexiQuest-Storage/maintenance/2026-10-28/remaining-systems.

| Check | Result | Evidence file |
| --- | --- | --- |
| Full Flutter | 3350 pass,10m22s | wave12-full-flutter-final.log |
| Analysis | No issues,13.0s | wave12-final-analysis.log |
| Windows PowerShell5.1 CLI | 23/23 suites; all logs inspected | wave12-final-cli-results.json; wave12-final-cli-manifest.json |
| Learning/sync regression | 377 pass after SRS correction; final full suite includes later UI/clock changes | dictation-final-learning-sync-regression.log |
| Final UI/voice/layout | 243 pass after the final lifetime guards | dictation-verified-ui-voice-green.log |
| Final hub/layout | 27 pass, including unchanged goldens and actual Thai200% entry | dictation-hub-final-green.log |
| Actual SRS/sync/bypass/carry boundaries | 25 pass | dictation-srs-gateway-carry-green.log |
| Clock recovery and immutable ACK retry | 2 pass | dictation-clock-rollback-green.log |
| Frozen source | All661 Dart hashes unchanged through suite/analysis/build | wave12-frozen-dart-source-final.json; wave12-source-verification.json |
| Normal debug APK | Build passes,119.2s; compiled kernel contains current build ID | wave12-normal-debug-build.log; wave12-normal-debug-apk-manifest.json |

The first full run at e6996b1a passed3348 and failed one hub golden. The new
English-first tile changed a Thai screen. All661 hashes matched that run.
The correction changes only ChooseMode and its tests: Thai copy/default launch,
entry placement and actual large-text proof. Original golden references remain
unchanged. The full suite reruns on the final frozen snapshot; component passes
are not substituted for that result.

The hub-corrected b86bbb6c suite passed3350. Analysis then found nine lint
items: two custom post-await visibility helpers did not expose their existing
mounted guard to the analyzer, and unused callback/import/null-assertion syntax
needed cleanup. Explicit mounted checks preserve the stronger original owner/
epoch/route guards. Independent review found no functional change. Analysis and
the243 UI/voice/layout checks pass before the final full regression is frozen.

Behavioral REDs preceded the projection, generic-bypass, corrupt-carry,
remote-baseline, voice-retirement, clock and hub corrections. The first two SRS
probes failed fixture setup because the immutable wire revision was5; correcting
that fixture to the actual revision1 exposed two real data regressions. Setup
failure is not counted as a demonstrated product bug. The old owned-voice test
expected two native stop calls; it now checks the actual stop after removal,
while existing factory tests check resource disposal. The generation guard
intentionally coalesces obsolete stop work. No test was skipped to obtain green.
Independent reviews accepted the core, voice/clock and final hub changes.

CLI ran at b86bbb6c: all1053 tracked-text snapshots and all54 CLI hashes match
through that run. The final three-file lifetime/lint delta changes no CLI or
backend input. Fresh offline CPU suites at b86bbb6c pass AI186/Voice64/LM140,
with one existing opt-in Firebase/OmniVoice E2E skip. All92 backend hashes match;
current-worktree import origins are asserted, existing Python3.11.15/pytest9.1.1
are used, and the socket audit reports113 internal Windows loopback pairs with
zero denied external calls. Logs/JUnit are inspected and hashed in
wave12-backend-manifest.json. No installation, download, GPU probe or live
credentials are used. Prior
Firestore45/Auth3/Hosting15 evidence remains separate; current static CLI policy
checks pass and policy source is unchanged.

## Artifact and remaining work

Normal lib/main.dart, debug1.0.0+1,
build ID bfa766b3; no installation or publication is authorized by this card.
The normal debug output replaces the prior normal APK; signed field baselines
remain separate.

- Path: C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest/build/app/outputs/flutter-apk/app-debug.apk.
- Bytes:251940493; SHA:`a257b9930f57012f3830fada164f969b3b7eb428ec13b4e15f8a9c964ea9e63d`.
- Lib tree:`23700ca6e6168b8994ee42e3306fcb6063295785`.
- Test tree:`21f4253222965136a769b22de87ec5a5630dc770`.
- Android tree:`c9abd4fd1187a4af13b306f1f077127f96884bac`.
- Dart manifest SHA:`5513a402146414f3fd5f80d5718284c269ec2acc5d2c6b01981f86bb9faf0b1d`.

Gradle used process-local Xmx3G/workers2/daemon=false and restored the prior
options. Existing future KGP and SDK XML3/4 warnings did not fail this build;
dependencies were not changed to suppress them. Post-build verification also
matches54 CLI inputs and92 backend sources; there are no untracked Dart inputs.

Schema remains18/35; v19+ is unreserved. Frozen8/44,
EvidenceContext/EventEnvelopeV2 and Research default-off remain unchanged.
Capability coverage remains10 connected/19 partial/15 missing: f13 improves,
but Cloze/Scramble/shared lesson shell and the other queued capabilities are
still incomplete. Cloze's grounded next card and shared native lifecycle design
remain plans until their own implementation and verification.

Physical-device audio/TalkBack, native dark200%/gestures, live service operation,
signed field-release checks and human UAT remain release work. Production
Research gateway/lifecycle, collection/upload and the existing approved external
authority artifacts remain separate. No enrollment, real data upload, deployment,
instrument validation or efficacy is claimed.

Both pre-existing critique files remain untouched. Automatic approval rejected
removal of the four task-generated hub feedback PNGs, stating `blocked by policy`.
The command did not execute; files remain in test/screens/failures with verified
evidence copies on D. No retry or reclaimed-space claim was made. Earlier denied
emulator/preview/worktree cleanup likewise remains unperformed.
