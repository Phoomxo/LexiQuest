# LexiQuest: runtime coverage of the 44 capabilities

Source: `codex/remaining-system-readiness`, through `efff26a6`, on 2026-10-28.
The [frozen catalog](../design/feature-catalog-1.3.0.json) retains revision 1.3.0
and its original 8-domain/44-capability identity.

This matrix distinguishes a connected local runtime from an incomplete or
missing implementation. It does not certify production readiness, research
validity, physical-device UAT or external service operation. The catalog's own
`unverified` rollout fields are not evidence of readiness.

There are 9 connected runtime capabilities, 20 partial capabilities and 15
missing runtime capabilities under this source-based classification. Every
capability still needs the applicable acceptance and release checks.

## Content

| ID | Capability | Runtime state | Evidence and remaining work |
| --- | --- | --- | --- |
| f01 | Curriculum & Learning Pack Catalog | Missing | User vocabulary categories exist; versioned curriculum/learning-pack catalog has no runtime entry. |
| f02 | Learning Pack Detail | Missing | No pack detail combines objectives, version, download state and start action. |
| f03 | Rich Lexical Card | Partial | `VocabListScreen` shows/edit words and SRS speaks them. A combined examples/image/memory card is absent. |
| f04 | Content Version & Quality Control | Partial | Vocabulary revisions, source provenance and captured revision metadata exist. Quality/report workflow and version presentation are incomplete. |

## Learning experience

| ID | Capability | Runtime state | Evidence and remaining work |
| --- | --- | --- | --- |
| f05 | Unified Lesson Shell | Partial | Several screens save through `LearningUseCases`. Shared progress/checkpoint/finish shell is absent. |
| f06 | Flashcard Mode | Connected | Learn, Weakness and Source open `SrsFlashcardsScreen`; reveal/rating/save/finish persist learning. |
| f07 | Meaning Quiz | Connected | `QuizScreen` saves choices and feedback, retries the same answer and finishes a recorded session. |
| f08 | Definition Quiz | Missing | No definition-mode runtime route. The legacy diagnostic is not this mode. |
| f09 | Cloze Test | Partial | `FillInTheBlanksScreen` remains a legacy flow without canonical learning persistence. |
| f10 | Matching Mode | Missing | No current route. Follow the approved Research completion sequence before this unit. |
| f11 | Typed Recall / Writing | Partial | Associative reading and Ghost save typed recall/spelling. Shared typed lesson/draft/IME contract is incomplete. |
| f12 | Handwriting Scratchpad | Missing | No scratchpad with undo, clear and text fallback. |
| f13 | LexiQuest Native Modes Integration | Partial | Reading, Ghost, Shadowing and Source/speech have persisted paths. Cloze/Dictation/Scramble and shared results remain incomplete. |

## Feedback

| ID | Capability | Runtime state | Evidence and remaining work |
| --- | --- | --- | --- |
| f14 | Flashcard-First Recommendation | Connected | `ChooseModeScreen` uses actual due counts and explains its SRS recommendation. |
| f15 | Active-Recall Ladder | Partial | Associative reading has stages and recommendations use due/weakness facts. A common ladder policy is absent. |
| f16 | Session Configuration | Partial | Category and targeted-word selection work. Combined count/time/mode/audio/accessibility configuration is absent. |
| f17 | Immediate Answer Feedback | Connected | Quiz waits for save acknowledgement, supports retry and shows selected/correct answers; SRS acknowledges saves. |
| f18 | Contrastive Distractor Explanation | Missing | Selected/correct answers appear, but no explanation distinguishes a distractor. |
| f19 | Hint, Strategy & Context | Partial | Quiz hints/reveals, reading associations and AI context exist. No shared hint/strategy contract. |
| f20 | Bookmark / Save | Missing | Adding vocabulary is not bookmarking. Saved/unsaved/offline bookmark workflow is absent. |
| f21 | Flag / Report Content | Missing | No revision-bound report sheet and durable report queue. |

## Review and assessment

| ID | Capability | Runtime state | Evidence and remaining work |
| --- | --- | --- | --- |
| f22 | Review Center | Partial | Weakness Clinic and SRS use actual due/mistake facts. Saved/reported content is not integrated. |
| f23 | Focus Timer | Missing | No connected timer configuration, pause and resume. |
| f24 | Automatic Learning-Time Capture | Missing | Timestamps and answer response times exist. Foreground active-time capture is absent. Session elapsed time is not treated as learning time. |
| f25 | Learning Calendar & Weekly Analytics | Partial | New history shows seven local dates with answer counts. Calendar, active-time and outcome analytics remain incomplete. |
| f26 | Goal / Test Countdown | Missing | No editable target date/countdown. |
| f27 | Opt-in Study Reminder | Missing | `SpacedReviewReminderService` only evaluates due state. Scheduling, permission, default-off UI and cancellation are absent. |
| f28 | Learning Assessment & Progress Comparison | Partial | Ordinary progress and frozen evidence/instrument/permit foundations exist. Assignment, baseline/post storage/UI and collection authority are not composed. |

## Motivation

| ID | Capability | Runtime state | Evidence and remaining work |
| --- | --- | --- | --- |
| f29 | Evidence-Based Quest | Partial | Quest use cases/repository exist. Learning hooks, replay, recurring periods and freeze prerequisites remain. |
| f30 | Gentle Streak | Partial | Mastery/Profile show the existing progress-derived streak. V2 streak/freezes are not composed into one authority. |
| f31 | Achievement & Milestone | Connected | Mastery opens achievements backed by persisted unlock facts and dates. |
| f32 | Avatar Level-Up & Cosmetic Unlock | Partial | XP, level and Shop preview/purchase/owned/equip use the current reward authority. Combined avatar level-up/unlock presentation is incomplete. |
| f33 | Contextual Companion | Missing | No event-driven companion with controlled messages and Reduced Motion. |
| f34 | Achievement Share Card | Missing | No private preview/save/share workflow. |

## Personalization

| ID | Capability | Runtime state | Evidence and remaining work |
| --- | --- | --- | --- |
| f35 | Learning Preference & Goal Quiz | Missing | No optional onboarding for goals, available time and interests. |
| f36 | Personal Learning Profile | Partial | Profile settings contain display name and metrics. Editable learning preferences/goals are absent. |
| f37 | Recommendation Panel | Connected | Choose Mode and Weakness offer rule-based due/weakness/quiz recommendations and targeted practice. |
| f38 | Accessibility | Partial | Several flows have adaptive layouts, semantics, input alternatives and text-scale checks. Coverage is incomplete; physical TalkBack is unverified. |
| f39 | Motion & Theme Controls | Partial | Appearance saves System/Light/Dark. Reduced Motion control is absent. |

## Local operation and rollout

| ID | Capability | Runtime state | Evidence and remaining work |
| --- | --- | --- | --- |
| f40 | Local-First Operation | Connected | Bootstrap composes Drift vocabulary/learning/progress/outbox/sync; history reads local facts. Live cross-device rollout remains separate. |
| f41 | Feature Flag & Controlled Rollout | Connected | Main navigation uses `FieldFeatureRegistry` and limited disclosure. Declaring a capability in the separate V2 registry does not compose its runtime. |
| f44 | Offline Content Manager | Partial | Settings connects device-model download/verify/activate/status. Learning-pack pin/repair/remove preserving evidence is absent. |

## Today and history

| ID | Capability | Runtime state | Evidence and remaining work |
| --- | --- | --- | --- |
| f42 | Today Hub | Partial | Choose Mode is a Learn landing with due/weakness recommendations. Assigned/resume/quest aggregation is incomplete. |
| f43 | Learning History | Connected | Mastery opens `LearningHistoryScreen`, through `ProgressUseCases.loadHistory` to owner-scoped Drift pages of 50 recorded sessions, seven local-date answer counts and refresh/retry. |

## Current engineering boundaries

The v11 unit stores ordinary activity class, cumulative hint use and the content
revision actually shown. It preserves immutable retry identity and sync metadata.
It does not activate eligibility policy, change score/SRS/reward projections or
collect research. All research pins are rejected at the current ordinary write
and sync boundaries.

The distinct P256 participation validator, supplied instrument contracts and
frozen catalog remain foundations. Default bootstrap still denies Research
operations. Approved protocol/instrument/issuer/ethics artifacts, participant
rollout authority, live model/service evidence and physical UAT are separate
requirements. No capability is described as complete merely because an
external gate also remains.

The [active integration plan](../superpowers/plans/2026-10-28-unfinished-system-integration.md)
orders Research consent/assignment/authority/capture first, followed by motivation,
native learning integration, versioned content and planning/continuity units.
