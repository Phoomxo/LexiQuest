# แนวทาง AI ใช้ง่ายและไม่เกิดค่าใช้จ่ายไม่คาดคิด

สถานะ: แผนเสนอ 2026-09-20; ไม่ใช่คำสั่งเริ่ม implementation/deploy/billing
ฐานที่ตรวจ: E7 34d520760d55ad14c06a266c0c6bd88152444619; อ่านเฉพาะสัญญา AI, use cases, backend limiter และตำแหน่ง tests ไม่ใช่ full review หรือ live-provider test

## เป้าหมายและข้อเท็จจริง
- ผู้ใช้ทั่วไปไม่ต้องสร้าง key เปิด Cloud Console หรือผูกบัตร; โควตาหมดแล้วหยุด AI และเรียนต่อด้วยเนื้อหาที่มีอยู่
- Google Login ยืนยันตัวตน; ไม่ได้ให้สิทธิ์นำแพ็กเกจ Gemini/ChatGPT มาเรียกโมเดลในแอปภายนอกโดยอัตโนมัติ
- MCP เชื่อมเครื่องมือ/ข้อมูล ไม่ใช่สิทธิ์เรียกโมเดลหรือหลักประกันค่าใช้จ่าย
- โควตารายคนที่แอปจัดสรรแยกจากโควตารวมของผู้ให้บริการ; ไม่แจก key เพื่อข้ามข้อจำกัด
- ไม่ตีความโมเดล “ลูน่า” ที่กล่าวถึงเป็นโมเดลที่เรียกได้ผ่านการล็อกอิน; ต้องทราบชื่อ/แหล่งอ้างอิงและสิทธิ์จริงก่อน

## ทางเลือก
| ทาง | ผู้ใช้ทำอะไร | ต้นทุน/ข้อจำกัด |
|---|---|---|
| A: AI ใน LexiQuest | ล็อกอินและเริ่มเรียน | ใช้โควตาโปรเจกต์กลาง; free-only เมื่อยืนยันบริการไม่มี billing หรือโควตาที่องค์กรออกให้โดยใช้งบที่อนุมัติแยก; backend ยังมีต้นทุน |
| B: LexiQuest ใน ChatGPT ผ่าน MCP | เชื่อมบัญชี LexiQuest จาก ChatGPT แล้วเรียนใน ChatGPT | โมเดลทำงานใน host; สิทธิ์แพ็กเกจ/มือถือ/การเผยแพร่ต้องทดสอบ; server ของเราไม่เรียก LLM ซ้ำ |
| C: ส่งโจทย์ไปแอป AI ที่ผู้ใช้มี | คัดลอกโจทย์ที่ตรวจแล้วและเปิดแอป AI ด้วยตนเอง | ไม่เกิด API call จาก LexiQuest; มีการสลับแอปและนำคำตอบกลับด้วยตนเอง ไม่อ้าง auto-sync |

ข้อเสนอ: เริ่ม A เฉพาะกลุ่มเล็กเมื่อ free-only/งบได้รับการยืนยัน; ทดลอง B แยกเพื่อพิสูจน์ไอเดียใช้บัญชีเดิม; C เป็นทางเลือกที่ใช้ได้โดยไม่ต้องพึ่ง native MCP ของ Gemini
ไม่รับประกันว่าค่าใช้จ่ายรวมของระบบเป็นศูนย์ หรือโควตา AI ของผู้ใช้ทุกบัญชีเหมือนกัน

## แผน 6 หัวข้อหลัก / 18 หัวข้อย่อย
| กลุ่ม | 3 หัวข้อย่อย | ผลส่งมอบ/เกณฑ์ผ่าน |
|---|---|---|
| A0 พิสูจน์สิทธิ์ | A0.1 ทำตาราง provider/host/แพ็กเกจ; A0.2 ตรวจ billing และ data-use; A0.3 ทดลองบัญชีเป้าหมายบนมือถือ | ระบุได้ว่าใครจ่าย โมเดลอยู่ที่ไหน โควตาของใคร; สิ่งไม่รองรับเป็น unavailable |
| A1 UX | A1.1 หน้าเริ่มแบบไม่ถาม key; A1.2 สถานะเหลือ/หมด/บริการติดขัด; A1.3 ทางเลือกเรียนต่อและเลิกเชื่อม | ผู้ใช้กลุ่มไม่ใช่สายคอมเริ่มใช้และอธิบายเงื่อนไขเงินได้; key เดิมอยู่ advanced opt-in ไม่ถูกลบทิ้ง |
| A2 Quota gateway | A2.1 ตรวจบัญชี/consent; A2.2 reservation แบบ atomic ต่อคนและส่วนรวม; A2.3 หยุด/คืนสถานะ/ติดตามต้นทุน | คำขอพร้อมกันและสองเครื่องใช้สิทธิ์สุดท้ายได้ครั้งเดียว; store ล่มต้องไม่ยิง provider |
| A3 เชื่อมแอป | A3.1 แยก managed/BYOK access mode; A3.2 ผูก adapter และ authored fallback; A3.3 migration และ feature flag | เปลี่ยนบัญชีไม่รั่ว; key และประวัติเดิมยังอยู่; ปิด flag กลับระบบเดิมได้ |
| A4 MCP ทดลอง | A4.1 ค้นศัพท์สาธารณะแบบ read-only; A4.2 OAuth อ่านชุดส่วนตัวขั้นต่ำ; A4.3 เสนอ draft ที่ผู้ใช้ยืนยันใน LexiQuest | host เรียกข้อมูลได้ด้วยสิทธิ์จริง; revoke มีผล; ไม่เขียนคะแนน/รางวัลจากข้อความ AI |
| A5 ตรวจรับ | A5.1 automated/delta review; A5.2 live quota+มือถือ+คน; A5.3 pilot และบันทึก feedback | มีหลักฐานตามแผน ไม่ใช้ mock อ้างแทน live; รายการ E7 ค้างเดิมยังต้องตรวจ |

ลำดับ A0 → A1 → A2 → A3 → A5; A4 เป็นขอบเขตทดลองเสริมหลัง A0 ไม่บังคับให้ core AI ขึ้นกับ MCP
หาก free-only ไม่รองรับกลุ่มเป้าหมาย ให้คงเนื้อหาในเครื่อง/C ไว้ และเสนอทางองค์กรสนับสนุนแยก ห้ามเปลี่ยนไป paid อัตโนมัติ

## Workflow และกติกาเงิน
แอป → session/consent → server ตรวจ access mode → จองสิทธิ์ต่อคน+ส่วนรวม → provider ที่อนุญาต → ตรวจคำตอบ → บันทึก usage/reconcile → แสดงผล
- ไม่พอ/429/บริการไม่พร้อม: หยุดตามสถานะ; ไม่ retry วน ไม่สลับไป paid provider; รักษาร่างและใช้ authored fallback
- แยกจำนวนครั้งรายวัน, token/input/output limits และเพดานงบ; RPM limiter อย่างเดียวไม่พอ
- ใช้ durable shared store กับ idempotency key; retry ห้ามหักซ้ำ; timeout หลังส่งจริงเป็น unknown ไม่คืนงบที่อาจใช้ไปแล้วทันที
- จองต้นทุนสูงสุดที่กำหนดได้ก่อนยิง; หากราคา/เพดานไม่แน่ชัดในโหมดมีงบ ให้ไม่เปิด route; billing alert ไม่ถือเป็น hard stop
- โหมดไม่เก็บเงินผู้ใช้: ไม่มีการผูกวิธีชำระเงินหรือ automatic top-up ในแอป; ต้นทุนที่ผู้พัฒนาหรือองค์กรจ่ายแสดงแยก
- Free-tier data use ต้องประเมินก่อนใช้กับนักศึกษา: ส่งข้อมูลขั้นต่ำ งดข้อมูลระบุตัวและผลการเรียนละเอียดที่ไม่จำเป็น
- UI แสดงเวลาคืนโควตาเฉพาะที่ทราบจริง; ถ้าผู้ให้บริการไม่บอกให้แสดงไม่ทราบเวลา ไม่เดา

## จุดต่อโค้ดที่พบจริง (พาธ relative ต่อ worktree daea/LexiQuest)
- lib/features/ai_tutor/domain/ai_tutor_contracts.dart: มี provider config/BYOK และ failure codes; เพิ่ม access mode โดย version contract
- lib/features/ai_tutor/application/ai_tutor_use_cases.dart: owner coordination/consent/usage/authored fallback; เชื่อม managed route โดยรักษา context isolation
- lib/features/ai_tutor/data/ai_tutor_gateway_factory.dart: จุดจัด provider adapter; ตรวจรายละเอียดเพิ่มก่อนลงมือ
- lib/features/ai_tutor/data/ai_tutor_settings_store.dart และ drift_ai_usage_repository.dart: ต้องตรวจ migration/credential preservation เพิ่ม
- backend/ai_api/src/lexiquest_ai/services/rate_limiter.py: limiter ในหน่วยความจำต่อ process มีทาง fall-through; ต้องเพิ่ม policy ที่ service orchestration และ distributed quota ไม่อ้างว่าตัวนี้คุมเงินแล้ว
- ใหม่ที่เสนอ: managed gateway, quota reservation store/API และ MCP adapter (ยังไม่สร้างไฟล์)

## Verification ที่ต้องเพิ่ม
- quota=0: outbound provider calls=0; last-slot concurrency, two-device, retry, restart, clock/reset, storage failure, 401/429/5xx/timeout/cancel
- ไม่มี paid fallback ทุก error path; แยก billable unknown จาก failed-before-send
- account switch/logout/revoke; forged owner/token, consent denied; no keys/tokens in logs
- MCP ใช้ audience/scope+PKCE; minimal read access; draft validation และ replay protection; output ไม่แก้คะแนนอัตโนมัติ
- guided repair/fallback/history เดิมไม่ถดถอย; 320/390/text200, offline และมือถือจริง
- ใช้ tool/cli/verify-scope.ps1 -Level Targeted -Area AI -TestTargets test/features/ai_tutor/ai_tutor_use_cases_test.dart แล้วเพิ่ม targets ใหม่ตามไฟล์ที่สร้าง; BackendAI ตามขอบเขตจริง
- ทดสอบจำลองระบุ simulated; ทดสอบ provider จริงต้องมีสิทธิ์และไม่ใช้เกินขอบเขต free-only/งบที่อนุมัติ
- usability pilot เสนอ 5–8 คน: บันทึกเริ่มเองสำเร็จหรือไม่ เวลาที่ใช้ ความเข้าใจเรื่องค่าใช้จ่าย และการเรียนต่อเมื่อ AI หมด; ยังไม่ได้ทดสอบ

## ขอบเขตกับงานเดิม
แผนนี้ไม่เปลี่ยนผล E7 และไม่ปิด pending device/provider/human gates เดิม; หลังเพิ่มให้ delta review และขยาย E7 test plan เฉพาะผลกระทบ ใช้หลักฐานเดิมเมื่อ fingerprint ไม่เปลี่ยน
เมื่อสั่งเริ่ม ใช้ source ล่าสุดที่รับรอง ณ ตอนนั้น, branch feature/, writer เดียว, Standard/default Astra medium; แผนนี้ไม่เปิด billing/deploy/สร้าง task ใหม่

## แหล่งอ้างอิงที่เปิดอ่าน
- https://developers.openai.com/plugins — host และการเชื่อมบริการ
- https://developers.openai.com/plugins/build/auth — MCP host เป็น OAuth client เข้าถึงเครื่องมือของเรา
- https://ai.google.dev/gemini-api/docs/oauth — OAuth ยังมี Cloud project/API scopes
- https://ai.google.dev/gemini-api/docs/billing — free/paid และ billing setup; ตรวจเงื่อนไขอีกครั้งก่อนเปิดใช้

## เพิ่มเติม: ต้นแบบ lnwjud ที่ผู้ใช้ส่งมา
ตรวจ 2026-09-20: https://github.com/engasnm111/lnwjud ที่ tree b98944f8224b6c030079ae9ccda2d165a900466d
หลักฐาน: README, FULL_README, docs/USAGE_TH.md และอ่านโครงสร้างบางส่วน apps/desktop/src/main/remote-mcp-controller.ts ผ่าน GitHub; ไม่ติดตั้ง ไม่รัน และไม่ใช่ full source audit
- Remote MCP หลัก: ChatGPT → HTTPS/ngrok → OAuth gateway → local MCP → เครื่องมือในคอมพิวเตอร์; โมเดลและบทสนทนาอยู่ใน host
- คู่มือยังต้องมี ngrok token/setup; ไม่ใช่ทุกเส้นทางล็อกอินแล้วจบทันที ส่วน Secure Tunnel เป็นทางเลือกที่มี credential/capability ต่างหาก
- เอกสารระบุไม่ใช้ browser token ของ ChatGPT/Codex แทน runtime credential; ไม่พบหลักฐาน Gemini consumer login → inference ในส่วนที่ตรวจ
- ปรับลำดับการพิสูจน์ไอเดีย: A0 แล้วทำ A4.1–A4.2 ขนาดเล็กก่อนตัดสินใจว่าจะลงทุนทาง managed AI เต็มรูปแบบ; 6 กลุ่ม/18 ข้อย่อยยังเดิม แต่ A2/A3 ไม่เป็นข้อบังคับของ MCP proof
- LexiQuest ควรให้ server กลางที่มี HTTPS/OAuth เชื่อมข้อมูลขั้นต่ำที่ผู้ใช้ยินยอม แทนให้นักศึกษารัน ngrok/desktop หรือเปิด MCP server บนมือถือ; ประเมิน hosting cost และข้อมูล local-only ที่ยังไม่ sync
- PoC จำกัด 3 tools ที่เสนอ: lookup_word, read_selected_deck, propose_practice_draft. Draft เป็นข้อมูลที่ต้องตรวจและผู้ใช้ยืนยันในแอป ไม่เขียนคะแนน/รางวัลอัตโนมัติ; ไม่เปิด shell/filesystem tools
- Flow: ผู้ใช้เชื่อม LexiQuest จาก ChatGPT → ขอฝึกชุดที่เลือก → host เรียกข้อมูล → host สอน → เสนอ draft → ผู้ใช้เปิด LexiQuest เพื่อตรวจรับ. การกลับเข้าแอป/deep link ต้องพิสูจน์จริง
- เมื่อ host ใช้ต่อไม่ได้เพราะโควตา ให้คงสถานะเดิม ไม่แอบเรียก API paid ของเรา; ไม่อ้างว่า server อ่านโควตา ChatGPT ได้ หรือป้องกัน host เปลี่ยนโมเดลตามแพ็กเกจได้
- ก่อนรับ PoC: พิสูจน์บัญชีที่ผู้ใช้เป้าหมายมีจริงและมือถือจริง, app availability/publication, link/revoke, owner isolation, native data sync และ server log ว่าไม่ได้ยิง inference API เพิ่ม
- ไม่รับประกันว่า MCP ใช้ได้ทุกแพ็กเกจหรือ Gemini รองรับเส้นทางเดียวกัน; ไม่ได้ทำให้ AI ฝังในหน้าจอ LexiQuest โดยใช้สิทธิ์สมาชิกส่วนตัวทันที
แหล่ง: https://github.com/engasnm111/lnwjud/blob/main/docs/USAGE_TH.md ; https://github.com/engasnm111/lnwjud/blob/main/FULL_README.md ; https://github.com/engasnm111/lnwjud/blob/b98944f8224b6c030079ae9ccda2d165a900466d/apps/desktop/src/main/remote-mcp-controller.ts

## อัปเดตความเป็นไปได้ Gemini จากเอกสารผู้ให้บริการ
ตรวจ 2026-09-20: https://support.google.com/gemini/answer/17209137
Gemini Apps มี custom MCP แล้ว: เชื่อมครั้งแรกผ่านเว็บ จากนั้นใช้บนเว็บ/มือถือได้ แต่เอกสารปัจจุบันจำกัดอายุ 18+, อยู่สหรัฐฯ, บัญชี Google ส่วนตัว, Keep Activity เปิด และภาษาอังกฤษ; ไม่รองรับบัญชี work/school ในเส้นทางนี้ จึงยังใช้เป็นค่าเริ่มต้นสำหรับนักศึกษาในไทยไม่ได้ ห้ามอ้างว่าสมัคร Pro แล้วปลดข้อจำกัดภูมิภาค/บัญชีดังกล่าว
ข้อมูลนี้แทนความไม่แน่ใจเดิมเรื่องการมี native MCP ใน Gemini; การใช้งานจริงกับกลุ่มเป้าหมายยังไม่ผ่าน A0 ต้องตรวจสิทธิ์ ChatGPT แยกเช่นกัน
เพิ่ม UX: ปุ่มยกเลิกการเชื่อมต่อใน LexiQuest เพิกถอนสิทธิ์ฝั่ง server และลิงก์ไปจัดการ connection ของ host; บอกชัดว่า disconnect ไม่ยกเลิกแพ็กเกจสมาชิก และไม่ลบประวัติที่ส่งไป provider แล้ว

ออกแบบราย feature/backend เพิ่มเติม: [LexiQuest MCP system design v1](lexiquest-mcp-system-design.md) — 8 กลุ่ม/24 งานย่อย; supersedes broad MVP sequencing with feasibility → auth → selected snapshots → draft acceptance, then pilot. Design only.
