# Root editorial cross-review — work in progress

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`.
Branch: `codex/pair-matching-pm0-pm8`.

Root read the meaning, original English example and Thai translation of every
one of the 1,156 newly authored primary entries in complete-1.json, in ordered
chunks, independently of its author. This review was of drafts, not frozen
files. The first 1,004 reviewed rows were snapshotted under
`build/verification/cefr-complete-20260912/root-one-primary-reviewed-prefix.json`.
All 152 remaining rows were then read. Source-index partition checks and a
separate source-sense cross-review are still required; do not treat prose review
alone as proof that every original mapping is correct.

Findings delivered to the sole file owner for adjudication and repair:

- Natural usage/Thai wording: bony, barren, bureau, conveniently, delightful,
  intense, seismic, worldly.
- Example ambiguity or grammar: compound (word formation context), fume
  (natural singular use), genome (singular genome compared across two varieties),
  revile (writer instead of article refusing an action).
- Translation fidelity: entrepreneur, elated, heifer, maternal, middle-aged,
  paratrooper, portray, southward, stately, taste, trader.
- Negation scope: wholly (“not wholly convinced” must not become complete disbelief).
- POS/usage verification: wizard (attributive noun is not proof of adjective),
  micro, transistor. Author is checking primary dictionary sources where needed.
- Existing primary outside this new batch: cooker should teach the bare cooker
  appliance sense rather than only the rice cooker compound. Root owns any
  resulting old-batch edit after receiving exact proposed fields.

No author file was edited by root during this review. Root subsequently read
the reported repairs and reconciled every difference against the saved first
1,004-row snapshot. Additional author refinements included bet's explicit match
context, caravan's gender-neutral Thai, confabulation's usage label, humble's
independent mapping and rotate's transitive source index. The remaining final
rows and reported corrections were also read. Author-frozen primary SHA-256:
`32c458008c58ba94a7fb36bd56065d9d07e058fc958a8f0ad5ade22703098b32`.

Root independently ran the structural validator on this frozen batch: 1,156
new primary entries, no duplicate examples or length/punctuation warnings;
1,834 source reviews partitioning 3,543 meanings (2,819 accepted, 724 excluded).
Evidence: `build/verification/cefr-complete-20260912/author-one-structural.json`.
Independent source-sense review by editorial_three covered all 1,834 rows and
3,543 original glosses. Its final findings produced 15 primary repairs and four
source decisions. Root reread all 15 final primary records without an actionable
finding. Final primary SHA-256:
`c615817a58afb6ecb9b5c24d8c35b8b5d9f1af133a9ba659697858d8ff953551`.
Final sense SHA-256:
`c3fcc05d70288e528517a6cbea1881cd285dbb7410fcd43243e80a4c8fa223eb`.
Final partition: 2,817 accepted and 726 excluded. This prose review does not
replace the source review. This is AI editorial review only, not human approval
or CEFR certification.
