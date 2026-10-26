# LexiQuest Revision 5 — Responsive/Adaptive Contract (Android)

สถานะ: สัญญาการออกแบบและเกณฑ์รับงานสำหรับ Figma Revision 5 และการนำไปพัฒนา Flutter

อัปเดต: 2026-10-18

ขอบเขต: Android-first เท่านั้น; iOS อยู่นอกขอบเขตของ revision นี้

## 1. วัตถุประสงค์และหลักตัดสิน

Revision 5 ต้องปรับโครงหน้าจอตาม **พื้นที่หน้าต่างที่แอปใช้ได้จริง ณ runtime** ไม่ใช่ชื่อรุ่นอุปกรณ์ ความละเอียดที่โฆษณา เส้นทแยงมุม หรือคำว่า phone/tablet/foldable เพียงอย่างเดียว ลำดับการตัดสินคือ:

1. อ่านขนาด window ในหน่วย dp และค่าระบบจาก runtime
2. หักพื้นที่ที่ใช้ไม่ได้จาก system insets, IME และ display features ที่บังเนื้อหา
3. จัด width/height size class จาก window ปัจจุบัน
4. ใช้ posture เพื่อแบ่งพื้นที่ที่เหลือเป็น safe regions
5. เลือก navigation และ pane pattern จากพื้นที่ใช้งานจริง
6. รักษา route, selected destination, scroll, text draft และ task progress เมื่อ resize, rotate, fold หรือ unfold

สัญญานี้ต่อยอดจาก `docs/design/figma-responsive-layout-audit.md:12-19,62-90,127-141,163-198`, `DESIGN.md:17-25` และ `docs/research/2026-10-18-figma-community-revision-5.md:35-55` หากตัวอย่างภาพขัดกับกฎ runtime ในเอกสารนี้ ให้ยึดกฎ runtime

## 2. ค่าที่ต้องแยกออกจากกัน

ห้ามใช้คำว่า “ขนาดหน้าจอ” แทนค่าหลายชนิดต่อไปนี้โดยไม่ระบุหน่วยและแหล่งที่มา

| ค่า | ความหมาย | ใช้ตัด breakpoint หรือไม่ |
| --- | --- | --- |
| Physical pixels (`px`) | ขนาด surface/framebuffer หรือภาพ screenshot ที่จับได้ อาจไม่เท่าความละเอียด native ของ panel | ไม่ใช้; บันทึกเป็นหลักฐานเท่านั้น |
| Density | `devicePixelRatio`/density DPI ที่แปลง physical pixels กับ logical dp | ไม่ใช้เดี่ยว ๆ; บันทึกคู่กับแหล่งที่มา |
| Window dp | logical width/height ของหน้าต่างแอป ณ runtime ก่อนหัก insets ภายใน | **ใช้** จัด width/height size class |
| Insets | `viewPadding`, `padding`, `viewInsets` แยกบน/ขวา/ล่าง/ซ้าย รวม status bar, navigation/gesture area, cutout และ IME | ใช้คำนวณ content bounds; ไม่ใช่ breakpoint ใหม่ |
| Posture / display features | สถานะ cover, book, tabletop, single/dual/triple และ bounds ของ fold/hinge/cutout พร้อมชนิดการบัง | ใช้แบ่ง window เป็น safe regions หลังจัด size class |
| Orientation | ความสัมพันธ์ของ width กับ height ณ ขณะนั้น | ใช้เป็นข้อมูลทดสอบ; ห้ามใช้แทน size class |

`usable bounds` ของ pane ต้องมาจาก window dp หลังหัก insets, navigation shell, gutters และ exclusion bounds ที่ runtime รายงาน ห้ามแปลงจากความละเอียด physical pixels ด้วยค่าความหนาแน่นที่เดาเอง

## 3. Runtime evidence record

การรับรองบนอุปกรณ์จริงทุก posture ต้องแนบ record เดียวกับ screenshot หรือ screen recording อย่างน้อยดังนี้:

```text
device_model
android_version_and_build
app_version_or_commit
physical_display_or_capture_surface_px + source
device_pixel_ratio_or_density_dpi + source
window_dp_before_internal_insets
view_padding_dp {top,right,bottom,left}
padding_dp {top,right,bottom,left}
view_insets_dp {top,right,bottom,left}
display_features[] {type,state,bounds_dp,occlusion}
orientation
posture
multi_window_state
text_scale
system_navigation_mode
timestamp
```

ถ้า physical pixel มาจาก screenshot surface ให้ระบุเช่นนั้นและห้ามเรียกว่า native panel resolution ค่าที่ไม่มีหลักฐานให้เขียน `not captured` แทนการอนุมาน

### 3.1 ชั้นทดสอบ LDPlayer

ใช้ LDPlayer 9 เป็น test harness สำหรับ phone/tablet resolution, DPI, orientation และ text scale โดยใช้โปรไฟล์แยกจาก instance เดิม รายการที่สร้างและคำสั่งอยู่ใน [`lexiquest-revision-5-ldplayer-matrix.md`](lexiquest-revision-5-ldplayer-matrix.md)

- Phase 1: 360×800, Vivo 393×876 และ 412×915dp
- Phase 3 tablet: 600×960, 800×1280, 1024×1366 และ 1280×800dp
- height boundary: 800×479 และ 800×480dp

ค่าที่ตั้งใน LDPlayer เป็น fixture input เท่านั้น ต้องอ่าน app window/insets จริงซ้ำเมื่อรัน การเปลี่ยน manufacturer/model ไม่ถือเป็นหลักฐาน hinge, seam, cutout หรือ posture ของรุ่นนั้น จอพับและจอสามพับจึงต้องใช้ Android foldable emulator ที่รายงาน display features หรืออุปกรณ์จริงประกบกัน

## 4. Breakpoint ที่มีหลักฐานรองรับ

ช่วงต่อไปนี้มาจาก Android window size classes ที่บันทึกไว้ใน `docs/design/figma-responsive-layout-audit.md:30-37,62-77` และเป็น breakpoint ชุดเดียวของ revision นี้

### 4.1 Width class

| Width class | Window width | โครงหลัก | Navigation | Grid / gutter |
| --- | ---: | --- | --- | --- |
| Compact | `<600dp` | single pane; เนื้อหารองต่อท้ายใน scroll | NavigationBar 4 จุดหมาย | 4 คอลัมน์; 16dp ที่ 320–359dp, 20dp ที่ 360–599dp |
| Medium | `600–839dp` | single pane จัดกลาง; grid อาจเพิ่มเป็น 2 คอลัมน์ | NavigationRail แบบ icon + label | 8 คอลัมน์; gutter 24dp |
| Expanded | `840–1199dp` | list-detail/supporting pane เมื่อ usable bounds ผ่านขั้นต่ำ | NavigationRail | 12 คอลัมน์; gutter 32dp |
| Large | `1200–1599dp` | two-pane ใน shell สูงสุด 1200dp; เพิ่ม negative space แทนการยืดข้อความ | NavigationRail; persistent drawer ใช้ได้เมื่อ IA รองรับ | 12 คอลัมน์; gutter 48dp |

ยังไม่มีหลักฐานใน repository นี้สำหรับการตั้งชื่อ breakpoint ใหม่ที่ `≥1600dp` จึงห้ามสร้าง class เพิ่มเอง ระหว่างรอ runtime evidence ให้ใช้พฤติกรรม large แบบอนุรักษ์นิยมโดยคง shell สูงสุด 1200dp และทำเครื่องหมายผลว่า “fallback — ยังไม่รับรอง breakpoint ใหม่”

### 4.2 Height class และกฎ override

| Height class | Window height | กฎ |
| --- | ---: | --- |
| Compact height | `<480dp` | single pane เสมอ, NavigationBar ด้านล่าง, ลด vertical gaps หนึ่งระดับ, body เลื่อนได้ และ CTA ห้ามทับ prompt |
| Medium height | `480–899dp` | ใช้กฎตาม width; two-pane ได้เมื่อแต่ละ pane ผ่าน minimum usable size |
| Expanded height | `≥900dp` | แสดง context/supporting pane ได้มากขึ้น แต่ primary task ต้องเด่นเพียงหนึ่งงาน |

เมื่อ width กับ height ให้รูปแบบขัดกัน กฎ compact height ชนะ เช่น window 800×360dp ยังเป็น single pane + NavigationBar (`docs/design/figma-responsive-layout-audit.md:73-82`)

### 4.3 Pane และ content limits

- ใช้ spacing บนฐาน 4dp และ component spacing หลัก 8dp
- touch target ทุก control อย่างน้อย 48×48dp และช่องว่างระหว่าง target อย่างน้อย 8dp
- list pane อย่างน้อย 320dp, detail pane อย่างน้อย 480dp และ pane gap 24–32dp หลังหัก rail, gutters, insets และ hinge; ถ้าไม่พอให้กลับเป็น single pane
- content max width: form 560dp, prose 640dp, primary task 720dp, ผู้ช่วยเรียนด้วย AI 760dp และ shell รวม 1200dp
- ตัวอย่าง expanded landscape 1280×800dp ใช้ list:detail ใกล้ 42:58, gutter 24dp เป็น visual target ไม่ใช่สูตรบังคับ เมื่อเนื้อหาหรือ exclusion zone ทำให้ pane ต่ำกว่าขั้นต่ำต้อง reflow

## 5. กฎร่วมของทุก phase

### 5.1 Safe area, keyboard และ text scale

- background วาดแบบ edge-to-edge ได้ แต่ข้อความ input, CTA, dialog center และ selection control ต้องอยู่ใน safe content bounds
- scroll content ต้องมี bottom padding อย่างน้อย `fixed navigation/action height + bottom inset + 16dp`
- ช่องพิมพ์ของผู้ช่วยเรียนด้วย AI และ input อื่นต้องยกตาม `viewInsets.bottom`; keyboard ห้ามทับข้อความร่าง ปุ่มยืนยัน หรือข้อความล่าสุด
- ต้องทดสอบ text scale 100%, 130% และ 200%; ข้อความสำคัญต้อง wrap, component ต้องสูงขึ้นตามเนื้อหา และห้ามใช้ ellipsis เพื่อซ่อน prompt, feedback, error หรือ primary action
- ห้ามล็อกความสูง card จากสัดส่วนภาพต้นแบบ หากข้อความ 200% ต้องการพื้นที่เพิ่ม ให้ card โตหรือให้ body scroll

### 5.2 Fold, hinge และ cutout

- ใช้ bounds และ occlusion ที่ runtime รายงานตามจริง ห้ามเดาความกว้าง hinge จากรุ่นอุปกรณ์
- display feature ที่ occluding เป็น exclusion zone เต็ม bounds; ไม่มีข้อความ ปุ่ม focus indicator dialog center หรือ selection control คร่อม
- feature ที่ไม่ occluding ยังเป็น visual seam: ห้ามวางคำหรือ CTA สำคัญพาด seam และต้องพิสูจน์การอ่านต่อเนื่องด้วย screenshot
- คำนวณ safe regions ตาม geometry จริง ห้ามสมมติว่าจอ dual/triple แบ่งครึ่งหรือแบ่งสามส่วนเท่ากัน
- การ fold/unfold และย้ายระหว่าง cover/main display ต้องไม่สร้าง route ซ้ำ reset task หรือส่งคำตอบซ้ำ

### 5.3 Navigation และ state

- 4 top-level destinations คงชุดเดียวกัน: เรียน, คลังคำ, ก้าวหน้า, โปรไฟล์
- การเปลี่ยน NavigationBar ↔ NavigationRail เป็นการเปลี่ยน shell layout ไม่ใช่ navigation event
- selected destination, list selection, scroll anchor, quiz answer/progress, AI conversation/draft และ focus ที่สมเหตุผลต้องคงอยู่หลัง resize/rotate/posture change
- nested focused task ใช้ app bar + Back; ห้ามแสดง back arrow ซ้ำใน detail pane ที่ list ยังอยู่ข้างกัน

## 6. Phase 1 — Vivo V2041 และ compact baseline

### 6.1 Canonical runtime

Vivo V2041 ใช้ **393×876dp** เป็น canonical window ของ Revision 5 ตามขอบเขตงานนี้ ขนาดนี้หมายถึง window dp ไม่ใช่ physical pixels และไม่รวมคำสัญญาว่า content area จะสูง 876dp เต็ม หลังหัก runtime insets งานวิจัยปัจจุบันบันทึก app area ไว้เพียง “ประมาณ 393×809dp” (`docs/research/2026-10-18-figma-community-revision-5.md:35-53`) ดังนั้น implementation ต้องอ่านค่าจริงและไม่ตรึง offset 67dp

ผลที่คาดหวังที่ 393×876dp:

- width Compact + height Medium
- single pane, NavigationBar 4 จุดหมาย และ horizontal gutter 20dp
- content width ก่อน component max-width ไม่เกิน 353dp (`393 - 20 - 20`)
- app bar 64dp อยู่ภายใน app area; shell root ที่มี navigation ใช้ NavigationBar 80dp เป็นเป้าหมายภาพและต้องบวก bottom inset แยก
- หน้าเรียนเห็นงานที่ทำต่อในครึ่งบน; แบบฝึกเห็นคำถาม ตัวเลือก และปุ่มหลักโดยไม่ชนกัน; ผู้ช่วยเรียนด้วย AI เห็นบริบท ที่มาของคำตอบ บทสนทนา และช่องพิมพ์; หน้าสรุปแสดงผลลัพธ์ก่อนรายละเอียดรอง

physical pixels, density และ insets ของเครื่อง Vivo ต้องบันทึกจาก runtime record ก่อนรับรอง hardware; เอกสารนี้ไม่กำหนดค่าทั้งสามแทนการวัด

### 6.2 Compact checks

| Test window | Class | Layout ที่ต้องได้ | จุดตรวจเฉพาะ |
| --- | --- | --- | --- |
| 360×800dp | Compact width + Medium height | single pane, NavigationBar, gutter 20dp; ลดเป็น 16dp ได้เฉพาะเมื่อ constraint เนื้อหาพิสูจน์ความจำเป็น | ไม่มี horizontal overflow; title ไม่ชน action; CTA อยู่เหนือ inset; label navigation อ่านครบ |
| 393×876dp | Compact width + Medium height | canonical ตามข้อ 6.1 | hierarchy, proportions และ safe-area behavior เป็น baseline |
| 412×915dp | Compact width + Expanded height | single pane, NavigationBar, gutter 20dp; เพิ่ม breathing room โดยไม่เปลี่ยน hierarchy | card ไม่ยืดสูงเพื่อเติมจอ; ไม่มี negative-space block ใหญ่; primary action ยังชัดหนึ่งจุด |

ต้องมี compact-height test เพิ่ม เช่น rotate/multi-window ที่ height 479dp และ 480dp เพื่อพิสูจน์ override และ boundary behavior โดยไม่อ้างว่าเป็นขนาดจริงของ Vivo

## 7. Phase 2 — Samsung fold/dual posture

Phase นี้ใช้ window size class และ display features ที่ runtime ส่งมาเท่านั้น **ไม่มีการกำหนด exact Samsung dp ในสัญญานี้** เพราะ repository ยังไม่มีหลักฐานดังกล่าว ทุก posture ต้องสร้าง runtime evidence record ก่อนตัดสิน expected class

| Posture | การจัด layout |
| --- | --- |
| Cover | จัด class จาก cover window ที่วัดได้จริง; ห้ามสมมติว่า Compact แม้มักมีลักษณะคล้ายโทรศัพท์ หาก runtime เป็น Compact ให้ใช้ single pane + NavigationBar |
| Book / unfolded | ใช้ vertical fold/hinge bounds แบ่ง safe regions; ใช้ list-detail ได้เมื่อพื้นที่หลังหัก rail/gutters/hinge ยังเหลือ list ≥320dp และ detail ≥480dp มิฉะนั้นใช้ centered single pane |
| Tabletop | ใช้ horizontal fold/hinge bounds; ไม่วาง dialog, prompt หรือ CTA คร่อม seam ค่าเริ่มต้นเป็น single pane หาก effective height เป็น Compact การแยก upper content/lower controls ทำได้เฉพาะ flow ที่พิสูจน์ reading order และ TalkBack order |
| Dual/spanned | ประเมินแต่ละ safe region แยกกัน; rail อยู่ขอบนอกของ region และ primary action อยู่กับ pane เจ้าของงาน ห้ามคำนวณจากความกว้างรวมที่รวม hinge |
| Split screen / freeform | จัด class ใหม่ทุกครั้งจาก window ปัจจุบัน; state ต้องคงอยู่เมื่อ drag ผ่าน 599/600 และ 839/840dp |

เกณฑ์ผ่าน hardware phase นี้ต้องมีอย่างน้อย cover → book → tabletop → cover หนึ่งรอบต่อ main flow สำคัญ โดยไม่มี state loss, duplicate submit, clipped text หรือ control ข้าม exclusion zone

## 8. Phase 3 — Huawei Mate XT และ tablet

### 8.1 Mate XT single/dual/triple

ชื่อ posture ใช้เพื่อจัดชุดทดสอบ ไม่ใช้กำหนด breakpoint:

| Posture | สัญญา |
| --- | --- |
| Single | อ่าน window dp/insets/display features แล้วใช้ size class ปกติ; physical panel pixels ห้ามเป็นตัวเลือก layout |
| Dual | รองรับรายการ display feature ตาม runtime อาจมีหนึ่งหรือหลาย seam; เลือก single/two-pane จาก usable safe regions จริง |
| Triple | รองรับ display features หลายรายการและคำนวณ connected safe regions; ห้ามสมมติสามส่วนเท่ากัน ห้ามยืด primary content เกิน max width และห้ามเพิ่ม pane เพียงเพื่อเติมพื้นที่ |

แต่ละ posture ต้องทดสอบ portrait/landscape เท่าที่ระบบเปิดให้หมุนจริง และต้องทดสอบ transition single ↔ dual ↔ triple โดยรักษา state หาก window กว้าง `≥1600dp` ให้ใช้ large fallback ที่ shell ≤1200dp พร้อมติดป้าย evidence ว่า breakpoint เหนือ 1599dp ยังไม่ผ่านการรับรอง ห้ามเรียก class ใหม่นอกหลักฐาน

### 8.2 Tablet small/medium/large

คำว่า small/medium/large tablet ในแผนทดสอบหมายถึงกลุ่มจาก **runtime width class** ไม่ใช่ขนาดนิ้วหรือชื่อผลิตภัณฑ์:

| กลุ่มทดสอบ | Runtime class | Portrait | Landscape |
| --- | --- | --- | --- |
| Small tablet | Medium `600–839dp` | rail + centered single column ≤720dp; long-form ≤640dp | จัดใหม่ตาม width/height ปัจจุบัน; compact height บังคับ single pane + bottom navigation |
| Medium tablet | Expanded `840–1199dp` | rail; single pane หรือตั้ง supporting pane เมื่อ minimum ผ่าน | rail + conditional list-detail; ตรวจ 42:58 เป็น visual target ไม่ใช่ fixed ratio |
| Large tablet | Large `1200–1599dp` | shell ≤1200dp, rail และ conditional two-pane | shell ≤1200dp; เพิ่ม outer negative space แทนยืด cards/prose |

ใช้ 600×960, 800×1280, 1024×1366 และ 1280×800dp เป็น synthetic fixtures ตาม [`lexiquest-revision-5-ldplayer-matrix.md`](lexiquest-revision-5-ldplayer-matrix.md) ได้ แต่ผล emulator/Figma ไม่แทน runtime record ของ tablet จริง และค่าทั้งหมดหมายถึง target window dp ไม่ใช่ physical resolution

## 9. Acceptance matrix

สถานะในตารางเป็น gate ที่ต้องพิสูจน์ ไม่ใช่ผลทดสอบที่ผ่านแล้ว

| Phase | Target / posture | Runtime evidence ที่ต้องมี | Expected layout | Acceptance gate |
| --- | --- | --- | --- | --- |
| 1 | Vivo V2041 393×876dp portrait | window dp, physical/capture px, density, insets, nav mode, text scale | Compact/Medium; single pane + NavigationBar | baseline screenshots ทุก main screen, 100/200% text, safe area และ IME ผ่าน |
| 1 | Synthetic 360×800dp | fixture metadata | Compact/Medium; single pane | no overflow, touch ≥48dp, navigation/action ไม่ทับ content |
| 1 | Synthetic 412×915dp | fixture metadata | Compact/Expanded; hierarchy เดิม | ไม่มี stretched card หรือ negative-space block ใหญ่ |
| 1 | Boundary/compact-height | 599/600, 839/840, 1199/1200; height 479/480, 899/900 | เปลี่ยน shell ตาม class; height override ทำงาน | route/selection/state ไม่เปลี่ยน และไม่มี collision |
| 2 | Samsung cover | record ที่วัดจริง; exact dp ไม่กำหนดล่วงหน้า | ตาม runtime class | safe insets, 100/200% text และ cover transition ผ่าน |
| 2 | Samsung book/unfolded | record + vertical feature bounds/occlusion | conditional list-detail | ไม่มี element คร่อม hinge; pane minima ผ่านหรือ reflow เป็น single |
| 2 | Samsung tabletop | record + horizontal feature bounds/state | single pane เป็น fallback; split regions เมื่อพิสูจน์ได้ | reading/TalkBack order, CTA ownership และ keyboard ผ่าน |
| 2 | Samsung split/dual | record ทุก window state | reclassify จาก window ปัจจุบัน | resize ต่อเนื่อง, state คงอยู่, ไม่มี duplicate submit |
| 3 | Mate XT single | record ที่วัดจริง | ตาม runtime class | physical pixels ไม่เปลี่ยน decision; safe area ผ่าน |
| 3 | Mate XT dual | record + display feature list | conditional one/two-pane | คำนวณ safe region จริง; ไม่มี assumption แบ่งครึ่ง |
| 3 | Mate XT triple | record + display features ทุก seam | ตาม runtime class และ usable safe regions; เมื่อกว้าง ≥1600dp ใช้ large fallback shell ≤1200dp | ไม่มี content ข้าม seam; state คงอยู่ทุก transition |
| 3 | Small tablet portrait/landscape | actual window records ใน Medium class | centered single pane + rail ยกเว้น compact height | max width, rotation state และ keyboard ผ่าน |
| 3 | Medium tablet portrait/landscape | actual window records ใน Expanded class | rail + conditional supporting/list-detail | pane minima, selection-detail consistency และ no duplicate Back ผ่าน |
| 3 | Large tablet portrait/landscape | actual window records ใน Large class | two-pane conditional ใน shell ≤1200dp | outer whitespace สมดุล; prose/cards ไม่ถูกยืด |

## 10. Cross-screen acceptance checks

Figma Page 1 และ Flutter implementation ถือว่าผ่านสัญญานี้เมื่อมีหลักฐานครบทุกข้อที่อยู่ใน phase นั้น:

- [ ] หน้าเรียน ภารกิจประจำวัน แบบฝึก ผลย้อนกลับ สรุปการฝึก คลังคำ ผู้ช่วยเรียนด้วย AI ความก้าวหน้า โปรไฟล์ และการตั้งค่า มี compact state ที่ 360×800, 393×876 และ 412×915dp
- [ ] root navigation เปลี่ยน bar → rail ที่ 599/600dp โดย selected destination และ route เดิมยังอยู่
- [ ] single → conditional two-pane ที่ 839/840dp เกิดเฉพาะเมื่อ height ≥480dp และ usable pane widths ผ่าน 320/480dp
- [ ] boundary 1199/1200dp เปลี่ยน gutter/shell โดยไม่ยืด content เกิน max width
- [ ] height 479/480 และ 899/900dp ไม่มี prompt, CTA, feedback, composer หรือ navigation ถูกตัด
- [ ] text scale 100%, 130% และ 200% ไม่มี overflow, clipped text, fixed-height collision หรือ ellipsis บนข้อความสำคัญ
- [ ] touch target ≥48×48dp, target gap ≥8dp และ focus/TalkBack order ตรงกับ visual reading order
- [ ] gesture navigation และ 3-button navigation ไม่ทำให้ fixed UI ทับ content
- [ ] เมื่อเปิดแป้นพิมพ์ที่เข้าสู่ระบบ/สมัครสมาชิก เพิ่มคำ ค้นหา และผู้ช่วยเรียนด้วย AI ช่องพิมพ์กับปุ่มทำงานต้องพ้น keyboard
- [ ] portrait/landscape, split screen และ posture transition รักษา selected tab, scroll anchor, typed text, list selection, quiz progress และ AI thread
- [ ] ทุก occluding hinge/cutout ถูกหักจาก usable bounds และไม่มี element สำคัญคร่อม
- [ ] list-detail มี selection ที่ตรงกัน, detail ไม่แสดง Back ซ้ำ และ primary action อยู่ใน pane เจ้าของงาน
- [ ] screenshot ของอุปกรณ์จริงแนบ runtime evidence record เดียวกัน; ภาพ Figma/emulator ไม่ถูกใช้กล่าวอ้างว่า hardware ผ่าน

## 11. แนวทางเชื่อมกับ Flutter

- ใช้ `MediaQuery.sizeOf(context)` สำหรับ window dp และอ่าน `viewPadding`, `padding`, `viewInsets`, text scaling และ `displayFeatures` จาก runtime
- ใช้ `LayoutBuilder` เมื่อตัดสิน constraint ภายใน pane; อย่าใช้ device model หรือ `OrientationBuilder` เป็นตัวเลือก root layout
- คำนวณ breakpoint ที่ adaptive shell จุดเดียว แล้วส่ง constraints/pane role ลง component เพื่อหลีกเลี่ยงแต่ละหน้าตัดสินต่างกัน
- อย่าล็อก orientation; ให้ shell reflow และเก็บ state ด้วย route/state owner เดิม
- tests ต้องใช้ logical dp fixtures และ display-feature fixtures แยกจาก physical-device acceptance

โค้ดปัจจุบันยังไม่ถือว่าปฏิบัติตามสัญญานี้เพียงเพราะ Figma มี rail หรือ foldable frame; audit เดิมไม่พบ adaptive switch ใน `lib/` (`docs/design/figma-responsive-layout-audit.md:49-56`) การรับรอง implementation ต้องอิง behavior และ tests จาก source snapshot ที่พัฒนาจริง
