# CEFR content and UI R10 — 2026-09-12

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch
`codex/pair-matching-pm0-pm8`, HEAD `788e90e62b1694c20945734787723c168b6a6ab2`.
User authorized editorial quality work, then UI cleanup using AllTCAS-style
organization. R9 editorial details remain in
[the R9 checkpoint](2026-09-12-cefr-editorial-r9-checkpoint.md).

## Delivered

- Curated primary meanings and original English/Thai examples for A1 933 and
  A2 1,101 words (2,034 total), authored/reread and independently cross-reviewed
  by AI. R10 preserves every R9 content asset. B1–C2 3,466 words and alternative
  dictionary senses remain pending. No human/CEFR certification is claimed.
- Catalog: overview, separate search/filter area and spaced word cards; the
  whole page scrolls with large text/short viewport.
- New full-page word detail: primary meaning card, English example and Thai
  translation sections, AI-review label, expandable dictionary alternatives
  and level explanation, fixed primary import button.
- Reading library: section headings and spaced level cards. Fixed the existing
  reader replacement behavior so Back returns to the library, allowing another
  level to open. No changes to import identity, stored content, research flags,
  lesson evidence, database or synchronization.

Presentation uses original LexiQuest Material 3 styling and the organization
principles recorded in the existing AllTCAS acceptance delta. No external
AllTCAS screen/artwork was copied or newly audited. This is a cleanup of the
catalog, word detail and reading library, not a whole-app UI redesign.

## Current-source verification

Evidence directory `build/verification/cefr-ui-20260912/`:

- `reading-navigation-green.log`: 50 tests passed (local reading library and
  choose-mode routes, including A1 → Back → A2).
- `remaining-regression-green.log`: 58 tests passed (all vocabulary tests,
  catalog/editorial/reader screens, adapters and Thai encoding). Together these
  disjoint final runs cover 108 tests on unchanged implementation source.
- `analysis-final.log`: seven touched Dart files, no issues.
- The new short-viewport test first reproduced the old RenderFlex overflow;
  reading-back RED reproduced the missing return route. Tests now scroll to
  lazily built cards rather than assuming every item is already mounted. Prior
  failing logs remain as evidence; no assertions were weakened or skipped.
- Independent read-only review found the reading-back issue; it was reproduced
  and fixed. No other actionable import regression was found.
- Focused diff/whitespace check passed. No full repository/backend suite or
  human TalkBack/audio/camera/two-device UAT was performed this round.

Both debug previews passed source gates with whole-source fingerprint
`57adb34a42fa0ada319df9859cae895fbebe39b1f3db26d5ffb7e9deb494434b`
(1,598 files), runtime gate fingerprint
`122d486f2f2558ff820ef65950838b4b30da35b696268e3f87e0d17ca6d4e2ff`
(1,348 files). R9→R10 manifest comparison shows only three screen files, four
screen test files and two plans changed. No content, importer or schema changes.
Plan checkboxes were updated after builds; final runtime/assets remain those
verified in the build. See `final-source.json` for the post-document snapshot.

APKs in `build/verification/motivation-ui-20260908/device/`:

| Artifact | State | SHA-256 |
| --- | --- | --- |
| `lexiquest-learning-preview-manual-v19-thai-r10-debug.apk` | Installed vivo; 153,868,027 bytes | `913ba647af99093bf475490733be7f8f55ef47a2928dc1cd678a9a255bf9b71a` |
| `lexiquest-learning-preview-v24-thai-r10-debug.apk` | Built, not installed; 226,711,577 bytes | `25d3566ff456a6aee9dd8e10d53016f69e5b0dd06c2f94ce571d435f3cd171a7` |

`apk-content-audit.json` verifies all 13 vocabulary assets/licenses/notices in
both APKs equal current source. Both are preview/debug builds, cloud sync off;
not a production release or research rollout.

## vivo verification

vivo V2041, serial 9582188822004C6: 37 binary-safe push parts verified, assembled
APK hash equals PC and installed base APK; `pm install -r -t` succeeded.
versionCode 19, signer unchanged, firstInstallTime remains 2026-09-01 00:27:20.
`device/install.json` proves durable data hashes preserved. Historical synthetic
code_cache stores cleared by Android were restored with identical backup hashes.

Native checks: Learn → library; A1 → Back → library → A2 → Back; scroll to catalog;
catalog coverage 2,034/5,500; about example/translation; expand alternatives;
scroll while import button remains reachable; re-import about to its category.
`persistence.json` proves all 21 vocabulary rows and nine other checked tables
exactly equal R9, both after UI use and restart. No duplicate about row, new
learning/research evidence or changed historical record. Relaunch PID 32692,
AndroidRuntime/flutter error log empty. Device left at manual launcher.

Screenshot evidence under `build/verification/motivation-ui-20260908/device/manual-ui/`:

- Before: `r9-catalog-20260912.png`, `r9-about-example-20260912.png`.
- After: `r10-library-20260912.png`, `r10-catalog-20260912.png`,
  `r10-about-example-20260912.png` (all visually inspected).
- Interaction: `r10-library-back-from-a1-20260912`, `r10-reading-a2-20260912`,
  `r10-library-back-from-a2-20260912`, `r10-detail-scroll-20260912`,
  `r10-about-reused-20260912` (PNG/XML/JSON).

## Remaining work

B1–C2 editorial pass (3,466 words), other UI surfaces if requested, human speech/
listening acceptance, paid AI provider/model/budget, two real sync devices and
real camera model comparison remain as previously recorded. No active shell,
Flutter build/test process or content writer remains. No commit, merge, deploy,
destructive cleanup or policy modification was performed.
