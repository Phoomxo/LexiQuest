# Independent source and existing-primary cross-review — batch 3

Reviewer: editorial_two. Worktree C:/Users/Phet/.codex/worktrees/02fa/LexiQuest, branch codex/pair-matching-pm0-pm8. Date: 2026-09-12.

## Exact scope

Read every input row from zero-based 900 through 1832 inclusive: 933 IDs, large through zoologist. Reviewed all 1,889 original Thai source glosses in this slice against their accepted/excluded indices, reasons, POS and primary source mapping. Read the complete English/Thai/meaning fields of all 345 existingEditorial entries in the slice. New primary meanings and source mappings were inspected as supporting evidence; root separately owns the full English/Thai prose review of all 1,155 new entries.

Root coordinates source rows 0–899 and their existing primary examples (including editorial_one's separate middle-range report). This report does not claim this reviewer independently covered that separate range or repeated root's full new-prose review.

Reviewed frozen files:
- complete-3.json SHA256 3C0D6C460B99F99C99B51371F101DBD668DE48C2DC93E8EBDE1CD99E24647D3F.
- sense-review-3.json SHA256 539C51EBC9868D9437DA907F11E0DB4C938123CD26D779D363012EC30631BC06.

Full compact snapshot of the exact reviewed fields is in build/verification/cefr-complete-20260912/two/cross-three-reviewed-snapshot.jsonl. Bounded reads covered 900–979, 980–1059, 1060–1139, 1140–1219, 1220–1299, 1300–1379, 1380–1459, 1460–1539, 1540–1619, 1620–1699, 1700–1779, and 1780–1832. An initial verbose truncated output was discarded as coverage evidence and reread fully in compact form.

## Actionable findings sent to owners

| ID / input index | Finding and proposed replacement | Owner / state |
| --- | --- | --- |
| octanove10:mariner / 963 | Source 0 explicitly labels the word obsolete, while the author's note and new primary correctly distinguish literary usage. Since runtime displays original accepted glosses, move 0 from accepted to excluded with reason: คำนี้ใช้เชิงวรรณกรรม ไม่ควรระบุว่าเป็นคำล้าสมัยที่เลิกใช้ทั้งหมด. Keep current independent primary. | Applied; final diff independently reconciled. |
| octanove10:maggot / 948 | Source 0 หนอนแมลง is broader than a fly larva. New primary already specifies ตัวอ่อนของแมลงวัน and null mapping. Candidate: exclude 0 because gloss can teach any insect larva as maggot; preserve current primary. | Applied; final diff independently reconciled. |
| cefrj15:overbook / 1123 | Source 0 จองตั๋วมากกว่าที่มี does not distinguish accepting bookings beyond capacity from a customer's booking action. New primary รับจองเกินจำนวนที่มี and null are clearer. Candidate: exclude 0 with reason explaining รับจองเกินความจุ. | Applied; final diff independently reconciled. |
| cefrj15:official / 1091 | Existing primary adjective gloss อย่างเป็นทางการ is adverb-shaped. Replace meaning with ที่เป็นทางการ. Source 0 already has exactly that adjective wording: keep mapping 0, English and translation. | Root applied; independently reread below. |
| cefrj15:poor / 1206 | Existing English farmer does not specify rice cultivation. Replace translation with เรื่องนี้เกี่ยวกับเกษตรกรที่ยากจน. Keep other fields. | Root applied; independently reread below. |
| cefrj15:tooth / 1660 | Existing Thai ฟันหน้าของฉันรู้สึกโยก gives the tooth a feeling. Replace translation with ฉันรู้สึกว่าฟันหน้าโยก. Keep other fields. | Root applied; independently reread below. |

Do not automatically remap old primary identities when source text is narrowed or spelling corrected. Accepting a broad but valid sense and authoring a more precise primary with null can be reasonable; the candidates above focus on potentially misleading displayed source wording, not mechanical null enforcement.

## Decisions checked without requiring correction

Reviewed correct exclusions of metric (not only metres), microorganism (not only animals/plants), neutral (no net charge is not nonconducting), psychiatric (not psychology), respiratory (related to breathing, not suitable to breathe), stroke (not only blocked vessels), and year (incorrect 365.5 figure). Confirmed deliberate independent meanings for mobile, peace, pepper, pilgrim, so, spy, sweat, tower, wedding and modern video while preserving source alternatives where useful.

Checked the nouns weep and underline, the adjectives lyric and pacific, and headword/POS relationships in existing examples. No independently certified CEFR level is asserted: literary mariner, pacific, nigh, philosophical/technical senses and historical tinker require register awareness.

Sensitive language in this slice includes prick, queer, tinker and tramp with potentially offensive person-directed uses; their authored senses/notes distinguish the intended context. Excluded insulting/dehumanizing source senses of loose, petty, reptilian, thick, tiger, trouble and woman were inspected. This is reading/register suitability review, not a blanket ban on legitimate self-identification such as queer.

## Structural evidence and limits

The reviewed slice contains exactly 933 consecutive IDs, 345 existing primary entries and 1,889 source glosses. Independent partition check found no duplicate/missing original indices within these 933 rows. Hashes read from saved final assets matched the author's freeze. No author assets were edited by this reviewer. No Flutter/build/runtime commands were run. Structural checks do not certify language quality; findings above come from individual editorial reading.

Final reconciliation completed: compared all 933 reviewed rows against the frozen snapshot and individually read all three changed records (maggot, mariner, overbook). Only their accepted/excluded decisions and explanatory notes changed in this scope; each now excludes source 0 with the intended specific reason, and the complete primary asset is unchanged. No actionable findings remain in this review's scope. Final sense-review-3.json SHA256 A2C9B8F1178FD0E6C5B4370FC46D7FD597CF477812DFBC5B326491AB5E3FD804; complete-3.json remains 3C0D6C460B99F99C99B51371F101DBD668DE48C2DC93E8EBDE1CD99E24647D3F. Root's source 0–899 review and new-prose review are separate evidence.

## Root's 33 old-primary corrections — independent final read

Read the actual batch-1/2/3 JSON entries for all 33 requested IDs: age, also, be, december, argument, armchair, beer, blame, cooker, until, from, guitar, guy, memory, old, poor, company, cooking, couple, deep, fighter, tooth, yard, granny, hip-hop, hug, joy, official, rugby, single, trust, wisdom and youth. Compared catalog POS/source meanings from all three completion input files.

No actionable issue remains in these 33 reviewed corrections. English now explicitly supplies older/younger or maternal relationships where Thai selects them; named people replace other unnecessary relationship assumptions. The be/until times match Thai, poor uses เกษตรกร, tooth locates the feeling with the speaker, official has an adjective gloss, deep functions as an adverb, and cooker uses the British appliance sense with independent null mapping. Company and hip-hop retain their independent mappings. Couple explicitly specifies marriage without inferring genders.

Actual reviewed old-asset SHA256:
- batch-1.json: D7AB58A1CCE6D7D30B92418B234161AB1A75088DA7934516F33D5791159B027B.
- batch-2.json: 9A53AB6653D1FCEBD61D8CF9A6251E11B5075E26EA865CC819E3FB29D100E46E.
- batch-3.json: B2534412E7EE71BB913F229952902F25E5D46265931A094DD6CD1316D3642F06.

This closes this report's three old-primary findings (official, poor, tooth) and the separately reported until fidelity issue. No assets were edited by this reviewer.
