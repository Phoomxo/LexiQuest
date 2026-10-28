# PM8 UI / Voice correction review

## Verdict

**Correction quality: Approved.** Important I1 และ I2 จาก `pm8-branch-ui-review.md` แก้ตรงสาเหตุแล้ว และไม่พบ Critical/Important ใหม่ใน correction ที่ตรวจ การอนุมัตินี้เป็น source-review gate เท่านั้น; affected run ที่ผู้รับผิดชอบกำลังรันและ full release gates ยังต้องตรวจผลบน frozen source ก่อนสรุป engineering acceptance.

## Scope / identity

- Exact worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`, HEAD `3bdb5f5605e670e8b30628f3f237cd9c0d660ad9` plus correction. ใช้ reviewer template/common brief และ approved runtime-owner/lease/active-clock contract จากรอบก่อน ไม่มี broad rereview ของ 50 paths เดิม.
- อ่าน `.superpowers/sdd/pm8-branch-correction.diff` ครบครั้งเดียวเป็น nonoverlapping chunks: 59536 bytes, independently verified SHA256 `3955156c4b3633afc36b43ca4c5e025d2cf6b25fbfece86551122f26088dbec8`.
- Wave manifest `.superpowers/sdd/pm8-branch-correction-wave-manifest.json`: SHA256 `d6d979f1e11ce1d12804962b49923505e1e2dc644d41a6ef13dcc9a5b86ea798`; ตรวจ raw before hashes ของทั้ง10 paths ตรงทั้งหมด. Current frozen23 manifest `.superpowers/sdd/pm8-branch-correction-frozen-manifest.json`: SHA256 `6785c321b489f23467d6f9164693e6a0ba93a46b2ec6842fab0bdb0a7dac374e`; independently hashed current23 paths, zero mismatches.
- UI assessment ครอบคลุม changed host/host tests และ Voice models/native provider/orchestrator/facade/tests ทั้งหมด รวม source ใหม่ต่อ original branch packet คือ `voice_use_cases.dart` และ test. อ่าน surrounding owner/conditional-stop/barrier/disposal logic เฉพาะเพื่อพิสูจน์ integration. Generic repository close correction เป็น engine/boundary-owned verdict ไม่อนุมัติแทน reviewer นั้น.
- Read-only; ไม่รัน Flutter/Dart/pub/dependency/test/build/scanner/Git mutation และไม่แก้ source. เขียนเฉพาะ report นี้.

## Finding disposition

### Important I1 — Resolved

`lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart:1359` แยก desired route state ออกจาก busy state ผ่าน `_routeWantsInteraction`; cover ตั้ง false และ resume ตั้ง true. `_reconcileRoutePause` ถูกเรียกทั้งตอน resume และหลัง initialization/operation เสร็จ (`:1004`, `:1032`) จึงปลด exact cover lease ที่เคยค้างหลัง returned-while-busy ได้ โดยยังตรวจ mounted, attached, live owner, coordinator และ busy. การ cover ซ้ำยังใช้ lease เดิมและ desired state ล่าสุด ไม่ใช้ timer/delay เดาว่าหน้าจอพร้อม.

Regression ใช้ real accepted canonical write, observed PageRoute cover+pop ขณะ write ยังถูก hold แล้วปล่อย acknowledgement; ตรวจ `boardUnavailable` หายและ full/challenge/remaining elapsed เป็น2000/2000/58000ms. RED เดิมแสดง exact `boardUnavailable` ค้าง. Test นี้ผ่านใน intermediate focused1 (ไม่ได้อยู่ในสอง failing tests); final covering rerun ยังต้องรับผลจาก sole executor.

### Important I2 — Resolved

- Host `:1303` ใช้ `VoiceSession.speakUntilCompleted` ซึ่งแยกจาก existing `speak` start-ack API. `VoicePlaybackResult.playbackCompleted` เป็น optional per-playback Future; orchestrator ส่ง object เดิมผ่านโดยไม่เปลี่ยน local-only flag หรือ telemetry payload.
- `lib/voice/native_tts_provider.dart:113` ให้ natural-completion proof กับ exact active completer. Explicit stop ถอด active identity ก่อน await native stop (`:141`), และ interruption/error ทำให้ completion proof unavailable ตลอดอายุ adapter นี้. เหตุผลถูกต้อง: flutter_tts callback ไม่มี utterance ID จึงไม่ควรรับ late untagged event เป็น completion ของเสียงใหม่. Ordinary speech ยังใช้ start-ack ได้; Pair เมื่อไม่มี proof จะ confirm stop แล้วแสดง text fallback. ไม่ทำ timeout เป็นหลักฐานว่าเสียงจบ.
- `lib/features/voice/application/voice_use_cases.dart:151–187` ตรวจ current session, activity epoch, provider generation และ failure ก่อนรับ natural completion. `_stopProviderGeneration` (`:309`) settle completion-owned waits หลัง provider stop ยืนยันแล้ว; error/timeout/missing proof ต้องผ่าน bounded conditional stop. Stale conditional stop ที่เป็น no-op ไม่ถูกนับว่า silence confirmed. Queued control tail และ ownership barrier เดิมยังป้องกัน replacement เริ่มทับ cleanup ที่ค้าง.
- Dispose รอ bounded managed cleanup ก่อน settle completion waits (`:462`). Failure แยกเป็น `cleanupIncomplete`; late natural callback ไม่สามารถกลับมาปลด pause หลัง failed cleanup เพราะ wait/failure/owner identity checks.
- Host `:1316–1322` เก็บ narration pause เมื่อ cleanup ยังไม่ยืนยัน. `_run` (`:1015`) และ board busy (`:1559`) ปิด typed answer dispatch ด้วย จึงไม่ได้ป้องกันเฉพาะการกด UI. Dedicated `Stop audio and continue` (`:1619`) เรียก `_recoverNarrationStop` (`:1328`) ซึ่งรอ owned stop, recheck learner owner และ voice-session currentness ก่อน release exact pause. Retry stop ไม่ใช้ stale handle's no-op เป็น authority.
- Tests แยก start acknowledgement ออกจาก natural end, ค้าง stop acknowledgement, route stop, takeover, failed stop, timeout, disposal และ late old callback; failed-stop host test ตรวจ zero answers แม้เรียก typed callback โดยตรง แล้ว retry owned stop สำเร็จและ clocks เดินต่ออย่างถูกต้อง. Native adapter test ตรวจ interrupted-lifetime conservative fallback และ ordinary start-ack positive control.

## Issues remaining in this correction

- **Critical:** ไม่มี demonstrated finding.
- **Important:** ไม่มี open finding ใน UI/Voice correction.
- **Minor:** ไม่มี defect ใหม่ที่พิสูจน์ได้. Conservative native fallback หลัง interruption เป็น explicit capability limitation ที่ตรวจแล้ว ไม่ใช่ deadlock: confirmed stop คืนการเรียนด้วยข้อความ; stop ที่ไม่ยืนยันยังคง pause และ retry affordance. ห้ามอ้างว่า native speech completion ใช้ได้ตลอด runtime หรือผ่าน physical-device validation.

## Evidence inspected

Metadata ระบุ executable `C:/Users/Phet/AppData/Local/Programs/flutter/bin/flutter.bat` และ cwd ตรง worktree ทุก run ด้านล่าง; อ่าน metadata และ retained log results โดยไม่รันทดสอบเอง.

| Prefix under `.superpowers/sdd/` | Exact bounded selection / result |
| --- | --- |
| `pm8-branch-host-red-20260907T033355332` | Host test `--name "queued normal Pair close\|covered and returned during accepted write"`; 0 pass/4 fail, exit1, wall12.4767791s. UI route case แสดง retained boardUnavailable; อีก3เป็น engine close cases. |
| `pm8-branch-narration-red-20260907T033719506` | Host `--plain-name "Pair narration counts no listening time before actual end"`; 0 pass/3 fail, exit1, wall10.5858895s; narration lease หายก่อน natural/routeStop/takeover end. |
| `pm8-branch-voice-red-20260907T033439970` | Voice facade `--plain-name "completion-owned narration"`; 0 pass/4 fail, exit1, wall5.7171178s (new API development RED). |
| `pm8-branch-voice-green1-20260907T033748894` | Same then-existing completion-owned selection; 4 pass, exit0, wall6.0924119s. Historical intermediate subset, not final aggregate. |
| `pm8-branch-focused1-20260907T034212483` | Host, Voice facade, native provider and orchestrator files; 114 pass/2 fail, exit1, wall49.1739085s. Two failures: failedStop host and provider-failure cleanup fixture/path; preserved, not hidden. |
| `pm8-branch-focused2-20260907T034429021` | Host+facade `--name "failedStop\|provider failure retains cleanup"`; corrected two tests pass, exit0, wall8.5941374s. Counts overlap; do not add to114 as a final frozen suite. |
| `pm8-branch-analyze2-20260907T034636401` | Exact `analyze --no-pub lib test`; no issues, exit0, reporter11.2s/wall14.1077375s. |

Current affected selection `pm8-branch-affected-20260907T034837852` belongs to sole executor `pm8_finalize`; this reviewer does **not** assert its completion, counts or success. Root must inspect final metadata/log and before/after raw source identity. Earlier971 covers the pre-correction source only and is not substituted for current evidence.

Root subsequently notified this reviewer of one legacy matching adapter failure involving the unconditional Drift finish-purpose read. Root/main/close reviewer owns that repository compatibility diagnosis and correction; UI/Voice source remains unchanged. This bounded UI approval does not close or override that separate finding, and suite acceptance remains pending.

## Remaining acceptance boundaries

Root retains source-frozen affected/full default+serial checks, relevant Voice/route regressions, policies and internal artifact verification. No fresh visual screenshot of the added failed-stop affordance was inspected here; its bounded widget test checks visibility, blocking and retry behavior. Existing unchanged15 PNG evidence remains historical/current-byte-equivalent as established in original UI review, without a new visual or physical-accessibility claim.

Physical TalkBack/Switch/Voice/performance/UAT, G4P role signatures and research/rollout authority remain NotRun/pending. No merge/push/deploy/enrollment/upload implied. Both original UI Important findings are closed at code-review level; reviewer ownership released and no reviewer process remains.
