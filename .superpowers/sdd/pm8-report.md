# PM8 implementation part (a) — finalizer handoff

Current status: the whole-branch correction wave is source-frozen and submitted
for independent review. The final v3 focused gate passed 142 tests and exact
analysis passed; the preceding v2 affected gate passed 1376 tests. All source and
serialized tooling ownership is now released to root. These are distinct source
snapshots; the earlier 971/969 evidence remains historical.
This is not self-approval, whole-PM8 completion, a release artifact, signed G4P
acceptance or a production-readiness statement.

## Current whole-branch correction wave

**Final source is v3**, with exact ten-path before/current hashes in
`pm8-branch-correction-wave-v3-manifest.json` (SHA256
`7ad34c4213face848cce413eff00102112360a856739cdbdf3890a55de853911`), and all 23
current PM8 source paths in `pm8-branch-correction-frozen-v3-manifest.json`
(SHA256 `4e10a9424ddfa8848b6257b69f01f269fed4ced7e70f11f9e16e209fbd156cfc`).
Full bounded wave diff: `pm8-branch-correction-v3.diff` (SHA256
`750f2253b3e165ee87e581ab6f815e465faa89c94321b6e67e8f3a25db274988`).
The final two-file delta against v2 is `pm8-branch-limit-correction.diff`
(SHA256 `0e8847dfe5e24f39f789317d10124ba8d719749e604b7b30f53c68f04ecc4c25`).
It adds only the canonical >64 candidate guard in production and its regression
test/import. Other 21 source paths remain byte-identical to v2.

The close reviewer demonstrated that the bounded candidate query's 65th row
must be treated as overflow: 65 generic candidates could conceal a Pair marker
in the 66th row for a nonreserved session. `pm8-branch-limit-red-20260907T040250448`
proves this with the real query window (65 generic returned, 66 durable rows)
and an unexpected emitted completion summary: 0 pass/1 fail, exit1,
wall7.0066942s. The final guard rejects before classification. The test was not
weakened; it passes in the final gate below.

- V2 covering run `pm8-branch-affected2-20260907T035752491`: **1376 passed**,
  exit0, reporter249s/wall255.817088s, UTC03:57:52.8784393–04:02:08.6955273 on
  2026-09-07. All 1045 lib/test input hashes unchanged; before/after SHA256
  `72c048f341c91ad3b5c0e0ab25f3ce5ca1d8c8791bff1de15b475b9ce04abe41`.
  It selects the exact prior 17 affected entries plus `test/features/voice` and
  `test/voice` (19 entries). Nine inherited Drift fixture warnings remain.
- Final v3 `pm8-branch-final-focused-20260907T040344127`: **142 passed**, exit0,
  reporter43s/wall49.4380382s, UTC04:03:44.5225699–04:04:33.9606081. Exact argv:
  `flutter test --no-pub --reporter expanded test/features/learning/pair_matching/pair_matching_experience_host_test.dart test/features/learning/matching_mode_adapter_test.dart test/features/learning/pair_matching/pair_matching_session_purpose_test.dart test/features/learning/drift_learning_repository_test.dart`.
  All 1045 lib/test input hashes unchanged; both SHA256
  `7aea13e1313474105967c1bed57ca9708325794fccaebbf2e6cc6d919deb4408`.
  This includes final overflow, missing/downgraded/hidden-earlier-Pair, unchanged
  generic legacy, owner close, live/lost-ack retry, UI route, narration and failed
  stop gates. No Drift warning occurred in this selected subset.
- Final v3 `pm8-branch-analyze4-20260907T040514405`: exact
  `flutter analyze --no-pub lib test`, **no issues**, exit0,
  reporter13.1s/wall16.1368197s, UTC04:05:14.4133604–04:05:30.5501801.
- `pm8-branch-format4-*.log`: exact `dart format` repository and host-test only,
  two files/one changed, exit0. The production guard already had brace-compliant
  formatting; only test layout changed.
- As root explicitly directed after the narrow sentinel guard, the 19-entry
  suite was not repeated a third time. V2 1376 is not claimed as an exact v3
  full run and counts are not added together. Root's immediately following full
  default/serial gates on the source commit remain required release evidence.

`pm8-branch-final-handoff-check.json` records UTC2026-09-07T04:06:22.0184702:
all 23 final source hashes match, no trailing whitespace, `git diff --check --
lib test` exit0, seven native status entries retained with empty actual numstat,
and no Dart/Flutter/dartaotruntime process. All execution sessions completed.
Native line-ending advisories are disclosed and their files were not rewritten.
In addition to the earlier missing board read, one manually mistyped affected-log
timestamp produced a read-only missing path; bounded discovery recovered the
existing log and no source or evidence file was overwritten.

**All PM8 source/test ownership and all serialized Flutter/Dart/pub/build/tool
ownership are explicitly released to root.** No further operation is running or
planned by this finalizer. The root owns Git/index, portable docs, full release
checks/artifacts and independent approval; UI source approval does not replace
the close reviewer or final release gates. No stage/commit/dependency setup,
generator/build, scanner, policy execution, deployment, research activation or
other-worktree operation was performed by this finalizer. Top-level PowerShell
wrappers captured native exit immediately after the executable, before hashes
or Git; none declared a helper-local LASTEXITCODE shadow.

Final v3 source SHA256 identities (relative to the exact worktree above):

| Path | SHA256 |
| --- | --- |
| `lib/features/identity/data/drift_owner_upgrade_repository.dart` | `56b94f27dbfa9f301cede70fdc5df76124623afb1211cd1b315f0d0d55606f2d` |
| `lib/features/learning/application/current_activity_evidence.dart` | `422f4a30f4789a31ff1928ed4ae1fd51941a49a412fff44d3a7cdc4afca56e38` |
| `lib/features/learning/application/learning_use_cases.dart` | `6239fe9d02fe0ead89063c7676b36c2caca060639fc7df4eaca37a83a80832cb` |
| `lib/features/learning/data/drift_learning_repository.dart` | `27df9287500eebda29fb45603b190630cace88417f1dcc65ed87eacd64f552af` |
| `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart` | `1e602907fede9caa3246f8c350362250cdccabfb7ee8b8bd25c1dc273b6fbc4a` |
| `lib/features/learning/pair_matching/application/pair_matching_unavailable_session.dart` | `ae52045c62c91a2bcef1711757f286eb933991678021dfe3af9c207ed8ef7c01` |
| `lib/features/learning/pair_matching/application/pair_practice_replay.dart` | `efea99c59257a3d7fba256da99247bbd39d599f4fb123ea9b24aaf20929421f9` |
| `lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart` | `9f0cef206f69b58f24e703d6e001be980d5bcfbdaa0a08f6f0371071e82feac5` |
| `lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart` | `9d723edefe165935edaa38ddf5b9f9a59d262e58d1e0d648ff6d02b04979fa96` |
| `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart` | `e97779f40f135ba2c25d396c79db9bdbbf302a80c12ea11ea905d4c94e634fc6` |
| `lib/features/learning/presentation/unified_lesson_shell.dart` | `ed11e21a4d1fa14b3ec87a1d173dc6a30895653984e092b0887541eb8c731585` |
| `lib/features/voice/application/voice_use_cases.dart` | `2947d049948ed8087e33aeaf0df5841bcaeefe81632bca1536f1728d63a82d3a` |
| `lib/voice/native_tts_provider.dart` | `e0efede3e03edcf62537c74bc4b079eef7eb3658dccf6dafcb190e9f12553f71` |
| `lib/voice/voice_models.dart` | `522a04a6724f310632feb014e171f404a7dc46b03205b388972efea84bd9f505` |
| `lib/voice/voice_orchestrator.dart` | `b86ac384e7570496d820b49f3a22e61169470610b74823e583ce5429363ac611` |
| `test/features/learning/pair_matching/pair_matching_compatibility_rollout_test.dart` | `f3a3bc6e3f4adf622c447bd0e0315245ad57cb2cac883bb898d541503c977c76` |
| `test/features/learning/pair_matching/pair_matching_experience_host_test.dart` | `aabb635e5f10fffe8e583b0f1d7a10112818efa00af4ed9c26a308d0dc758bc3` |
| `test/features/learning/pair_matching/pair_matching_owner_command_test.dart` | `9afc06e41af5ad5e8d864b9e67a76c3ad4a119e8816ad4f81208cb5a13713b50` |
| `test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart` | `f84a3921cf7f774e92ab4985641c5fc4b4ae1f9aca466950cb9f42dabb6fbf63` |
| `test/features/learning/pair_matching/pair_matching_owner_upgrade_test.dart` | `ae90a9a7ce0bc18ee9bf23da57b26f19a03d33d63df5c2dbc95cf52c8feda789` |
| `test/features/voice/voice_use_cases_test.dart` | `fa8983fc9c6354154251827b4d4357cb158c39aa9de3fa2bae63f6c140d2fec6` |
| `test/voice/native_tts_provider_test.dart` | `e51d6a8e702b819cdb666a93dfa178b6aa3c80a7f8522773a8d0a9d5a23a4b0a` |
| `test/voice/voice_orchestrator_test.dart` | `999c57dd43fff0f50b19b8ce663de63bb5d10c49482ab2883dd781121369a7fe` |

The preceding **v2** snapshot is retained below:
`pm8-branch-correction-wave-v2-manifest.json` (ten
paths, SHA256 `26ee30738bdd874a7f7321b6cf9a7874d6fce759b96cea25cb53d68f3f67c91a`)
and `pm8-branch-correction-frozen-v2-manifest.json` (all 23 current PM8 source
paths, SHA256 `671d436da1ae36edad2e9d124fb5e33384d898a3ec19850b82125bc91375f505`).
Full bounded wave diff: `pm8-branch-correction-v2.diff`, SHA256
`fc18c4e7c91b17f77ca3d138ea038349abf91926895e447d77804e115664399b`.
Only repository and host test changed from the initial correction snapshot;
`pm8-branch-classification-correction.diff` (SHA256
`375e77e8c70bc1f28a9f81bc25673bada8d4d54ef64494710cd0d84adfe6eef6`) records that
exact delta. All other 21 paths, including UI/Voice production, stayed identical.

The initial affected run `pm8-branch-affected-20260907T034837852` completed
1371 pass/1 fail, exit1, reporter248s/wall254.624511s, with all 1045 input hashes
unchanged (both manifest SHA256
`ec0208de7bea9fe288b9f78b46ee4e490830b5d7ce7229e4ea0268ef8da7e546`). It exposed
an existing valid generic-matching checkpoint continuation that the first fix
incorrectly sent through the strict adapter-state decoder. The original test
was preserved. The v2 discriminator is inside the same close transaction:
reserved `pair:` IDs always require strict accepted Pair authority, even with
missing/corrupt/downgraded checkpoints; nonreserved matching sessions inspect
the full canonical candidate query for Pair markers, including earlier
checkpoints when the latest is generic. Valid arbitrary generic map state
retains generic-close semantics. No malformed-JSON catch grants legacy status.

`pm8-branch-classification-red-20260907T035418297` selected the preserved generic
fixture and four new corruption controls: 3 pass/2 fail, exit1,
wall7.0769142s. It also demonstrated that missing checkpoints under a reserved
Pair session could previously close through a null snapshot. After v2,
`pm8-branch-classification-green-20260907T035511655` passed 11 cases, exit0,
wall15.0345061s: all four corruption controls, the unchanged generic fixture,
three actual owner-close races and three live exact retry/lost-ack controls.
The exact argv is retained in metadata. `pm8-branch-format3-*.log` records
`dart format` on repository/host-test only, two files/two changed, exit0.
`pm8-branch-analyze3-20260907T035606327` records exact
`flutter analyze --no-pub lib test`: no issues, exit0,
reporter10.3s/wall13.1735888s on the frozen v2 hashes. The final affected rerun
uses the identical 19-entry selection from the preceding run.

The initial correction identities below are preserved historical evidence:

Worktree/branch/HEAD remain `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`,
`codex/pair-matching-pm0-pm8`, `3bdb5f5605e670e8b30628f3f237cd9c0d660ad9`.
The engine/boundary and UI frozen reports found three Important issues. This
wave changes exactly the ten paths in `pm8-branch-correction-wave-manifest.json`
(SHA256 `d6d979f1e11ce1d12804962b49923505e1e2dc644d41a6ef13dcc9a5b86ea798`).
That manifest records every exact path, preserved before-copy, before hash,
current hash, and membership in the prior 122-path branch review. The two Voice
facade paths were not changed in the prior branch packet and are explicitly
marked as additional review inputs. The full current 23-path PM8 working-source
manifest is `pm8-branch-correction-frozen-manifest.json` (SHA256
`6785c321b489f23467d6f9164693e6a0ba93a46b2ec6842fab0bdb0a7dac374e`).
The bounded ten-file before/after diff is `pm8-branch-correction.diff` (SHA256
`3955156c4b3633afc36b43ca4c5e025d2cf6b25fbfece86551122f26088dbec8`).
These identities supersede earlier source hash tables only for the changed paths;
all earlier packets, baseline raw copies, reports and logs are preserved.

1. Ordinary canonical `finishSession` now classifies strict Pair inside its
   existing SQL transaction, reuses the accepted-disposition validator with a
   private option allowing unconfigured accepted Pair, requires the exact
   complete engine and terminal time, and checks the sole active owner again
   after achievement rebuilding. Existing unavailable-session APIs continue to
   require their configuration; valid legacy/no-checkpoint semantics are retained.
   Real recovered-host tests hold the canonical close and perform logout, owner
   switch, or a SQL trigger changing owner activity inside the close transaction.
   They compare session, owner, answer, event, outbox and achievement bytes before
   and after rejection, including pane disposal. A direct incomplete-board
   control rejects generic completion; existing live-owner, exact close retry,
   lost-acknowledgement, genuine merge and replay cases remain selected.
2. The host records whether the route wants interaction and reconciles the exact
   cover pause after busy work settles. An actual observed PageRoute push/pop
   during a held canonical answer verifies that `boardUnavailable` clears and
   challenge/interactive clocks count only the visible intervals.
3. Voice retains its existing `speak` start-acknowledgement contract. An optional
   per-utterance `playbackCompleted` future travels unchanged through the
   orchestrator; the new route-owned `speakUntilCompleted` waits for actual end,
   or confirmed stop before reporting cancellation/unavailable/timeout. Host
   narration holds its exact pause through that wait. If cleanup is uncertain,
   ordinary board actions and cached callbacks are gated, and a dedicated
   bilingual Stop audio and continue action requires a current route-owned stop
   plus owner recheck before releasing the lease. The UI does not invite text
   continuation while playback is still uncertain. Tests separate start, natural
   end, held stop, takeover, late completion, disposal, deadline and failed-stop
   recovery. No guessed duration or new time/reward authority is introduced.

Native completion limitation: flutter_tts 4.2.5 supplies untagged terminal
callbacks. The same `FlutterTtsAdapter` instance withholds natural-end proof for
the remainder of its lifetime after an active utterance is stopped, interrupted,
or errors. Normal naturally completed utterances do not disable later completion.
General start-acknowledgement speech remains available and installed/non-network
voice proof is unchanged. A subsequent completion-required request starts,
obtains a confirmed stop, then reports unsupportedCapability so Pair can show
text fallback and resume interaction truthfully. Replacing the composition-owned
runtime adapter creates a fresh completion capability. Stop failure or deadline
keeps the Pair gate/pause until a later confirmed owned stop or disposal. The
native tests use the real adapter/provider with an injected plugin test double;
they are not physical audio or platform-device acceptance evidence.

Evidence for this wave (all exact argv, executable, cwd, start/end UTC, duration
and native exit are in the corresponding metadata unless stated otherwise):

- `pm8-branch-host-red-20260907T033355332`: 0 pass/4 fail, exit1,
  wall12.4767791s. Three actual close writes changed active to completed; one
  observed route return retained boardUnavailable. Selected host file with
  `--name "queued normal Pair close|covered and returned during accepted write"`.
- `pm8-branch-voice-red-20260907T033439970`: 0 pass/4 fail, exit1,
  wall5.7171178s. New-interface NoSuchMethod evidence only, not the playback bug
  reproduction; selected facade file with `--plain-name "completion-owned narration"`.
- `pm8-branch-narration-red-20260907T033719506`: 0 pass/3 fail, exit1,
  wall10.5858895s. Actual old host released narration after start while the
  provider's explicit end future stayed pending; natural/routeStop/takeover.
  Selected host file with `--plain-name "Pair narration counts no listening time before actual end"`.
- `pm8-branch-voice-green1-20260907T033748894`: 4 pass, exit0,
  wall6.0924119s; same facade selection as its interface RED.
- `pm8-branch-focused1-20260907T034212483`: 114 pass/2 fail, exit1,
  wall49.1739085s. Host file plus full Voice facade/native provider/orchestrator
  files. Close and route regressions, ordinary narration and native completion
  tests passed. Failures: the deliberate additional failed-stop interaction-gate
  assertion, and a fixture's eagerly unobserved synthetic failed future. The
  host gate/retry fix and an eager error observer retaining the same failed
  provider future corrected these; no assertion was removed or weakened.
- `pm8-branch-focused2-20260907T034429021`: 2 pass, exit0,
  wall8.5941374s; host and facade files selected with
  `--name "failedStop|provider failure retains cleanup"`.
- First formatter metadata/log `pm8-branch-format-*`: only the ten wave files,
  10 formatted/10 changed, exit0. First exact analyzer
  `pm8-branch-analyze-20260907T034506831`: exit1, five brace-style infos only,
  reporter13.9s/wall16.7938587s. Five braces corrected in four declared files;
  `pm8-branch-format2-*.log` records 4 formatted/1 changed, exit0 (the exact
  four-file command is retained in the tool transcript; this second format
  log has no metadata wrapper).
- `pm8-branch-analyze2-20260907T034636401`: exact
  `flutter analyze --no-pub lib test`, no issues, exit0,
  reporter11.2s/wall14.1077375s on the frozen source hashes above.
- One read-only guessed board filename was absent; the error was inspected and
  `rg --files` immediately identified `pair_board_view.dart`. No write occurred
  at the missing path and no repeated filesystem retry was issued.

Final affected evidence, final diff/native-status check, no-process confirmation
and explicit source/tool release are recorded in the v3 handoff above.
Root retains independent review, Git/index, portable documentation and all final
part(b) full-suite/policy/local-audit/build/artifact gates. No approval, physical
device evidence, production rollout, research activation or deployment is claimed.

## Historical configured-host task-review correction

`pm8-task-review-report.md` found Important I1: an old configured pane P could
first-bind its unavailable-disposition helper to R after owner merge during
configuration revalidation. The host now supplies a pane-bound callback that
awaits the existing `_checkOwner()` (including sticky invalidation) and returns
the immutable pane `runtimeOwnerId`. Every helper owner check uses this callback;
no helper API, coordinator, repository, configuration or owner algorithm changed.

Two actual-host cases hold protocol revalidation, perform genuine P-to-R upgrade,
then release `SessionConfigurationResetRequired`: committed pending answer and
complete active board with no terminal checkpoint. Before the fix, both fail the
post-merge session/attempt/event/outbox byte comparison because the old pane
writes R acknowledgements/terminal work. Afterward the old pane, including its
disposal, leaves those bytes unchanged; a newly mounted current-R host reconciles
the same saved operation through the same unavailable-configuration path.

- RED: `pm8-host-race-red-20260907T030940709.log` plus metadata, 0 pass/2 fail,
  reporter3s/wall9.8547532s/exit1.
- GREEN: `pm8-host-race-green-20260907T031041249.log` plus metadata, 2 pass/0 fail,
  reporter4s/wall10.0404063s/exit0. Exact focused argv:
  `flutter test --no-pub --reporter expanded test/features/learning/pair_matching/pair_matching_owner_upgrade_test.dart --plain-name "stale configured host cannot first-bind"`.
- `dart format` only host/owner-test: two files/one changed (test only), retained
  `pm8-host-race-format-20260907T031129857.log`.
- Exact `flutter analyze --no-pub lib test` passed, no issues, reporter15.3s/
  wall18.1092873s/exit0, metadata/log prefix
  `pm8-host-race-analyze-20260907T031131371`.
- Current two-file corrective packet `pm8-host-race-correction.diff`, SHA256
  `84003f2164a128259ab004b0eaad8bd197dca39d1684c91344cd7dcde0d344b3`;
  saved raw reviewed bases matched root's original15file manifest before diffing.
- Current15file manifest `pm8-host-race-frozen-manifest.json`, SHA256
  `8a7f1cb96a84ade8f13a48ae03b98b78fa34c4c0c1562cddef061b642eea44d7`.
  Only two hashes supersede the earlier table:
  `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart`
  = `5d7af250f28df63fed82482d03c635764eb5d7824a1e7a8bfa43a70b06027557`;
  `test/features/learning/pair_matching/pair_matching_owner_upgrade_test.dart`
  = `ae90a9a7ce0bc18ee9bf23da57b26f19a03d33d63df5c2dbc95cf52c8feda789`.
  All other13 source hashes remain unchanged. No additional source path changed.

The same17-entry affected command recorded below passed **971/0 failed**, with
reporter233s, wall239.3704179s, exit0, UTC2026-09-07T03:12:45.0243207 through
03:16:44.3947386. Current prefix
`pm8-host-race-affected-20260907T031244596` has `.log`, `.metadata.json` (exact
argument array/executable/time/exit), `.inputs-before.sha256` and
`.inputs-after.sha256`. All1045 lib/test raw hashes stayed unchanged; both input
manifests SHA256 `3271873c56aacfd7666dc6b734e2c7517e5926eed7c6347288fcb856c7764a1e`.
Nine inherited Drift warnings remain visible; no failure/skip result was emitted.
Counts overlap with prior169/185/969 and focused2 and must not be added together.
No full default/serial release result is claimed.

Final `pm8-host-race-handoff-check.json` at UTC2026-09-07T03:17:04.4391992 records
all15 current hashes matched; source diffcheck exit0; native7 actual diff empty;
zero Dart/Flutter/dartaotruntime processes. All15 files have no trailing whitespace.
All execution sessions completed. No source edit followed the current freeze.

**Current source/test and all serialized Flutter/Dart/pub/build/tool ownership
are released to root again.** This finalizer has no running process or pending
write. The current correction changed only host.dart and its owner-upgrade test;
all earlier artifacts/failed logs/manifests are retained. Root owns independent
re-review, whole-branch review and all part(b) local release work listed below.
Fulltask correction re-review remains independent; no approval is inferred from
this implementation report or focused GREEN2. No Git/index/docs deployment,
dependency installation, production activation or other worktree change occurred.

## Previous handoff evidence (before configured-host correction)

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch
`codex/pair-matching-pm0-pm8`; implementation base HEAD
`3bdb5f5605e670e8b30628f3f237cd9c0d660ad9`, accepted PM7 source
`631b518bbb9c79f30b4f7ad4237551cdc09432a1`. Main implementer owns source and
serialized Flutter/Dart commands during part(a); root owns Git/index, five portable documents,
independent acceptance reviews and release part (b). No staging or commit by main.

## Implemented boundaries

- Canonical runtime owner R is authenticated against the complete accepted Pair
  checkpoint prefix and direct inactive historical-owner markers. Immutable plan,
  configuration, game-command owner P, fingerprints and reserved evidence remain
  unchanged. All new captures use R; old pending actor first-write admission is
  restricted to its exact durable reservation. Legacy Matching first writes retain
  their existing current-account actor behavior.
- Real owner upgrade authenticates before category/word changes, preserves all
  accepted lexical pins through the existing tombstone/alias machinery, validates
  destination completion capacity and reauthenticates after rehome atomically.
  Actual research lifecycle still raises ResearchOwnerUpgradeConflict.
- Capacity uses exact encoded R where authenticated callers supply it, preserves
  the historical exact-P default, and reserves the larger of future R occurrences
  and already-frozen envelopes. This avoids retroactively rejecting an admitted
  same-owner near-ceiling state or long-old-actor pending state moving into short R.
- Coordinator, actual host, PM6 shell lease/retirement/effort cap, PM7 unavailable
  disposition and terminal reconciliation bind R once. Pure engine commands stay P;
  no pure engine production changes. Fresh Replay projects only new configuration
  owner while preserving source bytes and the existing deleted-pin rejection.
- Current activity recovery and both first-write/idempotent answer paths verify
  canonical Pair ownership and exact pending actor/context/time/identity. SQL
  millisecond/event-second precision does not round immutable frozen command time.

No schema migration, new authority/table, frozen EvidenceContext/EventEnvelopeV2
change, production navigation/writer default change, real participant data,
deployment, push/merge or Codex Security workflow was performed. Native generated
registrant status entries are pre-existing empty-diff line-ending statuses.

## Test scope

Four new files use genuine canonical starts/upgrades, real SQL assertions and file
SQLite close/reopen for durable pending/terminal proof. They cover bind-new and
merge-existing, category and first-answer word collisions, both directions/densities,
configuration projection and tampering, owner lifetimes/lineage/races, measured and
unavailable elapsed, pending before/after writes and clear acknowledgement loss,
terminal receipts, actual UI/cap/disposition, Replay sinks, export/erasure isolation,
maximum Thai/control owner IDs, immutable P commands and legacy/rollout controls.
Helpers authored disjoint tests/source; only main ran Flutter/Dart. Helper reports
are supplementary, not independent approval.

## Retained development evidence

Logs below are relative to `.superpowers/sdd/`. Failed iterations remain retained;
counts overlap and must not be added into a coverage total.

| Log | Result and significance |
| --- | --- |
| pm8-runtime-owner-red.log | Initial real-upgrade recovery RED at original P==R guard |
| pm8-auth-upgrade-red.log | Invalid preliminary helper API compile result; not behavior RED |
| pm8-auth-upgrade-red2.log | 0 pass/6 fail; actual non/category strict purpose and word-collision legacy fence |
| pm8-integration-first.log | 39 pass/2 fail; fixture compile and bind assertion errors, preserved |
| pm8-runtime-boundaries-red.log | 31 pass/6 fail; host/disposition guards, forced pending actor rewrite and export fixture key |
| pm8-fractional-red.log | 0 pass/1 fail; extra frozen microsecond restriction rejected legitimate exact occurrence |
| pm8-runtime-boundaries-green1.log | 48 pass/2 fail; UI assertions passed but fixture upgrade heartbeat timer remained pending |
| pm8-runtime-command-green1.log | 21 pass/13s; runtime and immutable command focused evidence |
| pm8-replay-clock-red.log | 0 pass/2 fail; invented frozen-after-plan clock floor broke existing Replay parity |
| pm8-replay-config-red.log | Fresh replay after merge RED at original configuration owner binding |
| pm8-owner-capacity-red.log | Real near-ceiling destination merge unexpectedly succeeded; missing atomic capacity preflight |
| pm8-capacity-replay-green1.log | 82 pass/3 fail/69s; missing repository Replay config projection and wrong fixture points table; old Unicode near-ceiling control passed |
| pm8-auth-runtime-green2.log | 56 pass/19s; auth37 plus runtime19, no warnings |
| pm8-owner-races-fractional.log | 4 pass/2s; merged owner races before answer/after answer SQL/after checkpoint SQL and long historical actor fractional retry |
| pm8-owner-cap-ui.log; pm8-owner-cap-ui-green.log | Fixture compile errors from incorrect API names; not behavior RED |
| pm8-owner-cap-ui-verified.log | 1 pass/2s; actual merged configured host cap stops incomplete session under R with original config unchanged |

Independent frozen-auth review `pm8-auth-review-report.md` found two Important
items: malformed present JSON falling through strict classification and historical
merge time preceding destination creation. Both corrections are now present:
undecodable/unsupported present checkpoint state rejects before category remapping,
and historical merge time must be at or after destination creation. The five
regressions first failed in `pm8-auth-review-red.log` (0 pass/5 fail), followed by
`pm8-auth-review-green.log` (169 pass/9s). These older logs do not retain a complete
command/exit metadata record, so the fresh command below is the current gate.
`pm8-auth-review-format.log` records three files formatted/two changed. The prior
56-test snapshot and `pm8-affected-integration.log` (615 pass/229s before the two
auth fixes) remain historical, overlapping development evidence.

On 2026-09-07 the replacement finalizer resumed from the actual persisted source
and read the active contracts/checkpoint/code. A fresh independent review then
found the supported-version continuation of I1 in
`pm8-auth-current-review-report.md`: marker-only legacy1–5 still bypassed shape
validation. The final correction removes the duplicate discriminator and invokes
the existing shared `PairMatchingSessionPurpose.decode` for every present chain;
only a successfully validated legacy chain returns null. Empty checkpoint policy
is unchanged. I2 and codec source were not changed by this correction.

The actual category-only upgrade regression covers legacy markers1–5 with both
truncated outer payload and valid outer envelope/missing legacy state. All ten
failed by returning `OwnerUpgradeResult` before the correction. Five actual
legacy1–5 upgrade/recovery controls and one actual no-checkpoint session control
passed both before and after. Sources are frozen for independent review.

## Current finalizer verification

The first fresh gate below is retained pre-continuation evidence:

```text
flutter test --no-pub --reporter expanded test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart test/features/learning/matching_mode_adapter_test.dart test/features/learning/pair_matching/pair_matching_session_purpose_test.dart test/features/identity/drift_owner_upgrade_repository_test.dart
```

- `pm8-finalize-auth-25690907T094538465.log` and matching `.metadata.json`:
  169 passed/0 failed, reporter 10s, wall 19.8414884s, exit 0;
  UTC 2026-09-07T02:45:38.4673867 through 02:45:58.3088751.
  The filename uses the local Thai-calendar year; the metadata stores UTC 2026.
- Nine existing Drift multiple-AppDatabase warnings originate unchanged
  `test/features/identity/drift_owner_upgrade_repository_test.dart` lines
  917, 1082, 1611 and 1663. No warning suppression was introduced.
- Executable is
  `C:/Users/Phet/AppData/Local/Programs/flutter/bin/flutter.bat`;
  metadata retains the exact argument array and worktree.
- The first affected 17-entry selection passed 953/0 failed, reporter237s,
  wall243.0181078s, exit0. Prefix
  `pm8-finalize-affected-20260907T024722939`; `.selection.txt` and `.metadata.json`
  record exact inputs/argv. Before/after hashes of all 1,045 `lib`/`test` files were
  identical (manifest SHA256
  `60d194d3f789a59e8484c15775b026a18e088e194a03b6621a4886e0e2f08fba`).
  This run predates the supported-marker correction and has nine inherited Drift
  warnings. It is not the final-source gate.
- Historical `pm8-finalize-source.sha256` lists 11 modified production Dart files
  and four new test files before the continuation; its manifest SHA256 is
  `de260e745c565648e2357ca212d38d7fefc0d81d30d58fc68427765aca3452e0`.
  It is superseded by the final frozen manifest below. Root's five portable
  documentation files are outside the source manifest.
- Current `git diff --check -- lib test` passed with only Git line-ending
  advisories. The seven native registrant status entries still have empty actual
  `git diff --numstat` and were not rewritten.

Final correction and verification records (test/analyzer paired metadata retain
argv, executable, UTC start/end and exit; formatter records are logs; counts overlap):

| Unique log prefix under `.superpowers/sdd/` | Actual result |
| --- | --- |
| `pm8-legacy-classification-red-20260907T025314506` | 6 pass/10 fail, reporter2s, exit1; each malformed schema1–5 upgrade emitted OwnerUpgradeResult instead of throwing |
| `pm8-legacy-classification-green-20260907T025356852` | 16 pass/0 fail, reporter1s, exit0; ten corruption rollbacks and six positive controls |
| `pm8-legacy-classification-format-20260907T025411522` | `dart format` identity/auth-test: two files/two changed, exit0 |
| `pm8-finalize-auth2-20260907T025439191` | Same four-file argv as fresh169 above; 185 pass/0 fail, reporter10s, wall16.2246055s, exit0; nine inherited Drift warnings; before only subsequent brace formatting |
| `pm8-finalize-analyze-20260907T025505522` | Exact `flutter analyze --no-pub lib test`: six curly-braces infos, reporter27.7s, exit1; no compiler error |
| `pm8-finalize-braces-format-20260907T025632165` | Six brace-only fixes in identity, Drift learning repository and compatibility test; `dart format` three files/one changed, exit0 |
| `pm8-finalize-analyze2-20260907T025649189` | Exact `flutter analyze --no-pub lib test`: no issues, reporter16.7s, wall19.3766025s, exit0, UTC02:56:49.1967150–02:57:08.5733175 |

The final source affected selection passed **969/0 failed**, reporter240s,
wall246.2079664s, exit0, UTC2026-09-07T02:59:19.5763061 through
03:03:25.7842725. Its prefix is `pm8-finalize-affected2-20260907T025919186`, with
paired `.log`, `.metadata.json`, `.inputs-before.sha256` and `.inputs-after.sha256`.
All 1,045 lib/test files retained identical raw hashes; both manifests are
`b193f074c32a1604df54534245d9320d39e60fa686edd018c4b85202069c1a2d`.
The log has nine inherited Drift warnings and no failure/skip result. This is an
affected selection, with no exclusion flag; it is not the full default/serial
release suite. The overlapping auth185 count is not added to 969.

Exact final command (one invocation; line breaks show argument separation):

```text
flutter test --no-pub --reporter expanded
  test/features/learning/pair_matching
  test/features/identity/drift_owner_upgrade_repository_test.dart
  test/features/identity/research_owner_upgrade_test.dart
  test/features/learning/matching_mode_adapter_test.dart
  test/features/learning/current_activity_evidence_test.dart
  test/features/learning/learning_use_cases_test.dart
  test/features/learning/drift_learning_repository_test.dart
  test/features/learning/unified_lesson_controller_test.dart
  test/features/export/export_use_cases_test.dart
  test/features/account/local_data_deletion_test.dart
  test/scenarios/complete_owner_export_delete_test.dart
  test/features/adventure/adventure_pair_renderer_parity_test.dart
  test/features/adventure/presentation/adventure_pair_experience_test.dart
  test/features/research/research_sync_authorizer_test.dart
  test/runtime/production_feature_gate_test.dart
  test/runtime/runtime_feature_controls_test.dart
  test/screens/matching_mode_screen_test.dart
```

Auth185 was not repeated solely for braces; this affected run includes that entire
selection on the final source. Fresh `flutter --version --machine` exit0 is saved
in `pm8-finalize-toolchain.json`: Flutter3.44.7 stable/framework
`84fc5cbb223bc12f83d65b647ff8a56caf779ffd`, Dart3.12.2. The same executable path is
recorded in every final test/analyzer metadata file.

The exact two-file corrective packet is
`pm8-auth-classification-correction.diff`, SHA256
`d9cec55cf0d892d46f5db317b32557a084bfa9e4e88278d5c8e1633662cd857f`.
Its reconstructed reviewed bases were checked against the original raw manifest
hashes before diffing. One initial reconstruction assumed LF for the reviewed
identity source; the retained scratch failure was resolved by its verified CRLF
encoding, with no production change. One optional analyzer-log read used an
incorrect guessed timestamp and returned no content; the actual path was then
obtained from execution metadata. Neither is test or acceptance evidence.

## Final frozen source manifest

`pm8-finalize-frozen-manifest.json` SHA256
`4fa2bb670fe117c94b8c7294e6614ab02f39adc9aec33373cd148867a9d8d869`.
The auth-only four-file view is `pm8-finalize-auth-frozen-manifest.json`, SHA256
`d71f1e67cb88053d0cb2f8d58bc243f644e1ffc9faf2ec6847c2e713fef37fff`.

| Exact worktree-relative changed path | Raw SHA256 |
| --- | --- |
| `lib/features/identity/data/drift_owner_upgrade_repository.dart` | `56b94f27dbfa9f301cede70fdc5df76124623afb1211cd1b315f0d0d55606f2d` |
| `lib/features/learning/application/current_activity_evidence.dart` | `422f4a30f4789a31ff1928ed4ae1fd51941a49a412fff44d3a7cdc4afca56e38` |
| `lib/features/learning/application/learning_use_cases.dart` | `6239fe9d02fe0ead89063c7676b36c2caca060639fc7df4eaca37a83a80832cb` |
| `lib/features/learning/data/drift_learning_repository.dart` | `5f26066612023bfca8988163b537b70fb451ffe382189b7c2138e0aa5def822a` |
| `lib/features/learning/pair_matching/application/pair_matching_session_coordinator.dart` | `1e602907fede9caa3246f8c350362250cdccabfb7ee8b8bd25c1dc273b6fbc4a` |
| `lib/features/learning/pair_matching/application/pair_matching_unavailable_session.dart` | `ae52045c62c91a2bcef1711757f286eb933991678021dfe3af9c207ed8ef7c01` |
| `lib/features/learning/pair_matching/application/pair_practice_replay.dart` | `efea99c59257a3d7fba256da99247bbd39d599f4fb123ea9b24aaf20929421f9` |
| `lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart` | `9f0cef206f69b58f24e703d6e001be980d5bcfbdaa0a08f6f0371071e82feac5` |
| `lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart` | `9d723edefe165935edaa38ddf5b9f9a59d262e58d1e0d648ff6d02b04979fa96` |
| `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart` | `f0dcbc37c7de040c749fa4c486439c531dfc3eb144df7d0758e2c3dfedb0cec4` |
| `lib/features/learning/presentation/unified_lesson_shell.dart` | `ed11e21a4d1fa14b3ec87a1d173dc6a30895653984e092b0887541eb8c731585` |
| `test/features/learning/pair_matching/pair_matching_compatibility_rollout_test.dart` | `f3a3bc6e3f4adf622c447bd0e0315245ad57cb2cac883bb898d541503c977c76` |
| `test/features/learning/pair_matching/pair_matching_owner_command_test.dart` | `9afc06e41af5ad5e8d864b9e67a76c3ad4a119e8816ad4f81208cb5a13713b50` |
| `test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart` | `f84a3921cf7f774e92ab4985641c5fc4b4ae1f9aca466950cb9f42dabb6fbf63` |
| `test/features/learning/pair_matching/pair_matching_owner_upgrade_test.dart` | `86342e55b9e4562ff76a28da5e348c6c2a6f36cf462faff2553bcbb24d0894b6` |

## Historical pre-branch-review handoff and remaining root work

`pm8-finalize-handoff-check.json` records UTC2026-09-07T03:03:47.9400409:
all15 source hashes match the final manifest; `git diff --check -- lib test`
exit0; all15 files have no trailing whitespace; native7 actual numstat empty;
no Dart/Flutter/dartaotruntime process remains. All execution sessions completed.
Native status paths preserved unchanged:
`linux/flutter/generated_plugin_registrant.cc`,
`linux/flutter/generated_plugin_registrant.h`,
`linux/flutter/generated_plugins.cmake`,
`macos/Flutter/GeneratedPluginRegistrant.swift`,
`windows/flutter/generated_plugin_registrant.cc`,
`windows/flutter/generated_plugin_registrant.h`,
`windows/flutter/generated_plugins.cmake`.

**All PM8 source/test ownership and the serialized Flutter/Dart/pub/build/tool
slot are released to root.** No further source/tool process is planned or running
by this finalizer. Root may execute the next source-frozen release step once its
independent task and whole-branch reviews permit it. No index/stage/commit, global
configuration change, dependency resolution, generator, release build, scanner,
backend policy command, deployment or other-worktree operation was run by this
finalizer. The four newly authored Dart tests remain untracked for root staging.

Remaining executable local work is root-owned part(b): finalize independent
task/whole-branch review; normal source/final-plan generation and source identity;
full default and concurrency-one suites with the four exact release exclusions;
three host-fake journeys; applicable synthetic backend/policy/dependency gates;
verified internal debug APK and actual minimum compatible artifact; portable
SDS/RTM/TestPlan/UAT/status and evidence packaging. These were not run by this
finalizer and are not implied by the 969 passes. Latest reviewer approval, if
issued separately, is authoritative over this implementation report.

Physical UAT, external Product/Learning-Data/UX-Accessibility/QA/Tech decisions,
trusted research authority/provisioning and efficacy remain external NotRun or
pending. Default legacy writer/navigation, research default-off, schema24/48tables,
catalog8/44 and frozen evidence contracts remain unchanged. No real enrollment,
upload, production activation or signed G4P acceptance is asserted.
# Latest composition correction handoff — 2026-09-07 04:37 UTC

The current source baseline is `94c1e97fea5097af144b63adfdf9ab2e5f277bee` plus
the twelve-file composition correction. See
[pm8-composition-report.md](pm8-composition-report.md) for exact changed paths,
raw hashes, retained RED failures and final verification. Focused composition
and host: 51 pass. Final measurement: 17 pass. Analyzer: no issues/exit0.
The retained covering run was 624 pass/8 stale measurement-oracle failures;
only its twelfth test file changed afterward, with all17 measurement cases
verified again. Full default/serial/release gates remain root-owned.
Source and all serialized Flutter/Dart tools were explicitly released to root;
final check found no task Dart processes and preserved seven native empty diffs.
Historical sections below are earlier source snapshots, not current release
approval. This addendum does not assert whole-PM8 completion.
