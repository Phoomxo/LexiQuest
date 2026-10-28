# Thai Navigation Glossary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver one immutable Thai-first presentation glossary for the existing Drawer, bottom navigation, Choose Mode, Settings, Profile, Today Hub, Study Planning Hub, and their scoped child entry points without changing route identity, feature delivery, or persisted data.

**Architecture:** Add a single compile-time `NavigationGlossary` keyed by the stable presentation IDs already used by `ValueKey`, `productionEntryId`, and `AppPage.name`. Existing screens remain the navigation and feature-gate authorities; they consume immutable glossary entries only for visible labels, semantic names, tooltips, and Material icons. Contract tests lock the exact glossary set, while widget and scenario tests prove Thai presentation and unchanged route/gate behavior.

**Tech Stack:** Dart 3, Flutter Material 3 (`IconData`, `Icons`, `NavigationBar`, `ListTile`, `Semantics`, `Tooltip`), `flutter_test`, existing `AppNavigator`/`AppPage`, existing `FeatureRegistry`/`ProductionFeatureGate`.

## Global Constraints

- Work sequentially with one writer. Complete each RED, GREEN, focused verification, diff review, staging check, and commit before beginning the next task.
- `home/learn` has the canonical full and compact label `การเรียนรู้`.
- Existing `productionEntryId`, Drawer keys, `ValueKey` strings, `AppPage.name`, `LessonMode`, `Feature`, database values, protocol versions, sync identifiers, callbacks, and feature visibility decisions remain byte-for-byte unchanged.
- The glossary is presentation-only. It must not own navigation, delivery, cohort assignment, session/evidence handling, progress, research state, persistence, or availability.
- A registered ID has no English fallback. `NavigationGlossary.require(String id)` throws `StateError` for an absent entry before a menu can substitute another destination.
- Visible interactive entries retain Thai text, an explicit Thai semantics label, an explicit Thai tooltip, and the canonical Material icon. Main selectable destinations retain outlined/filled icon pairs.
- The only allowed Latin acronyms in covered menu copy are `AI`, `SRS`, and `CEFR`, each inside its canonical Thai explanatory phrase.
- Dynamic learner data, email, vocabulary spelling, pack title, provider name, canonical status payload, and external error payload remain data and are not translated by the glossary.
- Existing high-contrast, reduced-motion, keyboard/switch traversal, and Material 3 contrast behavior remain under their current authorities.
- Do not create ARB files, a locale selector, preference persistence, a runtime flag, a database/schema migration, sync/rules changes, generated artifacts, native Android/iOS changes, or a route factory.
- Do not run a repository-wide English scanner. Negative tests inspect only the immutable glossary and static widgets rendered by the scoped navigation surfaces.
- Do not rerun an unchanged failing command on the same source fingerprint. Diagnose the first failure, change the relevant source or fixture, then run only the affected command once.
- Never edit or stage the six parked iOS paths or seven generated plugin registrants. Use explicit `git add -- <paths>` commands only.
- No release build, deployment, push, or merge is part of this package.

## File Structure

- Create `lib/navigation/navigation_glossary.dart`: final immutable entry model, exact const entry map, stable ID group constants, and fail-closed lookup.
- Create `test/navigation/navigation_glossary_test.dart`: exact-set, immutability-by-construction, field, icon-pair, acronym, and missing-ID contract tests.
- Modify `lib/screens/main_navigation_screen.dart`: Drawer and `NavigationBar` glossary consumer; navigation callbacks and IDs remain owned here.
- Modify `lib/screens/choose_mode_screen.dart`: current lesson-mode tile consumer; mode registry and `_openMode` remain unchanged.
- Modify `lib/screens/setting_screen.dart` and `lib/screens/profile_settings_screen.dart`: static settings/account-action and profile-axis glossary consumers.
- Modify `lib/screens/today_hub_screen.dart` and `lib/screens/study_planning_hub_screen.dart`: existing hub action glossary consumers.
- Modify `lib/screens/review_center_screen.dart`, `lib/screens/learning_history_screen.dart`, `lib/screens/learning_pack_catalog_screen.dart`, `lib/screens/learning_goals_screen.dart`, and `lib/screens/learning_preference_quiz_screen.dart`: scoped child AppBar labels only; dynamic content and form/domain copy remain outside this package.
- Modify the existing screen tests adjacent to each consumer.
- Create `test/architecture/thai_navigation_glossary_boundary_test.dart`: narrow static-menu/acronym boundary over registered glossary entries only.
- Modify `test/scenarios/production_feature_navigation_test.dart`: unchanged production IDs, destination types, and fail-closed feature delivery after Thai copy changes.

---

### Task 1: Immutable glossary and exact contract

**Files:**
- Create: `lib/navigation/navigation_glossary.dart`
- Create: `test/navigation/navigation_glossary_test.dart`

**Interfaces:**
- Consumes: Flutter `IconData` and `Icons` only.
- Produces: `final class NavigationGlossaryEntry`, `abstract final class NavigationGlossary`, `static const Map<String, NavigationGlossaryEntry> entries`, and `static NavigationGlossaryEntry require(String id)`.
- Produces stable group constants used by later tasks: `mainDestinationIds`, `drawerDestinationIds`, `learningModeIds`, `todayActionIds`, `studyPlanningActionIds`, `settingsActionIds`, `profileAxisIds`, and `hubChildRouteIds`, each a const `Set<String>`.

- [ ] **Step 1: Write the failing exact-contract test**

Create `test/navigation/navigation_glossary_test.dart` with an independently declared expected ID set. The test must not derive its expectation from production group constants.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';

void main() {
  const expectedIds = <String>{
    'home/vocabulary',
    'home/learn',
    'home/today',
    'home/study-planning',
    'home/mastery',
    'home/weakness',
    'home/achievements',
    'home/profile',
    'drawer/rewards/shop',
    'drawer/practice/object-scanner',
    'drawer/practice/shadowing',
    'drawer/learning/ghost-duel',
    'drawer/ai-tutor/chat',
    'drawer/ai-tutor/settings',
    'drawer/export/center',
    'drawer/rewards/quests',
    'drawer/settings',
    'home/learn/associative-reading',
    'home/learn/quiz',
    'home/learn/quiz/typed-recall',
    'home/learn/quiz/matching',
    'home/learn/quiz/cloze',
    'home/learn/quiz/definition',
    'home/learn/srs',
    'home/learn/reading/cefr',
    'home/learn/quiz/dictation',
    'home/learn/quiz/sentence-scramble',
    'home/learn/quiz/word-scramble',
    'home/learn/speech/speaking',
    'home/learn/speech/shadowing',
    'today-hub-resume-action',
    'today-hub-start-recommendation',
    'today-hub-assessment-action',
    'today-hub-open-review',
    'today-hub-open-history',
    'study-planning/open-catalog',
    'study-planning/open-goals',
    'study-planning/open-learning-preferences',
    'settings/display',
    'theme-system',
    'theme-light',
    'theme-dark',
    'reduced-motion-switch',
    'settings/account',
    'settings/offline-content',
    'settings/research-consent',
    'settings/cloud-status',
    'settings/change-password',
    'settings/logout',
    'erase-local-data',
    'profile/mastery',
    'profile/srs',
    'profile/effort',
    'profile/accuracy',
    'profile/weakness',
    'profile/engagement',
    'home/today/review',
    'home/today/history',
    'research/assessment',
    'study-planning/catalog',
    'study-planning/goals',
    'study-planning/learning-preferences',
  };

  test('Thai navigation glossary is the exact immutable registered set', () {
    expect(NavigationGlossary.entries.keys.toSet(), expectedIds);
    for (final entry in NavigationGlossary.entries.values) {
      expect(entry.id, isNotEmpty);
      expect(entry.fullThaiLabel.trim(), isNotEmpty, reason: entry.id);
      expect(entry.shortThaiLabel.trim(), isNotEmpty, reason: entry.id);
      expect(entry.semanticsLabel.trim(), isNotEmpty, reason: entry.id);
      expect(entry.tooltip.trim(), isNotEmpty, reason: entry.id);
      expect(entry.icon.codePoint, greaterThan(0), reason: entry.id);
    }
    expect(
      NavigationGlossary.mainDestinationIds.every(
        (id) => NavigationGlossary.require(id).selectedIcon != null,
      ),
      isTrue,
    );
    expect(NavigationGlossary.require('home/learn').fullThaiLabel, 'การเรียนรู้');
    expect(NavigationGlossary.require('home/learn').shortThaiLabel, 'การเรียนรู้');
  });

  test('missing registered identity fails closed without a label fallback', () {
    expect(
      () => NavigationGlossary.require('home/not-registered'),
      throwsA(isA<StateError>()),
    );
  });
}
```

- [ ] **Step 2: Run the contract RED once**

Run:

```powershell
flutter test --no-pub test/navigation/navigation_glossary_test.dart --reporter compact
```

Expected: compilation fails only because `navigation_glossary.dart`, `NavigationGlossaryEntry`, and `NavigationGlossary` do not exist.

- [ ] **Step 3: Implement the immutable model and lookup**

Create `lib/navigation/navigation_glossary.dart` with this exact public shape:

```dart
import 'package:flutter/material.dart';

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

  final String id;
  final String fullThaiLabel;
  final String shortThaiLabel;
  final String semanticsLabel;
  final String tooltip;
  final IconData icon;
  final IconData? selectedIcon;
}

abstract final class NavigationGlossary {
  static const Set<String> mainDestinationIds = <String>{
    'home/vocabulary',
    'home/learn',
    'home/today',
    'home/study-planning',
    'home/mastery',
    'home/weakness',
    'home/achievements',
    'home/profile',
  };

  static const Map<String, NavigationGlossaryEntry> entries =
      <String, NavigationGlossaryEntry>{
        'home/learn': NavigationGlossaryEntry(
          id: 'home/learn',
          fullThaiLabel: 'การเรียนรู้',
          shortThaiLabel: 'การเรียนรู้',
          semanticsLabel: 'เปิดการเรียนรู้',
          tooltip: 'เปิดกิจกรรมการเรียนรู้',
          icon: Icons.school_outlined,
          selectedIcon: Icons.school,
        ),
      };

  static NavigationGlossaryEntry require(String id) {
    final entry = entries[id];
    if (entry == null) {
      throw StateError('Missing navigation glossary entry: $id');
    }
    return entry;
  }
}
```

Expand the const map and const group sets to the complete exact set in Step 1. Use the following exact entry data; every semantics and tooltip string is stored explicitly rather than generated from the visible label.

| ID | Full / short Thai label | Semantics label | Tooltip | Icon / selected icon |
| --- | --- | --- | --- | --- |
| `home/vocabulary` | `คลังคำศัพท์` / `คลังคำศัพท์` | `เปิดคลังคำศัพท์` | `เปิดคลังคำศัพท์` | `menu_book_outlined` / `menu_book` |
| `home/learn` | `การเรียนรู้` / `การเรียนรู้` | `เปิดการเรียนรู้` | `เปิดกิจกรรมการเรียนรู้` | `school_outlined` / `school` |
| `home/today` | `วันนี้` / `วันนี้` | `เปิดกิจกรรมวันนี้` | `เปิดกิจกรรมวันนี้` | `today_outlined` / `today` |
| `home/study-planning` | `วางแผนการเรียน` / `วางแผน` | `เปิดวางแผนการเรียน` | `เปิดวางแผนการเรียน` | `event_note_outlined` / `event_note` |
| `home/mastery` | `ความชำนาญ` / `ความชำนาญ` | `เปิดภาพรวมความชำนาญ` | `เปิดภาพรวมความชำนาญ` | `analytics_outlined` / `analytics` |
| `home/weakness` | `จุดที่ควรฝึกเพิ่ม` / `ฝึกเพิ่ม` | `เปิดจุดที่ควรฝึกเพิ่ม` | `เปิดจุดที่ควรฝึกเพิ่ม` | `healing_outlined` / `healing` |
| `home/achievements` | `รางวัล` / `รางวัล` | `เปิดรางวัล` | `เปิดรางวัล` | `emoji_events_outlined` / `emoji_events` |
| `home/profile` | `โปรไฟล์` / `โปรไฟล์` | `เปิดโปรไฟล์` | `เปิดโปรไฟล์` | `person_outlined` / `person` |
| `drawer/rewards/shop` | `ร้านค้า` / `ร้านค้า` | `เปิดร้านค้า` | `เปิดร้านค้า` | `shopping_bag` / none |
| `drawer/practice/object-scanner` | `สแกนวัตถุ` / `สแกนวัตถุ` | `เปิดสแกนวัตถุ` | `เปิดสแกนวัตถุ` | `document_scanner_outlined` / none |
| `drawer/practice/shadowing` | `ฝึกพูดตามเสียง` / `ฝึกพูดตามเสียง` | `เปิดฝึกพูดตามเสียง` | `เปิดฝึกพูดตามเสียง` | `mic_none` / none |
| `drawer/learning/ghost-duel` | `ดวลกับสถิติเดิม` / `ดวลกับสถิติเดิม` | `เปิดดวลกับสถิติเดิม` | `เปิดกิจกรรมเปรียบเทียบกับสถิติเดิม` | `sports_esports_outlined` / none |
| `drawer/ai-tutor/chat` | `ผู้ช่วยสอน AI` / `ผู้ช่วยสอน AI` | `เปิดผู้ช่วยสอน AI` | `เปิดผู้ช่วยสอน AI` | `chat_bubble_outline` / none |
| `drawer/ai-tutor/settings` | `ตั้งค่าการเชื่อมต่อ AI` / `ตั้งค่า AI` | `เปิดตั้งค่าการเชื่อมต่อ AI` | `จัดการกุญแจส่วนตัวที่เก็บในเครื่อง` | `key_outlined` / none |
| `drawer/export/center` | `ส่งออกข้อมูล` / `ส่งออกข้อมูล` | `เปิดการส่งออกข้อมูล` | `เปิดการส่งออกข้อมูล` | `file_download_outlined` / none |
| `drawer/rewards/quests` | `ภารกิจการเรียน` / `ภารกิจ` | `เปิดภารกิจการเรียน` | `เปิดภารกิจการเรียน` | `flag_outlined` / none |
| `drawer/settings` | `ตั้งค่า` / `ตั้งค่า` | `เปิดการตั้งค่า` | `เปิดการตั้งค่า` | `settings` / none |

Learning-mode entries use their existing `home/learn/...` IDs and these exact values:

| ID suffix | Full / short label | Semantics label | Tooltip | Icon |
| --- | --- | --- | --- | --- |
| `associative-reading` | `อ่านเชื่อมโยงความจำ` / same | `เปิดอ่านเชื่อมโยงความจำ` | `สร้างเรื่องเชื่อมโยงคำศัพท์เพื่อช่วยจำ` | `auto_stories_outlined` |
| `quiz` | `แบบทดสอบจากคลังคำศัพท์` / `แบบทดสอบ` | `เปิดแบบทดสอบจากคลังคำศัพท์` | `ตอบความหมายจากคำศัพท์ที่บันทึกไว้` | `quiz_outlined` |
| `quiz/typed-recall` | `นึกคำแล้วพิมพ์` / same | `เปิดกิจกรรมนึกคำแล้วพิมพ์` | `นึกตัวสะกดจากความจำแล้วพิมพ์คำตอบ` | `keyboard_outlined` |
| `quiz/matching` | `จับคู่คำศัพท์` / same | `เปิดกิจกรรมจับคู่คำศัพท์` | `จับคู่คำศัพท์กับความหมาย` | `compare_arrows_outlined` |
| `quiz/cloze` | `เติมคำในประโยค` / same | `เปิดกิจกรรมเติมคำในประโยค` | `เลือกหรือพิมพ์คำลงในประโยคที่ตรวจทานแล้ว` | `space_bar_outlined` |
| `quiz/definition` | `เลือกคำจากคำอธิบาย` / same | `เปิดกิจกรรมเลือกคำจากคำอธิบาย` | `เลือกคำศัพท์จากคำอธิบายที่ตรวจทานแล้ว` | `menu_book_outlined` |
| `srs` | `ทบทวนแบบเว้นระยะ (SRS)` / `ทบทวน (SRS)` | `เปิดทบทวนแบบเว้นระยะ SRS` | `ทบทวนคำศัพท์ตามกำหนดจากประวัติคำตอบ` | `event_repeat_outlined` |
| `reading/cefr` | `อ่านตามระดับภาษา CEFR` / `อ่าน CEFR` | `เปิดอ่านตามระดับภาษา CEFR` | `อ่านบทความตามระดับภาษา CEFR` | `chrome_reader_mode_outlined` |
| `quiz/dictation` | `ฟังแล้วพิมพ์` / same | `เปิดกิจกรรมฟังแล้วพิมพ์` | `ฟังเสียงแล้วพิมพ์คำศัพท์` | `hearing_outlined` |
| `quiz/sentence-scramble` | `เรียงประโยค` / same | `เปิดกิจกรรมเรียงประโยค` | `เรียงคำให้เป็นประโยคที่ถูกต้อง` | `format_list_numbered_outlined` |
| `quiz/word-scramble` | `เรียงตัวอักษร` / same | `เปิดกิจกรรมเรียงตัวอักษร` | `เรียงตัวอักษรให้เป็นคำศัพท์` | `extension_outlined` |
| `speech/speaking` | `ฝึกออกเสียง` / same | `เปิดกิจกรรมฝึกออกเสียง` | `ฝึกออกเสียงด้วยการรู้จำเสียงบนอุปกรณ์` | `mic_outlined` |
| `speech/shadowing` | `ฝึกพูดตามเสียง` / same | `เปิดกิจกรรมฝึกพูดตามเสียง` | `ฟังตัวอย่างแล้วฝึกพูดตาม` | `record_voice_over_outlined` |

Use these remaining exact entries:

| ID | Full label | Semantics / tooltip | Icon |
| --- | --- | --- | --- |
| `today-hub-resume-action` | `เรียนต่อ` | `เรียนต่อจากกิจกรรมเดิม` / `เรียนต่อจากกิจกรรมเดิม` | `play_arrow` |
| `today-hub-start-recommendation` | `เริ่มกิจกรรมที่แนะนำ` | `เริ่มกิจกรรมที่แนะนำ` / `เริ่มกิจกรรมที่แนะนำสำหรับวันนี้` | `auto_awesome_outlined` |
| `today-hub-assessment-action` | `เริ่มแบบประเมิน` | `เริ่มแบบประเมินที่ได้รับมอบหมาย` / same | `assignment_outlined` |
| `today-hub-open-review` | `เปิดศูนย์ทบทวน` | `เปิดศูนย์ทบทวน` / same | `fact_check_outlined` |
| `today-hub-open-history` | `ดูประวัติการเรียน` | `เปิดประวัติการเรียน` / same | `history` |
| `study-planning/open-catalog` | `เลือกชุดเนื้อหาการเรียน` | `เปิดชุดเนื้อหาการเรียนที่ตรวจสอบแล้ว` / same | `menu_book_outlined` |
| `study-planning/open-goals` | `เป้าหมายการเรียน` | `เปิดเป้าหมายการเรียน` / same | `flag_outlined` |
| `study-planning/open-learning-preferences` | `การตั้งค่าการเรียน` | `เปิดการตั้งค่าการเรียน` / same | `tune_outlined` |
| `settings/display` | `การแสดงผล` | `การตั้งค่าการแสดงผล` / same | `display_settings_outlined` |
| `theme-system` | `ระบบ` | `ใช้รูปแบบตามระบบ` / same | `settings_suggest_outlined` |
| `theme-light` | `สว่าง` | `ใช้รูปแบบสว่าง` / same | `light_mode_outlined` |
| `theme-dark` | `มืด` | `ใช้รูปแบบมืด` / same | `dark_mode_outlined` |
| `reduced-motion-switch` | `ลดการเคลื่อนไหว` | `เปิดหรือปิดการลดการเคลื่อนไหว` / same | `motion_photos_off_outlined` |
| `settings/account` | `บัญชีผู้ใช้` | `ข้อมูลบัญชีผู้ใช้` / same | `person_outline` |
| `settings/offline-content` | `เนื้อหาออฟไลน์` | `เปิดการจัดการเนื้อหาออฟไลน์` / same | `offline_pin_outlined` |
| `settings/research-consent` | `ความยินยอมงานวิจัย` | `จัดการความยินยอมงานวิจัย` / same | `fact_check_outlined` |
| `settings/cloud-status` | `สถานะการเชื่อมต่อระบบออนไลน์` | `ตรวจสอบสถานะการเชื่อมต่อระบบออนไลน์` / same | `cloud_done_outlined` |
| `settings/change-password` | `เปลี่ยนรหัสผ่าน` | `เปิดการเปลี่ยนรหัสผ่าน` / same | `password_outlined` |
| `settings/logout` | `ออกจากระบบ` | `ออกจากระบบ` / same | `logout` |
| `erase-local-data` | `ลบข้อมูลในเครื่องทั้งหมด` | `ลบข้อมูลในเครื่องทั้งหมด` / `ลบคำศัพท์ ประวัติการเรียน ความยินยอม และกุญแจ AI ที่บันทึกในเครื่อง` | `delete_forever_outlined` |
| `profile/mastery` | `ความชำนาญ` | `ความชำนาญ` / same | `analytics_outlined` |
| `profile/srs` | `ทบทวนแบบเว้นระยะ (SRS)` | `สถานะการทบทวนแบบเว้นระยะ SRS` / same | `event_repeat_outlined` |
| `profile/effort` | `เวลาเรียนจริง` | `เวลาเรียนจริง` / same | `timer_outlined` |
| `profile/accuracy` | `ความแม่นยำ` | `ความแม่นยำ` / same | `check_circle_outline` |
| `profile/weakness` | `จุดที่ควรฝึกเพิ่ม` | `จุดที่ควรฝึกเพิ่ม` / same | `healing_outlined` |
| `profile/engagement` | `ความต่อเนื่องในการเรียน` | `ความต่อเนื่องในการเรียน` / same | `local_fire_department_outlined` |
| `home/today/review` | `ศูนย์ทบทวน` | `ศูนย์ทบทวน` / same | `fact_check_outlined` |
| `home/today/history` | `ประวัติการเรียน` | `ประวัติการเรียน` / same | `history` |
| `research/assessment` | `แบบประเมิน` | `แบบประเมินที่ได้รับมอบหมาย` / same | `assignment_outlined` |
| `study-planning/catalog` | `ชุดเนื้อหาการเรียน` | `ชุดเนื้อหาการเรียน` / same | `menu_book_outlined` |
| `study-planning/goals` | `เป้าหมายการเรียน` | `เป้าหมายการเรียน` / same | `flag_outlined` |
| `study-planning/learning-preferences` | `การตั้งค่าการเรียน` | `การตั้งค่าการเรียน` / same | `tune_outlined` |

For every row whose table says `same`, write the repeated Thai string explicitly in both `semanticsLabel` and `tooltip`; do not compute either field from `fullThaiLabel`.

- [ ] **Step 4: Run GREEN and format only Task 1 paths**

Run:

```powershell
dart format lib/navigation/navigation_glossary.dart test/navigation/navigation_glossary_test.dart
flutter test --no-pub test/navigation/navigation_glossary_test.dart --reporter compact
git diff --check -- lib/navigation/navigation_glossary.dart test/navigation/navigation_glossary_test.dart
```

Expected: formatter exits 0, the exact contract tests pass, and diff check exits 0.

- [ ] **Step 5: Stage exactly Task 1 and commit**

```powershell
git add -- lib/navigation/navigation_glossary.dart test/navigation/navigation_glossary_test.dart
git diff --cached --name-only
git diff --cached --check
git commit -m "feat: add immutable Thai navigation glossary"
```

Expected staged paths: exactly the two Task 1 paths. Abort before commit if any parked iOS or generated registrant appears.

---

### Task 2: Main Navigation Drawer and bottom bar

**Files:**
- Modify: `lib/screens/main_navigation_screen.dart:129-229`
- Modify: `lib/screens/main_navigation_screen.dart:773-956`
- Modify: `lib/screens/main_navigation_screen.dart:1016-1044`
- Modify: `test/screens/main_navigation_screen_test.dart`
- Modify: `test/screens/production_shell_navigation_test.dart`

**Interfaces:**
- Consumes: `NavigationGlossary.require(String id) -> NavigationGlossaryEntry` from Task 1.
- Preserves: `_NavigationEntry.id`, `_NavigationEntry.productionEntryId`, `_NavigationEntry.screen`, `visibilityFeatures`, feature gates, `_pushDestination`, and `_pushFeatureDestination`.
- Produces: `_NavigationEntry.glossary` as the only source of main-destination label/icon presentation.

- [ ] **Step 1: Write focused Drawer and NavigationBar RED tests**

In `main_navigation_screen_test.dart`, update the existing `field composition exposes completed field destinations` expectation and add an exact glossary presentation test using `_mainNavigationApp`:

```dart
testWidgets('Thai glossary renders exact main and drawer destinations', (
  tester,
) async {
  await tester.pumpWidget(
    _mainNavigationApp(const BuildFeatureRegistry.fieldDefaults()),
  );
  await tester.pumpAndSettle();

  final learn = tester.widget<NavigationDestination>(
    find.byKey(const ValueKey<String>('home/learn')),
  );
  expect(learn.label, 'การเรียนรู้');
  expect((learn.icon as Icon).icon, Icons.school_outlined);
  expect((learn.selectedIcon! as Icon).icon, Icons.school);

  await tester.tap(
    find.byKey(const ValueKey<String>('legacy-drawer-button')),
  );
  await tester.pumpAndSettle();
  final drawer = find.byType(Drawer);
  expect(
    find.descendant(of: drawer, matching: find.text('ผู้ช่วยสอน AI')),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: drawer,
      matching: find.text('ตั้งค่าการเชื่อมต่อ AI'),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(of: drawer, matching: find.text('ภารกิจการเรียน')),
    findsOneWidget,
  );
  expect(find.descendant(of: drawer, matching: find.text('AI Tutor')), findsNothing);
  expect(
    find.descendant(of: drawer, matching: find.text('AI Provider BYOK')),
    findsNothing,
  );
  expect(find.descendant(of: drawer, matching: find.text('Quests')), findsNothing);
});
```

In `production_shell_navigation_test.dart`, change only presentation expectations while retaining the current stable destination loop. Add an assertion that tapping `home/learn` still selects `production-feature-view-learning`, and that tapping `drawer/settings` still reaches `SettingScreen` through route name `settings` using the existing shell harness.

- [ ] **Step 2: Run the main-navigation RED once**

```powershell
flutter test --no-pub test/screens/main_navigation_screen_test.dart test/screens/production_shell_navigation_test.dart --reporter compact
```

Expected: route/key tests remain green; new presentation assertions fail on `เรียนรู้`, `AI Tutor`, `AI Provider BYOK`, `Quests`, `สถิติ`, and `จุดอ่อน`.

- [ ] **Step 3: Replace `_NavigationEntry` presentation fields with one glossary entry**

Use this constructor shape without changing identity or gate fields:

```dart
final class _NavigationEntry {
  const _NavigationEntry({
    required this.id,
    required this.productionEntryId,
    required this.screen,
    required this.glossary,
    this.visibilityFeatures = const <Feature>[],
    this.alwaysVisible = false,
    this.showUnavailableWhenHidden = false,
    this.requiresComposedDependency = false,
  });

  final String id;
  final String productionEntryId;
  final Widget screen;
  final NavigationGlossaryEntry glossary;
}
```

Construct each entry with its unchanged `productionEntryId` and `glossary: NavigationGlossary.require('<same productionEntryId>')`. Render the bar with:

```dart
NavigationDestination(
  key: ValueKey<String>(entry.productionEntryId),
  icon: Icon(entry.glossary.icon),
  selectedIcon: Icon(entry.glossary.selectedIcon!),
  label: entry.glossary.shortThaiLabel,
  tooltip: entry.glossary.tooltip,
)
```

For each Drawer `ListTile`, resolve the exact existing key, use `entry.icon`, `entry.fullThaiLabel`, and wrap the tile with `Tooltip(message: entry.tooltip)`. Add `key: const ValueKey<String>('drawer/ai-tutor/settings')` to the existing AI settings tile because that stable ID is already specified by the approved contract; do not change its `_pushFeatureDestination('ai-tutor/settings', ...)` route name. Reuse the `home/vocabulary` entry for the vocabulary Drawer item. Use the `home/profile` entry for the fallback `TextButton.icon`. The Drawer opener may keep its existing key and Thai tooltip because it is a menu control, not a destination entry.

- [ ] **Step 4: Run GREEN, format, and inspect stable IDs**

```powershell
dart format lib/screens/main_navigation_screen.dart test/screens/main_navigation_screen_test.dart test/screens/production_shell_navigation_test.dart
flutter test --no-pub test/screens/main_navigation_screen_test.dart test/screens/production_shell_navigation_test.dart --reporter compact
git diff --check -- lib/screens/main_navigation_screen.dart test/screens/main_navigation_screen_test.dart test/screens/production_shell_navigation_test.dart
```

Expected: both files pass; destination keys and route assertions are unchanged; Thai labels and icon pairs match the glossary.

- [ ] **Step 5: Stage exactly Task 2 and commit**

```powershell
git add -- lib/screens/main_navigation_screen.dart test/screens/main_navigation_screen_test.dart test/screens/production_shell_navigation_test.dart
git diff --cached --name-only
git diff --cached --check
git commit -m "feat: apply Thai glossary to primary navigation"
```

---

### Task 3: Choose Mode labels, icons, semantics, and unavailable copy

**Files:**
- Modify: `lib/screens/choose_mode_screen.dart:61-335`
- Modify: `lib/screens/choose_mode_screen.dart:852-887`
- Modify: `test/screens/choose_mode_screen_test.dart`

**Interfaces:**
- Consumes: each current `home/learn/...` `NavigationGlossaryEntry`.
- Preserves: every `ValueKey`, `LessonMode`, registry resolution, `_openMode` callback, `AppPage.name`, and existing fail-closed gate.
- Produces: `_LearningTile({required NavigationGlossaryEntry glossary, required VoidCallback onTap})` with one visible Thai label, Thai description/tooltip, canonical icon, and one semantic action.

- [ ] **Step 1: Add the exact 13-mode presentation RED**

Use the existing `buildLessonModeRegistry()` and `_scrollToModeEntry` helpers:

```dart
testWidgets('Thai glossary covers every registered Choose Mode tile', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChooseModeScreen(
        featureRegistry: const BuildFeatureRegistry.allEnabled(),
        lessonModes: buildLessonModeRegistry(),
      ),
    ),
  );

  const cases = <(String, String, IconData)>[
    ('home/learn/associative-reading', 'อ่านเชื่อมโยงความจำ', Icons.auto_stories_outlined),
    ('home/learn/quiz', 'แบบทดสอบจากคลังคำศัพท์', Icons.quiz_outlined),
    ('home/learn/quiz/typed-recall', 'นึกคำแล้วพิมพ์', Icons.keyboard_outlined),
    ('home/learn/quiz/matching', 'จับคู่คำศัพท์', Icons.compare_arrows_outlined),
    ('home/learn/quiz/cloze', 'เติมคำในประโยค', Icons.space_bar_outlined),
    ('home/learn/quiz/definition', 'เลือกคำจากคำอธิบาย', Icons.menu_book_outlined),
    ('home/learn/srs', 'ทบทวนแบบเว้นระยะ (SRS)', Icons.event_repeat_outlined),
    ('home/learn/reading/cefr', 'อ่านตามระดับภาษา CEFR', Icons.chrome_reader_mode_outlined),
    ('home/learn/quiz/dictation', 'ฟังแล้วพิมพ์', Icons.hearing_outlined),
    ('home/learn/quiz/sentence-scramble', 'เรียงประโยค', Icons.format_list_numbered_outlined),
    ('home/learn/quiz/word-scramble', 'เรียงตัวอักษร', Icons.extension_outlined),
    ('home/learn/speech/speaking', 'ฝึกออกเสียง', Icons.mic_outlined),
    ('home/learn/speech/shadowing', 'ฝึกพูดตามเสียง', Icons.record_voice_over_outlined),
  ];
  for (final (id, label, icon) in cases) {
    await _scrollToModeEntry(tester, id);
    final tile = find.byKey(ValueKey<String>(id));
    expect(find.descendant(of: tile, matching: find.text(label)), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.byIcon(icon)), findsOneWidget);
  }
});
```

Retain the existing stable-route table at `choose_mode_screen_test.dart:644-711`; do not change any route name. Add one semantics test with `tester.ensureSemantics()` and `addTearDown(handle.dispose)` that reads the tile's Thai semantic label and taps the same tile key.

- [ ] **Step 2: Run Choose Mode RED once**

```powershell
flutter test --no-pub test/screens/choose_mode_screen_test.dart --plain-name "Thai glossary covers every registered Choose Mode tile" --reporter compact
```

Expected: the test reaches real tiles and fails only on current English titles or the old SRS label.

- [ ] **Step 3: Make `_LearningTile` consume one immutable entry**

Replace `icon`, `title`, and `subtitle` parameters with `glossary`. Avoid duplicate ListTile semantics by excluding the child semantics under one explicit button node:

```dart
class _LearningTile extends StatelessWidget {
  const _LearningTile({
    super.key,
    required this.glossary,
    required this.onTap,
  });

  final NavigationGlossaryEntry glossary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Tooltip(
        message: glossary.tooltip,
        child: Semantics(
          button: true,
          label: glossary.semanticsLabel,
          onTap: onTap,
          excludeSemantics: true,
          child: ListTile(
            minVerticalPadding: 16,
            leading: Icon(glossary.icon),
            title: Text(glossary.fullThaiLabel),
            subtitle: Text(glossary.tooltip),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
```

At each current tile, keep its key and callback exactly, and replace presentation parameters with `glossary: NavigationGlossary.require('<tile key>')`. Translate only the product-owned static unavailable SnackBar copy on this menu to `โหมดการเรียนนี้ยังไม่พร้อมใช้งาน`; do not translate session content, learner data, reset reasons, or external failures.

- [ ] **Step 4: Run focused GREEN and the unchanged route-stability test**

```powershell
dart format lib/screens/choose_mode_screen.dart test/screens/choose_mode_screen_test.dart
flutter test --no-pub test/screens/choose_mode_screen_test.dart --plain-name "Thai glossary" --reporter compact
flutter test --no-pub test/screens/choose_mode_screen_test.dart --plain-name "every production mode reaches one controller-backed shell on its stable route" --reporter compact
git diff --check -- lib/screens/choose_mode_screen.dart test/screens/choose_mode_screen_test.dart
```

Expected: Thai presentation and semantic tests pass; all 13 current route names remain exact.

- [ ] **Step 5: Stage exactly Task 3 and commit**

```powershell
git add -- lib/screens/choose_mode_screen.dart test/screens/choose_mode_screen_test.dart
git diff --cached --name-only
git diff --cached --check
git commit -m "feat: localize Choose Mode navigation in Thai"
```

---

### Task 4: Settings and Profile navigation presentation

**Files:**
- Modify: `lib/screens/setting_screen.dart:313-475`
- Modify: `lib/screens/profile_settings_screen.dart:40-145`
- Modify: `test/screens/setting_screen_test.dart`
- Modify: `test/screens/profile_settings_screen_test.dart`

**Interfaces:**
- Consumes: settings/profile entries from Task 1.
- Preserves: `DisplayPreferencesController`, account session state, consent use cases, cloud readiness, data erasure callback, profile loader, and all existing widget keys.
- Excludes: learner email, XP, counts, status payloads, and profile values from glossary lookup.

- [ ] **Step 1: Add Settings/Profile RED assertions**

Extend `setting_screen_test.dart` with a display-authority fixture and verify exact existing keys plus Thai copy:

```dart
expect(find.text('การแสดงผล'), findsOneWidget);
expect(find.byKey(const ValueKey<String>('theme-system')), findsOneWidget);
expect(find.text('ระบบ'), findsOneWidget);
expect(find.byKey(const ValueKey<String>('reduced-motion-switch')), findsOneWidget);
expect(find.text('ลดการเคลื่อนไหว'), findsOneWidget);
expect(find.byKey(const ValueKey<String>('erase-local-data')), findsOneWidget);
expect(find.text('ลบข้อมูลในเครื่องทั้งหมด'), findsOneWidget);
expect(find.text('Erase all local data'), findsNothing);
```

Use the existing injectable dependencies needed to expose offline content, research consent, account actions, and local erasure; assert their stable keys/callbacks remain enabled only under the same conditions. In `profile_settings_screen_test.dart`, replace the English axis expectations with:

```dart
for (final label in <String>[
  'ความชำนาญ',
  'ทบทวนแบบเว้นระยะ (SRS)',
  'เวลาเรียนจริง',
  'ความแม่นยำ',
  'จุดที่ควรฝึกเพิ่ม',
  'ความต่อเนื่องในการเรียน',
]) {
  expect(find.text(label), findsOneWidget);
}
expect(find.text('80% จาก 10 คำตอบ'), findsOneWidget);
expect(find.text('42 XP · ต่อเนื่อง 7 วัน'), findsOneWidget);
```

- [ ] **Step 2: Run Settings/Profile RED once**

```powershell
flutter test --no-pub test/screens/setting_screen_test.dart test/screens/profile_settings_screen_test.dart --reporter compact
```

Expected: current authority tests remain green; new assertions fail on local erasure, English profile axes, `Cloud`, and `Streak` presentation.

- [ ] **Step 3: Consume the glossary without changing domain state**

In `SettingScreen`, resolve entries adjacent to rendering and use the entry's full label/icon/semantics/tooltip for static controls. Cloud readiness still chooses `cloud_done_outlined` versus `cloud_off_outlined`, but both states render the fixed glossary title `สถานะการเชื่อมต่อระบบออนไลน์` and a Thai dynamic subtitle (`พร้อมใช้งาน` or `ไม่พร้อมใช้งาน · การเรียนออฟไลน์ยังทำงานได้`). Use `erase-local-data` tooltip as the Thai subtitle; retain the current key and `_eraseLocalData` callback.

In `ProfileSettingsScreen`, pass the six glossary labels into `_AxisCard`. Change only the presentation template from `Streak ${days} วัน` to `ต่อเนื่อง ${days} วัน`; keep the underlying engagement fields and values unchanged.

- [ ] **Step 4: Run GREEN and preserve state tests**

```powershell
dart format lib/screens/setting_screen.dart lib/screens/profile_settings_screen.dart test/screens/setting_screen_test.dart test/screens/profile_settings_screen_test.dart
flutter test --no-pub test/screens/setting_screen_test.dart test/screens/profile_settings_screen_test.dart --reporter compact
git diff --check -- lib/screens/setting_screen.dart lib/screens/profile_settings_screen.dart test/screens/setting_screen_test.dart test/screens/profile_settings_screen_test.dart
```

Expected: all tests pass; persistence and profile availability assertions remain unchanged.

- [ ] **Step 5: Stage exactly Task 4 and commit**

```powershell
git add -- lib/screens/setting_screen.dart lib/screens/profile_settings_screen.dart test/screens/setting_screen_test.dart test/screens/profile_settings_screen_test.dart
git diff --cached --name-only
git diff --cached --check
git commit -m "feat: apply Thai glossary to settings and profile"
```

---

### Task 5: Today Hub, Study Planning Hub, and scoped child entry labels

**Files:**
- Modify: `lib/screens/today_hub_screen.dart:261-447`
- Modify: `lib/screens/study_planning_hub_screen.dart:13-106`
- Modify: `lib/screens/review_center_screen.dart:47`
- Modify: `lib/screens/learning_history_screen.dart:50`
- Modify: `lib/screens/learning_pack_catalog_screen.dart:39`
- Modify: `lib/screens/learning_goals_screen.dart:137`
- Modify: `lib/screens/learning_preference_quiz_screen.dart:88-95`
- Modify: `test/screens/today_hub_screen_test.dart`
- Modify: `test/screens/study_planning_hub_screen_test.dart`
- Modify: `test/screens/review_center_screen_test.dart`
- Modify: `test/screens/learning_history_screen_test.dart`
- Modify: `test/screens/learning_pack_catalog_screen_test.dart`
- Modify: `test/screens/learning_goals_screen_test.dart`
- Modify: `test/screens/learning_preference_quiz_screen_test.dart`

**Interfaces:**
- Consumes: Today action IDs, Study Planning action IDs, and child `AppPage.name` entries from Task 1.
- Preserves: `TodayHubActionDelegate`, `_runAction` single-flight behavior, assessment feature gate, `AppNavigator.pushPage`, and these exact route names: `home/today/review`, `home/today/history`, `research/assessment`, `study-planning/catalog`, `study-planning/goals`, `study-planning/learning-preferences`.
- Produces: Thai action text/semantics/tooltips and Thai child AppBar labels only.

- [ ] **Step 1: Add Today Hub action RED tests**

Extend the existing `_app` fixture and exact action-delegation test:

```dart
const todayCases = <(String, String, IconData)>[
  ('today-hub-resume-action', 'เรียนต่อ', Icons.play_arrow),
  ('today-hub-start-recommendation', 'เริ่มกิจกรรมที่แนะนำ', Icons.auto_awesome_outlined),
  ('today-hub-assessment-action', 'เริ่มแบบประเมิน', Icons.assignment_outlined),
  ('today-hub-open-review', 'เปิดศูนย์ทบทวน', Icons.fact_check_outlined),
  ('today-hub-open-history', 'ดูประวัติการเรียน', Icons.history),
];
for (final (key, label, icon) in todayCases) {
  final action = find.byKey(ValueKey<String>(key));
  expect(action, findsOneWidget);
  expect(find.descendant(of: action, matching: find.text(label)), findsOneWidget);
  expect(find.descendant(of: action, matching: find.byIcon(icon)), findsOneWidget);
}
```

Keep the current exact `resumeCalls`, `recommendationCalls`, `reviewCalls`, `historyCalls`, and `assessmentCalls` assertions.

- [ ] **Step 2: Add Study Planning and child-route RED tests**

In `study_planning_hub_screen_test.dart`, assert these existing keys and Thai labels, then observe the current route name with a small `NavigatorObserver`:

```dart
const cases = <(String, String)>[
  ('study-planning/open-catalog', 'เลือกชุดเนื้อหาการเรียน'),
  ('study-planning/open-goals', 'เป้าหมายการเรียน'),
  ('study-planning/open-learning-preferences', 'การตั้งค่าการเรียน'),
];
```

After each tap, assert both destination type and exact route name: `study-planning/catalog`, `study-planning/goals`, or `study-planning/learning-preferences`. In each child test, add only the AppBar assertion:

```dart
expect(find.widgetWithText(AppBar, 'ชุดเนื้อหาการเรียน'), findsOneWidget);
expect(find.widgetWithText(AppBar, 'เป้าหมายการเรียน'), findsOneWidget);
expect(find.widgetWithText(AppBar, 'การตั้งค่าการเรียน'), findsOneWidget);
```

Retain existing dynamic pack/goal/preference content assertions. Review Center and Learning History already render Thai; change their tests to assert the AppBar text comes from the exact route glossary entry while leaving session, vocabulary, and pack-title expectations untouched.

- [ ] **Step 3: Run hub/child RED once**

```powershell
flutter test --no-pub test/screens/today_hub_screen_test.dart test/screens/study_planning_hub_screen_test.dart test/screens/review_center_screen_test.dart test/screens/learning_history_screen_test.dart test/screens/learning_pack_catalog_screen_test.dart test/screens/learning_goals_screen_test.dart test/screens/learning_preference_quiz_screen_test.dart --reporter compact
```

Expected: Today behavior remains green; Study Planning and three English child AppBars fail their Thai copy assertions, while route names and feature-gate assertions stay green.

- [ ] **Step 4: Implement glossary consumption at action and heading boundaries**

For Today buttons, resolve by the existing button key and render `entry.icon`, `entry.fullThaiLabel`, plus `Tooltip(message: entry.tooltip)` and a single explicit semantic label. Do not move `_runAction` or alter `_assessmentEnabled`.

For Study Planning, replace the English AppBar and introductory static navigation sentence with `วางแผนการเรียน` and `เลือกชุดเนื้อหาที่ตรวจสอบแล้วเพื่อวางแผนการฝึกครั้งถัดไป`. Each button consumes its existing-key entry; keep the existing `AppPage.name`, `ProductionFeatureGate`, and dependency condition unchanged.

For child screens, change only the AppBar label to the matching route entry:

```dart
AppBar(
  title: Text(
    NavigationGlossary.require('study-planning/catalog').fullThaiLabel,
  ),
)
```

Use the corresponding exact route ID for each child. Do not route dynamic pack titles, goal titles, learner history, review details, form validation, or external errors through the glossary.

- [ ] **Step 5: Run GREEN, format, and inspect route stability**

```powershell
dart format lib/screens/today_hub_screen.dart lib/screens/study_planning_hub_screen.dart lib/screens/review_center_screen.dart lib/screens/learning_history_screen.dart lib/screens/learning_pack_catalog_screen.dart lib/screens/learning_goals_screen.dart lib/screens/learning_preference_quiz_screen.dart test/screens/today_hub_screen_test.dart test/screens/study_planning_hub_screen_test.dart test/screens/review_center_screen_test.dart test/screens/learning_history_screen_test.dart test/screens/learning_pack_catalog_screen_test.dart test/screens/learning_goals_screen_test.dart test/screens/learning_preference_quiz_screen_test.dart
flutter test --no-pub test/screens/today_hub_screen_test.dart test/screens/study_planning_hub_screen_test.dart test/screens/review_center_screen_test.dart test/screens/learning_history_screen_test.dart test/screens/learning_pack_catalog_screen_test.dart test/screens/learning_goals_screen_test.dart test/screens/learning_preference_quiz_screen_test.dart --reporter compact
git diff --check -- lib/screens/today_hub_screen.dart lib/screens/study_planning_hub_screen.dart lib/screens/review_center_screen.dart lib/screens/learning_history_screen.dart lib/screens/learning_pack_catalog_screen.dart lib/screens/learning_goals_screen.dart lib/screens/learning_preference_quiz_screen.dart test/screens/today_hub_screen_test.dart test/screens/study_planning_hub_screen_test.dart test/screens/review_center_screen_test.dart test/screens/learning_history_screen_test.dart test/screens/learning_pack_catalog_screen_test.dart test/screens/learning_goals_screen_test.dart test/screens/learning_preference_quiz_screen_test.dart
```

Expected: all hub and child tests pass; no dynamic learner content expectation changes.

- [ ] **Step 6: Stage exactly Task 5 and commit**

```powershell
git add -- lib/screens/today_hub_screen.dart lib/screens/study_planning_hub_screen.dart lib/screens/review_center_screen.dart lib/screens/learning_history_screen.dart lib/screens/learning_pack_catalog_screen.dart lib/screens/learning_goals_screen.dart lib/screens/learning_preference_quiz_screen.dart test/screens/today_hub_screen_test.dart test/screens/study_planning_hub_screen_test.dart test/screens/review_center_screen_test.dart test/screens/learning_history_screen_test.dart test/screens/learning_pack_catalog_screen_test.dart test/screens/learning_goals_screen_test.dart test/screens/learning_preference_quiz_screen_test.dart
git diff --cached --name-only
git diff --cached --check
git commit -m "feat: localize Thai planning and today navigation"
```

---

### Task 6: Narrow English-menu regression, accessibility, and production navigation scenario

**Files:**
- Create: `test/architecture/thai_navigation_glossary_boundary_test.dart`
- Modify: `test/scenarios/production_feature_navigation_test.dart`
- Modify only if RED proves a scoped consumer gap: the Task 2-5 screen or adjacent test that renders the failing registered entry.

**Interfaces:**
- Consumes: `NavigationGlossary.entries` and the real production `MainNavigationScreen`/`ChooseModeScreen`/hub harnesses.
- Preserves: `productionFeatureContract`, `BuildFeatureRegistry.fieldDefaults()`, destination types, route names, and live emergency-off behavior.
- Produces: no production API; this task is release-gate coverage.

- [ ] **Step 1: Add the narrow glossary acronym/English boundary test**

Create `test/architecture/thai_navigation_glossary_boundary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';

void main() {
  test('registered Thai navigation copy has no unexplained English fallback', () {
    final latin = RegExp(r'[A-Za-z]');
    for (final entry in NavigationGlossary.entries.values) {
      for (final value in <String>[
        entry.fullThaiLabel,
        entry.shortThaiLabel,
        entry.semanticsLabel,
        entry.tooltip,
      ]) {
        final withoutApprovedAcronyms = value
            .replaceAll('AI', '')
            .replaceAll('SRS', '')
            .replaceAll('CEFR', '');
        expect(
          latin.hasMatch(withoutApprovedAcronyms),
          isFalse,
          reason: '${entry.id}: $value',
        );
      }
    }
  });

  test('approved acronyms retain canonical Thai explanatory context', () {
    expect(
      NavigationGlossary.require('drawer/ai-tutor/chat').fullThaiLabel,
      'ผู้ช่วยสอน AI',
    );
    expect(
      NavigationGlossary.require('home/learn/srs').fullThaiLabel,
      'ทบทวนแบบเว้นระยะ (SRS)',
    );
    expect(
      NavigationGlossary.require('home/learn/reading/cefr').fullThaiLabel,
      'อ่านตามระดับภาษา CEFR',
    );
  });
}
```

This test inspects only registered static presentation strings. It must not read source files, crawl `lib/`, or inspect dynamic widget text.

- [ ] **Step 2: Add the production navigation scenario regression**

In `production_feature_navigation_test.dart`, add one test named `Thai glossary preserves exact production entry identity and live gates`. Reuse `productionEntries` and the existing `_EntrySurface` harness. Assert:

```dart
for (final entryCase in productionEntries) {
  final delivery = productionFeatureContract[entryCase.feature]!;
  expect(delivery.productionEntryId, entryCase.id);
  expect(NavigationGlossary.require(entryCase.id).fullThaiLabel, isNotEmpty);
}
```

Where a production-contract entry points to a child mode rather than a glossary root, resolve its real stable `entryCase.id` only if it is part of the exact Task 1 set; do not add aliases or use translated labels as IDs. For the existing interactive part of the test, tap by `ValueKey<String>(entryCase.id)`, assert the unchanged `destinationType` and `routeName`, call `features.emergencyOff(entryCase.feature)`, and retain `_expectUnavailableGate`.

- [ ] **Step 3: Run the two RED gates once**

```powershell
flutter test --no-pub test/architecture/thai_navigation_glossary_boundary_test.dart --reporter compact
flutter test --no-pub test/scenarios/production_feature_navigation_test.dart --plain-name "Thai glossary preserves exact production entry identity and live gates" --reporter compact
```

Expected: the architecture test passes if all Task 1 copy is canonical. The scenario may expose only a missing registered production entry; if so, add the exact existing ID and Thai presentation entry, then rerun only the changed failing command. A route, gate, or destination mismatch is a production regression and must not be fixed by changing the expected stable ID.

- [ ] **Step 4: Run focused accessibility assertions**

In the adjacent screen tests from Tasks 2-5, use `tester.ensureSemantics()` with guaranteed disposal and assert each scoped interactive entry has exactly one Thai semantic action. Assert visible text remains present under its `Tooltip`; do not replace visible text with icon-only semantics.

Run:

```powershell
flutter test --no-pub test/architecture/thai_navigation_glossary_boundary_test.dart test/screens/main_navigation_screen_test.dart test/screens/choose_mode_screen_test.dart test/screens/setting_screen_test.dart test/screens/profile_settings_screen_test.dart test/screens/today_hub_screen_test.dart test/screens/study_planning_hub_screen_test.dart --plain-name "Thai glossary" --reporter compact
```

Expected: every scoped Thai glossary test passes with no leaked `SemanticsHandle` and no duplicate critical action semantics.

- [ ] **Step 5: Format, inspect, stage, and commit Task 6**

```powershell
dart format test/architecture/thai_navigation_glossary_boundary_test.dart test/scenarios/production_feature_navigation_test.dart
git diff --check -- test/architecture/thai_navigation_glossary_boundary_test.dart test/scenarios/production_feature_navigation_test.dart
git add -- test/architecture/thai_navigation_glossary_boundary_test.dart test/scenarios/production_feature_navigation_test.dart
git diff --cached --name-only
git diff --cached --check
git commit -m "test: lock Thai navigation glossary boundaries"
```

If a scoped production/test path changed due to a proven RED gap, include that exact path in the `dart format`, `git diff --check`, and `git add --` commands; inspect `git diff --cached --name-only` before committing.

---

### Task 7: Bounded verification, Android physical smoke, review, and staging audit

**Files:**
- Verify only: all Task 1-6 implementation and test paths.
- Do not create a verification artifact or change documentation in this task.

**Interfaces:**
- Consumes: frozen commits from Tasks 1-6.
- Produces: bounded acceptance evidence, physical Android smoke notes in the task record, and a clean staged set.

- [ ] **Step 1: Bind the frozen implementation fingerprint**

```powershell
git rev-parse HEAD
git status --short
git diff --check
```

Expected: only the protected parked iOS and generated registrant changes may remain; no glossary implementation path is uncommitted or staged.

- [ ] **Step 2: Run the exact formatter check once**

```powershell
dart format --output=none --set-exit-if-changed lib/navigation/navigation_glossary.dart lib/screens/main_navigation_screen.dart lib/screens/choose_mode_screen.dart lib/screens/setting_screen.dart lib/screens/profile_settings_screen.dart lib/screens/today_hub_screen.dart lib/screens/study_planning_hub_screen.dart lib/screens/review_center_screen.dart lib/screens/learning_history_screen.dart lib/screens/learning_pack_catalog_screen.dart lib/screens/learning_goals_screen.dart lib/screens/learning_preference_quiz_screen.dart test/navigation/navigation_glossary_test.dart test/architecture/thai_navigation_glossary_boundary_test.dart test/screens/main_navigation_screen_test.dart test/screens/production_shell_navigation_test.dart test/screens/choose_mode_screen_test.dart test/screens/setting_screen_test.dart test/screens/profile_settings_screen_test.dart test/screens/today_hub_screen_test.dart test/screens/study_planning_hub_screen_test.dart test/screens/review_center_screen_test.dart test/screens/learning_history_screen_test.dart test/screens/learning_pack_catalog_screen_test.dart test/screens/learning_goals_screen_test.dart test/screens/learning_preference_quiz_screen_test.dart test/scenarios/production_feature_navigation_test.dart
```

Expected: exit 0 and `0 changed`. If formatting changes are needed, run `dart format` on only the reported paths, commit them as `chore: format Thai navigation glossary package`, bind a new fingerprint, and do not repeat the old-fingerprint check.

- [ ] **Step 3: Run focused tests sequentially**

```powershell
flutter test --no-pub test/navigation/navigation_glossary_test.dart test/architecture/thai_navigation_glossary_boundary_test.dart --reporter compact
flutter test --no-pub test/screens/main_navigation_screen_test.dart test/screens/production_shell_navigation_test.dart --reporter compact
flutter test --no-pub test/screens/choose_mode_screen_test.dart test/screens/setting_screen_test.dart test/screens/profile_settings_screen_test.dart --reporter compact
flutter test --no-pub test/screens/today_hub_screen_test.dart test/screens/study_planning_hub_screen_test.dart test/screens/review_center_screen_test.dart test/screens/learning_history_screen_test.dart test/screens/learning_pack_catalog_screen_test.dart test/screens/learning_goals_screen_test.dart test/screens/learning_preference_quiz_screen_test.dart --reporter compact
flutter test --no-pub test/scenarios/production_feature_navigation_test.dart --reporter compact
```

Expected: every command exits 0. Run each command after the preceding command finishes; do not run groups concurrently.

- [ ] **Step 4: Run bounded analyzer and diff checks once**

```powershell
flutter analyze --no-pub lib
git diff --check
git status --short
```

Expected: analyzer exits 0 with no issues; diff check exits 0; status contains no unexpected or staged product path.

- [ ] **Step 5: Run one physical Android smoke after local gates are green**

Resolve one connected physical Android device without a hard-coded machine-specific ID:

```powershell
$thaiNavDevice = (& flutter devices --machine | ConvertFrom-Json | Where-Object { $_.targetPlatform -like 'android-*' -and -not $_.emulator } | Select-Object -First 1).id
if ([string]::IsNullOrWhiteSpace($thaiNavDevice)) { throw 'No physical Android device is connected.' }
flutter run --debug --no-pub -d $thaiNavDevice
```

On the device, verify in order: bottom bar labels and selected icons; Drawer Thai labels and AI private-key explanation; all Choose Mode tiles; Settings and Profile; Today Hub actions; Study Planning actions; Review Center, Learning History, Learning Pack Catalog, Learning Goals, and Learning Preferences headings. Confirm disabled/hidden feature entries remain disabled/hidden and back navigation returns to the same parent. Press `q` once to terminate the debug run. Record the device model, Android version, command exit code, and observed result in the controller/task log; do not create a repository file.

- [ ] **Step 6: Review the exact package diff**

```powershell
git diff HEAD~6..HEAD -- lib/navigation/navigation_glossary.dart lib/screens/main_navigation_screen.dart lib/screens/choose_mode_screen.dart lib/screens/setting_screen.dart lib/screens/profile_settings_screen.dart lib/screens/today_hub_screen.dart lib/screens/study_planning_hub_screen.dart lib/screens/review_center_screen.dart lib/screens/learning_history_screen.dart lib/screens/learning_pack_catalog_screen.dart lib/screens/learning_goals_screen.dart lib/screens/learning_preference_quiz_screen.dart test/navigation/navigation_glossary_test.dart test/architecture/thai_navigation_glossary_boundary_test.dart test/screens/main_navigation_screen_test.dart test/screens/production_shell_navigation_test.dart test/screens/choose_mode_screen_test.dart test/screens/setting_screen_test.dart test/screens/profile_settings_screen_test.dart test/screens/today_hub_screen_test.dart test/screens/study_planning_hub_screen_test.dart test/screens/review_center_screen_test.dart test/screens/learning_history_screen_test.dart test/screens/learning_pack_catalog_screen_test.dart test/screens/learning_goals_screen_test.dart test/screens/learning_preference_quiz_screen_test.dart test/scenarios/production_feature_navigation_test.dart
```

Review for: exact ID preservation; no label used as route identity; no gate mutation; no dynamic learner data in the glossary; no unexplained English; explicit Thai semantics/tooltips; canonical icons; no duplicate semantic action; no out-of-scope file. Require reviewer verdict `Critical 0, Important 0` before handoff.

- [ ] **Step 7: Audit staging and hand off without push/merge**

```powershell
git diff --cached --name-only
git status --short
git log -6 --oneline
```

Expected: staged set is empty, six task commits are present with the exact messages in this plan, and protected parked paths remain unstaged. Report commit SHAs, command exit codes, test counts, Android smoke result, and `Critical 0, Important 0`. Do not push or merge.
