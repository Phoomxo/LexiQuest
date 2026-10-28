# Editorial batch 2 — 2026-09-12

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`  
Branch: `codex/pair-matching-pm0-pm8`

Completed 678 of 678 assigned headwords: A1 shake–zoo (255), A2 ability–friendship (423). The asset is `assets/content/cefr_editorial/batch-2.json`. All have `primary-v1` and `ai-reviewed`; after cross-review corrections, 631 reuse a selected source meaning index and 47 have independently authored meanings with a null index. No POS overrides were necessary.

## Editorial process

Read all 678 source entries, including POS and all source meanings, in indexed blocks of 100/78. Authored each gloss, English example, and Thai translation individually in seven scratch blocks. No automatic example-sentence templates, copied dictionary quotations, paid APIs, or external model batch generators were used. Assembly only serialised the authored rows and attached source IDs.

Read all 678 authored rows a second time, reviewing meaning, POS, grammatical sentence, exact headword, capitalization, and translation together. Re-read sections hidden by output truncation. Second-pass corrections included `Thursday` ("stays open late" to match Thai เปิดถึงดึก), the Thai royal term in `death`, translating `lock` precisely in `evidence`, and natural present-progressive planning in `flight`.

## Decisions requiring attention

- Used genuine noun constructions for shake, smell, smile, spell, stand, stop, surf, swim, throw, try, turn, underline, visit, vote, walk, wash, worry, brainstorm, crisp, dislike, escape, express, fix and float. These do not silently switch to the more familiar verb/adjective senses.
- Used standalone pronouns for some, these, those, another, which and whose; determiner uses for this, the and your; adverb uses for across, besides, deep and enough. Assistant is attributive before manager; adult, comic, chemical, audio and east modify nouns.
- Authored null-index senses when the dictionary supplied an inaccurate, absent, differently scoped or different meaning: for example so (result), that (content clause), spy (สายลับ), bored (feeling bored), apparently (reported/inferred), apply (สมัคร), company (บริษัท), audio (sound), bargain (good-value purchase), and feature (characteristic).
- `year` uses source index 2 and does not repeat the inaccurate orbital-day figure. `dinosaur` uses a neutral independently authored Thai name instead of the source's overbroad size assertion. `clone` is an independently authored duplicate sense in an explicit game example, avoiding unsupported biological detail. `angel` and `curse` explicitly occur in stories.
- Preserved catalog spellings and capitalization such as T-shirt, TV, Sunday, Wednesday, yoghurt, cheque, favor, colorful and behavior. The inherited list mixes US/UK spelling; individual examples are grammatical, without claiming a uniform dialect conversion.
- Repeated note wording for straightforward items records POS/sense review only; it did not generate the example. Tricky rows have specific notes. The presence of a note is not a quality certification.

## Validation and limits

Read the assembled JSON back using PowerShell `ConvertFrom-Json`, comparing against `input-2.json`: 678 entries in the exact input ID order; 678 unique IDs; zero invalid source indices, zero missing case-insensitive exact headword tokens, correct reviewed status, and zero duplicate English examples. `git diff --check -- assets/content/cefr_editorial/batch-2.json` reported no whitespace errors. Content is new/untracked, so the JSON checks and editorial reading provide the substantive file evidence rather than an empty tracked diff.

Initial reviewed asset SHA-256: `B3F727DC279080BDCB92C18D9B6A6D71BB6A4C852F2558BD16D4C733FF678B43`.

## Applied cross-review corrections

Read all findings in `2026-09-12-editorial-cross-review-2.md` and rechecked the actual source meanings before editing. Applied seven corrected IDs:

- student, video, chef, association and fancy now use null source identities: the curated general learner, modern video, professional cook, organised association and elaborate clothing senses differ in scope from the source meanings.
- the now says `Please close the door after you come in.` so the English explicitly matches the incoming direction in Thai.
- up uses null, rather than the reviewer's suggested index 1. Source `ไปตาม` is a broad along-path sense and `ข้างบน` is positional; neither explicitly retains the uphill direction of `ขึ้นไปตาม` / `We walked up the hill.` An independent identity is the conservative choice under the exact-equivalence contract. Root was informed of this reasoned variation.

Reread all seven changed entries on the final asset. Read-back checks on the corrected JSON: 678 IDs in input order, zero index/status/token errors, zero duplicate English examples. No POS changed. Final asset SHA-256: `1904357F4294FE2988D85E4AE1127EBEAEF027CC6F8C6848C7023739F5219851`.

One initial multi-hunk patch was rejected because the requested hunks were not in source order (association occurs before chef). A read-only reconciliation confirmed the original hash and that no partial changes were applied; sorting hunks by actual entry order corrected the operation on the first recovery attempt. No unresolved write or process remains.

This is AI-authored and AI-reviewed learner content, not human certification or independently established CEFR validation. Structural checks do not prove language quality. Full cross-review is complete and its corrections are applied; root's final acceptance and runtime/importer integration checks remain pending. No Flutter tests, builds, shared catalog changes, runtime edits, or deployment were performed by this batch worker. No processes remain running. The next step is root's integration verification of this frozen asset.
