# LexiQuest MCP — ChatGPT-first development plan v2

สถานะ: แผนพัฒนาตามคำสั่งผู้ใช้ให้วางแผน ChatGPT ก่อน; ยังไม่เริ่ม implementation/deploy/billing; 2026-09-20
ต่อยอด ai-access-no-surprise-plan.md; ฐาน E7 34d520760d55ad14c06a266c0c6bd88152444619
ตรวจเฉพาะ feature inventory, E6/E7 reports, personal sets use cases, AI contracts/use cases และ backend auth/app; mapping อื่นเป็น integration candidates ต้องตรวจละเอียดก่อนแก้

## 1. ขอบเขตผลิตภัณฑ์
แอปหลักฟรีและทำงานได้โดยไม่มี MCP; AI host ใช้บัญชี/สิทธิ์ของผู้ใช้ตามที่ผู้ให้บริการรองรับ ไม่มี inference API call เพิ่มจากเส้นทาง MCP ใน MVP
แยก native AI Tutor (เดิมใช้ BYOK) ออกจาก external tutoring ผ่าน MCP; ไม่สัญญาว่า OAuth จะย้ายโควตาสมาชิกมาใช้ในหน้าจอ Flutter ได้
ผู้ช่วยพลอยในแอปทำ navigation/authored guidance ต่อได้ ส่วนข้อความกำหนดบุคลิกที่ส่งให้ host เป็นแนวทาง ไม่สามารถรับประกัน host/model ทำตามทุกครั้ง
ไม่บังคับซื้อ Plus/Pro เพื่อฝึกในแอป ไม่ให้รางวัลเพิ่มเพราะซื้อ AI ไม่เปิด billing/deploy ในงานออกแบบนี้

## 2. สถาปัตยกรรมที่แนะนำ
Flutter → authenticated sharing API → selected-content snapshots/draft inbox
ChatGPT → HTTPS Streamable HTTP MCP → OAuth resource authorization → bounded learning tools → snapshots/draft inbox
Flutter รับ draft → ตรวจ schema/content revision/owner → ผู้ใช้ยืนยัน → เรียก domain use case เดิม → บันทึก local DB

เลือก remote server ที่โครงการดูแล; ไม่ให้นักศึกษาติดตั้ง ngrok หรือรัน server บนมือถือ ไม่มี dependency ต่อ desktop lnwjud
การแชร์เป็น snapshot แบบ opt-in ไม่ใช่อัปโหลด DB ทั้งก้อน; local-only/guest เรียนต่อได้ หากยังไม่ link จะไม่เปิด private tools
remote snapshot เป็นข้อมูลสำหรับติว; local domain/evidence ยังเป็น authority ของคะแนนและรางวัล อย่าสร้าง source of truth แข่งกัน

## 3. Feature coverage
| ส่วนแอป | MCP ที่เสนอ | ขอบเขต/ลำดับ |
|---|---|---|
| vocabulary/offline_content | lookup_word: นิยาม/ตัวอย่าง/CEFR พร้อม content revision | MVP; เฉพาะเนื้อหาที่สิทธิ์อนุญาตเผยแพร่ |
| F01 personal sets/learning_packs | read_selected_deck, propose_practice_draft | MVP; exact revision/sense pins; เพิ่มชุดเป็น draft |
| F02 goals/today_hub/study plan | read_shared_plan, propose_plan_draft | ระยะ2; เวลา/เป้าหมายผู้ใช้ยืนยัน ไม่เปลี่ยนตารางเอง |
| F03 hint/guided repair | read_selected_practice_context | ระยะ2; ส่งเฉพาะข้อที่เลือก; AI explanation แยกจาก authored answer/scoring |
| F06 collocations/confusables | read_contrast_context | ระยะ2; ใช้ pinned content; ตัวอย่างใหม่มีป้าย AI-generated |
| F04 written practice/assessment | ส่งข้อความที่เลือกและ rubric ให้ host ช่วยอธิบาย | ระยะ2; feedback ไม่ใช่คะแนนรับรอง ห้าม finalize assessment ผ่าน MCP |
| F05 speaking/media_practice | บทสนทนา/เป้าหมายฝึกที่เลือก | ระยะ3; text ก่อน ไม่มีเสียงดิบใน MVP; pronunciation score ต้องมีหลักฐานเสียงที่เหมาะสม |
| F08 audio lesson/voice | แชร์ transcript ที่อนุญาตและเสนอ comprehension exercise | ระยะ3; ไม่อ้างคุณภาพเสียงจาก transcript; speech generation ไม่แถม API paid |
| F07 branching dialogue | แชร์สถานการณ์และเสนอบทสนทนาฉบับร่าง | ระยะ2; จำกัด schema/จำนวน node; ไม่เปลี่ยน content ที่ตรวจรับแล้วเงียบ ๆ |
| F09 transfer probe/review | ฝึกเพิ่มจากศัพท์ที่เลือก | ระยะ2; ห้ามเปิดเฉลยของ active probe หรือบันทึก draft เป็นผลสอบ |
| review/SRS | read_shared_review_summary | ระยะ2; AI แนะนำได้ แต่ scheduling/mastery ตัดสินในแอป |
| camera/device_model | แชร์ label ที่ผู้ใช้ยืนยัน แล้วเสนอศัพท์ | ระยะ3; ไม่เปิดกล้องระยะไกล ไม่อัปโหลดภาพอัตโนมัติ ไม่เปิดโมเดล default-off |
| progress/history/recommendation | read_shared_learning_summary | ระยะ2; summary ขั้นต่ำ ไม่เผยประวัติทั้งหมด |
| companion/motivation/quests | บริบทคำแนะนำ/เป้าหมายที่ผู้ใช้เลือก | ระยะ2; การทำ quest และ reward ต้องมี native evidence |
| adventure/achievements/rewards | เสนอ narrative draft | ภายหลัง; ไม่แก้ XP/coin/streak ไม่ปลด feature gate |
| time_tracking/reminders/preferences | เสนอเวลาฝึก/ข้อความเตือน | ภายหลัง; native confirmation ก่อนตั้ง reminder; ไม่เขียนเวลาเรียนจาก chat |
| accessibility | คู่มือเชื่อมภาษาไทย/ข้อความสั้น/keyboard/screen reader | MVP; mobile host จริงยังต้องตรวจ ไม่ถือ widget test เป็น TalkBack pass |
| account/identity/consent/export | link/unlink, scopes, receipt, delete shared copy | MVP; consent AI sharing แยกจาก research consent |
| sync/session/events | snapshot version, idempotency, bounded audit, conflict handling | MVP; ไม่ข้าม owner gate/duplicate terminal event |
| research | ไม่มี MCP tool ใน MVP | consent/assignment/export สถิติอยู่นอก scope; ห้ามส่ง research identifiers ให้ host |

## 4. MVP contracts: 3 tools
1. lookup_word(query, locale, cursor?): public licensed catalog; จำกัดผลและ payload; คืน canonical word/sense IDs กับ version
2. read_selected_deck(share_id, revision, cursor?): ต้อง scope deck.read และ grant ครอบคลุม share; owner ดึงจาก token ห้ามเชื่อ owner_id จากโมเดล
3. propose_practice_draft(share_id, base_revision, items, request_id): ต้อง draft.propose; โฮสต์ส่งเนื้อหาที่สร้างมาเอง server ตรวจ/เก็บเท่านั้น ไม่เรียก LLM
ชื่อ/schema เป็นข้อเสนอใหม่ ไม่ใช่ API ที่มีอยู่แล้ว
ผลลัพธ์ envelope: schema_version, content_revision, source, status, bounded data, next_cursor, retry_after เมื่อทราบ; error แยก AUTH_REQUIRED/REVOKED/NOT_SHARED/STALE_REVISION/NOT_SYNCED/RATE_LIMITED/INVALID_DRAFT
proposal ต้องมี expected revision+dedup digest ต่อ owner/client/request; retry เดิมคืน draft เดิม คนละ payload key เดิมให้ conflict; ไม่มี approve/apply tool ใน MVP
exact pins หายหรือ content ถอนสิทธิ์ → unavailable; ไม่เลือกเวอร์ชันอื่นเอง

## 5. Auth / data / backend
- Firebase bearer verifier ปัจจุบันเป็น identity boundary ของ API ไม่ใช่ MCP OAuth authorization server ครบชุด ต้องเพิ่มหรือใช้ IdP ที่รองรับ authorization-code+PKCE/resource metadata/client registration ตาม host
- map provider subject → LexiQuest account ผ่าน flow ที่เจ้าของยืนยัน ไม่รวมบัญชีจาก email ตรงกันเพียงอย่างเดียว; ตรวจ issuer/audience/expiry/scope ทุก request
- access/refresh tokens แยกจาก Firebase session; private storage, rotation/revocation, no logs; credentials ของ provider ไม่ส่งให้โมเดล
- ข้อมูลเสนอเพิ่มฝั่ง server: mcp_connections, sharing_grants, shared_snapshots, practice_proposals, minimal_audit; ตั้ง retention/TTL ก่อน rollout; revoke แล้วปิด access ทันทีตาม SLA ที่ทดสอบ
- connection states: unlinked/awaiting_authorization/linked/expired/revoked/unavailable; proposal states: pending/accepted/rejected/expired/conflict
- Flutter schema34 baseline: ก่อนเพิ่ม table/column ตรวจ migration inventory; additive only ถ้าจำเป็น มี rollback flag ไม่มี destructive rewrite
- backend rate/concurrency/body-size/per-user/global limits + TTL cache; ไม่ retry storm; infrastructure มีต้นทุนแม้ไม่มี LLM bill จึงต้องกำหนดงบและปุ่มปิดบริการ
- การถอนสิทธิ์ไม่ลบข้อความที่ host ได้รับแล้ว; UI อธิบายก่อนแชร์และแยก disconnect ออกจากยกเลิกสมาชิก AI
- MCP result เป็น untrusted data; tools ไม่มี arbitrary URL/SQL/shell/filesystem; schema allowlist, SSRF protection สำหรับลิงก์ และ authorization หลัง lookup ทุกครั้ง

## 6. Workflow ผู้ใช้
1 เลือกชุดศัพท์ → 2 เปิดหน้าบอกข้อมูลที่จะส่ง → 3 อนุญาตแชร์ snapshot → 4 เชื่อม host ผ่าน flow ทางการ → 5 ติวใน host → 6 รับ draft ในแอป → 7 ดูตัวอย่าง/ตรวจ → 8 บันทึกผ่าน personal-set use case
หาก provider ไม่รองรับบัญชี/ภูมิภาค: แสดง unavailable และให้เรียน native ต่อ ไม่ชวนซื้อแพ็กเกจเพื่อแก้สิ่งที่ยังไม่พิสูจน์
โควตา host หมด: host เป็นผู้ควบคุม; server เราอาจไม่ได้รับแจ้ง ห้ามสร้างตัวนับโควตาปลอม ไม่มี API fallback อัตโนมัติ
เน็ตหลุด/มือถือปิด: server อ่านได้เฉพาะ snapshot ที่เคยแชร์; draft รอรับภายหลัง; ไม่อ้างข้อมูลล่าสุดถ้ายังไม่ sync
สองเครื่องแก้ชุดพร้อมกัน: expected revision ไม่ตรง → แสดง conflict เลือกสร้าง revision ใหม่หลังยืนยัน; ไม่ overwrite
logout/account switch: ล้าง private UI/cache/cancel in-flight ของ owner เก่า; การ revoke ถาวรเป็นอีก action ที่ชัดเจน

## 7. Code integration candidates
พาธ relative ต่อ C:/Users/Phet/.codex/worktrees/daea/LexiQuest
- lib/features/learning_packs/application/personal_sets_use_cases.dart: จุดรับ draft หลัง validate; readExact/owner generation ที่อ่านพบต้องคงไว้
- lib/features/learning_packs/domain/personal_sets.dart, sense_crosswalk.dart: pinned revision/schema mapping; ตรวจ implementation เพิ่มก่อนเปลี่ยน
- lib/features/ai_tutor/application/ai_tutor_use_cases.dart: authored fallback/owner coordination; external session แยก native request
- lib/screens/ai_tutor_settings_screen.dart: connection cards และ BYOK advanced
- lib/features/sync/application/sync_engine.dart; domain/sync_gateway.dart, sync_store.dart: ตรวจรองรับ selected sharing หรือเพิ่ม bounded adapter ห้ามเหมารวมว่าซิงก์ทุก entity ได้แล้ว
- backend/ai_api/src/lexiquest_ai/auth.py, app.py: นำแนว auth/error/body limit มาใช้; แยก MCP route/service ออกจาก LLM ContentGenerator
- ใหม่เสนอ: backend/mcp_gateway, Flutter connection/sharing/draft adapters; path สุดท้ายเลือกหลัง audit service deployment ไม่แยก service โดยไม่มีเหตุผล
ไม่ port Dart domain ทั้งหมดไป Python; server validate schema/ownership ส่วน semantic application ผ่าน domain เดิมในมือถือ

## 8. แผน 8 กลุ่ม / 24 งานย่อย (M เป็น design IDs ไม่ทับ G/E)
| กลุ่ม | งานย่อย 3 ข้อ | เกณฑ์จบ |
|---|---|---|
| M0 feasibility | M0.1 account/region/mobile matrix; M0.2 billing/data policy; M0.3 read-only host smoke | มีหลักฐาน target user ใช้ได้ ไม่ใช่ developer account เท่านั้น |
| M1 contracts/UX | M1.1 schemas/scopes; M1.2 Thai linking/unlinking UX; M1.3 data retention/source ownership | ผู้ทดสอบเข้าใจสิ่งที่แชร์และปิดสิทธิ์ได้ |
| M2 backend auth | M2.1 resource+auth server; M2.2 UID mapping/grants; M2.3 limits/revoke/audit | cross-owner/replay/wrong audience ถูกปฏิเสธ |
| M3 selected data | M3.1 licensed lookup; M3.2 opt-in snapshot; M3.3 pinned deck read | private/local-only data ไม่หลุด revision ไม่เปลี่ยนเงียบ |
| M4 drafts | M4.1 schema/idempotent inbox; M4.2 preview/native accept; M4.3 owner/conflict/offline recovery | ไม่มีคะแนน/รางวัลเพิ่มจาก generated draft |
| M5 feature extensions | M5.1 plans/review summary; M5.2 repair/writing/dialogue; M5.3 confirmed camera word + transcript context | แยก feedback จาก assessment; media opt-in ผ่านข้อกำหนดจริง |
| M6 validation | M6.1 targeted tests/delta review; M6.2 real-host/mobile/revoke; M6.3 user pilot/feedback | no-key journey ใช้กับคนไม่ใช่สายคอมได้ หลักฐานจริงครบ |
| M7 bounded rollout | M7.1 cost/availability dashboard; M7.2 staged flag/rollback; M7.3 acceptance ledger/help | ปิด MCP แล้ว core learning ยังปกติ ไม่มี unauthorized paid calls |
ชุดทดลองแรก = M0–M4 แล้วใช้เกณฑ์ M6 ทดสอบก่อน; ขอบเขตพัฒนารอบนี้รวม M5 ทุกข้อ แล้วตรวจ M6 ขั้นสุดท้ายก่อน M7 ทำทีละ writer/task ตามนโยบายเดิมเมื่ออนุญาต ไม่ dispatch ตอนออกแบบ

## 9. Test plan และผลกระทบ E7
- Unit/contracts: scopes/pins/limits/schema/idempotency; integration: real DB atomic grant/proposal, migration rollback, owner switch, two devices
- Adversarial: forged IDs/audience, token replay/revoke, stale snapshot, prompt-like content, duplicate approve, malicious links, oversized payload
- Native regression: personal sets, AI tutor settings/use cases, sync owner lifecycle, reward/session isolation; use verify-scope.ps1 -Level Targeted -Area AI/Learning/Integration ตาม targets จริง
- Live: connect/read/propose/revoke บน host+มือถือและบัญชีเป้าหมาย; ตรวจ server egress ไม่มี paid inference; quota exhaustion ใช้ simulation แยกจาก observed real-host limit
- Pilot เสนอ 5–8 ผู้เรียนไม่ใช่สายคอม: เริ่มเอง/ขอความช่วยเหลือ/เข้าใจข้อมูลแชร์/ยกเลิกได้/กลับมาเรียนเมื่อ AI unavailable; เก็บข้อผิดพลาดแบบไม่บันทึก token/บทสนทนาส่วนตัวทั้งหมด
- MCP ไม่ปิด E7 physical camera/audio/human/provider/two-device gates เดิม; เพิ่ม delta review/regression ต่อ source ที่เปลี่ยนและทำ evidence reconciliation ไม่รันซ้ำส่วนที่ไม่กระทบ
- ไม่มีผลทดสอบใหม่ในเอกสารนี้; free-account availability, public distribution, hosting budget และ retention ยังเป็นจุดตัดสินใจก่อน rollout

## 10. แหล่งข้อมูล/ข้อจำกัดปัจจุบัน
- https://developers.openai.com/plugins/build/auth : OAuth/MCP host; ไม่ใช่สิทธิ์เรียกโมเดลด้วย subscription token
- https://support.google.com/gemini/answer/17209137 : native custom MCP มีแล้ว แต่เอกสารที่ตรวจจำกัด US/18+/personal account/English/Keep Activity; ไม่ตั้งเป็นเส้นทางเริ่มต้นนักศึกษาไทย
- https://github.com/engasnm111/lnwjud : ต้นแบบ gateway; นำแนวคิด bounded tools/auth มาใช้ ไม่จำเป็นต้องยก desktop runtime มาทั้งชุด
- ai-access-no-surprise-plan.md : หลักไม่มี user API key/paid fallback และต้นทุนฝั่งโครงการแยกกัน

## 11. ข้อสรุปขอบเขต ChatGPT-first v2 (ใช้แทนทางเลือก provider ใน v1)
- ผู้ให้บริการ/host แรก: ChatGPT; ไม่ล็อกชื่อโมเดลหรือแพ็กเกจที่ไม่ผ่านการตรวจจริง ชื่อ ChatGPT ไม่ใช่ model ID ของ API
- Gemini อยู่นอก implementation/test/rollout รอบนี้ เก็บข้อมูลอ้างอิงเดิมเป็นประวัติ ไม่พัฒนา Gemini OAuth หรือ adapter ตอนนี้
- AI Tutor เดิมคงอยู่และแยกสถานะจาก “ติวต่อใน ChatGPT”; หน้าตั้งค่าธรรมดาไม่ถาม API key; BYOK เดิมอยู่ advanced opt-in
- ไม่มี headless ChatGPT, browser-cookie reuse, subscription-token proxy หรือ paid inference fallback
- ใช้ connection/scopes และ content schemas ที่ไม่ผูกผู้ให้บริการเกินจำเป็น แต่ไม่สร้าง framework หลายเจ้าล่วงหน้า

## 12. Camera → vocabulary → ChatGPT
ลำดับ: ถ่ายในแอป → local model เสนอ class+confidence → ผู้ใช้ยืนยัน/แก้ label → จับคู่ canonical word/sense → อ่านออกเสียงด้วยระบบเดิม → เลือก “ฝึกคำนี้ใน ChatGPT”
- MCP ส่ง confirmed word/sense + content revision + learning level เมื่อยินยอมเท่านั้น; ไม่ส่งภาพ/เสียงดิบหรือ EXIF
- envelope แยก model_prediction จาก user_confirmed_label; provenance=model_version, prediction_id, label_source; เปิดให้ host เฉพาะฟิลด์จำเป็น ไม่ส่งตัวระบุหลักฐานวิจัย
- เพิ่ม context_type=camera_confirmed_word ให้ sharing snapshot ใน M5.3; reuse lookup_word และ propose_practice_draft ไม่เพิ่ม tool เปิดกล้อง
- โมเดลไม่มั่นใจ: ให้ถ่ายใหม่/เลือกศัพท์เอง; ไม่อ้างว่า AI แก้ผลแล้วโมเดลแม่นขึ้น และไม่เปิด candidate model ที่ยังไม่ผ่าน gate เดิม
- pronunciation/เสียงยังใช้เส้นทางที่ได้รับอนุญาตเดิม; MCP ไม่ทำให้ TTS ฟรีอัตโนมัติและไม่เพิ่มเสียงคลาวด์โดยปริยาย
- การเทรนโมเดล/วัด accuracy และการประเมิน AI tutoring แยกชุดข้อมูลกับรายงาน; MCP ไม่แทนการทดสอบกล้องจริงของ E7

## 13. การจำกัดขอบเขตผู้ช่วย
- Native UI เปิดงานจากกิจกรรม เช่น explain_word/practice_sentence/review_mistake; ส่ง learning objective และ allowlisted context
- ChatGPT host เป็นผู้ช่วยทั่วไป เราไม่สามารถห้ามคำตอบนอกเรื่องทั้งแชตได้; ล็อกสิ่งที่ tools อ่าน/เขียนได้ที่ server
- Draft ต้องเป็นประเภทกิจกรรมที่รองรับ มีความสัมพันธ์กับคำ/ชุดที่แชร์ ความยาวจำกัด และผ่าน semantic/content-quality checks ก่อนรับ; schema ผ่านอย่างเดียวไม่พอ
- เนื้อหาน่าสงสัย/นอกเป้าหมายเก็บเป็น rejected หรือให้แก้ draft ไม่เข้าสู่ graded content; ผู้ใช้เห็น preview และแหล่ง AI-generated
- คำถามอาหารเพื่อฝึกภาษาอนุญาตตาม objective; recipe-only ไม่กลายเป็นกิจกรรมเรียนโดยอัตโนมัติ
- ไม่พึ่ง prompt/classifier เพียงตัวเดียว ไม่อ้างว่าล็อกคำตอบ LLM ได้ 100%; add prompt-injection/off-topic regression fixtures

## 14. รายการส่งมอบและการส่งต่อ 24 tasks
ทุก task ใช้ M0.1–M7.3 ตามตารางเดิม (กลุ่มละ3); ชุดงานนี้เป็น MCP ไม่เปลี่ยนเลข G/E หรืออ้างว่าผ่าน E7 เพิ่มแล้ว
handoff แต่ละ task ต้องระบุ base/accepted SHA, branch feature/mcp-<task>, ขอบเขตไฟล์, contract version, dependency, tests/evidence, findings, external NOT RUN และ next task เพียงหนึ่งเมื่อได้รับอนุญาต
writer เดียว, Astra medium Standard/default, no Fast/subagents; error ที่แก้ได้ให้แก้และทดสอบต่อ ไม่ข้าม gate
ก่อน M0: ตรวจ latest source และ clean/dirty state ใหม่ ไม่ใช้ planning checkout 7712 ทับแอป
M0 แยกผล “บัญชี developer ใช้ได้” ออกจาก “ผู้ใช้ฟรีในไทยบนมือถือใช้ได้”; ถ้าอย่างหลังไม่ได้ ต้องแสดงข้อจำกัดจริงและคง core free ไม่ชวนสมัคร Plus/Pro โดยไม่มีหลักฐานว่าจะรองรับ
M2 เลือก hosting/IdP/retention/budget ที่มีจริงเป็น decision record ก่อนเปิดบริการ; ไม่ถือ Firebase Login เป็น OAuth authorization server ที่พร้อมใช้โดยอัตโนมัติ
M3/M4 ต้องได้ interface manifest + migrations + contract tests + no cross-owner writes; M5 เพิ่ม feature adapters ทีละประเภท
M6 รายงาน defects พร้อม reproduction/source/evidence และ feedback จากกลุ่มเป้าหมาย; live-required tests ที่ไม่มีหลักฐานคง NOT RUN
M7 เปิด flag ทีละกลุ่มเมื่อ acceptance ผ่านและมี deployment authorization; rollback ปิด MCP ได้โดยไม่ลบ shared/draft/learner data แบบเงียบ ๆ

## 15. Release acceptance checklist
- [ ] ChatGPT account/plan/region/mobile target matrix มีหลักฐาน actual usage และ distribution route ที่รองรับ
- [ ] ผู้เรียนเชื่อม/ใช้/ยกเลิกได้โดยไม่จัดการ API key; consent ชัดว่าข้อมูลใดออกจากเครื่อง
- [ ] 3 core tools + M5 context types ผ่าน authorization/revision/limits/idempotency tests
- [ ] Camera ส่งเฉพาะ confirmed vocabulary; capture/recognition/TTS/core learning ทำงานเมื่อไม่เชื่อม ChatGPT
- [ ] Off-topic draft ไม่ถูกนำเข้า graded content; MCP เปลี่ยน score/reward/SRS schedule โดยตรงไม่ได้
- [ ] Offline/revoke/account switch/two-device/conflict/retry ไม่ทำข้อมูลหายหรือปนกัน
- [ ] ไม่มี inference API call/paid fallback จาก MCP route; hosting limits/ค่าใช้จ่ายของโครงการชัดเจน
- [ ] ผ่าน targeted review, native regression, actual-host/mobile และ user pilot; E7 pending เดิมไม่ถูกปิดด้วย mock
- [ ] Feature-flag rollback และคู่มือสั้นสำหรับผู้เรียน/ผู้ดูแลผ่านการตรวจ
ทั้งหมดเป็นเกณฑ์ที่ต้องทำในอนาคต ไม่ใช่ผลผ่าน ณ วันที่เขียนแผน
