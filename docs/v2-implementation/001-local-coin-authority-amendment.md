# Amendment 001 — C-COIN-LOCAL-1

Approved execution authority: LQ-00's user-delegated Option A grant on 2026-10-20, recorded in `docs/field/2026-10-20-lq-00-wave-0-checkpoint.md` under `Option A authorization and C-COIN execution grant`. This is an explicit bounded semantic amendment, not an invented architecture-board meeting, commit, rollout or ethics approval. Local implementation/verification continues on 2026-10-21 (Asia/Bangkok).

## Superseded definitions

- Coin balance is **SUM(effectiveAmount)** from one deterministic fold of owner-scoped RewardTransactions. Raw SUM is an audit metric and is not a valid balance when duplicate, invalid or unaffordable purchase evidence exists.
- The rewards domain owns purchase/equip admission and evidence-bound local credit materialization. There is no public arbitrary `grantCoins(amount)` API. The shadow RewardEligibility policy is not activated.
- PointsLedgerEntries is XP only. Historical rewardPurchase debits are retained and excluded from XP reads. Rewards never add/delete those debits or rewrite raw attempts/purchase/equip/legacy ledger history.

## Fixed local credits

| Type | Identity/key/source | Amount/time | Transport |
| --- | --- | --- | --- |
| creditQuizCorrectV1 | `coin:quiz:<attemptId>` / `creditQuizCorrectV1:<attemptId>` / correct same-owner attempt ID | +1 / immutable attempt UTC time | Locally derived; no credit outbox. Reconstructed from synced attempts, not a server anti-cheat receipt |
| creditLegacyCarryV1 | `coin:legacy:<legacyRowId>` / `creditLegacyCarryV1:<legacyRowId>` / same-owner positive legacy ledger row ID | legacy residual / original UTC time | Local-only; no outbox or cloud restore guarantee |

Both credit types use **catalogVersion=0**, itemId=null. Catalog revisions cannot change their earning provenance. Materialization inserts or verifies the exact immutable row; ID/key/owner/source/amount/time conflict rolls back the credit savepoint. No altered-source retry can overwrite a grant. A conflict makes reward accounting unavailable until reconciled; local learning/attempt sync still commit their own evidence.

For each correct attempt, the canonical +1 XP row is covered by its quiz credit and creates no carry. For noncanonical legacy rows referencing that attempt, one unit is covered once across those rows and the remainder is opaque carry. Other positive opaque rows retain their full amount as carry. This preserves a legacy 200-unit credit tied to an attempt as quiz1+carry199, and avoids double credit when learning subsequently rebuilds the canonical XP row. Wrong/cross-owner sources never qualify for a quiz credit.

## Fold and admission

Available credits are evaluated first, then purchases ordered by UTC timestamp and ID, then equipment in that order. This retains the historical behavior where later known learning credit may activate an earlier unaffordable raw purchase. It is not a claim about historical wallet funds at transaction time.

Valid purchases debit the frozen catalog price/version once per item. Duplicate, invalid or unaffordable purchases have effectiveAmount=0 and remain raw. Equipment requires effective ownership (or a free item). Repository reads, admission, durable ownership/equipment rebuild and opt-in personal export share this fold; none may SUM the mixed XP ledger or trust stale ownership projections.

## Portability and compatibility boundary

- Existing remote protocol/rules remain purchase/equip-only. Both derived credit types are excluded from owner namespace requeue; accidental credit outbox operations are quarantined. Remote positive mint is denied.
- Opaque carry cannot be reconstructed on another device without its local legacy evidence. No issuer/signature/server receipt is invented. Personal export is an audit, not an import/restore or trusted mint mechanism.
- **Downgrading to an old mixed-ledger client on the same database is unsupported after new purchases.** The new client preserves raw XP200 and coins120 after purchase80; an old client that SUMs the XP ledger may incorrectly display200. No legacy mirror is written into XP to hide this boundary. Existing historical purchase/equip evidence and valid balances/rights are preserved when upgrading into this client.
- No database schema, table, route, shared UI, EventEnvelopeV2 or EvidenceContext change is made.

## Personal export and deletion inventory

`ExportSelection.includeRewards` is explicit opt-in and defaults false. CSV/PDF personal exports can include raw/effective/status/localOnly/source and the folded balance. Opt-in artifact schema is2; existing artifacts remain1. Anki/research JSON reject reward opt-in; research content is not expanded. Export UI selection is a follow-up and is not implemented here.

Derived credits use the existing owner-scoped RewardTransactions table already listed in `ownerUpgradeInventory`. Existing local owner-data lifecycle therefore includes the rows without a new entity/table. This does not supply the separately pending whole-account/cloud deletion authority or a cross-device carry restore feature.
