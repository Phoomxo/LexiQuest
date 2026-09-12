# Cross-review batch 1 — 2026-09-12

Reviewed **all 678 entries**, index 0–677, in `assets/content/cefr_editorial/batch-1.json` against `build/verification/cefr-editorial-20260912/input-1.json`. Read actual meaning, English example, Thai translation, assigned POS, and selected source meaning for every row, in blocks 0–99, 100–249, 250–399, 400–549, 550–677. Read the author's review notes; inspected complete source alternatives and entry notes again for flagged/ambiguous cases.

Reviewed asset SHA-256: `60E0DC43D8BACEFC123B08C62E3DAD8A5494BC331A4D7FD59AA1B54BE11C6702` (matches writer's frozen hash). Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`.

## Actionable corrections

1. **`cefrj15:set` — Thai translation obscures the time being set.**
   - Existing English: `I set my alarm for six every night.`
   - Existing Thai can suggest setting the alarm at six every night, whereas English sets its ringing time to six and performs the setup nightly.
   - Replace `translation` with **`ทุกคืนฉันตั้งนาฬิกาปลุกให้ดังตอนหกโมง`**.
   - Keep other fields, including source index 3.

2. **`cefrj15:grass` — preserve the present-time statement.**
   - English: `The grass is wet this morning.` Existing Thai `หญ้าเปียกเมื่อเช้านี้` shifts the natural reading to a past morning observation.
   - Replace `translation` with **`เช้านี้หญ้าเปียก`**.
   - Keep other fields.

3. **`cefrj15:cool` — remove unnatural experiencer wording in Thai.**
   - English: `The evening air feels cool.` Existing Thai `อากาศยามเย็นรู้สึกเย็นสบาย` makes the air itself the experiencer.
   - Replace `translation` with **`อากาศยามเย็นเย็นสบาย`**.
   - Keep other fields. This is a naturalness improvement, not an English grammar defect.

4. **`cefrj15:peace` — use a conservative independent source identity for tranquillity.**
   - English/Thai correctly demonstrate quiet tranquillity: `I enjoy the peace of the garden.` / `ฉันชอบความสงบของสวน`.
   - Source index 1 is `ความสงบเรียบร้อย`, normally orderly peace/public order; the other source sense is a peace treaty. Neither explicitly gives this garden-tranquillity sense. These are related senses, but the import contract requires equivalence rather than merely related meaning.
   - Replace `sourceMeaningIndex` with **`null`**.
   - Replace `meaning` with **`ความสงบเงียบ`**.
   - Replace `translation` with **`ฉันชอบความสงบเงียบของสวน`**.
   - Replace `reviewNote` with **`Tranquillity sense authored independently; source public-order and treaty glosses are not used as equivalent import identities.`**
   - Keep English, ID, sense key and status. This is a conservative mapping correction, not a claim that the source Thai wording can never overlap in ordinary speech.

## Decisions reviewed and retained

- `its`: `partOfSpeechOverride: determiner`, null source identity, and `The dog wagged its tail.` are internally consistent. The original catalog remains unchanged.
- `bye` and `dig`: the actual examples genuinely use sports-pass and archaeological-site nouns, respectively. Writer's review documents American Heritage and Merriam-Webster corroboration. This cross-review checked the source rows, examples and author notes; it does not claim a new independent browse of those reference pages. Neither sense is independently certified as A1; that level belongs to the inherited headword inventory. No forced farewell/verb substitution is recommended.
- Other potentially misleading POS were checked in context, including noun call/catch/check/cook/cry/drive/feed/finish/hope/kick/kiss/look/move/paint/pay/play/purple/ride/run/saw/self; adjective close/front/gold/key/only/orange/open; and adverb about/above/before/behind/below/alone/along/no/much/lot. Their actual examples support the intended constructions.
- Grandparent terms give the correct explicitly stated maternal/paternal relationship in the English and Thai examples. Month/day names, CD, I, Miss, OK and Olympics preserve natural capitalization in sentences.
- Null-index repairs such as biscuit, e-mail, gray, ideal, mobile, rice and never avoid importing an unrelated or obsolete source meaning. No further mandatory English grammar/POS correction was found in the 678 rows during this reading.

## Limits and next step

This is an independent AI editorial reading of every entry, not human approval, independent CEFR sense certification, or proof of learning efficacy. No structural test result was used as evidence of language quality. Read-only access to batch 1 was maintained; only this findings file was written. No Flutter/build/runtime operations or processes were started.

Original writer should apply the four corrections, reread the changed entries, refresh the asset hash and original review counts (one additional null identity), then hand the frozen result to root for integration verification.
