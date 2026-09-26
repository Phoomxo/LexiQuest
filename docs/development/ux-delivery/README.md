# LexiQuest — สถานะการส่งมอบ UX ตามสปรินต์

## S01-BC — checkpoint ล่าสุด (หยุดตามคำสั่งผู้ใช้)

Existing explicit logout recovery **HOST_PASS570**: account/settings/owner 286 + runtime/navigation 284; 46 new offline cases. Callback เดิมหมดสิทธิ์เมื่อ account/session/dependency/route/tab/pop/lifecycle เปลี่ยน; ป้องกันคำสั่งซ้ำและผลล่าช้าพาออกจากหน้าใหม่. ตรวจ owner ที่คิวและ transaction เดิม; รักษา rollback/entry restoration โดยไม่ย้อนผล provider ที่ commit แล้วหรือแทนที่ owner ใหม่. Error แสดงภาษาไทยอย่างไม่อ้างผลสำเร็จหรือ rollback ที่พิสูจน์ไม่ได้; ต้องเลือกใหม่โดยผู้ใช้เอง.

Final source pins 1,563 ตรงกันและตรงไฟล์ปัจจุบัน; inherited ZIPs 233 ชุดไม่เปลี่ยน. Scoped analysis ไม่พบปัญหา; Drift warnings core11/runtime25 ไม่ถูก suppress. Prototype115+3 ใช้หลักฐานเดิมบน8 pins. Self-review only; ไม่ใช่ native/device/visual/keyboard/screen-reader/user/trial/release acceptance. UX-D01–25 OPEN และวันเริ่ม/กำหนด review S01 เดิมไม่เปลี่ยน.

คำสั่งล่าสุดให้จบ BC แล้ว release writer และส่ง controller เพื่อสำรอง/จัดระเบียบ: **ไม่มี successor, nested transfer ZIP, commit/push หรือ cleanup โดย writer นี้**. ดู [validation](evidence/S01-BC-validation.json), [รายงาน BC](S01-BC.md), [controller checkpoint](handoffs/S01-BC-controller-checkpoint.json) และ [backup inventory](handoffs/S01-BC-backup-inventory.json). S01 ยังไม่จบ.


Authority: [แผนฉบับ 5](../../design/worksheet-to-play-blueprint.md), อนุมัติให้ implement และแยกแชตต่อสปรินต์/งานย่อยโดยผู้ใช้ 2026-09-24. เอกสารนี้เป็น index ของงานใหม่ ไม่ใช้ `ari/state.json` หรือ G/B-bundle state เก่าสั่งงานต่อ

Live S01 checkpoint: [รายงาน S01](S01.md), [ชุดส่งตรวจ](reviewer-packet.md), [ผลตรวจพร้อม source pins](evidence/S01-validation.json). S01-A ผ่านเฉพาะการตรวจ source; B/C มีร่างและ host checks แล้ว ยังรอ review/visual evidence. D external pending; ไม่ใช่จบ sprint. Latest native checkpoint is S01-AA in da20 (189 scoped host tests PASS); X/Y 115 host + 3 compatibility reused on exact pins. Read state.json and the latest receipt for the sole live writer and successor; predecessor worktrees are immutable. S01-Z adds a proposed instructional evidence contract (source/design review only, no runtime/schema change). See state.json, instructional-evidence-contract-v1.md and readiness-12-groups.md for full-plan pending acceptance and readiness.

## อ่านก่อนเริ่ม

Latest authority 2026-09-24: continue ready work across plan-v5 backlog automatically, one writer/package at a time. S01 draft completion does not exhaust all independent UX/a11y/interface work. Jev can advise the next model against fresh executor capabilities and the original guarded USD5 budget; unavailable Jev means explicit current-model fallback. Standard/default remains mandatory. Existing controller heartbeat `lexiquest-r3` is authorized; do not duplicate it. Instructional Flutter and learning trials retain their media/reviewer/participant gates.

1. อ่าน [state.json](state.json) และ handoff ที่ระบุใน state; ตรวจว่าเป็น snapshot หรือสถานะ live ก่อนอัปเดต
2. ตรวจ source ตาม manifest และข้อกำหนดใน `AGENTS.md`; HEAD อย่างเดียวไม่ครอบคลุม dirty/untracked จาก d38e
3. รับ writer เฉพาะงานที่จองไว้และเมื่อ predecessor ปล่อยแล้ว บันทึก thread/worktree/branch/current item/UTC start ใน state ของ workspace ที่รับงาน
4. อ่านแผนเฉพาะข้อ 15.3–15.8 และส่วนของงานนั้น; เกณฑ์การเรียนข้อ 5.4/6.6/14 คงเดิม ห้ามโหลดหลักฐานทุกยุคหรือกลับไปรัน 215 ข้อ

## สถานะและขอบเขต

- Bootstrap เตรียมเอกสารและ verified transfer; ยังไม่เป็น S01-A PASS
- S01-A: source/reuse/dependency/interface/media feasibility และทะเบียน 14 workflow/14 mode/6 activity families
- S01-B: บท/สื่อ/คำสั่ง/rubric/ข้อใหม่และชุดสำหรับผู้ตรวจ; draft ไม่เท่ากับ reviewed
- S01-C: ต้นแบบสองเส้นทางและ defect ที่กระทบ; navigation ทำได้ระหว่างรอสื่อที่ตรวจแล้ว
- S01-D: ผู้ตรวจ/สื่อ/ผู้ทดลองจริงพร้อมจึงทดลอง; ขณะ bootstrap ยัง external pending

ใช้ result `PASS / FAIL / NOT_TESTED / EXTERNAL_PENDING` ต่อเกณฑ์ และเก็บงาน `TODO / IN_PROGRESS / COMPLETE / WAITING` แยกจากผลรับ. ทั้ง chat, sprint, work item และ release มีสถานะของตนเอง. เอกสาร/Node/host/native/provider/user evidence ไม่ทดแทนกัน

## การส่งต่อและ source authority

- สดสุดอยู่ใน state ของแชตที่ถือ writer ซึ่งระบุด้วย receipt ล่าสุด; source ต้นทางใน d38e และ snapshot นี้เป็น immutable predecessor หลัง dispatch
- [bootstrap handoff](handoffs/S01-bootstrap.json) ระบุ bootstrap dispatch ID และชุดไฟล์ที่ต้องรับ; [bootstrap report](bootstrap.md) ระบุผลตรวจเอกสาร/การรักษาไฟล์
- Source overlay และ before-backup อยู่ใน `build/ux-delivery/20260924-bootstrap/` ของ d38e เป็น local transfer artifacts; manifest อยู่ใน `handoffs/bootstrap-source-manifest.json`. ไม่ย้าย/ลบต้นทาง และไม่ commit build/cache/secrets
- Snapshot ไม่ประกาศว่าทั้ง source ผ่านรับ และไม่แก้ความหมายหลักฐานเก่า. เก็บ base SHA + dirty/untracked โดยทดสอบอ่าน archive คืนและ hash ให้ตรงก่อน dispatch
- สร้าง successor หนึ่งรายการใน project `e0d28f74-0d26-40bc-b126-4cfebe4ff7a0` (ตรวจ list_projects ก่อน); fresh context, source ตาม handoff ไม่ใช่ default branch. ถ้าเคยมี ID ให้ต่อรายการนั้น; clientThreadId ยังไม่ใช่ threadId
- ผู้ส่งหยุดเขียน application source หลัง release. การบันทึก receipt ทำในไฟล์แยก ไม่เปลี่ยน source snapshot. ผู้รับเป็นผู้ดูแล live state และส่งต่อรุ่นถัดไป; ไม่สร้าง writer ซ้อน
- ไม่มีผู้ตรวจจริงให้คง pending แล้วทำ independent authorized work; ห้ามส่งข้อความนัดคน/ผู้ให้บริการแทนผู้ใช้โดยไม่มีคำสั่งส่งข้อความ

## การตรวจและรายงาน

ใช้ `tool/cli/verify-scope.ps1` สำหรับ application gates ตาม scope; ไม่ rerun passed inputs เดิม ไม่รัน heavy checks พร้อมกัน. งาน bootstrap เอกสารตรวจ consistency/paths/JSON/source preservation/transfer roundtrip เท่านั้น ไม่เรียก Flutter/backend/Android/GPU/native/user trial

Known tool restriction from the predecessor: browser automation of the local prototype was rejected, including attempts to bypass through another browser/CDP/headless/localhost. Do not work around that rejection. Source checks and permitted file previews remain available; keep actual visual/browser/user acceptance pending until a permitted review path exists.

Checkpoint สั้นต่อขอบเขตงาน: ผลล่าสุด, source/content/APK ถ้ามี, evidence, defect/RED/pending, next ready action และ routing receipt. ใช้ heartbeat เดิมที่ผู้ใช้อนุมัติ ไม่สร้างซ้ำ ไม่อ้างเปอร์เซ็นต์ประหยัด token โดยไม่มี telemetry.

Live authority correction / S01-AA: existing native shell still has five entries, so independent navigation implementation is ready despite media/trial/visual acceptance pending. Read S01-AA-acceptance.md and handoffs/S01-AA-continuation.json. f72d writer released for one fresh native-package successor; the separate dispatch receipt identifies the current task. Earlier idle statements are historical.

Latest checkpoint: S01-AB recovery HOST_PASS in f436, 128 scoped tests. Read state and S01-AC handoff for sole-writer succession; predecessor source immutable after release.


## Latest checkpoint — S01-AD

AD existing personal export recovery/lifecycle HOST_PASS: 73 affected host tests, including 9 new widget/route cases and 2 store cases; all 1,539 source pins and stream hashes verified. Nine confirmed RED cases resolved. Thai truthful explicit retry, effective dependency/owner-reader rebinding, operation generations and immediate route-pop cancellation preserve canonical formats/content/owner snapshots/consent/store cleanup and rollback. Selections remain; no automatic save or AI write action. Prototype 115+3 reused on eight unchanged pins. No remaining RED; native/device/real a11y/user/trial/release pending, UX-D01–25 OPEN and S01 dates unchanged. See evidence/S01-AD-validation.json.

All twelve groups reassessed in evidence/S01-AD-backlog-reassessment.json. Next coherent scope S01-AE: existing review queue recovery and launch/dependency lifetime. Initial/retry future observation, duplicate retry and mutable use cases during pending launch are source hypotheses requiring widget/route RED before implementation. Preserve canonical owner/content/SRS/session/lease authorities; no instructional expansion. See S01-AE-acceptance.md.


## Latest checkpoint — S01-AE

AE existing review queue recovery/lifecycle HOST_PASS: 255 affected host tests, 16 new widget/route cases; 11 confirmed RED resolved. All 1,539 source pins and stream hashes verified; exact source closure retained. Immediate future observation, bounded explicit retry, dependency/builder rebinding and generation/route guards prevent stale actions. Displayed owner is checked before start, returned session owner matched and current owner rechecked before building/pushing; stale sessions use their original abandon/lease retirement authority. Canonical content/SRS/scoring/session/schema unchanged. Prototype 115+3 reused on eight unchanged pins. No remaining RED; native/device/real accessibility/visual/user/trial/release pending, UX-D01–25 OPEN and S01 dates unchanged. See evidence/S01-AE-validation.json.

All twelve groups reassessed in evidence/S01-AE-backlog-reassessment.json. Next coherent scope S01-AF: existing personal progress dashboard read recovery. Failure has Thai text but no in-page retry; direct loader invocation lacks synchronous-error capture/immediate future observation. Existing tab/dependency rebinding must be preserved and verified with read/owner/context lifetimes. These are source hypotheses, not runtime RED. No scoring or instructional expansion; see S01-AF-acceptance.md.


## Latest checkpoint — S01-AF

AF existing personal progress dashboard recovery/lifecycle HOST_PASS: 222 affected host tests, 18 new widget/route/real-Drift owner cases. Ten inherited RED cases and one introduced explicit-loader rebinding regression resolved. All 1,539 source pins, gate streams and closed checkpoint ZIP verified. Thai bounded explicit retry captures immediate/synchronous failure; generation, subscription epoch, tab/route/disposal retirement and canonical owner observation/revalidation prevent stale results. Explicit loaders retain independence from unrelated dependency changes. Separate axes/no-evidence/optional owner-bound guidance and weakness/review/calendar/goals navigation retained; no canonical data, scores, events or schema changes. Prototype 115+3 reused on eight unchanged pins. Self-review only. No remaining RED; native/device/restart/real accessibility/visual/user/trial/release pending, UX-D01–25 OPEN and S01 dates unchanged. See evidence/S01-AF-validation.json.

All twelve groups reassessed in evidence/S01-AF-backlog-reassessment.json. Next coherent scope S01-AG: existing read-only quest status retry/listener lifecycle. _retry currently lacks pending/generation/route guards and failure layout lacks scrolling. These are source hypotheses, not runtime RED; preserve automatic durable-status notifications and canonical bounded read/owner/pinned-definition rules. Retry must never become refreshDaily, event/reward/score writes or instructional expansion. See S01-AG-acceptance.md.


## Latest checkpoint — S01-AG

AG existing read-only quest status recovery/lifecycle HOST_PASS: **264 affected host tests**, 16 new quest cases; 11 confirmed quest RED resolved. Generation-bound explicit retry, immediate observation, tab/route/pop/disposal retirement and one trailing read for coalesced durable notifications preserve canonical bounded limit50 reads, owner/pinned-definition rules and conditional-not-earned reward meaning. Thai failure scrolls at 360px/200%; owner-bound optional read-only guidance retained. No quest scheduling/reward/event/scoring/schema change.

Expanded production-shell checks found two obsolete five-tab expectations plus a real missing-composition vocabulary drawer blank view. Fixtures now distinguish available composition and assert four tabs against real bootstrap; drawer opens canonical unavailable gate and returns to its original parent. Original application/test bytes, all 1,539 source pins, log hashes and closed checkpoint ZIP verified. See evidence/S01-AG-validation.json. Prototype 115+3 reused on eight unchanged pins. Self-review only; no remaining RED. Native/device/restart/real accessibility/visual/user/trial/release pending; UX-D01–25 OPEN and S01 dates unchanged.

All twelve groups reassessed in evidence/S01-AG-backlog-reassessment.json. Next coherent scope **S01-AH existing achievement read recovery and user-directed share confirmation lifetime**. Source hypotheses require real widget/route RED first; preserve canonical unlock evidence, user confirmation/save picker, cancellation and dedup, read-only reward meaning, quest/shop links and baseline without AI. No instructional expansion; see S01-AH-acceptance.md.


## Latest checkpoint — S01-AH

AH existing achievement read recovery and user-directed share lifetime HOST_PASS: **352 affected host tests**, 25 new widget/route/real-Drift owner cases; 14 confirmed RED resolved. Immediate/synchronous read failures are observed; explicit retries are bounded by generation/pending/tab/route. Owned confirmation stays usable with single-dialog protection; unrelated cover, pop, disposal, service and owner changes retire stale callbacks/results. Canonical owner observation plus revalidation protects unlock receipts. Thai failure scrolls at 360px/200%; old status retry cannot update a disposed page. Custom loaders remain independent of unrelated dependencies.

Canonical unlock validation, artifact immutability/no owner identifiers, explicit user confirmation/destination/cancel/dedup and original evidence meaning remain unchanged. Pending user-authorized immutable saves are not claimed revoked. All source pins, stream hashes and checkpoint ZIP verified; original edited bytes and inherited archives retained. Prototype 115+3 reused on eight unchanged pins. Self-review only; no remaining RED. Native/device/restart/real accessibility/visual/user/trial/release pending, UX-D01–25 OPEN, original S01 dates unchanged. See evidence/S01-AH-validation.json.

All twelve groups reassessed in evidence/S01-AH-backlog-reassessment.json. Next coherent package **S01-AI existing avatar reward read recovery and explicit item-action lifetime**: _reload, preview and purchase/equip callbacks have visibility/generation/displayed-owner hypotheses. Reproduce widget/route/isolated-Drift RED first, retain price/catalog/owner/transaction/progression and uncertain-write reconciliation authorities; no live purchases or instructional expansion. See S01-AI-acceptance.md.


## Latest checkpoint — S01-AI

Existing avatar reward recovery HOST_PASS: **206 scoped host tests** (39 avatar + 167 reward/owner/navigation), 32 new cases, 16 confirmed RED resolved. Reads/reconciliation, retry and displayed item actions are fenced by generation, owner and route/tab lifetime. Expected-owner admission prevents old displayed buttons acting for a replacement owner. Preview/cancel and deferred scrolling have operation lifetime; overlapping operations cannot leave retired busy state. Thai failure scrolls at 360px/200%. Canonical price/catalog/coin/progression and transaction checks, explicit purchase/equip, read-only uncertain-write reconciliation, dedup and menu context remain. Source pins/streams/checkpoint ZIP verified; original archives retained. No remaining RED; native/device/real accessibility/visual/user/trial/release pending; UX-D01–25 OPEN and S01 dates unchanged.

All twelve groups reassessed in evidence/S01-AI-backlog-reassessment.json. Next coherent package S01-AJ: existing learner preferences read recovery and explicit draft/save lifetime. Source hypotheses: missing retry/immediate observation, mounted-only visibility checks and unbound draft callbacks. Test before fixes; preserve owner/feature/transaction guards, draft recovery and truthful planning-preference meaning. No instructional expansion. See S01-AJ-acceptance.md.


## Latest checkpoint — S01-AJ

Existing learner preferences recovery HOST_PASS: **175 scoped host tests** (58 feature/owner/store + 117 preference merge/display/sync/planning/navigation), 23 new cases and 17 targeted confirmed RED resolved. Explicit read-only retry observes failures immediately. Draft callbacks and saves are bounded by displayed generation, owner and route/tab lifetime; own dropdown selection remains usable. Same-owner draft survives recoverable read/owner-observation errors while hidden; owner replacement clears it. Post-save owner revalidation and read-only uncertain-acknowledgement reconciliation keep draft/lastConfirmed/saving/saved/failed truthful, without automatic resave. Through-commit guard rollback preserves preference and outbox together. Home/display scoped merges, enum/range, owner/feature authorities and optional read-only context remain.

Open-dropdown owner transition required an additional diagnostic: disposing the picker makes the route current without another dependency notification. A single generation-bound post-frame resume read resolves the blank retired form. Temporary instrumentation removed; original assertions retained. All 1,539 source pins, gate streams and checkpoint ZIP verified; original archives preserved. Prototype 115+3 reused on eight unchanged pins. No remaining RED; native/device/restart/real keyboard/screen-reader/visual/user/trial/release pending, UX-D01–25 OPEN, original S01 dates unchanged. See evidence/S01-AJ-validation.json.

All twelve groups reassessed in evidence/S01-AJ-backlog-reassessment.json. Next coherent package **S01-AK existing learning goals read recovery and explicit goal-action lifetime**. Read failure lacks retry; mutation guard lacks tab/route/displayed-generation bounds, and optional owner context checks do not fence returned list data. These are source hypotheses requiring widget/route/isolated-Drift RED before implementation. Preserve create/edit/status/delete confirmation semantics, owner/feature/transaction/outbox/date/timezone authorities, owned dialogs and reminder entry; no actual notification scheduling or instructional expansion. See S01-AK-acceptance.md.


## Latest checkpoint — S01-AK

Existing learning goals recovery HOST_PASS: **252 scoped host tests** (80 goal/editor/owner + 172 planning/reminder/date/navigation), 23 new cases, 14 targeted confirmed RED and one introduced reminder-entry regression resolved. Read-only bounded retry observes immediate/synchronous errors. Canonical owner revalidation after every asynchronous context boundary, displayed generations, tab/route/pop/disposal and editor operation lifetime fence stale callbacks. Owned status/kind/date/time pickers and explicit reminder entry remain usable. Same-owner draft remains private across observation errors and returns after retry; owner replacement clears it. Explicit stable-command retry and read-only uncertain delete/status reconciliation preserve honest acknowledgement; no automatic mutation. Through-commit rollback preserves goal and outbox together.

All 1,540 source pins, final streams and closed checkpoint ZIP verified. Original archives and diagnostic runs preserved; prototype 115+3 reused on eight unchanged pins. Self-review only. No remaining RED. Native/device/restart/real keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and original S01 start/due unchanged. See evidence/S01-AK-validation.json.

All twelve groups reassessed in evidence/S01-AK-backlog-reassessment.json. Next coherent package **S01-AL existing study reminder status recovery and explicit opt-in/cancel lifetime**: initial/resume status futures, missing read retry and mounted/epoch-only callbacks are source hypotheses requiring meaningful widget/route/isolated-Drift RED before changes. Preserve owner, prepared intents, permission, quiet-hours/date/timezone, desired/platform status and explicit manual action authorities; test with isolated scheduler doubles only, no actual device notification scheduling. No instructional/provider/schema/research expansion. See S01-AL-acceptance.md.


## Latest checkpoint — S01-AL

Existing study reminder recovery HOST_PASS: **448 scoped host tests** (121 reminder/widget/date-time + 327 reminder/planning/goals/owner/navigation/bootstrap regression), 20 new cases and 14 confirmed RED resolved. Explicit bounded read-only retry, displayed generations, owner observation/revalidation, route/pop/inactive/disposal and owned-picker retirement fence stale data/actions. Offstage preserves same-owner partial date/time/timezone/quiet drafts across recoverable reads; owner replacement clears private state. Uncertain acknowledgements reread canonical status without resubmission. Pre-permission owner/feature/fence checks and through-commit reminder/outbox rollback preserve explicit action authorities. No actual device notification or permission action; scheduler doubles and isolated databases only.

All 1,540 source pins, stream hashes and checkpoint ZIP verified; original archives and diagnostics retained. Prototype 115+3 reused on eight unchanged pins. Self-review only. Native/device/restart/real keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and original S01 dates unchanged. See evidence/S01-AL-validation.json.

All twelve groups reassessed. Next coherent scope **S01-AM existing learning-calendar read recovery and private snapshot lifetime**, with existing dashboard route admission included. Direct one-time loader, missing retry and captured calendar snapshot are source hypotheses requiring widget/route/isolated-owner RED first. Preserve canonical personal-calendar readers, local dates, separate effort/accuracy/skill/trend/no-evidence semantics; no new aggregation, statistical reporting, research, instruction, schema or provider work. See S01-AM-acceptance.md.


## Latest checkpoint — S01-AM

Existing learning-calendar recovery and dashboard route admission HOST_PASS: **373 scoped host tests** (98 calendar/profile/owner/readers + 275 feature/navigation/bootstrap), 20 new cases and 11 confirmed RED resolved. Bounded read-only retry observes immediate/synchronous/repeated failures. Displayed generations, loader/dependency/owner observation and canonical revalidation, tab/cover/pop/disposal/app lifecycle retire private snapshots. Production calendar rereads canonical personal profile under live mastery feature gate; custom loaders remain independent. Parent guards stale/duplicate navigation and preserves child usability. Canonical calendar body, separate effort/accuracy/skills/trend/sample/no-evidence and local date/timezone semantics unchanged.

All source pins, stream hashes and checkpoint ZIP verified; original archives and diagnostics retained. Prototype 115+3 reused on eight unchanged pins. Self-review only; no remaining RED. Native/device/restart/real keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and original S01 dates unchanged. See evidence/S01-AM-validation.json.

All twelve groups reassessed. Next coherent package **S01-AN existing profile-tab read recovery and private identity/evidence lifetime**: missing explicit retry, owner-observer epoch and mutable loader/visibility checks are source hypotheses requiring widget/route/isolated-owner RED first. Preserve compact profile, expanded details, optional read-only menu contexts, secondary actions during failure and canonical owner/account matching; no account mutation or instructional/schema/provider/research expansion. See S01-AN-acceptance.md.


## Latest checkpoint — S01-AN

Existing profile read recovery/private identity HOST_PASS: **387 scoped host tests** (103 profile/owner/readers/dashboard + 284 navigation/gates/menu/bootstrap), 19 new cases and 9 confirmed RED resolved. Explicit bounded READ-ONLY retry observes immediate/synchronous failures. Displayed generations, owner-observer epoch, loader/dependency/tab/cover/pop/disposal/app lifecycle retire private snapshots and callbacks. Canonical returned profile/current owner/account UID checks preserved; standalone loaders remain independent and never borrow unrelated account email. Compact details, separate mastery/SRS/effort/accuracy/weakness/engagement/no-evidence meanings, secondary actions on error and optional owner-bound menu context retained.

All 1,540 final pins, streams and checkpoint ZIP verified; originals and diagnostics retained. Prototype 115+3 reused on eight unchanged pins. Self-review only. No remaining RED. Native/device/restart/real keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and original S01 dates unchanged. See evidence/S01-AN-validation.json.

All twelve groups reassessed. Next coherent package **S01-AO existing study-planning hub route admission and child lifetime**: unguarded repeated/stale navigation, parent-context child builders and captured registry are source hypotheses requiring meaningful route/widget/isolated-Drift RED first. Preserve child usability, live gates/composition, one canonical parent, Thai semantics, existing plan/personal-set entry and baseline without AI/login. No study assignment, calculations, scheduling, research, schema/provider or instructional work. See S01-AO-acceptance.md.


## Latest checkpoint — S01-AO

Existing planning parent/child navigation lifetime HOST_PASS: **404 scoped host tests** (120 planning children + 284 navigation/gates/menu/bootstrap), 19 new cases and 15 confirmed RED resolved. All five entries share displayed-generation, mounted/current-route/tab/pop/disposal/app-lifecycle and single-route admission. Child gates resolve their own live scope; replacement registries and removed parents no longer retain stale authority. Real-Drift goal status remains editable and commits once; each entry returns to its original parent. Thai 360px/200% semantics, menu actions and baseline without login/AI preserved. No goal mutation, scheduling, schema/scoring/research/provider/instructional change.

All 1,540 source pins, final streams and checkpoint ZIP verified; original archives and diagnostic runs retained. Prototype 115+3 reused on eight unchanged pins. Self-review only; no remaining RED. Native/device/restart/real keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and original S01 dates unchanged. See evidence/S01-AO-validation.json.

All twelve groups reassessed. Next coherent package **S01-AP existing catalog read recovery and filter/detail-entry lifetime**: unbounded dependency reload, absent retry/use-case replacement and detached filter/detail callbacks are source hypotheses requiring widget/route/isolated-owner RED before fixes. Preserve read-only catalog metadata, pinned revisions, canonical owner/progress and live gates; no content, study assignment, scoring, aggregation, scheduling or instructional expansion. See S01-AP-acceptance.md.


## Latest checkpoint — S01-AP

Existing catalog read/filter/pinned-detail navigation recovery HOST_PASS: **412 scoped host tests** (44 catalog + 84 related + 284 navigation/gates/menu/bootstrap), 20 new cases, 12 original-source RED and one introduced filter regression resolved. Explicit bounded READ-ONLY retry, effective use-case/dependency binding, canonical owner observation/revalidation and displayed lifetime guards preserve query/filter recovery. Detail/personal-set entries share single admission; live child gates survive registry replacement and parent removal. Pinned identity/revision, content quality, metadata-not-achievement, empty/no-match and optional menu contexts retained. Thai 360px/200% retry remains reachable. No content, study assignment, scoring, scheduling, schema, statistics, research or provider change.

All 1,540 source pins match across final gates and current source; streams and closed checkpoint ZIP verified. Original archives and diagnostics retained; prototype 115+3 reused on eight unchanged pins. Sole-writer self-review only. No remaining RED. Native/device/restart/real keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and original S01 dates unchanged. See evidence/S01-AP-validation.json.

All twelve groups reassessed. Next coherent package **S01-AQ existing pinned pack-detail read recovery and private snapshot/action lifetime**: unconditional dependency reload, missing explicit retry/owner observation and retained result/action callbacks are source hypotheses requiring widget/route/isolated-owner RED before fixes. Preserve pinned content identity/revision/quality, canonical progress, live feature/composition and existing explicit bookmark/report semantics; no new instructional activity or statistical aggregation. See S01-AQ-acceptance.md.


## Latest checkpoint — S01-AQ

Existing pinned pack-detail read/private snapshot and explicit control admission HOST_PASS: **463 scoped host tests** (179 detail/catalog/control/quality/planning + 284 navigation/gates/menu/bootstrap), 24 new cases, 17 original-source RED and two additional control-boundary RED resolved. One introduced removal-of-standalone-reader regression resolved. Bounded READ-ONLY retry, selected reader/vocabulary/action/repository rebinding, canonical owner observation/revalidation and tab/cover/pop/disposal/app lifecycle fence private data and stale controls. Owned report remains single-flight and usable; detached submit/close/reason retire. Bookmark/unsave/report retain truthful post-await acknowledgement. Exact pinned revision/lexical identity, fail-closed quality, optional owner context and Thai 360px/200% retry preserved.

All1,540 final pins agree/current; streams and checkpoint ZIP verified. Originals and diagnostics retained; prototype115+3 reused on eight unchanged pins. Self-review only, no remaining AQ RED. Native/device/restart/real keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and original S01 dates unchanged. See evidence/S01-AQ-validation.json.

AQ does not prove cancellation/rollback inside an already-admitted bookmark/report transaction. All twelve groups reassessed. Next coherent package **S01-AR existing bookmark/unsave/report owner and transaction lifetime**: canonical repositories await owner creation then select the active owner inside the transaction; report consent awaits within it. Whether owner changes or retired UI admission redirect/commit an in-flight explicit action is a source hypothesis requiring isolated-Drift/widget RED first. Preserve owner authority, natural-key/idempotency, tombstone/outbox atomicity, consent, explicit confirmation and truthful acknowledgement. No external reports/messages, learning/scoring/schema/protocol/provider/research expansion. See S01-AR-acceptance.md.


## Latest checkpoint — S01-AR

Existing explicit bookmark/unsave/report owner and transaction lifetime HOST_PASS: **547 scoped host tests** (115 mutation/control/detail + 148 related catalog/planning/readers + 284 navigation/bootstrap), 28 new cases and 21 original-source RED resolved. Nonbreaking async admission constraints carry displayed owner and control lifetime into canonical transactions. Initial owner is pinned; transaction owner/final admission checks reject stale commands and roll back local row/tombstone and outbox together, including retirement during consent and partial writes. Route/tab/pop/lifecycle/dependency/disposal retire actions permanently. Owned report remains usable. Post-commit notifier failure has truthful unknown acknowledgement and explicit idempotent retry; no automatic resubmission. Already committed writes are not undone.

All 1,543 final pins agree/current; final and original-RED source ZIPs, streams and inherited originals verified. Two prior upgrade expectations were strengthened to reject stale commands then test explicit current-owner retry, including original export/delete ownership assertions. Two mixed-owner positive fixtures corrected and negative reader/writer isolation added. Viewport fixtures now tap the intended lexical identity. Final mutation/related streams have no warnings; runtime preserves the same 25 Drift multiple-instance warnings as AQ, all284 tests PASS. Prototype115+3 reused on eight unchanged pins. Self-review only; no remaining RED. Native/device/restart/real keyboard/screen-reader/visual/user/trial/release pending, UX-D01–25 OPEN and original S01 dates unchanged. See evidence/S01-AR-validation.json.

All twelve groups reassessed. Next coherent scope **S01-AS existing local reading library navigation and child lifetime**: direct library/chooser route pushes, captured registry and parent callback are source hypotheses requiring meaningful widget/route RED before changes. Keep all six existing article texts/notices, local reading without fake session/CEFR/progress, vocabulary catalog/practice and original-parent return. No new content/media/instruction, scoring/events, assignment, provider, research or schema work. Qualified content/media/trial gates remain; see S01-AS-acceptance.md.


## Latest checkpoint — S01-AS

Existing reading-library navigation and child lifetime **HOST_PASS: 393 scoped host tests** (109 reading/catalog/chooser + 284 navigation/gates/bootstrap), 22 new cases; 19 original-source RED and one additional immediate-admission RED resolved. Displayed generations, mounted/current-route/tab/pop/disposal/lifecycle/dependency/widget replacement and shared single-flight retire stale entries. Each production article/catalog/library child resolves live scope; route-owned vocabulary configuration remains usable after chooser removal. Six original article texts/notices, no-session reading and canonical vocabulary practice preserved.

All 1,543 final path/hash pins agree/current; source ZIPs and streams verified. All inherited101 original ZIPs unchanged; originals/diagnostics retained. Prototype115+3 reused on eight unchanged pins. Self-review only. Reading has3 documented Drift warnings from isolated replacement-registry fixtures; runtime retains25 as AR. No remaining RED. Native/device/restart/real keyboard/screen-reader/visual/user/trial/release pending, UX-D01–25 OPEN and S01 dates unchanged. See evidence/S01-AS-validation.json.

All twelve groups reassessed. Next coherent scope **S01-AT existing CEFR catalog read/filter/license/detail navigation recovery**: one-time future/retry, detached filters, unguarded license/detail routes and parent-context child builder require meaningful RED first. Preserve offline content/editorial/rights/sense identities, existing explicit import authority and baseline without login/AI. No content/media/instruction/scoring/session/assignment/statistics/research/schema/provider expansion. See S01-AT-acceptance.md.


## Latest checkpoint — S01-AT

Existing CEFR catalog read/search/filter/license/detail navigation recovery **HOST_PASS: 419 scoped host tests** (135 catalog/import/reading/chooser + 284 navigation/gates/bootstrap), 27 new cases; 21 distinct original-source RED and two additional retained license-close RED resolved. Same-source bounded retry handles immediate/synchronous errors; fixed injected futures never silently switch to bundled content. Displayed generations and current route/tab/pop/disposal/lifecycle/dependency binding retire stale callbacks. Detail/license share single-flight admission; owned production detail resolves live scope and remains readable after parent removal. Original-catalog query return and canonical explicit import through UI pass.

All 1,544 final path/hash pins agree/current; checkpoints and streams verified. All inherited110 original ZIPs unchanged; original sources and diagnostic runs retained. Prototype115+3 reused on eight unchanged pins. Self-review only. Catalog4 documented Drift warnings (three inherited AS and one additional isolated replacement-registry fixture); runtime25 unchanged. No remaining RED. The original `_add` body, import algorithm/repository and word/sense/editorial/content/rights identities remain unchanged. Native/device/restart/real keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and original S01 dates unchanged. See evidence/S01-AT-validation.json.

All twelve groups reassessed. Next coherent scope **S01-AU existing explicit CEFR import recovery**: `_add` still awaits owner/categories with mounted-only checks, raw category-dialog callbacks and post-await messaging. Confirm meaningful widget/isolated-owner RED for category-dialog/read/admission/acknowledgement lifetime before changes. Preserve explicit-only importing, canonical owner/category/word/sense/editorial authority, duplicates/legacy edits and truthful results. No new content/instruction/scoring/provider/research/schema work; see S01-AU-acceptance.md.


## Latest checkpoint — S01-AU

Existing explicit CEFR import recovery **HOST_PASS: 495 scoped host tests** (32 widget/curated + 179 vocabulary/read/navigation + 284 runtime), 30 new cases. Initial 15 original-source RED, three additional transaction/acknowledgement boundary RED and three candidate recovery RED resolved. Owned category choice stays usable and single-flight; route/tab/pop/disposal/lifecycle/dependency/owner changes retire stale reads, selections and acknowledgements. Thai read recovery and truthful uncertain acknowledgement allow explicit retry without automatic resubmission.

Opt-in admission through canonical createWord wraps its existing algorithm in one outer transaction, rolling word/outbox back together on retirement before commit decision. Existing callers retain prior semantics; committed writes are not undone. Exact word/sense/editorial/source/rights, category validation/capacity, legacy edits and idempotency preserved. All 1,545 final pins agree/current; five RED source ZIPs and host checkpoint verified; all inherited124 original ZIPs unchanged. Prototype115+3 reused on eight unchanged pins. Final widget0/related4/runtime25 Drift warnings; related/runtime warnings inherited, no suppression. Self-review only; no remaining RED. Native/device/restart/real keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and S01 dates unchanged. See evidence/S01-AU-validation.json.

All twelve groups reassessed. Next coherent scope **S01-AV existing private vocabulary browse recovery**: category-to-word-list read/retry/search/navigation and child lifetime. Existing word-list failure has no retry; category callbacks use mounted/feature-only admission and capture parent binding. Confirm meaningful widget/isolated-Drift RED first; preserve private/packaged read-only identities, original-category return and existing explicit create/edit/delete/import algorithms. No content/instruction/scoring/provider/research/schema expansion; see S01-AV-acceptance.md.


## Latest checkpoint — S01-AV

Existing private vocabulary browse recovery **HOST_PASS: 472 scoped host tests** (104 widget/journey/mutation regression + 84 canonical vocabulary/import/isolated restart + 284 runtime/navigation), 26 new cases. Sixteen original-source RED and four additional boundary failures resolved (two strengthen existing title assertions). Stable read subscriptions retain local search and original category/query return; Thai explicit retry observes synchronous/immediate failures. Displayed generations, canonical owner observation/revalidation, category removal, dependency/feature/route/tab/pop/disposal/lifecycle and single-flight admission retire stale browse actions. Live child composition survives parent removal and registry replacement. Private titles retire with unavailable categories.

Canonical category/word/editorial identities, packaged read-only access, and all existing explicit mutation/import algorithms remain unchanged. All final source pins, streams, three RED source archives and host checkpoint verified; inherited originals retained. Prototype115+3 reused on eight unchanged pins. Self-review only. Widget3 isolated-Drift fixture warnings, related0, runtime25 unchanged from AU; no suppression. No remaining AV RED. Native/device/real restart/keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and S01 dates unchanged. See evidence/S01-AV-validation.json.

All twelve groups reassessed. Next coherent scope **S01-AW existing explicit personal category add/delete recovery**. Unchanged _showAddCategory/_confirmDelete/_AddCategoryDialog use mounted/feature-only admission and retained input/cancel/save/delete/post-await callbacks. These are source hypotheses requiring meaningful widget/route/isolated-Drift RED before fixes; preserve usable owned dialogs, drafts, canonical owner/category/outbox and truthful acknowledgement. No word/import expansion or new content/instruction/schema/provider/research work. See S01-AW-acceptance.md.


## Latest checkpoint — S01-AW

Existing explicit personal category add/delete recovery **HOST_PASS: 503 scoped host tests** (35 action/reconciliation + 100 vocabulary widget/journey + 84 repository/import/isolated restart + 284 runtime/navigation), 31 new cases. Twenty-eight original-source RED and three additional owner/privacy/copy RED resolved. Shared single-flight entry and owned dialog lifetimes retire stale native/menu controls across owner/category/dependency/feature/route/tab/pop/disposal/lifecycle changes. Thai read recovery retains partial drafts; explicit early save awaits initial owner read. Uncertain acknowledgement is truthful; committed optional identity can be reconciled read-only without resubmission.

Optional category admission wraps the existing canonical create/delete transactions; retirement before commit decision rolls category, word tombstones and outbox back together. Already committed writes are not revoked. Original inner repository algorithms, category rename and word create/edit/delete/import algorithms remain unchanged. All final source pins/streams and six RED source archives plus host checkpoint verified; all inherited143 original ZIPs unchanged. Prototype115+3 reused on eight unchanged pins. Self-review only. No remaining AW RED. Native/device/real restart/keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and original S01 dates unchanged. See evidence/S01-AW-validation.json.

All twelve groups reassessed. Next coherent scope **S01-AX existing explicit word-delete recovery**. VocabListScreen _deleteWord retains mounted/feature-only entry, raw dialog cancel/confirm callbacks and ordinary post-await messaging; _mcpDeleteWord has existing optional verification but only pre-mutation application admission. Confirm meaningful widget/route/isolated-Drift RED before fixes, preserving owner/category/word/outbox authority and committed reconciliation. No new instructional/content/provider/research/schema work. See S01-AX-acceptance.md.


## Latest checkpoint — S01-AX

Existing explicit personal word-delete recovery **HOST_PASS: 535 scoped host tests** (65 delete/reconciliation/offline journey + 102 vocabulary/category widgets + 84 repository/import/isolated restart + 284 runtime/navigation), 32 new cases. Twenty-seven meaningful original-source RED resolved; three introduced readiness/copy/explicit-retry regressions resolved. Shared single-flight admission, owned dialog lifetime, canonical owner/category/word revision checks, pending-read/Thai retry and truthful acknowledgement retire stale native/menu controls across dependency/feature/route/tab/pop/disposal/lifecycle changes. Real SQLite tests prove word tombstone/outbox rollback before commit decision. Already committed deletes remain committed; optional reconciliation reads only. After an uncertain error, a fresh owner-checked read of the unchanged word is required before allowing another explicit deletion attempt.

Original canonical delete body, category/create/edit/import algorithms and content/editorial/rights unchanged. All 1,552 final path/hash pins agree/current; source ZIPs and streams verified; all 157 inherited original ZIPs unchanged. Prototype 115+3 reused on eight unchanged pins. Self-review only. Final Drift warnings: core 5 separate-memory fixtures, widget 4 inherited category/browse, related 0, runtime 25 inherited; none suppressed. No remaining AX RED. Native/device/real restart/keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and original S01 dates unchanged. See evidence/S01-AX-validation.json and S01-AX.md.

All twelve groups reassessed. Next coherent scope **S01-AY existing explicit personal word form create/edit recovery**. AddWordScreen binds owner once, retains direct field/CEFR/fill/save callbacks and mounted-only messaging; native save does not pin the displayed owner, while updateWord checks admission only before canonical mutation. These are source hypotheses requiring meaningful widget/route/isolated-Drift RED before fixes. Preserve partial drafts, explicit-only writes, canonical lexical/category/owner/outbox authority and read-only committed reconciliation. No new content/instruction/schema/provider/research work; see S01-AY-acceptance.md.


## Latest checkpoint — S01-AY

Existing explicit personal word form recovery **HOST_PASS561**: 91 core + 102 widget + 84 repository/import/isolated restart + 284 runtime/navigation;26 new cases,23 original-source RED and4 candidate regressions resolved. Owner/source snapshots, initial privacy, partial-draft Thai retry, owned CEFR, explicit-only Save and read-only committed reconciliation preserve canonical word/outbox authority. All1,554 final pins agree/current and171 inherited ZIPs unchanged. Prototype115+3 reused on8 pins. Self-review only; warnings7/4/0/25 retained. No remaining AY RED. Native/device/real restart/keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and S01 dates unchanged. See [S01-AY report](S01-AY.md) and [validation](evidence/S01-AY-validation.json).

All twelve groups reassessed. Next **S01-AZ existing explicit manual personal import recovery**: one-time owner binding, retained fill/preview/import/back callbacks, native expectedOwnerId omission and mounted-only completion; confirm meaningful RED before changing form or canonical transaction admission. Preserve row failures, duplicate detection, category limits, import receipt/sourceHash/owner/outbox and read-only committed reconciliation. No new content/instruction/provider/research/schema scope. See [acceptance card](S01-AZ-acceptance.md).


## Latest checkpoint — S01-AZ

Existing explicit manual personal import recovery **HOST_PASS596**: 90 core +138 widget +84 repository/import/isolated restart +284 runtime;31 new cases,28 original-source RED resolved, plus cancellation/owner-read error recovery. Owner/category snapshots, retained-control retirement, initial and partial-draft Thai retry, explicit-only import and read-only committed reconciliation preserve actual import identity/source hash and canonical word/outbox/receipt transactions. All1,556 final path/hash pins agree/current;186 inherited ZIPs unchanged. Prototype115+3 reused on8 pins. Self-review only; Drift warnings2/9/0/25 retained without suppression. No AZ RED remains. Native/device/real restart/keyboard/screen-reader/visual/user/trial/release pending; UX-D01–25 OPEN and S01 dates unchanged. See [AZ report](S01-AZ.md) and [validation](evidence/S01-AZ-validation.json).

All twelve groups reassessed. Next **S01-BA existing display preference recovery**: SettingScreen theme/reduced-motion native/semantics/menu callbacks use mutable controller and mounted-only error notices; DisplayPreferencesController serializes existing canonical writes but only checks disposal in mutation guard. These are source hypotheses requiring meaningful RED before fixes. Preserve current controls, owner isolation, queue order, canonical preference store, committed outcomes and explicit-only writes. Account/erasure/research controls and new content/provider/schema scope excluded. See [acceptance card](S01-BA-acceptance.md).


## Latest checkpoint — S01-BA

Existing display preference recovery **HOST_PASS371**: 87 core/widget/preference/merge/erasure + 284 runtime; 51 new cases, 26 original-source and 7 additional boundary/companion RED resolved. Owned controls, explicit canonical read recovery, companion/no-op correctness and transaction commit guards preserve existing settings and committed outcomes. All 1,557 final pins agree/current; 200 inherited ZIPs unchanged. Prototype115+3 reused on8 pins. Scoped analysis clean; Drift warnings0/25 retained. Self-review only; no remaining BA RED. Native/device/real restart/keyboard/screen-reader/visual/user/trial/release pending, UX-D01–25 OPEN, original S01 dates unchanged. See [BA report](S01-BA.md) and [validation](evidence/S01-BA-validation.json).

All twelve groups reassessed. Next **S01-BB existing password dialog recovery**: retained dialog/entry callbacks, mutable account binding and mounted-only notices, plus reauthentication/update lifetime boundaries are source hypotheses. Reproduce offline RED first; no real credentials/provider/account operations, no new auth protocol or automatic reset/retry. Preserve BA display and all unrelated flows. See [acceptance card](S01-BB-acceptance.md).


## Latest checkpoint — S01-BB

Existing password dialog recovery **HOST_PASS432**:148 core/settings/account/display/erasure +284 runtime;47 new offline cases. Owned single-flight dialog/submission, session/dependency/route/tab/pop/lifecycle retirement, Thai validation and truthful uncertain acknowledgement. Gateway checks auth-state/caller lifetime between reauthentication and update; already-sent updates cannot be rolled back. SDK fresh-wrapper behavior covered. All1,560 final pins agree/current;217 inherited ZIPs unchanged. Prototype115+3 reused on8 pins. Self-review only; Drift0/25 retained. Analysis has no errors/warnings and one test-only style info. No BB RED remains. Required native/user/trial/release layers pending; UX-D01–25 OPEN; original dates unchanged. See [BB report](S01-BB.md) and [validation](evidence/S01-BB-validation.json).

All twelve groups reassessed. Next **S01-BC existing explicit logout recovery**: retained native/semantics callbacks can consult mutable account, mounted-only late navigation and typed-only error handling are source hypotheses. Reproduce offline with isolated fake account/local-owner authorities; preserve canonical owner transition, rollback/entry restoration and committed outcomes. No real sign-out, account/login/email/provider operation; no automatic retry or new auth protocol. See [acceptance card](S01-BC-acceptance.md).
