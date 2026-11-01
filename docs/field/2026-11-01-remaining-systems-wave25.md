# Wave25: packs and Research transport in progress

## Current checkpoint, 2026-11-01 (active)

This section supersedes the initial grounding notes below. The all-feature
implementation remains active on the same worktree/branch/HEAD; no completion,
deployment, real payment, enrollment or real-data upload is claimed.

### Current integration gate

All source writers are stopped. The first frozen source v2 is1194files/877Dart at the same
baseline HEAD, `D:/LexiQuest-Storage/maintenance/2026-11-01/wave25-verification/frozen-source-v2.json`.
Current analysis0issues in13.5s. The first analysis80style/warnings and subsequent
single wrong-cast correction in a bootstrap test are preserved in separate logs.
Only that test differs between frozen v1 and v2; production/CLI/backend inputs
are unchanged. No tests or guards were weakened to satisfy analysis.

- Current offline backend563PASS/one existing opt-in skip,107source hashes
  unchanged. Manifest SHA256 `2f62ebc333bbd6789cca8ec54665b63e08e337b8f35c595c83bca8dd1c1fa82d`.
- CLI23/23PASS on frozen v1, before the bootstrap-test-only cast correction.
  Summary SHA256 `212e2a63833efdb157b6d6b4136b22fb0312da32d5f52e044affd380056e71aa`.
- Full Firestore rules emulator52PASS/0skip. Log SHA256
  `326d14f529243a2b17d4472b49addb8e90e023377360e117ce62bf6b3f93f2ab`.
- Current schema/migration/export/owner/time/SRS/bootstrap consumer bracket279PASS,
  `schema23-current-consumers.log`.
- Whole voice207 plus pack UI19 =226PASS,39s,
  `voice-and-pack-final-subsystems.log`. Both independent UI voice P2s and the
  shared native cancellation7RED-to-GREEN are accepted. Four independent UI
  canaries and eight native canaries remain unchanged. The two accidental table
  literals from test-helper extraction were restored, with exact assertions kept.
- First full Flutter regression completed5071PASS/9FAIL,13m35s test time, with
  all1194inputs unchanged. Receipt/log remain in `wave25-verification/`; logSHA
  `0f02fd6f0cf9dc40f694f11dbe0fe1905f19a304baaa59632c54fdab733fa68e`.
  Every failure was traced to latest-schema/count or missing pack fixture data.
  The reviewed8file correction preserves every exact row/snapshot assertion and
  supplies an actual codec/canonical-install pack only in the owner inventory
  case. All200cases in the eight corrected files now pass, including all9prior
  failures (`wave25-fixture-corrections-focused.log`). Current re-analysis and a
  new frozen full regression follow; no green full-source or APK claim yet.

The next native-resume and Quest initial RED patches are ready on D only, with
39/27input hash receipts. They have not been applied, compiled or run. They may
not modify the frozen repository or run Flutter. No migration beyond23 or Matching
implementation has started. The all-feature program continues after this checkpoint.

- C1 storage and bounded HTTP: `pack-transport-storage-boundaries.log`52PASS
  (23download,22storage,7scope). Actual canonical-word bridge bracket37PASS.
  Raw-meaning corruption was observed RED and fixed at the content fingerprint.
- Independent actual installed-merge/export/deletion/retry tests now9PASS,
  `pack-independent-lifecycle-final.log`. Two prior deletion baselines were
  corrected after source activation; exact bytes/SHA assertions remain.
- Pack catalog/import/action UI now9PASS, `pack-ui-actions-view-scroll.log`
  (SHA256 `af55f4dc40b3484b91b2ba77cebf028c9c08506be8e2e3ec6d1d4bbfb2ca4a24`).
  Covers canonical SRS completion, voice/save/report, exact immutable retry,
  owner A-B-A, cache-only install/remove, 320px/200% text/IME/light/dark.
  Seven new action tests exposed a real 200% text
  dropdown overflow, corrected with expanded width. Their initial teardown
  masked failures; bounded advancing FakeAsync disposal now closes correctly.
  SRS reaches canonical answer ACK; a fixture referenced nonexistent
  `answer_records`, corrected to the actual `answer_attempts`. View scroll resets
  only on actual catalog/detail/card transitions; acknowledged writes remain visible.
- Research AI backend359PASS, then independent49PASS on unchanged reviewed
  inputs. Purpose-specific operation validity and contradictory completion graph
  fixes accepted. Actual Dart archive golden was accepted by the Python endpoint.
- Current existing client/composition gate67PASS,
  `research-current-composition-gate.log`: HTTP16, consent10, archive31,
  AuthorityUI5, ArchiveUI2, composition1 and bootstrap2. These overlap prior runs.
- Explicit local participation activation is implemented: current
  cache refresh alone does not import issuer-signed assignment/participation
  rows. A fresh unadmitted SQLite fixture observed the missing action RED before
  implementation. Configurable HTTP factory and explicit activation now pass;
  no read/refresh or ordinary learning action may silently enroll a participant.
- Independent client canaries observed2PASS/3FAIL: configured-but-unavailable
  lazy Assessment downgraded export to Motivation-only, and retained acceptance
  callbacks survived changed notice/owner A-B-A. Both P2 root causes accepted;
  corrections now pass all5 unchanged independent canaries and independent source
  recheck accepts them. Bracket18PASS includes activation, actual bootstrap writer,
  AuthorityUI and a narrow build-metadata fix preserving `1.0.0+1` exactly; no
  authority identifier format was broadened.
- Configured real HTTP factory/UI5PASS, no construction-time requests or SQL
  writes. Activation11PASS after correcting the intentional withdrawal setup's
  GET-count baseline; no guard was weakened. The third independent P2 had2actualRED
  at questionnaire withdrawal. The shared same-authority correction now passes
  both unchanged online/offline canaries; independent recheck accepts all3 P2 fixes.
- Whole current Research/consent/Assessment subsystem1022PASS, exit0,6m44s,
  `research-complete-subsystems.log`. This includes the old Study UI/withdrawal,
  signatures, owner/assignment isolation, before/after linkage, projection
  isolation and current archive/upload/activation cases. Actual bootstrap,
  Settings/Export entry and registered identity bracket8PASS separately.
- Registered identity adapter3PASS after observed RED; reuses the actual registered
  owner binding and retires token acquisition across auth A-B-A. Existing identity
  binding7PASS after3actualRED: failed/closed observers stay retired and a local
  guest row cannot masquerade as a registered account. Firebase production
  configuration now uses the real adapter; no live Firebase call was tested.
- Actual Firestore emulator7PASS for all four billing and three Research
  server-only namespaces, across registered owner/foreign/anonymous/unauthenticated
  reads/create/update/delete. No production service was accessed.
- Latest-schema test assertions are aligned to23/43 in27bounded files while
  historical captures, old-row equality and DDL checks remain. Current full
  regression/analysis/CLI/backend-policy/build attestation is still pending.

Independent pack voice bracket1PASS/3actualRED found two presentation P2s: a late
canonical-word read can start audio after Back, and a native start acknowledgement
was mistaken for playback completion. Pack presentation correction is underway.
A bounded shared native-provider cancellation review is also underway. No live
TTS or physical device was used. The read-only inventory of one stopped-run temp
found161028617bytes; its exact-target cleanup was denied by automatic policy
(`blocked by policy`). It remains intact and must not be retried through another
mechanism. No freed-space claim is made.

Current writers are pack presentation/tests, a bounded native-voice worker and
Root shared composition/checkpoints. Research and schema writers have stopped;
independent Research review is bounded ACCEPT. A separate L1 reader is grounding
the next lexical lesson unit without source edits. Flutter/pub/codegen/build remain one
Root-controlled lane. No schema beyond23 is reserved. Initial Wave25 notes below
are retained as historical decisions, not the current task board.

## Initial Wave25 grounding (historical)

Worktree `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`, branch
`codex/remaining-system-readiness`, baseline HEAD
`7c2a02393bb4fd600f2968c5996ce8cdf7773c2f`. Implementation remains uncommitted.
Preserve the two pre-existing critique notes and `test/screens/failures/`.
All44-capability completion stays active. Published16Connected/18Partial/10Missing
is not promoted from focused checks. No real purchase, deployment, enrollment or
Research upload has occurred.

## Prior integration evidence

Wave24 first full4886PASS/26FAIL,11m44s, frozen1137inputs unchanged. The26cases
were stale latest-schema/table assertions, corrected without removing old-row or
DDL checks. Corrected cases194PASS, analysis0; final profile/caller14PASS includes
actual RED-to-GREEN hydration and failed-reload immutable retry checks. Earlier
325focused Flutter, backend477PASS/one existing opt-in skip, CLI23suites with one
observed navigation RED then focused recovery PASS, and four actual Firestore
billing-denial emulator cases remain recorded. These overlap, not additive totals.
Full current-source re-attestation and APK are pending as the program continues.
Billing stays default-off; see `docs/runbooks/billing-readiness.md`.

## C1 actual state

Root captured genuine22/41 before editing:68syntheticrows, all67old rows retained,
FK/integrity valid. Capture records uncommitted Wave24 and generated-source hash.
`tool/capture_schema_v22_test.dart`1PASS; hashes/reservation in schema ledger.

Schema23/43 adds `learning_pack_versions`, `lexical_content_snapshots` and one
owner/word lookup index. Expected23/actual22 RED preceded reservation. Normal
build_runner ran with both Dart workers paused, exit0/65s. Populated22-to23/reopen
retains every old row and exact DDL; two new tables empty. No later schema reserved.

Owner inventory puts parents before children for reverse purge. Category/word
merge remaps new FKs before deleting collided parents and keeps original word
revision/content pins. Equal-digest pack parents require identical immutable
metadata and valid cache hashes. Preserve target pin choice, copy missing verified
cache, promote original installation links only when target was cache-only, and
bump an explicit merge mutation revision. Historical lexical rows remain.
Different-digest variants coexist. Merge-conflict metadata references identical
retained media/cache by package SHA, avoiding duplicate blobs and mutable parent
references across subsequent owner merges.

`pack-storage-focused-second.log`64PASS:55codec,6owner-scope, actual canonical
install/replay, populated migration/reopen and cache-parent merge/replay. Prior
fixture const/import compile failures and owner-scope1PASS/5FAIL are retained.
Scope waits for first observation, captures generation before owner read, retires
on observer failure/disposal and rejects another runtime's scope. This is initial
storage evidence: rollback/cache/stale-content/file restart and installed owner
merge/full export/purge tests remain in progress.

## Active writers

- `implement_pack_installation`: pack domain/contracts/codec/application/data and
  neutral tests; expanding actual rejection/retry/storage coverage.
- `implement_research_backend`: AI backend Research/config/HTTP/deletion/dependency
  lock/tests. Default-off preprovisioned UID binding, real signatures, consent,
  withdrawal, refresh/upload and Firestore adapter. Evidence remains provisional
  until Root/independent review. No real issuer or enrollment.
- `implement_research_client`: Research/consent/local Study runtime and Research
  UI/tests. Paired-cache gate, bounded HTTP, authoritative consent mirror and
  dedicated dual-grant upload. Root owns shared composition and Settings entries.
- Root: schema/ledger/owner lifecycle, shared bootstrap/AppDependencies, navigation,
  pack catalog/detail/rich cards/download and integration.

Wire coordination is on D in `research-backend-wire.md`. HTTP signed-cache canary
was RED then GREEN in actual SQLite. Root is currently running one actual R1
synthetic golden emission for backend interoperability. Initial forward-slash
path failed exact Windows parent validation before writing; corrected command
uses the canonical backslash path. The corrected emission passes1case; golden
SHA256 is `b319819f0466d7840326128e9ec9f3700a54822c8c6fa748e316c9386b0dbec0`.
It has been sent to the backend writer for actual wire interoperability.

Expanded pack storage18PASS/one actual stale-raw-meaning defect is under correction
(`pack-storage-expanded-first.log`). Consent/archive first bracket34PASS/one
upload-fixture failure: changing grants without bumping snapshotRevision correctly
triggered anti-equivocation. The fixture now advances revision; Root rerun is active
(`research-consent-upload-second.log`). Coordinator edits overlapped the first
bracket, so it is provisional. No authority guard was relaxed.

Root added optional `AppDependencies.learningPacks`/`studyUploads` and actual local
pack bootstrap construction/disposal. No pack presentation/download yet. Other
Root processes have ended; serialize Flutter/pub/build/codegen.

## Next executable steps

Inspect golden result; send verified path/hash to backend and let client resume.
Finish installed FK/parent merge plus personal export/purge/constraints. Connect
actual pack UI/callers, then review transport/consent/upload. Pause Dart writers
for generation and all implementation writers for repository-wide gates.

Subsequent grounded D designs are `native-resume-next.md` (existing session slots,
no new table) and `quest-recurrence-next.md` (period identity, canonical recovery,
typed XP/freeze receipts and one streak authority). They are not implementations.
Shared lessons/config/hints/Definition, Quest/streak/avatar/companion/share, report
transport/reminders, Today/accessibility and remaining native resume stay open.
Pair Matching follows actual Research engineering completion. Merchant setup,
trusted Research artifacts, device/store UAT and explicit rollout stay separate.
