# P8 Bounded Production Hardening Evidence

## Status and evidence boundary

The local Checkpoint C gates were run sequentially against immutable Task 8
implementation commit `b854c63a4eb7e77f6f7f622d0b7924bbef22a29f` and are
recorded below. Overall Task 8 acceptance remains blocked-external because the
current centrally funded Firebase baseline has no owner-controlled billing or
no-billing evidence proving the 0–100 THB/month target.

The implemented evidence boundary is host/widget/SQLite/file-backed and
fake-provider evidence. It does not claim a live provider request, a physical
camera or microphone result, a signed field build, a provider price, a free
tier, or field certification. Schema remains 12; no generated Drift source or
migration was changed.

MaxPlus/Claude advisory review was unavailable after repeated `invalidKey`.
That unchanged external failure was not retried or reconfigured. Local
read-only adversarial review supplied actionable evidence; every accepted
finding below was converted to a regression test and production fix. This is
not described as a specialist pass. Codex Security was not invoked, installed,
resumed, or recommended.

## Durable runtime controls

- `RuntimeFeatureControls` is the only product mutation authority for feature
  overrides. Permanent emergency-off rows survive file close/reopen; clear is
  separately reopened and restores the immutable build state.
- Expiry uses injected UTC time with strict active-before/exact-expiry
  semantics. Bootstrap initialization schedules restored TTL rows. Early,
  cancelled, stale, replaced, cleared, and disposed callbacks are generation
  fenced.
- Accepted writes are serialized without dropping a different feature's
  command. A committed kill applies live before a later blocked operation.
  Rejected or failed reload paths converge durable and live state fail closed.
- The production `MainNavigationScreen` journey proves the exact
  `drawer/ai-tutor/chat` entry, a live mounted route, direct invocation,
  permanent restart, and clear/restart. AI Tutor's nested provider-settings
  route carries the same live gate and is replaced immediately on emergency
  off.

## Schema-12 owner lifecycle authority

The frozen manifest is exactly 31 tables:

- root: `local_owners`;
- 25 direct owner tables: `research_consents`, `vocabulary_categories`,
  `vocabulary_words`, `vocabulary_imports`, `learning_sessions`,
  `answer_attempts`, `srs_states`, `reading_progress_entries`,
  `reading_events`, `points_ledger_entries`, `achievement_unlocks`,
  `reward_transactions`, `owned_reward_items`, `equipped_reward_items`,
  `outbox_operations`, `sync_checkpoints`, `sync_conflicts`, `events_v2`,
  `quest_instances`, `streak_states`, `learning_day_log`,
  `association_records`, `associative_memory_states`, `ai_usage_events`, and
  `speech_evidence`;
- transitive owner tables: `vocabulary_import_rows` and
  `quest_objective_progress`;
- global tables: `runtime_flags`, `model_downloads`, and `quest_definitions`.

The scenario derives the live table set and direct `owner_id` inventory from
Drift/SQLite metadata, couples export and deletion disposition to the same
manifest, and requires a unique exact physical deletion order. Explicit
transitive and speech children are deleted before parents; the owner root is
last. Every physical owner row is individually counted, the shared Task 5 gate
is fenced first, and foreign-key validation is empty after reopen.

Two fully populated owners exercise every lifecycle table. Erasure removes the
target root, direct/transitive rows, credential pointer/intent metadata, current
and pending versioned secure blobs, scoped legacy values, and legacy Gemini
key/consent values. The foreign owner, its case- and wildcard-colliding
credential metadata, secure values, and every preserved global row remain
byte-identical. Runtime credential prefix scans use binary key ranges rather
than SQLite `LIKE`.

## Allowlisted archive and diagnostics

The complete owner archive is reachable through the production
`ExportUseCases` facade and injected artifact store. It resolves the single
active owner inside one coherent Drift transaction. Core export never owns a
screen file picker.

- All 31 entries include a stable alias and explicit export/deletion
  disposition. Personal tables emit only their complete typed allowlists;
  `vocabulary_imports` deliberately omits `sourceName` and every path field.
- AI usage, feature state, successful model transfers, tracked-version window,
  and model state are aggregate/typed diagnostics. Pending AI work is omitted.
  Mixed known/unknown provider costs fail closed to unknown rather than
  reporting a partial sum.
- Credential namespaces are omitted and target-deleted. Feature/download
  namespaces are preserved and emit only their namespace-specific diagnostic
  fields. Gate, cloud-cache, and unknown globals are preserved and omitted.
- Raw owner/Firebase/actor IDs, participant transcripts, event/session/word
  IDs, auth and lease tokens, credential keys/values, opaque payloads, raw
  provider provenance, URLs, local paths, and runtime flag keys/sources are not
  serialized.
- Canonical metadata distinguishes archive schema, algorithm, and database
  schema versions. The manifest digest includes table and runtime-namespace
  policies; deterministic content and artifact SHA-256 values are reproduced
  byte-for-byte for the same snapshot and UTC instant.

## Reliability, bounded counters, and cost

- Existing Gemini transport remains capped at three total attempts inside one
  20-second absolute budget with typed circuit state; the voice remote route
  retains its 30-second outer budget and native/local fallback.
- AI usage recovery is active-owner scoped under the shared lease, runs before
  90-day terminal retention, and preserves recent/pending and foreign-owner
  rows. A pending row older than retention is recovered then purged in the same
  production cycle.
- Download diagnostics retain at most 100 success markers per version and 20
  model versions, use source-authenticated binary key ranges, preserve unknown
  globals, disclose saturation/window semantics, and protect the just-written
  marker under clock rollback. Foreign exact-key collisions cannot impersonate
  an owned marker.
- Model activation writes a deterministic marker bound to the durable,
  monotonic activation timestamp. Callback loss repairs on a verified restart,
  cached opens do not inflate, and a genuine second verified transfer of the
  same manifest increments exactly once. Cross-version cached reactivation
  preserves the original completion marker. A Task 7 UUID marker is
  transactionally replaced on first verified cached open, preserving its count.
- The expanded product gate exposed an out-of-order learning projection defect:
  a later-arriving older attempt left `first_answer` provenance pinned to the
  first-arriving event. The projection now keeps the unlock identity unchanged
  while correcting its source and UTC time only when canonical `(time, id)`
  evidence is earlier. The isolated regression and the complete learning
  repository test file pass without changing the Task 3 expectation.
- `CentralCostBaseline.productionDefaults()` inventories local core,
  participant-funded BYOK, Firebase Authentication, App Check, and the
  build-default Firestore sync surface without naming a provider price or free
  tier. No verified billing-plan or unit-cost evidence is recorded, so the
  assessed central monthly amount is `unknown` and the 0-100 THB/month target
  is not yet demonstrated. Unknown never means free; a known amount above 100
  is typed `outOfBudget`.
- **External acceptance blocker:** unblock only with current, owner-controlled
  evidence for this Firebase project showing either verified no-billing mode
  (known central amount 0) or a measured and budget-bounded central amount no
  greater than 100 THB/month. Historical version-code-9/source-`6a42c9a`
  no-billing evidence is not reused for this source. Budget alerts alone are
  not represented as a hard spending cap.

## OSV dependency triage

The Windows OSV Scanner could not traverse a directory: both `.` and the
literal worktree path were incorrectly resolved to `C:\`. The replacement
diagnostic enumerated dependency files with `rg --files` and scanned all six
literal lockfiles sequentially. `pubspec.lock`, `package-lock.json`,
`backend/lexiquest_lm/uv.lock`, and the Hugging Face `requirements.txt` were
clean (the npm result used the existing documented optional-Storage UUID
filter). The initial two service-lock scans reported these ten deduplicated
advisory groups:

| Locked package | Primary ID and aliases | OSV range / fix | Source-advisory summary |
|---|---|---|---|
| `cryptography@49.0.0` (initial) | `PYSEC-2026-3552`; `GHSA-g6cj-pr64-35w5`; `CVE-2026-69247` | `>=44.0.0,<50.0.0`; fix `50.0.0` | PKCS#7 EnvelopedData decryption can expose a Bleichenbacher oracle through distinguishable errors/timing. |
| `h2@4.4.0` (AI), `4.3.0` (voice), initial | `PYSEC-2026-3628`; `GHSA-6hr6-w5qg-qmwg`; `CVE-2026-71554` | introduced `0`, fixed `4.4.1` | Duplicate Host headers can become an HTTP/2-to-HTTP/1.1 request-smuggling primitive. |
| `torch@2.8.0+cu128` | `PYSEC-2025-203`; `CVE-2025-55551`; `BIT-pytorch-2025-55551` | introduced `0`, fixed `2.9.0` | `torch.linalg.lu` slice handling can cause denial of service. |
| `torch@2.8.0+cu128` | `PYSEC-2025-204`; `CVE-2025-55552`; `BIT-pytorch-2025-55552` | introduced `0`, fixed `2.9.0` | `torch.rot90` with `torch.randn_like` has unsafe unexpected behavior. |
| `torch@2.8.0+cu128` | `PYSEC-2025-206`; `CVE-2025-55554`; `BIT-pytorch-2025-55554` | introduced `0`, fixed `2.9.0` | `torch.nan_to_num().long()` can overflow an integer conversion. |
| `torch@2.8.0+cu128` | `PYSEC-2026-139`; `CVE-2026-4538`; `BIT-pytorch-2026-4538` | introduced `0`; **no fixed event** | A local PT2 loading-handler path can deserialize attacker-controlled data. |
| `torch@2.8.0+cu128` | `PYSEC-2026-2286`; `PYSEC-2026-1856`; `GHSA-63cw-57p8-fm3p`; `CVE-2026-24747`; `BIT-pytorch-2026-24747` | introduced `0`, fixed `2.10.0` | A malicious checkpoint can corrupt memory or execute code through the `weights_only` unpickler. |
| `torch@2.8.0+cu128` | `GHSA-qfhq-4f3w-5fph`; `PYSEC-2025-195`; `CVE-2025-3001`; `BIT-pytorch-2025-3001` | introduced `0`, fixed `2.10.0` | `torch.lstm_cell` can trigger local memory corruption. |
| `torch@2.8.0+cu128` | `GHSA-rrmf-rvhw-rf47`; `PYSEC-2025-194`; `CVE-2025-3000`; `BIT-pytorch-2025-3000` | introduced `0`, fixed `2.13.0` | `torch.jit.script` can trigger local memory corruption. |
| `torch@2.8.0+cu128` | `GHSA-vgrw-7cvw-pwgx`; `PYSEC-2025-193`; `CVE-2025-2999`; `BIT-pytorch-2025-2999` | introduced `0`, fixed `2.9.1` | `torch.nn.utils.rnn.unpack_sequence` can trigger local memory corruption. |

`cryptography` and `h2` are not direct declarations. Both enter the AI and
voice locks through direct `firebase-admin==7.5.0`: Google Auth/PyJWT crypto
pulls `cryptography`, while `httpx[http2]` pulls `h2`. No service source imports
the reported PKCS#7 or HTTP/2 primitives. Because compatible fixed releases are
available and neither transitive is pinned, the bounded disposition was a
lock-only update to `cryptography==50.0.0` and `h2==4.4.1` in both service
locks. No direct declaration changed. The complete AI CPU suite passed 76/76;
the voice CPU suite passed 55 tests with only the explicitly opt-in live
Firebase/OmniVoice E2E skipped for absent credentials. Literal-lock OSV scans
then reported no remaining `cryptography` or `h2` finding.

Torch is different: the voice `gpu` group directly pins both
`torch==2.8.0+cu128` and `torchaudio==2.8.0+cu128` to the explicit CUDA 12.8
index; `omnivoice==0.2.1` also depends on both. Production startup enforces this
exact trio in `runtime_compat.py`, and dependency/runtime tests bind the same
values. Source uses only `torch.float16` directly, but
`OmniVoice.from_pretrained` loads an operator-selected model snapshot; the
default repository and immutable revision are pinned. No reported operation
name appears in local source, yet dependency-internal model loading means
applicability cannot be dismissed from source search alone. CPU tests inject a
fake engine and deliberately do not import Torch; the real Firebase/OmniVoice
test is opt-in. Consequently, Torch is not a safe lock-only bump. A declaration
change must update the paired Torch/Torchaudio CUDA release, runtime guard, pin
tests, OmniVoice compatibility evidence, and a real GPU load/synthesis probe.
Version `2.13.0` would clear the seven fixable Torch groups according to OSV,
but `PYSEC-2026-139` has no fixed event and still needs an artifact-format /
call-path applicability decision. Blindly changing the paired CUDA stack was
therefore rejected. The eight exact primary IDs are time-bounded in
`backend/voice_api/osv-scanner.toml` until 2026-09-11 and are applied only to
the voice lock. The repository-wide root OSV policy contains no Torch exception,
so other Torch locks cannot inherit this disposition. The contract pins that
separation, the optional group, OmniVoice/Torch/Torchaudio versions,
research-spike status, expiry, and exact IDs. The filter does not claim a fix
or safety: remote GPU voice remains release-blocked until a compatible stack
and physical-GPU end-to-end probe exist.

`tool/cli/verify-osv-locks.ps1` is the executable scope boundary. It enumerates
all six dependency files without wildcard or recursive paths and pairs the
voice policy exclusively with `backend/voice_api/uv.lock`; every other file is
scanned with the repository-wide root policy. Any failed literal scan stops the
gate.

## Checkpoint C execution ledger

No concurrent implementation or audit agent was active during this sequential
run. The local gates are complete, but Checkpoint C remains blocked-external
until the current central-cost evidence above exists.

| Gate | Command | UTC | Source SHA | Exit code | Result |
|---|---|---|---|---|---|
| Task 8 Flutter scenarios | `flutter test test/runtime/runtime_feature_controls_test.dart test/scenarios/runtime_kill_switch_journey_test.dart test/scenarios/complete_owner_export_delete_test.dart --reporter compact` | `2026-08-13T04:31:17.7464287Z` | `b854c63a4eb7e77f6f7f622d0b7924bbef22a29f` | `0` | PASS — 20/20 |
| Product completion gate | `powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-product-completion.ps1` | `2026-08-13T04:33:23.7803781Z` | `b854c63a4eb7e77f6f7f622d0b7924bbef22a29f` | `0` | PASS — contract, format, analysis, product tests, Firebase Auth and Firestore emulators, debug APK, model integrity, and diff hygiene |
| Gitleaks | `gitleaks git . --redact --no-banner` | `2026-08-13T04:34:01.6207444Z` | `b854c63a4eb7e77f6f7f622d0b7924bbef22a29f` | `0` | PASS — 562 commits, 102.58 MB, no leaks found |
| OSV Scanner | `powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-osv-locks.ps1 -ScannerPath C:\Users\Phet\AppData\Local\Microsoft\WinGet\Packages\Google.OSVScanner_Microsoft.Winget.Source_8wekyb3d8bbwe\osv-scanner.exe` | `2026-08-13T04:34:24.8480798Z` | `b854c63a4eb7e77f6f7f622d0b7924bbef22a29f` | `0` | PASS — six literal dependency files; one root UUID disposition and eight voice-lock-only Torch dispositions documented above |
| Dependency inventory | `flutter pub outdated` | `2026-08-13T04:34:41.2352431Z` | `b854c63a4eb7e77f6f7f622d0b7924bbef22a29f` | `0` | PASS (inventory) — 34 locked packages upgradable, 11 constrained; retracted transitive `build_daemon 4.1.3` is resolvable to `4.1.5`; no mutation |
| Diff hygiene | `git diff --check` | `2026-08-13T04:34:48.5072682Z` | `b854c63a4eb7e77f6f7f622d0b7924bbef22a29f` | `0` | PASS |

Unbound WIP diagnostics observed before the Task 8 source was committed are not Checkpoint C evidence and did not populate the ledger above. They included a
complete product-gate run, a 561-commit Gitleaks scan, literal scans of all six
dependency files under the reviewed root and voice-lock OSV policies, and `flutter pub outdated`
inventory. These diagnostics guided the lock and policy changes, but their
results are intentionally not claimed against a source SHA. The ledger contains
only the later sequential reruns against the immutable implementation commit.
The central-cost evidence blocker remains external and cannot be converted into
a pass by any local rerun.
