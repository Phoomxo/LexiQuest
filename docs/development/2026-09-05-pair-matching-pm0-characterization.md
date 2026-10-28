# Pair Matching PM0 characterization

Date: 2026-09-05
Baseline and rollback target: `ca123ddd` (`docs(research): record verified source, full regression and Android artifact`)

## Locked boundary

- Pair Matching is product contract `f10` (`Matching Mode`) inside the existing 8-domain/44-feature catalog. It does not create `f45`.
- `LessonMode.matching` resolves to the quiz parent entry `home/learn/quiz` and child route `learning/matching` through `MatchingModeAdapter`.
- Production delivery defaults to `implementedOff`; `resolve(LessonMode.matching)` returns null. There is no Pair main destination.
- Database schema remains v24 with 48 tables. There is no Pair/Matching star table and stars are absent from the current screen.

## Current behavior

- `MatchingModeAdapter` pins at most six ambiguity-safe word/meaning pairs in deterministic word and meaning orders. Fewer than two safe pairs yields an unavailable board.
- The screen renders the existing `Matching` app bar, Words/Meanings columns, semantic matched-pair progress and a time-remaining message.
- Independent matches produce `matchingPair` recognition evidence through `CurrentActivityEvidenceAdapter`; answer-revealing support produces guided-practice evidence. The UI does not write SRS, mastery, reward or research projections directly.
- `LearningUseCases.startCheckpointedQuiz` and `ExactPinnedLearningActivityRepository.startExactPinnedSessionWithCheckpoint` provide the atomic pinned-session plus initial-checkpoint seam. Current transaction checks owner, lexical revision/checksum and active-session conflict; it does not yet check content-quality reports or a Pair-specific delivery gate.

## Restart, recovery and rollback

- Checkpoint schema is 5; readers accept schemas 1–5. Repository limits are 64 revisions and 64 KiB. The next writer version must be rechecked and introduced reader-first.
- Checkpoints preserve the lexical snapshot, deterministic board, pending evidence, frozen evidence/event contexts, timeout anchor/deadline, pending close and terminal acknowledgement. Restart reconstructs the original session and content even after vocabulary edits/deletion.
- Lost evidence/checkpoint/close acknowledgements retry the frozen identity. Timeout does not invent unanswered evidence. Emergency retirement blocks new actions while accepted work closes through the existing lifecycle.
- The rollback target is `MatchingModeScreen` plus `MatchingModeAdapter` on the f10 child route. New Pair presentation must remain hidden and removable while these legacy semantics stay available.

## PM1–PM8 integration seams

1. Define hidden typed launch/plan contracts that carry source, exact lexical pins, return target and presentation without changing evidence payloads.
2. Extend atomic start validation for Pair delivery and content-quality eligibility while preserving retry identity.
3. Evolve checkpoint schema reader-first within the existing revision/size ceilings; do not write on timer ticks.
4. Put interaction, repair, timeout choices and replay in a shared reducer/controller used by both renderers.
5. Continue submitting answers only through the existing evidence gateway with recognition/guided classification.
6. Project stars from committed terminal evidence in a read-only/application projection; do not add a table, currency or reward authority.
7. Keep Standard/Adventure renderers semantic-equivalent and preserve the accepted plan when Adventure turns off.
8. Retain default-hidden delivery and verify feature-off navigation, restart recovery, exact 8/44 mapping and rollback before any internal enablement.
