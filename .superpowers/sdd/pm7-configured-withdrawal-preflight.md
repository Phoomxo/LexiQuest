# PM7 previously accepted configured Pair after withdrawal

## Finding

**Confirmed static gap, P1 integration/liveness:** previously accepted normal Pair with research-pinned configuration can remain an active durable session after withdrawal makes configuration revalidation fail on reopen. Current preservation prevents data loss but does not provide an explicit disposition, so a new ordinary checkpointed canonical start encounters `ActiveLearningSessionConflict`. This is different from a fresh nonparticipant setup, whose actual provider resolves baseline successfully

This is report-only PM7 preparation, not a PM6 final verdict or implementation authorization. No Flutter/Dart/tests/format/analyzer/source/index mutation. Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch supplied by parent `codex/pair-matching-pm0-pm8`

## Exact path

- `lib/features/research/application/assigned_learning_event_context_provider.dart:43–54`: rollout resolver calls persisted current-activity resolution for new capture/config resolution and maps unavailable state to Legacy. `:187–223` rejects missing/ambiguous assignment, missing mapping, nongranted consent or withdrawal; withdrawn consent returns null. These checks correctly prevent continued research authority
- `lib/features/learning/application/session_configuration_policy.dart:112–129`: `PersistedSessionConfigurationProtocolProvider` returns real `catalog.baseline` for Legacy; valid research uses exact catalog binding. A protocol/catalog failure while research remains selected may instead throw resetRequired (`:130–135`, `:48–88`). Do not conflate baseline fallback with permission to reinterpret an accepted research session
- Fresh ordinary Pair setup validates a fresh configuration from these real limits. Previously accepted research config retains its original protocol/limits identity. Reopening host calls real runtime revalidator (`pair_matching/presentation/pair_matching_experience_host.dart:71–79`); policy `:313–318` rejects protocolId/version/limitsIdentity mismatch with staleProtocol. Research limits identity includes assignment/consent authority (`session_configuration_policy.dart:82–87`), so a genuine research binding differs from baseline even if numeric limits happen to match
- Controller `application/unified_lesson_controller.dart:308–316` revalidates **before** attaching session/start state. `_revalidateStartConfiguration:465–475` sets resetRequired and rethrows. This is correct fail-closed behavior; no accepted configuration rewrite occurs
- Pair host binds accepted config/revalidator and sets `preservePreacceptedSessionOnAttachmentFailure: true` (`pair_matching_experience_host.dart:280–281`). It reserves coordinator, then awaits shell attachment (`:411–428`); revalidation failure happens before `_attached=true` or automatic retry/finish (`:430–432`)
- Shell `_initializeSession` records exact loaded owner/session (`presentation/unified_lesson_shell.dart:479–488`), invokes controller start (`:517–523`), and on failure invokes compensation (`:525–530`). `_compensateUnattached:766–770` deliberately returns without abandoning this preaccepted session. Retirement also returns when not attached and preservation is set (`:750–753`)
- Current host recovery error surface offers Retry saved session / Return (`pair_matching_experience_host.dart:629–635`). Retry detaches/rebuilds (`:519–525`) and encounters the same stale protocol if authority stays withdrawn. Generic shell reset prompt only navigates back. Existing cap-specific exit requires `configurationLimitReached` (`unified_lesson_shell.dart:309–313`) and is not a disposition for a planned/unattached controller rejected by protocol revalidation
- Durable row therefore stays active for the incomplete/no-pending minimal case. New ordinary canonical checkpointed start checks owner-scoped active rows and throws conflict (`data/drift_learning_repository.dart:743–761`). Baseline provider success alone cannot resolve this existing active-row conflict

The minimal concrete case needs no race: admit research-configured normal Pair with at least one incomplete pair and no uncertain operation; persist withdrawal; reopen saved operation; observe staleProtocol and no attachment; Return; attempt fresh baseline normal Pair → conflict with original active session. Protocol-unavailable revalidation failure follows the same attachment/preservation path, although temporary unavailability should still offer retry

## Bounded PM7 solution direction

- Preserve immutable accepted config/start/evidence/consent/signature checks. Do not drop config, substitute baseline limits in old session, reclassify it as replay or announce success for an incomplete board
- Add an explicit owner-validated **unavailable accepted-session disposition** for the exact loaded session. Reuse canonical abandon semantics documented in `pm6-effort-cap-audit.md`: retain accepted checkpoints/answers/counts, no Pair acknowledged completion/stars, release active conflict, return truthful stopped/incomplete presentation. A new ordinary session then uses fresh baseline canonical admission
- Do not simply call `controller.abandonAtCutoff` in its current planned/unattached state: `unified_lesson_controller.dart:886–888` only transitions local planned state and does not abandon the persisted loaded session. Existing owner/session-pinned `learning.abandonSession` inside shell compensation (`unified_lesson_shell.dart:779–782`) is the relevant persistence seam, but needs **explicit** disposition distinct from automatic failure compensation, first retained timestamp, accepted-work ordering, and actual loaded owner validation
- First fence new commands and reconcile exact preaccepted work under existing bounded recovery authority. Keep original operation/occurrence identities. No unrestricted callback or research capture after withdrawal. If pending research evidence cannot pass existing collection/recovery checks, preserve it and report the exact denied boundary; do not force a drain by bypassing consent/signature checks or abandon in a way that strands a partly committed write. This preflight does not establish which revoked pending variants reconcile successfully; PM7 must test them
- For a genuinely complete board/accepted terminal, reconcile only through existing valid completion authority and exact receipts where permitted. Never turn rejection into success just to release conflict
- Use existing abandoned row/endedAt as durable retry reconciliation: lost ACK repeats same timestamp; reload abandoned exact owner/session as stopped rather than attempting active Pair restore. No new table/terminal schema required for the no-pending incomplete case

## Targeted real UI acceptance

Extend PM7 `test/features/learning/pair_matching/pair_measurement_boundary_test.dart` with actual research fixture, real persisted rollout provider + protocol provider/catalog + internal Pair host. Admit configured normal Pair under signed synthetic active authority, retain one accepted answer and incomplete board, withdraw through canonical fixture operation, reopen exact accepted start, verify staleProtocol, config/start/evidence bytes unchanged and no new research rows/events/outbox/uploads. Exercise explicit disposition, assert canonical abandoned + retained answer/checkpoints + null stars + no mission-success, then start and complete fresh baseline ordinary Pair without conflict or research artifacts

Separately cover: already nonparticipant fresh start (baseline control); temporary protocol unavailable then restored retry; lost ACK on abandonment with exact endedAt; wrong/current-owner drift; frozen pending before/after answer commit under withdrawal; accepted completed/terminal recovery without duplicate mission events. This is a proposed test matrix, not reported execution

## Snapshot and uncertainty

Read `pm7-contract-refresh.md` provider clarification and real UI fixture requirements, plus PM6 integration brief config/preservation/effort-disposition sections. Host/shell are actively owned by main implementer; this report binds only the captured snapshot. Six SHA256 values matched at start/end of focused read:

| File (relative to lib/features/) | SHA256 |
| --- | --- |
| research/application/assigned_learning_event_context_provider.dart | A6105F56238026CE6BDF0A8D11E7E12B0908283C2D547D838EE21C17EE7334DC |
| learning/application/session_configuration_policy.dart | 19125A5AFE07C5799EE68149E55F23A79CD9712DF263B2EC4963D66EA4507624 |
| learning/application/unified_lesson_controller.dart | 885E80B4D799698ED45B61AE8AC3CCC65E5867C82BC99DD1F00B91ECCC43265A |
| learning/presentation/unified_lesson_shell.dart | 793D7883E50AFE34425BACD9A01F5C46035830B15518D932F6A9EED5DE8364D0 |
| learning/pair_matching/presentation/pair_matching_experience_host.dart | 7D3AE90A3C198A67B5A1A2971C852A3BD056A0D71969C1549654FE15EFFF4692 |
| learning/data/drift_learning_repository.dart | EA4453867125229F1EF5250A05086026441D5AEDB7C633242C064F3B069F10AA |

Only report written; no processes started. Current frontend may change after release and needs refresh before PM7 implementation. No production enrollment/upload/efficacy claims

## Final PM6 freeze refresh: concrete pending disposition design

This addendum supersedes the earlier uncertainty about where revoked frozen first writes fail. It is static design evidence only; no test was run. Focused checks were: (1) frozen replay vs first-write guard, (2) abandoned pending continuation, (3) final shell attachment/disposition seam. No source edits

### Actual committed versus uncommitted behavior

| Durable state at disposition | Existing behavior under revoked consent | Safe action |
| --- | --- | --- |
| Frozen pending checkpoint; answer/source/decision transaction absent | `current_activity_evidence.dart:1203–1205` restores frozen resolved contexts without refreshing providers; this alone is not current authorization. First-write `drift_learning_repository.dart:1650–1683` inserts attempt/outbox/source then requires decision set inside its outer transaction. `drift_learning_event_store.dart:390–397` rechecks persisted rollout and throws when current Legacy differs from frozen research mode. Entire answer transaction rolls back | Do not repeatedly retry or rewrite frozen context to Legacy. Classify exact source as uncommitted, preserve frozen checkpoint unchanged, then explicitly abandon exact session with no new evidence/success |
| Answer transaction committed; ACK or following acknowledged Pair checkpoint lost | `learning_use_cases.dart:1042–1051` first invokes `replayCommittedAnswer`; repository `:1463–1506` validates exact attempt/source/context. `ensureDecisionSetForAttempt:381–387` validates existing immutable decision receipt and returns **before** current rollout admission check | Exact committed replay can reconcile despite withdrawal without granting a new research first write. Append existing coordinator acknowledgement under recovery lease while session still active, then branch complete vs incomplete |
| Existing attempt/source but missing/corrupt required decision receipt or identity mismatch | Exact replay fails or, when decision receipt absent, reaches current rollout check; not equivalent to an authenticated committed result | Fail closed for that corrupt/uncertain case. Do not manufacture decision receipt, declare answer absent, acknowledge it or grant success. Surface precise recovery failure; separate this from the normal first-write-absent case |

The current consent-dependent guard is `PersistedEvidencePolicyRolloutModeProvider.resolve(evidenceContext: ...)` in `research/application/assigned_learning_event_context_provider.dart:105–120`: withdrawn/non-granted consent resolves Legacy. The above is the local canonical decision-set admission boundary, **not proof of permit/signature/upload authority**. PM7 must retain separate research collection/upload authorizers unchanged

Coordinator `pair_matching_session_coordinator.dart:518–575` persists frozen pending, then records/retries, then appends engine acknowledgement. Do not call its unqualified `retryPending` as a general “drain everything” in the revoked-first-write case: denied first write is a valid terminal disposition reason, not a retry loop. The existing replay API can also materialize a missing decision receipt while authorized, so a strict disposition classifier should inspect/validate existing receipt presence before using replay as proof of already-committed state

### Can abandoned sessions retain a frozen pending checkpoint?

Yes for the explicit **never-committed** case, without clearing the pending field or adding a cancellation schema. `drift_learning_repository.dart:2639–2676` canonical abandon changes only state/endedAt; it preserves frozen checkpoint and all accepted historical answers. Strict Pair purpose decoder continues to accept incomplete pending ledger with no acknowledged terminal; it does not claim pending is an answer. After abandon:

- New first-write answer is rejected by active-session lookup (`drift_learning_repository.dart:1601–1610`)
- Pair checkpoint append is rejected for abandoned state (`:922–932`)
- Interactive coordinator restore is rejected (`pair_matching_session_coordinator.dart:298–300`)
- Existing exact committed replay remains historical idempotent reconciliation, not a new answer; no learner continuation is reopened

Thus a retained pending diagnostic does not authorize future continuation. UI must explicitly show stopped/unrecorded pending answer, retain prior accepted answers, and avoid success/stars. Do not delete the frozen checkpoint to make it look fully acknowledged. Generic successful History remains completed-only

### Minimal proposed canonical seam

Add a narrow typed owner/session-bound **disposition of an already-loaded Pair rejected by current configuration**. Keep final shell preservation (`unified_lesson_shell.dart:766–786`) for automatic failures and keep cap-only action (`:319`) distinct. Failed attachment leaves controller planned: its planned abandon only changes local state, so use canonical loaded-session repository abandonment rather than pretending attachment succeeded

1. Explicit user action reserves first cutoff and exact loaded owner/session/start/checkpoint identity. Fence new commands and pause coordinator; await all route-owned in-flight work before classification. Do not dispose while an uncertain write is running
2. Reconcile only exact already-committed pending answers/acknowledgements with existing recovery methods. No new capture, changed source ID, reconstructed research context or refreshed accepted configuration
3. At the final persistence boundary, transactionally re-read current active owner, exact session and latest checkpoint, and validate expected immutable pins plus pending source state. Use the **same Drift database transaction** as existing `abandonSession` (nested transaction/canonical method reuse), so a racing answer is observed as committed before final abandonment or sees abandoned and fails afterward. A UI-only check followed by a write is insufficient; canonical abandon itself currently checks pinned row owner but not current active owner/pending outcome
4. If valid pending transaction is absent and research admission remains denied, leave pending checkpoint untouched and abandon. If completed pending work makes board complete, follow successful close reconciliation below. If another acknowledgement/checkpoint revision changed since classification, reclassify exact state rather than dropping it
5. Retain first cutoff across commit-then-throw; `drift_learning_repository.dart:2648–2652` retries abandoned only at same timestamp. Read back abandoned exact owner/session as stopped after lost ACK, not active restore. Owner drift before action denies mutation; drift during asynchronous preparation requires transaction-bound current-owner recheck. Never retarget to the new owner

This can be a small repository/application disposition method using existing tables/guards and canonical abandon, plus shell/host typed callback. It is not a new evidence authority and must not make generic append or recordAnswer accept abandoned sessions

### Completed terminal path and remaining uncertainty

Already acknowledged completed session must not be abandoned. Exact committed last answer may advance board to complete before disposition; use existing Pair terminal intent/ack/presented receipts only if historical completion identity can be authenticated. Current configuration revalidation prevents ordinary controller attachment even for this recovery, so PM7 needs a narrowly constrained **terminal reconciliation attachment** of exact durable session/config, not a fresh-learning start that bypasses stale protocol. Preserve old configuration and permit only pending/terminal replay, no new command/time/research collection. This seam is not currently proved by this preflight; implement/test it before promising completed recovery after withdrawal. Incomplete must never call success finish

Required focused UI/transaction tests: revoked frozen-uncommitted pending → no attempt/source/decision/outbox insertion, abandoned with unchanged pending bytes and future append/answer rejected; committed-answer lost ACK → exact historical replay and acknowledged checkpoint without new research records; source/decision corruption fails closed; race answer commit vs disposition; wrong owner/drift; abandonment lost ACK same endedAt; complete/terminal replay without new mission/research success after withdrawal. New ordinary baseline start succeeds after acknowledged incomplete disposition. These are proposed tests, not GREEN claims

Final freeze file hashes for this addendum (relative to `lib/features/learning/`):

| File | SHA256 |
| --- | --- |
| presentation/unified_lesson_shell.dart | 24932DE9EB9D1F30858273BC3E0D114E4E2E8DE6C9A22DC02F82BAA0235F25E1 |
| pair_matching/presentation/pair_matching_experience_host.dart | F377E2B6E99800E80A3168BCF4CBEEC985EA4AABA77D0A9866C02D075E9AF9D3 |
| pair_matching/application/pair_matching_session_coordinator.dart | 02BDB24F570B0571645E6F139ED1902247AEDDFD7EBF4DB09A817F46022460E8 |
| data/drift_learning_repository.dart | D4D334B1BD31447158EC83EB393BB283697ECDC7169C93889677FA6FD70999CD |
| data/drift_learning_event_store.dart | AE1B281DDBECB16CC1019209E0577062040BCDC453B5D4A068E643C5EB5F1CB5 |

Only this preflight report changed. No running processes or remaining helper-owned work
