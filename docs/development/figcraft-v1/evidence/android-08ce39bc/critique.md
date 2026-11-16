Method: design review only (detector not applicable, native platform)

# Native Assessment A at 08ce39bc

**Disposition: functional corrections accepted for the observed two-screen slice; FigCraft visual alignment remains partial.** ไม่พบ P0/P1 ที่ขวางงานใน native actions รอบนี้. ยังไม่รับรองว่าตรงแบบครบหรือว่าทั้ง S1/แอปผ่าน acceptance.

ผู้วิจารณ์เปิดดูภาพ Android จริง, ภาพคู่ทั้งสอง และ XML. กด navigation/search/add-menu บน emulator เองตาม [README.md](README.md). ใช้ source `08ce39bcca697d903ec79ca15c52d9ac66b0d391` จาก Git สำหรับ source pointers. งาน S5 ที่กำลังเปลี่ยนใน working tree ไม่อยู่ใน APK และไม่ใช่สิ่งที่ภาพชุดนี้พิสูจน์.

อุปกรณ์คือ LDPlayer `emulator-5590`, BVL-AN16 Android 9. APK versionCode 28, SHA-256 `25b76cb6e177616c42c7855d103d612bdd009ad62bca7e69beef38a69c8c7528`. Capture 624×1350/density256, font100% light สำหรับเทียบ FigCraft 390×844. Native font200% มีทั้ง light/dark และภาพหลังเลื่อน. ทุกภาพใช้ข้อมูลสังเคราะห์ travel3/kitchen0/platform due1 เดิม ไม่มีการเติมคำหรือสร้างคำตอบเพื่อทำภาพ.

## Design specificity และภาพรวม

รุ่นนี้สื่อว่าเป็นคลังคำของผู้เรียนได้ชัดขึ้น. ตัวอย่าง platform/station/ticket, จำนวนคำ และชื่อชุดบน due card ให้ข้อมูลจริงที่ช่วยตัดสินใจ. ทางเพิ่มคำ ค้นคำ และฝึกจากชุดที่ขาดในภาพรุ่นก่อนกดใช้งานได้แล้ว. Empty kitchen แสดง 0 คำอย่างซื่อสัตย์.

ภาพรวมยังเป็น Material UI ที่ใช้ palette ม่วงสดและแถว folder มากกว่าโลกภาพ indigo ที่สงบของ FigCraft. หน้าทั้งสองเริ่มเนื้อหาสูงกว่าแบบ และให้ลำดับน้ำหนักกับชื่อชุด/ปุ่มเพิ่มคำต่างกัน. ช่องว่างและความต่างเหล่านี้มองเห็นได้ในภาพคู่ จึงยังไม่เรียกว่า visual match.

Deterministic scan: not applicable (native platform). ไม่มี browser detector หรือ overlay. ไม่มีภาพ Flutter ที่สร้างด้วย AI.

## Design health score

คะแนนเป็น heuristic judgment ของสองหน้าใน fixture นี้. ไม่ใช่คะแนนผู้เรียนหรือ accessibility certification.

| # | Heuristic | 0–4 | หลักฐานและข้อจำกัด |
| --- | --- | ---: | --- |
| 1 | Visibility of system status | 3 | Due1, ชุดจริง, คำจริง และจำนวนชุดอ่านได้. Loading/error รุ่นนี้ยังไม่ capture |
| 2 | Match system/real world | 3 | เพิ่มคำ/เพิ่มชุดและชื่อการเดินทางแยกชัด. ตัวเลือกเพิ่มมี task จริงให้เลือก |
| 3 | User control/freedom | 3 | Back จากชุดคืน Library พร้อมคำค้น. Cancel เมนูไม่เขียนข้อมูล. ยังไม่ตรวจ interrupted save |
| 4 | Consistency/standards | 3 | Home/Library ใช้หัวเรื่องใหญ่ชิดซ้ายร่วมกันและ Material controls. ลำดับแบบและหน้าชุดภายในยังต่าง |
| 5 | Error prevention | 3 | ย้ายการจัดการชุดไป overflow และเลือก destination ก่อนเพิ่ม. ไม่ได้ทดลองลบ/Save ในรอบนี้ |
| 6 | Recognition rather than recall | 3 | Preview คำ/จำนวนและ due-set context ช่วยจำ. Folder ซ้ำยังช่วยแยกชุดได้น้อยกว่าภาพในแบบ |
| 7 | Flexibility/efficiency | 3 | Global search เปิดชุดที่ตรงและคืน query ได้. Home มี direct set practice. ยังไม่ตรวจชุดคำจำนวนมาก |
| 8 | Aesthetic/minimalist design | 2 | Task ชัดขึ้น แต่ header rhythm, primary CTA, palette และน้ำหนักชื่อชุดยังไม่ร่วมภาพ FigCraft |
| 9 | Error recovery | 2 | Back/cancel ตรวจจริง. Source มี recovery แต่ native new/empty/error/retry ยังไม่อยู่ในชุดนี้ |
| 10 | Help/documentation | 3 | บอกชุดต้นทางและให้นึกก่อนเปิดคำแปล. เมนูกล้อง/ไฟล์บอกเงื่อนไขก่อนเริ่ม |
| | **รวม** | **28/40** | **Acceptable for bounded functional review; visual follow-up required** |

## สิ่งที่รับจากภาพและการกดจริง

- Root Add Word มีอยู่และเปิด destination → เมนูเพิ่มคำในชุดการเดินทางได้. ความบกพร่องด้านทางเข้ารุ่นก่อนปิดแล้วในขอบเขตที่สังเกต.
- Global search platform คืนผลพร้อมชื่อชุด. เลือกแล้วได้ชุดการเดินทางที่ filter platform. Back คืน Library และ query เดิม. Home direct set action สลับไป Library ได้ที่ font200% ธีมมืด.
- Home ไม่เสนอ weakness เมื่อ fixture ไม่มีคำตอบผิด. แสดงชื่อชุดจริงเหนือ platform โดยไม่เปิดคำแปล. Preview คลังมีคำจริงและจำนวน 0 ของ kitchen ไม่เติมเนื้อหาตัวอย่างแทนข้อมูล.
- Thai body text ที่ตรวจไม่ถูกตัดทั้ง light/dark 200%. Card และ labels ขยาย/ขึ้นบรรทัดใหม่ และกิจกรรมที่เลื่อนพ้นจอยังเลื่อนถึงได้. Dark action text และ due CTA อ่านได้จากภาพจริง โดยไม่อ้างค่าคอนทราสต์เชิงตัวเลขจากภาพ.

## P2 · จัด baseline และจังหวะแนวตั้งให้ร่วมแบบ

**พบจริง:** ในภาพคู่ที่ใช้ frame เท่ากัน หัวเรื่อง Flutter เริ่มสูงกว่า FigCraft. Search, หัวข้อชุด และรายการคลังจึงอยู่สูงและรวมตัวกันกว่าแบบ. Home due heading/card และฝึกเพิ่มเติมก็เริ่มเร็วกว่าแบบ ทำให้พื้นที่ว่างใต้เนื้อหามากขึ้น.

**ผลต่อผู้เรียน:** หน้าปัจจุบันใช้ได้ แต่จังหวะการสแกนและสัดส่วนความสำคัญยังต่างจากสิ่งที่อนุมัติใน FigCraft. การเพิ่ม spacing เพื่อเลียนภาพเดียวโดยไม่คำนึง safe area จะทำให้ 200% แย่ลง.

**ก่อนรับ visual alignment:** กำหนดว่า system status bar/insets อยู่ในพื้นที่เทียบส่วนใด แล้วใช้ spacing roles เดียวกันสำหรับหัวเรื่อง/เนื้อหาสองแท็บ. เทียบ anchor หลักที่100% และคงการเลื่อน/การ wrap ที่200%. ไม่เติม spacer ตายตัวเพื่อบังคับตำแหน่งเฉพาะภาพนี้.

Source ที่จับภาพ: `lib/screens/choose_mode_screen.dart:104–120`, `lib/screens/categories_page.dart:53–95`, `lib/config/m3_theme.dart:8–24` ที่ commit08ce39bc. Suggested command: `$impeccable layout`.

## P2 · ชื่อชุดและ Add Word ยังมีน้ำหนักต่ำกว่าแบบ

**พบจริง:** FigCraft ให้ชื่อชุดและรูปประจำชุดเด่น พร้อมปุ่มเพิ่มคำแบบ filled ที่หัวหน้า. Flutter ใช้ชื่อชุดขนาด titleMedium, folder outline ซ้ำ และคำสั่งเพิ่มคำแบบ text ที่มีน้ำหนักใกล้เพิ่มชุด. Preview และจำนวนดีขึ้น แต่ชื่อชุดยังเล็กเมื่อเทียบหัวหน้าและพื้นที่ว่างรอบรายการ.

**ผลต่อผู้เรียน:** ผู้ใช้ใหม่ต้องค้นด้วยสายตามากขึ้นเพื่อแยกคำสั่งเพิ่มคำจากเพิ่มชุด. สองชุดต่างกันได้จากข้อความ แต่ยังไม่มีภาพช่วยจำระดับเดียวกับแบบ.

**ก่อนรับ visual alignment:** ทำชื่อชุดเป็นลำดับภาพหลักของแต่ละแถว และให้ Add Word เป็น primary creation action ตามแบบ. ใช้สินทรัพย์จาก design ที่มีที่มาหรือภาพกลางที่ไม่อ้างว่าเป็นภาพของคำผู้ใช้. คง overflow แทนปุ่มลบที่แย่งสายตา และคงเป้าแตะ/ข้อความ200%.

Source ที่จับภาพ: `lib/screens/categories_page.dart:65–71`, `:253–274`. Suggested command: `$impeccable typeset`, `$impeccable polish`.

## P2 · Card composition, CTA shape และ palette ยังคนละน้ำเสียง

**พบจริง:** มุม due card16ใกล้แบบแล้ว แต่ native เป็นคอลัมน์ข้อความกับ CTA เต็มความกว้างทรง pill. แบบวางคำ/ประโยคกับภาพในสองส่วนและใช้ CTA มุมโค้งน้อยกว่า. Primary `#5A4CF2` และ Material lavender ในแอปสดกว่าสี indigo/cool lavender ใน reference. Search ใช้ tonal fill ขณะที่แบบเป็นพื้นขาวกรอบบาง.

**ผลต่อผู้เรียน:** ทั้งสองหน้าเป็นระเบียบ แต่สีและรูปทรงให้บุคลิกต่างจากแบบเดียวกัน. การ์ดทบทวนดึงสายตามากกว่าลำดับของงานในคลัง.

**ก่อนรับ visual alignment:** เทียบ palette/shape roles กับ reference แล้วใช้ร่วมทั้งสองหน้า. รักษา primary/onPrimary คู่ที่อ่านได้ใน dark theme และรักษา CTA ที่ขยายตามข้อความ. ไม่บังคับปุ่มเล็กเท่าภาพ100% เมื่อใช้200%.

การไม่ใส่ประโยค “Meet me on platform two.” และภาพสถานีเป็นข้อมูลผู้เรียนใน fixture นี้ **ยอมรับได้** เพราะ runtime ไม่มีประโยค/รูปที่ผูก provenance ให้คำนี้. ให้แยกการไม่มีข้อมูลจริงออกจากความต่างด้าน palette/shape. ไม่แก้ด้วย hardcoded demo content ที่ดูเหมือนคำจากคลัง.

Source ที่จับภาพ: `lib/screens/choose_mode_screen.dart:185–220`, `lib/config/m3_theme.dart:27`, `:52–65`, `:115–124`. Suggested command: `$impeccable colorize`, `$impeccable polish`.

## Cognitive load และ personas

ผู้เริ่มเรียนเห็นงานหลักทบทวนหนึ่งงาน แล้วมีทางฝึกจากชุดและอ่านเพิ่มเติม. ไม่มี weakness ที่ยังไม่มีหลักฐานมาขอให้ตัดสินใจ. เมนูเพิ่มคำแยก destination ก่อนวิธีเพิ่ม จึงเพิ่มหนึ่งขั้นแต่ทำให้ทราบว่าจะเก็บที่ใด. เป็น adaptation ที่รับได้สำหรับคลังจริงหลายชุด.

ผู้ที่กลับมาหาคำเดิมใช้ search แล้ว Back ได้โดยไม่เสีย query. คำตัวอย่างในแถวช่วยเปิดชุดถูกขึ้น. ข้อที่ยังแย่งสายตาคือชื่อชุดเล็กเมื่อเทียบ primary header และโครงสร้างภาพ folder ที่ซ้ำกัน.

ผู้ใช้ตัวอักษรใหญ่เห็น Home hero เกือบเต็ม viewport และต้องเลื่อนอ่านกิจกรรม. เลื่อนแล้วอ่านได้ครบทั้ง light/dark. Library headingขึ้นสองบรรทัดตามพื้นที่. ไม่แนะนำให้ cap body text เพื่อให้เหมือนภาพ100%. นาฬิกา system status bar ถูกตัดใน emulator ที่200% จึงแยกเป็นข้อสังเกตของ Android9 ไม่อ้างว่าแอปหรือ system bar ผ่านทั้งหมด.

## Accessibility และขอบเขตที่ยังไม่ตรวจ

XML ของ controls หลักมีเป้าแตะประมาณ48dpหรือใหญ่กว่า เช่น app-bar action77pxที่ density256 และ navigation tabs156×128px. บาง bounds200% ถูกปัดเป็น76px. ส่วนแถวที่พ้น viewport ไม่ใช้ visible fragment มาตัดสินขนาดเป้าแตะ.

XML ยังมี standard semantic strings ภาษาอังกฤษ เช่น Back, Dismiss และ Tab x of4. Empty search EditText ไม่มี hint ใน XML dump นี้. เป็นรายการตรวจต่อด้วย TalkBack จริง โดย XML อย่างเดียวไม่พอจะสรุปว่าไม่มี accessible name หรือเสียงพูดผิดภาษา. รอบนี้ไม่ได้เปิด TalkBack และไม่อ้าง focus order/การฟังเข้าใจ/full journey ผ่าน.

ยังไม่ตรวจ native loading/error/new-owner/empty-library, ocean theme, จำนวนคำมากหรือข้อความยาว, interrupted save, camera model accuracy, การฝึกจนจบ และ restart-result ของ emulator ในงานสองหน้านี้. หลักฐาน vivo ของ root ไม่ได้นำมาเพิ่มคะแนนหรือเปลี่ยนขอบเขตการประเมินนี้.

## Run notes

- Native Assessment A อย่างเดียวตาม native routing. ไม่มี Assessment B, detector, browser visibility หรือ overlay ที่อ้างว่าใช้งานได้.
- Impeccable context ใช้ผลที่อ่านไว้ก่อนหน้า. ไม่รัน context ซ้ำ. ไม่พบ `.impeccable/critique/ignore.md`. ไม่เขียน `.impeccable` snapshot นอก write set ที่อนุญาต; เก็บรายงานที่นี่แทน.
- รูปดิบมาจาก `build/capture_android.py` โดย XML ก่อน PNG. ภาพคู่มาจาก `tool/figcraft/compare_android.py` เดิม. ไม่แก้สอง helper และไม่มี local web server.
- Capture เฉพาะ LexiQuest ที่ตรวจแล้วอยู่ใน manifest. Probe ที่ไม่ใช่ LexiQuest ไม่อยู่ในหลักฐาน. Helper ทิ้ง UUID XML ชั่วคราวบน emulator; ไม่ลบไฟล์เก่าด้วย pattern กว้าง.
- Installer/emulator recovery และการคืนค่าอยู่ใน README/metadata. คืน device ownership แล้ว. ไม่มี ADB writes ต่อระหว่างจัดทำรายงาน.

Questions skipped: ขอบเขต native review และ write set ถูกกำหนดแล้ว. ข้อแตกต่างด้านภาพส่งให้ root จัดลำดับต่อ โดยไม่ขอให้ผู้ใช้ยืนยันงานที่อนุญาตอยู่แล้ว.
