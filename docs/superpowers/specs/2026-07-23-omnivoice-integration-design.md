# OmniVoice Integration and Research Design

วันที่: 23 กรกฎาคม 2026
สถานะ: Design approved for written review
Branch: `feature/omnivoice-integration`
ฐานการพัฒนา: `origin/refactor`

## 1. วัตถุประสงค์

เพิ่ม OmniVoice ให้ LexiQuest เป็นระบบสร้างเสียงอ้างอิงคุณภาพสูงสำหรับการเรียนคำศัพท์และประโยค โดยยังคง `flutter_tts` เป็นระบบสำรองและเป็น baseline สำหรับการทดลองในปริญญานิพนธ์

ระบบต้องตอบโจทย์พร้อมกันสองด้าน:

1. ด้านผลิตภัณฑ์: ผู้เรียนกดฟังคำศัพท์และประโยคได้อย่างเสถียร แม้ OmniVoice API ไม่พร้อมใช้งาน
2. ด้านการวิจัย: เปรียบเทียบผลระหว่าง Native TTS กับ OmniVoice ภายใต้เนื้อหาและขั้นตอนการเรียนที่เหมือนกัน

## 2. ขอบเขต

### 2.1 สิ่งที่รวมอยู่ในงาน

- สร้าง abstraction `VoiceService` ใน Flutter
- รองรับผู้ให้บริการเสียงสองแบบ: OmniVoice และ `flutter_tts`
- สร้าง Python HTTP API สำหรับ OmniVoice
- ตรวจสอบ Firebase ID Token ก่อนสร้างเสียง
- cache เสียงตามข้อความ ภาษา เสียง ความเร็ว และเวอร์ชันโมเดล
- เก็บไฟล์เสียงใน Firebase Storage และ metadata ใน Firestore
- ใช้เสียงกับคำศัพท์ ประโยค และแบบฝึกหัดที่เลือก
- บันทึก telemetry ที่จำเป็นสำหรับการประเมินผล
- fallback ไป Native TTS เมื่อ network, API หรือ playback มีปัญหา

### 2.2 สิ่งที่ยังไม่รวมในรุ่นแรก

- Voice cloning จากเสียงของผู้ใช้
- การฝึกหรือ fine-tune OmniVoice
- การประเมิน phoneme หรือสำเนียงแบบละเอียด
- การรันโมเดล OmniVoice บนอุปกรณ์มือถือ
- การแทนที่ `speech_to_text`
- การเปลี่ยนโครงสร้างเกมหรือคะแนนที่ไม่เกี่ยวกับเสียง

## 3. ทางเลือกและการตัดสินใจ

### ทางเลือก A: ใช้ OmniVoice ทั้งหมด

คุณภาพเสียงสม่ำเสมอ แต่แอปจะพึ่งพา network และ GPU service ทุกครั้ง มีความเสี่ยงต่อ latency และค่าใช้จ่าย

### ทางเลือก B: Hybrid OmniVoice + Native TTS

ใช้ OmniVoice เมื่อมีเสียงใน cache หรือ API พร้อมใช้งาน และใช้ `flutter_tts` เป็น fallback เหมาะกับการใช้งานจริงและสร้าง baseline สำหรับงานวิจัย

### ทางเลือก C: OmniVoice บนอุปกรณ์

ลดการพึ่งพา server แต่ไม่เหมาะกับรุ่นแรก เนื่องจากโมเดลและ Python/PyTorch runtime มีขนาดและความต้องการทรัพยากรสูง

### การตัดสินใจ

เลือกทางเลือก B แบบ Hybrid

## 4. สถาปัตยกรรม

```text
Flutter UI
  |
  v
VoiceService
  |-- AudioCacheService
  |-- OmniVoiceProvider ---- HTTPS ----> Voice API ----> OmniVoice GPU Worker
  |                                  |                    |
  |                                  |                    v
  |                                  +------------> Firebase Storage
  |                                                       |
  |                                                       v
  |                                                  Firestore metadata
  |
  +-- NativeTtsProvider (`flutter_tts`)
```

### 4.1 ขอบเขตความรับผิดชอบ

#### Flutter UI

ส่งคำขออ่านเสียงและแสดงสถานะ loading/error เท่านั้น ไม่รู้รายละเอียด Firebase Storage หรือ OmniVoice API

#### VoiceService

กำหนด interface กลาง เลือก provider ตาม assignment และ policy จัดการ cache, timeout, fallback และ telemetry

#### OmniVoiceProvider

เรียก Voice API ด้วย Firebase ID Token แปลงผลลัพธ์เป็น audio source ที่ Flutter เล่นได้

#### NativeTtsProvider

ห่อหุ้ม `flutter_tts` เดิมและรับ parameter ในรูปแบบเดียวกับ OmniVoiceProvider

#### Voice API

ตรวจสิทธิ์ validate input สร้าง cache key ตรวจ cache ส่งงานเข้า worker และคืนผลลัพธ์แบบมีโครงสร้าง

#### OmniVoice GPU Worker

โหลดโมเดลเพียงครั้งเดียว สร้างเสียงจากข้อความ และส่งไฟล์ให้ storage layer โดยไม่รับคำขอจาก mobile client โดยตรง

## 5. Flutter Interface

```dart
enum VoiceEngine {
  nativeTts,
  omniVoice,
}

class VoiceRequest {
  final String text;
  final String languageCode;
  final String voiceId;
  final double speed;
  final String contentId;
  final String contentType;
}

abstract interface class VoiceService {
  Future<VoicePlaybackResult> speak(VoiceRequest request);
  Future<void> stop();
}
```

`contentId` และ `contentType` ใช้เชื่อม event กับคำศัพท์หรือแบบฝึกหัดโดยไม่บันทึกข้อความส่วนตัวเกินความจำเป็น

## 6. API Contract

### 6.1 สร้างหรือดึงเสียง

```http
POST /v1/speech
Authorization: Bearer <Firebase-ID-Token>
Content-Type: application/json
```

```json
{
  "text": "The cat is sleeping.",
  "language": "en",
  "voice": "teacher_female",
  "speed": 0.9,
  "format": "wav"
}
```

ผลลัพธ์:

```json
{
  "requestId": "01...",
  "audioUrl": "https://...",
  "durationMs": 2450,
  "cached": true,
  "engine": "omnivoice",
  "modelVersion": "omnivoice-server-version"
}
```

### 6.2 ตรวจสถานะ

```http
GET /health/live
GET /health/ready
```

`live` ตรวจ process และ `ready` ตรวจว่าโมเดลโหลดพร้อมสร้างเสียง

### 6.3 รหัสข้อผิดพลาด

- `400 INVALID_REQUEST`: ข้อมูลไม่ครบหรือค่าผิดรูปแบบ
- `401 UNAUTHENTICATED`: Firebase token ไม่ถูกต้อง
- `413 TEXT_TOO_LONG`: ข้อความยาวเกินขีดจำกัด
- `429 RATE_LIMITED`: เรียกใช้เกิน quota
- `503 MODEL_UNAVAILABLE`: worker หรือโมเดลไม่พร้อม
- `504 GENERATION_TIMEOUT`: สร้างเสียงเกินเวลาที่กำหนด

Flutter ต้อง fallback เฉพาะ error ที่เหมาะสมและบันทึกเหตุผลทุกครั้ง

### 6.4 Operating modes

ระบบต้องมี policy แยกสองโหมดอย่างชัดเจน:

- `practice`: อนุญาตให้ fallback จาก OmniVoice ไป Native TTS เพื่อให้ผู้เรียนทำกิจกรรมต่อได้
- `researchEvaluation`: ไม่อนุญาตให้ fallback ข้าม engine หาก engine ที่กำหนดใช้งานไม่ได้ ให้บันทึก `technical_failure` และไม่นำ trial นั้นไปรวมกับผลของอีก engine

research assignment และ operating mode ต้องถูกกำหนดก่อนเริ่มกิจกรรมและห้าม UI เปลี่ยนเองระหว่าง trial

## 7. Cache และ Data Model

### 7.1 Cache key

```text
SHA-256(
  normalizedText
  + language
  + voice
  + speed
  + format
  + modelVersion
)
```

การใส่ `modelVersion` ทำให้เปลี่ยนโมเดลหรือ configuration ได้โดยไม่เล่นไฟล์จากรุ่นเก่าโดยไม่ตั้งใจ

### 7.2 Firebase Storage

```text
tts/{modelVersion}/{language}/{voice}/{cacheKey}.wav
```

### 7.3 Firestore collection

```text
voice_assets/{cacheKey}
```

ตัวอย่างฟิลด์:

```json
{
  "language": "en",
  "voiceId": "teacher_female",
  "speed": 0.9,
  "format": "wav",
  "modelVersion": "omnivoice-server-version",
  "storagePath": "tts/...",
  "durationMs": 2450,
  "createdAt": "server timestamp",
  "lastAccessedAt": "server timestamp"
}
```

ไม่เก็บ Firebase ID Token, raw microphone audio หรือ secret ใน metadata

## 8. Request Flow

1. ผู้ใช้กดฟังเสียง
2. Flutter สร้าง `VoiceRequest`
3. VoiceService อ่าน research assignment และ engine policy
4. ถ้าเป็น Native TTS ให้พูดผ่าน `flutter_tts`
5. ถ้าเป็น OmniVoice ให้ตรวจ local cache ก่อน
6. เมื่อ local cache ไม่มี ให้เรียก `POST /v1/speech`
7. API ตรวจ Firebase token และ input
8. API ตรวจ shared cache
9. ถ้าไม่มี cache ให้ GPU worker สร้างเสียงและ upload
10. Flutter download/play และเก็บ local cache
11. ในโหมด `practice` หาก OmniVoice ล้มเหลว ให้ fallback ไป Native TTS
12. ในโหมด `researchEvaluation` หาก engine ที่กำหนดล้มเหลว ให้หยุด trial และบันทึก `technical_failure`
13. บันทึก event โดยไม่รบกวนการเรียน

## 9. Error Handling

- API timeout ต้องไม่ทำให้ UI ค้าง
- ปุ่มเล่นเสียงต้องป้องกันการกดซ้ำระหว่างคำขอเดียวกัน
- ผู้ใช้ต้องกดหยุดหรือเปลี่ยนคำได้
- เมื่อ URL หมดอายุ ให้ขอ URL ใหม่แทนการ generate เสียงซ้ำ
- local cache ที่เสียหายต้องถูกละทิ้งและดาวน์โหลดใหม่
- Native TTS fallback ใช้ได้เฉพาะโหมด `practice` และต้องบันทึก telemetry
- โหมด `researchEvaluation` ห้าม fallback ข้าม engine เพราะจะทำให้ treatment contamination
- เมื่อทั้งสอง engine ใช้ไม่ได้ ให้แสดงข้อความสั้นและมีปุ่มลองใหม่

## 10. Security, Privacy และจริยธรรม

- ใช้ HTTPS เท่านั้น
- ตรวจ Firebase ID Token ทุกคำขอ
- จำกัดจำนวนคำขอต่อ user, device และช่วงเวลา
- จำกัดความยาวข้อความและ character set
- ไม่รับ path หรือ URL จาก client เพื่อป้องกัน file/URL injection
- ไม่บันทึก token, secret หรือข้อมูลเสียงไมโครโฟนใน log
- แยก service account ออกจาก source code
- กำหนดอายุ cache และนโยบายลบไฟล์
- ปิด Voice cloning ในรุ่นแรก
- หากเปิด Voice cloning ในอนาคต ต้องมี explicit consent, audit trail, revocation และการป้องกันการเลียนเสียงบุคคลอื่น

## 11. Research Design

### 11.1 คำถามวิจัย

การใช้เสียงจาก OmniVoice ช่วยเพิ่มความเป็นธรรมชาติ ความชัดเจนในการรับฟัง ผลการเรียนรู้คำศัพท์ และความพึงพอใจ เมื่อเทียบกับ Native TTS หรือไม่

### 11.2 เงื่อนไขทดลอง

- Control: `flutter_tts`
- Treatment: OmniVoice
- เนื้อหา หน้าจอ ลำดับกิจกรรม และระบบรับเสียงต้องเหมือนกัน
- assignment ต้องถูกบันทึกและคงเดิมตาม research protocol
- วิเคราะห์ภาษาไทยและภาษาอังกฤษแยกกัน
- ระหว่างเก็บข้อมูลต้องใช้ `researchEvaluation` และห้าม auto-fallback
- อุปกรณ์ ระบบปฏิบัติการ Native TTS engine, voice ID, pitch, speed, volume และ audio output ต้องถูกล็อกหรือบันทึกตาม protocol
- OmniVoice model weights, model version, voice ID, inference parameters, sample rate และ random seed (เมื่อรองรับ) ต้องถูกล็อก

### 11.3 ตัวชี้วัด

#### Perception

- Mean Opinion Score ด้านความเป็นธรรมชาติ
- คะแนนความชัดเจน
- ความพึงพอใจ

#### Learning

- ความถูกต้องของคำตอบ
- เวลาในการตอบ
- pre-test/post-test หรือ delayed retention ตาม protocol ที่คณะอนุมัติ

#### System

- time to first audio
- playback success rate
- fallback rate
- cache hit rate
- generation latency
- จำนวนคำขอและต้นทุนโดยประมาณ

### 11.4 ข้อมูลที่ไม่ใช้เป็นคะแนนการออกเสียง

ผลจาก `speech_to_text` เป็นเพียงการรู้จำคำที่พูด ไม่ใช่ phoneme-level pronunciation score งานวิจัยต้องไม่เรียกผล exact-match เดิมว่าเป็นคะแนนคุณภาพการออกเสียง

ASR error, empty transcript และ recognition confidence ต้องถูกบันทึกแยกจากคะแนนการเรียนรู้ เพื่อไม่ให้ความผิดพลาดของ Speech Recognition ถูกตีความว่าเป็นผลของ TTS engine

## 12. Telemetry

Event ขั้นต่ำ:

- `voice_requested`
- `voice_cache_hit`
- `voice_generation_started`
- `voice_playback_started`
- `voice_playback_completed`
- `voice_fallback_used`
- `voice_technical_failure`
- `voice_error`
- `exercise_answered`
- `speech_recognition_result`

แต่ละ event ใช้ pseudonymous user/session ID, research group, operating mode, content ID, language, engine, latency และ error code ที่จำเป็น ห้ามเก็บ token หรือ raw microphone audio

## 13. Testing Strategy

### 13.1 Flutter

- unit test การเลือก provider
- unit test cache key normalization
- unit test fallback policy
- widget test loading, retry และ error state
- integration test playback ด้วย fake provider

### 13.2 Backend

- unit test request validation
- unit test deterministic cache key
- unit test authentication dependency
- unit test rate limiting policy
- integration test cache miss และ cache hit
- integration test worker timeout
- contract test ระหว่าง Flutter DTO กับ API schema

### 13.3 Model Quality

- golden dataset คำและประโยคไทย/อังกฤษ
- human review ความชัดเจนและความเป็นธรรมชาติ
- ตรวจตัวเลข ชื่อเฉพาะ เครื่องหมายวรรคตอน และข้อความยาว
- บันทึก model/config version ทุกครั้งเพื่อทำซ้ำการทดลองได้

## 14. Rollout

### Phase 1: Research specification

จัดทำ architecture, protocol, metrics และ acceptance criteria

### Phase 2: Backend proof of concept

สร้าง API และเสียงจาก golden dataset โดยยังไม่เชื่อมผู้ใช้จริง ระยะนี้ยังไม่เพิ่ม shared cache หรือ telemetry ที่ซับซ้อน เพื่อวัดความพร้อมของโมเดล authentication และ latency ก่อน

### Phase 3: Flutter integration

เพิ่ม VoiceService, provider, playback, local cache และ fallback

### Phase 4: Shared cache and hardening

เชื่อม Firebase Storage/Firestore, authentication, rate limit และ monitoring

### Phase 5: Research instrumentation

เพิ่ม assignment, telemetry และ data export ที่ผ่านการตรวจด้านจริยธรรม

### Phase 6: Controlled evaluation

ทดลองกับกลุ่มที่กำหนด วิเคราะห์ผล และค่อยตัดสินใจเปิด OmniVoice เป็นค่าเริ่มต้น

## 15. Pull Request Strategy

1. `docs: define OmniVoice architecture and research design`
2. `feat: add OmniVoice backend proof of concept`
3. `feat: add Flutter voice service abstraction`
4. `feat: add audio cache, authentication, and fallback`
5. `feat: add research instrumentation`

แต่ละ PR ต้องมีขอบเขตเดียว ตรวจสอบได้ และไม่ merge จนกว่าทีมตรวจทาน

## 16. Acceptance Criteria สำหรับรุ่นแรก

- ผู้ใช้กดฟังคำศัพท์ภาษาอังกฤษผ่าน OmniVoice ได้
- ในโหมด `practice` เมื่อ OmniVoice ใช้ไม่ได้ แอปกลับไปใช้ Native TTS ได้
- ในโหมด `researchEvaluation` เมื่อ engine ใช้ไม่ได้ ระบบบันทึก technical failure โดยไม่เล่นเสียงจากอีก engine
- คำขอซ้ำใช้ cache และไม่ generate ใหม่
- API ปฏิเสธคำขอที่ไม่มี Firebase authentication
- UI ไม่ค้างเมื่อ generation timeout
- ระบบบันทึก engine, latency, cache และ fallback event
- test ของ Flutter และ backend ผ่านตามขอบเขตที่ implement
- ไม่มี secret, token หรือข้อมูลเสียงผู้ใช้ถูก commit ลง repository
- เอกสารระบุชัดว่า Speech-to-Text exact match ไม่ใช่ pronunciation scoring
- research protocol ล็อก Native TTS environment และ OmniVoice model/inference configuration
