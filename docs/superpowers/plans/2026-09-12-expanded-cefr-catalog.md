# Expanded CEFR Catalog Implementation Plan

Use executing-plans inline in the existing 02fa worktree; one writer, serial
Flutter test/build. User authorized expanding the main inventory to 5,000 and
adding a separate C2 supplement while unavailable. No extra approval gate.

Goal: preserve all original 3,000 rows/meanings/import identities, add 750 B1,
750 B2 and 500 C1 to the main pack; offer 500 C2 separately (5,500 unique total).
Use CEFR-J 1.5 for A1–B2 and Octanove 1.0 for C1/C2, exact spelling/POS joins to
LEXiTRON. Source-level labels remain approximate and translations unreviewed.

Architecture: keep original immutable asset/namespace. Bundle a 1,500-row CEFR-J
extension, separate CC BY-SA 4.0 advanced level index (with source and changes
notice) and independently licensed LEXiTRON translation lookup. Join read-only
at runtime; no database migration, no auto-import or changes to learning/rewards.
Default browsing/search covers 5,000 main words; C2 dropdown explicitly selects
the supplement. Preserve old import sources and use a stable new namespace for
new entries. Keep capacity 50, owner gates, idempotence and user edits.

- [x] Generator tests RED: expansion preserves originals, excludes duplicate
  headwords across sources, exact quotas, insufficient-source failure.
- [x] Implement `tools/build_expanded_cefr_catalog.py`, extend old join with
  optional levels/prefix without changing default output. Generate independently
  pinned extension/profile/translation assets, source CSV and license notices.
- [x] Dart tests RED then loader/integrity validation and stable per-entry import
  namespace. Validate 5,000/500 split, C1/C2, source-pin corruption and legacy IDs.
- [x] UI: counts/main/supplement labels, C1/C2 filter, attribution. Test narrow
  large-text UI and C2 search/selection, import/update retention.
- [x] Focused regression + analysis + deterministic rebuild audit. Build R8 manual
  v17 and ordinary v22 with stable source gates. Update vivo with hash-checked
  transport and -r -t, preserve existing data; verify C1/C2 and legacy April.
- [x] Record evidence, source/APK hashes, limits and outstanding editorial work.

Out of scope: certified CEFR curriculum, complete C2 lexicon, 100-item legacy
activity query, 6-reading expansion, paid AI/service/human audio/device UAT.

Engineering preview completed. Results in
`docs/development/2026-09-12-expanded-cefr-r8-checkpoint.md`.
Checklist updated after builds; runtime/assets/tests were not changed afterward.
