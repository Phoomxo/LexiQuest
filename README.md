# LexiQuest

An AI-enhanced gamified vocabulary learning application built with Flutter, Firebase, and an authenticated OmniVoice text-to-speech engine.

## Overview

LexiQuest combines gamified vocabulary learning (quizzes, word scrambles, category management) with research-grade voice synthesis. It implements a **Hybrid Voice Pipeline** that routes speech requests between an authenticated cloud OmniVoice WAV API and native device TTS, backing practice modes and research evaluation.

## Tech Stack & Architecture

- **Frontend**: Flutter 3.44.7 / Dart 3.12.2 (Android API 36 / JVM 17)
- **Voice Pipeline**: `HybridVoiceService`, bounded in-memory LRU audio cache (`MemoryVoiceAudioCache`), native TTS fallback (`NativeTtsProvider`), and WAV audio player (`PluginVoiceAudioPlayer`).
- **Telemetry & Privacy**: `FirestoreVoiceTelemetrySink` recording privacy-by-construction metrics (`schemaVersion: voice_telemetry_v1`).
- **Backend API**: Python 3.11 FastAPI service (`backend/voice_api`) serving OmniVoice 0.2.1 24 kHz WAV synthesis with Firebase ID token authentication.

## Development & Testing

### Running Flutter Tests

```powershell
flutter test
```

### Running Static Analysis

```powershell
flutter analyze
```

### Running Backend API Tests

```powershell
uv run --project backend/voice_api pytest backend/voice_api/tests -q
```

### Running Backend Golden-Set Benchmark

```powershell
uv run --project backend/voice_api python backend/voice_api/research/run_golden_set.py
```

### Building Application Targets

```powershell
flutter build apk --debug --dart-define=LEXIQUEST_VOICE_API_URL=https://your-voice-api.example.com
```
