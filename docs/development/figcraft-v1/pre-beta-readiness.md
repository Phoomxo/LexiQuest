# LexiQuest ก่อน Beta

**ผลประเมิน ณ 14 พฤศจิกายน 2026: ยังไม่พร้อมเปิด Beta.** เส้นทางหลักของรุ่น
v32 ใช้บน vivo ได้ตั้งแต่เปิดแอปถึงเก็บคำ ฝึก และเปิดผลซ้ำออฟไลน์
งานที่ยังขาดคือเส้นทางตามแบบครบชุด การตรวจ TalkBack จากเสียงจริง
และการยืนยันบริการใน staging ที่ได้รับอนุญาต การอนุมัติ Beta แยกจาก
การอนุมัติใช้ข้อมูลหรือรับผู้เข้าร่วมวิจัย

รุ่นที่ตรวจบนอุปกรณ์คือ source `189fd79d89d38711b9b7bbcf708b0a4c3b1c7bf9`,
APK 32 SHA-256 `e8e04089e4e2bc821be18bec2714065fe0ff29f66dfc6a01314d6e53d6fa2154`.
Windows และ Linux CI ของ source นี้ผ่าน Flutter 2,268 กรณี
และ backend CPU 267 กรณี. [Draft PR #16](https://github.com/Phoomxo/LexiQuest/pull/16) ·
[CI](evidence/ci-189fd79d.txt) · [อุปกรณ์จริง](evidence/vivo-189fd79d.md)

รุ่นทดสอบล่าสุดบน vivo คือ v34 จาก source
`04d2a19962a3501ba5d1ec676ca26b8ec97e1fe0`, APK SHA-256
`5c1d7bd0a515d9586d88ff0380dce170bc6a978beb2e21c73bf6309668f9c05d`.
ทดสอบป้ายถูก/ผิดจาก Android hierarchy บน v33 และการปฏิเสธกล้องหนึ่งครั้งบน
v34 แล้ว ทั้งสองครั้งกลับมาชุด A ที่มี 4 คำและผล 75%. v34 ยังตรวจว่า bookmark
อยู่หลังเปิดใหม่ออฟไลน์ และเอาออกจากรายการได้โดยเก็บคำเดิมไว้ใน A.
[Score semantics](evidence/s7-score-semantics.txt) ·
[ผลตรวจสิทธิ์กล้อง](evidence/s7-camera-denial.txt)

## ผลรายรหัส

| ทะเบียน | ผ่าน | ไม่ผ่าน | ยังไม่ยืนยัน | รอเงื่อนไข |
| --- | ---: | ---: | ---: | ---: |
| [48 หน้าจอ](evidence/screens.csv) | 0 | 15 | 33 | 0 |
| [44 ฟีเจอร์](evidence/features.csv) | 3 | 5 | 35 | 1 |
| [64 ชุดงาน](evidence/work-packages.csv) | 9 | 0 | 41 | 14 |

รหัสที่ไม่ผ่านมีทางเข้าหรือพฤติกรรมสำคัญขาดในซอร์สปัจจุบัน.
ตัวอย่างได้แก่ Cloze, Word Scramble และ World Map ที่ยังไม่มีเส้นทางปกติ
ครบถึงกิจกรรม และฟีเจอร์กรองระดับ ตั้งจำนวนข้อ เตือนทบทวน กับแชร์การ์ด.
การตรวจช่องทางเข้าทั้งหมดพบ 33 หน้าที่มีทางเข้าจากแอป รวมหน้าที่มี
เส้นทางต่างจากแบบ. หลักฐานการใช้กล้อง คลัง และ Quiz บน v32 อยู่ใน
แถวของแต่ละหน้า. การตรวจครบเกณฑ์หน้าจอยังต้องรวมจุดเข้าเดิม ทางกลับ
และการเข้าถึงตามที่ระบุในแต่ละแถว. f10 รอการปิดงานวิศวกรรม Research
และคำขอแยกจากเจ้าของโครงการ

## เกณฑ์ก่อน Beta เก้าข้อ

| ข้อ | ผลที่ยืนยันได้ | งานค้างและเจ้าของ |
| --- | --- | --- |
| 1 โค้ดและหนี้ทางเทคนิค | อ่าน source/review จนครบ 156 รหัส พบช่องว่างของทางเข้าและสถานะ. Migration ผ่าน independent review. แก้ป้ายถูก/ผิด (16 เทสต์) และการขอสิทธิ์กล้องซ้ำ (71 เทสต์) แล้วตรวจซ้ำบน vivo | ทีม Flutter ปิดทางหลักที่ขาดและปรับขอบช่องค้นหากับปุ่มเพิ่มคำในธีมสว่าง ซึ่งวัดได้ราว 1.3:1 |
| 2 สถาปัตยกรรมและฐานข้อมูล | สคีมา v11/v12 และอีกสามรูปแบบจาก v25 ผ่านเปิดซ้ำ/เก็บข้อมูลเดิม. ความล้มเหลวก่อน commit ย้อนครบ. มี 38 ตาราง, local export 36 และ cloud deletion 26. owner switch, export, delete, sync และคงใบรับเดิมผ่านด้วยข้อมูลสังเคราะห์ | เก็บขอบเขตการกู้คืนไว้กับรุ่น. ใช้ forward recovery ที่รองรับ v26 เมื่อ migration สำเร็จแล้ว |
| 3 Security และ compliance | Gitleaks ตรวจ 22 commits ของสาขาแบบปกปิดข้อมูลและไม่พบ leak. Firestore 33 และ Auth 3 ผ่านใน demo emulator. Supabase reset/lint/advisors/storage ผ่านที่ CI. Research start deny-all | OSV พบ advisories ใน lockfiles เดิม และ npm audit พบ 18 รายการ ได้แก่ high 7, moderate 10, low 1. ทีม security/backend ต้องทวน runtime reachability และแก้ dependency ตามผลจริงก่อน Beta |
| 4 UX, design system และ edge cases | ภาพคู่เดิมใช้สถานะตรงกันบน Android emulator. vivo v32 ตรวจไทย 200% และกด Score Back หลังเลื่อน. v33 รักษาชุด A ในแนวนอนและส่งป้ายถูก/ผิดใน semantics. v34 กดปฏิเสธกล้องครั้งเดียวแล้วกลับ A ได้ | ผู้ทดสอบมือถือเทียบแบบในสถานะเดียวกันรอบใหม่ ตรวจแนวนอนทั้งเส้นทาง และฟัง TalkBack จบรอบ โดยตรวจเสียงสถานะคำตอบและโฟกัสหลังย้อน |
| 5 Backend และ API | CPU suites ตรวจ bearer, owner scope, request length, timeout/retry, safe errors และ readiness แบบ local. Auth และ deletion ใช้ fixture สังเคราะห์ | ผู้ดูแล staging ตรวจ provider, App Check, quotas, budget alerts, kill switch และหลาย replica ในโครงการที่อนุญาต. Readiness ของ AI ตรวจ configuration |
| 6 Performance และ load | vivo v32 เปิด process-cold 5 รอบ Activity median 606 ms ช่วง 524–621 ms ทุกครั้งพบ Home และ Library A4/B0. PSS Home 141,421–147,543 KiB และ Library 125,826–129,843 KiB. API test ภายในโปรเซสมี 600 requests ที่ concurrency 1/2/4 และไม่มี error | ทีม performance เก็บ first interactive frame, รายการใหญ่, memory แบบหลายช่วงและ latency จริงใน staging. Library 2,394–2,912 ms รวม ADB และรอ UI dump. ขาด baseline อุปกรณ์/ข้อมูลเดียวกัน จึงยังเทียบ budget ไม่ได้ |
| 7 Analytics | ตรวจ EventEnvelopeV2, consent และ no-research tests ในแอป รวมการพัก outbox ของข้อมูลเดิม. ทดสอบสังเคราะห์ในเครื่อง | ผู้ดูแล staging ต้องยืนยัน synthetic events ถึง dashboard ให้ถูก dataset และ alert ทำงานก่อนนับ operational analytics ว่าพร้อม. การทดลองผลวิจัยต้องมี authority ต่างหาก |
| 8 Functional, automated และ acceptance | Flutter Windows/CI, backend CPU, policy และ APK v32 ผ่านการตรวจตามหลักฐานแนบ. ถ่ายจริงแล้วกรอกเองและยืนยัน notebook, ฝึกได้ 75%, กลับ A, เปิดใหม่ออฟไลน์ B0. รอบที่พักไว้กลับข้อ 2 | ความแม่นยำของกล้องเป็น `not_checked`. UAT ยังไม่มีผู้ใช้สังเกตจริง. ใช้โจทย์ด้านล่างเมื่อผู้ประสานงานจัดรอบได้ |
| 9 CI/CD, environments และ release | APK ลงนามด้วยใบรับรองเดิมและแฮชติดตั้งตรง. exact-head CI ผูกกับหลักฐานแต่ละรุ่น. สัญญา field-release ผ่าน 68 และ signing ผ่าน 56. Cloud sync ปิดใน APK และ Research deny-all | ผู้ดูแล release ต้องทดสอบ package/feedback/stop-switch ใน staging ที่ได้รับอนุญาต. v31 กู้ได้หลัง v30 ล้มก่อน commit. ห้ามนำคู่มือย้อน v7 มาใช้กับฐานที่ย้าย v26 สำเร็จแล้ว |

[แผนตรวจรับ](execution.md#pre-beta-completion-criteria-for-this-goal) ·
[สถาปัตยกรรม](README.md) ·
[บัญชีสคีมา](../../database/schema_ledger.md) ·
[ผล SQLite](evidence/s7-v26-bridge.txt) · [แผนเฝ้าระวัง](../../v2-implementation/monitoring_plan.md) ·
[คู่มือย้อนรุ่น](../../v2-implementation/rollback_playbook.md)

[ภาพคู่ Home](evidence/android-08ce39bc/home-comparison.png) ·
[ภาพคู่คลังคำ](evidence/android-08ce39bc/library-comparison.png) ·
[Impeccable critique](evidence/android-08ce39bc/critique.md)

## แผนทดสอบระบบและ UAT

1. ตรวจ APK hash, signer, versionCode และค่า cloud/Research ก่อนเปิด.
   ใช้ชุดคำ A/B สังเคราะห์. เก็บค่าหน้าจอและเครือข่ายเดิม.
2. เปิด A และผลที่มีอยู่ กดย้อนกลับ A. ถ่ายภาพจาก A แล้วตรวจคำที่จะเก็บ.
   เมื่อไม่มีคำเสนอ ให้กรอกคำสังเคราะห์และกดยืนยัน. ตรวจ A มีคำใหม่และ B เดิม.
3. ฝึกจาก A ตอบถูกและผิด พักเมื่อขึ้นข้อ 2. หลังแอปไม่มีงานเขียนค้างให้ปิด
   โปรเซสแล้วเปิดต่อ. จบรอบแล้วกดผลและกลับ A.
4. เปิดซ้ำออฟไลน์ อ่านคำและผลเดิม. ตรวจ 200%, ธีมสว่างและมืด,
   Android Back และปุ่มกลับในแอป. จดผลของ TalkBack จากเสียงและโฟกัสจริง.
5. สำหรับ UAT ให้ผู้ลองทำโจทย์ “เก็บคำจากสิ่งที่เห็น แล้วฝึกและกลับมาหาผลเดิม”
   ให้ผู้สังเกตบันทึกเวลาจบ ทางที่เลือก จุดที่ขอความช่วยเหลือ ความผิดพลาด
   และทำซ้ำได้เองหรือไม่. เก็บเฉพาะข้อสังเกตที่ผู้ลองอนุญาต.

| ความเสี่ยงจาก review | วิธีทดสอบซ้ำและเกณฑ์ |
| --- | --- |
| SQLite คนละประวัติการอัปเกรด | ใช้ fixture v11, v12, v25 ตรง, v23→v25 และ v25 ที่ v29 ประทับ v10. เทียบ foreign keys/ดัชนี/owner ก่อนและหลัง. บังคับล้มก่อน commit แล้วเปิดซ้ำ ต้องรักษาข้อมูลและ version เดิม |
| คะแนนหรือเครดิตเดิมถูกนำมานับใหม่ | เปิดผล 67% ก่อนเริ่มรอบใหม่. ใช้ fixture ที่มี Assessment, ใบรับเดิม, historical v2 ACK และคิวเก่า. คะแนนและ byte ของรายการเดิมต้องอยู่ ส่วนคำตอบใหม่ได้เครดิตของตัวเองครั้งเดียว |
| ปฏิเสธสิทธิ์แล้วถูกขอซ้ำ | เข้ากล้องจาก A แล้วปฏิเสธหนึ่งครั้ง. ต้องแสดงเหตุผลและให้ผู้ใช้ตัดสินใจลองใหม่เอง. กดย้อนกลับ A แล้วตรวจคำและผลเดิม |
| ผลย้อนหลังสื่อผ่านสีหรือไอคอน | เปิดรอบที่คำตอบเดียวกันมีทั้งถูกและผิด. อ่าน semantics และฟังจาก TalkBack. สถานะของแต่ละคำต้องถูกและโฟกัสกลับมาที่ทางเข้าที่ใช้ต่อได้ |
| เจ้าของหรือบริการเปลี่ยนระหว่างงาน | ใช้ owner A/B สังเคราะห์ สลับระหว่าง Quiz, export และ rehome. ปิดเน็ต/คืน callback ช้า. ห้ามข้าม owner หรือเปิด research upload เมื่อไม่มี permit |

คำสั่งและข้อมูลดิบในเครื่องอยู่ใน `build/s7-v26-*.txt`,
`build/figcraft-189fd79d/` และ `build/figcraft-api-load.py`.
ความหน่วง API เป็นการเรียก ASGI ในโปรเซสด้วย fake provider และ auth.
แต่ละระดับมีห้าชุด ชุดละ 40 requests และ 12 warmups.
ตรวจ response และจำนวนเรียก generator ครบ. p50 อยู่ที่ 1.60–5.79 ms
ตามระดับ concurrency. รอบวัดใช้เครื่อง Windows เดียวกับงานทดสอบ
จึงรายงานเป็นตัวอย่างภาระงานสังเคราะห์ ไม่มีข้อสรุปเรื่องความเร็ว production.

ADLC ใช้ checkpoint และหลักฐานของแต่ละหน่วย. Systematic debugging, TDD
และ verification-before-completion ผูกกับการจำลอง migration และ regression.
Ponytail review ใช้ตรวจคิวส่งและ ledger. Archify/Mermaid อธิบายขอบเขตข้อมูล.
Impeccable กับ mobile-android-design ใช้ตรวจภาพและเป้าแตะบน vivo.
Benchmark-checklist ใช้ตรวจภาระงาน การเกิด request จริง และขอบเขตของเวลา.
