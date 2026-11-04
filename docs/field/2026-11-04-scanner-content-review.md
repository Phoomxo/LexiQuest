# Scanner vocabulary content review

Baseline `a5e46226247ef09e7faa8cc12248fe483d7034db`. Source reviewed: `lib/services/object_vocabulary_database.dart`. The static list contains 127 entries in 11 categories. The 120+ count is correct; the comment saying 10 categories is not. The count comes from the 127 complete `ScannedVocabulary` constructors, excluding the class constructor. No source content was changed in this review.

Method: read every entry's English, Thai, pronunciation, example, category, and declared level. Read the lookup, scanner acceptance, result display, and their tests. P means no confirmed defect in the English, Thai, example, or pronunciation in the intended sense, subject to the common qualifications below. F identifies a confirmed finding. The table is a reviewer disposition, not professional linguistic certification. Plural and inflected example forms count as valid target usage. The examples and phonetics are stored in the database but the current scanner card does not display them, and acceptance stores neither.

All CEFR labels are unverified editorial assignments. The source gives no authority or alignment method. The test checks only that the strings belong to the CEFR set. Do not treat P as a CEFR validation. The scanner persists the assigned label as `cefrLevel` on acceptance. Treat those values as estimates unless independently mapped to a stated source and sense. The list mixes British and American word choices and IPA conventions. No dialect is declared, and final `/r/` appears alongside British vowels. This does not by itself establish that every transcription is wrong, but a single named accent and dictionary-based review are needed before claiming consistency. Category names are practical groupings, not a linguistic taxonomy. `Sports` can include music only if intended as recreation, while `Furniture` includes doors and windows and `Kitchen` includes a clock. The category is persisted on acceptance.

## Confirmed findings

- Stapler: the example uses the verb `staple`, not the noun `stapler`. Minimum replacement: `Use a stapler to join these pages.`
- Comment above the list: change `10 categories` to `11 categories`. The API returns 11 distinct values.
- The bidirectional substring fallback invents relationships. `water` selects `Water bottle`, even though the label does not establish a bottle. `hotdog` selects `Dog`, and an empty label selects the first entry, `Apple`. `coffee cup` selects `Coffee` before `Cup`, and its test explicitly permits either. Return no match for an unsupported ambiguous label; use exact matching or explicit reviewed aliases. In particular, `water` must not be asserted to mean `water bottle`, and empty input must return null. Add behavior tests for these cases and known legitimate model aliases. An exact `Mouse` label still has animal and computer senses; `Orange` can name a color or fruit. Exact spelling alone cannot resolve a model's sense. Verify against the deployed model's actual label list before defining aliases. The model loads labels embedded in its downloaded artifact, not this file.
- The result card says `พบวัตถุจริง แต่ยังไม่มีคำแปลที่ตรวจสอบแล้วในคลังคำศัพท์` when no vocabulary matched. A classifier prediction does not prove an object is present or that the translation was independently checked. Minimum replacement: `โมเดลคาดเดาวัตถุได้ แต่ยังไม่มีคำศัพท์ที่ตรงกันในคลัง`.

The database test asserts presence of fields and level syntax, not correctness. The scanner uses the first usable classification that maps, then stores the word and Thai meaning as a noun with the category and level. Its confidence is the classifier's confidence for the matched label, not a confidence in the translation. A scan can therefore persist a wrongly inferred sense after user acceptance. Test fixtures are synthetic and are not evidence of model recognition accuracy.

Optional editorial changes, not confirmed defects: replace `I had toast and bread for breakfast.` with `I had bread for breakfast.` for a simpler example. Group musical instruments under a recreation label if product taxonomy requires literal categories. These are not required corrections to the individual word meanings.

## Entry ledger

All rows inherit the CEFR, dialect, and lookup qualifications above. F names the additional item-specific finding.

| # | Label | Review |
|---:|---|---|
| 1 | Apple | P |
| 2 | Banana | P |
| 3 | Orange | P; classifier sense is ambiguous. |
| 4 | Bread | P |
| 5 | Cake | P |
| 6 | Coffee | P |
| 7 | Tea | P |
| 8 | Water bottle | P; generic bottle labels cannot establish contents. |
| 9 | Pizza | P |
| 10 | Ice cream | P |
| 11 | Egg | P |
| 12 | Rice | P |
| 13 | Laptop | P |
| 14 | Mobile phone | P |
| 15 | Tablet computer | P |
| 16 | Keyboard | P |
| 17 | Mouse | P; classifier sense is ambiguous. |
| 18 | Headphones | P |
| 19 | Television | P |
| 20 | Camera | P |
| 21 | Speaker | P |
| 22 | Charger | P |
| 23 | Monitor | P |
| 24 | Printer | P |
| 25 | Shirt | P |
| 26 | Shoe | P |
| 27 | Hat | P |
| 28 | Sunglasses | P |
| 29 | Watch | P |
| 30 | Backpack | P |
| 31 | Jacket | P |
| 32 | Trousers | P |
| 33 | Dress | P |
| 34 | Belt | P |
| 35 | Scarf | P |
| 36 | Glove | P |
| 37 | Dog | P; substring fallback can match `hotdog`. |
| 38 | Cat | P |
| 39 | Bird | P |
| 40 | Fish | P |
| 41 | Butterfly | P |
| 42 | Horse | P |
| 43 | Elephant | P |
| 44 | Rabbit | P |
| 45 | Turtle | P |
| 46 | Frog | P |
| 47 | Duck | P |
| 48 | Parrot | P |
| 49 | Chair | P |
| 50 | Table | P |
| 51 | Desk | P |
| 52 | Bed | P |
| 53 | Couch | P |
| 54 | Bookshelf | P |
| 55 | Lamp | P |
| 56 | Mirror | P |
| 57 | Door | P |
| 58 | Window | P |
| 59 | Pillow | P |
| 60 | Curtain | P |
| 61 | Book | P |
| 62 | Pen | P |
| 63 | Pencil | P |
| 64 | Scissors | P |
| 65 | Paper | P |
| 66 | Envelope | P |
| 67 | Ruler | P |
| 68 | Calculator | P |
| 69 | Notebook | P |
| 70 | Eraser | P |
| 71 | Stapler | F. Replace example with `Use a stapler to join these pages.` |
| 72 | Folder | P |
| 73 | Car | P |
| 74 | Bicycle | P |
| 75 | Bus | P |
| 76 | Motorcycle | P |
| 77 | Airplane | P |
| 78 | Boat | P |
| 79 | Train | P |
| 80 | Truck | P |
| 81 | Taxi | P |
| 82 | Helicopter | P |
| 83 | Scooter | P |
| 84 | Flower | P |
| 85 | Tree | P |
| 86 | Leaf | P |
| 87 | Grass | P |
| 88 | Rock | P |
| 89 | Cloud | P |
| 90 | Sun | P |
| 91 | Moon | P |
| 92 | Star | P |
| 93 | Mountain | P |
| 94 | River | P |
| 95 | Key | P |
| 96 | Wallet | P |
| 97 | Umbrella | P |
| 98 | Toothbrush | P |
| 99 | Comb | P |
| 100 | Towel | P |
| 101 | Soap | P |
| 102 | Bottle | P |
| 103 | Bag | P |
| 104 | Ring | P |
| 105 | Necklace | P |
| 106 | Perfume | P |
| 107 | Ball | P |
| 108 | Tennis racket | P |
| 109 | Swimming pool | P |
| 110 | Skateboard | P |
| 111 | Helmet | P |
| 112 | Guitar | P |
| 113 | Piano | P |
| 114 | Cup | P |
| 115 | Plate | P |
| 116 | Bowl | P |
| 117 | Fork | P |
| 118 | Spoon | P |
| 119 | Knife | P |
| 120 | Frying pan | P |
| 121 | Kettle | P |
| 122 | Refrigerator | P |
| 123 | Microwave | P |
| 124 | Oven | P |
| 125 | Washing machine | P |
| 126 | Clock | P |
| 127 | Candle | P |

No external dictionary or CEFR source was checked in this pass. P records this reviewer's judgment and does not establish independent validation or pronunciation consistency. No Flutter, Dart, build, device, or network test was run.
