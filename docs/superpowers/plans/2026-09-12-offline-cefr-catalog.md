# Offline CEFR vocabulary starter implementation plan

Use executing-plans inline in existing 02fa worktree; one writer, serial Flutter
commands. User approved adding vocabulary while unavailable, following the
3,000-word first-delivery discussion. Preserve six readings and existing data.

Goal: ship a searchable offline 3,000-headword A1–B2 reference catalog with
Thai meanings and source-level provenance, and allow deliberate selection into
the existing personal vocabulary authority. No new database table or automatic
3,000-word insertion. The old 12-word immutable starter is unchanged.

Sources: CEFR-J 1.5 via Open Language Profiles (attribution terms) and NECTEC's
LEXiTRON 2.0 CSV distribution (include full English/Thai license and acknowledgement).
Keep SHA-256 provenance. Do not use the Google frequency list: its license file
does not clearly permit the anticipated commercial distribution.

Level labels are source annotations at headword/POS level, not certified learner
proficiency or sense-level validation. First import includes source translations,
not fabricated examples. Full per-sense examples/editorial approval remains a
separate quality stage, explicitly disclosed in-app and in results.

- [x] Build deterministic validated source join; exact POS mapping, no invented
  translations/CEFR, 3,000 case-insensitive unique headwords preserving display
  capitalization, retained source row IDs.
  Cover all eligible A1/A2 first, then distribute remaining selection across
  B1/B2. Check duplicates, malformed text and selection reproducibility.
- [x] Bundle catalog and attribution assets. Parse with strict schema/identity
  checks; search all 3,000 items and filter levels locally, independent of the
  existing 100-candidate activity query.
- [x] Add catalog screen from Learn reading library. Show Thai labels, total,
  level filter, search, meaning/POS/source and license. A1–B2 only; do not imply
  C1/C2 content exists in this first starter.
- [x] Allow one chosen word/meaning into a user-selected personal category via
  existing VocabularyUseCases; respect capacity 50, owner identity, duplicates,
  source attribution, existing personal rows and SRS. Never overwrite edits.
- [x] Test catalog integrity/search beyond 100, narrow/large-text UI, import
  idempotence/owner/category errors; run focused reading/vocabulary regressions,
  analysis and review. Build source-pinned preview artifact after checks.
- [x] Record delivered count, provenance, quality limits, exact checks and next
  step. Preserve unreviewed content status and do not claim live service UAT.

Completed as an engineering preview; editorial approval remains open as described
above. Results: `docs/development/2026-09-12-cefr-catalog-r7-checkpoint.md`.
Checklist updated after both builds; runtime/asset/test source remains unchanged.
