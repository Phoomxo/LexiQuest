# CEFR editorial R9 checkpoint — 2026-09-12

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch
`codex/pair-matching-pm0-pm8`, HEAD `788e90e62b1694c20945734787723c168b6a6ab2`.
Pre-existing modified/untracked work preserved; no commit, deployment or cleanup.

## Editorial delivery

One curated primary Thai sense, original English example and faithful Thai
translation for all 2,034 A1/A2 headwords: A1 933, A2 1,101. Three writers read
their full source batches, authored/reread every entry, and cross-reviewed all
three batches. Reports: `2026-09-12-editorial-batch-{1,2,3}-review.md` and
`2026-09-12-editorial-cross-review-{1,2,3}.md` in this directory.
All 17 cross-review corrections were reconciled (4 + 7 + 6 IDs).

Final mappings: 1,918 equivalent original sense identities and 116 independent
editorial identities. `its` alone has a determiner override; original POS is
preserved and shown with original dictionary alternatives. The base catalog
and all R8 expansion assets remain byte-identical. Three shared example texts
are valid for two target words each: hand/raise, more/need and on/table; these
are intentional acceptable cross-word reuse, not duplicate headwords.

Final batch SHA-256:

- 1: `781581eaee3de66689359ba3768a1d42bbc1407539ca7d28313a075c836b2945`
- 2: `1904357f4294fe2988d85e4ae1127ebeaef027cc6f8c6848c7023739f5219851`
- 3: `d85708ae5ea49306fe31dc5e3e5c7ab3a4a9ffafcf5996f4e12415f80db41435`

This is AI editorial review, not human approval or CEFR certification. Source
levels concern headwords and do not certify every specialized sense. B1–C2
3,466 headwords and unselected dictionary senses remain pending. Examples are
catalog presentation content, not verified quiz/RAG evidence or personal-word
rich metadata. No paid AI API or human microphone evaluation was performed.

## Implementation and verification

New immutable checksum-pinned overlay/parser/manifest, optional all-or-nothing
fallback to the 5,500-word catalog, selected-sense import preserving legacy
source identity and user edits, curated/pending UI and bilingual examples.
No schema migration or new learning/reward authority.

Evidence root: `build/verification/cefr-editorial-20260912/`.

- `focused-final.log`: 9 new parser/overlay/import/UI tests passed.
- `regression-final.log`: 106 tests passed: all vocabulary tests, catalog and
  editorial screens, local reading library, CEFR reader, choose-mode, AI/voice/
  reading adapters and Thai encoding. This is a focused regression, not the
  entire repository suite.
- `analysis-final.log`: eight touched Dart files, no issues.
- Python generators 4 + 2 and editorial validator 2 tests passed (8 total).
- `audit-final.json`: exact 2,034 coverage, no warnings; structural validation
  explicitly does not certify language quality.
- Independent read-only runtime review found no actionable correctness issue.
- Expected RED tests and a corrected widget test event-loop helper failure
  remain in earlier logs. No tests were weakened/skipped. No running processes.

Both debug preview builds passed with unchanged whole-source fingerprint
`5a4dab58b274006fffdd04f3304ac29811764d5687fce1998d382a08e1ef73c3`.
Runtime gate fingerprint `5e190dbaea65524955ef9937abcb84196383c83cacfd0263af8dffc71eb0ebcb`
(1,347 source files). `apk-content-audit.json` proves all 13 vocabulary content/
notice/license assets in each APK equal their workspace files.

- Installed manual R9 v18, 153,860,359 bytes:
  `33562d1583cd1d3361e7613056d5f5e002ff440daeb24e7a99fbd69d1e174aa5`.
- Ordinary R9 v23, built but not installed, 226,705,945 bytes:
  `11f53d238a92027e6cae1b8f344ac1385a4c7bba63bc93d5009d135f0c46713b`.
- APKs archived under `build/verification/motivation-ui-20260908/device/` with
  `lexiquest-learning-preview-[manual-]v{18|23}-thai-r9-debug` stems.

## vivo evidence

vivo V2041, serial 9582188822004C6. Binary-safe 37-part `adb push -Z`, each
part hashed, Android concatenation, full SHA equals local APK and actual
installed base APK. `pm install -r -t` success, versionCode 18, same signer,
firstInstallTime remains 2026-09-01 00:27:20. `device/install.json` verifies
all durable data hashes unchanged; package-manager-cleared historical synthetic
code_cache stores were restored from a verified backup, with exact hashes.

Native UI: Learn → library → catalog; global 2,034/5,500 coverage; English/Thai
examples for about, April, its and A2 itself; correct determiner override and
original-POS label. about added twice and legacy April re-imported. Existing
20 words remained exactly unchanged, only one about row added (21 total),
stable `cefr-editorial-r1/about/primary-v1`; April remains one original row.
Owners 2, categories 2, sessions 3, configurations 2, attempts 11, reading
events 0, events_v2 102, time segments 7, research proofs 0: all exact rows
unchanged. Reopen preserves all rows; no AndroidRuntime/flutter error output.
See `persistence.json`, R9 sqlite snapshots and `r9-relaunch-errors.log`.
Screenshots in `build/verification/motivation-ui-20260908/device/manual-ui/`
with `r9-` prefix. Device left at manual launcher after restart.

## User steering and next action

User requested UI cleanup after editorial work, citing AllTCAS organization.
Editorial R9 checkpoint is complete. Next: organize the catalog and example
detail with readable spacing, clear sections and progressive disclosure,
using original LexiQuest Material 3 styling and existing data/import behavior.
R9 screenshots are the before evidence. Verify responsive text and interactions,
then build/update a new preview; do not reuse R9 immutable evidence paths.
