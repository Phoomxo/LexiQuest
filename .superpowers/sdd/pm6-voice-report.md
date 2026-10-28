# PM6 local-only Voice handoff

วันที่ 2026-09-06 บน worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest` branch `codex/pair-matching-pm0-pm8`

## ผลลัพธ์

- เพิ่ม `VoiceRequest.localOnly` แบบ default `false` เพื่อคง routing เดิม และ reject การใช้ร่วมกับ research evaluation, voice mirror หรือ participant-transient privacy ตั้งแต่ request validation
- จำกัด local-only policy ให้ใช้เฉพาะ verified offline pack และ native TTS; dynamic speech ใช้ native โดยตรง และ remote handlers ไม่ได้รับคำขอ
- คง `localOnly` ผ่าน `VoiceOrchestrator._copyForStep` โดยไม่เปลี่ยน telemetry schema
- เพิ่ม optional `NativeTtsLocalVoiceAdapter` โดยไม่บังคับ existing `NativeTtsAdapter` fakes/default callers ให้เปลี่ยน
- local-only native TTS ยอมพูดเมื่อพิสูจน์ได้ว่า language ติดตั้ง, voice locale ตรง, `network_required == '0'`, ไม่มี `notInstalled`, และ `setVoice` คืน `1`; capability/platform/inventory/selection ที่พิสูจน์ไม่ได้คืน safe typed synthesis failure ก่อนส่ง text ไป `speak`
- เส้นทางเดิมเมื่อ `localOnly == false` ยังใช้ลำดับ native configuration เดิมและไม่เรียก local proof APIs

## Exact write set

- `lib/voice/voice_models.dart`
- `lib/voice/voice_policy.dart`
- `lib/voice/voice_orchestrator.dart`
- `lib/voice/native_tts_provider.dart`
- `test/voice/voice_models_test.dart`
- `test/voice/voice_policy_test.dart`
- `test/voice/voice_orchestrator_test.dart`
- `test/voice/native_tts_provider_test.dart`
- `.superpowers/sdd/pm6-voice-report.md`

## TDD evidence

- RED: `.superpowers/sdd/pm6-voice-red.log` — focused test files ทั้ง 4 โหลดไม่ผ่านตามคาด เพราะยังไม่มี named parameter/getter `localOnly` และ local capability interface
- GREEN รอบแรก: `.superpowers/sdd/pm6-voice-green.log` — 116 tests ผ่าน แต่ native test file โหลดไม่ผ่านที่ `native_tts_provider.dart:162,167`; Dart ไม่ promote `NativeTtsAdapter` เป็น unrelated `NativeTtsLocalVoiceAdapter`
- Compile fix: หลัง capability guard ผูก explicit proven-capability binding แล้วเรียก `isLanguageInstalled`/`loadVoices` ผ่าน binding นั้น โดยไม่เปลี่ยน behavior
- GREEN สุดท้าย: `.superpowers/sdd/pm6-voice-green2.log` — focused suite รวม 142 tests ผ่าน (`All tests passed!`)
- `git diff --check` สำหรับ source/test write set ผ่าน; มีเฉพาะคำเตือน working-copy LF/CRLF จาก Git

## ข้อจำกัดที่ยังไม่ทดสอบ

- ยังไม่ได้ทดสอบเสียงจริง, installed voice inventory, การเลือก voice หรือ playback บนอุปกรณ์ Android/iOS จริง; physical SDK/device behavior เป็น **Not Run**
- การเชื่อม Pair host ผ่าน `VoiceUseCases` และ facade-level remote spy/route acceptance อยู่ใน ownership ของ parent และไม่อยู่ใน write set นี้

หลังรายงานนี้คืน ownership ของ source, tests และ tooling ทั้งหมดให้ `/root/pm6_implementation`; ไม่มี source edit หรือ process ที่ค้างจาก task นี้
