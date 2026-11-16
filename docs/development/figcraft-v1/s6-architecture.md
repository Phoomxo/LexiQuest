# S6: Quest และ Gentle Streak จากคำตอบที่บันทึกแล้ว

2026-11-14. P4.4 / f29 / f30. Worktree `figcraft-flutter-v1`, branch `codex/figcraft-flutter-prototype`. Grounded against production196d4e22, schema10 and the actual schema ledger. UI evidence through04c19a93 changes no production after196d. This is the implementation contract, not feature acceptance or a migration reservation.

## Callers and ownership

```dart
await learning.recordAnswer(/* unchanged stable attempt ID + original UTC */);
final view = await progress.load(); // one owner/asOf; read-only
await rewards.claimQuest(expectedOwnerId: view.ownerId,
    instanceId: card.instanceId); // no UI amount/version/evidence
await streak.selectHomeTimezone(expectedOwnerId: view.ownerId,
    ianaId: selectedZone); // existing Settings, prospective
```

Existing Mastery owns current daily/weekly cards, explicit Claim, recent history and seven actual learning-day markers. XP/game motivation stays distinct from accuracy, mastery and learning/research outcomes. No49th screen, new balance, research event bus or Pair Matching.

Learning owns immutable answers and original owner/time. Motivation owns civil calendar/day/streak policy. Quest owns pinned criteria and reconstruction. RewardUseCases/repository owns the explicit claim command; DriftLearningProjectionRebuilder remains the only XP issuer. DriftRewardProjectionRebuilder remains the coin issuer. Existing ProgressUseCases supplies a consistent owner-checked snapshot. Widgets do not coordinate load/advance/save/complete stages.

## Arena decision

Both frozen preferred designs converged on reconstruction, with separate whole worker/journal alternatives. Root read all six files and screened the architect red flags. Root and independent gpt-6.1-terra/high judge selected Candidate B: scores A23/B24 of30, by learning/recovery4/4, recurrence/migration4/4, calendar3/4, economy4/4, interface depth4/4, scope/verification4/4. A used gpt-6-astra/high; B used gpt-6.1-sol/high. Skill default providers were unavailable; these are the actual supported substitutes. Two stalled pending initializations were interrupted/reassigned once before either produced files; both then finished normally.

Graft A's original-commit eligibility distinction and lossless legacy baseline/origin analysis. Reject its extra hidden-start session exclusion: eligibility belongs to each original answer commit. Reject both workers/journals until measured indexed queries justify that machinery. No speculative performance claim.

Root corrections to both drafts:

- Dart library-private grant objects cannot cross unrelated feature libraries. Do not add part-file coupling or a public raw XP proof. The existing XP rebuilder will gain a narrow `rebuildQuestXp(ownerId)` operation reading validated local immutable receipts. There is no existing `rebuildOwner` API; do not invent/call one or rebuild every SRS word for a claim.
- Do not lose a durable answer's Quest progress merely because an optional period-pin insert failed. Capture immutable eligibility intent on the original answer, with no answer-time Quest instance/counter writes. Query reconstructs; explicit claim alone materializes instance/receipt.
- One immutable archived canonical definition is authoritative. Instances/attempts reference its version/digest; do not maintain a second editable copy of the catalog.

## Evidence and periods

Add bounded versioned calendar/Quest-intent metadata to the existing answer row, never a duplicate answer store. Captured calendar evidence contains original origin owner, IANA/rule/tzdb revision, civil-day and Monday labels, offset, and normalized immutable day/week arrays of half-open UTC segments. Day/week membership is the union of its segments; every original fact must belong to exactly one segment in each array. Exact replay retains original metadata and existing immutable-answer conflict checks. New remote/legacy/hidden answers carry no Quest intent and cannot gain eligibility by opening Mastery or toggling visibility later.

A trusted optional catalog capability is exposed only after its immutable definitions are validated/archived. Intent pins the original enabled decision, origin, each cadence's period identity and catalog revision. Per-cadence revision activation is prospective at the next period boundary; current periods retain their original revision. An unknown/mismatched pin becomes visibly unavailable, never another reward. Gate-hidden boot/practice constructs no Quest factory/catalog/pipeline and writes no Quest data.

An original enabled answer whose calendar calculation is unavailable may retain an explicit pending intent only when its exact original rule and per-cadence definition revisions are durably known. Repair uses those references, never today's owner/settings/catalog. If those identities cannot be captured, ordinary learning still commits and the UI reports actual missing eligibility; do not falsely call it retryable. No mutation from a Mastery read. Pin conflicts fail closed for that card and do not block unrelated learning.

Counts group distinct committed attempt IDs under compatible owner/period/pin and original correct predicate. Completion time is the target-th qualifying (UTC,id)-ordered fact. Daily5 grants50XP; weekly20 grants200XP. Incomplete closed periods expire; completed unclaimed periods remain claimable. Reopening, replaying and a process exit after answer commit require no delivered hook acknowledgement. Virtual current zero-progress cards and actual history are read-only; missing empty past periods need not be fabricated.

## Calendar and legacy history

Initialize the installed timezone database at bootstrap. Explicit UTC is the usable initial home calendar; UI labels it. Learner may select a validated IANA region in existing Settings. OS travel/abbreviations/locale/offset do not silently change that authority. Persist full epoch bounds prospectively. A zone change activates at the LAST end of the current week's exact segments. Previously committed current-period segments cannot extend beyond that scheduled boundary; prove this invariant before persisting a request. New-zone segments are clipped at activation/expiry. Do not retrospectively truncate a claimed or pinned period. Repeated pending selections replace only an unused request.

The original single-contiguous-interval premise failed twice: Gaza's repeated midnight invalidated the constructor choice, then St Johns invalidated the premise itself. Actual Flutter REDs preserve both observations. A directed comparison chose exact segments over typed refusal (root agrees with judge18/15of20). For each civil day/week wall-label range, intersect every actual constant-offset UTC interval with its exact inverse; coalesce only touching segments. No min/max hull may admit a gap. Civil ordinal arithmetic defines labels, not elapsed UTC hours. Persist the exact original segments/tzdb identity for replay. Unsupported range or genuinely unavailable authority is explicit and never invalid captured evidence.

Period identity is origin + immutable calendar rule/epoch + cadence + civil label + Quest family. A segment, offset, receipt timestamp, attempt ID or catalog update never creates a second entitlement. Both St Johns Saturday fragments contribute to one Saturday. Expiry uses the LAST segment end; a temporary excursion into another date cannot permanently expire a returning period. Day segments are a subset of the corresponding week union after epoch clipping. Existing public day helpers are unchanged in this primitive unit; production cutover uses the new captured metadata.

Historical UTC-only attempts remain explicitly UTC-only, with no invented past IANA/offset. Existing raw Quest counters/definitions/IDs remain archived history and cannot alone warrant a new grant. Unknown historical criteria are nonclaimable. Preserve raw legacy XP/coins and existing freeze assets; do not manufacture past protected dates.

Gentle Streak uses one canonical dated fold for its headline and week markers. Actual studied and freeze-protected days remain distinct. Seal each original owner's v10 state as an opaque cutoff baseline; keep max known longest and exact token balance, not fabricated reconstructed continuity. Future auto-freeze debits for a one-day gap retain the existing rule that length is unchanged. Persist each accepted debit/protection once with stable origin/command identity, atomically with the forward day projection. Manual debit without a date remains a debit, not an invented protected day. Grant/manual calls require stable identities and nonnegative transactional balance.

Recover missing day projections from committed dated answers, ordered chronologically, without a high-water cursor that skips late facts. Late days update attendance and post-cutoff folds; never refund or invent a committed old freeze debit. No read-time token consumption. If optional settlement fails, preserve the answer and show pending/unavailable Streak rather than a false settled zero; retry from durable answers before returning settled state. Detailed fold/merge cases are acceptance tests before this unit's writes.

## Claim, economy and merge

Claim validates active expected owner and gates inside a SQLite write transaction, resolves the canonical period, reconstructs/pin-checks evidence, and writes one immutable receipt plus its XP projection on the same executor. Exact replay returns the original receipt/time/amount. Existing rows must match full immutable provenance; insert-ignore alone is insufficient. Database uniqueness/transaction retry protects different connections; the current repository's per-instance write gate alone does not.

Add `questClaimXpV1` as an XP-only kind. Exclude it in the existing legacy coin bridge before source-backing subtraction. Five correct answers yield XP5/coins5; explicit daily claim yields XP55/coins5. Preserve legitimate legacy200XP minus80coin purchase =>120coins, purchases/equipment and raw history. No separate mint in Quest or UI.

Owner upgrade handles conflicts before generic owner moves. Compatible same-period/same-pin3+2 facts may union by immutable attempt ID. Different pins/windows are a visible nonclaimable conflict unless identity is proved; overlap alone is not transitive equivalence. A guest period straddling two target periods must not be credited twice. Any existing receipt closes its alias group. Both independently issued receipts/XP remain raw history with stable IDs; never claw back balances or issue a third grant. Stale guest cards fail after owner change.

Freeze assets/baselines retain stable original-owner identities and move once; do not dedupe independent debits solely because their civil dates match. Preserve both raw baselines; target baseline controls future continuity, max longest remains known, source overlap stays explicitly uncertain. Future learning uses target calendar; historical stamps stay immutable. Repeat merge is a no-op. Every owner table requires inventory/export/deletion and scoped-join coverage.

## Schema and cloud boundary

Current10/next11 were read from the ledger. Reserve the actual next version immediately before migration code, after the file-backed v10 fixture/write set is concrete. Intended delta: answer metadata; owner calendar epochs; immutable shared definition revisions; recurring instance key/history/pin/alias fields; local claim receipts; origin-keyed sealed streak baselines and dated token adjustments. Preserve old instance/objective PKs/content/FKs while replacing lifetime owner/Quest uniqueness. Keep one canonical catalog archive, nullable legacy provenance and explicit captured-row constraints. Owner lifecycle code and full export must cover all additions in the same wave.

Claims/calendar/freeze authority is local-only. Existing cloud attempt/SRS and purchase/equipment routes do not carry trusted Quest entitlements. Remote payloads cannot assert eligibility/receipts/XP grants; verify actual inbound routes and policy rejection, not an assumption about default denial. Local full export includes pins/definitions/receipts/history; ordinary reward CSV/PDF remains spendable coins. UI states installation-only claim history and no cross-device/reinstall restoration guarantee.

Do not use events_v2 as motivation storage. Frozen EvidenceContext and EventEnvelopeV2's22fields stay unchanged. Nonparticipants create zero research rows/events/research outbox/uploads through practice, read, replay, claim, export and owner upgrade. Normal learning sync outbox is a separate allowed category.

## Verifiable implementation units

1. **S6-A economy boundary:** `test/features/rewards/coin_authority_test.dart` RED, then minimal existing reward projection filter. Real5answer/file-reopen/B-isolation and source-backing tests; existing legacy purchase preserved. No feature-completion claim.
2. **S6-B calendar window:** existing `timezone_policy.dart` and its test only. Immutable exact-segment capture from originalUTC/IANA, DST23/25h, Gaza/St Johns, skipped dates, Monday/year, pre-1970 synthetic weekly disconnection, exact microsecond epoch clipping and unsupported range. Motivation38 and scoped analysis passed with unchanged source hashes; independent review accepted. Existing public day APIs remain compatible. No migration yet.
3. **S6-C persistence:** concrete ledger reservation and real v10 file-SQLite migration/reopen/foreign-key tests; raw IDs/history/balances/token assets conserved, current create parity, all owner export/delete coverage. Root owns schema/generated files and serialized codegen.
4. **S6-D reconstruction/claim:** pure criterion/day folds plus real repository transactions, same-ms distinct attempts/replay, concurrent connections, fault boundaries/lost ACK/reopen, repeated/straddling owner merge, pending repair, history and recurrence. XP issuer remains existing class.
5. **S6-E production/UI:** actual bootstrap gates and existing Mastery/Settings, read-only view, origin/owner fences, refresh/back, Thai200%/claim labels, hidden constructors/writes absent. Retire old production event/no-argument hooks in the same caller migration. No fake synthetic efficacy or default research writes.
6. **S6-F attest:** freeze writers; touched subsystem/policy tests then required full regression/analyze/build and actual native evidence. Reconcile catalogue without shrinking48/44/64. Keep real enrollment/upload/deployment disabled.

Units1–2 have concrete disjoint test writers; root runs all Flutter commands serially and observes RED before production edits. Later-unit details are verified against source before writing, not excuses for another discussion-only approval cycle. Current architecture and candidate text are design evidence; no benchmark, migration, claim or whole-feature result is asserted here.
