# Additional content review

Baseline `a5e46226247ef09e7faa8cc12248fe483d7034db`. This is a static English and Thai review, not external CEFR validation, a runtime test, or certification. Starter pack and scanner entries have separate reports. The reading adapter is being assessed separately. No research instrument was changed.

The findings in this report concern baseline legacy sources for which no production caller was found. Separate starter, scanner, and reading findings were addressed in subsequent source edits; the original reports retain their historical findings. This report does not claim that variable external content is correct.

## Findings

- `cefr_diagnostic_test_screen.dart` labels its five-item vocabulary quiz a CEFR assessment and converts 5/5 to C1/C2, although there is no C2 item or demonstrated calibration in this source. All correct answers are first. This is not evidence of overall CEFR proficiency. No production constructor caller was found.
- `dynamic_story_contextualizer_service.dart` labels every unknown target B2 and inserts it into a generic sentence. For an adjective such as `happy`, “Learning about happy” is not a natural use of the target. This is a template defect, not evidence for the assigned level. No production caller was found.
- `cefr_service.dart` silently substitutes `คำแปล <word>`, `Example sentence for <word>.`, and noun when enrichment fails or lacks data. These placeholders do not teach a meaning, contextual example, or reliable part of speech. The traced CEFR selection path is not reachable from a found production constructor for its world map.
- The default boss is labelled C1 but includes `ephemeral` tagged C2 and `sustainable` tagged B2 in the local CEFR list. These labels are inconsistent even before independent level validation. No production constructor caller was found. Exact spelling comparison is the intended answer behavior, but accepts no alternative spellings.
- The three associations are labelled `curated`, with system ownership and a fixed 2026-01-01 timestamp. Those fields do not identify an author, source, or review. The resilient bamboo cue says “never snapping”, an absolute unsuitable as a general factual claim; it remains a metaphor for resilience. No production caller of the service was found.

## Finite entries

Each row below was read against the actual source. “No obvious issue” means the meaning and sentence are plausible in context; it does not establish an authoritative CEFR assignment, a comprehensive definition, or independent editorial review. No provenance for the levels was found in these sources. The level is a local label.

### CEFR vocabulary

Source `lib/services/cefr_service.dart`. `CefrSelectionScreen` uses the list; `LearningWorldMapScreen` constructs that screen, but no production construction of the map was found. `ZpdRecommenderService` also references the service without a found production caller.

| Word | Local level | Review |
| --- | --- | --- |
| hello | A1 | No obvious issue. |
| dog | A1 | No obvious issue. |
| apple | A1 | No obvious issue. |
| book | A1 | No obvious issue. |
| journey | A2 | No obvious issue. |
| weather | A2 | No obvious issue. |
| borrow | A2 | No obvious issue. |
| achieve | B1 | Translation is appropriate for the example's sense. |
| opportunity | B1 | No obvious issue. |
| challenge | B1 | No obvious issue. |
| innovative | B2 | No obvious issue. |
| perspective | B2 | Thai includes attitude as another sense; example uses viewpoint. |
| sustainable | B2 | No obvious issue. |
| meticulous | C1 | No obvious issue. |
| ubiquitous | C1 | No obvious issue. |
| pragmatic | C1 | No obvious issue. |
| ephemeral | C2 | No obvious issue. |
| quintessential | C2 | No obvious issue. |
| perspicacious | C2 | Thai เฉียบแหลม fits; สายตายาวไกล can suggest foresight rather than perceptiveness. Example is somewhat redundant. |

### Phrasal verbs

Source `lib/services/phrasal_verb_service.dart`. Symbol search found no production caller. Local CEFR labels lack cited authority.

| Phrase | Level | Review |
| --- | --- | --- |
| look forward to | B1 | Meaning and gerund example fit. |
| give up | A2 | The example fits the “not abandon” sense. |
| come up with | B2 | Translation and example fit the idea-creation sense. |
| bring about | C1 | Translation and example fit. |
| carry out | B2 | Translation and experiment example fit. |

### Diagnostic items

Source `lib/screens/cefr_diagnostic_test_screen.dart`. The first option is the keyed answer in every row. No production constructor caller was found. The local level labels are not validated by this review.

| Item | Key | Review |
| --- | --- | --- |
| apple | แอปเปิ้ล | Correct translation among the supplied options. |
| journey | Trip | Plausible synonym among the supplied options. |
| achieve | บรรลุเป้าหมาย | Correct for the intended sense. |
| innovative | ที่เป็นนวัตกรรมใหม่ | Correct among the supplied options. |
| ubiquitous | Present everywhere | Correct among the supplied options. |

### Boss and story

Source `lib/screens/boss_battle_screen.dart`. No production constructor caller was found. The three translations fit the intended words, but the C1 title conflicts with the local CEFR labels as described above.

| Prompt | Required spelling | Review |
| --- | --- | --- |
| ชั่วคราว | ephemeral | Plausible. |
| พิถีพิถัน | meticulous | Plausible. |
| ยั่งยืน | sustainable | Plausible. |

Source `lib/services/dynamic_story_contextualizer_service.dart`. No production caller was found.

| Target | Review |
| --- | --- |
| opportunity | English and Thai convey Sarah taking an opportunity to present a project. Local B1 label is unsupported here. |
| resilience | English and Thai convey recovery after setbacks. Thai is colloquial. Local C1 label is unsupported here. |
| Any other target | Generic interpolated sentence and Thai translation do not explain the target's sense. B2 is assigned without evidence. Empty input also reaches this template. |

### Associations

Source `lib/services/associative_memory_service.dart`. No production caller was found. User associations are variable and private on creation. The fixed records are not evidence of an independently reviewed corpus.

| ID | Target | Review |
| --- | --- | --- |
| curated-e1 | ephemeral | Morning mist disappearing is a plausible sensory cue for short duration. |
| curated-e2 | ephemeral | Transient, short-lived, and fleeting are plausible synonyms. |
| curated-r1 | resilient | Bending bamboo is a plausible metaphor, but “never snapping” is absolute. |

## Variable content and validation

`GeminiRestGateway` prompts for a concise tutor, B1-B2 English, at most two short sentences, and guided or direct mode. `AiTutorScreen` supplies five scenario labels: job interview, airport check-in, cafe ordering, academic meeting, and hotel check-in. These labels are scenarios, not answers or certified levels. The gateway bounds input, response bytes, parses candidate text, and rejects blocked or malformed responses. It does not validate linguistic correctness or guarantee compliance with its prompt. `GeminiTutorUseCases` requires active provider consent and a key; sharing a progress summary is separately optional. The UI identifies the AI assistant, exposes data disclosure and error messages, and offers content reporting. A generated answer remains variable and must not be represented as independently verified.

The backend `llm_content_service.py` asks providers for a sentence, a micro-story, or an explanation using the requested target, level, and language. It accepts nonempty provider message text; the prompt is not proof of naturalness or CEFR alignment. `SentenceScrambleContent` checks source kind, English language, model version, bounded text, whole target, and token suitability. `ClozeContent` also requires exactly one whole target and lexical context. These checks admit exercise structure, not grammar or semantic appropriateness. The current inventory describes CSV, JSON, and learning-pack import limits. Those checks likewise do not certify imported meanings or examples.

## Search and remaining gaps

Discovery used `rg --files assets lib backend` filtered for `json|csv|yaml|txt|story|question|quiz|prompt|gemini|vocab|association|exercise`, and `rg -l -i 'exampleSentence|example_sentence|correctAnswer|correct_answer|questionText|quizQuestions|sample (sentence|question)|dummy|mock|fallback|gemini|prompt' lib --glob '*.dart'`. The latter matched 876 lines including generated code, infrastructure, and research. Production references were checked with exact symbol searches for the classes in this report. Direct symbol searches cannot rule out indirect runtime construction. `pubspec.yaml` declares the Noto Sans Thai font; the discovered `backend/voice_api/research/golden_texts.json` is voice research material, not established as bundled learning content.

This is not an exhaustive proof that no other inline content exists. The broad search results were not all reviewed line by line. In particular, arbitrary literals outside the searched terms, the voice research golden texts, remote or generated training corpora, and every runtime feature flag remain unreviewed. Frozen research instruments were not linguistically reviewed or changed; their authorization and gating need their own evidence. No Flutter, Dart, device, provider, billing, or cloud operation was run.

## Coverage follow-up

The route and registry checks are recorded in `2026-11-04-content-inventory.md`. The earlier gap paragraph remains a record of the initial pass. This follow-up found two more finite legacy sources by searching static lists and maps in services, screens, and models. Exact class searches found no production callers. This does not prove that a future route cannot expose them.

`CollocationService` contains 12 phrases. For `decision`, they are `make a decision`, `reach a decision`, `firm decision`, and `tough decision`. For `opportunity`, they are `great opportunity`, `seize the opportunity`, `equal opportunity`, and `golden opportunity`. For `sustainable`, they are `sustainable development`, `sustainable energy`, `sustainable growth`, and `sustainable practice`. These are plausible collocations in suitable contexts. Its two fallback templates, `use $lower in context` and `key $lower aspect`, are instructions or mechanical combinations rather than verified collocations. For `happy`, `key happy aspect` is not a natural collocation.

`LexiVisionAccessibilityService` contains six fixed entries. The pairs are `cup` and `แก้วน้ำ`, `table` and `โต๊ะ`, `chair` and `เก้าอี้`, `book` and `หนังสือ`, `phone` and `โทรศัพท์`, and `laptop` and `แล็ปท็อป`. The translations are plausible. The first four carry local A1 labels and the last two A2 labels without cited level authority. For an unknown label, the service returns the label as its Thai translation, wraps the label in slashes as if it were IPA, and assigns B1. That fallback does not establish a translation, pronunciation, or level. This is a source-level defect in an unreferenced helper, not evidence that the current scanner uses it.

Current-source inspection found the reading adapter was replaced. The new `ReadingMaterial` composes matching lexical examples or word-only text rather than the historical generated passages. Ordered records retain each selected word's ID and revision, including when spellings repeat, and the material ID includes ordered content identities. This observation does not validate runtime integration or existing saved content. Starter version `1.0.1` states that AI-assisted review was completed and independent human editorial review is pending. The pack preview distinguishes file integrity from expert certification. The scanner displays CEFR as approximate. None of these statements proves independent CEFR calibration.

The search remains bounded to repository source. The 90-file broad match includes generated schema, data transport, progress and evidence counters, voice fallback, and UI state. Those matches do not themselves add a fixed teaching corpus. Variable provider outputs, owner data, remote training outputs, and voice research golden texts were not linguistically reviewed. Research instruments remain separately controlled and unchanged. This source inspection does not certify every arbitrary string or runtime configuration.

The bounded follow-up inspected the matching lines in all 90 files and classified each file in the inventory ledger, with complete-file SHA-256 hashes. It also checked nonmatching static lists, routes, and the finite datasets named in the inventory. This closes the identified broad-search classification gap for the recorded source snapshot. It does not establish linguistic correctness for external data, arbitrary unseen strings, or runtime configurations.
