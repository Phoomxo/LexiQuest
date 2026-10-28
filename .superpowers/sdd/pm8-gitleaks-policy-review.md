# PM8 Gitleaks synthetic fixture policy review

ผลสุดท้าย **PASS สำหรับ3 synthetic findings และ corrected V3 rule-targeted policy พร้อม actual positive/negative controls**. Initial global policy เป็น retained FAIL: baseline7/new-global3 ซ่อน same-path mutated token. Initial static scope PASS ถูกถอนและ superseded; corrected V3 เพิ่ม `targetRules = ["generic-api-key"]` ในทั้ง2new blocks และ actual control report ยืนยัน baseline7/current4 ต่างกันเฉพาะ3ค่า/path ที่อนุมัติ. ไม่พบ secret จริงใน3ค่าที่จำแนก. Actual full repository-scope scan reruns ยังเป็น root-owned งานถัดไป ไม่ถูกอ้างผ่านใน report นี้.

ตรวจแบบ read-only ใน `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest` วันที่2026-09-07. อ่าน original redacted scanner report `build/verification/1875a61854490e0493cc084bffb705f5d3bd4b0b/pm8-20260907T051654323Z-gitleaks-test.report.json`, exact source contexts, local lease implementation, config diff และ ignored control fixture/report. ไม่รัน scanner/test/build หรือ rehash104 source inputs. เขียนเฉพาะ report นี้.

## Classification

| Finding | Exact synthetic value | Verified use |
| --- | --- | --- |
| `pair_matching_compatibility_rollout_test.dart:425` | `pm8-synthetic-owner-gate` | `PairHarness()` ใช้ `NativeDatabase.memory()`; fixed value ใช้ acquire/release `DriftOwnerOperationGate` และ ownerGateToken ของ local `DriftSyncStore.claimPending` ใน reader/writer rollout fixture |
| `pair_measurement_boundary_test.dart:985` | `pm7-synthetic-claim-gate` | `PairMeasurementFixture` ใช้ base `MotivationResearchFixture` ที่สร้าง `NativeDatabase.memory()`; fixed local runtime_flags lease identity สำหรับ acquire/release และ claim fencing |
| `pair_measurement_boundary_test.dart:999` | `pm7-synthetic-claim` | Fixed outbox claim lease identity; `DriftSyncStore.claimPending` บันทึก `canonicalLeaseToken` ใน local `outbox_operations.leaseToken` และ returned claim |

`DriftOwnerOperationGate` ใช้ token เป็น local SQL `runtime_flags.source` เพื่อเปรียบเทียบ lease ownership/expiry. ค่าเหล่านี้ไม่ได้เป็น Firebase login token, API credential, consent receipt หรือ private signing key. การค้น bounded `lib`/`test` พบแต่3ตำแหน่งข้างต้น. Measurement fixture ใช้ real authority/signature behavior ภายใน synthetic data แต่3ค่านี้ไม่ใช่ signature/permit credentials. ไม่มีเหตุผลให้เปลี่ยน production/test logic เพื่อหลบ scanner.

## Initial policy static scope — superseded by runtime controls

Initial `.gitleaks.toml` SHA-256 `e2bd2920575b6b388c6be132b839f4437d5ea80f10e558bc88ea7f1bc4407309`. Initial Git diff มี14 added lines:2 global `[[allowlists]]`; ไม่มี lib/test/AGENTS diff ใน read-only scope check. ส่วนนี้เก็บเหตุผล static review เดิมเพื่ออธิบายว่าทำไม empirical controls จำเป็น; ไม่ใช่การอนุมัติ global version.

- Default rules ยังเปิดผ่าน `useDefault = true`.
- ทั้ง2รายการใช้ `condition = "AND"`, `regexTarget = "secret"`, exact end-anchored test-file paths และ exact `^...$` secret patterns.
- Compatibility path อนุญาตเพียง1ค่า; measurement path เพียง2ค่าที่จำแนกแล้ว. ไม่เพิ่ม wildcard secret, directory-wide exclusion, rule disabling, line-number blanket ignore หรือ production-path exception.
- `(?:^|/)` อนุญาต repository-relative หรือ prefixed path ที่ลงท้าย exact test path ซึ่งสอดคล้อง existing policy และทำให้ ignored fixture tree จำลอง relative paths ได้. Exact secret suffix/prefix mutation ไม่อยู่ใน regex ที่เพิ่มนี้.

## Retained initial control failure

Current retained control report มี3 findings ตรง3ค่าเดิมที่ `unallowlisted_lease_test.dart`, แสดงว่ายัง detect same-value/other-path controls. Expected fourth finding `pm8-synthetic-owner-gate-changed` ที่ allowlisted path ไม่ปรากฏ. Static regex review ยืนยันค่า suffix นี้ไม่ match `^pm8-synthetic-owner-gate$`; แต่ static review เพียงอย่างเดียวไม่พิสูจน์สาเหตุ runtime scanner behavior. จึงต้องรอ root's original-policy baseline/control correction ก่อนอ้างว่าพิสูจน์ same-path/different-secret detection แล้ว. ห้ามลด expected4เป็น3เพื่อซ่อนข้อสงสัยโดยไม่มี baseline evidence.

## Corrected V3 final review

อ่าน final diff และ actual `pm8-gitleaks-controls-v3.metadata.json` / `pm8-gitleaks-controls-v3-exact.report.json` เทียบ retained `pm8-gitleaks-controls-v2-baseline.report.json`. Current config raw SHA-256 `e7a3624f0c1f7cc8eb9e076103ae6f521d1778ba77e9d488997cd4e7fb2f22a0` ตรง V3 metadata. Final diff16 added lines เพิ่ม `targetRules = ["generic-api-key"]` ใน2new blocks; ไม่แก้ existing policy blocks หรือ disable default rules.

Baseline actual report มี7 `generic-api-key` findings. V3 actual report เหลือ4: compatibility fixture line3 คือ `qm8-synthetic-owner-gate` ที่ path อนุญาต และ unallowlisted fixture lines2/3/4 คือ3ค่าเดิมในอีก path. Report delta ตัดเฉพาะ compatibility line2 และ measurement lines2/3 ซึ่งเป็น exact3 synthetic values/path ที่อนุมัติ. Metadata บันทึก native exit1/expected1 ถูกต้องเพราะ fixture จงใจมี4 remaining detections; `policyControlsPassed=true` จึงไม่ใช่การนำ scan failure มาตีความ green โดยไม่มี expectation.

Suffix `-changed` control ในรอบแรกไม่ detect แม้ baseline จึงถูกเปลี่ยนเป็น one-character mutation ที่ baseline detect; original failure ยังเก็บไว้. V2 ยัง fail เพราะ global-path semantics แล้ว V3 targeted rules จึงแก้ root cause ตาม actual controls. ไม่มีการลด expected4เป็น3หรือขยาย ignore เพื่อเอา green.

**Final bounded verdict: classification PASS, corrected-policy scope PASS, actual V3 control reconciliation PASS.** ไม่มี open finding ใน2new rule-targeted blocks. Initial global policy ไม่ได้รับอนุมัติและถูกแทนแล้ว. Root ต้องเก็บ initial findings/control failures และรัน9 bounded Gitleaks scopes บน corrected policy พร้อม recorded hashesก่อน local evidence finalization; review นี้ไม่อ้างว่ารันเหล่านั้นผ่านแล้ว. ไม่มี source/rollout/research authority เปลี่ยนจาก review นี้.
