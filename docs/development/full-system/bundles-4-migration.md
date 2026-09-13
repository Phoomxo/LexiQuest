# เปลี่ยน workflow หลัง G0.5

Revision 2026-09-13-bundles-4 · base 9125ae7b9ccff15bb44ebbab455b8b0251c8fcfe

เปลี่ยนเป็น **20 bundles สำหรับ59packagesที่เหลือ**. เก็บG0.1–G0.5เป็นacceptedhistory และคง64requirements/dependencies/acceptanceทั้งหมด. Packagebriefเป็นrequirement unit; dispatchเฉพาะbundleจบ

ตรวจผ่าน:64IDsครั้งเดียว, 5historyไม่redispatch, 59remainingครบ, 20bundlechain, dependency/phase order, reviewก่อนTest Plan, technicalbrief bodiesเดิมครบ64, coverage/source traceabilityเดิมครบ74rows, active links611, ไม่มีapplicationchangesหรือfutureduplicate dispatch. [ผลตรวจและปัญหา](evidence/bundles-4/verification.json) · [Source manifest](evidence/bundles-4/source-manifest.json)

เริ่มB01 G0.6–G0.8จากacceptedorchestrationcommitที่ต่อจากG0.5. ActualSHA/receiptอยู่external orchestrationhandoffหลังcommit. Masterไม่ทำapplicationpackagesและไม่ได้รันFlutter/backend/build/GPU/releasegatesเพิ่ม
