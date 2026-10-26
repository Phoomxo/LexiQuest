# LQ-05 marketplace purchase/equip/appearance continuation checkpoint

- Date: 2026-10-21 (Asia/Bangkok)
- Chat/card: LQ-05 / I6 purchase confirmation, owner-bound intents, idempotent equip, and restart-applied appearance
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch/base HEAD: `feature/associative-reading-loop` / `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- Authority: LQ-00 granted the exclusive production writer and serialized Flutter slot for the six production files below and their direct tests.
- Coin authority dependency: C-COIN Option A accepted from `docs/field/2026-10-20-lq-04-c-coin-checkpoint.md` (checkpoint SHA-256 `623ECE49B259FAC259891EB78B9F60F1C00D32C8E9E021F2CAF28A8B39A6EEFE`). `RewardTransactions` effective fold remains the sole coin authority.
- State: **closure implemented and verified locally; candidate for LQ-00 acceptance**. The closure addendum at the end of this checkpoint supersedes the earlier partial disposition while retaining it as historical evidence.

## Outcome and user-visible behavior

- Purchase now requires a confirmation dialog showing item price, balance before/after, and the explicit cosmetic-only disclaimer. Cancel and Back perform no reward writes.
- Purchase and equip use stable, owner-bound intent keys. Repository equip now distinguishes first write, replay, and already-equipped without duplicate transaction/outbox evidence. Conflicting key reuse fails closed.
- The active owner is checked before and after purchase/equip. Switching owners while confirmation or an operation is pending cannot debit or equip the newly active owner. The mounted shop clears intents, hides the previous owner's snapshot during the no-owner gap, and reloads the next owner.
- Equipped theme/wallpaper rows drive `MaterialApp` light/dark theme composition through the active-owner appearance stream. Reopen restores the appearance; A-to-B owner switching resets to B's appearance without replacing Navigator state.
- Catalog filter, preview, scroll restoration, direct equip, Back behavior, large text, and dark/light layouts remain covered.
- C-COIN behavior is unchanged: no positive transport, no XP spending, no second balance/ownership authority, and no schema change.

## Changed files and shared-file touches

Production write set:

- `lib/features/rewards/domain/reward_models.dart`
- `lib/features/rewards/application/reward_use_cases.dart`
- `lib/features/rewards/data/drift_reward_repository.dart`
- `lib/screens/shop_page.dart`
- `lib/main.dart`
- `lib/config/m3_theme.dart`

Direct tests/callers:

- `test/features/rewards/reward_use_cases_test.dart`
- `test/features/progress/legacy_reward_xp_compatibility_test.dart`
- `test/features/rewards/coin_authority_test.dart`
- `test/screens/shop_page_test.dart`
- `test/screens/avatar_equipment_screen_test.dart`
- `test/config/m3_theme_test.dart`
- `test/runtime/reward_appearance_restore_test.dart`

The worktree contains unrelated pre-existing changes. They were preserved. In particular, `drift_reward_repository.dart`, reward tests, `m3_theme.dart`, and `shop_page.dart` also contain accepted earlier-card work; this handoff claims only the continuation behavior above. No bootstrap, app-dependency, schema/generated source, routes, manifests, export, identity, sync implementation, production rules, dependency, or feature-ID file was changed by this continuation.

## Contracts/schema/route/feature IDs affected

- Added reward application/domain contracts: `RewardSession`, `RewardAppearance`, `EquipResult`/`EquipStatus`, and `RewardFailureCode.ownerChanged`.
- `RewardUseCases.purchase` and `equip` require the caller's expected owner; equip also requires its stable idempotency key.
- `DriftRewardRepository.equip` returns `EquipResult`; `watchAppearance` exposes only the active owner's equipped rows.
- No database schema/table/migration, route, 8-category/44-capability catalog, frozen EvidenceContext/EventEnvelopeV2, export/delete, or sync-policy contract changed.

## TDD and recovery evidence

- Reward API tests first failed to compile until the owner/session/equip-result contracts existed, then passed.
- A stale `loadSession` test initially returned owner A after activation changed, then passed after the post-load owner check.
- Theme tests initially failed because appearance-aware theme factories did not exist, then passed with ocean/focus light/dark composition and contrast checks.
- Reopen integration initially timed out waiting for appearance, then passed after binding `MyApp` to the durable active-owner stream.
- Owner transition tests exposed stale shop rendering and an existing `setState` callback returning `Future`; both were corrected and now pass.
- `purchase double tap and replay debit only once` writes one purchase/outbox and is designed to reuse one intent after synthetic callback acknowledgement loss, but the focused widget run does not complete after starting. Per LQ-00's recovery instruction, further retry/gesture/pump edits were stopped. The test remains present, enabled, and unweakened.

## Focused checks on the current source

All commands were serialized in this worktree after production edits stopped.

1. `dart format --output=none --set-exit-if-changed <13 manifest paths>`: **exit 0**, `Formatted 13 files (0 changed)`.
2. Focused `git diff --check -- <13 manifest paths>`: **exit 0**; only Git's existing LF-to-CRLF advisory was emitted.
3. `flutter analyze --no-pub lib/features/rewards lib/screens/shop_page.dart lib/main.dart lib/config/m3_theme.dart test/features/rewards test/features/progress/legacy_reward_xp_compatibility_test.dart test/features/sync/reward_transaction_sync_test.dart test/screens/shop_page_test.dart test/screens/avatar_equipment_screen_test.dart test/config/m3_theme_test.dart test/runtime/reward_appearance_restore_test.dart`: **exit 0**, `No issues found!` (3.9s analyzer time).
4. `flutter test --no-pub test/features/rewards/reward_use_cases_test.dart test/features/rewards/coin_authority_test.dart test/features/progress/legacy_reward_xp_compatibility_test.dart test/features/sync/reward_transaction_sync_test.dart test/config/m3_theme_test.dart test/runtime/reward_appearance_restore_test.dart test/screens/avatar_equipment_screen_test.dart --reporter compact`: **exit 0, +40 All tests passed**.
5. `flutter test --no-pub test/screens/shop_page_test.dart --name "^(?!purchase double tap and replay debit only once$).*" --reporter compact`: **exit 0, +11 All tests passed**. This execution filter excluded only the unresolved exact test name; the source test is not skipped or disabled.
6. `flutter test --no-pub test/runtime/app_build_info_test.dart test/screens/production_shell_navigation_test.dart --reporter compact`: **exit 0, +12 All tests passed**.
7. Focused unresolved command `flutter test --no-pub test/screens/shop_page_test.dart --plain-name "purchase double tap and replay debit only once" --reporter expanded`: started the named test but produced no completion after more than 30 seconds; the task-owned test session was stopped. This is unresolved evidence, not a passing check.

## Review and handoff §13.5

```text
Chat / card / source branch and snapshot
LQ-05 / I6 purchase-equip-appearance continuation
feature/associative-reading-loop @ f43aa0fff2155ca29d6a26f2695191dd44a2d6d1
Dirty source snapshot identified by the SHA-256 manifest below.

Outcome and user-visible behavior
Confirmation, cosmetic-only disclosure, owner-bound stable intents, idempotent
equip/replay, active-owner shop isolation, and durable theme/wallpaper restoration
are implemented. Navigator state survives appearance and owner changes.

Changed files and shared-file touches
Six granted production files, seven direct test/caller files, and this checkpoint.
Unrelated dirty work is preserved. No out-of-scope shared implementation touched.

Contracts/schema/route/feature IDs affected
Reward session/appearance/equip result/owner-changed application contracts only.
No schema, route, frozen research envelope, feature catalog, or parallel authority.

Focused checks with exact result
Format exit0; diff-check exit0; analyze exit0; 40 connected tests pass;
11 runnable Shop tests pass; 12 app-shell/navigation tests pass. One enabled
lost-acknowledgement widget test hangs and is not counted as passing.

Claude review: not available
No fresh Claude review was authorized or run for this source snapshot.

Review disposition: must-fix / follow-up
Runnable bounded behavior is accepted by focused evidence, but the lost-ack widget
test hang prevents claiming full I6 engineering completion or a green Shop suite.

Device/external/release dependencies
No physical-device, TalkBack, screenshot/golden, full-repository suite/build,
production deployment, cross-device restore, enrollment, or real-data check.

Next executable step
LQ-00 verifies this checkpoint/current diff and may reopen the same bounded owner
for a new-hypothesis diagnosis of the lost-ack widget hang. After it completes,
rerun the complete Shop file (without a name filter), connected regression,
targeted analyze/format/diff checks, and refresh hashes before marking I6 Done.
```

## SHA-256 source/test manifest

| Path | SHA-256 |
| --- | --- |
| `lib/features/rewards/domain/reward_models.dart` | `300B18203E61F55350B0DA66C92194B24A40135301BA9F861F8D2E94CFF688D3` |
| `lib/features/rewards/application/reward_use_cases.dart` | `55496777BBB3896DB2CAD01ECADEB6725CBC8ACF9981FB192EC9DF17C89DA186` |
| `lib/features/rewards/data/drift_reward_repository.dart` | `705A5E9BC5071DBE9A7DC600D27A3B81A3185C32B7956ADDB4D224E7A3A6CF1E` |
| `lib/screens/shop_page.dart` | `71BC519BDC3E3B1E869D591B373B96D8E3289509BBFDA5463B9C05086656AFE8` |
| `lib/main.dart` | `943B03ABC9931DDF03C37A2DF7831F7629A66E6511D2161ED4CE453530235F6B` |
| `lib/config/m3_theme.dart` | `735B31D083521286225420D845FDCFFAC0E5AD356D3217AE7487EFF11336ED41` |
| `test/features/rewards/reward_use_cases_test.dart` | `A940A9AC0EB344F9F5463DD4E59FD6851416291F678A38E9010AB1F54AE5459A` |
| `test/features/progress/legacy_reward_xp_compatibility_test.dart` | `46C8C58FA1D7B48027A3611B5D30932AE1D4D67A5D2CA7F2E1BB6A29593A2B5E` |
| `test/features/rewards/coin_authority_test.dart` | `9FA69B2ACB934EE608D1A234E22DA482F19CD0581AF52E8C446F4499A771F749` |
| `test/screens/shop_page_test.dart` | `ED949F9B41E0C90E33156CEC7880110DB8A0CFF27285C17BF35F9247EAB8B77F` |
| `test/screens/avatar_equipment_screen_test.dart` | `3DA965996E608BE6F48A38675677AFDA124F575520D7E451C0E56714A7653DDA` |
| `test/config/m3_theme_test.dart` | `04BF53C36E6B24C408548CD75F63EE7195101148AF2B2E4B6AC6B0A980B3724C` |
| `test/runtime/reward_appearance_restore_test.dart` | `B7950012CE9A89674C2FD363ADA2145B7D91027FB02D85C978F89D8117B5E588` |

The checkpoint hash is reported separately to avoid self-reference. No commit, reset, cleanup, deployment, publication, participant enrollment, or real research-data upload was performed.

## Lost-ack closure addendum — 2026-10-21

This addendum supersedes the earlier `partial / must-fix` disposition above. The previously hanging enabled widget test now completes without a name filter. No test was deleted, skipped, renamed, or weakened.

### Bounded implementation

- Added the narrow four-method `RewardShopOperations` application boundary (`loadSession`, `watchAppearance`, `purchase`, `equip`). `RewardUseCases` implements it and remains the only production implementation; no controller/store/reward authority was added.
- `ShopPage` consumes that interface. Its production behavior and dependency fallback are unchanged.
- The real Drift application test performs a committed purchase whose post-commit callback loses acknowledgement, retries with the same owner/item/key, and proves one effective debit (`-80`), one purchase row, one outbox row, ownership, replay status, and balance `120`.
- The same enabled widget test `purchase double tap and replay debit only once` now uses a controllable application-port fake instead of placing real Drift asynchronous work under Flutter fakeAsync. It invokes the confirmation callback twice synchronously and proves one dispatch; the unknown result retains the single generated intent; retry records the same owner/item/catalog/key and reaches owned terminal UI with balance `120`.
- No repository/domain/main/theme/bootstrap/identity/sync/export/schema/dependency/manifest implementation changed in this closure. No production defect requiring an expanded write set was found.

### RED/GREEN and final checks

1. RED: `flutter test --no-pub test/screens/shop_page_test.dart --plain-name "purchase double tap and replay debit only once" --reporter expanded` → **exit 1**, compile failure because `RewardShopOperations` did not yet exist.
2. Real Drift GREEN: `flutter test --no-pub test/features/rewards/reward_use_cases_test.dart --plain-name "committed purchase acknowledgement loss replays without duplicate debit" --reporter expanded` → **exit 0, +1 All tests passed**.
3. Widget GREEN after the interface/fake implementation: `flutter test --no-pub test/screens/shop_page_test.dart --plain-name "purchase double tap and replay debit only once" --reporter expanded` → **exit 0, +1 All tests passed**, no hit-test warning after deterministic double-confirm invocation.
4. Required unfiltered Shop run: `flutter test --no-pub test/screens/shop_page_test.dart --reporter compact` → **exit 0, +12 All tests passed**.
5. Connected current-source regression: `flutter test --no-pub test/features/rewards test/features/progress test/features/sync test/config/m3_theme_test.dart test/runtime/reward_appearance_restore_test.dart test/runtime/app_build_info_test.dart test/screens/shop_page_test.dart test/screens/avatar_equipment_screen_test.dart test/screens/production_shell_navigation_test.dart test/architecture --reporter compact` → **exit 0, +169 All tests passed**. This includes the real DB/reward/progress/sync/theme/appearance restore/app shell and architecture policy paths.
6. `dart format --output=none --set-exit-if-changed lib/features/rewards/application/reward_use_cases.dart lib/screens/shop_page.dart test/features/rewards/reward_use_cases_test.dart test/screens/shop_page_test.dart` → **exit 0, 4 files / 0 changed**.
7. `flutter analyze --no-pub lib/features/rewards/application/reward_use_cases.dart lib/screens/shop_page.dart test/features/rewards/reward_use_cases_test.dart test/screens/shop_page_test.dart` → **exit 0, No issues found** (2.3s analyzer time).
8. Focused `git diff --check` on the same four closure paths → **exit 0**; only existing LF-to-CRLF advisories were emitted.
9. Manual connected diff review found the interface contains only the four approved Shop operations, the fake records actual call history, and no skip annotation or out-of-scope source change was introduced. Fresh Claude/independent-agent review was not available for this snapshot.
10. Final task runtime process count: **0** for Dart/Flutter/gen_snapshot and Firebase-emulator Java processes.

### Authoritative §13.5 closure handoff

```text
Chat / card / source branch and snapshot
LQ-05 / I6 lost-ack two-layer closure
feature/associative-reading-loop @ f43aa0fff2155ca29d6a26f2695191dd44a2d6d1
Dirty source snapshot identified by the final 13-path SHA-256 manifest below.

Outcome and user-visible behavior
An uncertain post-commit purchase result keeps its owner-bound intent. A retry
uses the same key, resolves as already owned, and cannot debit twice. Double
confirmation dispatches once. Existing preview/equip/owner/theme behavior passes.

Changed files and shared-file touches
Closure delta: reward_use_cases.dart, shop_page.dart, their two direct tests,
and this checkpoint. Earlier authorized I6 changes remain in the 13-path manifest.
No out-of-scope production file changed during closure.

Contracts/schema/route/feature IDs affected
Added only RewardShopOperations with the four existing Shop operations.
No schema/route/catalog/frozen research envelope/transport/authority change.

Focused checks with exact result
RED compile proof; two isolated GREEN proofs; full unfiltered Shop +12; connected
reward/progress/sync/theme/restore/shell/policy +169; analyze/format/diff exit0;
process0. Exact commands are recorded above.

Claude review: not available
No fresh Claude or independent-agent review was run; manual connected diff review
found no actionable closure issue.

Review disposition: candidate accepted for bounded I6 engineering closure
All previously unresolved acceptance evidence is green on one current snapshot.
Final program acceptance remains with LQ-00.

Device/external/release dependencies
No physical-device/TalkBack/golden/full-repository build, production deployment,
cross-device restore, enrollment, or real-data verification is claimed.

Next executable step
LQ-00 verifies this addendum, current diff and hashes; reruns any chosen bounded
acceptance command; then accepts/rejects I6 and transfers the next gated slot.
```

### Final 13-path SHA-256 manifest

| Path | SHA-256 |
| --- | --- |
| `lib/features/rewards/domain/reward_models.dart` | `300B18203E61F55350B0DA66C92194B24A40135301BA9F861F8D2E94CFF688D3` |
| `lib/features/rewards/application/reward_use_cases.dart` | `BA06300F2CC2B3CFAD7CD048C4F9BD3161AF9B3D420F3622B09BFD9C6E8E39D7` |
| `lib/features/rewards/data/drift_reward_repository.dart` | `705A5E9BC5071DBE9A7DC600D27A3B81A3185C32B7956ADDB4D224E7A3A6CF1E` |
| `lib/screens/shop_page.dart` | `9691F9E4693E5776BA00CCFA35DF8CBAAA0C2269570E2F3E469738860A8F29CE` |
| `lib/main.dart` | `943B03ABC9931DDF03C37A2DF7831F7629A66E6511D2161ED4CE453530235F6B` |
| `lib/config/m3_theme.dart` | `735B31D083521286225420D845FDCFFAC0E5AD356D3217AE7487EFF11336ED41` |
| `test/features/rewards/reward_use_cases_test.dart` | `4B4F7499E438DD30D75EA246AA253FA52F9DC44F8B1368A41C1439B803B8056D` |
| `test/features/progress/legacy_reward_xp_compatibility_test.dart` | `46C8C58FA1D7B48027A3611B5D30932AE1D4D67A5D2CA7F2E1BB6A29593A2B5E` |
| `test/features/rewards/coin_authority_test.dart` | `9FA69B2ACB934EE608D1A234E22DA482F19CD0581AF52E8C446F4499A771F749` |
| `test/screens/shop_page_test.dart` | `DA08466A6C092A498E8A8DDC388202704D2C5515F70AF16A2C4E2B7E485B98F1` |
| `test/screens/avatar_equipment_screen_test.dart` | `3DA965996E608BE6F48A38675677AFDA124F575520D7E451C0E56714A7653DDA` |
| `test/config/m3_theme_test.dart` | `04BF53C36E6B24C408548CD75F63EE7195101148AF2B2E4B6AC6B0A980B3724C` |
| `test/runtime/reward_appearance_restore_test.dart` | `B7950012CE9A89674C2FD363ADA2145B7D91027FB02D85C978F89D8117B5E588` |

This checkpoint's final hash is reported separately to avoid self-reference. Budgets remain LQ-05 cap24 / program250; no token or credit consumption was available and none is invented. No commit, reset, cleanup, deployment, publication, participant enrollment, or real research-data upload was performed.
