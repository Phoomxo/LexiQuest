# CEFR curated meanings and examples

User authorized editorial quality work. Optional scope question offered A1–A2
first versus all 5,500; while unanswered adopt recommended A1–A2 first (2,034
headwords), with transparent pending status for other levels. If user selects
all, continue the same pipeline through remaining levels before completion.

Use brainstorming/writing-plans and executing-plans inline. For independent
content batches apply dispatching-parallel-agents with disjoint files; root is
the only runtime/test writer. Never claim human/CEFR certification.

Architecture: an immutable editorial overlay per headword, one primary sense
with original English example and Thai translation. Original catalog assets,
meanings/indexes/IDs are unchanged. Each sense has a permanent key and optional
equivalent sourceMeaningIndex. Importing a curated sense uses its original source
identity when equivalent, otherwise a new stable editorial identity; existing
user edits are returned unchanged. Never migrate/overwrite personal words.
Display curated sense/example first, dictionary alternatives distinctly pending.
Examples are presentation content, not verified quiz/RAG/learning evidence.

Schema batch root: schemaVersion 1, entries list. Each entry has id, senseKey
`primary-v1`, sourceMeaningIndex (int or null), meaning, example, translation,
reviewNote (specific to tricky grammar/sense, otherwise short meaningful note),
status `ai-reviewed`. Content is AI-authored and editorially checked, not human
approved. Source indices must only denote equivalent senses, not position order.
Optional partOfSpeechOverride corrects erroneous source POS for a curated example
(e.g. its as determiner). It requires sourceMeaningIndex:null, an explicit review
note and preserves the original catalog POS/meaning data unchanged.

Checks per item: English grammatical/natural; target word/POS/sense demonstrated;
Thai gloss and sentence translation accurate; concrete learner-appropriate context;
no fabricated quotations/facts or copied examples. A1 sentences usually 4–12
words; A2 6–16, not rigid quotas. Retain target exact spelling where natural.
Ambiguous/niche uses require primary-source lookup or flag, not invented evidence.

- [x] Read all assigned source words and meanings, author 3 disjoint content
  batches covering all 2,034 A1/A2 words, retain review evidence and flagged issues.
- [x] Cross-review batches for meaning/POS/translation/naturalness and repair
  findings, then freeze asset writers before integration verification.
- [x] Root TDD overlay parser/integrity/index validation, importer stable identity,
  UI curated/pending states and English/Thai examples. No schema migration.
- [x] Structural coverage audit, focused regressions, analysis, and source-pinned
  preview build; update vivo with hash-safe transfer and preserve data.
- [x] Native example/legacy import checks and checkpoint with coverage, limitations,
  exact counts, source/APK hashes and remaining levels.
