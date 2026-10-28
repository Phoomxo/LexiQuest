# Local AI Analysis Orchestrator Design

## Goal

สร้างเครื่องมือวิเคราะห์สำหรับการพัฒนา LexiQuest ที่ใช้ GPT Pro 20x Stable เป็น primary analyst และ AWS Lite Ultimate Claude Opus 5 เป็น read-only reviewer โดยปรับ effort ตามความเสี่ยงของงาน เก็บ API key ด้วย Windows DPAPI นอก repository และไม่อนุญาตให้โมเดลภายนอกแก้ไฟล์หรือรันคำสั่ง

## Scope

รวมในรุ่นนี้:

- Developer-only PowerShell tooling สำหรับ Windows
- DPAPI secret initialization, validation, rotation replacement และ removal
- Bounded project context จาก explicit file list หรือ Git diff
- GPT primary analysis ผ่าน OpenAI Responses-compatible endpoint
- Claude independent review ผ่าน Anthropic Messages-compatible endpoint
- Automatic effort routing พร้อม manual override
- Redacted report และ metadata-only usage record
- Mocked tests และ bounded real-provider smoke test

ไม่รวมในรุ่นนี้:

- การเพิ่มโมเดลทั้งสองเข้า runtime ของแอป LexiQuest
- การให้โมเดลภายนอกเขียนไฟล์ รัน shell หรือ commit Git
- All Max Pools
- Automatic retry, automatic fallback หรือ silent model substitution
- Management token รูปแบบ `ccmk-…`
- Cloud secret storage หรือ CI integration

## Selected providers

### Primary analyst

- Pool: GPT Pro 20x Stable
- Base URL: `https://api.maxplus-ai.cc/gpt-pro-20x-stable`
- Model: `gpt-5.6-sol`
- Generation route: `/v1/responses`
- Transport: `stream: true`, `store: false`; accept exactly one `response.completed` SSE envelope
- Model discovery route: `/v1/models`
- Required request property: `store: false`

### Read-only reviewer

- Pool: AWS Lite Ultimate
- Base URL: `https://api.maxplus-ai.cc/aws-lite-ultimate`
- Routine model: `claude-sonnet-5`
- Deep/high-risk model: `claude-opus-5`
- Routing: `focusedPackage` and `failedOrMultiFile` use Sonnet; `architectureSensitive`, `releaseBlocker`, and `criticalDisagreement` use Opus
- Generation route: `/v1/messages`
- Model discovery route: `/v1/models`
- Thinking mode: `thinking.type: adaptive`
- Effort property: `output_config.effort`

`claudecode-lite` is treated as a legacy alias and is not used by new configuration.

## Repository paths

Only code and non-secret configuration live in Git:

```text
tool/ai-analysis/
├── initialize-secrets.ps1
├── invoke-analysis.ps1
├── remove-secrets.ps1
├── config.json
├── README.md
└── lib/
    ├── context-builder.ps1
    ├── effort-router.ps1
    ├── maxplus-client.ps1
    ├── reviewer.ps1
    └── report-writer.ps1

tool/ai-analysis/tests/
├── context-builder.tests.ps1
├── effort-router.tests.ps1
├── maxplus-client.tests.ps1
├── secret-store.tests.ps1
└── orchestrator.tests.ps1
```

Generated reports and test artifacts are ignored by Git:

```text
build/ai-analysis/
└── 20260801T120000Z-a1b2c3d4/
    ├── report.md
    └── metadata.json
```

Every run directory uses a UTC timestamp followed by eight lowercase hexadecimal characters, as illustrated above.

## Secret paths and lifecycle

Secrets are stored outside every workspace and worktree:

```text
%LOCALAPPDATA%\LexiQuest\ai-analysis\secrets\
├── gpt-stable.dpapi
└── claude-reviewer.dpapi
```

`initialize-secrets.ps1` performs these actions:

1. Creates the secret directory if missing.
2. Prompts for each `ccsk-…` key with `Read-Host -AsSecureString`.
3. Validates the shape `^ccsk-[a-f0-9]{64}$` without displaying the value.
4. Encrypts with `ConvertFrom-SecureString`, which binds decryption to the current Windows user through DPAPI.
5. Writes one DPAPI blob per provider.
6. Restricts the directory ACL to the current Windows user and `SYSTEM`.
7. Calls `/v1/models` for the bound pool and requires the selected model to be present.

The scripts never accept a key as a command-line argument because process arguments may be logged. They never print the decrypted key, request authorization header or DPAPI blob.

Replacing a key is atomic: validate and probe the replacement first, write a temporary DPAPI blob, then replace the old blob. Failure leaves the old secret unchanged. Removing local blobs does not revoke remote keys; the owner must revoke or reroll them in the MaxPlus dashboard.

The orchestrator accepts only `ccsk-…` inference keys. It rejects `ccmk-…` management tokens.

## Context boundary

The context builder supports two modes:

```powershell
tool/ai-analysis/invoke-analysis.ps1 -Task "Review Guest persistence" -ChangedFiles

tool/ai-analysis/invoke-analysis.ps1 -Task "Review provider cancellation" -Path lib/features/ai_tutor/application/ai_tutor_use_cases.dart -Path test/features/ai_tutor/ai_tutor_use_cases_test.dart
```

Rules:

- Default scope is changed tracked source files only.
- Explicit paths must resolve inside the current repository.
- Directories expand only to text source files allowed by `config.json`.
- Maximum 20 files and 96,000 UTF-8 characters per provider request.
- Binary files, generated build outputs and files larger than 256 KiB are rejected.
- Secret and private-evidence denylist always wins over an explicit path.
- The context builder adds file paths and line-numbered excerpts, not entire repository archives.

Hard denylist:

```text
.env*
*.jks
*.keystore
*.p12
*.pem
*.key
key.properties
android/local.properties
field/evidence/**
build/**
**/*.dpapi
**/google-services.json
**/GoogleService-Info.plist
```

Before sending, the context is scanned for MaxPlus, OpenAI, Anthropic and Gemini key shapes. A match blocks the request and reports only the affected file path and rule identifier.

## Effort policy

### GPT primary levels

| Local level | API value | Default use |
|---|---|---|
| Low | `low` | inventory, formatting review, test-output summary |
| Medium | `medium` | focused bug diagnosis and one-package review |
| High | `high` | multi-file implementation review and nontrivial debugging |
| ExtraHigh | `xhigh` | architecture, concurrency, migration and privacy-sensitive work |
| Max | `max` | release blocker and repeated failure requiring deep analysis |
| Ultra | `ultra` | final adjudication of a critical unresolved model disagreement |

### Claude reviewer levels

| Local level | API value | Default use |
|---|---|---|
| Low | `low` | short independent check |
| Medium | `medium` | normal code review |
| High | `high` | architecture, concurrency and migration review |
| ExtendedHigh | `xhigh` | release blocker and long-horizon review |
| Max | `max` | critical final review with unconstrained reasoning effort |

The tool probes every non-default effort value with a bounded request before certifying it. An unsupported value returns `unsupportedEffort` and stops; it is never silently downgraded.

### Automatic routing

| Task classification | GPT | Claude | Reviewer rule |
|---|---|---|---|
| Simple/read-only | Low | none | Do not call reviewer |
| Focused package | Medium | Low | Call when source behavior changes |
| Multi-file or failed test | High | Medium | Always call reviewer |
| Architecture/race/migration/privacy | ExtraHigh | High | Always call reviewer |
| Release blocker | Max | ExtendedHigh | Always call reviewer |
| Critical disagreement | Ultra | Max | GPT receives the Claude critique for final adjudication |

Manual `-Effort` may raise effort. It may lower effort only when the task is not classified as release-critical. `-NoReviewer` is rejected for architecture, migration, privacy and release-blocker classifications.

## Token and cost controls

Maximum output tokens:

| Local effort | GPT | Claude |
|---|---:|---:|
| Low | 2,048 | 4,096 |
| Medium | 4,096 | 8,192 |
| High | 8,192 | 16,384 |
| ExtraHigh / ExtendedHigh | 32,768 | 65,536 |
| Max | 65,536 | 65,536 |
| Ultra | 65,536 | not applicable |

Each key must have a non-null daily or lifetime spend cap. Startup calls `/v1/me` and refuses analysis when the key is inactive, credit is non-positive, the cap is missing or the cap is exhausted. The client reads only credit and key-limit fields; account email and display name are discarded immediately and never logged.

The tool records provider, model, effort, latency, token counts and provider-reported cost when present. It never calculates monetary cost from a hardcoded price table. When cost is absent, metadata records `unknown`.

## Provider request flow

1. Load and decrypt the relevant DPAPI blob in process memory.
2. Validate provider host exactly equals `api.maxplus-ai.cc` and scheme is HTTPS.
3. Call the pool-specific `/v1/models` endpoint.
4. Verify the configured model exists.
5. Build bounded context and run the secret scan.
6. Call GPT primary with `store: false` and selected reasoning effort.
7. When required, call Claude with the same source context plus the primary conclusion, adaptive thinking and selected reviewer effort.
8. If findings agree, synthesize a deterministic report from structured fields.
9. If critical findings conflict, send only the two conclusions and cited file references to GPT for one adjudication request.
10. Zero decrypted key variables and dispose HTTP objects in `finally` blocks.

There is no automatic retry. Timeout, cancellation, rate limit, quota, invalid key, unsupported model, unsupported effort, malformed response and unavailable provider are distinct outcomes.

## Output and retention

Raw provider responses remain in process memory and are not written to disk. The report writer stores only:

- task and explicit scope
- source commit and dirty-state flag
- provider/model/effort metadata
- redacted findings with local file references
- agreement/disagreement status
- token, latency and cost metadata
- final outcome category

Reports live under ignored `build/ai-analysis/`. Default retention is 14 days; the tool removes older run directories at startup and after a successful run. A `-NoReport` option keeps the complete result in memory/output only.

## Write and execution boundary

The orchestrator is analysis-only:

- It does not expose shell, filesystem-write or Git tools to either provider.
- It does not parse provider text as commands.
- It does not apply patches.
- It does not stage, commit or push.
- It does not call a third provider.

Implementation remains in the active Codex workflow and follows the repository’s focused-test and integration gates.

## Testing strategy

Automated tests use fake keys and mocked HTTP responses only:

- DPAPI round-trip is scoped to the current Windows user.
- Invalid key shapes and management tokens are rejected before network access.
- Denylisted paths and embedded secret patterns block context creation.
- Path traversal and paths outside the repository are rejected.
- Effort classification and manual-override floors are deterministic.
- Reviewer is skipped or required according to the policy table.
- Unsupported model/effort stops without fallback.
- Timeout and cancellation perform exactly one request and write no partial report.
- Reports contain no request authorization, DPAPI blob, source content or raw response.

The bounded real smoke performs:

- one `/v1/models` request per key
- one GPT Low request with fixed non-project text
- one Claude Low request with fixed non-project text
- zero retries

Real smoke evidence stores metadata only.

## Acceptance criteria

- Both keys are DPAPI-encrypted outside the repository and never appear in Git, logs or process arguments.
- GPT Stable and AWS Lite Ultimate models pass authenticated discovery.
- Every requested effort level is either proven supported or reported unsupported without downgrade.
- Automatic routing selects the documented effort and reviewer policy deterministically.
- Project context is bounded, path-confined and secret-scanned.
- External models cannot mutate the workspace or execute tools.
- Raw responses are not persisted.
- Mocked tests, secret scan and bounded provider smoke pass.
- No existing LexiQuest runtime behavior or release evidence schema changes.
