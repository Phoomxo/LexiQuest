# LexiQuest ADLC final9 UI critique checkpoint

Date: 2026-10-24; follow-up critique attested 2026-10-26
Branch: `feature/associative-reading-loop`
Disposition: `engineering-complete` for the reviewed Flutter UI, copy, accessibility, and local product gate
Data boundary: local and synthetic evidence; production research remains disabled

## Intent and grounded scope

Run `/critique` on the current application UI, repair every must-fix finding immediately, and attest the resulting dirty-worktree snapshot through the repository ADLC. This card covers the touched Flutter screens, responsive behavior, Thai user-facing copy, accessibility semantics, navigation continuity, and local product verification. It does not authorize publication, deployment, production research, or real participant enrollment.

## Execute

The final9 repair closed these review findings:

- Vocabulary uses one primary floating action; import/source actions reflow inside the content pane.
- The CEFR world map carries the selected level into the destination and uses theme color roles in light and dark modes.
- Quiz feedback uses accessible semantic color pairs. Its AppBar switches to a 96 dp, two-line title at 200% text scale, including when a Back button consumes width.
- Weakness practice uses the plain Thai title `ฝึกจุดอ่อน`, one Filled primary action, and one Outlined secondary action.
- The Score screen keeps `ฝึกคำที่ผิด` as the single Filled primary action and renders `กลับไปเลือกกิจกรรม` as an Outlined secondary action.
- XP is presented as `คะแนนประสบการณ์`; marketplace currency is `เหรียญ`; destination names use `ร้านค้ารางวัล`, `ฝึกพูดตามเสียง`, and `ฝึกจุดอ่อน` consistently.
- User-facing UI no longer exposes build IDs, achievement/source IDs, AI model IDs, scanner delegates, engine IDs, or catalog versions.
- Permanent microphone denial offers a direct path to the device permission center.
- Async errors use live regions and progress indicators have Thai semantics labels, including the three Settings busy states and consent-status failure.
- Stale test assumptions were repaired without reverting product behavior: lazy Gemini Settings controls are scrolled into view, internal build IDs are asserted absent, the privacy-copy assertion follows the current wording, and two intended visual changes received new golden baselines.

The 2026-10-25 follow-up critique then closed the remaining shell and copy issues:

- Compact and wide layouts expose one predictable menu trigger while the compact shell keeps four primary destinations.
- App-bar titles use a consistent adaptive Material type role and retain two-line capacity at large text sizes.
- Core labels use shorter plain Thai: `เลือกแบบฝึก`, `สแกนวัตถุ`, `คำศัพท์ตามระดับ`, and `ผู้ช่วย AI`.
- Registration privacy notice is separated from optional research consent; opening the notice cannot grant consent.
- Empty-state recovery, item-specific delete tooltips, OTP busy announcements, and progress semantics now state the action or status explicitly.
- Scanner and marketplace gutters follow the compact 16/20 dp contract.

## Review: `/critique`

Three independent read-only reviews inspected the follow-up source after repair.

| Review | Result | Score | Remaining must-fix |
| --- | --- | ---: | --- |
| Visual hierarchy, responsive typography, theme/accessibility, interaction continuity | PASS | 40/40 | None |
| UX copy, plain Thai, identifier privacy, recovery, accessibility status | PASS | 40/40 | None |
| ADLC Review/Attest consistency and regression scope | PASS | — | None |

Visual evidence includes compact portrait and landscape behavior at 200% text, dark/light semantic color pairs, CEFR route continuity, one primary Vocabulary action, and the corrected Weakness action hierarchy. UX evidence includes consistent reward terminology, hidden internal metadata, permission recovery routes, live-region errors, and labelled progress states.

### Follow-up `/critique` cycle 3 — 2026-10-25

The native Impeccable review found one remaining P1 copy family: learner-facing screens still exposed `วิธีคำนวณรุ่น` or `เกณฑ์รุ่น`. The repair removed those labels from Achievements, Profile, Mastery, Shadowing, Ghost Duel, and Weakness while retaining algorithm/version provenance in domain, sync, and export boundaries. Six connected widget suites now assert the learner copy and absence of internal labels. The inspected Weakness golden was updated only after the isolated actual render showed intact title, card, and actions at 180% Thai text.

Post-repair design health: **40/40**, with zero unresolved P0/P1 findings. Snapshot: `.impeccable/critique/2026-10-25T16-10-09Z__lib-screens.md`.

### Follow-up `/critique` cycle 4 — 2026-10-25

The navigation and copy pass found one remaining P1 information-architecture issue: the drawer presented `ตั้งค่าผู้ช่วย AI` as a separate destination immediately after `ผู้ช่วยฝึกภาษาอังกฤษ`, even though the Tutor tile already exposed a contextual setup action. The repair removed only the duplicate drawer item. AI setup remains reachable from the main Settings screen, from the Tutor AppBar, and from the limited-state `เชื่อมต่อผู้ช่วย AI` action.

The focused navigation, runtime, Settings, and Tutor suites passed 95/95 after the RED/GREEN repair. Post-repair design health remains **40/40**, with zero unresolved P0/P1 findings. Snapshot: `.impeccable/critique/2026-10-25T16-29-34Z__lib-screens.md`.

### Follow-up `/critique` cycle 5 — 2026-10-25

Direct inspection of the 200% Thai learning-hub golden found one remaining P1 layout/copy issue: the first activity title `ฝึกจากคลังคำศัพท์` broke `คำศัพท์` across lines, while its subtitle occupied four lines and made the card disproportionately tall. The repair changed only the learner-facing copy to `ฝึกคำศัพท์` and `ฝึกคำแปล แล้วดูคำที่ควรทบทวน`; routing, feature visibility, and learning behavior are unchanged.

The RED/GREEN copy test passed, the isolated actual/diff image was inspected, and only `learning_hub_large_text.png` was updated. The focused learning/navigation suites passed 31/31 and the golden suite passed 4/4. Post-repair design health remains **40/40**, with zero unresolved P0/P1 findings. Snapshot: `.impeccable/critique/2026-10-25T16-49-36Z__lib-screens.md`.

### Follow-up `/critique` cycle 6 — 2026-10-26

The authentication review found one remaining P1 recovery issue: submitting an empty or malformed email from `รีเซ็ตรหัสผ่าน` dismissed the dialog before surfacing provider validation, forcing the user to reopen the dialog and re-enter context. The repair uses the same email rule as Login, keeps the dialog open, shows `กรอกอีเมล` or `ตรวจสอบรูปแบบอีเมล` inline, clears the error while editing, and calls the provider only after valid input. Google sign-in, guest mode, registration, and optional research consent are unchanged.

The RED/GREEN reset test passed, the focused authentication/accessibility suites passed 32/32, and 200% light/dark Login and Register coverage remained green. Post-repair design health remains **40/40**, with zero unresolved P0/P1 findings. Snapshot: `.impeccable/critique/2026-10-25T17-10-17Z__lib-screens.md`.

### Follow-up `/critique` cycle 7 — 2026-10-26

The registration review found one remaining P1 form-feedback issue: invalid email, weak password, confirmation mismatch, and missing privacy acknowledgement surfaced globally or serially, so users could not see all local corrections in one attempt. The repair validates all four controls before provider use, attaches native errors to the three fields, exposes the privacy acknowledgement error as a live region, and clears only the relevant local error while editing. Domain validation remains the independent trust boundary; privacy acknowledgement and optional research consent remain separate.

The RED/GREEN invalid-fields test passed, the focused registration/account/accessibility suites passed 47/47, and 200% light/dark coverage remained green. Post-repair design health remains **40/40**, with zero unresolved P0/P1 findings. Snapshot: `.impeccable/critique/2026-10-25T17-31-01Z__lib-screens.md`.

### Follow-up `/critique` cycle 8 — 2026-10-26

The email-verification review found one remaining P1 consistency issue: when the account provider was unavailable, `ฉันยืนยันอีเมลแล้ว` explained the failure but `ส่งอีเมลยืนยันใหม่` silently returned, making the secondary action appear broken. The repair gives Resend the same `ระบบยืนยันอีเมลไม่พร้อมใช้งาน` recovery message while preserving the busy guard and performing no provider call.

The RED/GREEN unavailable-resend assertion passed and the focused verification/authentication/accessibility suites passed 59/59. Post-repair design health remains **40/40**, with zero unresolved P0/P1 findings. Snapshot: `.impeccable/critique/2026-10-25T17-52-54Z__lib-screens.md`.

### Follow-up `/critique` cycle 9 — 2026-10-26

The account-settings review found one remaining P1 recovery issue: blank or weak values in `เปลี่ยนรหัสผ่าน` dismissed the dialog before provider validation surfaced globally, so the learner lost the correction context. The repair validates both fields inside the dialog, shows direct Thai errors for empty, short, and overlong values, clears only the edited field error, and dispatches no account-provider call until both values are valid. The account use-case remains the independent trust boundary.

The RED/GREEN password-change test passed and the focused Settings/account/deletion/authentication suite passed 74/74. Post-repair design health remains **40/40**, with zero unresolved P0/P1 findings. Snapshot: `.impeccable/critique/2026-10-25T18-18-29Z__lib-screens.md`.

### Follow-up `/critique` cycle 10 — 2026-10-26

The vocabulary-category review found one remaining P1 form-recovery issue: blank, duplicate, or failed category saves surfaced in a page-level SnackBar while the active modal field had no error state, and rapid submission was not locally guarded. The repair keeps validation and persistence errors beside `ชื่อหมวดหมู่`, preserves the draft, clears the error during editing, shares one submit path between keyboard and button, and blocks duplicate persistence or route exit only while a save is in flight. Cancel, Back, and outside dismissal remain available before submission.

The RED/GREEN category-dialog test passed and the focused vocabulary journey/use-case/repository suites passed 17/17. Post-repair design health remains **40/40**, with zero unresolved P0/P1 findings. Snapshot: `.impeccable/critique/2026-10-25T18-40-59Z__lib-screens.md`.

### Follow-up `/critique` cycle 11 — 2026-10-26

The Add/Edit Word review found one remaining P1 feedback and transaction issue: blank word, meaning, and part-of-speech input collapsed into one generic page-level SnackBar, while Back could detach the learner from an in-flight save. The repair identifies all three missing fields in one attempt, maps domain length failures back to the affected control, retains duplicate/capacity/storage failures in a live form message, shares one submit path with keyboard Done, and guards navigation only during persistence. The learner's draft remains intact after every recoverable failure.

The RED/GREEN word-form test passed at 360×800 and 200% text, and the focused vocabulary journey/use-case/repository suites passed 18/18. Post-repair design health remains **40/40**, with zero unresolved P0/P1 findings. Snapshot: `.impeccable/critique/2026-10-25T19-01-33Z__lib-screens.md`.

### Follow-up `/critique` cycle 12 — 2026-10-26

The vocabulary-import review found one remaining P1 correction-loop issue: saving an invalid preview row closed its editor and returned it as `ต้องแก้ไข`, forcing the learner to reopen the same row. The repair validates word, meaning, and part of speech inside the existing dialog, shows all missing fields together, preserves the draft, clears only the edited error, and shares one submit path between keyboard Done and Save. Parser, duplicate, cancellation, owner, and persistence contracts are unchanged.

The RED/GREEN import-row test passed at 360×800 and 200% text, the focused import/parser/use-case suites passed 28/28, and an independent read-only critique scored 40/40 with no P0/P1. Snapshot: `.impeccable/critique/2026-10-25T19-33-16Z__lib-screens.md`.

## Attest

All commands below completed on the cycle 12 source snapshot after the last code and test update.

| Check | Result |
| --- | --- |
| Focused navigation, runtime, Settings, and Tutor tests | PASS, 95/95 |
| Focused learning hub, shell navigation, and layout tests | PASS, 31/31 |
| Learning-loop golden suite | PASS, 4/4 |
| Focused authentication and accessibility tests | PASS, 32/32 |
| Focused registration, account, and accessibility tests | PASS, 47/47 |
| Focused verification, authentication, and accessibility tests | PASS, 59/59 |
| Focused Settings, account, deletion, and authentication tests | PASS, 74/74 |
| Focused vocabulary journey, use-case, and repository tests | PASS, 17/17 |
| Focused Add/Edit Word and vocabulary tests | PASS, 18/18 |
| Focused import editor, parser, importer, and vocabulary tests | PASS, 28/28 |
| `flutter test --concurrency=1` | PASS, 1752/1752 |
| `flutter analyze` | PASS, no issues |
| `git diff --check` | PASS; existing LF-to-CRLF warnings only |
| `tool/cli/verify-product-completion.ps1` | PASS |
| Product completion Flutter tests | PASS, 727/727 |
| Firebase Auth emulator journey | PASS, 3/3 |
| Firestore emulator rules | PASS, 33/33 |
| Android debug APK | PASS |
| APK model runtime integrity (Debug) | PASS |
| Whitespace and conflict markers | PASS |

An earlier full-suite attempt correctly exposed ten stale assertions/baselines after the UX changes. Each was diagnosed and repaired with focused evidence. A final golden critique then found one Score action-hierarchy issue. The follow-up full suite exposed two stale visual baselines caused by the reviewed title and copy improvements. Their master/test/diff images were inspected before updating only those goldens. Cycle 3 added a RED/GREEN copy test across six reachable screens, inspected and updated the affected Weakness golden, then passed the focused suites 76/76 and golden suite 4/4. Cycle 4 added a RED/GREEN navigation assertion for the duplicate AI settings route and passed its focused 95/95 suite. Cycle 5 added a RED/GREEN large-text activity-copy assertion, inspected the isolated actual/diff render before updating one golden, and passed the focused 31/31 and golden 4/4 suites. Cycle 6 added a RED/GREEN password-reset validation test and passed its focused authentication/accessibility 32/32 suite. Cycle 7 added a RED/GREEN registration field-validation test and passed its focused registration/account/accessibility 47/47 suite. Cycle 8 added a RED/GREEN unavailable-resend assertion and passed its focused verification/authentication/accessibility 59/59 suite. Cycle 9 added a RED/GREEN in-dialog password-change validation test and passed its focused Settings/account/deletion/authentication 74/74 suite. Cycle 10 added a RED/GREEN in-dialog category validation/single-flight test and passed its focused vocabulary 17/17 suite. Cycle 11 added a RED/GREEN Add/Edit Word validation/pending-navigation test at 200% text and passed its focused vocabulary 18/18 suite. Cycle 12 added a RED/GREEN import-row validation test at 200% text, passed its focused import 28/28 suite, and then passed the current 1752/1752 suite, analysis, recovered Firestore 33/33 gate, and full product gate. Generated comparison images under `test/screens/failures/` are diagnostic output from intentional failing golden runs and are not release evidence.

## Integrate and release state

This card is `engineering-complete` for the inspected Flutter source and local product gate. It does not upgrade the project to published, deployed, or production-research-ready.

- Figma Cloud R11 reflects the earlier final8 state and is stale relative to final9 UI/copy/accessibility changes.
- Final8 physical Vivo and release-signature evidence belongs to its older source snapshot; no post-final9 physical-device or signed-release artifact was produced in this card.
- Fold/posture behavior still lacks evidence from real fold hardware.
- TalkBack reading order still requires a post-final9 physical-device pass.
- Production research authority, enrollment, and upload remain default-off pending their separate approvals and evidence.

## Learn

- Route-level large-text tests must include the leading Back action; a screen mounted directly as `home` has more title width and can hide truncation.
- `scrollUntilVisible` can create a lazy child while leaving its center outside the hit-test viewport. Follow it with `ensureVisible` before tapping long adaptive forms.
- When UI intentionally hides internal identifiers, update tests to assert absence and preserve domain-level storage tests separately.
- Golden failures after an approved visual change require image inspection and a focused baseline update; removing the golden assertion would weaken the gate.
- Transactional dialogs should keep validation, pending state, and recovery inside the dialog; lock dismissal only while persistence is actually in flight.
- Full-page forms should report every local correction in one attempt and reserve a live form-level message for domain or storage failures that do not belong to one field.
- Editors nested inside review flows must not return invalid data to the outer review and force users to rediscover the same correction.
