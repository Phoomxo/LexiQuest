# Thai menu layout polish implementation plan

**Goal:** Address the user's request for readable Thai system labels and clearly separated menu cards on vivo.

**Architecture:** Continue the approved 2026-09-01 Thai navigation design using existing glossary, routes, callbacks, feature gates and Material 3 theme. Apply bounded presentation corrections to the existing worktree; no new navigation or learning authority.

**Design:** Keep the single-column phone list with 12 px clear space between cards, 16 px interior padding and 24 px between sections. This preserves reading order and accommodates Thai at 200% text size. A multi-column phone grid would shorten labels and reduce readability; a complete navigation redesign would exceed this correction. Use Thai for product-owned labels, retain English learning material and identifiers.

**Tech stack:** Flutter / Dart, existing widget tests and Android debug fixture.

- [x] Add focused regression coverage for card separation, large text and Thai action copy; observe baseline failures.
- [x] Improve Choose Mode, settings/profile card spacing and product-owned system labels. Preserve callbacks and feature visibility.
- [x] Translate the session configuration form's labels/options and keep policy values unchanged; update existing visible-label assertions.
- [x] Separate the manual device launcher's controls into readable Thai sections; preserve its isolated data and voice authority.
- [x] Run affected widget/navigation/configuration tests and analysis; inspect diff. Build and visually inspect the updated manual app if the connected device is available, retaining the original APK backup.
- [x] Record exact evidence and remaining human UAT requirements. Earlier 4,852-pass source evidence predates these edits.

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch `codex/pair-matching-pm0-pm8`; base `788e90e62b1694c20945734787723c168b6a6ab2`. Preserve the existing media viewport and Adventure performance corrections and all untracked evidence. Do not publish or enable research enrollment/upload.

Completed evidence and device handoff: `docs/development/2026-09-08-ui-layout-results.md`. Physical inspection additionally required a SafeArea header correction and explicit dependency ownership for repeated manual-app opening; both were verified with regression tests and on vivo.
