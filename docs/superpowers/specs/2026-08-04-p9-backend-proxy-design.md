# LexiQuest P9 — Backend Proxy Design

**Status:** DRAFT — starts after P8-G controlled rollout is complete

**Date:** 2026-08-04

**Owner:** LexiQuest project owner

**Dependency:** P8-G must reach 30-participant rollout and owner approval before
this project begins. P8 source certification must not be invalidated by changes
made under P9.

---

## สรุปสำหรับเจ้าของโครงการ

P8 ใช้ client-side BYOK โดยตรง ซึ่งเหมาะสำหรับ controlled field rollout30 คน
แต่ไม่เหมาะสำหรับ public production เพราะ API key อยู่บนอุปกรณ์ผู้ใช้

P9 ออกแบบ backend proxy แยกต่างหากที่:
- เก็บ provider credential ฝั่ง server
- รับ request จาก app ผ่าน authenticated endpoint
- กระจายงานไปยัง provider โดยผู้ใช้ไม่เห็น key
- มี rate/cost quota, abuse controls, และ audit-safe telemetry

P9 เป็นโครงการใหม่ ไม่แตะ P8 source เลย

---

## 1. Scope boundary

P9 delivers a server-side authenticated proxy between the LexiQuest app and AI
providers. It does not modify any P8 Flutter source, Drift schema, evidence
records, or release certificates.

The P8 app contracts (`AiTutorGateway`, `AiTutorController`) remain stable. P9
introduces one new app-side gateway implementation that speaks to the proxy
instead of calling providers directly.

## 2. Architecture overview

```
LexiQuest App (P8 client)
  │
  │  HTTPS + Firebase Auth token
  ▼
LexiQuest Backend Proxy  ← P9
  ├── Auth verifier (Firebase Admin SDK)
  ├── App Check verifier
  ├── Rate/cost quota enforcer
  ├── Provider router
  │   ├── Gemini adapter
  │   ├── OpenAI adapter
  │   ├── Anthropic adapter
  │   └── OpenRouter adapter
  ├── Redacted telemetry store
  └── Incident rollback controls
  │
  ▼
AI Provider APIs
```

## 3. Server-side credential isolation

Provider API keys are held only in server-side secret storage (e.g. Google
Secret Manager or equivalent). They are never returned to clients, never
written to logs, and never included in error responses.

The app sends only:
- Firebase Auth ID token (for authentication)
- App Check token (for integrity)
- Provider ID and model ID
- Tutor scenario and learner message (bounded length)
- Optional learning summary flag (aggregate only, no raw history)

The proxy performs:
- ID token verification
- App Check verification
- Per-user and per-app rate and cost quota checks
- Provider key resolution from secret storage
- Bounded outbound request with timeout and cancellation
- Redacted metadata-only response telemetry
- Streaming or buffered reply forwarding to the app

## 4. App-side proxy gateway

A new `ProxyAiTutorGateway` implements the existing `AiTutorGateway` contract.
It replaces the per-provider direct gateways when the proxy is configured.

```dart
/// Gateway that routes tutor requests through the authenticated backend proxy
/// instead of calling provider APIs directly.
final class ProxyAiTutorGateway implements AiTutorGateway {
  ProxyAiTutorGateway({
    required this.providerId,
    required this.model,
    required Uri proxyBaseUri,
    required http.Client client,
    required Future<String?> Function() idTokenProvider,
    required Future<String?> Function() appCheckTokenProvider,
    Duration requestTimeout = const Duration(seconds: 30),
  });

  @override final AiProviderId providerId;
  @override final String model;

  // listModels: calls proxy /models endpoint with Auth + AppCheck
  // generateTutorReply: calls proxy /generate with Auth + AppCheck + bounded payload
  // validateKey: always succeeds (server holds the key)
}
```

Switching from BYOK to proxy mode requires only replacing the `AiGatewayResolver`
in `AppBootstrap`. No screen, use case, or evidence contract changes.

## 5. Authentication and authorization

Every proxy request carries:
- `Authorization: Bearer <Firebase ID token>` — user identity
- `X-Firebase-AppCheck: <App Check token>` — device integrity

The proxy rejects unauthenticated, unverified, or rate-exceeded requests before
forwarding to any provider. App Check enforcement follows the pattern established
in P8-F: verify valid traffic before enabling enforcement, roll back if valid
traffic is rejected.

## 6. Rate and cost quota

Per-user quotas:
- Maximum requests per minute and per day
- Maximum input and output tokens per request
- Maximum total tokens per day
- Hard stop when monthly budget threshold is reached

Quotas are stored server-side and enforced atomically. The app receives a
typed `quota` or `rateLimited` error identical to the P8 BYOK error codes so
existing UI copy remains correct.

## 7. Provider routing and consent

Provider selection remains user-controlled via the existing settings screen.
The proxy validates that the requested provider/model is on an approved list
before forwarding.

Server-side kill switches disable individual providers without an app update.
The existing `providerDisabled` failure code (established in P8-A) maps to the
proxy's provider-disabled response.

## 8. Redacted telemetry

The proxy records only:
- Request ID (random, non-identifying)
- Provider ID and model
- Input/output token count and reported cost
- Latency and outcome category
- App Check result
- Timestamp (UTC, minute-granularity)

It never records:
- Learner message text
- Tutor reply text
- Learning summary content
- Firebase UID in cleartext (use a one-way hash if needed for abuse detection)
- IP address in persistent storage

## 9. Rollback and incident controls

- Per-provider kill switch with zero-downtime toggle
- Per-user suspension without app update
- Replay protection via request ID deduplication window
- Budget hard-stop at configurable threshold with owner alert
- Automated rollback when error rate exceeds threshold

## 10. Privacy and data retention

The proxy does not store the content of any tutor exchange. Aggregate telemetry
is retained for 90 days and then purged automatically. No learning content,
voice data, or participant identifiers are retained server-side.

## 11. Work packages

| Package | Deliverable |
|---|---|
| P9-A | Proxy API contract: request/response schema, auth, AppCheck, quota, error codes |
| P9-B | Proxy server implementation: Cloud Run or App Engine, secret manager, adapters |
| P9-C | `ProxyAiTutorGateway` in app + feature flag to switch BYOK ↔ proxy |
| P9-D | Rate/cost quota and abuse controls |
| P9-E | Redacted telemetry, budget alerts, kill switches |
| P9-F | Load test, App Check enforcement, security review |
| P9-G | Production rollout alongside or replacing P8-G controlled deployment |

## 12. Not in scope for P9

- Changing any P8 Flutter source files, Drift schema, or evidence records
- Replacing the voice architecture (VoxCPM, STT, pronunciation)
- Adding new AI features (that is a separate product cycle)
- Migrating existing BYOK users automatically (requires a consent and data
  migration plan outside this document)

## 13. Starting condition

P9 may begin design and implementation planning when:

- P8-G controlled rollout reaches 30 participants and receives owner approval
- No unresolved P8 release blockers remain open
- The P8 source commit and APK hash are frozen and verified

This document is a design reference only. An implementation plan will be
written as a separate file following the same format as the P8 implementation
plans when the starting condition is met.
