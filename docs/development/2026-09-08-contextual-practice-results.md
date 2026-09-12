# ผลการผสม WordQuest กับการฝึกประโยคและเสียงใน LexiQuest

วันที่ 8 กันยายน 2026 — ผสม UI และการฝึกประโยค/เสียงเสร็จ การทดสอบอัตโนมัติและ APK ผ่านแล้ว; ยังไม่ตรวจรับบนอุปกรณ์จริง

## สิ่งที่นำมาใช้

นำแนวคิดจาก [English Game for Kids / WordQuest — Spelling Adventure](https://github.com/tarntanate/English-Game-For-Kids) ที่กู้ลิงก์จากประวัติเดิมได้ มาผสมกับลำดับฝึกเติมประโยคและฟัง/พูดที่ผู้ใช้เสนอโดยอ้างอิง Duolingo เขียนภายในระบบ Flutter เดิม ไม่คัดลอกโค้ด รูปภาพ หรือชุดคำศัพท์ภายนอก

- **เรียงตัวอักษร:** การ์ดคำใบ้จากความหมายจริง พร้อมชนิดคำที่มีอยู่ ตัวอักษรกับช่องคำตอบแยกกัน แตะหรือลากได้ และแตะตัวในช่องเพื่อคืนกลับไปยังตำแหน่งเดิม แม้มีตัวอักษรซ้ำ คำ 6 ตัวอยู่แถวเดียวที่ขนาดปกติ และแบ่งแถวเมื่อขยายตัวอักษร
- **เติมประโยค:** เลือกรูปแบบตอบก่อนเห็นชุดคำ จากนั้นเลือก/เปลี่ยนคำได้จนกด “ตรวจคำตอบ” มีการ์ดประโยคและปุ่มหลักชัดเจน ทางเลือกพิมพ์คำยังคงกติกาหลักฐานการจำด้วยตนเองเดิม
- **ฟังและลองพูด:** แสดงหลังคำตอบหลักบันทึกสำเร็จ ฟังประโยคต้นฉบับที่ผ่านการตรวจแล้ว ฝึกพูด หยุด ลองใหม่ หรือข้ามได้ แสดงข้อความที่ระบบได้ยินโดยไม่อ้างคะแนนความแม่นยำการออกเสียง
- **ควบคุมเสียง:** ยกเลิกผลจากข้อเก่าเมื่อเปลี่ยนข้อ ออกจากหน้า แอปพัก หรือสิทธิ์ฟีเจอร์เปลี่ยน ทุกเส้นทางหยุด/คืนทรัพยากรเสียงรอการหยุดชุดเดิมก่อนเริ่มชุดใหม่ ถ้าหยุดไม่สำเร็จจะไม่เริ่มสื่อทับกัน ผู้เรียนยังไปข้อต่อไปได้

ผลฝึกพูดเพิ่มเติมเป็นสถานะชั่วคราว ไม่มีการบันทึกเสียง/ข้อความพูดลงประวัติ ไม่มีคะแนน ผลทบทวน หรือรายการวิจัยเพิ่ม การทดสอบร่วมกับฐานข้อมูลยืนยันว่าฟัง/พูดซ้ำและกดข้ามไม่เพิ่ม answer/points/reward/SRS/speech rows และสองข้อปิด session เดิมเพียงหนึ่งรายการ

เกมสะกดคำกับเติมประโยคยังเป็นกิจกรรมเดิมคนละประเภท ไม่เปิดบทเรียนต่ออัตโนมัติหลังสะกดคำจบ ไม่เพิ่มระบบหัวใจ เหรียญ หรือผู้คุมคะแนนอีกชุด คงแค็ตตาล็อก 8/44 และสัญญาข้อมูลเดิม ไม่มี schema/dependency ใหม่

## ผลตรวจหลังตรึง UI

| ชุดตรวจ | ผล |
| --- | --- |
| Focused integration และหน่วยที่เกี่ยวข้อง | 131 ผ่าน รวม panel29 กรณีและการเดินสองข้อด้วยฐานข้อมูล/บริการเสียงผ่าน facade จริงกับ gateway จำลอง |
| Accessibility smoke ทั้งไฟล์ | 33 ผ่าน รวมจอ240x640/text200 และ reduced motion |
| Analyzer | ผ่านครบ7ราก source จริง: lib, test, integration_test, test_driver, assets, tool, tools; ไม่รวมสำเนาเก่าใน build และไม่แก้กฎ lint |
| ภาพ UI | 4 renderer tests ผ่าน; ตรวจ14ภาพที่390x844/text100 และ360x800/text200 รวมสถานะเลือกคำ ผลคำตอบ และข้อความฝึกพูด |
| Full regression สุดท้าย | **4,964 ผ่าน / 0 ล้มเหลว / 0 ข้ามในผลที่รัน**, error events0, parse failures0, doneSuccess=true; 463.92วินาที |
| เส้นทางใช้งานบน host | Core, feature controls และ media ทั้ง3ผ่านหลัง UI เสร็จ ใช้หน้าจอจริง/ข้อมูลสังเคราะห์และ fake media |
| แผนตรวจ8/44และfeature map | สร้าง/ตรวจผ่านตาม generator เดิม feature-map revision1.3.0 |
| Android APK | `flutter build apk --debug --no-pub` ผ่านใน92.64วินาที เป็นแอปปกติจาก main.dart; source fingerprint ตรงทุก gate |

คำสั่ง full regression ยังคง `--exclude-tags release-excluded` ซึ่งเว้น4กรณี native/platform เดิม ไม่รวมในยอด0 SKIP และไม่มีการเพิ่มข้อยกเว้นเพื่อให้ผ่าน การทดสอบครั้งนี้ไม่ได้รัน backend/CLI ใหม่; หลักฐานเดิมอยู่ในรายงาน UI ก่อนหน้า เนื่องจากงานนี้ไม่แก้โค้ดสองส่วนนั้น

## ตัวตนซอร์สและหลักฐาน

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`, HEAD `788e90e62b1694c20945734787723c168b6a6ab2` ไม่มี commit ใหม่

เทียบกับ baseline UI ที่ตรวจผ่านก่อนเริ่มงานนี้ พบการเปลี่ยน12ไฟล์: 7lib/5test รายชื่อและ SHA256 อยู่ใน `build/verification/contextual-practice-20260908/incremental-source-identity.json` พร้อม diff เทียบ baseline งานเก่า เก็บการเปลี่ยนที่มีมาก่อนทั้งหมดไว้

ผลตรวจสุดท้ายใช้ source fingerprint `eefb9a48384ad47230c66514e34ab7e0c590d8a8d219e81fe9b340de4783977e` จำนวน1,166ไฟล์ ตรวจ before/after ว่าคงที่ในแต่ละ gate ดูรายการคำสั่ง เวลา และตำแหน่งหลักฐานใน [final-gates.json](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/contextual-practice-20260908/final-gates.json)

- [ผลและรายการ full regression](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/contextual-practice-20260908/full-final.summary.json), [inventory](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/contextual-practice-20260908/full-final.inventory.json)
- [การตรวจภาพ](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/contextual-practice-20260908/visual-review.md), [ภาพสะกดคำ](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/contextual-practice-20260908/visual/390-text100-04-spelling.png), [ภาพเติมประโยค](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/contextual-practice-20260908/visual/390-text100-02-selected.png)
- [ผลตรวจอิสระ](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/contextual-practice-20260908/final-system-review.md), [ประวัติความล้มเหลวและการแก้](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/contextual-practice-20260908/recovery-history.md)

รอบ full แรกผ่าน4,962และล้มเหลว2จากตัวทดสอบที่ยังค้นหาชื่อปุ่มช่วยอ่านภาษาอังกฤษเดิม เปลี่ยน finder เป็นไทยและเลื่อนด้วย key ก่อนตรวจและกด โดยเก็บ assertions เรื่องขนาด motion semantics และผลตัวอักษรครบ ทั้งสองผ่านเฉพาะส่วนและผ่านใน full สุดท้าย ไม่มีการลบหรือทำให้ assertions อ่อนลง

Drift warning print events88 เท่ารายงาน UI ก่อนหน้าและ full รอบแรกของงานนี้ เก็บคำเตือนตามจริง ไม่ปิดคำเตือนเพื่อให้ผลผ่าน

APK: [lexiquest-contextual-practice-debug.apk](C:/Users/Phet/.codex/worktrees/02fa/LexiQuest/build/verification/contextual-practice-20260908/lexiquest-contextual-practice-debug.apk), 261,486,867 bytes, SHA256 `5bfa355b3f8e2cfd843f5be76e664599d1f1117d1e54b50be1dcc23ddf16ed08` ตรวจตรงกับ app-debug.apk ที่สร้างครั้งนี้แล้ว รายละเอียดอยู่ใน final-apk-identity.json ไม่มีการติดตั้งบนโทรศัพท์

Build ยังเตือน KGP compatibility ใน Flutter รุ่นอนาคตสำหรับ firebase_app_check, flutter_tts, speech_to_text, workmanager_android และ SDK XML รุ่น3/4ต่างกัน เหมือนงาน UI ก่อนหน้า ไม่ทำให้ build ปัจจุบันล้มเหลวและไม่ได้เปลี่ยน dependency ในงานนี้

ผลตรวจอิสระขั้นสุดท้าย: **APPROVE** ตรวจ hashes ของ12ไฟล์ ผลทั้ง9gates และ hash/ขนาด APK ตรงจริง ปิดข้อพบเรื่องลำดับหยุดเสียงและความหมายของตัวทดสอบครบ ไม่พบข้อบกพร่องสำคัญค้างในขอบเขตที่ตรวจ

## สิ่งที่ยังต้องตรวจบนเครื่องจริง

ADB ไม่พบอุปกรณ์ระหว่างงานนี้ จึงยังไม่ได้ติดตั้ง APK หรือยืนยันเสียง ไมโครโฟน การอนุญาตของ Android, TalkBack, native picker หรือประสิทธิภาพบน vivo ผลในรายงานนี้ไม่แทน UAT หรือการทดสอบใช้งานต่อเนื่อง3ชั่วโมงบนเครื่องจริง และ14ภาพครั้งนี้เป็นภาพหน้าที่เกี่ยวข้อง ไม่ใช่การตรวจรับทุกหน้า/ทุกปุ่มบนโทรศัพท์

เมื่อ vivo เชื่อมต่อ ขั้นถัดไปคือยืนยันตัว APK/ข้อมูลเดิมก่อนติดตั้งแบบรักษาข้อมูล แล้วตรวจสะกดคำ เติมประโยค ฟัง/พูด/ข้าม สลับแอปและสิทธิ์ไมค์ รวมถึง TalkBack ร่วมกับผู้ใช้ตามความพร้อมที่เคยให้ไว้

ไม่มี deploy, เปิดรับผู้เข้าร่วม, อัปโหลดข้อมูลจริง หรือเรียก Codex Security workflow ในงานนี้
