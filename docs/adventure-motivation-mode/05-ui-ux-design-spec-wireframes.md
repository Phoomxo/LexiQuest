# UI/UX Design Specification and Wireframes — Adventure Motivation Mode

**Document ID:** LQ-AMM-UX-001
**Version:** 1.2
**Status:** Draft for Owner and Learner Review
**Date:** 2026-09-04
**Baseline:** LexiQuest 8/44 at `99f7fb21`
**References:** `AMM-AUDIT-001 v1.0`, `LQ-AMM-SRS-001 v1.2`, `LQ-AMM-SDS-001 v1.2`
**Decision references:** `LQ-AMM-ADR-001 v1.2`, `LQ-AMM-MDS-001 v1.2`
**Brand naming rule:** Show `LexiQuest`; do not add the removed “เก่งศัพท์” label
**Visual companions:** [`05a-wireframe-overview.svg`](05a-wireframe-overview.svg), [`05b-research-participation-wireframes.svg`](05b-research-participation-wireframes.svg) and [`05c-pair-matching-prototype-wireframes.svg`](05c-pair-matching-prototype-wireframes.svg)

## 1. Experience Intent

Adventure Motivation Mode makes existing learning feel like a short, understandable journey. It answers four questions immediately:

1. วันนี้ควรทำอะไร;
2. ทำไมระบบแนะนำสิ่งนี้;
3. ใช้เวลาประมาณเท่าไร;
4. ถ้าทำไม่ได้ จะเกิดอะไรต่อไป.

The interface does not simulate progress independent of learning. The map is a visual explanation of canonical Today Hub state. A learner can switch to Standard at any time without losing a session, evidence, due review or reward already committed by existing authorities.

## 2. User Principles

### 2.1 Motivation without pressure

- Use invitation: “เริ่มเมื่อพร้อม” rather than urgency or threat.
- Never show hearts, lives, loss, red countdowns, shame copy or public rank.
- A streak may be shown as continuity already earned; it is not a debt.
- Wrong answers produce support and a future review path, not loss of map progress.
- Stop/leave actions are honest and available; do not use dark patterns.

### 2.2 One primary decision per screen

At the first viewport, expose one primary learning CTA. Secondary actions are Standard view, change duration, accessibility/list view and details. A world screen with many equally prominent quests is prohibited in v1.

### 2.3 Explain, do not decorate over uncertainty

Every recommendation includes a bounded reason from the current authority, for example:

- “มีคำที่ถึงเวลาทบทวน 8 คำ”;
- “ต่อจากบทที่เรียนค้างไว้”;
- “ฝึกจุดที่ยังสับสนจากคำตอบล่าสุด”.

After Host authorization, when canonical data becomes stale or Adventure content is unavailable, the UI says so and can render Standard from the same snapshot; before authorization it returns Learn. It never invents a mission.

### 2.4 Existing learning remains familiar

After accepting a mission, the learner enters the existing Unified Lesson Shell. Adventure may show a compact origin label and supportive scripted companion outside the answer surface, but answer controls, correctness, hints, accessibility and evidence semantics stay unchanged.

## 3. Target Users and Needs

| Persona | Need | Design response |
|---|---|---|
| New/returning learner | Does not know where to begin | One recommended mission, reason and duration |
| Learner with due review | Wants manageable work | Due-first mission with exact count and no forced extension |
| Learner after repeated errors | Fears failure | Support ladder, one repair, future Review/SRS continuity |
| Busy learner | Has 5–10 minutes | Change-duration control using existing policy |
| Screen-reader/keyboard user | Map cannot be spatial-only | List parity, semantic state, logical traversal |
| Reduced-motion user | Animation is distracting | Zero-duration transitions and static companion pose |
| Offline learner | Needs predictable behavior | Verified-local status and immediate Standard fallback |
| Adult research participant | Must understand optional prompt and permit status | Natural breakpoint, Skip, consent details, no learning block |
| Guardian | Must grant/refuse permission without pressure | Plain purpose/data/withdraw/no-learning-impact and explicit issue state |
| Minor learner | Must assent independently in age-banded language | Equal Agree/Not now actions; guardian permission never substitutes assent |

## 4. Information Architecture

```text
Existing Learn destination (bottom navigation unchanged)
└── additive card `home/learn/today-experience` (eligible only)
    └── Today Experience Host
        ├── Standard `TodayHubView(snapshot)` (available only after Host authorization)
        └── Adventure presentation (hidden/default-off)
            ├── Adventure Home
            │   ├── Primary Mission Card
            │   ├── Journey Map
            │   ├── Equivalent Journey List
            │   ├── Companion Summary
            │   └── Status / fallback panel
            ├── Mission Details sheet
            │   ├── Why this mission
            │   ├── Estimated duration / change duration
            │   ├── Activity/count/accessibility summary
            │   └── Start / return to Standard
            ├── Existing Unified Lesson Shell
            │   ├── Existing activity UI
            │   ├── Existing feedback/hint
            │   └── Adventure context outside answer semantics
            ├── Adventure Result
            │   ├── Learning
            │   ├── Effort
            │   ├── Engagement
            │   ├── Existing reward/quest projection
            │   └── Next action / Review
            └── Optional Research Participation
                ├── Guardian permission (minor)
                ├── Learner assent (minor)
                ├── Research prompt (active permit/run)
                └── Invalid/expired/revoked permit → product continuation
```

There is no separate Adventure vocabulary library, flashcard library, profile, shop or history. Existing destinations remain the canonical place for those functions. Adventure deep-links to them through typed actions.

## 5. Navigation Model

### 5.1 Entry outside a research protocol

1. Learn surface remains unchanged and has no card while Adventure is hidden.
2. When visible/enabled and Today/content dependencies are ready, show one additive Today Experience card; never add a bottom tab.
3. Card authorization creates one `entryAttemptId`, opens Today Experience Host and loads one Today snapshot; Product Entry reads only an optional active permit projection, never raw receipts.
4. Hidden/disabled/unknown or stale direct route returns Learn without constructing Host/snapshot/research opportunity.
5. During prototype, an explicit session choice can preview Adventure without persistence.
6. After preference v2 is deployed end-to-end, remember `standard` or `adventure` for the owner.
7. Standard remains available through the top app bar and fallback panels.

### 5.2 Entry inside a research protocol

1. A valid signed `ActivePresentationPermit` selects the intended protocol treatment.
2. Active permit gates protocol treatment and research measurement, not the right to learn.
3. A learner assigned Adventure may switch to Standard.
4. The assignment is not rewritten; a neutral presentation-change event records crossover in the participant opportunity.
5. A withdrawn, expired, revoked or nonparticipant user falls back through session choice/preference/Standard and continues product learning; no new research row is created.

### 5.3 Back behavior

| Location | System back result |
|---|---|
| Adventure Home | Close Today Experience Host and return to Learn; no data mutation |
| Mission sheet before start | Close sheet, remain Adventure Home |
| Accepted lesson | Existing lesson close/abandon confirmation and lifecycle |
| Result | Close result and recompose journey |
| Research prompt | Skip/close without changing learning completion |
| Guardian permission/learner assent | Not now/decline without changing learning access |
| Unauthorized entry | Return Learn; do not show Standard through the hidden route |
| Authorized Host error with snapshot | Standard `TodayHubView(snapshot)` |
| Today dependency unavailable | Return to Learn with bounded reason |

### 5.4 Standard escape rule

“มุมมองมาตรฐาน” is visible without scrolling on every Adventure top-level screen. During an accepted learning session, escape follows the existing safe-close lifecycle and never bypasses a pending evidence commit.

## 6. Screen Inventory

| Screen ID | Name | Purpose | Primary action | Canonical dependency |
|---|---|---|---|---|
| UX-00 | Learn Today Experience Entry | Add one eligible entry without changing baseline navigation | Open Today Experience | feature/dependency only |
| UX-01 | Product Presentation Resolver | Choose safe effective presentation | Continue to resolved view | feature/dependency/preference/active permit projection; no raw receipts |
| UX-02 | Adventure Home — Map | Show one mission and three-node journey | View/Start mission | Today Hub + journey projection |
| UX-03 | Adventure Home — List | Accessible equivalent of map | View/Start mission | same snapshot as UX-02 |
| UX-04 | Mission Details | Explain and confirm work | Start mission | session composer |
| UX-05 | Existing Lesson with Adventure Context | Run canonical learning | Existing answer action | Unified Lesson Shell |
| UX-06 | Incorrect Feedback/Repair Notice | Explain error and safe future retry | Continue | existing feedback + repair policy |
| UX-07 | Adventure Result | Separate outcomes and next step | Continue journey/Review | canonical session and projection receipts |
| UX-08 | Resume Card | Resume accepted session first | Resume | existing recovery authority |
| UX-09 | Empty/Unavailable/Fallback | Preserve access when data/assets fail | Open Standard | Today/asset/dependency state |
| UX-10 | Research Prompt | Optional bounded response | Submit/Skip | consented measurement run |
| UX-11 | Presentation Preference | Save Standard/Adventure later | Save | learner preference v2 |
| UX-12 | Guardian Permission | Explain and issue/decline minor permission | Allow / Not now / details | approved enrollment + guardian receipt authority |
| UX-13 | Learner Assent | Obtain independent age-banded assent | Agree / Not now | guardian-approved enrollment + assent authority |
| UX-14 | Permit Invalid/Expired/Revoked | Explain research mode stopped | Continue learning / details | validated permit status |
| UX-15 | Withdrawal Continuation | Confirm research stopped without product penalty | Continue Standard/product choice | withdrawal result |

## 7. Global Layout and Design Tokens

### 7.1 Existing design system

Use repository `M3Theme`:

| Token | Existing value/use |
|---|---|
| Primary | `#1E88E5` (`M3Theme.primaryBlue`) |
| Accent | `#3F51B5` (`M3Theme.accentIndigo`) |
| Light background | `#F8FAFC` |
| Card surface | white in light theme |
| Typeface | `NotoSansThai` |
| Card radius | 16 logical px |
| Minimum themed button size | 48×48 logical px |

Adventure may derive tonal containers from `ThemeData.colorScheme`; it must not introduce an independent hard-coded fantasy palette that fails dark/high-contrast modes.

### 7.2 Spacing and sizing

| Token | Value | Use |
|---|---:|---|
| space-1 | 4 | icon/text micro gap |
| space-2 | 8 | compact component gap |
| space-3 | 12 | internal card grouping |
| space-4 | 16 | standard padding |
| space-5 | 24 | section separation |
| space-6 | 32 | major separation |
| touch-min | 48×48 | every action |
| content-max | 720 | tablet/desktop reading column |
| bottom-safe | device inset + 16 | persistent action clearance |

### 7.3 Typography roles

| Role | Guidance |
|---|---|
| App title | Material titleLarge; “LexiQuest” or screen title only |
| Mission title | titleLarge/semibold; maximum two lines before reflow |
| Recommendation reason | bodyMedium; never ellipsize essential meaning |
| Node label | titleSmall + state phrase |
| Result axis | titleMedium + independent explanation |
| Technical detail | bodySmall; expandable, not primary copy |

## 8. Component Specifications

### 8.1 Adventure App Bar

Required content:

- leading: existing navigation/back behavior;
- center/title: `LexiQuest` on root, descriptive title on subview;
- action 1: map/list toggle where relevant;
- action 2: “มุมมองมาตรฐาน” text/icon action, always visible without scroll.

Do not add the removed “เก่งศัพท์” text. Do not place XP/Coins as competing headline metrics.

### 8.2 Primary Mission Card

Order:

1. bounded state label: “ภารกิจแนะนำวันนี้”;
2. activity title from glossary;
3. reason from canonical recommendation/Today source;
4. estimated duration and item count;
5. offline/local readiness when relevant;
6. one filled CTA: “ดูภารกิจ” or “เรียนต่อ”;
7. optional text action: “เปลี่ยนเวลา”.

States:

| State | CTA | Copy requirement |
|---|---|---|
| ready | ดูภารกิจ | reason + duration |
| resume | เรียนต่อ | state that previous session is preserved |
| loading | disabled progress | semantic busy state |
| stale | รีเฟรช | explain that start is temporarily blocked |
| unavailable | มุมมองมาตรฐาน | no fabricated mission |
| offline-ready | ดูภารกิจ | state content is available offline |
| offline-missing | มุมมองมาตรฐาน | optional download only when online |

### 8.3 Journey Node

Each node consumes one `AdventureNodeSnapshot` and exposes exactly one semantic action.

| State | Visual | Text | Action |
|---|---|---|---|
| completed | check icon + filled shape | “เสร็จแล้ว” | Open canonical summary/history if allowed |
| current | flag/compass + thick outline | “ภารกิจปัจจุบัน” | Open mission |
| available | open circle + arrow | “พร้อมเริ่ม” | Open mission |
| locked | lock + neutral surface | explicit reason | none or explain reason |
| unavailable | warning/info + dashed outline | dependency/asset reason | Standard/fix action |

Color is supplementary only. Path decoration is excluded from semantics.

### 8.4 Map/List toggle

- Same snapshot, node order, labels and actions.
- Toggle is not stored as learning preference; it may follow accessibility/display preference if later approved.
- Screen reader defaults to list semantics even when map art is visually present.
- The list is not a degraded version; it has feature parity.

### 8.5 Companion Panel

Contains:

- existing equipped avatar/cosmetic or neutral packaged companion;
- one scripted reaction line;
- accessible text equivalent;
- no relationship meter;
- no raw answer text;
- no AI-generated text;
- no animation when reduced motion is on.

The panel is secondary to learning. It must not push the primary mission CTA below the first practical viewport on common phones.

### 8.6 Mission Details Sheet

Required sections:

- title/activity;
- “ทำไมเป็นภารกิจนี้”;
- “ใช้เวลาประมาณ” with approved duration choices;
- count and activity mix;
- accessibility/voice/offline availability;
- primary “เริ่มภารกิจ”;
- secondary “ไว้ภายหลัง” and visible Standard action.

Sheet start is single-flight. Closing before acceptance writes no learning or engagement reward.

### 8.7 Lesson Context Strip

Optional compact strip outside the answer component:

- node/mission title;
- position such as “3 จาก 8” only if the existing session safely exposes it;
- companion pose without blocking controls;
- no separate timer unless the existing configuration is timed;
- no Adventure correctness, points or life display.

### 8.8 Incorrect Feedback and Repair Notice

Immediate feedback remains the existing reviewed feedback UI. Adventure adds only a supportive, non-authoritative notice such as:

“คำนี้ยังไม่ผ่านในครั้งนี้ เดี๋ยวระบบจะช่วยทบทวนอีกครั้งโดยไม่ลดความคืบหน้าเดิม”

If current-session repair is possible:

“จะกลับมาอีกครั้งหลังทำข้ออื่นสักครู่”

If fewer than three intervening items remain:

“เก็บคำนี้ไว้ทบทวนครั้งถัดไปแล้ว”

Do not promise a repair if SRS/review commit is pending or failed.

### 8.9 Result Axes

The result screen uses three independent sections:

| Axis | Shows | Must not claim |
|---|---|---|
| Learning — “สิ่งที่เรียนรู้” | correct/guided/needs review, skills/content | total mastery from engagement alone |
| Effort — “ความพยายาม” | active duration, completed items, resumed work | correctness or intelligence |
| Engagement — “สิ่งที่ทำในแอป” | mission started/completed, optional map actions | learning gain |

Existing quest/streak/reward outcomes appear in a fourth optional area “ผลจากระบบเดิม”. A pending projection says “ผลการเรียนบันทึกแล้ว กำลังอัปเดตรางวัล” and never re-grants.

### 8.10 Research Prompt

- Display only at a natural breakpoint after learning completion is safe.
- Title: “ช่วยบอกความรู้สึกหลังเรียน” rather than “ทำแบบทดสอบ”.
- State why: improve motivation experience.
- Use bounded response choices only.
- Provide `ข้าม` at equal accessibility, not hidden in low contrast.
- Link to consent details.
- Closing/Skip never changes reward, progression or next learning access.

### 8.11 Guardian permission

- Guardian-led surface states purpose, bounded data, duration/expiry, withdrawal and that refusal has no effect on learning.
- `Allow participation` and `Not now` are visually balanced; no preselected consent and no countdown.
- Success shows “permission recorded; learner assent still required” rather than “enrolled”.
- The app stores an opaque receipt reference and age-band code, never guardian PII or full DOB.

### 8.12 Learner assent

- Uses short age-banded copy and addresses the learner directly.
- `I agree` and `Not now` remain independently actionable even when guardian permission exists.
- Not now returns to learning with zero protocol treatment/research rows.
- Completion restores focus to the control that opened the flow and announces one concise status.

### 8.13 Invalid, expired, revoked or withdrawn permit

- State headline says research mode has stopped; it never says learning access was removed.
- Primary action is `Continue learning`; secondary action opens participation details when permitted.
- If the Host was already authorized, fallback uses the once-loaded Standard view; a new unauthorized direct route returns Learn.

## 9. Detailed Screen States

### UX-02/03 Adventure Home state matrix

| Feature | Dependency | Snapshot | Asset | Effective view |
|---|---|---|---|---|
| hidden | any | any | any | Learn baseline; no card/spacing/dead route |
| hidden/disabled/unknown direct entry | any | any | any | Return Learn; no Host/snapshot/opportunity |
| stale route | any | any | any | Return Learn with bounded reason |
| on but dependency missing before authorization | missing | any | any | Return Learn; card absent |
| on | ready | loading | verified | skeleton/busy; Standard available |
| on | ready | valid | verified | Adventure map/list |
| on | ready | stale | verified | stale label, unsafe CTA disabled, refresh |
| on | ready | valid | corrupt | quarantine panel + Standard |
| on | ready | empty | verified | calm empty state + Standard/History |
| emergency-off | any | any | any | block new mission; safe-close accepted session |

### UX-07 Result state matrix

| Learning commit | Side-effect projection | Result |
|---|---|---|
| pending/failed | not run | keep exact retry state; no completion/reward claim |
| committed | pending | show learning axes + “รางวัลกำลังอัปเดต” |
| committed | committed | show learning axes + canonical receipts |
| committed | permanently unavailable but retryable later | show learning success, Standard/continue; diagnostics only |
| assessment | excluded | outcome/assessment result only; no motivation reward area |

## 10. Content and Copy System

### 10.1 Voice

Calm, specific, supportive, concise. Address the task, not the learner’s ability.

| Situation | Approved direction | Prohibited direction |
|---|---|---|
| Start | “พร้อมเมื่อไร เริ่มภารกิจ 8 คำได้เลย” | “รีบทำก่อน streak หาย” |
| Incorrect | “ยังไม่ใช่คำนี้ ลองดูความต่างแล้วไปต่อ” | “ผิด! เสียพลัง 1” |
| Skip | “ข้ามได้ เก็บไว้ทบทวนภายหลัง” | “ยอมแพ้แล้ว” |
| Return | “ข้อมูลเดิมยังอยู่ เรียนต่อจากจุดนี้ได้” | “หายไปนานเลยนะ” |
| Complete | “จบภารกิจนี้แล้ว” | “เก่งขึ้นแน่นอน 100%” |
| Technical failure | “ยังเปิดภารกิจนี้ไม่ได้ ใช้มุมมองมาตรฐานได้” | “คุณทำให้ระบบผิดพลาด” |

### 10.2 Stable identity versus display copy

Tests and navigation must target stable keys/semantics such as `home/learn/associative-reading`, not obsolete visible English copy. Thai glossary currently labels this activity “อ่านเชื่อมโยงความจำ”. Display copy may evolve through content review without breaking route identity.

### 10.3 Localization readiness

Every content record contains:

- Thai and English key;
- semantics key;
- short label for narrow layout;
- state-specific reason key;
- content review classification;
- catalog version/checksum.

Missing required locale invalidates that catalog bundle and triggers safe fallback.

## 11. Accessibility Specification

### 11.1 Semantics

Each actionable node announces:

`<title>, <state>, <reason>, <duration>, <action>`

Example: “ทบทวนคำที่ถึงเวลา, พร้อมเริ่ม, มี 8 คำถึงเวลาทบทวน, ประมาณ 7 นาที, เปิดรายละเอียดภารกิจ”.

Decorative path, sparkles, scenery and avatar ornament are excluded from the semantics tree.

### 11.2 Focus order

1. App bar back/navigation;
2. Standard switch;
3. primary mission card;
4. current node;
5. remaining journey nodes in logical order;
6. companion text;
7. secondary/help actions.

Modal sheets trap focus only while open and restore focus to the invoking control on close.

### 11.3 Text scale and reflow

At 200% text:

- map may switch visual composition to vertical/list-first;
- no essential copy is ellipsized;
- CTA remains visible and at least 48 px high;
- result axes stack vertically;
- bottom sheet becomes full-screen/scrollable while keeping actions reachable.

### 11.4 Motion

Use `M3Theme.motionDuration`. When `MediaQuery.disableAnimations` or saved reduce-motion is true:

- path transitions are zero duration;
- no parallax, bounce or particle motion;
- companion uses a static pose;
- state change uses text/icon update and optional haptic only if platform/user permits.

### 11.5 Contrast and non-color state

WCAG 2.2 AA applies to text and controls. Every state has at least two of icon, text, shape and pattern. High contrast derives from the accessibility scope, not a parallel theme.

### 11.6 Mandatory research/minor accessibility matrix

| Flow | TalkBack | Switch Access/keyboard | Text 200% | Focus restoration | Offline validation |
|---|---|---|---|---|---|
| Optional Research Prompt | Required | Required | Required | To invoking prompt action | Active permit/run only |
| Guardian Permission | Required | Required | Required | To participation card | Signed receipt result announced |
| Learner Assent | Required | Required | Required | To participation card | No cached assent may be inferred |
| Invalid/Expired/Revoked Permit | Required | Required | Required | To Continue learning | Fail closed; product continues |
| Withdrawal race | Required | Required | Required | To learning surface | No new opportunity/event/enqueue |

Every required action must have unique role/name/state, no focus trap, no timed dismissal and a 48×48 logical-pixel target. Failure in any primary flow is blocking even when aggregate accessibility percentage passes.

## 12. Responsive Behavior

| Width | Layout |
|---|---|
| <360 | list-first; one-column cards; short glossary label |
| 360–599 | portrait map with mission card above; sheets full width |
| 600–839 | two-pane mission summary + map/list |
| ≥840 | centered max-width content; map and details side by side; no stretched text lines |

Landscape with short height prioritizes the mission CTA and list view. The companion area collapses before essential mission information.

## 13. Low-Fidelity Wireframes

### 13.1 UX-02 Adventure Home — phone

```text
┌──────────────────────────────────────┐
│ ☰             LexiQuest      มาตรฐาน │
├──────────────────────────────────────┤
│ ภารกิจแนะนำวันนี้                    │
│ ┌──────────────────────────────────┐ │
│ │ ทบทวนคำที่ถึงเวลา               │ │
│ │ มี 8 คำจากประวัติการเรียน       │ │
│ │ ⏱ ประมาณ 7 นาที  ✓ ใช้ออฟไลน์ได้│ │
│ │                                  │ │
│ │        [ ดูภารกิจ ]              │ │
│ │          เปลี่ยนเวลา              │ │
│ └──────────────────────────────────┘ │
│                                      │
│ เส้นทางวันนี้              [แผนที่|รายการ]│
│        ✓ ทบทวนเดิม                   │
│        │                             │
│      ◎ ภารกิจปัจจุบัน                │
│        │                             │
│      ○ ต่อไป: ฝึกจุดที่สับสน         │
│                                      │
│ [ตัวละคร] “เริ่มเมื่อพร้อมนะ”         │
└──────────────────────────────────────┘
```

### 13.2 UX-03 Journey List — accessibility parity

```text
┌──────────────────────────────────────┐
│ ← เส้นทางวันนี้              มาตรฐาน │
├──────────────────────────────────────┤
│ 1  ✓ ทบทวนเดิม                      │
│    เสร็จแล้ว · เปิดสรุป              │
├──────────────────────────────────────┤
│ 2  ◎ ทบทวนคำที่ถึงเวลา              │
│    พร้อมเริ่ม · 8 คำ · 7 นาที        │
│                         [ดูภารกิจ]   │
├──────────────────────────────────────┤
│ 3  🔒 ฝึกจุดที่สับสน                 │
│    เปิดหลังจบภารกิจปัจจุบัน          │
└──────────────────────────────────────┘
```

### 13.3 UX-04 Mission Details

```text
┌──────────────────────────────────────┐
│ ทบทวนคำที่ถึงเวลา                 ✕ │
├──────────────────────────────────────┤
│ ทำไมเป็นภารกิจนี้                    │
│ มี 8 คำที่ถึงเวลาทบทวนจาก SRS        │
│                                      │
│ ใช้เวลาประมาณ                        │
│ [ 5 นาที ] [ 10 นาที ] [ ไม่จำกัด ]  │
│                                      │
│ กิจกรรม: ทบทวน + จับคู่              │
│ เนื้อหาพร้อมใช้งานในเครื่อง           │
│                                      │
│ [        เริ่มภารกิจ        ]         │
│ ไว้ภายหลัง        ใช้มุมมองมาตรฐาน   │
└──────────────────────────────────────┘
```

### 13.4 UX-05 Existing Lesson with context

```text
┌──────────────────────────────────────┐
│ ← ทบทวนคำที่ถึงเวลา          3 จาก 8│
├──────────────────────────────────────┤
│  [ Existing Unified Lesson Shell ]   │
│                                      │
│        canonical question/answer     │
│        existing hint/feedback        │
│        existing accessibility        │
│                                      │
├──────────────────────────────────────┤
│ [static companion] “ค่อย ๆ นึกได้”   │
└──────────────────────────────────────┘
```

No lives, Adventure points or separate timer are present.

### 13.5 UX-06 Incorrect and repair

```text
┌──────────────────────────────────────┐
│ ยังไม่ใช่คำนี้                       │
│ [existing contrastive feedback]      │
│                                      │
│ จะกลับมาอีกครั้งหลังทำข้ออื่นสักครู่ │
│ ความคืบหน้าเดิมไม่ถูกลด              │
│                                      │
│                [ ไปข้อต่อไป ]        │
└──────────────────────────────────────┘
```

### 13.6 UX-07 Result

```text
┌──────────────────────────────────────┐
│ ภารกิจเสร็จแล้ว              มาตรฐาน │
├──────────────────────────────────────┤
│ สิ่งที่เรียนรู้                       │
│ ✓ จำได้ด้วยตนเอง 5  ◐ มีตัวช่วย 2    │
│ ↻ เก็บไว้ทบทวน 1                    │
├──────────────────────────────────────┤
│ ความพยายาม                           │
│ ใช้เวลาเรียนจริง 6 นาที · ทำ 8 ข้อ   │
├──────────────────────────────────────┤
│ สิ่งที่ทำในแอป                       │
│ จบภารกิจวันนี้ 1 ภารกิจ               │
├──────────────────────────────────────┤
│ ผลจากระบบเดิม                        │
│ Quest อัปเดตแล้ว · Streak คงต่อเนื่อง │
│                                      │
│ [ ดูเส้นทางต่อ ]   [ ไปหน้าทบทวน ]   │
└──────────────────────────────────────┘
```

### 13.7 UX-09 Safe fallback

```text
┌──────────────────────────────────────┐
│ Adventure ยังไม่พร้อม                │
├──────────────────────────────────────┤
│ ยังตรวจสอบข้อมูลภารกิจนี้ไม่ได้       │
│ การเรียนและประวัติเดิมยังอยู่ครบ      │
│                                      │
│ [      ใช้มุมมองมาตรฐาน      ]       │
│ [ ลองตรวจสอบอีกครั้ง ]                │
│ รายละเอียดทางเทคนิค ▾                 │
└──────────────────────────────────────┘
```

### 13.8 UX-10 Optional research prompt

```text
┌──────────────────────────────────────┐
│ ช่วยบอกความรู้สึกหลังเรียน            │
│ คำตอบนี้ใช้ศึกษาประสบการณ์แรงจูงใจ    │
│                                      │
│ ตอนนี้คุณอยากกลับมาเรียนต่อแค่ไหน?    │
│ ○ น้อย  ○ ค่อนข้างน้อย  ○ ปานกลาง    │
│ ○ ค่อนข้างมาก  ○ มาก                 │
│                                      │
│ [ ส่งคำตอบ ]              ข้าม       │
│ ดูรายละเอียดความยินยอม                │
└──────────────────────────────────────┘
```

### 13.9 Research participation companion

Detailed low-fidelity screens for guardian permission, learner assent, optional prompt, permit invalidation and post-withdrawal continuation are in [`05b-research-participation-wireframes.svg`](05b-research-participation-wireframes.svg). The companion is normative for action hierarchy, escape paths and focus-return annotations; final visual styling remains governed by Material 3 tokens in this document.

## 14. Prototype and Validation Plan

### 14.1 Prototype A — no persistence

- Use fixture Today snapshot and catalog.
- Session-local Standard/Adventure switch.
- No database migration, research row or production entry.
- Validate hierarchy, comprehension, Standard escape, map/list parity and copy.

### 14.2 Prototype B — canonical read-only

- Use real Today Hub readers in an internal/hidden route.
- Internal route is not a production learner entry; production uses the eligible additive Learn card only after ADR-001 route gate.
- No mission start or writes.
- Validate deterministic projection, empty/stale/offline behavior and route disposition.

### 14.3 Prototype C — learning bridge

- Start existing lessons through typed application port.
- Compare Standard/Adventure command and evidence fixtures.
- Validate wrong-answer copy, repair understanding, result axes and restart.

### 14.4 Learner research questions

Ask learners to demonstrate, not merely rate:

1. “ถ้าจะเริ่มเรียนตอนนี้ คุณกดตรงไหน?”
2. “เพราะอะไรระบบแนะนำภารกิจนี้?”
3. “ถ้าตอบผิด คุณคิดว่าจะเสียอะไรหรือไม่?”
4. “ถ้าไม่อยากใช้แผนที่ จะกลับไปแบบเดิมอย่างไร?”
5. “ผลส่วนไหนบอกการเรียนรู้ และส่วนไหนบอกความพยายาม?”
6. “คำถามหลังเรียนข้ามได้ไหม และเกี่ยวกับรางวัลหรือไม่?”

## 15. UX Acceptance Criteria

| ID | Criterion |
|---|---|
| UX-AC-01 | 5/5 formative participants can identify the primary mission without prompting |
| UX-AC-02 | At least 4/5 can explain the recommendation reason in their own words |
| UX-AC-03 | 5/5 can find Standard in no more than two intentional actions |
| UX-AC-04 | 5/5 understand that a wrong answer does not remove existing progress/access |
| UX-AC-05 | Map and list expose identical node actions and states in automated parity tests |
| UX-AC-06 | Required screens pass 200% text, dark, high contrast and reduced-motion checks |
| UX-AC-07 | Screen-reader traversal reaches primary mission and Standard switch with no trap |
| UX-AC-08 | Result comprehension distinguishes learning, effort and engagement for at least 4/5 participants |
| UX-AC-09 | Research prompt Skip is discoverable and does not alter learning/reward state |
| UX-AC-10 | Missing/corrupt asset always leaves a usable Standard action |
| UX-AC-11 | Hidden/disabled/unknown/stale direct route returns Learn and creates no Host/snapshot/opportunity |
| UX-AC-12 | Guardian 5/5 and learner 5/5 independently understand Skip/withdraw/no-learning-impact |
| UX-AC-13 | Prompt/guardian/assent/invalid-permit flows pass TalkBack, Switch Access, text 200% and focus restoration |
| UX-AC-14 | Permit expiry/withdrawal keeps product learning available and creates no new research operation |
| UX-AC-15 | No visible “เก่งศัพท์” label is introduced; brand remains LexiQuest |
| UX-AC-16 | No prohibited pressure mechanic/copy is present in design or content catalog |

## 16. Design Handoff Checklist

- Approved screen inventory and stable route IDs
- Component/state table linked to SRS IDs
- Thai/English copy catalog with semantics labels
- Responsive rules and 200% examples
- Reduced-motion behavior for every animated element
- Map/list parity matrix
- Error/fallback and pending-evidence/reward states
- Research participation companion wireframe with guardian/assent/permit states and focus annotations
- Test keys based on stable identity, not display copy
- Catalog/asset checksums and ownership
- Signed UX, accessibility and content review
- Findings transferred to RTM, Test Plan and UAT

## 17. Pair Matching Prototype UI Standard

### 17.1 Experience model

Pair Matching เป็นกิจกรรมสั้นใน Learn, Today Mission, Review และ Adventure ไม่ใช่ destination ใหม่ รูปแบบที่ผู้ใช้คุ้นเคยคือ tap-to-match สองคอลัมน์ แต่เอกลักษณ์ LexiQuest คือคำถูกเลือกจาก canonical work, wrong ได้รับการช่วยอย่างไม่ลงโทษ, timer เป็นทางเลือก และผลกลับไป Review อย่างโปร่งใส

```text
Context card
 → Setup (density + timer)
 → Pair board
    ├─ correct → matched progress
    ├─ wrong → feedback → delayed repair/guided completion
    └─ timeout → continue untimed | +30 once | restart round
 → Result (stars + learning axes + time)
 → source return | Review | Practice Replay
```

### 17.2 Pair screen inventory

| UX ID | Screen/state | Primary purpose | Primary action |
|---|---|---|---|
| UX-P01 | Contextual entry card | อธิบายว่าทำไมได้ชุดนี้และเริ่มโดยไม่เพิ่ม menu | เริ่มจับคู่ |
| UX-P02 | Setup | แสดง 4/6 จาก preference และ timer OFF/60/90/120 | เริ่ม |
| UX-P03 | Regular pair board | Tap English↔Thai ด้วย two-column layout | เลือก tile |
| UX-P04 | Focused accessible board | Source หนึ่งคำ + target list สำหรับ narrow/200%/assistive flow | เลือกความหมาย |
| UX-P05 | Wrong/repair state | Feedback, audio/hint และบอก delayed return | ทำต่อ |
| UX-P06 | Timeout decision sheet | ให้ผู้ใช้ควบคุมหลังหมดเวลา | ทำต่อโดยไม่จับเวลา |
| UX-P07 | Result | แยก stars, independence, assistance, timer และ next Review | กลับจุดเดิม/ไปต่อ |
| UX-P08 | History/replay state | latest/best และ Practice Replay ที่ไม่ให้ผลซ้ำ | ฝึกชุดนี้ซ้ำ |
| UX-P09 | Insufficient/replay unavailable | ป้องกัน filler/stale content | ฝึกกิจกรรมอื่น/สร้างชุดใหม่ |

### 17.3 Setup specification

Order:

1. activity title “จับคู่คำ–ความหมาย”;
2. bounded source reason เช่น “6 คำที่ถึงเวลาทบทวน”;
3. pair density ที่ resolve แล้ว—4 หรือ 6; guardian override แสดงเป็นข้อมูล ไม่ใช่ disabled punishment;
4. timer segmented control โดย “ไม่จับเวลา” selected ทุก session;
5. เมื่อเปิด timer แสดง 60/90/120 โดย suggestion 60 สำหรับ compact4, 90 สำหรับ standard6, 120 สำหรับ accessibility preference แต่ผู้ใช้เปลี่ยนได้;
6. filled CTA “เริ่มจับคู่”; secondary “ไว้ภายหลัง” คืน source surface.

ห้ามแสดงดาว, leaderboard, reward multiplier หรือข้อความว่าจับเวลาเรียนได้ดีกว่า

### 17.4 Regular board layout

```text
┌────────────────────────────────────────┐
│ ← จับคู่คำ–ความหมาย       2/6   01:12 │
│ แตะคำอังกฤษและความหมายไทยที่ตรงกัน     │
├──────────────────┬─────────────────────┤
│ apple            │ บ้าน                │
│ house  [selected]│ แอปเปิล             │
│ water            │ น้ำ                 │
│ cat              │ แมว                 │
│ mountain         │ ภูเขา               │
│ book             │ หนังสือ             │
├──────────────────┴─────────────────────┤
│ 🔊 ฟังคำที่เลือก          คำใบ้          │
└────────────────────────────────────────┘
```

- Grid ใช้สองคอลัมน์เท่ากันเมื่อ effective width รองรับ; ไม่ branch จาก device name
- source/target order แยกและ deterministic; visual position ไม่เป็น correctness authority
- tile text wrap สองบรรทัดเป็นอย่างน้อย; essential label ห้าม ellipsis
- matched stateใช้ ✓ + “จับคู่แล้ว” + border/fill semantic; placeholder คง geometry ระหว่าง focus transition
- same-side selection เปลี่ยน selected tile ไม่แสดงผิด
- timer chipหายเมื่อ OFF; warningไม่กระพริบและไม่ใช้สีแดงอย่างเดียว

### 17.5 Adaptive/focused layout

เมื่อ width <360, text 200% ไม่ fit, TalkBack/Switch profile ต้องการ linear flow หรือ localization ทำ tile ต่ำกว่าค่าขั้นต่ำ ให้ใช้:

```text
คำที่เลือก
┌──────────────────────────────────────┐
│ house                         🔊     │
└──────────────────────────────────────┘
เลือกความหมาย
┌──────────────────────────────────────┐
│ บ้าน                                 │
├──────────────────────────────────────┤
│ หนังสือ                              │
├──────────────────────────────────────┤
│ น้ำ                                  │
└──────────────────────────────────────┘
```

Focused layout ต้อง dispatch command เดียวกับ two-column, ไม่มีคะแนน/เวลา/ดาวแตกต่าง และให้ย้อนกลับเลือก source ได้โดยไม่สร้าง answer

### 17.6 Component tokens and states

| Token | Value | Rule |
|---|---:|---|
| `pair.tile.minHeight` | 56 | regular minimum |
| `pair.tile.compactYoungMinHeight` | 64 | compact/young profile |
| `pair.tile.radius` | 16 | align M3Theme cards |
| `pair.tile.gap` | 12 | vertical gap |
| `pair.columnGap` | 12 phone / 16 wide | board separation |
| `pair.contentMax` | 720–840 | tablet/wide center column |
| `pair.border.default/state` | 1 / 2 | non-color state distinction |
| `pair.motion.select/resolve/requeue` | 100/160/200ms | all zero under reduced motion |

`PairTile` states: idle, selected, resolving, matched, incorrect, cooldown, requeued, guided, disabled, persistenceError `Timer` states: off, running, warning, timeoutDecision, extended, continuedUntimed `Result` states: complete, sideEffectPending, practiceReplay, incomplete

### 17.7 Wrong, support and repair copy

| Situation | Thai copy | Behavior |
|---|---|---|
| first mismatch | “ยังไม่ใช่ ลองเก็บคำนี้ไว้แล้วกลับมาอีกครั้งนะ” | unselect; no shake/loss |
| repair queued | “คำนี้จะกลับมาหลังฝึกคำอื่นอีกสักครู่” | progress unchanged |
| semantic help | “ลองดูความหมายและฟังเสียง แล้วจับคู่อีกครั้ง” | subsequent response guided |
| late tail | “ช่วยกันจับคู่คำนี้ให้ครบ แล้วระบบจะเก็บไว้ทบทวนอีกครั้ง” | guided completion + Review deferral |
| technical failure | “ยังบันทึกไม่ได้ คำตอบของคุณยังอยู่” | freeze selection; retry exact operation |

Pronunciation button ต้อง user-initiated Accessibility/TTS ที่อ่าน visible prompt ไม่แสดงเป็น “ใช้คำใบ้” และไม่ลดดาว Answer-revealing hint ต้องติด semantic support stateชัดเจน

### 17.8 Timeout decision

```text
┌──────────────────────────────────────┐
│ ยังไม่ทันเป้าหมาย แต่ทำต่อได้        │
│ จับคู่สำเร็จแล้ว 4 จาก 6 คู่          │
│                                      │
│ [ ทำต่อโดยไม่จับเวลา ]               │
│ [ เพิ่ม 30 วินาที ]  ใช้ได้ 1 ครั้ง   │
│ เริ่มรอบใหม่ด้วยคำชุดเดิม             │
└──────────────────────────────────────┘
```

Sheet ไม่มี auto-dismiss/secondary countdown Focus เข้า heading แล้ว primary action; ปิด sheetไม่ได้ทำให้ evidence หาย Restart copy อธิบายว่า “สลับตำแหน่งใหม่ แต่ประวัติรอบนี้ยังอยู่” เมื่อ extension ใช้แล้วปุ่มยังคง disabled พร้อมเหตุผลหลัง recovery

### 17.9 Result and stars

```text
┌──────────────────────────────────────┐
│ จับคู่ครบแล้ว                        │
│              ★ ★ ☆                   │
│ ทำได้ด้วยตนเอง 5/6 · มีตัวช่วย 1     │
│ ทันเป้าหมาย 90 วินาที                │
│ คำที่ระบบเก็บไว้ทบทวน 1 คำ           │
│                                      │
│ [ ทำภารกิจต่อ ]                      │
│ ไปหน้าทบทวน     ฝึกชุดนี้ซ้ำ          │
│                 ไม่เพิ่มรางวัล/SRS    │
└──────────────────────────────────────┘
```

Stars แสดงหลัง complete เท่านั้นและมี accessible text “ได้สองดาวจากสามดาว—เป็นผลการทำรอบนี้ ไม่ใช่ระดับความเก่ง” Timely copy แยกจากดาว Untimed ใช้ “จับคู่ครบแล้ว · ใช้เวลาเรียนจริง …” Practice Replay result ติด badge และไม่ overwrite mission best

### 17.10 Semantics and focus contract

- Tile label: language + visible value + state เช่น “คำอังกฤษ house, เลือกแล้ว”
- Timer ไม่ announce ทุกวินาที; polite threshold ที่ 30/10 วินาทีและผู้ใช้ focus เพื่ออ่านค่าปัจจุบันได้
- Incorrect/correct/timeout/persistence เป็น status message ไม่ย้าย focusฉับพลัน
- หลัง match announce แล้ว focus ไป first actionable unmatched tile; matched semantics ถูก exclude
- Sheet close/continue คืน focus ไป board instruction/selected contextตาม transition
- Switch Access ทำทุก actionได้ด้วย single activation ไม่มี drag-only/nested duplicate node
- Audio unavailable มี text/IPA fallback; no-audio ไม่ block completion

### 17.11 Prototype validation matrix

| Prototype | Persistence | What it proves | Gate |
|---|---|---|---|
| Pair A — Interaction | fixture only | setup, two layouts, repair copy, timeout/result comprehension | PM-A |
| Pair B — Contract | plan/engine/checkpoint reader; writer hidden/off | exact 4/6, deterministic state, source/legacy compatibility | PM-B |
| Pair C — Integrated | hidden writer | evidence/restart/replay/history and Standard/Adventure parity | PM-C/G4P |

Formative tasks:

1. เริ่มแบบไม่จับเวลาโดยไม่ต้องมีคนบอก;
2. อธิบายว่าคำมาจากอะไรและจำนวนคู่ถูกกำหนดอย่างไร;
3. จงใจจับผิดแล้วสังเกตว่าความคืบหน้าไม่ลด;
4. ใช้เสียงปกติและ answer-revealing hint แล้วอธิบายความต่าง;
5. ทำ timeout ทั้ง Continue, +30 และ Restart;
6. อธิบายว่าดาวไม่ใช่ mastery/reward;
7. ใช้ Practice Replay และอธิบายว่าไม่เพิ่มรางวัล/เลื่อน SRS;
8. เล่น flow เดียวกันใน Standard/Adventure และตรวจว่ากติกาไม่เปลี่ยน

### 17.12 Pair UX acceptance criteria

| ID | Criterion |
|---|---|
| UX-AC-17 | 5/5 formative users start untimed and identify how to select a pair without moderator instruction |
| UX-AC-18 | 5/5 understand timer is optional and all three timeout choices; +30 once remains clear after resume |
| UX-AC-19 | 5/5 understand wrong does not remove progress/reward and can identify delayed/guided Review outcome |
| UX-AC-20 | At least 4/5 distinguish stars from mastery/reward and timed praise from stars |
| UX-AC-21 | compact4/standard6, EN→TH/TH→EN and Thai long-label fixtures complete without ambiguity or clipping |
| UX-AC-22 | Two-column and focused layouts dispatch semantically equivalent answers and receive equal outcomes |
| UX-AC-23 | Pair setup/board/wrong/timeout/result/history pass TalkBack, Switch Access, keyboard, 200% text, reduced motion and no-audio |
| UX-AC-24 | Practice Replay copy is understood by 5/5 and normal/replay results are visually and semantically distinguishable |
| UX-AC-25 | Standard/Adventure Pair action hierarchy, timer, support and result meanings remain equivalent |
| UX-AC-26 | No hearts/lives, pay-to-continue, public ranking, star currency, speed reward or shame copy appears |
