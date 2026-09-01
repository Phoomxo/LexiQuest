# Thai-First Navigation Glossary Design

Date: 2026-09-01
Status: approved design-spec; no implementation is included in this package.

## Decision

LexiQuest navigation will be Thai-first for learners who cannot read English. The implementation will use one immutable, presentation-only navigation glossary keyed by stable internal navigation IDs. A screen consumes glossary entries for display text, semantics, tooltip text, and icon selection; it does not translate or reinterpret routes, feature IDs, database values, research protocol values, or learner content.

The selected approach is a single typed glossary. Two alternatives were considered and rejected:

- translating literals independently in each screen would keep current drift and make semantics/icon verification incomplete;
- introducing full application localization/ARB would broaden this bounded navigation package into a product-wide localization program.

This is a Thai navigation consistency package, not a runtime feature, cohort mechanism, or localization framework.

## Scope

The glossary covers these presentation surfaces and only their navigation/menu copy:

| Surface | Current production owner | Covered destinations/actions |
| --- | --- | --- |
| Drawer | `MainNavigationScreen` | vocabulary, shop, object scanner, shadowing practice, historical duel, AI tutor, AI connection settings, export, quests, settings |
| Bottom `NavigationBar` | `MainNavigationScreen` | vocabulary, learn, Today Hub, Study Planning Hub, mastery, weakness, achievements, profile |
| Choose Mode | `ChooseModeScreen` | all current selectable lesson-mode tiles and their static descriptions/unavailable navigation messages |
| Settings | `SettingScreen` | display, theme choices, motion, account, offline content, research consent, cloud status, password, logout, local data erase |
| Profile | `ProfileSettingsScreen` | profile axes and navigation-adjacent account/status labels |
| Today Hub | `TodayHubScreen` plus `MainNavigationScreen` actions | resume, recommendation, assigned assessment, review center, learning history |
| Study Planning Hub | `StudyPlanningHubScreen` | learning packs, learning goals, learning preferences |
| Hub children | existing routed screens/actions | Review Center, Learning History, Learning Pack Catalog, Learning Goals, Learning Preferences, and a research assessment only when its existing gate exposes it |

The scope does not translate arbitrary lesson body content, cards that render learner data, persistence values, or external-provider messages.

## Glossary authority and model

### Stable identity

Each entry is keyed by an existing stable presentation identifier, not its translated label. Existing `productionEntryId`, drawer keys, `AppPage.name`, lesson-mode identity, `Feature`, route name, database value, protocol version, and sync identifier remain unchanged.

Examples of stable glossary IDs are:

| ID family | Examples |
| --- | --- |
| Main destinations | `home/vocabulary`, `home/learn`, `home/today`, `home/study-planning`, `home/mastery`, `home/weakness`, `home/achievements`, `home/profile` |
| Drawer destinations | `drawer/rewards/shop`, `drawer/practice/object-scanner`, `drawer/practice/shadowing`, `drawer/learning/ghost-duel`, `drawer/ai-tutor/chat`, `drawer/ai-tutor/settings`, `drawer/export/center`, `drawer/rewards/quests`, `drawer/settings` |
| Learning modes | existing `home/learn/...` keys, including `associative-reading`, `quiz`, `typed-recall`, `matching`, `cloze`, `definition`, `srs`, `reading/cefr`, `dictation`, `sentence-scramble`, `word-scramble`, `speaking`, and `shadowing` |
| Hub actions | `today-hub-resume-action`, `today-hub-start-recommendation`, `today-hub-assessment-action`, `today-hub-open-review`, `today-hub-open-history`, `study-planning/open-catalog`, `study-planning/open-goals`, `study-planning/open-learning-preferences` |
| Settings/profile actions | existing `settings/offline-content`, theme/reduced-motion keys, `erase-local-data`, and named profile axes |

The implementation must introduce a final immutable entry type equivalent to:

```dart
final class NavigationGlossaryEntry {
  const NavigationGlossaryEntry({
    required this.id,
    required this.fullThaiLabel,
    required this.shortThaiLabel,
    required this.semanticsLabel,
    required this.tooltip,
    required this.icon,
    this.selectedIcon,
  });
  // immutable fields only
}
```

`fullThaiLabel` is used in Drawer/ListTile/AppBar/action contexts. `shortThaiLabel` is used only where compact navigation needs it, such as `NavigationDestination`. `semanticsLabel` and `tooltip` are explicit Thai accessibility strings rather than generated from an icon or English fallback. `selectedIcon` is required only for destinations that have selected/unselected state.

The glossary is a compile-time immutable map/list with an exact-set validation test. `require(id)` must have no English fallback. A missing registered entry is a contract/widget-test failure and is fail-closed in development/test; route selection must never quietly substitute a different destination or mutate feature state.

### Boundary rules

- The glossary is presentation data only. It does not own navigation, feature visibility, session/evidence handling, progress, research assignment, or persistence.
- Existing feature gates decide whether an item is visible. If hidden, the glossary does not make it visible.
- Existing callbacks and `AppPage.name` values are reused verbatim; a translated label is never used as a route key.
- A dynamic destination may interpolate canonical learner data after a Thai template, but dynamic content is not passed through a translation table.
- No UI may use an icon as the sole meaning. Every interactive menu destination retains a visible Thai label and a Thai semantic name.

## Canonical Thai terminology

These terms are mandatory on all covered user-facing navigation surfaces:

| Concept | Canonical Thai-first rendering |
| --- | --- |
| AI tutor | ผู้ช่วยสอน AI |
| AI connection/key settings | ตั้งค่าการเชื่อมต่อ AI |
| explanation for private key | จัดการกุญแจส่วนตัวที่เก็บในเครื่อง; do not expose `BYOK` as the learner-facing name |
| quests | ภารกิจการเรียน |
| learning packs | ชุดเนื้อหาการเรียน |
| study planning | วางแผนการเรียน |
| SRS | ทบทวนแบบเว้นระยะ (SRS) |
| CEFR | ระดับภาษา CEFR |
| mastery | ความชำนาญ |
| active learning time | เวลาเรียนจริง |
| accuracy | ความแม่นยำ |
| weakness | จุดที่ควรฝึกเพิ่ม |
| streak | ความต่อเนื่องในการเรียน |

`AI`, `SRS`, and `CEFR` are the only acronyms allowed in user-facing menu labels, and each appears with enough Thai context to explain it. Brand/proper data such as `LexiQuest`, a learner email, a vocabulary spelling, a pack title, a provider name, or a canonical status value is retained as data rather than blindly translated.

## Destination glossary and icon policy

The following table is the implementation target. Icons use Material symbols already associated with each destination where possible. For selectable main destinations, outlined is the unselected state and filled is the selected state; actions and Drawer entries have a single icon because they do not have a selected state.

| Stable destination/action | Thai label | Icon rationale | Selected pair |
| --- | --- | --- | --- |
| `home/vocabulary` | คลังคำศัพท์ | `menu_book_outlined` signals a word collection | `menu_book` |
| `home/learn` | การเรียนรู้ | `school_outlined` signals guided learning | `school` |
| `home/today` | วันนี้ | `today_outlined` signals the current day | `today` |
| `home/study-planning` | วางแผนการเรียน | `event_note_outlined` signals a schedule/plan | `event_note` |
| `home/mastery` | ความชำนาญ | `analytics_outlined` signals an evidence summary | `analytics` |
| `home/weakness` | จุดที่ควรฝึกเพิ่ม | `healing_outlined` signals supportive practice, not failure | `healing` |
| `home/achievements` | รางวัล | `emoji_events_outlined` signals earned milestones | `emoji_events` |
| `home/profile` | โปรไฟล์ | `person_outlined` signals the learner profile | `person` |
| `drawer/rewards/shop` | ร้านค้า | `shopping_bag` signals local reward redemption | none |
| `drawer/practice/object-scanner` | สแกนวัตถุ | `document_scanner_outlined` signals the scanner surface | none |
| `drawer/practice/shadowing` | ฝึกพูดตามเสียง | `mic_none` signals voice repetition | none |
| `drawer/learning/ghost-duel` | ดวลกับสถิติเดิม | `sports_esports_outlined` signals a historical self-challenge, not social competition | none |
| `drawer/ai-tutor/chat` | ผู้ช่วยสอน AI | `chat_bubble_outline` signals the approved tutor surface | none |
| `drawer/ai-tutor/settings` | ตั้งค่าการเชื่อมต่อ AI | `key_outlined` signals private connection-key management | none |
| `drawer/export/center` | ส่งออกข้อมูล | `file_download_outlined` signals a user-selected local export | none |
| `drawer/rewards/quests` | ภารกิจการเรียน | `flag_outlined` signals a learning objective | none |
| `drawer/settings` | ตั้งค่า | `settings` signals application controls | none |
| associative reading | อ่านเชื่อมโยงความจำ | `auto_stories_outlined` signals story/memory cues | none |
| meaning quiz | แบบทดสอบจากคลังคำศัพท์ | `quiz_outlined` signals an answer activity | none |
| typed recall | นึกคำแล้วพิมพ์ | `keyboard_outlined` signals typed recall | none |
| matching | จับคู่คำศัพท์ | `compare_arrows_outlined` signals matching pairs | none |
| cloze | เติมคำในประโยค | `space_bar_outlined` signals filling a gap | none |
| definition quiz | เลือกคำจากคำอธิบาย | `menu_book_outlined` signals definition lookup | none |
| SRS review | ทบทวนแบบเว้นระยะ (SRS) | `event_repeat_outlined` signals scheduled recurrence | none |
| CEFR reading | อ่านตามระดับภาษา CEFR | `chrome_reader_mode_outlined` signals reading | none |
| dictation | ฟังแล้วพิมพ์ | `hearing_outlined` signals listening input | none |
| sentence scramble | เรียงประโยค | `format_list_numbered_outlined` signals ordered words | none |
| word scramble | เรียงตัวอักษร | `extension_outlined` signals letter assembly | none |
| speaking | ฝึกออกเสียง | `mic_outlined` signals speech practice | none |
| shadowing | ฝึกพูดตามเสียง | `record_voice_over_outlined` signals modeled repetition | none |
| Today resume | เรียนต่อ | `play_arrow` signals continuation | none |
| Today recommendation | เริ่มกิจกรรมที่แนะนำ | `auto_awesome_outlined` signals a recommendation, not a guarantee | none |
| Today assessment | เริ่มแบบประเมิน | `assignment_outlined` signals an assigned assessment | none |
| Today review center | เปิดศูนย์ทบทวน | `fact_check_outlined` signals review work | none |
| Today history | ดูประวัติการเรียน | `history` signals immutable learning history | none |
| Study Planning packs | เลือกชุดเนื้อหาการเรียน | `menu_book_outlined` signals content selection | none |
| Study Planning goals | เป้าหมายการเรียน | `flag_outlined` signals goals | none |
| Study Planning preferences | การตั้งค่าการเรียน | `tune_outlined` signals adjustable preferences | none |
| Settings offline content | เนื้อหาออฟไลน์ | `offline_pin_outlined` signals locally verified content | none |
| Settings research consent | ความยินยอมงานวิจัย | `fact_check_outlined` or `assignment_outlined` mirrors current consent state | none |
| Settings connection status | สถานะการเชื่อมต่อระบบออนไลน์ | `cloud_done_outlined` / `cloud_off_outlined` conveys availability with visible text | none |
| Settings account actions | เปลี่ยนรหัสผ่าน, ออกจากระบบ, ลบข้อมูลในเครื่องทั้งหมด | existing `password_outlined`, `logout`, `delete_forever_outlined` communicate the action and remain text-labelled | none |

Settings and Profile presentation must also use the canonical terms: `การแสดงผล`, `ลดการเคลื่อนไหว`, `ความชำนาญ`, `ทบทวนแบบเว้นระยะ (SRS)`, `เวลาเรียนจริง`, `ความแม่นยำ`, `จุดที่ควรฝึกเพิ่ม`, and `ความต่อเนื่องในการเรียน`. The glossary does not translate a learner email, vocabulary word, meaning, source ID, runtime provider value, or status payload.

## Error, fallback, and accessibility behavior

- A registered menu is never rendered with English fallback text. A missing glossary ID is a failing contract/widget test, not a fallback to a hard-coded English literal.
- A route that is unavailable because its existing feature/dependency gate is off remains unavailable exactly as today. The glossary may supply Thai unavailable copy, but it may not enable, assign, or redirect the feature.
- Dynamic errors are shown through a Thai wrapper only when the message is product-owned. External or canonical error payloads remain data and are not falsely translated.
- Semantics labels and tooltips are Thai and name the action/destination. Visible labels remain present even where a tooltip is available.
- High-contrast, reduced-motion, keyboard/switch focus order, and M3 icon contrast continue to be supplied by the existing accessibility/theme authorities. The glossary does not add animation, preference persistence, or a parallel accessibility state.

## Testing design

Testing follows TDD in a single bounded UI package. RED tests first add the exact contract; GREEN centralizes only the glossary consumption needed to satisfy them.

### Contract and widget tests

1. Add an exact glossary contract test that proves every registered target ID has non-empty Thai full/short/semantics/tooltip fields, a valid icon, and a selected icon where the destination is selectable.
2. Add exact widget assertions on Drawer, `NavigationBar`, Choose Mode, Settings, Profile, Today Hub, Study Planning Hub, and hub-child entry points:
   - expected Thai labels are visible;
   - the corresponding Material icon widget and selected/unselected pair are present where applicable;
   - Thai semantics/tooltip text describes the same destination/action;
   - existing stable keys, `productionEntryId`, `AppPage.name`, and feature-gate behavior remain unchanged.
3. Add a negative missing-entry contract/widget test. It must fail before a menu can silently render a fallback label.
4. Add a narrowly scoped regression for unexplained English menu strings. It inspects only user-facing static menu labels/semantics produced by the target navigation surfaces, permits `AI`, `SRS`, and `CEFR` only in their canonical Thai-context entries, and excludes dynamic learner/brand/proper data. It is not a repository-wide English-text scanner.
5. Keep existing navigation/key tests as route-stability regressions. Tests must not assert translated labels as route IDs.

### Bounded verification sequence

After a changed fingerprint, run only the affected groups:

```powershell
flutter test --no-pub test/screens/main_navigation_screen_test.dart test/screens/production_shell_navigation_test.dart --reporter compact
flutter test --no-pub test/screens/choose_mode_screen_test.dart test/screens/setting_screen_test.dart test/screens/profile_settings_screen_test.dart --reporter compact
flutter test --no-pub test/screens/today_hub_screen_test.dart test/screens/study_planning_hub_screen_test.dart --reporter compact
flutter test --no-pub test/scenarios/production_feature_navigation_test.dart --reporter compact
```

Then run the targeted formatter and analyzer only over changed navigation/glossary files, followed by `git diff --check`. Run the bounded physical Android smoke only after focused gates pass. This package does not trigger a release build, full backend suite, push, or merge.

## File-impact proposal

The proposed implementation is intentionally small and may be refined only after RED evidence:

| Change type | Candidate paths |
| --- | --- |
| New presentation authority | `lib/navigation/navigation_glossary.dart` and a focused glossary contract test |
| Main destination/Drawer consumer | `lib/screens/main_navigation_screen.dart`, `test/screens/main_navigation_screen_test.dart`, `test/screens/production_shell_navigation_test.dart` |
| Learning-mode consumer | `lib/screens/choose_mode_screen.dart`, `test/screens/choose_mode_screen_test.dart` |
| Settings/profile consumers | `lib/screens/setting_screen.dart`, `lib/screens/profile_settings_screen.dart`, their existing tests |
| Hub consumers | `lib/screens/today_hub_screen.dart`, `lib/screens/study_planning_hub_screen.dart`, their existing tests |
| Routed child labels only when reached from a covered hub | existing Review Center, Learning History, Learning Pack Catalog, Learning Goals, and Learning Preferences surfaces/tests |
| Regression/architecture coverage | a focused navigation-glossary contract/architecture test plus existing production navigation scenario |

No schema, generated artifact, runtime-feature registry, product-contract revision, backend rule, route factory, native Android/iOS, or data model change is proposed.

## Rollout and acceptance criteria

This is one bounded UI package. It is delivered through existing runtime visibility and dependency gates; no new feature flag is introduced. It is safe to roll back by removing glossary consumption from navigation surfaces, with no data cleanup because the glossary persists no state.

The package is acceptable only when all of the following hold:

- every scoped menu destination/action uses an exact immutable glossary entry;
- Thai labels, semantics, tooltips, and icon pairs match the table above;
- no registered menu renders unexplained English or an icon-only meaning;
- `AI`, `SRS`, and `CEFR` occur only with their Thai explanatory context;
- all stable route IDs, feature IDs, database/protocol values, existing keys, and runtime gate decisions are unchanged;
- missing glossary entries fail the focused contract/widget test;
- dynamic learner/brand/proper content is not mistranslated;
- existing accessibility behavior remains intact; and
- only the exact implementation/spec/test paths are staged, with physical Android smoke deferred until focused local gates are green.

## Non-goals

- full app localization, ARB generation, locale selection, or persisted language preferences;
- translating stored learner content, vocabulary definitions, pack titles, provider payloads, or remote/backend content;
- database, schema, sync, Firestore Rules, research protocol, feature-gate, cohort, or route semantics changes;
- iOS-specific work, native/plugin changes, or Android build changes;
- unrelated copy rewrites outside the covered navigation surfaces; and
- release, deployment, push, or merge.
