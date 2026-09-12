# ปรับเมนูภาษาไทยและการจัดวาง — 2026-09-08

Worktree `02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`, base HEAD `788e90e62b1694c20945734787723c168b6a6ab2`. งานนี้เป็นการแก้ UI ตามคำขอผู้ใช้ และคงงานแก้ media viewport / Adventure performance ก่อนหน้าไว้ ไม่มี commit หรือ deployment ในรอบนี้

## สิ่งที่เปลี่ยน

- Choose Mode / โปรไฟล์ / ตั้งค่า: การ์ดห่างกัน 12 px เพิ่มพื้นที่ภายใน และให้หัวข้อ/ตัวเลือกธีมขึ้นบรรทัดเมื่อพื้นที่ไม่พอ
- หน้าตั้งค่าก่อนเรียน: หัวข้อ ป้ายตัวเลือก ปุ่ม ข้อความกู้กิจกรรม และข้อความตั้งค่าใหม่เป็นไทย; dropdown รองรับข้อความยาวและขนาดตัวอักษร 200% โดยคงค่า enum และนโยบายเดิม
- หัวข้อหน้าลูก: แบบทดสอบ จับคู่ อ่านเชื่อมโยงความจำ ภารกิจ เตือนเวลาเรียน ตั้งค่า AI และรายละเอียดชุดเนื้อหาเป็นไทย กิจกรรมในชุดเนื้อหาอ้างคำจาก NavigationGlossary เดิม
- กล่องยืนยันลบข้อมูลและสถานะระบบออนไลน์เป็นไทย ไม่มีการเปลี่ยนการลบข้อมูลหรือสิทธิ์การใช้งาน
- หลังตรวจภาพจริงพบแถบสถานะทับนาฬิกา: shell ใช้ SafeArea และแถวเมนูที่จัดพื้นที่ชัดเจนแทนปุ่มลอยบนเนื้อหา ป้ายเมนูล่างใช้ขนาด 12 px
- ตัวเปิดทดสอบบน vivo แยกหมวดเสียง/จับคู่ ระยะระหว่างหมวด 24 px ปุ่มสูงอย่างน้อย 56 px และเว้นระหว่างปุ่ม 12 px
- ตรวจเครื่องแล้วพบตัวเปิดทดสอบนำ DisplayPreferencesController ที่ถูก dispose กลับมาใช้เมื่อเปิดแอปซ้ำ: เพิ่ม `MyApp.ownsDependencies` (ค่าเริ่มต้น true คงการปิดทรัพยากรเดิม) ตัวเปิดทดสอบใช้ false และเป็นผู้ dispose เอง ตรวจการเปิดซ้ำและ default disposal ด้วย tests

## หลักฐาน

หลักฐานทั้งหมดอยู่ใต้ `build/verification/remediation-20260907/`

- RED ก่อนแก้: การ์ดเดิมห่าง 8 px, กล่องลบข้อมูล/หัวข้อตั้งค่าก่อนเรียนยังเป็นอังกฤษ
- `ui-final-tests-20260907T172203925Z`: **490 PASS**, source stable, 80.033 s; ครอบคลุม `test/screens`, `test/navigation`, Thai glossary boundary, session configuration sheet/policy
- RED จากแถบบน: `build/verification/ui-layout-20260908-inset-red.log` พื้นที่ข้อความเริ่ม y=8 ทั้งที่ status inset=32
- `ui-final-shell-20260907T172946814Z`: **38 PASS**, source stable, 19.405 s หลังแก้ SafeArea/ตำแหน่งเมนู
- `ui-final-shell-20260907T173808455Z`: **48 PASS**, source stable, 20.879 s รวมการเปิดซ้ำและ ownership cleanup
- `ui-final-analyze-20260907T173832689Z`: **No issues**, source stable, 28.986 s
- Source comparison ระหว่างชุด 490 และชุด 38 ต่างเพียง `main_navigation_screen.dart`, test ของหน้านี้ และ generated final-plan 2 ไฟล์ จึงทดสอบซ้ำเฉพาะ shell ที่แก้
- หลังชุด 38 แก้เพิ่มเฉพาะ ownership ที่ `main.dart`, manual launcher และ test `app_build_info_test.dart`; ชุด 48 รวม tests เหล่านี้และ shell เดิม
- Fingerprint ปัจจุบันของ 1,162 source/evidence inputs: `2d9b61bc5af391e61a574597a3a3b67d68bb10da5749cb20449d3f9e5197f113`
- Canonical final-plan fingerprint: `4c6c7f082a1dfd53d82f4c6a649f3fa0cfd1bfa7ddf2261cc85985acd38ab0d2`; HEAD ที่บันทึกเป็นฐานของ working tree ไม่ใช่ commit ของการแก้ครั้งนี้

เก็บผลที่ไม่ผ่านระหว่างปรับไว้: assertion อังกฤษเก่าใน tests ได้แก้ให้ตรงป้ายไทย; test โปรไฟล์เลื่อนถึงแต่ละหัวข้อก่อนตรวจ semantics ไม่ลด/ข้าม assertion การทำงาน

## ขอบเขตของผล

การขยายตัวอักษร 200% เป็น widget test บน viewport 360×800 ไม่ใช่การรับรอง TalkBack/Switch Access โดยผู้ใช้ ชุด 4,852 PASS ก่อนหน้านี้เป็นหลักฐานก่อนแก้ UI ไม่ใช่ผลรันใหม่ของงานนี้

การทดสอบกล้อง ไมโครโฟน การได้ยินเสียง และ TalkBack ที่ต้องมีคำตอบผู้ใช้ยังเปิดอยู่ ผู้ใช้เคยตอบพร้อมแล้ว ไม่ต้องถามความพร้อมซ้ำ ไม่ได้ถือคำขอปรับ UI เป็นผลยอมรับ UAT หรืออนุมัติ release/research

## สถานะเครื่องและขั้นถัดไป

ติดตั้งและตรวจรุ่น `manual-ui-v6` บน vivo V2041 (`9582188822004C6`) แล้ว โดยใช้แหล่งข้อมูลทดสอบแยกเดิม Build `manual-ui-v6-build-20260907T173905348Z` ผ่าน 52.128 s ด้วย fingerprint เดียวกับชุด 48 และ analyzer รุ่นที่ค้างอยู่เป็น manual QA ไม่ใช่ production release

ติดตั้งด้วย `adb install -r -t`, ตรวจ signer และ installed SHA-256 ตรงกับ archive: `50a42c1ce50ae84038bddf36f4df02209fa0eb7cf1a4a12ca69e8a1b443c2559` หลักฐาน `manual-ui-v6-device/setup.json`, PID 30492 ณ ตรวจเสร็จ ยังไม่คืน original APK เพื่อให้ผู้ใช้ตรวจ UI/ทำ UAT ต่อ

ภาพจริงใน `manual-ui-v6-device/`: `first-open.png`, `launcher-after-back.png`, `reopened.png`, `learning-menu.png`, `session-settings.png` ตรวจแถบบนไม่ทับนาฬิกา/ปุ่มเมนู, ป้ายเมนูล่างพอดี, การ์ดมีช่องว่าง, แบบฟอร์มไทยแสดงครบ และกดย้อนกลับมา launcher แล้วเปิด MyApp ซ้ำโดยไม่พบหน้าจอ error เดิม ปิดแบบฟอร์มด้วยปุ่ม X และเปิดหน้าเลือกกิจกรรมไว้ให้ผู้ใช้

ไม่มี Flutter/test/build process ของงานนี้ค้างอยู่ `git diff --check` และ generated final-plan `--check` ผ่านหลังงานนี้ ดูรายชื่อ tracked changes รวมงานเดิมใน `manual-ui-v6-device/changed-files.txt` งานถัดไปคือรับข้อเสนอแนะ UI หรือดำเนิน human UAT ที่ยังเปิดอยู่ตามคำสั่งผู้ใช้

เก็บ original APK สำรองไว้ที่ `build/verification/788e90e62b1694c20945734787723c168b6a6ab2/device-20260907/v2041-installed-before-testing.apk`, SHA-256 `632edb07f6882890c98e467871f98da02502c792df9dadbb854b9f40f17872a1` และรักษา roots ใน manifest `code_cache/lexiquest-manual-uat-owned-20260907.json` ไม่ uninstall/clear data ไม่เปิด cloud/research upload
