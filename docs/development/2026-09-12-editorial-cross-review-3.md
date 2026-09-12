# Cross-review batch 3 — 2026-09-12

Read **all 678 entries (0–677)** in `assets/content/cefr_editorial/batch-3.json` against `build/verification/cefr-editorial-20260912/input-3.json`, including every English sentence, Thai meaning/translation, POS and selected source gloss. Reading blocks: 0–119, 120–269, 270–409, 410–549, 550–677. Read the writer's review and re-opened complete source alternatives for flagged cases.

Reviewed SHA-256: `EA2362F090918EC936B246ABC7C3B38A4FBE1D9EDE9C2678269C746847DC5346`, unchanged from the supplied frozen hash. Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch: `codex/pair-matching-pm0-pm8`. No batch asset was edited.

## Six precise corrections

1. **`cefrj15:furniture` — direction in Thai.** English `We moved the furniture away from the window.` means increasing distance from the window. Existing `เราย้ายเครื่องเรือนออกจากหน้าต่าง` can read as removing furniture from/out of the window.
   - Replace `translation`: `เราย้ายเครื่องเรือนให้ห่างจากหน้าต่าง`
   - Keep other fields.

2. **`cefrj15:mall` — source identity.** The selected source means department store (`ห้างสรรพสินค้า`); the curated shopping-centre sense (`ศูนย์การค้า`) denotes a complex of shops. Source alternative `ทางเดินเท้า` also does not match. Do not silently import these distinct retail-place senses under one identity.
   - Replace `sourceMeaningIndex`: `null`
   - Replace `reviewNote`: `Independent shopping-centre sense; source department-store and pedestrian-walkway meanings are not equivalent import identities.`
   - Keep meaning, English and Thai example.

3. **`cefrj15:sunflower` — make the flower sense explicit.** Source and curated meaning both say `ดอกทานตะวัน`; current English describes a whole tall plant growing, and Thai switches to `ต้นทานตะวัน`. Preserve source flower identity with an unmistakable flower example.
   - Replace `example`: `She placed a sunflower in a tall vase.`
   - Replace `translation`: `เธอปักดอกทานตะวันหนึ่งดอกในแจกันทรงสูง`
   - Replace `reviewNote`: `Flower example matches source ดอกทานตะวัน; does not silently switch the primary sense to the whole plant.`
   - Keep meaning and source index 0.

4. **`cefrj15:hey` — do not infer forgetting from left.** Existing English can describe a bag deliberately left on a chair. Match that neutral meaning, consistent with the hat/mobile corrections in batch 1.
   - Replace `translation`: `เฮ้ คุณวางกระเป๋าทิ้งไว้บนเก้าอี้!`
   - Keep other fields.

5. **`cefrj15:somebody` — same left/forgot distinction.**
   - Replace `translation`: `ใครบางคนวางร่มทิ้งไว้นอกประตูบ้านเรา`
   - Keep other fields.

6. **`cefrj15:sunglasses` — same distinction and more natural towel phrase.**
   - Replace `translation`: `เธอวางแว่นกันแดดทิ้งไว้บนผ้าขนหนูสำหรับใช้ที่ชายหาด`
   - Keep other fields.

The last three are translation-precision improvements; the original translations express a plausible contextual inference, not an impossible interpretation. No forced change to the English is needed.

## Special constructions corroborated and retained

The potentially unfamiliar constructions were checked against primary dictionary publishers, rather than rejected merely for being less common:

- `pacific` adjective for peaceful/conciliatory character: [Merriam-Webster](https://www.merriam-webster.com/dictionary/pacific), adjective senses 1 and 2. Current lowercase adjective example works; it is not the ocean name.
- `lyric` adjective expressing personal feeling in poetry: [Merriam-Webster](https://www.merriam-webster.com/dictionary/lyric), adjective sense 2a. Current poem example and Thai match.
- `unlike` predicative adjective: [Merriam-Webster](https://www.merriam-webster.com/dictionary/unlike), adjective entry explicitly recognises dissimilarity and marks this use somewhat formal. Current `The two sisters are very unlike in character.` is valid.
- `such` pronoun in a list-ending `and such`: [Merriam-Webster](https://www.merriam-webster.com/dictionary/such), pronoun sense 3. No determiner override is needed.
- `weep` singular noun for a period of crying: [Collins](https://www.collinsdictionary.com/dictionary/english/weep), COBUILD singular noun and British noun sense 6. Current `a quiet weep` is supported. Merriam-Webster's retrieved entry listed only a verb; Cambridge retrieval returned an internal error, so Collins was used as the bounded alternative. No failed request was repeatedly retried.

No dictionary example was copied into the proposed replacement content. These references corroborate meaning/POS, not independent A2 suitability or pedagogical efficacy.

`handicapped` remains explicitly labelled as an older potentially impolite term in the learner gloss and situated on an old sign; retain that register context. Technical/poetic/formal senses including lyric, pacific, progressive grammar, weep and unlike are inherited catalog choices, not independently certified A2 senses. The review does not treat their specialised character alone as proof of incorrect English.

## Remaining checks and handoff

Read and retained legitimate noun uses such as knock/mention/pass/release/return/search/shot/spread/writing and adjective uses such as kindly/net/principal/split/terrorist/uniform. Reviewed pronoun references, subject-verb agreement, inflection/capitalization, translations and source mappings across every row. No additional mandatory English grammar or POS correction was found in this reading.

This is AI cross-review, not human certification. Hash/count identify what was reviewed; structural checks cannot establish language quality. Original writer should apply accepted corrections, refresh source-linked/null counts (mall adds one null identity), read changed rows, and supply the new hash. Root retains integration responsibility. This worker wrote only this findings file for the batch-3 review and ran no Flutter/build/runtime commands; no processes remain running.
