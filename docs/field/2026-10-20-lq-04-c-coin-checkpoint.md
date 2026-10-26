# LQ-04 C-COIN Option A

- Worktree/branch: `C:\Users\Phet\Documents\LexiQuest` / `feature/associative-reading-loop`
- Base HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`; existing dirty work preserved.
- Authority: LQ-00 user-delegated C-COIN Option A exclusive writer/Flutter slot, followed by file-specific identity/export grant on 2026-10-20.
- Budget: existing LQ-04 38 / program 250 cap; no reset.
- Final local verification: 2026-10-21, Asia/Bangkok. State: **bounded C-COIN engineering-complete; submitted for LQ-00 acceptance**. Exclusive production writer/Flutter slot returned with this handoff. No schema/routes/shared UI change, public arbitrary grant API, shadow-rate activation or raw history rewrite.

## Approved accounting policy

RewardTransactions is the coin ledger. One pure deterministic fold supplies repository reads, admission, rebuild and explicit personal reward export. Balance is SUM of **effective** amounts, replacing the historical raw-SUM target under the approved Option A decision. Raw invalid/duplicate/unaffordable purchases remain visible with effectiveAmount=0. Existing valid catalog price/version checks stay strict.

- `creditQuizCorrectV1`: +1, deterministic transaction ID/key/sourceEventId/time derived from the same owner's immutable correct AnswerAttempt. Incorrect/cross-owner/missing/mismatched provenance cannot mint. Rebuild/retry never creates a second grant. Both credit types use catalogVersion=0 and itemId=null.
- `creditLegacyCarryV1`: deterministic compatibility credit for a positive legacy ledger row without a corresponding canonical correct-answer credit. If a canonical row contains additional legacy units, only its residual is carry; no double counting the one evidence-backed coin. Raw ledger rows stay unchanged. Carry is local-only and has no outbox/cloud portability claim.
- Both credit types are materialized locally; quiz credits may be reconstructed from synced attempts, never pushed as positive raw transactions through the existing purchase/equip-only transport. Owner namespace requeue selects purchase/equip only.
- All known credits are available before purchase replay, matching the old projection (including its later-credit activation of an earlier unaffordable purchase). Purchases sort by UTC time then ID; duplicates/unaffordable/invalid entries have zero effective debit. Equipment is replayed after purchases in the same deterministic ordering, preserving legacy ownership/equipped behavior.
- Reward rebuilding never writes/deletes legacy PointsLedgerEntries. XP remains non-spendable. Raw answers, purchase/equip and legacy ledger history are unchanged.
- Admission uses the same fold result, not cached ownership/balance. Conflicting idempotency is rejected. Invalid motivation rows fail closed for reward effects without breaking unrelated local learning.

## Scope and cards

1. RED real-DB reward tests: evidence-bound credit, opaque carry, invalid/duplicate/insufficient purchase, raw-preservation/replay/reopen/owner isolation, conflict and concurrency.
2. Minimal pure fold plus existing reward repository/rebuilder integration; no schema or general grant API.
3. Granted identity requeue boundary and explicit personal export (`includeRewards=false` default); use the same accounting result with raw/effective/status/localOnly/source metadata. Rewards are rejected for research JSON, not silently added to research data. Existing export UI remains unchanged.
4. Serialized focused reward/progress/learning/identity/export/sync/caller tests, targeted analysis/format/diff, independent read-only review, final hashes and process=0, then section 13.5 handoff to LQ-00.

## Shared-file grant

`lib/features/identity/data/drift_owner_upgrade_repository.dart` and connected tests: exclude derived credit transactions from cloud requeue; preserve purchase/equip behavior. `lib/features/export/data/drift_export_reader.dart`, `lib/features/export/application/export_use_cases.dart`, `lib/features/export/domain/export_contracts.dart` and connected tests: explicit personal reward export, default false; no UI mutation. Sync/rules remain purchase/equip-only. Export changes may version the opt-in artifact format, not the database schema.

## Section 13.5 — final handoff

### Outcome / contracts / scope

- Chat/card: LQ-04 / C-COIN Option A, C-COIN-LOCAL-1. Source branch and base HEAD are above; the SHA256 manifest below identifies the dirty source snapshot, not a commit. No commit/reset/cleanup performed. Pre-existing account/UI/learning changes are preserved, not claimed as this card's work.
- One `foldRewardLedger` now supplies reward reads, admission, ownership/equipment rebuild and opt-in personal export. Reward rebuilding no longer writes/deletes XP. Invalid/duplicate/unaffordable raw evidence is retained with zero effective debit. Existing replay, reopen and owner-isolation checks pass.
- Provenance insert-or-verify conflicts roll back the reward savepoint; both local learning and pulled attempts still commit. No parallel reward authority or shadow rates activated.
- Credit rows never enter transport. Owner requeue excludes them; accidental local credit outbox rows become permanent failures. Unsupported remote reward types are quarantined **before** existing-row handling, with owner-scoped stable conflict identity; page cursor and later valid purchase continue. No remote credit row is inserted or local credit overwritten.
- Personal CSV/PDF API opt-in defaults false; schema2 only when rewards selected, schema1 otherwise. Both use the same audit formatter with evidence ID, transaction type, item, UTC milliseconds, raw/effective amounts, status, localOnly and source. Research JSON and Anki reject reward opt-in. Existing export UI unchanged.
- No schema/table/dependency/route/feature-ID change; frozen EvidenceContext/EventEnvelopeV2 and 8/44 catalog unchanged. Owner deletion inventory already covers RewardTransactions; no claim of whole-account/cloud deletion completion.
- Shared-file touches are the granted learning repository, sync store, identity upgrade repository, export reader/contracts/use cases and connected tests. `test/screens/shop_page_test.dart` changes only purchase/equip count assertions for the new credit rows; pre-existing catalog-preview changes remain baseline. Production rules unchanged; only denial tests added.

### Checks on the final source

All commands ran from `C:\Users\Phet\Documents\LexiQuest`, serialized. Final source edits stopped before the checks below; subsequent edits are this checkpoint only.

1. `dart format` on the 17 Dart paths in the manifest: exit0, 17 files formatted; last formatting pass changed only sync implementation/test. Removed one unused sync-failure test import revealed by analysis; reran analysis and the entire subsystem command afterward.
2. `flutter analyze --no-pub lib/features/rewards lib/features/learning/data/drift_learning_repository.dart lib/features/sync/data/drift_sync_store.dart lib/features/identity/data/drift_owner_upgrade_repository.dart lib/features/export test/features/rewards test/features/identity/drift_owner_upgrade_repository_test.dart test/features/sync/reward_transaction_sync_test.dart test/features/progress/legacy_reward_xp_compatibility_test.dart test/features/export test/screens/shop_page_test.dart`: **exit0, No issues found**, 3.5s.
3. `flutter test --no-pub test/features/rewards test/features/progress test/features/learning test/features/identity test/features/account/account_owner_isolation_test.dart test/features/sync test/features/export test/screens/srs_flashcards_screen_test.dart test/screens/quiz_screen_test.dart test/screens/weakness_clinic_screen_test.dart test/screens/mastery_dashboard_screen_test.dart test/screens/shop_page_test.dart test/screens/avatar_equipment_screen_test.dart test/screens/offline_vocabulary_journey_test.dart test/architecture/learning_screen_boundary_test.dart test/runtime/app_bootstrap_test.dart test/screens/production_shell_navigation_test.dart --reporter expanded`: **exit0, +245 All tests passed**, 18s. Covers repository/domain, sync, owner rehome/isolation, export and connected production callers.
4. `npm run test:rules`: **exit0, 33 tests / 4 suites / pass33 / fail0 / skipped0**, 5121ms test duration. Local `demo-lexiquest-rules-test` emulator only. Expected PERMISSION_DENIED logs are negative-test evidence, not failed assertions. Emulator shut down normally.
5. Focused `git -c core.safecrlf=false diff --check -- <manifest tracked paths>`: **exit0**. Manual connected diff review completed; no schema, production-rules, generated source or shared UI edits by this card. Final source hashes below.
6. Task runtime process check using `Get-CimInstance Win32_Process`, filtering Dart/Flutter tester/Firestore Java command lines: **task_runtime_process_count=0** after all commands. No command/session/emulator left running; reviewer finished read-only work.

TDD/recovery evidence: initial real-DB authority tests RED then GREEN; conflict isolation, legacy source residual/rehome, accidental credit outbox and export opt-in each exposed concrete failures before fixes. Independent review found remote pull poisoning: three unsupported-type regressions failed with InvalidSyncPayloadFailure, then passed with quarantine. Export audit regression failed on missing item/time fields, then passed after shared CSV/PDF formatter. Focused final sync/export command passed20 before the full245 run. One transient formatter lock was inspected and retried successfully after its owner exited; no process was killed or user data removed. No unresolved failing check remains within this bounded card.

### Review disposition

- Claude review: **evidence-derived**, limited to the earlier bounded proposal critique already recorded in the previous LQ-04 handoff. This is not a fresh C-COIN code review or an invented Claude verdict.
- Independent code review: `/root/lq04_bounded_review`, read-only connected source review, no tests/builds/writes. P1 remote unsupported-type pull poisoning and P2 incomplete PDF audit metadata were must-fix; both corrected and re-reviewed **accepted**, no additional actionable finding in that re-review. Root ran the final checks above.
- Accepted: bounded local coin authority, preservation and granted integration behavior. Not verified: rendered PDF layout, physical devices, full-repository regression/build, production/cross-device restore. Whole I3, whole research engineering and release readiness are not claimed.

### Remaining boundaries / next executable step

- Same-database downgrade to the old mixed-XP client after a new purchase is **unsupported**: regression deliberately preserves raw XP200 while new coins120 after purchase80; no mirror debit is written. Opaque legacy carry is local-only, with no cross-device restoration promise.
- Export UI opt-in is not exposed in this card; API-only behavior is tested. PDF generation/signature and shared audit fields are tested, not rendered layout. No new UI grant inferred.
- No deployment/publication/enrollment/real research upload, production-data access or security scanner run. Release-only/cloud deletion/device gates stay separate.
- LQ-00 next: verify this manifest/current diff and accept/reject C-COIN, then grant the next owner/Flutter slot under its sequencing. LQ-04 starts no LQ-05 implementation. If accepted, LQ-05 purchase/equip/restart remains the next authorized card, not part of this completion.
- Budget remains LQ-04 cap38 / program250; no spend telemetry available, no actual-credit-consumption claim and no cap reset.

### SHA256 source/test/contract manifest

These are all 21 C-COIN source/test/contract paths; this checkpoint is the 22nd file and its hash is sent separately to LQ-00 to avoid self-reference. `drift_learning_repository.dart` contains preserved pre-existing `wordIds` work; this card only changes optional reward rebuild isolation there.

| Path | SHA256 |
| --- | --- |
| `lib/features/rewards/domain/reward_ledger.dart` | `17AC3F42493E755E24695A0C51887C3D2A3D46751FAE931581B693E6089D3A88` |
| `lib/features/rewards/data/drift_reward_projection_rebuilder.dart` | `957CC9090104AA81EC403B93611084FACE76AF83C8F1826AF62C6E1ED981F1F7` |
| `lib/features/rewards/data/drift_reward_repository.dart` | `21DFD47001685443E5A02F885AFDFA20E7C83FD8327AD95D1B345337DE2D3106` |
| `lib/features/learning/data/drift_learning_repository.dart` | `D1E72B4C4E0E0709BE93046CEE18E037D58A49FD15B77778B26A04D8DA8B17E1` |
| `lib/features/sync/data/drift_sync_store.dart` | `AF1CCC01BEB05934CCB130C17751D1E00A0126C0D15705CF9B574146B80967A1` |
| `lib/features/identity/data/drift_owner_upgrade_repository.dart` | `327389EAF00CEDAA64FF48208BA953572826BF0AAD749DDCEBA2D268C05899DF` |
| `lib/features/export/domain/export_contracts.dart` | `694EAE432952591DF277DA71676C2669421612049418D3700C8E8CED688EA030` |
| `lib/features/export/data/drift_export_reader.dart` | `AFA5149D1E805F565D0466458FEBE69D522DBACC702CBD62C2D0985E98C5BD89` |
| `lib/features/export/application/export_use_cases.dart` | `DCF7BEDE1285454733DEE00D008698F96212D290DDC188B5C47938090DC732D3` |
| `test/features/rewards/coin_authority_test.dart` | `2431AECB09C4893670C54A634D701806B2B179A5A2AA3C9E5C6F18EAC1D783F8` |
| `test/features/rewards/reward_ledger_test.dart` | `458D64FBA37AE12CD2F8924E02BF3F1FF12719D32FB1E3907A3DC86F114654D3` |
| `test/features/rewards/reward_use_cases_test.dart` | `A948905549BF52524509FF155CCC47AECD8D01A5777582B7F9630A03CE195848` |
| `test/features/identity/drift_owner_upgrade_repository_test.dart` | `1191EE6D4C0CF2E7E4AE1AE23A3E338F6EEA44823BBF3471DF90D5E8EFC4FE47` |
| `test/features/sync/reward_transaction_sync_test.dart` | `3B56D4BE61D72DE798C2CE35DBCE706F85115A952682608836B8B4EBC969A2AF` |
| `test/features/progress/legacy_reward_xp_compatibility_test.dart` | `02D335891CEEC0D35203CA9FB13E4DAF29FDB041EAB72123046A08604A4E088B` |
| `test/features/export/export_use_cases_test.dart` | `9969900B5E5474B75DA1778CB99B2ECF6F7296DB2218D0E89FB970534D3D8690` |
| `test/screens/shop_page_test.dart` | `9462B66637ED57FF4B69ECFF5B1C82E65C2DDF7019C09C55C7E70806382A0C83` |
| `test/security/firestore-rules.test.cjs` | `6FEE7931D8FD93E3DCA3DC69797FAFFF299093130C64FB449A0345729AE03FF0` |
| `docs/v2-implementation/001-local-coin-authority-amendment.md` | `C0951852C7DEA026F9DFA4E82CB76EC9335F3B9E3CD494B28891ECD3FA8F2275` |
| `docs/v2-implementation/semantic_contract.md` | `08B873BBD1B32B443AE31080854675A885DB28A65993D22AD0D3BCD022BA3004` |
| `docs/v2-implementation/authority_matrix.md` | `57C341EF909ADF312E02EB925A5F8310C40415A965418112C9A0A6BBFBE02984` |
