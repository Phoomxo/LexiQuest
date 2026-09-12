# CEFR complete batch 2 editorial review — 2026-09-12

Worktree: C:/Users/Phet/.codex/worktrees/02fa/LexiQuest. Branch: codex/pair-matching-pm0-pm8.

## Coverage and status

Individually reviewed all 1,833 input rows (zero-based 0–1832, aberration through zone), including every original Thai source gloss. Authored 1,155 original English examples with Thai glosses and sentence translations for precisely the rows without existingEditorial. Read all 678 existingEditorial entries for sense, POS, translation, and source identity. Existing batch assets were not edited by this writer.

A second editorial reading covered every authored primary row and every source decision: primary scratch ranges 000 through 1800, source review ranges 000 through 1800. Batches were read in bounded chunks; a truncated combined output was reread in smaller chunks before counting it. Revisions included literal meaning, adverb/adjective gloss forms, natural Thai, source identity distinctions, and dictionary attribution. This is AI editorial review, not human certification or independent certification of CEFR sense difficulty. Inherited levels remain catalog labels; specialized/literary senses can be harder than that label suggests.

Frozen output:
- complete-2.json: 1,155 entries; SHA256 F173B57C3540C4E44B39FE8ADE0BE7C6B1C75961FF39D74FBC90A930C3CAB0C9.
- sense-review-2.json: 1,833 entries; SHA256 EBB94097BE4A1D6A47F24849B0A76F2967AF70C3F6C662E9D9E321F4D498278A.

Independent reviewer editorial_one read all 1,833 source rows and 1,155 primary examples from snapshots. All supplied actionable corrections were applied. Their completed 2026-09-12-cefr-cross-review-2.md confirms reading all 52 changed records after freeze, including this writer's additional revisions, against the exact hashes above. No actionable findings remain in the new batch.

## Verification evidence

Ran build/verification/cefr-complete-20260912/two/verify-final.ps1 against the saved JSON, exit 0: 1,155 primary; 1,833 reviews; 2,894 accepted and 794 excluded source glosses; 1,018 linked primary senses and 137 independently authored primary mappings; errors [].

Checks cover exact missing-ID coverage, duplicate IDs/examples, complete source-index partitions, valid linked mappings, exact English headword tokens, required text, status and sense key. No POS overrides were needed. Structural checks do not establish language quality. No Flutter, runtime, build, deployment, or paid API commands were run for this content batch.

## Editorial decisions and corrections

Every source gloss received an individual accept/exclude decision, with reasons for exclusions. Exclusion from practice does not automatically invalidate an old primary identity: an old curated gloss can repair a source typo or narrow its wording while representing the same underlying sense.

- frosty: source 0 reverses the causal relation between cold and ice. Primary uses independently authored หนาวจนมีน้ำค้างแข็ง, null mapping. Source 1, unfriendly, remains accepted.
- motor: new primary shows an electric motor and uses มอเตอร์ with null mapping. Source เครื่องยนต์ remains accepted for its own usage.
- literally: primary demonstrates following the actual wording of an instruction; independently authored ตามตัวอักษร; ตามความหมายตรง. Source อย่างแท้จริง remains accepted for the actual/real sense.
- neutralize: replaced unnatural neutralize the dispute with an original sports-training sentence about counteracting another team's advantage, with matching Thai and null mapping.
- convict: primary Thai refined to ตัดสินว่ามีความผิด. Retained source 1: the independent reviewer verified Merriam-Webster's find/prove guilty definition and withdrew an overly strict proposed rejection.
- source errors excluded include tact as ประสาทสัมผัส, tights as เสื้อรัดรูป, wane's incorrect lunar explanation, were restricted to plurals, and would described as having a participle.
- grammar and register were checked for singular ravage, noun correlate, adjective waste, brim as a verb, antiques commode, literal vermin, old/literary unto and verily, and philosophical solipsism. These contexts are deliberate, not claims that the selected sense is elementary.
- Lower-case holocaust uses destruction by fire in a fictional novel, distinct from the proper historical name; English now explicitly says caused by fire.
- Translation fixes include lemon versus lime, farmer versus rice farmer, couple without added marriage/gender assumptions, stop to sniff versus stop sniffing, fallen apples on grass, chef without added gender, and explicit older/younger siblings where the Thai sentence selects that relationship.
- Corrected original spelling in blister and debut primary glosses without changing their underlying source identities.
- Replaced a repeated speculate/conjecture context with a different original sentence. Sector and sauna received more natural singular-headword and activity-sequence examples.

## Existing-primary findings for root

Root adjudicated been, blonde, clerk, cola, and description as refinements preserving the underlying identity; retain their existing mappings. Cooker was the distinct compound/appliance error and root owns its correction. See 2026-09-12-cefr-existing-primary-adjudication.md. Other raw source exclusions caused by incomplete grammar, spelling, or overbroad descriptions do not automatically request remapping existing primary senses (including had, liter, symphony, and were). Existing tights, website, would, and yoghurt already have independent corrected primary meanings.

Minor translation fidelity proposal sent to root: cefrj15:until has “The shop stays open until nine.” but Thai specifies สามทุ่ม. Proposed English: “The shop stays open until nine at night.” Keep its source mapping and Thai. This writer did not alter old batches.

## Sensitive language and practice suitability

No ethnic slur was identified in this 1,833-row slice. The following need reading/register awareness and should not be prompted as language to address or demean people:
- octanove10:ingrate: direct personal insult คนอกตัญญู; the authored sentence reports an angry fictional narrator's label.
- cefrj15:retard: selected formal verb means slow plant growth. Its same-spelling noun is a severe disability slur; avoid person-directed practice and distinguish POS/register.
- octanove10:vermin: selected literal pest sense. Applied to people it is dehumanizing; keep practice literal.
- cefrj15:dumb and cefrj15:fool: insulting when directed at people; current contexts concern a mistake or self-description, not addressing another learner.
- Excluded source senses: cefrj15:trash 2 (devaluing people), cefrj15:skirt 1 (demeaning women), cefrj15:simple 3 (mental-capacity insult), cefrj15:skeleton 2 (body-shaming), cefrj15:tool 4 (insult) and 5 (vulgar sexual slang), plus insulting person-label senses of bag, dog, animal, fox, chicken, mouse, monkey, clown, mad, and trap.
- cefrj15:neurosis is a historical/informal clinical label, not a diagnosis or label to apply to classmates. Suicide appears in a prevention/documentary context without methods. Primitive describes a basic system, not a people.

## Primary references used for genuine ambiguity

Definitions and register were checked; examples are independently authored, not copied:
- [Cambridge: bulimia](https://dictionary.cambridge.org/dictionary/english/bulimia).
- [Merriam-Webster: carbonize](https://www.merriam-webster.com/dictionary/carbonize), [brimming](https://www.merriam-webster.com/dictionary/brimming), [commode](https://www.merriam-webster.com/dictionary/commode), [correlate](https://www.merriam-webster.com/dictionary/correlate), [holocaust](https://www.merriam-webster.com/dictionary/holocaust), [harrow](https://www.merriam-webster.com/dictionary/harrow), [ravage](https://www.merriam-webster.com/dictionary/ravage), [solipsism](https://www.merriam-webster.com/dictionary/solipsism).
- [American Heritage: neurosis](https://ahdictionary.com/word/search.html?q=neurosis), [romper](https://www.ahdictionary.com/word/search.html?q=romper). Romper's person sense was excluded for usefulness, not falsely marked obsolete.
- Independent reviewer's [Merriam-Webster: convicts](https://www.merriam-webster.com/dictionary/convicts) resolved the proposed convict source rejection.

Next integration step: root combines the independently reconciled content with runtime changes and owns subsystem checks.
