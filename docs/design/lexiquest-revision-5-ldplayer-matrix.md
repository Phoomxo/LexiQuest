# LexiQuest Revision 5 — LDPlayer device matrix

สถานะ: สร้างโปรไฟล์ทดสอบแล้วเมื่อ 2026-10-18 โดยไม่แก้ instance เดิมชื่อ `LDPlayer`

ขอบเขต: ใช้ LDPlayer 9 สำหรับตรวจ resolution, density, orientation, text scale และ responsive layout ของ phone/tablet เท่านั้น ส่วน fold/hinge/posture ต้องตรวจด้วย Android foldable emulator ที่รายงาน display features หรืออุปกรณ์จริง

## หลักตัดสิน

- ชื่อยี่ห้อและรุ่นใน emulator เป็น metadata สำหรับจัดชุดทดสอบ ไม่ใช่หลักฐานว่า geometry ของอุปกรณ์จริงถูกจำลองครบ
- ค่าในคอลัมน์ `Target dp` เป็นค่าที่คำนวณจาก resolution และ DPI เพื่อเตรียม fixture; ตอนรันต้องบันทึก window dp, system insets และ app bounds จริงอีกครั้ง
- เปิดทดสอบครั้งละหนึ่ง instance เพื่อลดความแปรปรวนด้านหน่วยความจำและ GPU
- ใช้ข้อมูลสังเคราะห์เท่านั้น ห้ามใส่บัญชีจริง ข้อมูลผู้เรียนจริง หรือข้อมูลงานวิจัยจริงใน emulator

## โปรไฟล์ที่สร้าง

| Phase | LDPlayer instance | Resolution / DPI | Target dp | ใช้ตรวจ |
| --- | --- | ---: | ---: | --- |
| 1 | `LQ-P1-Vivo-393x876` | 1080×2408 / 440 | ≈393×876 | canonical Vivo V2041 |
| 1 | `LQ-P1-Compact-360x800` | 1080×2400 / 480 | 360×800 | compact lower check |
| 1 | `LQ-P1-Compact-412x915` | 824×1830 / 320 | 412×915 | compact upper check |
| 3 | `LQ-P3-Tablet-S-600x960` | 1200×1920 / 320 | 600×960 | small tablet lower boundary |
| 3 | `LQ-P3-Tablet-SU-800x1280` | 1600×2560 / 320 | 800×1280 | small tablet upper check |
| 3 | `LQ-P3-Tablet-M-1024x1366` | 2048×2732 / 320 | 1024×1366 | medium tablet two-pane candidate |
| 3 | `LQ-P3-Tablet-L-1280x800` | 2560×1600 / 320 | 1280×800 | large tablet landscape list-detail |
| Boundary | `LQ-Boundary-H479` | 1600×958 / 320 | 800×479 | compact-height side of boundary |
| Boundary | `LQ-Boundary-H480` | 1600×960 / 320 | 800×480 | medium-height side of boundary |

โปรไฟล์สร้างด้วย [`Configure-LexiQuestProfiles.ps1`](../../tools/ldplayer/Configure-LexiQuestProfiles.ps1) ซึ่งทำงานแบบ idempotent ตรวจผลจาก `ldconsole list2` และไม่ลบ instance ใด

## วิธีรันทดสอบ

1. สร้างหรือปรับโปรไฟล์ซ้ำได้ด้วย:

   ```powershell
   & .\tools\ldplayer\Configure-LexiQuestProfiles.ps1 -Apply -IncludeBoundaryProfiles
   ```

2. เปิด instance เป้าหมายเพียงตัวเดียว ติดตั้ง APK debug ที่สร้างจาก source state เดียวกัน และใช้ข้อมูลสังเคราะห์
3. บันทึกอย่างน้อย `wm size`, `wm density`, app window dp, insets, orientation, text scale, screenshot และ commit/build id
4. ตรวจเส้นทางหลัก หน้าเรียน → แบบฝึก → ผลย้อนกลับ → สรุปการฝึก รวมคลังคำ ผู้ช่วยเรียนด้วย AI ความก้าวหน้า โปรไฟล์ และการตั้งค่า
5. หมุนแนวตั้ง/แนวนอนและเปลี่ยน text scale 100%, 130%, 200% โดยยืนยันว่า route, selected answer, draft, scroll และ progress ไม่หาย

ตัวอย่างคำสั่งตรวจผ่าน CLI:

```powershell
& 'C:\LDPlayer\LDPlayer9\ldconsole.exe' adb --name 'LQ-P1-Vivo-393x876' --command 'shell wm size'
& 'C:\LDPlayer\LDPlayer9\ldconsole.exe' adb --name 'LQ-P1-Vivo-393x876' --command 'shell wm density'
& 'C:\LDPlayer\LDPlayer9\ldconsole.exe' adb --name 'LQ-P1-Vivo-393x876' --command 'shell dumpsys window displays'
```

## Foldable และ tri-fold

LDPlayer รองรับการตั้ง resolution, DPI, manufacturer/model และ autorotate ผ่าน CLI แต่การตั้ง model ไม่ได้สร้าง hinge, occlusion bounds หรือ posture transition ให้ Android โดยอัตโนมัติ จึงใช้ลำดับนี้:

1. ใช้ LDPlayer ตรวจว่าหน้าเดียวกัน reflow ถูกเมื่อ width/height เปลี่ยน
2. ใช้ Android foldable/resizable emulator ตรวจ `displayFeatures`, book/tabletop posture และ state continuity
3. ใช้ Samsung/Huawei จริงเมื่อมีเครื่อง เพื่อยืนยัน system bars, cutout, seam และพฤติกรรมเปลี่ยน posture

แหล่งอ้างอิงคำสั่ง LDPlayer: [Command Line Interface](https://www.ldplayer.net/support/introduction-to-ldplayer-command-line-interface.html), [การสลับแนวตั้ง/แนวนอน](https://www.ldplayer.net/support/how-to-switch-from-landscape-to-portrait.html), [ตัวอย่าง tablet resolution](https://www.ldplayer.net/support/set-up-tablet-resolution-for-better-gaming-experience-in-golden-spatula.html)
