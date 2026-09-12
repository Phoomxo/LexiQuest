# ผลแก้บักที่พบระหว่างทดสอบบน vivo

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`, HEAD `788e90e62b1694c20945734787723c168b6a6ab2` งานเดิมที่ยังไม่ commit คงอยู่ ไม่มี deploy/เผยแพร่/เก็บข้อมูลวิจัยจริง

## สิ่งที่แก้และเหตุผล

| จุด | พฤติกรรมหลังแก้ | หลักฐานเฉพาะจุด |
| --- | --- | --- |
| ส่วนหัวบทเรียน | เว้นขอบระบบด้วย SafeArea ทั้งส่วนหัวและเนื้อหา ไม่ทับ status bar | RED ตาม inset24 แล้ว GREEN2 รวม nested AppBar ที่ไม่เว้นซ้ำ |
| ฝึกพูด | ผลชั่วคราวไม่สร้างคะแนน/เปิดจบกิจกรรม; ผล final ล้างเฉพาะข้อผิดพลาดรู้จำเสียง; ไม่ซ่อนปัญหาอ่านเสียง/บันทึกผล | RED4 → GREEN32, ตรวจ idempotent retry และ late callbacks |
| เปิดกล้องกลับจาก inactive | เก็บเหตุโมเดลไม่พร้อมของ lease เดิม แล้วคืนปุ่มดาวน์โหลดเมื่อกลับหน้าเดิม | RED1 → GREEN26 รวม ownership/lifecycle/preprocessing |
| ชื่อวัตถุเป็นคำศัพท์ | exact/alias ที่ตรวจแล้ว แทน substring ที่ทำให้ screwdriver→river, triceratops→rice, king penguin→pen; blank ไม่จับคู่เป็น apple; coffee cup→cup | RED5 → GREEN34; คำศัพท์127รายการเดิมไม่เปลี่ยน |

จำนวนเฉพาะจุดทับซ้อนกัน ห้ามบวกเป็นจำนวน test ไม่ซ้ำ การแก้ mapping ลดคำแปลที่ยังไม่ตรวจโดยตั้งใจ ไม่ใช่หลักฐานว่าโมเดลจำวัตถุแม่นขึ้น ผู้ตรวจอิสระอ่าน source/diff และ log จริงครบใน `build/verification/motivation-ui-20260908/reports/native-*-review.md`

## ตรวจหลังรวม source

ทุก gate ต่อไปนี้ตรวจ source เดียวกัน 1,498 inputs fingerprint `3536599289dbf74d8888d80f8639457eedaf6f16161db69052696e424e16e513`; inner gate1,252 inputs `7c1b2cc7511cb4c5bd5d04c9fe6e1fcbc554a1e13f89d377636b9f8505e23891` บันทึก before/after ตรงกัน

| Gate | ผล / หลักฐาน |
| --- | --- |
| Format / diff | Dart8ไฟล์ ไม่มีการเปลี่ยนจาก formatter; focused diff check ผ่าน |
| Analyzer7roots | PASS `motivation-f2-analysis-20260908T102109279Z` หลังแก้ style lint null-aware collection; failed runก่อนหน้ายังคงไว้ |
| Flutter regression | **5,029 PASS / 0fail / 0skip / 0error / 0parseFailure**, `motivation-f3-full-20260908T102127300Z`,480.12s; parsed inventory `logs/native-followup-f3-final.*` |
| Host journeys | core,controls,media3 flows PASS; `logs/integrations-20260908T102932339999Z/summary.json` |
| Feature / generated plan | 8/44 contract และ current generated plan PASS; `logs/contracts-20260908T103212744836Z/summary.json` |
| Ordinary debug APK | PASS41.45s; `logs/apk-20260908T103227403303Z/summary.json` |

Regression ยังแยก4 release-excluded native/platform cases เดิมออกจากคำสั่ง; 0skip ไม่ได้แปลว่ารันข้อยกเว้นเหล่านั้นใน host มี88 known Drift warnings และ generator fixtures ที่ตั้งใจสร้าง drift แยกจาก parse failures Native model/TTS/inventory tests ของรอบก่อนมีหลักฐานจริงแยกอยู่ แต่ไม่ใช่ accuracy benchmark และไม่ใช่ native rerun ของ source ล่าสุดนี้

Source comparison `reports/native-followup-source-delta.json` พิสูจน์การเปลี่ยนจาก35ac4a80… เพียง4lib+4test+2generated-plan files Backend/policy/dependency/platform/assets ไม่เปลี่ยน จึงอ้างผลชุดก่อนที่ไม่เปลี่ยน input แยกจากการรันซ้ำในรอบนี้ ไม่อ้างว่าเพิ่งรัน backend/Supabase ใหม่

## APK

Archive `build/verification/motivation-ui-20260908/device/lexiquest-native-ui-fixes-debug.apk` SHA256 `b94b5fffd6d4fbdb034669876cb92a9ebe50e575135078c0c20f2b55af6d153b`,261,536,166bytes Package `com.lexiquest.app`,1.0.0/code14, debug signer `1f10bbeedb0b8f18bcbb789c31d862bcfe9a3d146920033fb93eb1d228b0c5b4` ผ่าน aapt2/apksigner จริง เป็น debug artifact ไม่ใช่ release-signed

Manual fixture ที่แยกข้อมูลทดสอบ build PASS33.47s จาก source เดียวกัน: `motivation-c1-manual-native-fixes-debug.apk` SHA256 `89a07a60ad8c434bdab0d490e61d0258bdf1cbfdd5829b30d08b518dcd6beaf1` การติดตั้งครั้งแรกมี USB disconnect หลังส่งไฟล์และ exit255; reconciliation ภายหลังพบ candidate hash จริงและไม่มีคำสั่งติดตั้งค้าง จึงเปิดแอปผ่าน helper โดยไม่ติดตั้งซ้ำ `manual-install-native-fixes-reconciled/install.json` PASS/sourceStable/ไม่มี installIntent คงหลักฐานความไม่แน่นอนครั้งแรกไว้ ข้อมูลแอปเดิมไม่ถูกล้างหรือถอนติดตั้ง

ภาพจริง25/26เห็น launcher ของชุดทดสอบที่ยังขึ้นกำลังเล่นเสียง และการกดเปิดแอปครั้งที่บันทึกไว้ไม่เปลี่ยนเป็นหน้าเรียน การอ่าน UI hierarchy ไม่มีไฟล์ผลลัพธ์หลัง tool รายงาน exit0 เปิด cold restart เฉพาะ APK ที่ตรวจ hash แล้ว; ลอง hierarchy อีกครั้งยังไม่มีไฟล์ ตรวจ TalkBack/accessibility ยัง disabled จึงยังไม่ปิดงาน visual UAT หรือสรุปสาเหตุว่าเป็น native TTS, app freeze หรือ automation โดยไม่มีหลักฐานเพิ่ม Next device diagnosis ต้องเก็บ stdout/stderr ของ uiautomator dump ก่อนอ่านไฟล์ และตรวจ process/log เฉพาะแอป แทนการวนกดหรือติดตั้งซ้ำ

## สิ่งที่ยังไม่รับรอง

- บน APK เดิม e780… ผู้ใช้ยืนยันได้ยินเสียงและรู้จำ station; ภาพจริง23/24ยืนยัน preview/capture/inference แต่ผล joystick34% ไม่ผ่านความถูกต้องของสิ่งของที่ถือ
- UI/ผลเสียงของ APK ที่แก้ใหม่ยังต้องตรวจบนหน้าจอจริง; ไม่อนุมาน UAT จาก host regression
- TalkBack แบบมนุษย์ใช้งานจริงและเส้นทางต่อเนื่อง180นาทียังไม่เสร็จ
- ยังไม่มี dataset/held-out accuracy/calibration ที่รับรอง >90% หรือโมเดลที่ฝึกใหม่ อ่านข้อเสนอ `2026-09-08-object-recognition-accuracy-proposal.md` ซึ่งผู้ใช้เลือกสองกลุ่มแบบรายการจำกัดแล้ว
- รายงาน capture เดิมและผลสอบเชิงสังเคราะห์ไม่ใช่หลักฐานการวิจัยประสิทธิผลหรือการอนุญาตเก็บข้อมูลเด็ก
