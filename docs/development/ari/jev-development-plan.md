# Jev สำหรับช่วยงานพัฒนา LexiQuest

วันที่ศึกษา: 2026-09-23  
สถานะล่าสุด: guard/caller ติดตั้งแล้ว; offline18 tests PASS; synthetic1 และ real sanitized review1 เรียกจริง cost0 — full pilot/efficiency ยัง OPEN. รายละเอียด [jev-review-115.json](jev-review-115.json). ข้อความสถานะยังไม่ติดตั้งด้านล่างเป็นประวัติก่อนลงมือ  
ขอบเขต: ใช้ Jev เป็นเครื่องมือเสริมในการตรวจข้อมูลพัฒนาที่ผ่านการคัดกรอง; ไม่ใช่ MCP และไม่ใช่โมเดลสนทนาสำหรับเขียนหรือแก้โค้ด

## สรุปผลศึกษา

Jev รับ `state` และชุดคำถามชนิด `Choice`, `Score`, `Noul` แล้วคืนคำตอบแบบมีชนิดข้อมูล; Choice และ Score มี probability distribution และ confidence ส่วน Noul คืนค่าความน่าจะเป็นโดยตรง คำถามควรแยกเป็นข้อสั้นเฉพาะเรื่อง แล้วให้โปรแกรมเป็นผู้รวมผล การมีชนิดผลลัพธ์ตายตัวช่วยให้ต่อกับตัวจำแนกได้ง่าย แต่ไม่ได้พิสูจน์ว่าคำตอบถูก จึงต้องเทียบกับเฉลยมนุษย์ก่อนใช้ตัดสินใจใด ๆ [เอกสารแนะนำ](https://docs.typesafe.ai/introduction) · [แนวทาง confidence](https://docs.typesafe.ai/confidence) · [Quickstart/API](https://docs.typesafe.ai/introduction/quickstart).

การทดสอบสังเคราะห์หนึ่งครั้งผ่าน Vercel AI Gateway เมื่อ 2026-09-23: HTTP 200, 290 input tokens, Jev ตอบ `has_failure = 0.02`, `gateway cost = $0`, `marketCost = $0.00001218`, surcharge $0. ครั้งแรกก่อนหน้านี้ถูกปฏิเสธ HTTP 403 เพราะต้องยืนยันบัตรกับ Gateway หลักฐานนี้ยืนยันเพียงว่าเรียกได้ในครั้งนั้นและ Gateway รายงานค่าเรียกเก็บเป็นศูนย์ ไม่ยืนยันยอดเครดิตฟรีคงเหลือหรือเงื่อนไขราคาในอนาคต หน้าโมเดล Vercel ระบุ Jev ว่า Free ในขณะตรวจและแจ้งว่าโปรโมชันสิ้นสุด 25 ก.ย. 2026 [หน้า Jev บน Vercel](https://vercel.com/ai-gateway/models/jev). ราคาตามบทความเปิดตัว TypeSafe คือ $0.042 ต่อหนึ่งล้าน input tokens และ output ฟรี [ประกาศ TypeSafe](https://typesafe.ai/blog/introducing-system-one-models-and-jev).

Vercel ระบุว่า Gateway คิดค่าตามอัตราผู้ให้บริการ ไม่มี markup และเครดิตที่ซื้อเป็นแบบเติมเงิน; free-tier allowance ขึ้นกับสถานะบัญชีและรุ่น จึงตรวจจาก balance/usage จริงก่อนทุกช่วงทดลอง [เอกสารราคา Gateway](https://vercel.com/docs/ai-gateway/pricing). ผลตอบกลับครั้งเดียวที่ cost เป็นศูนย์ไม่ใช่หลักประกันว่าจะไม่มีการหักเครดิตในคำขอถัดไป.

TypeSafe รายงานความเร็วและต้นทุนที่ดีในงาน System One ที่เลือกมา แต่บอกข้อจำกัดเองว่า benchmark ทำโดยทีมผู้พัฒนา, ใช้ reference จาก Astra/Fable และผลที่รายงานอาจเป็นกรณีได้เปรียบ Jev จึงเป็นสมมติฐานให้วัดกับ LexiQuest ไม่ใช่ข้อสรุปว่าจะเร่ง Codex ได้แน่นอน [รายละเอียด benchmark และข้อจำกัด](https://typesafe.ai/blog/introducing-system-one-models-and-jev). การเรียก Jev เพิ่มไม่ได้ทำให้ Codex ใช้ context window หรือ reasoning tokens ลดลงเอง ต้องมี orchestration ใช้ผล Jev จัดลำดับงานและวัดเวลา/โทเคนรวมทั้ง pipeline.

## ข้อเสนอการใช้งานกับ LexiQuest

เน้น **code review และการคัดงานระหว่างพัฒนา** ให้ Jev เป็น triage pass: รับสรุป diff ที่ผ่านการคัดข้อมูล, จัดหมวดความเสี่ยง, ระบุส่วนที่ควรตรวจลึก, แนะนำชุดตรวจที่เกี่ยวข้อง และส่งสัญญาณความไม่แน่นอน จากนั้นผู้ตรวจหลักยังอ่าน diff และหลักฐานจริง รวมถึง deterministic analyzers และ tests. ความเสี่ยงสูงหรือ confidence ต่ำต้องถูกส่งให้คนตรวจทันที; Jev ห้ามข้าม review, tests, security/privacy gates หรืออนุมัติ merge.

จุดที่อาจประหยัดเวลาคือจัดลำดับ review และลดการส่งงานซ้ำไปยังโมเดลที่แพงกว่า แต่ **ยังไม่มีหลักฐานว่า Jev ลด reasoning/context tokens ของ Codex** เมื่อ Codex ยังต้องตรวจ diff เต็ม การเพิ่ม Jev ยังเพิ่ม input อีกชั้น จึงต้องวัดเวลา end-to-end, จำนวน calls, Jev tokens/cost, primary reviewer tokens ถ้ามี telemetry, และอัตราพบ defect เทียบ baseline. ถ้าวัด token telemetry ของ Codex ไม่ได้ ให้รายงานว่ายังวัด token savings ไม่ได้.

เก็บการเชื่อมต่อไว้หลังตัวเรียก endpoint เดียวสำหรับ pilot และปิดเป็นค่าเริ่มต้น การทดสอบส่วนใหญ่ใช้ fixture สังเคราะห์กับ fake adapter โดยไม่เรียกเครือข่าย เก็บ request/response ที่ทำให้ระบุตัวตนไม่ได้พร้อมจำนวน tokens, receipt cost และผลมนุษย์ตัดสิน เพื่อประเมิน precision/recall ต่อหมวดและ calibration ของ confidence บนชุดข้อมูลที่แยกจากชุดออกแบบ ห้ามส่ง source code, raw logs, path ส่วนตัว, account IDs, credentials หรือข้อมูลผู้เรียนให้ provider ในระยะแรก.

## แผนพัฒนาเป็นลำดับ

1. **P1 ขอบเขตและค่าใช้จ่าย** — เลือกงานแรกเพียงจัดกลุ่มข้อผิดพลาด/ชี้ขอบเขต review จากข้อมูลสังเคราะห์. อนุญาตใช้เครดิตฟรีที่ตรวจพบ $5; เพดานเงินจริง $0; ไม่เพิ่มวงเงินเอง. ยืนยันสถานะคิดเงินจริงก่อน live และไม่ตั้ง timer เรียกซ้ำ.
2. **P2 Baseline ก่อนสร้างเครื่องมือ** — เตรียม 12 กรณีสังเคราะห์ที่มีเฉลย ตรวจหมวด UI, storage, owner isolation, async state, configuration และข้อมูลไม่พอ. ต้องมี owner isolation และ data loss เป็นกรณีสำคัญ. ตัดสินงานตรงไปตรงมาด้วยกฎก่อน; ส่ง Jev เฉพาะกรณีที่กฎไม่พอ. ล็อกเฉลยก่อนดูคำตอบ Jev และระบุว่าเป็น pilot ขนาดเล็ก ไม่ใช่ benchmark รับรองทั่วไป.
3. **P3 ตัวเรียกขนาดเล็ก** — วางไฟล์ใหม่ที่เสนอ `tool/experiments/jev_review/pilot.py` และ `cases.json` ใช้ endpoint/model ที่ probe สำเร็จแล้ว. ไม่สร้าง framework สลับหลาย provider. จำกัด 1 request พร้อมกัน, ไม่ retry/fallback อัตโนมัติ, ไม่เกิน 12 requests ต่อรอบ, timeout 30 วินาที, input ไม่เกิน 8,000 ตัวอักษรและไม่ตัดข้อความเงียบ ๆ. ใช้ cache ตาม hash ของ input/schema/model เพื่อลดการเรียกซ้ำ; cache ไม่ใช้แทนหลักฐานราคาปัจจุบัน. Offline fixtures ตรวจ fail-closed ของ cost gate และ response validation ก่อน network.
4. **P4 Pilot เมื่อ cost gate ผ่าน** — ใช้ผล smoke เดิมเป็นหลักฐานเชื่อมต่อ ไม่รันทวนโดยไม่มีเหตุ. เริ่ม pilot ทีละกรณี ตรวจ cost receipt ก่อนกรณีถัดไป; หยุดเมื่อเครดิตฟรีหมด/ไม่พอครอบคลุมคำขอถัดไป หรือ cost ขาดหาย/อ่านไม่ได้, timeout ที่ไม่รู้ว่าคิดเงินหรือไม่, provider/model เปลี่ยน หรือหมดสิทธิ์ free. ไม่ส่งซ้ำจนกระทบยอดได้. ถ้าไม่สามารถยืนยันว่าใช้เฉพาะเครดิตฟรีได้ ให้จบที่ offline โดยไม่ขัดขวางงาน MCP เดิม.
5. **P5 ทดลองในงาน review หนึ่งชุด** — เมื่อ pilot มีประโยชน์ จึงใช้สรุป diff/ข้อผิดพลาดที่ตัดข้อมูลลับแล้วภายใต้ขอบเขตการใช้ Jev พัฒนาระบบที่ผู้ใช้อนุมัติ; ขอข้อมูล/สิทธิ์เพิ่มเฉพาะการเปิดเผยที่เกินขอบเขตนั้น. ให้ Jev คืน `category`, `uncertain`, `suggested_check_group` เท่านั้น. Astra ตรวจ code semantics, owner boundaries, async lifecycle และหลักฐาน tests ตามปกติ. Jev ไม่มีสิทธิ์ลดรายการตรวจที่จำเป็นหรือแก้ไฟล์. เลือกตรวจ patch จริงที่ยังค้างโดยไม่รัน gate ที่ผ่านและ source ไม่เปลี่ยนซ้ำ.
6. **P6 ตัดสินคงไว้หรือถอดออก** — เปรียบเทียบ baseline กับ Jev-assisted บนงานเทียบเคียงและสลับลำดับเพื่อลดอคติจากการเห็นเฉลยก่อน. รวมเวลาเตรียม input, API, ตรวจคำตอบ และทำงานแก้ความผิดพลาด. รายงาน token ของแต่ละ provider แยกกัน; ไม่รวมเป็นหน่วยราคาเดียว. หากไม่มี telemetry ของ Astra จะไม่สรุปว่าประหยัดโทเคน. เกณฑ์ pilot ที่เสนอ: ต้องไม่จัดกรณี owner isolation/data loss ว่าปลอดภัยหรือไม่ต้องตรวจ และเวลามัธยฐานรวมลดอย่างน้อย 20% โดยคุณภาพ review ไม่ลด. ตัวเลขนี้เป็นเกณฑ์ทดลอง ไม่ใช่ผลที่ทำได้แล้ว. หากไม่ผ่าน ให้ปิด Jev และกลับไป workflow เดิม.

## ผลทบทวน revision 5

- แผนเดิมลงทุน adapter ก่อนพิสูจน์ประโยชน์: เปลี่ยนเป็น pilot เดียวและ endpoint เดียว.
- การให้ Astra สรุปโค้ดยาวเพื่อ Jev แล้วกลับมาอ่านผลอาจเปลืองกว่าเดิม: ใช้ metadata/ผลตรวจที่มีอยู่และคำถามสั้น; นับต้นทุนการเตรียมข้อมูลด้วย.
- การจัดลำดับตรวจเพียงอย่างเดียวไม่ทำให้ review ใช้โทเคนน้อยลง: วัดจำนวนการวิเคราะห์ซ้ำที่ลดลงจริง ไม่ใช้ความเร็ว API แทนผลทั้งงาน.
- receipt หลังคำขอป้องกันได้เฉพาะคำขอถัดไป: ไม่อ้างว่าเป็น hard cap ฝั่งผู้ให้บริการ. ยังไม่มีหลักฐานการบังคับเพดานต่อ request ฝั่ง Gateway; นโยบายปัจจุบันอนุญาตหักเครดิตฟรีได้ แต่ห้ามหัก paid balance.
- `marketCost` เป็นคนละช่องกับค่าเรียกเก็บใน receipt: ค่าที่มากกว่าศูนย์ไม่พิสูจน์ว่าบัญชีถูกหักเงินจริงแล้ว และค่า gateway เป็นศูนย์ครั้งเดียวไม่รับรองอนาคต.
- ทบทวนเอกสารเท่านั้นในรอบนี้; ไม่มี API call ใหม่ ไม่มีการเปลี่ยนบัญชีหรือ billing setting. Markdown และ JSON ใช้ P1–P6 ตรงกัน.

## ## ข้อจำกัดค่าใช้จ่ายและเงื่อนไขพัก

นโยบาย revision 5 ตามคำสั่งล่าสุดแทนการห้ามหักเครดิตฟรีใน revision 2: **ใช้ Free Credits $5 ได้;เงินจริง $0.** ตรวจหน้า Vercel จริงพบ `5.00 Free Credit` และ usage 1 request, 311 tokens, cost $0. ยอดนี้เป็น snapshot ไม่ใช่ยอดที่รับรองตลอดไป.

- ก่อนเรียก อ่านยอด free ที่เหลือและกันวงเงินสำหรับคำขอที่จะส่ง; ใช้ยอดต่ำกว่าระหว่างเครดิตคงเหลือจริงกับส่วนที่เหลือของวงเงินทดลอง $5. เครดิตอาจถูกงานอื่นใช้ร่วมกัน.
- หลังเรียก บันทึก actual cost และกระทบยอด; cost มากกว่าศูนย์อนุญาตได้เมื่อหักจาก free allowance เท่านั้น. `marketCost` ไม่ใช่ตัวเลขหักบัญชีโดยตรง.
- พักเมื่อเครดิตฟรีหมด หรือเหลือน้อยกว่าค่าสูงสุดที่คาดว่าคำขอถัดไปจะใช้; ไม่จำเป็นต้องใช้จนเหลือศูนย์พอดี. หยุดเมื่อยอด/ค่าบริการไม่ชัดเจนหรือมี paid deduction.
- ไม่ซื้อเครดิต ไม่เปิด auto top-up และไม่ย้ายไป paid balance. ตรวจ dashboard แล้วว่า Auto-reload is disabled; ไม่ได้เปลี่ยน setting.
- ส่งทีละคำขอ ไม่มี automatic retry/fallback. Timeout ที่ไม่ทราบ billing ต้องกระทบยอดก่อนส่งใหม่. การตรวจ receipt หลังเรียกไม่ใช่ hard cap ฝั่ง provider; ยังไม่ได้ติดตั้งระบบบังคับอัตโนมัติ.
- เมื่อโควต้ารอบนี้หมดให้พัก Jev live จนผู้ใช้สั่งต่อ ไม่กลับมาเรียกเองเพราะมีการเติมเครดิตฟรีรอบใหม่. งานพัฒนา/MCP ปกติทำต่อได้.

เกณฑ์ตรวจรับ

- สคริปต์ปฏิเสธการส่งเมื่อ cost gate ไม่ผ่าน และไม่มี network request ในเส้นทางนั้น.
- fixture/fake tests ครอบคลุมการ parse คำตอบ, malformed response, timeout, rate limit, redaction และการปิดใช้งาน โดยไม่ใช้ token จริง.
- Live smoke ถ้าทำได้ต้องมี receipt ที่ตรวจยอดอยู่ภายในเครดิตฟรี, route/model ชัดเจน และรายการ usage สอดคล้องกัน; ไม่ถือผลสังเคราะห์หนึ่งตัวอย่างเป็นการรับรองคุณภาพ.
- การประเมิน code review มี diff ที่ได้รับอนุญาต, ป้ายมนุษย์, held-out defects, metric ต่อ class, confidence/abstention, false-negative review และเวลา/โทเคนรวมพร้อมข้อจำกัด.
- ปิด adapter แล้ว LexiQuest และ workflow พื้นฐานทั้งหมดทำงานเหมือนเดิม; Jev ไม่อยู่ในเส้นทางหลัก.

## แหล่งอ้างอิงและหลักฐานใน repository

- TypeSafe [Introduction](https://docs.typesafe.ai/introduction), [Quickstart](https://docs.typesafe.ai/introduction/quickstart), [Confidence](https://docs.typesafe.ai/confidence), [ประกาศ Jev และข้อจำกัด benchmark](https://typesafe.ai/blog/introducing-system-one-models-and-jev).
- Vercel [หน้าโมเดล Jev](https://vercel.com/ai-gateway/models/jev), [ราคา AI Gateway](https://vercel.com/docs/ai-gateway/pricing).
- ผล probe สังเคราะห์และรายละเอียด receipt: [jev-free-probe.json](jev-free-probe.json). Key อยู่ใน DPAPI secret store ภายนอก repository; ห้ามเปิดเผยหรือ commit.


## คำสั่งใช้งานระหว่างพัฒนา — revision 5

ผู้ใช้กำหนดให้ลงมือเชื่อมและเรียก Jev ควบคู่กับงานพัฒนา สำหรับคัดกรองข้อผิดพลาดและเตรียม code review ที่เหมาะสม เมื่อระบบตรวจเครดิตฟรีพร้อมแล้ว การทำแผนอย่างเดียวไม่ถือว่าทำตามคำสั่งครบ ต้องมีหลักฐานการเรียกจริงและผลที่ใช้ช่วยงาน ไม่เรียกซ้ำเพียงเพื่อแสดงว่าใช้งานแล้ว ใช้เฉพาะเครดิตฟรีก้อนที่อนุมัติสูงสุด 5 USD; พัก Jev ก่อนเครดิตไม่พอหรือมีค่าใช้จ่ายเงินจริง และทำงานหลักต่อได้ ปัจจุบันมีเพียง synthetic smoke สำเร็จหนึ่งครั้ง ยังไม่ได้ติดตั้ง workflow เรียกใช้ระหว่างพัฒนาหรือระบบคุมเครดิต


## ตรวจความพร้อมก่อนเริ่ม — revision 5

ยืนยันใน UI: Free Credit 5.00 USD, Auto-reload disabled, No team budget. ยังไม่มี runtime guard จึงยังไม่ถือว่าได้บังคับวงเงินด้วยโค้ด ต้องทำ ledger ถาวร กันวงเงินก่อนส่ง ตรวจยอดจริงที่ใช้ร่วมกับงานอื่น และกระทบยอด timeout ก่อนส่งซ้ำ. การตรวจครั้งนี้ไม่มี API call ใหม่หรือการซื้อเครดิต.

งานแอปค้าง checkpoint114: test/screens/learning_pack_catalog_screen_test.dart มี late-attachment test ที่ยังล้มเหลวตาม build/catalog-owner-114-red.log ต้องวิเคราะห์ แก้ และทดสอบส่วนนี้ก่อน catalog detail/native build. Goal scheduler ยัง paused; การตรวจแผนนี้ไม่ใช่การ resume goal.

## Revision 6 — แผน Jev controller routing และ GODKILLER ZERO (2026-09-23)

ส่วนนี้เป็นสถานะและลำดับงานปัจจุบันแทนข้อความสถานะเก่าใน revision 5; P1–P6 ยังเป็นหลักฐาน pilot เดิม ไม่เริ่ม ledger ใหม่หรือรีเซ็ตยอดเดิม. งานผลิตภัณฑ์ LexiQuest ยังคงใช้แผนตรวจรับ 14 workflow/14 โหมดใน `optional-mcp-workflows.json` และแผนตรวจทั้งโครงการใน `post-mcp-project-review-plan.json`. Router เป็นเครื่องมือพัฒนาภายใน ไม่ใช่ dependency ของแอปหรือเงื่อนไขให้ลดเกณฑ์ตรวจรับ.

### ข้อเท็จจริงที่ตรวจได้ก่อนออกแบบ

- โปรแกรมในเครื่อง `C:/Users/Phet/Documents/GODKILLER ZERO/godkiller-console.exe` รายงาน v1.0.0; GUI รายงาน v1.0.0. ไฟล์ทั้งคู่มี SHA-256 ตรง `SHA256SUMS.txt` แต่ไม่มี Authenticode signature. นี่เป็นการตรวจตัวตนระดับไฟล์ ไม่ใช่การรับรองผู้ผลิต.
- `~/.gemini/mcp_config.json` ลงทะเบียน `godkiller-zero` ด้วย `--mcp`; `~/.gemini/GEMINI.md` มีกฎ hook หนึ่งบล็อก. มี process MCP รันอยู่ แต่ไม่พบ listener บนพอร์ตเริ่มต้น 4242. สถานะนี้ยืนยันการตั้งค่า MCP/hook เท่านั้น ไม่ยืนยันว่า proxy ดักทุกข้อความของ Antigravity.
- CLI มี `--repo-map`, `--prune`, `--purify`, `--gate`, `--run` และ MCP tools `gk_get_repo_map`, `gk_gatekeeper_scan`, `gk_claim_done`. Repo map เป็นแผนที่สัญลักษณ์จำกัด token; gate ตรวจรูปแบบ/complexity ไม่แทน Flutter/native/storage acceptance. `--purify` อาจพึ่ง local AI ต้องตรวจการทำงานและต้นทุนก่อนใช้จริง.
- ตัวเลขลด token ใน README เป็น lab note ของผู้พัฒนา ทำบน Cursor และโมเดลตัวอย่าง ไม่ใช่ผล LexiQuest/Antigravity. Hook `GEMINI.md` เองเพิ่ม context ทุกครั้งที่ถูกอ่าน; repo map/MCP และการแก้ prompt ก็มี overhead. ต้องวัด input, output, thinking/cache tokens และจำนวนรอบงานจริงก่อนสรุป.
- Router ใน `tool/experiments/jev_review/model_route.py` มี allowlist และ offline contract แล้ว แต่ยังไม่เรียก Jev เพื่อตัดสิน route จริงและยังไม่ dispatch worker. Jev เป็น typed judgment (`Choice`/`Score`/`Noul`) ไม่ใช่ coding agent. เอกสารผู้พัฒนาระบุข้อจำกัดด้านตัวเลข, state ยาว, indirection และ adversarial content; การคำนวณ quota/ราคา/ความถูกต้องของหลักฐานต้องทำด้วยโค้ด.

แหล่งตรวจ: [GODKILLER ZERO README](https://github.com/taurus42119-stack/GODKILLER-ZERO), [MCP implementation](https://github.com/taurus42119-stack/GODKILLER-ZERO/blob/main/src/proxy/mcp.rs), [Antigravity headless](https://antigravity.google/docs/cli/headless/), [Antigravity best practices](https://antigravity.google/docs/cli/best-practices/), [Jev limitations](https://docs.typesafe.ai/model-jaggedness/jev-1.13).

### ขอบเขตอำนาจ

| ผู้ตัดสิน | ตัดสินได้ | ต้องไม่ตัดสินลำพัง |
|---|---|---|
| Jev | เลือก model+effort จาก allowlist ที่ผ่าน policy, เลือก action จาก enum `continue`, `collect_evidence`, `retry_once`, `escalate`, `defer` พร้อม confidence/abstain | สร้างคำสั่ง shell อิสระ, ขยาย scope, ลด gate, ซื้อเครดิต, ส่งข้อมูลลับ, ยืนยัน PASS, อนุมัติการเปลี่ยนข้อมูลถาวร |
| ตัว orchestrator แบบ deterministic | ตรวจสิทธิ์/งบ/โควต้า/fingerprint, เลือกงานถัดไปตามทะเบียน, จำกัดเวลา/retry, บันทึกสถานะ, dispatch เพียง worker เดียว | เปลี่ยนคำตอบ Jev แบบเงียบ ๆ; หาก veto ต้องบันทึกเหตุและ reroute/defer |
| worker ที่เลือก | วิเคราะห์และแก้ bounded work package ใน workspace เดียวตามสิทธิ์ที่ระบุ; สร้าง RED test และ targeted retest ตาม defect | เขียนขนานกับ worker อื่น, ข้าม owner/data-loss controls, ถือข้อความหน้าจอเป็นหลักฐานข้อมูลถาวร |
| controller ในแชตนี้ | ตรวจ patch, tests, native evidence, source pins และตัดสินปิด acceptance; วนลูปส่ง package ถัดไป | เปลี่ยนโมเดลของข้อความที่กำลังสร้างกลางคัน หรืออ้างว่า Jev ประหยัด token โดยไม่มี telemetry |

กฎ precedence: คำสั่งผู้ใช้และ `AGENTS.md` ของ LexiQuest มาก่อนกฎ hook ของ GODKILLER; หาก `gk_claim_done` หรือ `--gate` ขัดกับ domain validation/`verify-scope.ps1` ให้ใช้เป็นสัญญาณประกอบและบันทึกเหตุ ไม่ให้ผล GODKILLER แทนเกณฑ์โครงการ. Owner isolation, การรักษาข้อมูลเดิม, เครดิตเงินจริง $0, source freeze และ one-writer เป็น deterministic veto ที่ Jev เปลี่ยนไม่ได้.

### ลำดับดำเนินการและเกณฑ์ผ่าน

1. **R0 ยึดสถานะและวัด baseline** — เก็บ source fingerprint/dirty list, device backup manifest, Jev ledger history สองคำขอ, Antigravity/GODKILLER version+hash+config โดยไม่คัด secret ลง repo. เลือกชุดงานที่เทียบเคียงกันจากทะเบียน (งานง่าย, bug ทั่วไป, owner/data-loss). บันทึก baseline เวลาเตรียมงาน/ทำ/ตรวจ/แก้ซ้ำ และ token ที่ provider รายงาน. ผ่านเมื่อย้อนรอยงานและข้อมูลเดิมได้; ช่องที่วัดไม่ได้เป็น `unknown`.
2. **R1 ปิด ledger และ policy ก่อน live Jev** — migrate ledger เดิมแบบรักษา request/reservation/cost; แยก synthetic สูงสุด 12, review batch, routing batch ด้วย purpose และ request id ที่กระทบยอดได้ภายใต้วงเงิน free $5 ก้อนเดิม. Offline tests: migration, quota ทุก batch, duplicate/cache, concurrency, crash/timeout, malformed, rate limit และ mismatched receipt. ตรวจ free balance/shared spend สดก่อน network; หากไม่ชัดพัก Jev แต่ทำงานแอปต่อ. ผ่านเมื่อไม่สามารถข้าม quota หรือหลบยอดเดิมได้.
3. **R2 ตั้งสัญญา routing/incident แบบปิด** — ใช้ pool ที่ตรวจได้: Antigravity `gemini-3.8-flash-{low,medium,high}`; Codex Astra/Sol/Luna `low,medium,high,xhigh,max` ตาม CLI ที่ตรวจ (light→low, extra high→xhigh; `ultra` เป็น unsupported ในเส้นทาง CLI จนพิสูจน์ได้). Jev เลือกจาก eligible shortlist เท่านั้น; owner/data-loss มี risk floor; confidence ต่ำ/ไม่ชัดคืน `defer`. Incident enum มี precondition, max attempts, deadline, abort. ผ่าน offline cases รวม quota หมด, command fail ซ้ำ, stale source, evidence conflict และ prompt injection.
4. **R3 ทดลอง GODKILLER แบบแยกองค์ประกอบ** — บันทึก current hook/MCP โดยไม่แก้ global settings; ทดลอง `repo-map`/`prune` บน fixture ที่ไม่ลับและวัดความครบของพิกัด, source pin และ token budget. ทดสอบ `purify` เฉพาะหลังรู้ว่าใช้ local model/เครือข่ายใดและมี redaction. เทียบ Antigravity task เดียวกันแบบ A/B: baseline, hook+MCP, และ proxy เฉพาะเมื่อพิสูจน์การเชื่อมต่อ/การส่งข้อมูล/rollback ได้. เก็บ actual provider usage ไม่ใช้ estimated chars/4 หรือ README แทน. หาก context ที่ย่อขาด owner provenance, defect steps หรือ acceptance criteria ให้ fallback เต็มและนับ rework.
5. **R4 ต่อ reviewed sequential dispatcher** — รับ Jev route, ตรวจ policy อีกครั้ง, สร้าง prompt สั้นที่มี task id, source fingerprint, invariant, file scope, acceptance, targeted gate และ stop conditions; ส่งผ่าน CLI ที่เลือกทีละ work package. ก่อน dispatch ยืนยัน model availability/quota และ cwd `d38e`; หลังงานบันทึก argv, exit, usage, diff, test artifacts, incident choice และ veto reason. ห้าม auto-retry ที่ไม่ idempotent; ไม่เปิด parallel writers. ผ่านเมื่อ dry-run และงานเสี่ยงต่ำหนึ่งงานมี audit trail ครบ โดย controller ตรวจ patch ก่อน package ถัดไป.
6. **R5 ค่อยเปิดลูปกับ LexiQuest** — ใช้ทะเบียนเดิมตามลำดับความเสี่ยง: owner isolation → data loss/duplicate → baseline → context/feedback → UI. แต่ละ defect: reproduce → RED → root cause → fix → targeted `verify-scope.ps1` → native retest เมื่อเกี่ยวข้อง. ยึด checkpoint สั้นทุกจุดสำคัญและไม่รัน gate ที่ fingerprint ไม่เปลี่ยน. Godkiller เป็นตัวช่วยหา scope/check hygiene; PASS ของ 14/14 ต้องมาจากเกณฑ์ host/native/provider/persistence ที่แยกกัน. หาก incident อยู่ใน enum และ precondition ผ่าน Jev เลือกทางต่อได้; นอก enum หรือมี deterministic veto ให้หยุดเฉพาะ route นั้นและทำ package อื่นที่ได้รับอนุญาตต่อ.
7. **R6 ประเมินก่อนเปิดประจำ** — เทียบ task ที่เทียบเคียงกันและนับเวลารวม controller+Jev+GODKILLER+worker+rework; token และค่าใช้จ่ายแยก provider พร้อม cache/unknown. เกณฑ์คงใช้: ไม่ลดการตรวจ owner/data loss, คุณภาพไม่ต่ำลง, median end-to-end time ดีขึ้นอย่างน้อย 20% ตาม pilot เดิม. ถ้า token ของ controller ไม่มี telemetry ห้ามอ้างประหยัด token รวม; หากหลักฐานไม่พอรายงาน `ยังสรุปไม่ได้` และคง manual/reviewed mode.

การแก้เฉพาะหน้า: response Jev malformed/timeout → reconcile reservation ก่อน retry; quota/model unavailable → เลือก eligible shortlist ใหม่หนึ่งครั้งหลังตรวจสด; source เปลี่ยนระหว่างงาน → หยุดและ rebase task context; คำสั่งล้มเหลวซ้ำหรือไม่คืบ 10 นาที → หยุด package ตาม `AGENTS.md`; GODKILLER omission/conflict → ใช้ source ต้นฉบับและ gate โครงการ; ข้อมูลบนอุปกรณ์ผิด/restore ไม่ผ่าน → freeze งานที่กระทบข้อมูล, เก็บหลักฐาน, กู้คืนจาก backup ที่ตรวจ hash แล้ว. ทุกกรณีบันทึกผู้ตัดสิน เหตุและผล ไม่ให้ Jev สร้างวิธีแก้ใหม่โดยไม่มีขอบเขต.

หลัง acceptance ของขอบเขตปัจจุบันจึงเข้า `post-mcp-project-review-plan.json`, freeze source, endurance จริง 180 นาที และ full release verifier บน frozen SHA ตามแผนเดิม. แผน router นี้ไม่อนุญาต deploy, paid fallback, research activation หรือการใช้งาน production โดยอัตโนมัติ.

## Revision 7 — แผนพัฒนาต่อและการตัดสินใจเมื่อเกิดเหตุ (2026-09-23)

ส่วนนี้เป็นลำดับปฏิบัติการล่าสุดของ revision 6 และแผน 14/14 ที่ผู้ใช้อนุมัติแล้ว; ข้อความประวัติก่อนหน้านี้ยังคงเป็นหลักฐาน ไม่ใช้เป็นสถานะปัจจุบัน. เป้าหมายคือปิด acceptance ของ LexiQuest โดยให้ Jev ช่วยเลือกโมเดลและทางแก้เฉพาะหน้าที่มีขอบเขต และให้ GODKILLER ลดการอ่าน context ที่ไม่จำเป็นเฉพาะเมื่อพิสูจน์ว่าข้อมูลสำคัญไม่หาย. ไม่มีการเปลี่ยนโมเดลของข้อความที่กำลังตอบในแชตนี้. คำขอล่าสุดของผู้ใช้ให้ Jev เลือกจาก GPT-6/Gemini pool เป็นการปรับกติกา model สำหรับ worker ในโครงการนี้; Standard/default tier, one-writer, no background implementation และงบเงินจริง $0 ยังคงเดิม.

### ผลวิเคราะห์ที่เปลี่ยนการออกแบบ

1. [TypeSafe confidence routing](https://docs.typesafe.ai/patterns/confidence-routing) ให้ใช้ confidence เป็นเงื่อนไขลงมือ ไม่ใช่ตัวตัดสินความจริง. [ข้อจำกัด Jev 1.13](https://docs.typesafe.ai/model-jaggedness/jev-1.13) ระบุว่าคณิตศาสตร์, state ยาว, indirection และข้อความชักจูงมีความเสี่ยง. ดังนั้น deterministic code ต้องคำนวณราคา/โควต้า/เวลา, ตรวจ policy และ source pin ก่อนและหลัง Jev. Jev ตอบได้เพียง `Choice` ที่มีคำอธิบายชัดเจนพร้อม `defer`.
2. GODKILLER 1.0.0 ที่ตั้งค่าในเครื่องเป็น hook `GEMINI.md` + MCP; การอยู่ใน MCP config ไม่เท่ากับ proxy ของ Antigravity ทำงาน. [ซอร์ส proxy handler](https://github.com/taurus42119-stack/GODKILLER-ZERO/blob/main/src/proxy/handlers.rs) เพิ่มตัวนับ `tokens_preserved` จากส่วนต่างความยาวข้อความหาร 4 และสร้าง `usage` บาง response จากความยาวข้อความ; [repo map](https://github.com/taurus42119-stack/GODKILLER-ZERO/blob/main/src/domain/repo_map.rs) จำกัดผลด้วยสูตรอักขระหาร 4 เช่นกัน. ตัวเลขเหล่านี้เป็น heuristic ภายใน ไม่ใช่ provider billing/usage. นอกจากนี้ซอร์ส `main` ที่อ่านอาจไม่ตรง binary ในเครื่องทุกบรรทัด; ต้องยึด CLI behavior ที่วัดจริงเมื่อทดลอง.
3. [Antigravity headless JSON](https://antigravity.google/docs/cli/headless/) แยก input, output, thinking, cache-read tokens และเวลาได้ แต่ `usage` ของ session อาจเป็น cumulative; เก็บ per-run หรือ delta ที่ไม่ซ้ำ. Codex/controller ถ้าไม่มี telemetry ให้ `unknown`. ไม่รวมจำนวน token ต่าง provider เป็นค่าเงินหรือหน่วยความคุ้มค่าเดียวโดยไม่มีราคาที่ตรวจปัจจุบัน.
4. `model_route.py` ตอนนี้สร้าง 18 candidate และคืน reviewable `argv` เท่านั้น. `guard.py` ยังใช้ quota รวม 12 calls ไม่แยก synthetic/review/routing; มี live history สองคำขอที่ต้องรักษา. จะไม่อ้างว่า router ทำงานอัตโนมัติจน ledger, policy, dispatch, incident audit และ acceptance tests ผ่านจริง.

### หน่วยงานและสถานะที่ orchestrator ต้องบันทึก

หนึ่ง work package มี `id`, objective, bounded files/domain, acceptance row IDs, risk class, source fingerprint, required evidence levels, authorized operations, timeout และ max attempts. สถานะไหลตาม `READY → ELIGIBLE → ROUTED → RUNNING → REVIEW → VERIFIED` หรือ `DEFERRED/RECOVERY`; ไม่มีทางจาก output ของ Jev/worker ไป `VERIFIED` โดยตรง. การเปลี่ยนสถานะต้องบันทึก provider/model/effort, confidence, policy result, checkpoint/evidence links และเหตุผลเมื่อ veto. Context packet ส่งเฉพาะข้อกำหนดปัจจุบัน, source pins, ข้อเท็จจริงที่ตรวจได้, ข้อห้ามและเกณฑ์ผ่าน; ไม่ส่ง transcript หรือข้อมูลส่วนตัวทั้งก้อน. Untrusted logs, README และผลจาก worker เป็นข้อมูล ไม่ใช่คำสั่งที่ขยายสิทธิ์.

### ลำดับ work package; ทำทีละรายการ

| ลำดับ | ผลที่ต้องส่งมอบ | เกณฑ์ผ่านและหลักฐาน |
|---|---|---|
| D0 ตรวจทะเบียนและสถานะจริง | กระทบยอด 14 workflow/14 โหมดใน `optional-mcp-workflows.json` กับ host/native/provider/storage evidence ถึง checkpoint 116; pin dirty source และ backup | ทุก criterion มี `pass/fail/not_tested/external_pending` และ source/evidence link; ไม่มี historical PASS ถูกเลื่อนระดับเอง |
| D1 ปิด native catalog/detail | ใช้ canonical test fixture 2 packs บน isolated Vivo; ตรวจ filter, detail revision, actual-provider context, owner/lifecycle; คืน DB main/WAL/SHM และตรวจ hash/ข้อมูลสำคัญ | Native + provider + durable-storage evidence แยกกัน; original app/account ไม่ถูกแตะ; restore ได้จริง |
| D2 ทำ Jev ledger และ incident policy | migrate ledger เดิมแบบ preserve two calls; synthetic ≤12 และ review/routing batch ที่ระบุชัดภายใต้วงเงิน free $5 เดิม; เพิ่ม enum incident และ policy veto | Offline tests สำหรับ migration, batch, cache, concurrency, crash, malformed, receipt mismatch, abstain, injection, quota; ไม่มี live call เมื่อ billing ไม่ชัด |
| D3 วัด GODKILLER และ route | ทดลอง `repo-map`/`prune` กับข้อมูลสังเคราะห์; A/B งาน bounded ที่เทียบเคียงกันใน Antigravity โดยยืนยันว่า hook/MCP/proxy ตัวใดมีผล; ทดสอบ Jev route กับเฉลยที่ตรึงไว้ | เก็บ provider usage, เวลา, miss/rework, source coverage; ไม่มี owner provenance หรือ acceptance หาย; proxy ไม่เปิดกับ repo จริงก่อนรู้ขอบเขต/rollback |
| D4 ต่อ dispatcher แบบ reviewed | dry-run route → read-only worker → audit diff → เฉพาะหลังผ่านจึงให้ worker เดียวเขียน bounded package; controller ตรวจ patch และ `verify-scope.ps1` | CLI model/effort ตรงกับ Jev ที่ผ่าน policy; cwd/source pin ตรง; no parallel writer; failure/retry audit ครบ; เก็บ argv โดยไม่เก็บ secret |
| D5 ปิด 14/14 ตาม risk | owner isolation → data loss/duplicate → baseline no AI/login → context/feedback → UI; ตรวจทุกสถานะการเชื่อมและทิศทางที่รองรับ | RED/repro/root cause/fix/targeted gate/native retest; คะแนน XP rewards/history เทียบข้อมูลถาวร; speech/camera/export/sync ใช้หลักฐานระดับจริง; external prerequisite ไม่กลายเป็น PASS |
| D6 ตรวจทั้งโครงการ | ใช้ `post-mcp-project-review-plan.json` เมื่อ D5 ปิด; coverage matrix และ defect ledger ทุก subsystem; แก้เป็น increment เดียวตามความเสี่ยง | ทุกส่วนมีสถานะ; confirmed defects มี retest หรือ prerequisite ภายนอกที่จำเป็นจริง; migration/rollback ตรวจเมื่อ schema เปลี่ยน |
| D7 ปิด release evidence | freeze source; affected regression/native, endurance จริง 180 นาที, full verifier บน frozen SHA | ไม่มี RED ค้าง, source/evidence ตรงกัน, checkpoint/crash/ANR/resource/data reconciliation ครบ; ไม่มี deploy อัตโนมัติ |

D0/D1 มาก่อนการเปิด dispatcher เพราะข้อมูลเดิมและเกณฑ์ native เป็นความเสี่ยงสูงที่ค้างอยู่; D2/D3 เป็น tooling increment ถัดมาและห้ามทำขนานกับ D1. หาก Jev live พักเพราะ billing ให้ D5 ดำเนินต่อด้วย workflow ที่ได้รับอนุญาตและบันทึก routing เป็น pending. ไม่บังคับให้ทุกงานต้องเรียก Jev: กฎตายตัว/งานเล็กที่ตัวเลือกชัดใช้ deterministic route เพื่อไม่เพิ่ม latency/token ฟรี ๆ.

### ตารางตัดสินใจเมื่อเกิดเหตุเฉพาะหน้า

| เหตุที่สังเกตได้ | อำนาจ Jev หลังกรอง policy | การลงมือและขอบเขต |
|---|---|---|
| Jev timeout/response ผิด schema/receipt ไม่ตรง | `defer` เท่านั้น | คง reservation pending, ตรวจ provider log/billing จาก request id ก่อนส่งใหม่; ห้าม retry network อัตโนมัติ |
| โมเดลหมด quota หรือ unavailable | `reroute_once` จาก eligible shortlist ที่ตรวจสด หรือ `defer` | ตรวจ quota/capability อีกครั้ง; ไม่มี paid fallback และไม่ลด risk floor; หาก route ใหม่ไม่พอให้ทำงานอื่น |
| RED test หรือ command ล้มเหลวซ้ำ | `collect_evidence`/`escalate` | หยุดวิธีที่ล้ม ไม่ใช่หยุดทั้งโครงการ; inspect logs/path/symbol, แก้สาเหตุและ targeted retest; ไม่ retry blind หรือข้าม assertion |
| Source fingerprint เปลี่ยนระหว่าง worker ทำงาน | ไม่มีสิทธิ์ override | หยุดการใช้ผล route/patch, ตรวจ diff ใหม่และ rebase context packet; หลักฐานเก่าไม่รับรอง source ใหม่ |
| GODKILLER map/purify ตัดข้อกำหนดหรือบิดความหมาย | `defer` หรือ `collect_evidence` | กลับไปอ่าน canonical source; แยก GODKILLER ออกจาก package นั้น; นับ overhead/rework ใน A/B |
| Owner leak, data loss, duplicate write หรือ restore mismatch | `escalate` ภายใต้ risk floor; ห้าม `continue` | เก็บ snapshot, หยุด mutation ที่เสี่ยง, กู้ isolated backup ที่ตรวจ hash, reproduce/RED/root cause แล้วแก้; controller ตรวจข้อมูลถาวรก่อนปิด |
| Vivo/USB, actual provider, speech/camera หรือ hosted sync ใช้ไม่ได้ | `collect_evidence`/`defer` | ทำ host/offline checks ที่แยกหลักฐานได้; ทำเครื่องหมาย native/provider/external pending ตามจริง; ไม่ใช้ mock แทนผลจริง |
| Worker บอกเสร็จแต่ gate/evidence ไม่ครบ | ไม่มีสิทธิ์ยืนยัน PASS | controller คืน package ไป `RECOVERY`, ระบุเกณฑ์ที่ขาด, ตรวจบน source เดิมหรือ source ใหม่ตาม fingerprint |

Jev ได้รับเหตุการณ์แบบ structured ที่ผ่าน redaction และเลือกจาก action ที่ incident type อนุญาตเท่านั้น. ตัว orchestrator คำนวณ retry count/deadline และบังคับ hard stop. หาก Jev ไม่มั่นใจหรือ input ไม่ครบให้ `defer`; controller/worker แก้ปัญหาที่อยู่ในขอบเขตผู้ใช้อนุมัติได้โดยไม่ต้องถามซ้ำ. หากต้องมีบริการภายนอกที่ขาดจริง ให้บันทึก prerequisite เฉพาะรายการนั้น แล้วทำงานอิสระที่ยังทำได้ต่อ.

### วิธีพิสูจน์ความคุ้มค่าและเงื่อนไขเปิดประจำ

ทดลองบนงานเทียบเคียงกันอย่างน้อยสามชั้นความเสี่ยงและสลับลำดับ A/B เพื่อจำกัด learning effect. เวลารวมเริ่มตั้งแต่เตรียม context ถึง controller รับ patch และปิด evidence; รวม Jev call, GODKILLER call, worker, test, rework และ incident handling. รายงาน `median_end_to_end_seconds`, defect escape/false-safe, acceptance completeness, provider tokens แยก input/output/thinking/cache, actual free-credit debit และช่อง `unknown`. ค่า GODKILLER `tokens_preserved` เป็น diagnostic เท่านั้น. ใช้ Jev+GODKILLER ประจำต่อเมื่อ owner/data-loss false-safe เป็นศูนย์, คุณภาพไม่ลด และ median time ดีขึ้น ≥20% ตาม pilot เดิม; ถ้าตัวอย่างหรือ telemetry ไม่พอ สถานะ `ยังสรุปไม่ได้`. ไม่อ้างประหยัด controller/Codex token จาก usage ของ Antigravity เพียงอย่างเดียว.

ทุก checkpoint บันทึกผลล่าสุด, source/APK hash, evidence, open defect, Jev ledger status, route/GODKILLER mode และ next bounded package ใน `continuation-checkpoint.json`. ปรับแผนเมื่อพบเหตุใหม่ด้วย decision record ที่อ้างหลักฐานและแก้เฉพาะขั้นที่ได้รับผลกระทบ; คง requirement ID และเกณฑ์ผ่านเดิมเพื่อไม่ให้การแก้เฉพาะหน้ากลายเป็นการลด scope.

