# LexiQuest: runtime coverage of the 44 capabilities

Source: `codex/remaining-system-readiness`, through `fabc990f` (v18/35),
updated2026-10-30. Latest full suite/APK: Flutter3266, analysis0, CLI23/23 and
normal debug APK pass. Backend CPU390 passes, with one existing opt-in real
Firebase/OmniVoice E2E skipped. All654 Dart hashes match through checks/build.
The optional Study host connects signed local authority, both actual supplied
presentations, durable switching and baseline/post Motivation to one exact
canonical quiz. Assessment writer, compatible paired comparison and actual
pre/post Study UI are verified with strict ordinary isolation. Production authority
gateway/lifecycle and collection/upload integration remain prerequisites.
Research remains default-off. See [wave11 evidence](2026-10-30-remaining-systems-wave11.md).
The [frozen catalog](../design/feature-catalog-1.3.0.json) retains revision 1.3.0
and its original 8-domain/44-capability identity.

This matrix distinguishes a connected local runtime from an incomplete or
missing implementation. It does not certify production readiness, research
validity, physical-device UAT or external service operation. The catalog's own
`unverified` rollout fields are not evidence of readiness.

There are 10 connected runtime capabilities, 19 partial capabilities and 15
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
| f05 | Unified Lesson Shell | Partial | Meaning Quiz has a durable accepted plan/checkpoint and canonical finish. Other modes still use their separate screens; a common lesson shell is absent. |
| f06 | Flashcard Mode | Connected | Learn, Weakness and Source open `SrsFlashcardsScreen`; reveal/rating/save/finish persist learning. |
| f07 | Meaning Quiz | Connected | `QuizScreen` persists exact questions/options, sticky assistance, pending answer and original finish. History resumes the same owner/session without duplicate answers or rewards; drift/legacy data has an explicit unavailable path. |
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
| f16 | Session Configuration | Partial | Supported category/targeted meaning-quiz configuration and exact accepted deck are immutable and recoverable. Combined user-facing count/time/mode/audio/accessibility configuration remains absent. |
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
| f28 | Learning Assessment & Progress Comparison | Partial | The optional signed Study host connects actual controlled Assessment pre/post, compatible descriptive comparison, Motivation forms and the exact first quiz. Either form order works; pre precedes opening and Assessment-only post does not hold Score. v18 writer/retries, ordinary isolation, owner/export/purge, signature races and actual UI are verified atfabc990f. Genuine production gateway/lifecycle and collection/upload integration remain incomplete; Research default-off. No efficacy/instrument-validation claim. |

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
| f39 | Motion & Theme Controls | Connected | Commit `0eedc90b` wires saved theme/Reduced Motion, OS accessibility propagation and route/card/chat/sheet consumers. Focused 153 tests and Android light 100% settings fixture pass; native dark/200% and hardware gestures remain release checks. |

## Local operation and rollout

| ID | Capability | Runtime state | Evidence and remaining work |
| --- | --- | --- | --- |
| f40 | Local-First Operation | Connected | Bootstrap composes Drift vocabulary/learning/progress/outbox/sync; history reads local facts. Live cross-device rollout remains separate. |
| f41 | Feature Flag & Controlled Rollout | Connected | Main navigation uses `FieldFeatureRegistry` and limited disclosure. Declaring a capability in the separate V2 registry does not compose its runtime. |
| f44 | Offline Content Manager | Partial | Settings connects device-model download/verify/activate/status. Learning-pack pin/repair/remove preserving evidence is absent. |

## Today and history

| ID | Capability | Runtime state | Evidence and remaining work |
| --- | --- | --- | --- |
| f42 | Today Hub | Partial | Choose Mode has due/weakness recommendations and an optional eligible Study entry with exact first-index resume. General assigned/resume/quest aggregation remains incomplete; eager page rendering creates no Research facts. |
| f43 | Learning History | Connected | Mastery opens owner-scoped pages of 50 sessions and seven local-date answer counts. Active stored meaning quizzes have an exact owner/session resume action; refresh, pagination and owner-change hiding remain. |

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
