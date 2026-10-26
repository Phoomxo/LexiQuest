# LQ-05 — MKT-BALANCE-LOCAL honest insufficient-balance UX

## Section 13.5 handoff / intent and authority

- Card: `MKT-BALANCE-LOCAL`; bounded local Shop affordability UX after root acceptance of `MKT-PREVIEW-LOCAL-1`. It is not a new reward authority, full marketplace implementation, responsive-grid card, or release attestation.
- Worktree: `C:\Users\Phet\Documents\LexiQuest`; branch `feature/associative-reading-loop`; HEAD `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`. Existing dirty work was preserved; the final hashes below identify the verified source snapshot rather than relying on HEAD alone.
- Authority: direct source-root transfer granted the sole production-writer and serialized Flutter/test/analyze/format slot for the two code/test paths below plus this new checkpoint. Coordinator checkpoint SHA256 at transfer was `F3A582D502416C294B3712C119348A88987F190A731EF2955B6FBF06821A0BF1`.
- State: **bounded engineering-complete, submitted for root acceptance; RETURN writer/test slot**. No later card was started.

## Ground / outcome / changed files

Re-read the current Shop implementation/tests, preview checkpoint, active coordinator delegation, reward catalog/session/replay/owner contracts, repository insufficient/stale validation, and ADLC/checkpoint requirements before TDD. Initial SHA256 values matched the grant: Shop `FEDD62ABC53D91AD830A2F19A29ED79CFED2D8A27B7FA9255F7341AEC6A8A44E`; Shop test `A02067F20B3208E7EAAA7E036AAF556A9A72B2996B0B3520D0B7BB24425F398E`. The exact checkpoint path did not exist before creation.

Wrote only the authorized three paths:

1. `lib/screens/shop_page.dart`: a new purchase whose displayed balance is below the catalog price opens a scrollable informational dialog showing item, current balance, actual price, exact missing amount, and a recovery instruction. It has Cancel/Back but no executable confirmation, does not create an intent, and never renders a negative projected balance. A retained uncertain intent for the same owner/item bypasses this display-only guard so the existing same-key reconciliation path remains available. Exact-price and affordable purchases continue through the existing confirmation and repository authority. A repository-time insufficient rejection now reloads the owner-scoped session after removing the known-failed intent; stale catalog, owner change, and generic uncertain acknowledgement handling remain distinct.
2. `test/screens/shop_page_test.dart`: adds balance0/just-below fake-call and intent0 assertions; visible and semantic balance/price/missing evidence; real in-memory transaction/owned/equipped/outbox snapshot preservation across Cancel/Back; exact-price purchase-to-zero; repository race insufficiency with honest reload and no new mutation; and portrait360x800/light plus landscape800x360/dark at text200% with reachable 48dp controls. Existing affordable, double-confirm, lost-ack same-key replay identity, owner isolation, direct equip, preview composition, filter/scroll/Back, and responsive preview tests remain active.
3. This checkpoint.

No pricing/currency/catalog/model/use-case/repository authority, reward formula, `M3Theme`, global appearance, main/bootstrap, learning/account/consent/research, schema/generated/dependency/native/backend, or other checkpoint was changed. The tracked Shop diff against HEAD contains pre-existing accepted work from earlier cards; this checkpoint does not claim those unrelated lines.

## RED → GREEN / bounded recovery

- New tests were written before production edits. The first portrait/text200% attempt failed before the behavior assertion because an offscreen purchase/detail control was not materialized by the harness; the same balance0 scenario was rerun at the stable functional viewport.
- Valid behavioral RED then failed as intended: balance0 still opened the old executable confirmation and did not show `คะแนนไม่เพียงพอ` (`exit1`, expected one message, found none). No production edit preceded this valid RED.
- After the minimum production branch, focused balance0 passed; balance0 and balance79 then passed together with purchase-call0, intent0, no negative projection, semantics, Cancel/Back, 48dp, and unchanged in-memory snapshots.
- Exact-price and repository-race focused run initially produced one pass and one fixture-assumption failure. The race test expected an empty reward-transaction table, but current repository loading had legitimately projected `creditLegacyCarryV1` from the seed. Investigation confirmed that baseline authority effect; the test was corrected to compare pre-action snapshots rather than deleting or rejecting valid evidence. Both focused cases then passed 2/2.
- The first portrait layout fixture again targeted the offscreen second theme item and failed to materialize it; changing only seed0 to seed1 did not correct that harness path. Within the bounded recovery budget, portrait layout was switched to the first visible filtered wallpaper item while the separate balance0 behavioral proof remained intact. Portrait light and landscape dark dialog checks then passed 2/2. No production layout or catalog behavior was weakened.

## Final current-source verification

All Flutter/Dart commands were serialized and awaited to completion. The final code/test snapshot was unchanged throughout the following verification and review:

```text
flutter test --no-pub test/screens/shop_page_test.dart --reporter compact
```

**Exit0, +23 All tests passed** in about 10 seconds. This includes the new affordability, exact-price, race, semantics and 200% layout cases plus all retained Shop preview/purchase/equip/retry/owner/Back/filter/scroll tests.

```text
flutter test --no-pub test/features/rewards test/features/progress test/features/sync test/config/m3_theme_test.dart test/runtime/reward_appearance_restore_test.dart test/runtime/app_build_info_test.dart test/screens/shop_page_test.dart test/screens/avatar_equipment_screen_test.dart test/screens/production_shell_navigation_test.dart test/features/identity test/features/account/account_owner_isolation_test.dart test/architecture --reporter compact
```

**Exit0, +218 All tests passed** in about 21 seconds. This is the connected local reward/progress/sync/theme/appearance/runtime/navigation/identity/owner-isolation/architecture set with no name filter. Counts overlap the Shop run and are not 241 unique tests.

```text
flutter analyze --no-pub lib/screens/shop_page.dart test/screens/shop_page_test.dart
dart format --output=none --set-exit-if-changed lib/screens/shop_page.dart test/screens/shop_page_test.dart
git -c core.safecrlf=false diff --check -- lib/screens/shop_page.dart test/screens/shop_page_test.dart
```

Run separately in that order after the final test edit: **analyze exit0, No issues found (2.1s); format exit0, 2 files / 0 changed; diff check exit0**.

Runtime inventory at `2026-10-23T06:21:18.3560311+07:00`: `task_runtime_process_count=0`. `Get-CimInstance Win32_Process` checked `dart.exe`, `dartvm.exe`, `flutter_tester.exe`, `dartaotruntime.exe`, `gen_snapshot.exe`, and workspace Firebase/Firestore Java processes. No process was killed after final verification.

## Review disposition / UI evidence limits

- Independent read-only reviewer `/root/mkt_balance_review`: **no Critical, Important, or Minor actionable findings; verdict pass**. It verified the local guard, exact-price path, repository-race reload, generic uncertain same-key retention, semantics, layout matrix, and retained regressions. Reviewer hashes matched the manifest below. The reviewer made no write and ran no Flutter/Dart command; root-owned test/analyze evidence remains authoritative.
- UI/UX guidance was applied narrowly: native disabled behavior is represented by absence of an executable confirm, visible textual recovery rather than color alone, scrollable Material dialog, native button semantics, and existing M3 48dp button tokens. No redesign or new animation was added.
- Evidence is widget/in-memory local testing only. There was no remote asset, network, live marketplace, physical-device pixel, TalkBack, or manual contrast verification.

## Limits / release dependencies / next executable step

The displayed balance remains an advisory snapshot, not a reservation or ledger authority; repository validation still decides purchase outcome. Responsive grid, remote assets/download/connectivity, pricing/catalog changes, and broader marketplace work remain held. No full-repository suite/analyze/build/APK/device test, live backend/provider, security scan, production research flow, deployment, publish, participant enrollment, real-data upload, commit, merge, push, or destructive cleanup was performed.

Engineering completion of this bounded card is not release readiness or deployment/research authority. **Next:** root reviews this checkpoint, the current two-file manifest, and the actual bounded diff; then accepts or returns the card. This card returns the sole writer/Flutter slot and does not self-dispatch another task.

## Final SHA256 manifest

| Source/test path | SHA256 |
| --- | --- |
| `lib/screens/shop_page.dart` | `0677469F2C69712E5DC1AD4522C45161DD63FB9C139DC74C0A0D1FB10BB44362` |
| `test/screens/shop_page_test.dart` | `1CBCB096B710A378637C49D555C3C3C542D688D25614E49917B428AB92E63E26` |

Checkpoint SHA256 is reported separately to avoid self-reference. The manifest, review, and final verification refer to the same code/test snapshot; all unrelated dirty work was preserved.
