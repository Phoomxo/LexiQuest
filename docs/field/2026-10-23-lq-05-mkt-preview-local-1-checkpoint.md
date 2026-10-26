# LQ-05 — MKT-PREVIEW-LOCAL-1 truthful local appearance preview

## Section 13.5 handoff / intent and authority

- Card: `MKT-PREVIEW-LOCAL-1`; bounded local Shop preview repair only. It does not authorize marketplace connectivity, remote images, purchase/equip redesign, deployment, or a later card.
- Worktree: `C:\Users\Phet\Documents\LexiQuest`; branch `feature/associative-reading-loop`; HEAD `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`. The existing dirty worktree was preserved; the hashes below identify the verified source snapshot rather than relying on HEAD alone.
- Authority: direct root delegation granted the sole production-writer and serialized Flutter/test/analyze/format slot for the two code/test paths below plus this new checkpoint. No second writer or overlapping Flutter command was used.
- State: **bounded engineering-complete, submitted for root acceptance; RETURN writer/test slot**. No next card was started.

## Ground / outcome / changed files

Read the active card and guardrails, current Shop implementation/tests, `M3Theme.lightThemeFor/darkThemeFor`, reward appearance/catalog contracts, and the existing checkpoint pattern before editing. Pre-card SHA256 values matched the grant: Shop `9691F9E4693E5776BA00CCFA35DF8CBAAA0C2269570E2F3E469738860A8F29CE`; Shop test `DA08466A6C092A498E8A8DDC388202704D2C5515F70AF16A2C4E2B7E485B98F1`. The exact checkpoint path did not exist before creation.

Wrote only the authorized three paths:

1. `lib/screens/shop_page.dart`: passes the current equipped theme/wallpaper into the detail sheet. Selecting `theme_ocean` or `wallpaper_focus` replaces only its own slot, composes the other equipped cosmetic, and renders a scoped `Theme` using the existing M3 light/dark factories. The mini learning surface is static and non-interactive; the app's outer theme is unchanged. Decoration previews retain the existing generic icon/gradient treatment. Preview semantics expose the item name plus owned/equipped/price status, and Close has a 48dp minimum height.
2. `test/screens/shop_page_test.dart`: adds real-token light/dark composition assertions, outer-theme isolation, database/outbox/intent no-write checks, non-interactive semantics checks, and responsive coverage for both Ocean and Focus at 360x800 and 800x360 with 200% text. Existing filter, Back, scroll, ownership, retry, owner-isolation, purchase, and equip cases remain active.
3. This checkpoint.

No `M3Theme`, global app theme, reward authority/model/repository, schema/ledger/generated source, dependency, native/backend, account/consent/research, or other checkpoint was changed by this card. The tracked Shop diff against HEAD contains pre-existing dirty work from earlier cards; this checkpoint does not claim those unrelated lines.

## RED → GREEN / bounded recovery

- Before production editing, the first test load exposed a missing `SemanticsFlag` import in the new harness; that import was corrected. The next attempt stalled because direct Drift futures were awaited inside widget fake time, so the task-owned test process was stopped and fixture setup was moved to the file's existing `tester.runAsync` pattern.
- Valid behavioral RED then failed as intended: Ocean preview returned the outer default primary color instead of Ocean's primary token (`exit1`, assertion failure). No production change preceded that valid RED.
- After the scoped implementation, Ocean light + equipped Focus and Focus dark + equipped Ocean each passed focused tests. One Focus run then reported an undisposed semantics handle after all behavior assertions; the harness was corrected to dispose it before Flutter's end-of-test verification.
- Independent review found no Critical/Important issue and one Minor coverage gap: missing 360x800 light evidence and layout coverage opening only Ocean. The matrix was expanded to both appearance items across light/dark portrait/landscape; focused layout checks passed 6/6. Read-only re-review closed the finding with no new issue.

## Final current-source verification

All Flutter/Dart commands were serialized and awaited to completion. The following final checks ran after the last code/test edit:

```text
flutter test --no-pub test/screens/shop_page_test.dart --reporter compact
```

**Exit0, +17 All tests passed** in about 10 seconds. This includes no-write preview/Back, light/dark token composition, non-interactive semantics, purchase/equip/retry/owner behavior, filter/scroll preservation, and the final responsive matrix.

```text
flutter test --no-pub test/features/rewards test/features/progress test/features/sync test/config/m3_theme_test.dart test/runtime/reward_appearance_restore_test.dart test/runtime/app_build_info_test.dart test/screens/shop_page_test.dart test/screens/avatar_equipment_screen_test.dart test/screens/production_shell_navigation_test.dart test/features/identity test/features/account/account_owner_isolation_test.dart test/architecture --reporter compact
```

**Exit0, +212 All tests passed** in about 20 seconds. This is the connected local reward/progress/sync/theme/runtime/navigation/owner-isolation/architecture set; there was no name filter.

```text
flutter analyze --no-pub lib/screens/shop_page.dart test/screens/shop_page_test.dart
dart format --output=none --set-exit-if-changed lib/screens/shop_page.dart test/screens/shop_page_test.dart
git -c core.safecrlf=false diff --check -- lib/screens/shop_page.dart test/screens/shop_page_test.dart
```

Run separately in that order: **analyze exit0, No issues found (3.4s); format exit0, 2 files / 0 changed; diff check exit0**.

Runtime inventory at `2026-10-23T06:07:26.1300102+07:00`: `task_runtime_process_count=0`. `Get-CimInstance Win32_Process` checked `dart.exe`, `dartvm.exe`, `flutter_tester.exe`, `dartaotruntime.exe`, `gen_snapshot.exe`, and workspace Firebase/Firestore Java processes. No process was killed after final verification.

## Review disposition / evidence limits

- Independent read-only reviewer `/root/mkt_preview_review`: initial **no Critical/Important; one Minor test-matrix gap**. After the root-owned test update and focused 6/6 evidence, read-only re-review marked the finding closed and reported no new finding. The reviewer made no write and ran no Flutter/Dart command.
- The preview uses synthetic in-memory Drift fixtures and widget semantics. There was no remote image, network, live marketplace, physical-device pixel, TalkBack, or manual contrast evidence.
- The implementation creates no temporary equip, purchase, intent, persistence, outbox, or global theme mutation. Existing reward and owner authorities remain the trust boundaries.

## Limits / release dependencies / next executable step

Held items remain held: insufficient-balance UX and broader responsive-grid work were not started. No full-repository suite/analyze/build/APK/device test, live backend/provider, security scan, production research flow, deployment, publish, participant enrollment, real-data upload, commit, merge, push, or destructive cleanup was performed.

Engineering completion of this bounded preview card is not release readiness or deployment/research authority. **Next:** root reviews this checkpoint, current source/test hashes, and the actual bounded diff; then accepts or returns the card. This card returns the sole writer/Flutter slot and does not self-dispatch another task.

## Final SHA256 manifest

| Source/test path | SHA256 |
| --- | --- |
| `lib/screens/shop_page.dart` | `FEDD62ABC53D91AD830A2F19A29ED79CFED2D8A27B7FA9255F7341AEC6A8A44E` |
| `test/screens/shop_page_test.dart` | `A02067F20B3208E7EAAA7E036AAF556A9A72B2996B0B3520D0B7BB24425F398E` |

Checkpoint SHA256 is reported separately to avoid self-reference. The manifest, review, and tests refer to the same final source snapshot; all unrelated dirty work was preserved.
