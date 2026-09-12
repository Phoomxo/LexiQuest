# Original packaged starter content: editorial record

Status: INTERNALLY REVIEWED — root independently reviewed the definitions, sentences and Thai meanings, then requested the clock correction below before approving the shipped text. This is an internal editorial record, not external certification.

Scope: twelve original everyday nouns, one English definition and one example sentence each. This is a small starter set, not a complete curriculum. `partOfSpeech` is `noun`; CEFR level, IPA and prerecorded audio are intentionally unspecified. Internal review does not represent teacher certification, validated CEFR placement, ethics approval or learning-efficacy evidence.

| Key | Thai meaning | English definition | Example sentence |
| --- | --- | --- | --- |
| book | หนังสือ | A set of pages joined together for reading. | I read a book with fifty pages. |
| pencil | ดินสอ | A writing tool that makes marks you can usually erase. | I write with a pencil and erase a wrong letter. |
| chair | เก้าอี้ | A seat with a back for one person. | I sit on a chair with a tall back. |
| door | ประตู | A part of a wall that opens so people can enter or leave. | Please close the door after you enter the room. |
| window | หน้าต่าง | An opening in a wall, usually with glass, that lets in light. | Sunlight comes through the window beside my desk. |
| bottle | ขวด | A container with a narrow neck for holding liquids. | I pour water from a bottle with a narrow neck. |
| cup | ถ้วย | A small container, often with a handle, used for drinking. | I drink warm milk from a cup with a handle. |
| spoon | ช้อน | A tool with a handle and a small bowl, used for eating or serving food. | I use a spoon to eat my soup. |
| plate | จาน | A flat dish used for serving or eating food. | I put my rice on a round plate. |
| bag | กระเป๋า | A container made of a soft material, used for carrying things. | I carry my clothes in a bag. |
| clock | นาฬิกา | An object that shows the time, usually on a wall or a table. | The clock on the wall shows seven in the morning. |
| key | กุญแจ | A small object shaped to open or close a lock. | I turn a key to open the lock. |

Review checks grammar, intended word sense, Thai meaning, a single whole-word occurrence suitable for masking, and whether available distractors make the selected answer ambiguous. Passing a unique-occurrence code check alone is not semantic review. Shipped metadata uses the existing `RichLexicalMetadata` version 2, with empty synonym/antonym arrays and null IPA/audio.

Author: recognition_readiness_audit implementation worker. Independent reviewer: root, 2026-09-08. Outcome: twelve items accepted after changing the clock sentence: the original apostrophe form contained a second match under the existing Cloze word-boundary rule. Shipped metadata and hashes must match this final text; runtime acceptance remains subject to the unchanged artifact verifier and tests.

The catalog has one fixed inactive packaged owner. Read access requires the exact catalog identities, core checksums, category and owner state, and immutable lexical manifests. The `isGlobal` flag alone never grants access. Personal mutation APIs reject the reserved owner and identities, including callers that pass the packaged owner directly. Provisioning verifies all twelve assets before an atomic insertion; an identity or revision collision fails without overwriting existing rows. Attempts, SRS, events and rewards continue to belong to the learner.

Missing or corrupt starter bytes are reported through `AppRuntimeStatus.starterContentFailure`. A new database receives no partial catalog. An existing database retains previously verified core words for basic games; each Cloze or Definition read still reloads and verifies its lexical bytes, so an unavailable artifact yields no question for that word. Personal learning remains available. This is not a promise to hide an entire previously installed catalog when one rich artifact is unavailable.

The frozen f14-v1 personalized recommendation policy requires personal content ownership. Shared starter words therefore remain outside those personalized candidates; their ordinary progress, SRS and review paths continue to use learner-owned evidence. Expanding f14 eligibility requires an explicitly versioned policy change and is outside this bounded corpus fix.
