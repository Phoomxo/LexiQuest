# LexiQuest task-first UI concept · 2026-09-24

## Latest critique and revision plan

The current planning authority is [the learner-diversity and sprint plan, version 5](worksheet-to-play-blueprint.md). It retains version 4's instructional gates and adds the user-approved Agile/SDLC workflow: four-week cadence, capacity-based scope rather than a 16-sprint/64-week forecast, a reuse inventory, three evidence axes, and sequential fresh chats with verified source handoffs. See [the active delivery index](../development/ux-delivery/README.md). Ages 6–50 and all 14 workflow groups remain the expansion scope. The locked user dataset was not accessed; reported learner situations are qualitative input, not population statistics.

**The version 5 plan does not imply an implemented prototype update.** S01-A inventories actual reuse/contracts; S01-B prepares the pilot material and reviewer package; S01-C implements the two journeys; S01-D trials run only when reviewed media and actual participants are available. The draft below still has a quiz-first start, reading difficulty controls that show unchanged content, and writing drafts that do not survive re-entry. No reviewed pilot assets, reviewer assignments or learner results are implied. The historical 215-criterion register remains retired from active acceptance; its evidence and applicable data-integrity principles are preserved.

## Full-system clickable draft

Open [`lexiquest-full-ux-prototype.html`](lexiquest-full-ux-prototype.html) for the current detailed draft. The left panel changes between new learner, returning learner, and no-internet examples; the right panel links to all 14 workflow groups and all 14 practice modes. The phone itself keeps only four primary destinations. Its CSS and JavaScript are local files in this folder and use the Thai font already in the repository. No subscription or account is required.

The worksheet-to-app research, six proposed activity families and rebaseline decision remain in [the version 5 plan](worksheet-to-play-blueprint.md). The prototype's right panel links to each activity draft. This is a future coverage map, not a requirement to finish every activity before testing the two initial journeys. The six families do not automatically add production mode IDs or establish learning outcomes across the target ages.

| Ledger group | Learner-facing draft path | Main states and actions shown |
| --- | --- | --- |
| W01 Identity/connection | ฉัน → บัญชีของฉัน | Local use without login; optional account explanation; data between devices |
| W02 Navigation/preferences | Four tabs → ฉัน → ตั้งค่า | Readable text sizing, contrast, voice and AI paths |
| W03 Vocabulary | คำศัพท์ | Search, categories, add, edit, delete confirmation, import preview, practice |
| W04 AI conversation | วันนี้ / ฉัน → ผู้ช่วยใน LexiQuest | In-app optional helper: off, simulated ready, failed/offline, manual fallback; no external ChatGPT/MCP pairing in the proposed learner flow |
| W05 Exercises/games | ฝึก | Beginner, everyday, and exam goals; six worksheet-derived activity drafts; game choices, all 14 nested mode pages, and optional short exam-practice drafts |
| W06 Reading/CEFR | ฝึก → อ่านและเขียน → อ่านตามระดับ | Short article, Thai support, level explanation, question |
| W07 SRS/weakness | วันนี้ → ทบทวนวันนี้ | Empty/new state, due items, weak-word route, flashcards |
| W08 Planning | ฉัน → วางแผนการเรียน | Daily goal, pack choice, review route |
| W09 Progress/history | ฉัน → ความก้าวหน้า / ประวัติ | Empty/new state and returning example; only learner work counts |
| W10 Quests/rewards/shop | ฉัน → ภารกิจและรางวัล | Empty/new state, quest progress, preview before spending points |
| W11 Speech/audio | ฝึก → ฟังและพูด | Dictation, speaking, shadowing, a short listen-and-answer example, microphone explanation and alternate route |
| W12 Camera | คำศัพท์ → เรียนคำจากภาพ | Local image preview; example camera permission, model unavailable, suggested result, and failure states; learner verifies the word before entering it manually. No camera or model inference runs in the HTML draft. |
| W13 Export | ฉัน → ส่งออกข้อมูล | Select scope, download a sample CSV only |
| W14 Offline/sync | ฉัน → เรียนเมื่อไม่มีเน็ต | Local content, waiting items, conflicting data example |

All 14 mode IDs from `optional-mcp-workflows.json` are present in the Practice disclosure and right-hand map: associative reading, meaning quiz, typed recall, definition quiz, cloze, matching, flashcard, handwriting scratchpad, dictation, speaking, shadowing, CEFR reading, sentence scramble, and word scramble. Their user-visible titles and instructions are in Thai. An English prompt appears only as learning content, with Thai help where relevant. Directions shown on a mode page are illustrative and must be checked against that mode's actual capability before Flutter implementation.

### Practice and exam-preparation direction from learner feedback

Keep ordinary practice first. Familiar worksheet actions become small playable interactions: multiple choice → meaning/definition quiz; fill-in-the-blank → cloze; matching columns → matching; ordering words/letters → scramble; short written response → typed recall or writing scratchpad; reading a passage and answering → CEFR reading. Each interaction needs one clear instruction, a visible question, feedback tied to the learner's answer, a retry, and a way out. Paper format is a content pattern, not a reason to put every mode on the first screen.

An optional **ซ้อมสอบแบบสั้น** entry under ฝึก now shows original sample prompts inspired by TOEIC and IELTS Academic. Learners can try listening, reading, writing, and “อ่านแล้วคิดจากข้อมูล” without an account or AI. The listening sample uses device text-to-speech and exposes a transcript on request; neither is an official exam recording. “อ่านแล้วคิดจากข้อมูล” is a cross-cutting inference skill, **not an official exam section**. The official IELTS Academic sections are Listening, Reading, Writing and Speaking ([IELTS test format](https://ielts.org/take-a-test/test-types/ielts-academic-test)). TOEIC Listening/Reading has distinct Listening and Reading sections ([ETS format](https://www.ets.org/toeic/about/listening-reading.html)); TOEIC Speaking/Writing is a separate assessment ([ETS format](https://www.ets.org/toeic/about/speaking-writing.html)). The draft does not reproduce official questions, impose official timing, estimate bands or scaled scores, auto-grade writing, or represent an authorized exam product.

#### Which new practice formats are justified?

| Priority | Format to add or extend | Existing foundation | Reason and next production requirement |
| --- | --- | --- | --- |
| Now in UX draft | Listen to a sentence or conversation, then answer about a detail | Dictation, audio playback and choice-answer UI | Listening comprehension is different from copying a heard word. Production needs licensed/original recordings, audio availability, repeat/pace policy, captions/transcripts for access, and fixed answer keys. |
| Next content increment | Read a passage and locate evidence; later add True/False/Not Given and heading match | CEFR reading, multiple choice and matching | Supports scanning and distinguishing absent information from contradiction. Every item needs a cited evidence span and explanation, not just a correct option. [IELTS Reading format](https://ielts.org/take-a-test/test-types/ielts-academic-test/ielts-academic-format-reading). |
| Next content increment | Guided writing: sentence → short message/email → description/opinion with a checklist | Typed recall and writing scratchpad | Short tasks serve beginners; longer prompts serve exam goals. Save the learner's draft and revision before any feedback. AI feedback, if used, stays advisory; no official band or automatic proof of mastery. [IELTS Writing format](https://ielts.org/take-a-test/test-types/ielts-academic-test/ielts-academic-format-writing), [TOEIC Writing format](https://www.ets.org/toeic/about/speaking-writing.html). |
| Later, after content and scoring rules | A timed practice set with pause/resume and answer review | Short exam draft | A real simulation needs original/licensed item banks, form versions, timer and interruption rules, owner-scoped attempts, fixed scoring, and a distinct practice score. Do not imply official equivalence. |

These are practice templates and content pathways inside the existing W05/W06/W11 areas; they do not silently change the declared 14 learning-mode IDs or the archived acceptance register. Learners choose by goal: **เริ่มต้นง่าย ๆ**, **ใช้ภาษาในชีวิตจริง**, or **เตรียมสอบ**. Do not require an age declaration to get a usable route. For younger learners, production UX still needs short Thai instructions, larger targets, optional spoken guidance, age-appropriate content and a guardian-reviewed AI experience; adult exam content stays in the optional exam route.

#### In-app AI product decision

The learner-facing AI helper belongs inside LexiQuest. It should answer questions about the current lesson in a native LexiQuest chat surface, with clear data-use disclosure and a visible off/failure state. The proposed flow has **no ChatGPT account login, MCP pairing or cross-app conversation synchronization**. The model/service provider behind the app remains an implementation choice and must be disclosed before real traffic; an in-app interface alone does not make AI offline or free. Never put provider credentials in the client. The app's manual lesson, exercise, score and history paths remain available without AI, and chat suggestions never submit answers or award XP.

The existing Flutter developer-test/provider pairing code remains in the repository for now. Replacing or removing it requires a separate scoped implementation and migration audit, including any existing owner-bound conversation data, rather than treating this HTML draft as a production change.

Before implementing a real mock exam, define licensed/original item provenance, track/version, skill and question type, answer/rubric, time rules, accessible audio and text alternatives, save/resume/exit behavior, scoring authority, and owner-scoped attempt history. Distinguish a short practice set from a timed full simulation in the UI. Do not award learning XP or claim an official score from opening a question or an AI-generated suggestion. The 215-row run is retired from active acceptance; the redesigned scope needs a new register after UX review.

This draft is deliberately age-neutral rather than childish or technical. The ordinary learner never sees workflow IDs, research terminology, provider names, or the 215 acceptance criteria inside the phone. Research-only controls are outside the normal user navigation. AI is an optional help surface and never awards progress. All edits, downloads, audio, and selected images operate on examples in the browser page; the prototype does not authenticate, recognize speech or images, synchronize, or write to LexiQuest storage.

Run `node docs/design/check-full-ux.cjs` from the repository root to verify 14+14 coverage, view routes, action handlers, unique static IDs, and local dependencies. `node docs/design/check-exam-ux.cjs` checks the short exam-practice route and sample flow; `node docs/design/check-worksheet-lab.cjs` checks the six activity examples. `node --check docs/design/lexiquest-full-ux.js` checks syntax. Initial key screens were rendered and inspected before the last copy/legibility edits. The browser automation tool subsequently blocked this local `file://` page under its URL policy; final in-browser click and visual verification therefore requires a manual walkthrough by a human using the HTML file. This does not affect the archived 215-criterion acceptance run.

## First visual concept

Open [`lexiquest-ux-concept.html`](lexiquest-ux-concept.html) in a browser. It is a self-contained, editable HTML/CSS/JavaScript prototype; the only local dependency is the Thai font already in `assets/fonts`. No account, subscription, network, backend, AI provider, or build is required. The four PNG files in this folder are visual review snapshots.

## What this draft changes

| Learner question | Prototype answer | Existing app capability to preserve during implementation |
| --- | --- | --- |
| Where do I start? | One dominant `เริ่มเรียน` action on Today | Manual quick-start lesson with no AI/login dependency |
| How do I continue? | Returning-learner state says `เรียนต่อ` | Canonical current-owner Today/resume and review authorities |
| What should I practice? | Three plain-language goals; 14 modes behind disclosure | Existing mode routes, direction capabilities, feature gates |
| Where are my words? | Dedicated vocabulary tab with search/add | Existing owner-scoped vocabulary storage and practice |
| Where did my effort go? | `ฉัน` gathers progress, history, rewards and settings | Existing durable progress/history/rewards sources |
| Is AI required? | AI entry sits under `ตัวช่วยเพิ่มเติม` | Optional provider state; manual baseline continues when disconnected |

The exercise, words, weekly minutes, and returning state are **illustrative**. The prototype does not write real learning data, award points, connect AI, or replace the Flutter app. Its `เพิ่มคำศัพท์` interaction changes only the current browser page. The four-tab shell is a design proposal, not a code or acceptance change.

## Free design-tool decision

Penpot is the preferred editable design workspace if a shared visual file is needed: its published Professional cloud tier is $0 with unlimited design files and up to eight team members, and it supports interactive prototypes, components, and self-hosting. A Penpot cloud account is required. Lunacy is the offline desktop alternative on Windows with a free tier and local files; its free built-in graphics require attribution, so this concept uses original CSS shapes and no Icons8 assets. Excalidraw is useful for quick wireframes without an account, but this task needed a more realistic, clickable mobile screen.

Sources checked 2026-09-24: [Penpot pricing](https://penpot.app/pricing), [Penpot cloud/self-host guide](https://help.penpot.app/user-guide/first-steps/cloud-selfhost/), [Lunacy pricing](https://icons8.com/lunacy-pricing), [Lunacy local/offline docs](https://lunacy.docs.icons8.com/about/), [Excalidraw](https://plus.excalidraw.com/).

## Review before implementation

Ask a fresh learner, without pointing at buttons, to start a short lesson, find a specific practice type, add a word, and find progress. Repeat with a returning learner. Record task success, wrong turns, hesitation, and the names they use for tabs. If learners still hesitate, revise the navigation and copy before changing Flutter production UI. The old 215-criterion R3 register is historical, not an active release gate; a new register follows the redesigned scope.

## Full-system prototype work package

The user requested a detailed second draft covering the product end to end for Thai learners aged approximately 6–50, including people who cannot read English interface copy. The deliverable is a separate clickable prototype linked from this folder. It remains a design artifact, not a production Flutter change.

1. **Inventory and map.** Use `optional-mcp-workflows.json` as the 14 workflow-group inventory, `NavigationGlossary` and current Flutter screens for route names, and the 14 nested modes from the ledger. Preserve manual baseline and optional AI distinctions. Put every group and mode in a coverage map with a clickable entry.
2. **Task-first navigation.** Keep four plain-Thai destinations (วันนี้, ฝึก, คำศัพท์, ฉัน). Put less frequent systems behind a visible, named path rather than a long first-view menu. Each screen must answer what the learner can do, what happens next, and how to return.
3. **Detailed states.** Sketch fresh/returning/no-account states; answer feedback and retry; vocabulary add/find/import; review/planning/packs; progress/history/rewards; speech/camera permissions; export; offline/sync; AI never connected/connected/failed. Show only plausible samples and mark simulated data.
4. **Thai copy and accessibility.** All navigation, instructions, errors, and action labels must be Thai-first, short, and understandable without technical vocabulary. English may appear in learning material with Thai support. Maintain large tap areas, readable type, clear contrast, no color-only feedback, back paths, and narrow-phone scrolling.
5. **Visual and structural verification.** Render and inspect key screens at phone width, exercise both fresh and returning flows, verify every declared route/action resolves, check no duplicate IDs or JavaScript syntax errors, and compare the coverage map to all 14+14 identifiers. Do not run the retired 215-criterion acceptance or change Flutter application data.

No external service, subscription, device data, migration, or deployment is needed. Before turning this into Flutter UI, test the four core learner tasks and accessibility with real users; the prototype itself cannot prove usability.
