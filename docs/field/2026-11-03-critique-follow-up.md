# Version23 critique follow-up

Disposition: all five findings corrected and verified within the bounded offline
scope. Final application source `dc740a8e`, signed version1.0.0+25 installed on
Vivo V2041 without clearing data. Final hub render confirms one filled primary
action; the generic practice action is outlined. Thai results and original
history remain intact. Artifact/install/device receipts are under critique35.
APK SHA256: `5cbc1d43c59c682aa1a7b813d6d0780f4afae7624ff5fbe979a0e380349b716f`.
AAB SHA256: `bdeb4f07035231dee28f118187a967c24e6f96549cebeacff2cdbddc54d4375f`.

Worktree: `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`.
Branch: `codex/remaining-system-readiness`. Baseline: `95c91d91`.
Scope: all five findings in the archived 2026-11-03 score/hub/report critique.
Cloud A/Billing, payments, public release, Research enrollment and recording
remain excluded. This change does not certify external services or audible UX.

## Changes

1. The existing recall recommendation appears before resume and companion
   content. Its word and suggested action stay visible; evidence explanations
   and seven manual alternatives expand under one labelled control.
2. Zero resumable rounds use a compact status and View history link. Positive,
   loading, failed and retired-owner paths retain their existing guards.
3. ScoreScreen owns one language value, including its RecordedTimeView. Existing
   Thai callers keep Thai; bilingual Matching/native resume forward their value.
   The time explanation expands on demand only on the score page.
4. The score action says Back, matching its existing callback or route pop.
   It does not claim that every caller returns to the activity picker.
5. Inbox keeps the report ID selectable inside source details. Offline send and
   receipt controls are absent while the existing offline status remains visible.
   Connected explicit send/refresh and other shared status consumers stay intact.

No database migration, progress/reward counter, report identity or transport
authority changed. Reusing the existing data shapes follows Model the Domain.
Neutral Back wording avoids adding destination state to existing navigation.
Prove It Works requires current tests and renders, not the older version23 images.

## Review and evidence

Independent source review accepted the implementation with one visual check:
inspect the hub for competing primary actions. No new comments or suppressions
were introduced. Root preserved unrelated untracked critique/failure files.

Evidence directory:
`D:\LexiQuest-Storage\maintenance\2026-11-03\critique35`.

The first focused run passed64 and failed2 because a new assertion cast the
EditableText found inside SelectableText to its parent type. The finder now
selects the SelectableText ancestor. No production guard or assertion was removed.
The corrected focused suite passes66 tests. Score's changed Back label has an
updated and visually inspected large-Thai-text golden; its focused check passes.
Integration across shared score routes, hub/motivation, Matching and content
reports passes246 tests. Static analysis reports no issues. Full5575 evidence
belongs to the prior version23 source and is not claimed for this change. This
pass uses focused and affected-subsystem regression; unrelated backend/policy
suites were not rerun at that point.

The owner then requested completion across all44 capabilities. Full regression
on `1e6e8960` passes5581 with zero failures and unchanged1350 inputs. The signed
version24 package passed native/model integrity and installed with matching hash,
preserving all data. Physical checks confirm Thai score text, folded explanation,
Back to original History, retained4/4 and1/1 sessions, report details and absent
offline send controls. See install24-result.json and device24-result.json.

Device24 also revealed two competing filled actions. The final small hub fix
demotes the generic button when a recall entry is composed, keeping the existing
callback and the primary fallback when no recall entry is available. The new
visible-primary assertion fails before the fix and passes afterward; the hub,
resume, layout and motivation suite passes60. Only choose_mode_screen.dart and
recall_ladder_entry_flow_test.dart differ in Flutter inputs from the full run.
Final version25 artifact/device evidence is recorded in the disposition above;
version24 is not final visual acceptance for the hub. No independent artifact verdict is claimed because that
reviewer's model quota was exhausted; root retains measured package evidence.
