# Complete CEFR editorial quality and practice integration

User explicitly authorized all remaining CEFR quality/practice work and
subagents. Existing worktree/branch retained. Root is sole runtime/test writer;
three editorial agents own disjoint complete-N.json and sense-review-N.json
plus own reports. No concurrent Flutter/build/codegen commands.

Deliverable: all 5,500 primary meanings/examples reviewed, every dictionary
alternative assessed and useful/correct alternatives offered to learners.
Preserve immutable source catalogs, legacy import IDs and all saved user edits.
Rejected source alternatives are retained as source data with exclusion reasons,
not silently replaced or deleted from personal vocabulary. AI review/estimated
levels remain explicit; human certification is not claimed.

Runtime design:
- Add keyset-paged candidate discovery in the production repository, maintaining
  owner/access/deletion filtering and 100-row page limits. Scan until suitable
  items or end; preserve exact canonical admission and lifecycle checks.
- Extend checksum-pinned overlay to all levels and pin sense-review coverage.
  All-or-nothing optional loading keeps ordinary learning available on corruption.
- Resolve example content by exact normalized word, sense, POS and level, never
  headword alone; reject mismatched user edits. Examples are presentation support,
  not fabricated verified artifact metadata or independent pronunciation scoring.
- Show examples in personal vocabulary detail and after answer/reveal in the
  appropriate existing practice surfaces. Never leak the answer before recall
  or modify evidence/hints silently. Reuse existing practice/session writers.
- Review six readings and aligned questions at the agreed six-lesson scope;
  confirm estimated-level caveats and accessibility. Do not add a new placement
  test or claim validated CEFR assessment.

Checks: RED/GREEN candidate-after-100, owner/deleted/end paging; mapping and
edited-sense rejection; no pre-answer example leakage; all primary/alternative
coverage/pins; cross-review and repair content. Freeze writers before regression,
analysis/build. Device update uses verified binary-safe transfer, preserves
records, and checks actual installed APK hash/UI/restart. Human audio/TalkBack
and external services are separate pending acceptance, not invented results.

- [x] Author missing 3,466 primary entries and review all 10,793 source meanings.
- [x] Cross-review all batches, fix findings and freeze with hashes.
- [x] Implement/test paged candidate discovery and safe example resolution.
- [x] Integrate personal detail and post-answer/reveal practice examples.
- [x] Review six lessons and extend vocabulary integrity/coverage tests.
- [x] Final focused regressions, analysis, source-pinned APK and vivo verification.
- [x] Save exact completion evidence and remaining human-only dependencies.

Runtime progress (integration remains pending the editorial writers): paged
discovery tests 2 and repository paging 1 passed; personal/quiz/SRS integration
has post-reveal and no-extra-evidence checks. A broad run passed 138 and failed
2 new example assertions because earlier unrelated non-CEFR words initiated
an unnecessary shared asset load. Restricting loads to words with CEFR metadata
fixed this: the complete Quiz/SRS suites passed 41 cases. Focused selection and
example tests passed 6; usage-guidance tests passed 4; import contracts passed 2.
The newly written full-coverage and corrupted-sense-file tests are intentionally
RED until all new assets are complete, reviewed and pinned; do not omit them.
Eleven touched runtime files analyzed with no issues. Drift repository has six
pre-existing brace-style infos outside the new paging code, no reported errors.

Six-reading editorial review is recorded in
`docs/development/2026-09-12-cefr-six-reading-quality-review.md`.
Actual source finding: `cefrj15:gook` is a severe racial slur, now explicitly
marked recognition-only in catalog UI/import. Other ordinary headwords retain
useful non-offensive meanings. Source catalogs and saved rows remain unchanged.

All evidence logs for this phase are in
`build/verification/cefr-complete-20260912/`. R11 build/transfer/audit helpers
are prepared there but have NOT run. Next build numbers: manual20, ordinary25.
Current device remains verified R10. Do not claim new 5500-word editorial
coverage or R11 installation until the remaining acceptance checks finish.

Additional focused verification: corrected cooker primary has a distinct null
mapping, while the old saved rice-cooker gloss resolves no unrelated example;
all three example-resolution tests passed (`corrected-primary-example.log`).
No-eligible-word UI now explains that the activity's conditions are unmet;
its RED/GREEN test passed without creating a durable session or attempt
(`empty-guidance-red.log`, `empty-guidance-green.log`). Other old-primary
mapping candidates are adjudicated in the existing-primary report, preserving
equivalent legacy identities. Python validator unit tests passed three cases
when run directly; module-style invocation lacked its tools import path and was
corrected, not treated as a product defect. R11 persistence helper is prepared
but unexecuted. ADB read-only connectivity returned `device` on this continuation.

Editorial batch 1 is author-frozen (1156 new primaries, 1834 source reviews),
and its author is cross-reviewing stable batch 2 drafts. Batches 2 and 3 remain
under author/reviewer work. No final overlay pins or R11 build yet.

Independent read-only runtime review by editorial_one covered the example
resolver/widget and their quiz, flashcard and personal-vocabulary hosts. No
actionable correctness finding: quiz is gated by committed feedback, flashcards
by resettable reveal state, personal detail intentionally reveals; matching
checks spelling/level/POS/sense and the additions contain no evidence writes.
This code review is separate from the focused executable test evidence above.

Final content closure: all three authors and cross-reviewers have stopped writes.
All 5,500 primaries are pinned; source decisions cover 10,793 glosses (8,654
accepted, 2,139 excluded). Structural validation reports no warnings; four shared
sentences across different targets are explicitly adjudicated. Existing 33
primary repairs have an independent reread. Original catalog hashes unchanged.
Editorial_two also independently reviewed paging, overlay failure and import
preservation paths without an actionable finding.

Integration regression passed 204 tests on runtime source fingerprint
`2003ba7e5721fc62fd57a3491766f7a496ee9220059653ceee2666eff2de5d0f`
(1,360 files; current-source gate exit 0, source stable). Evidence directory:
`build/verification/remediation-20260907/cefr-r11-regression-20260912T092317489Z`.
Analysis of 15 touched runtime files reports only the same six pre-existing
Drift brace-style infos listed above (exit 1); no errors or warnings. Do not
describe that analysis as issue-free. Next executable step: build R11 manual20
and ordinary25, audit packaged bytes, then hash-gated vivo update/UI/persistence.

Final delivery supersedes the R11 build step: physical R11 review found the
reading title's hard-coded indigo unreadable against the dark background.
Changed only that title to colorScheme.onSurface, passed the 10 reading tests
and repeated all 204 integration tests on stable runtime fingerprint
`ceac723c48cef5b1937e7694c006558e14ddd312309988135446601813d3a36a`.
R12 manual21 and ordinary26 built from whole-source fingerprint
`76978cc308c1cef3372976ad9add2346f50058932190cdef9f4a6d554bf2f518`.
Both APKs pass the 19-content-file byte audit. Manual21 is installed on vivo,
actual SHA verified, preserved data and restart checks pass. All agents and
task processes have finished. Final evidence and external-only dependencies:
`docs/development/2026-09-12-cefr-complete-r12-checkpoint.md`.
