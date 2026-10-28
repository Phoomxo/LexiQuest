# Voice Research Telemetry Data Dictionary

**Collection Name:** `voice_telemetry_events`  
**Schema Version:** `voice_telemetry_v1`

## Overview

This collection records append-only, privacy-by-construction operational metrics for audio synthesis and playback in LexiQuest. It supports thesis research evaluation comparing OmniVoice AI synthesis vs. Native TTS baselines.

## Privacy Guarantees

The following information is **STRICTLY EXCLUDED** and **NEVER** written to Firestore:
- Spoken text or vocabulary content strings.
- Audio binary data or audio URLs.
- Firebase Auth ID tokens, session tokens, or user email addresses.
- Detailed system error stack traces or network addresses.

## Field Specifications

| Field Name | Type | Description | Values / Examples |
|---|---|---|---|
| `schemaVersion` | String | Fixed version identifier | `"voice_telemetry_v1"` |
| `outcome` | String | Terminal lifecycle outcome | `"succeeded"`, `"failed"`, `"cancelled"` |
| `mode` | String | Request mode | `"practice"`, `"researchEvaluation"` |
| `requestedEngine` | String | Primary engine requested | `"nativeTts"`, `"omniVoice"` |
| `actualEngine` | String? | Engine that produced playback | `"nativeTts"`, `"omniVoice"`, `null` |
| `usedFallback` | Boolean | Whether native fallback was triggered | `true`, `false` |
| `fallbackReason` | String? | Reason category if fallback used | `"network"`, `"timeout"`, `"authentication"`, etc. |
| `failureCategory` | String? | Failure category if outcome failed | `"network"`, `"timeout"`, `"unsupported"`, etc. |
| `cacheHit` | Boolean | Whether in-memory WAV cache served request | `true`, `false` |
| `latencyMs` | Integer | Total request-to-playback latency in ms | `120`, `450` |
| `contentId` | String? | Anonymized content identifier | `"word-123"` |
| `contentType` | String? | Anonymized content type | `"vocabulary_word"`, `"quiz_sentence"` |
| `requestId` | String? | Server request UUID (if OmniVoice used) | `"a1b2c3d4-..."` |
| `modelVersion` | String? | Model version string | `"0.2.1"` |
| `occurredAtUtc` | String | ISO 8601 UTC timestamp | `"2026-07-24T10:00:00.000Z"` |
