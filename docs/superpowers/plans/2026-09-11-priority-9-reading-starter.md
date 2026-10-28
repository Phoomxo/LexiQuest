# Priority 9 reading starter implementation plan

Use executing-plans inline in the existing task worktree. User requests continued
implementation; no additional approval gate or production rollout is implied.

Goal: replace placeholder CEFR reading with usable original local passages,
without presenting local text as generated AI or certified CEFR material.

Architecture: a versioned immutable local reading catalog, six provisional
level entries A1–C2. Existing vocabulary/session/evidence authorities remain.
The current reader resolves a passage for its existing canonical word level;
it does not assign levels to unclassified words or bypass availability checks.
The legacy AI adapter honestly returns local fallback provenance and reports
only requested target words actually present in the passage.

- Add tests for all six passages, unique stable identity, invalid-level
  rejection, honest fallback and target-word coverage. Observe failures.
- Add `lib/services/local_reading_catalog.dart`; integrate it into existing
  `ai_reading_content_adapter.dart` and `ai/local_content_fallback.dart`.
- Replace the one-line CEFR route content with a catalog passage and expose
  the provisional local-content label in `cefr_article_reader_screen.dart`.
- Run focused service, reader and navigation checks. Review source diff.
- Archive a new test APK at the integration checkpoint; record content-review
  and physical acceptance limits. Do not claim a validated CEFR curriculum.

Priority 8 physical human-speech acceptance remains external; automated and
native microphone lifecycle results are recorded in its checkpoint. Continuing
priority 9 follows the user's latest instruction to keep working to completion.

Device-driven refinement: the R3 vocabulary route selected an unclassified word
before checking CEFR and abandoned the session. The reader entry now first opens
`LocalReadingLibraryScreen`, allowing all six local passages without invented
vocabulary evidence. Its separate vocabulary-practice action retains the typed
session path. That loader filters the repository's bounded first 100 candidates
before canonical pinned admission and revalidates availability afterwards.
The repository does not offer paged CEFR selection; larger collections beyond
this candidate window remain a limitation of vocabulary-linked practice, not
of the six local readings. Error/empty pages now have a Back app bar.

Verification: 292 integration tests, three opt-in real-bootstrap scenarios,
and focused reading service/UI checks passed. Analyzer: no errors/warnings,
four inherited test-style infos. R4 physical verification/build recorded in
the development checkpoint once complete. Content levels remain provisional.
