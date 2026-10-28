# PM8 root bounded integration advisory — implementation in progress

Read-only source inspection 2026-09-06 in C:/Users/Phet/.codex/worktrees/02fa/LexiQuest, HEAD3bdb5f56 with evolving PM8 source. Not final independent review or executed test evidence. Main retains sole Flutter/Dart tooling; root changes no source/test. Both observations sent to main for correction and focused verification.

## Byte reservation across owner changes

Main requested review of replacing codec.frozenOccurrenceByteBound's exact plan-owner contribution with maximum allowed owner encoding. Current code uses two owner/actor JSON strings, while LearningEvidenceContract.validIdentifier allows256 Unicode scalars. A safe absolute per-string JSON bound is6*256+2 including quotes. This is independent of immutable plan's stricter UTF-16 length check.

Unconditionally replacing the exact original owner in every historical reservation raises an ASCII256-owner bound by2560B. The prior admitted64632B near-ceiling reservation would become67192B; historical same-owner mandatory continuation could fail even without an owner upgrade. Relevant callers include coordinator timer availability, dispatch, pending capture/retry, flush and timer transition; repository uses capacity for initial admission. Decoder structural acceptance alone does not prove mandatory continuation remains possible.

Suggested minimal compatible approach: retain default exact-P semantics, pass authenticated runtime R into capacity projections for a recovered R coordinator, and check destination R capacity inside upgrade preflight before category/word mutation. For an already frozen historical occurrence, reserve the greater of its actual bytes and future R frozen bound; do not reject a long old actor merely because destination R is shorter. Authentication and actual frozen schema bounds remain mandatory. Do not change immutable bytes or pure engine owner namespace. Prove current same-owner near-ceiling completion, maximum destination owner encoding, and long-old-actor/short-current-owner pending replay. Main chooses implementation after these checks.

## Legacy actor selector overlap

The evolving learning_use_cases.dart first-write actor-preservation selector uses promptMode='matchingPair' and providerProvenance='pinned-lexical-matching'. These values are also used by the unchanged legacy MatchingModeAdapter captureMatching path. Its restoreMatching path preserves the old pending actor. Therefore provider strings alone do not distinguish an authenticated Pair6 reservation from legacy pending retry.

Existing exact regression: test/features/learning/matching_mode_adapter_test.dart, 'pre-write guest pending retry uses current account actor after upgrade' (around1667 at inspection) retains guest actor in legacy pending schema4 then expects first NEW event actor=current account. The adjacent 'post-write guest pending recovery preserves historical actor on exact replay' protects existing committed replay. Root did not run either test. Main was asked to narrow first-write Pair preservation through canonical strict Pair admission (repository remains authority) and run both controls. No frozen EvidenceContext/EventEnvelope field or generic first-write relaxation is justified.

## Inspection recovery

One initial bounded rg included nonexistent lib/core. After inspecting the error, root discovered actual identifier/local-owner files with rg --files lib and read those paths. No retry of that missing root, source write, test run or process was performed.
