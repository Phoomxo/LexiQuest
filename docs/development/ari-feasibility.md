# อารี — ผลตรวจความเป็นไปได้และแผนตรวจรับ

ตรวจเอกสารทางการ 2026-09-20 · ฐานโค้ด E7 `34d520760d55ad14c06a266c0c6bd88152444619`

**ผล: รองรับบางเงื่อนไข แต่ยังไม่มีเส้นทางที่ยืนยันครบสำหรับ LexiQuest บนมือถือ จึงไม่ผ่าน gate เริ่ม V2** นี่คือผลตรวจเอกสาร ไม่ใช่ผลทดลองบัญชีจริง และไม่ใช่ข้อสรุปว่าไม่มีทางทำได้ตลอดไป

## ข้อกำหนดและขอบเขต

- ผู้ช่วยชื่อ **อารี**; สนทนาใน LexiQuest ด้วยบัญชี ChatGPT Free ของผู้ใช้ในไทย ไม่ให้ผู้ใช้สร้าง API key หรือเปิด Developer mode เปิดเบราว์เซอร์เฉพาะล็อกอินได้
- ไม่ใช้ API ที่โครงการจ่ายเงินแทน ไม่เพิ่ม production API/schema/MCP เต็มระบบก่อนผ่าน V0–V1; Gemini อยู่นอกแผน
- ต้นแบบเมื่อผ่าน gate: ข้อความศัพท์ `bottle` หนึ่งคำ ไม่มีภาพ เสียง ข้อมูลวิจัย การแก้คะแนนหรือรางวัล
- แทนที่แผน MCP เดิม 24 งาน M0–M7 ซึ่งให้สนทนาใน ChatGPT; เก็บต้นฉบับและ hash เป็นประวัติใน receipt ภายนอก ไม่ใช่คำสั่งพัฒนาปัจจุบัน
- E7 และการตรวจรับเครื่องจริงที่ค้างยังคงสถานะเดิม งานนี้ไม่ปิด release gate

## หลักฐานและผลเทียบเส้นทาง

| เส้นทาง | สิ่งที่เอกสารรองรับ | ผลต่อข้อกำหนด |
|---|---|---|
| MCP / plugin | ChatGPT หรือ Codex เป็น client เรียก MCP ของเรา โดย OAuth ให้สิทธิ์เข้าถึงทรัพยากรของเรา [S1] | ไม่ใช่สิทธิ์ให้ Flutter เรียกโมเดลด้วยโควตา ChatGPT; แผน host-side เดิมไม่ตรง UX |
| Sign in with ChatGPT | Sites ใช้ identity สำหรับเว็บที่โฮสต์; partner beta แชร์ข้อมูลโปรไฟล์และแยกการอนุญาตเครื่องมือ [S2,S3] | การล็อกอินอย่างเดียวไม่พิสูจน์สิทธิ์ inference ใน native app |
| ChatKit / API | ฝัง chat ได้โดย server สร้าง session ด้วย `OPENAI_API_KEY` [S4] | ไม่ผ่านเงื่อนไขใช้โควตา ChatGPT ของผู้ใช้; ไม่เลือกเป็น paid fallback |
| Codex App Server | ฝัง Codex ในผลิตภัณฑ์ได้ มี managed login, streamed replies, logout และ rate-limit APIs [S5,S6] | เป็น candidate ที่มีหลักฐานจริง ไม่ควรตัดทิ้งเพียงเพราะเป็น Codex; แต่ app-server/WS ระบุ experimental/ไม่รองรับ production และยังไม่มีหลักฐานเส้นทางมือถือของเรา |
| บัญชี Free | เอกสาร pricing รวม Free ในสิทธิ์ Codex; usage ร่วมกับ ChatGPT Work และบางแผนใช้เครดิตต่อได้ [S7] | ไม่กล่าวว่าบัญชีฟรีไม่มีสิทธิ์ แต่ยังไม่ยืนยัน Free ในไทย + native mobile + ห้ามค่าใช้จ่ายครบชุด |

การทดสอบ MCP ที่ยังไม่เผยแพร่มี Developer mode **ใน ChatGPT** [S8] เป็นคนละอย่างกับ Android Developer options ไม่อ้างว่าการเปิดอย่างหนึ่งทำให้แอปธนาคารใช้งานไม่ได้ การเผยแพร่ plugin มีขั้นตอนตรวจ identity, endpoint, ประเทศ และ review [S9]; การผ่าน review ไม่พิสูจน์การฝังโมเดลใน Flutter

สำหรับ candidate App Server: quota เป็นสิทธิ์บัญชีที่ล็อกอินตามแผน ไม่ใช่ quota ที่ MCP สร้างขึ้น การอ่าน rate limit เป็นเพียงข้อมูล ไม่ใช่ spend cap แบบ atomic ข้ามหลายอุปกรณ์ ต้องยืนยันการปิดใช้เครดิต/overage ที่ provider บังคับได้; logout ก็ยังไม่เท่ากับพิสูจน์ remote token revocation

## 4 กลุ่ม / 12 งานย่อย

การดำเนินงานต่อใช้ **หนึ่ง task ต่อกลุ่ม V0–V3** ตาม [workflow ส่งต่อ](ari-task-workflow.md) เริ่มจากช่องว่างของหลักฐานเดิม ไม่เริ่มตรวจทุกเรื่องใหม่; V2 ยังขึ้นกับ gate เดิม

`REVIEWED` = ตรวจเอกสารแล้ว ไม่เท่ากับ runtime PASS; `UNCONFIRMED` = ตรวจแล้วแต่หลักฐานไม่ครบ; `NOT_RUN` = ไม่ได้ทดสอบจริง

| งาน | ผลและเกณฑ์ที่เหลือ | สถานะ |
|---|---|---|
| V0.1 ล็อกอินแอปภายนอก | แยก Sites/partner identity, MCP resource grant และ Codex managed auth [S1–S3,S5] | REVIEWED |
| V0.2 สิทธิ์เรียกโมเดล | Codex auth มี subscription access; API ใช้ API identity แยกกัน [S4–S7] | REVIEWED |
| V0.3 Free ไทยและมือถือ | Free มีในเอกสาร แต่ยังไม่มีหลักฐานเส้นทาง LexiQuest Android/iOS และบัญชีไทยครบชุด | UNCONFIRMED |
| V1.1 quota/ค่าใช้จ่าย | แยก account quota, API billing และ hosting; ป้องกันใช้เครดิต/overage ใน candidate ยังไม่พิสูจน์ | UNCONFIRMED |
| V1.2 คำตอบในแอป | App Server stream ได้; runtime/transport มือถือและการแยกเจ้าของยังไม่ยืนยัน | UNCONFIRMED |
| V1.3 เผยแพร่/ถอนสิทธิ์ | plugin publishing กับ App Server logout เป็นคนละเส้นทาง; native distribution/revoke ยังไม่ครบ | UNCONFIRMED |
| V2.1 เชื่อมบัญชี Free จริง | ไม่เริ่ม เพราะ V0–V1 ยังไม่ผ่าน | NOT_RUN |
| V2.2 คุยกับอารีหนึ่งคำ | ไม่ใช้ mock หรือบัญชีนักพัฒนาแบบเสียเงินแทนหลักฐาน Free | NOT_RUN |
| V2.3 สิทธิ์หมด/ยกเลิก | ต้องทดสอบ quota, offline, switch, revoke ตามตารางด้านล่างหลังมี route | NOT_RUN |
| V3.1 เทียบข้อกำหนด | สรุป partial support ตามหลักฐาน; acceptance ของผลิตภัณฑ์ยังไม่ผ่าน | REVIEWED |
| V3.2 ผู้เรียน 5 คน | ยังไม่มีต้นแบบเข้าเกณฑ์; 0/5 คน ไม่รายงาน 0 ว่าเป็นผลสอบตก | NOT_RUN |
| V3.3 แผนต่อยอด | กลับมา V0–V1 เมื่อได้หลักฐานปิดช่องว่างของ candidate แล้วจึง V2 → pilot → production plan | REVIEWED |

## เงื่อนไขเปิด V2 อีกครั้ง

ต้องมีเอกสารทางการหรือคำยืนยันจากผู้ให้บริการที่ตรวจสอบได้สำหรับ (1) auth/return flow และ runtime ของ native mobile (2) สิทธิ์ Free ในไทยสำหรับ integration นี้ (3) วิธีไม่ใช้ paid credits/overage โดยไม่อาศัย rate-limit precheck อย่างเดียว (4) การเผยแพร่และถอน grant/token ต้นทาง รองรับ logout/สลับบัญชีอย่างแยกเจ้าของได้ บันทึก source/version ก่อนเริ่มต้นแบบ หากเปลี่ยนข้อกำหนดต้องให้ผู้ใช้ตัดสินใจ ไม่เปลี่ยนเป็น desktop companion หรือ ChatGPT-hosted chat เอง

## Test Plan เมื่อผ่าน gate — ทุกกรณีด้านล่างยัง NOT_RUN

| กรณี | ขั้นตอนหลัก | ผลที่ต้องได้ / หลักฐาน |
|---|---|---|
| T01 Free/ไทย/mobile | ใช้บัญชี Free จริงในไทยบนเครื่องจริง ล็อกอินผ่าน browser แล้วกลับแอป | ไม่มี key/Developer mode; บันทึก OS/app/provider version และ plan แบบปกปิดข้อมูลส่วนตัว |
| T02 คำศัพท์ | ส่ง “ช่วยอธิบาย bottle และยกตัวอย่างหนึ่งประโยค” | คำตอบอยู่ใน LexiQuest; trace ของ route ที่อนุมัติ ไม่ใช่ WebView สนทนา ChatGPT หรือ mock |
| T03 สิทธิ์/โควตาหมด | ใช้ provider test mechanism ที่รองรับหรือบัญชีที่หมดจริง ไม่จงใจเผา quota | แจ้งหยุด ไม่สลับ API key ไม่ซื้อ/ใช้เครดิตสำรอง; request/billing evidence |
| T04 เน็ตขาด | ตัดเน็ตก่อนส่งและระหว่างรับ แล้วต่อใหม่ | draft อยู่ ไม่ตอบซ้ำ/คิดซ้ำจาก retry; trace แยก interrupted/completed |
| T05 สลับบัญชี | A ส่งคำขอค้าง → logout → B login | ไม่มี reply/history/token ของ A ไป B; late response ถูกทิ้ง |
| T06 ถอนสิทธิ์ | ถอน grant จาก provider ระหว่างใช้งาน แล้วลอง credential เก่า | เรียกต่อไม่ได้; บัญชีอื่นไม่กระทบ; logout และ provider revoke มีหลักฐานแยก |
| T07 ห้าม paid fallback | ทำ T03/T04/auth failure พร้อมสังเกต network/usage | ไม่มี API เสียเงินสำรองหรือ shared project credential; ผลจำลองแยกผลจริง |
| T08 usability | ผู้เรียนไม่ใช่สายคอม 5 คน เชื่อมบัญชี → ถามศัพท์ → ถอนสิทธิ์ | อย่างน้อย 4/5 ทำครบโดยผู้พัฒนาไม่ทำแทน; บันทึกเวลา จุดติดขัด และจำนวนคำแนะนำ |

เก็บผลด้วย case ID, build SHA, อุปกรณ์/แผน, เวลา, expected/actual, PASS/FAIL/NOT_RUN, live/simulated, หลักฐานปกปิดข้อมูล และ defect/retest link ไม่เก็บ token/password/ข้อมูลวิจัย Pilot เป็น usability เท่านั้น ไม่สรุปผลการเรียนรู้

## การปรับโค้ดรอบนี้

- ตั้งชื่ออารีในหัวหน้าสนทนา ผู้ส่งข้อความ สถานะไม่พร้อม/หยุดเชื่อมต่อ และ persona prompt เดิม; Text semantics อ่านชื่อใหม่จาก label เดียวกัน
- คง `AiTutor*`, route, owner/session IDs, schema และ provider เดิม ไม่แตะคำศัพท์ “เพชรพลอย” หรือหลักฐานเก่า
- Native Tutor ปัจจุบันยังใช้เส้นทาง BYOK เดิม การเปลี่ยนชื่อไม่ทำให้ login แบบ ChatGPT Free ใช้งานได้ และไม่เปิด feature gate เพิ่ม
- ผลทดสอบโค้ดเฉพาะส่วนเก็บใน [evidence](ari-feasibility-evidence.json); ไม่ใช้ผลนั้นแทน T01–T08 หรือ E7

## แหล่งทางการ

- S1 [MCP authentication](https://developers.openai.com/plugins/build/auth) — Components / Custom auth
- S2 [Sites](https://learn.chatgpt.com/docs/sites) — Add Sign in with ChatGPT
- S3 [Plugins](https://learn.chatgpt.com/docs/plugins) — Connect supported partners with Sign in with ChatGPT
- S4 [ChatKit](https://developers.openai.com/api/docs/guides/chatkit) — Set up ChatKit in your product
- S5 [Codex App Server](https://learn.chatgpt.com/docs/app-server) — Protocol / Auth endpoints / Rate limits
- S6 [Authentication](https://learn.chatgpt.com/docs/auth) — OpenAI authentication
- S7 [Pricing](https://learn.chatgpt.com/docs/pricing) — Included plans / Tokens and credits
- S8 [Connect and test](https://developers.openai.com/plugins/deploy/connect-chatgpt) — Enable developer mode
- S9 [Submit plugins](https://developers.openai.com/plugins/deploy/submission) — Developer identity / Required materials
- S10 [Codex as a platform](https://developers.openai.com/blog/codex-as-a-platform) — Integration layer; harness กับ model access แยกกัน
