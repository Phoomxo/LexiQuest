# PM8 planned-case coverage map review

ตรวจเมื่อ 2026-09-07 10:14 ICT ที่ branch
`codex/pair-matching-pm0-pm8`, HEAD
`3bdb5f5605e670e8b30628f3f237cd9c0d660ad9` โดยอ่าน
`.superpowers/sdd/pm8-pmt-coverage-map.md`, TC-PMT rows ใน
`docs/adventure-motivation-mode/06-test-plan-and-test-cases.md`, UAT headings ใน
`docs/adventure-motivation-mode/07-uat-script.md` และ test headings เฉพาะ mapping ที่ต้อง
ตรวจความหมายเพิ่ม ไม่มีการแก้ map/docs/source และไม่มี test หรือ coverage inventory ถูก execute

## Inventory result

- เอกสาร test plan มี TC-PMT data rows 44 แถว, 44 IDs ไม่ซ้ำ และครบ
  `TC-PMT-001` ถึง `TC-PMT-044`
- ตาราง planned cases หลักใน coverage map มี 14 mapping rows เมื่อขยาย en-dash ranges และ
  comma-separated IDs แล้วได้ 44 IDs พอดี ช่วง 001–044 ไม่มี missing ID และไม่มี duplicate
  การนับนี้ตั้งใจไม่นับ TC-PMT references ซ้ำในตาราง UAT crosswalk
- เอกสาร UAT มี headings 12 หัวข้อ, 12 IDs ไม่ซ้ำ และครบ `UAT-039` ถึง `UAT-050`
- ตาราง External UAT ใน map มี 12 แถวตรงกับ 039–050 ครั้งละหนึ่งแถว ทุกแถวระบุ
  `Human/device status = NotRun` และ related TC-PMT references อยู่ในช่วง 001–044
- Local automated evidence column มี path references 68 รายการ หรือ 48 paths ไม่ซ้ำ
  ทุก path มีไฟล์จริง ณ เวลาตรวจ สำหรับ path ที่ขึ้นต้น `test/` ใช้ repository-relative;
  path ที่ไม่ขึ้นต้น prefix ใช้
  `test/features/learning/pair_matching/<declared-path>` ตามกติกาใน map
- ข้อความสรุปท้าย map ที่ระบุ 258 unique RTM rows, 188 planned TC rows และ 50 UAT
  scripts ตรงกับเอกสารปัจจุบัน: 258/258, 188/188 และ 50/50 unique ตามลำดับ

## Semantic overclaim check

ไม่พบการอ้างว่า human, learner, guardian, physical audio, accessibility device, historical
binary, deployed fleet, remote rollout หรือ production activation ผ่านแล้ว Map ระบุข้อจำกัดไว้
ชัดเจน ได้แก่ learner comprehension ไม่ได้วัด, physical audio/provider/model performance
`NotRun`, physical TalkBack/Switch/gesture/device validation `NotRun`, historical binaries
ไม่ได้ execute, real remote rollout/production activation ไม่มี และ G4P decisions/names/dates
ยังไม่บันทึก

Spot checks ของ mapping ที่มีโอกาสถูกอ่านกว้างเกิน fixture ยืนยันชื่อ test ที่สอดคล้อง:

- TC-PMT-001 มี test ชื่อ exact f10 hidden learning boundary และ negative f45/main-route/
  star-table mutations รวมกับ production navigation/default-off screen tests
- TC-PMT-024 อ้าง native TTS tests ที่ตรวจ locale/rate, installed local voice, no-text-on-
  failure, provenance, stop/fallback/privacy policy เท่านั้น จึงไม่ใช่ physical audio result
- TC-PMT-040 มี Release A legacy schema/old reader, current reader, strict schema 6,
  writer capability และ old-reader rejection headings จริง พร้อม limit ว่าไม่ได้ execute
  historical binaries
- TC-PMT-041 มี codec headings สำหรับ raw elapsed identity, Unicode attempt ledger,
  byte/terminal capacity และ owner-upgrade headings สำหรับ immutable plan/actor/pins
- TC-PMT-042 มี canonical renderer parity และ same-host fallback headings จริง โดย map
  จำกัดผลเป็น normalized synthetic semantics
- TC-PMT-043 มี widget headings สำหรับ text 200%, keyboard/semantics tap, focus stability,
  reverse locale labels, guided confirmation และ long Thai wrapping; คำว่า action parity
  อยู่ในบริบท widget และมี physical-device `NotRun` กำกับ
- TC-PMT-044 มี compatibility writer/Quiz disposal, configured disposition,
  Standard/Adventure parity fallback และ runtime emergency-off/control headings จริง

## Gaps and limits

ไม่พบ structural gap, missing path หรือ human/device acceptance overclaim ใน map ปัจจุบัน
อย่างไรก็ตาม map เป็น file-and-heading inventory เท่านั้น การมีไฟล์หรือชื่อ test ไม่พิสูจน์ว่า
ทุก assertion ของ TC-PMT row ผ่านบน frozen source และไม่พิสูจน์ coverage เชิง runtime

Final root evidence ยังต้องแนบ actual named JSON inventory จาก source identity เดียวกันและ
จำแนก pass/fail/skip อย่างชัดเจน ตาราง UAT crosswalk ใช้ TC-PMT ranges และคำบรรยาย
`configured host cap fixtures` แทน exact test names จึงควร trace ผ่านตารางหลักและ actual JSON
inventory ไม่ควรนำ crosswalk เพียงอย่างเดียวไปอ้างว่า UAT ผ่าน

## Reproducible read-only checks

```powershell
rg -n '^\| TC-PMT-' `
  'docs/adventure-motivation-mode/06-test-plan-and-test-cases.md'
rg -n '^### UAT-0(39|4[0-9]|50) —' `
  'docs/adventure-motivation-mode/07-uat-script.md'

# Parse only map rows beginning "| TC-PMT-"; expand NNN–NNN and comma lists.
# Resolve prefixed paths from repository root and unprefixed paths from:
# test/features/learning/pair_matching/
```

ผลนี้ไม่ใช่ test execution, coverage execution, G4P decision, UAT acceptance หรือ
physical-device evidence
