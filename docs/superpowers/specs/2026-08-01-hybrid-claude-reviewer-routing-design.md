# Hybrid Claude Reviewer Routing Design

**Date:** 2026-08-01

**Scope:** Project-scoped local AI analysis runtime for LexiQuest

**Status:** Routing concept approved; written specification awaiting owner review

## Context

The AWS Lite Ultimate `/v1/models` response observed with the owner's inference key exposes both `claude-opus-5` and `claude-sonnet-5` as bare model IDs. The earlier pool-prefixed value does not appear in that authenticated catalog and causes credential initialization to stop with `unsupportedModel`.

The reviewer should use Sonnet for routine work and reserve Opus for work whose correctness or release impact warrants the additional capability and cost. Selection must be deterministic and happen before a provider request. A provider failure must never trigger a retry, fallback, model substitution, or second-provider call.

## Goals

- Route each reviewer request to exactly one approved Claude model according to task risk and explicit effort.
- Preserve safety floors for architecture, security, migration, and release work.
- Keep one Windows DPAPI-protected Claude inference key that is valid for both approved models.
- Validate the authenticated model catalog without persisting the catalog, account envelope, identity fields, or plaintext key.
- Record the model and effort actually used in allowlisted analysis and smoke metadata.
- Keep the behavior usable from the canonical checkout, linked worktrees, Codex Desktop, and Codex CLI through the stable project launcher.

## Non-goals

- Automatic provider fallback or model substitution.
- Concurrent calls to Sonnet and Opus for the same review.
- User-defined model IDs, arbitrary endpoints, or management-token operations.
- Changing the primary GPT analyst routing.
- Reading or writing API keys in the repository, shell profile, environment variables, command arguments, logs, reports, or chat.
- Replacing the local reviewer with an application runtime provider.

## Approved Models and Secret Location

The reviewer pool remains `AWS Lite Ultimate` at exactly `https://api.maxplus-ai.cc/aws-lite-ultimate` and uses Anthropic-compatible `/v1/messages` plus `/v1/models`.

Approved model IDs:

- Routine reviewer: `claude-sonnet-5`
- Deep reviewer: `claude-opus-5`

Both models share one inference key stored only as the current Windows user's DPAPI blob:

`C:\Users\Phet\AppData\Local\LexiQuest\ai-analysis\secrets\claude-reviewer.dpapi`

The secret directory retains protected ACLs with access limited to the current Windows user and `SYSTEM`. The blob is created or replaced atomically only after the key, account state, credit state, optional spend-cap state, and both required model IDs pass validation. A failed validation leaves any previous blob unchanged. An empty placeholder file is invalid and must not be created.

## Routing Contract

The existing task classifier remains the primary routing authority. It is extended only where needed to ensure database, authentication, credential, secret, and security work receives the architecture-sensitive safety floor.

| Classification | Examples | Reviewer model | Automatic reviewer effort |
|---|---|---|---|
| `simple` | Summary, inventory, formatting, read-only output | None | None |
| `focusedPackage` | Focused feature or package review | `claude-sonnet-5` | Low |
| `failedOrMultiFile` | Regression, failure, or multi-file review | `claude-sonnet-5` | Medium |
| `architectureSensitive` | Architecture, race, concurrency, migration, database schema, privacy, security, authentication, credential, or secret handling | `claude-opus-5` | High |
| `releaseBlocker` | Signing, upgrade install, release readiness, rollout blocker | `claude-opus-5` | XHigh |
| `criticalDisagreement` | Critical primary/reviewer contradiction requiring adjudication | `claude-opus-5` | Max |

### Manual effort

- `Low`, `Medium`, and `High` retain Sonnet for routine classifications.
- `XHigh` and `Max` explicitly upgrade a routine classification to Opus.
- `Ultra` remains valid only for GPT critical adjudication; its Claude reviewer uses Opus at Max.
- A manual value may raise capability or effort but may not lower the model or effort below the classification's safety floor.
- `NoReviewer` remains rejected for architecture-sensitive, release-blocker, and critical-disagreement work.

The policy result adds an explicit `ClaudeModel` property. It is `null` when no reviewer is required and otherwise contains exactly one of the two approved model IDs. Model selection is complete before the analysis command reads the Claude secret or makes a network request.

## Configuration Contract

The Claude configuration changes from one mutable-looking `model` value to an immutable two-model map:

```json
{
  "models": {
    "routine": "claude-sonnet-5",
    "deep": "claude-opus-5"
  }
}
```

Configuration validation requires:

- the exact AWS Lite Ultimate HTTPS base URL and approved routes;
- both exact model keys and values, with no extra model entries;
- the existing Anthropic authentication style and version;
- the existing bounded effort and output-token configuration.

Consumers receive a request-local provider descriptor whose `model` is copied from the policy result. Shared configuration objects are never mutated.

## Credential Initialization

Claude initialization performs exactly:

1. one secure `Read-Host -AsSecureString` prompt;
2. one `/v1/me` request to verify active key, positive credit, and optional finite/unlimited spend-cap state;
3. one `/v1/models` request;
4. exact membership checks for both `claude-sonnet-5` and `claude-opus-5`;
5. one atomic DPAPI write after all checks pass.

The account envelope and model catalog are cleared before the DPAPI write. Console output reports only the provider name and the two validated model IDs. It never reports credit, spend, identity, key preview, authorization headers, plaintext key, or DPAPI data.

If either required model is missing, initialization throws `unsupportedModel`, identifies only the missing approved model ID, performs no fallback, and does not write or replace the blob.

## Analysis Data Flow

1. Build and secret-scan the bounded repository context.
2. Classify the task and resolve effort, reviewer requirement, safety floor, and `ClaudeModel`.
3. Load the DPAPI secrets only for providers required by the resolved policy.
4. Validate account state and exact selected-model availability with one attempt per endpoint.
5. Run the GPT primary analysis once.
6. When required, run exactly one Claude review using the policy-selected model and effort.
7. When the existing contradiction rules require critical adjudication, retain Opus as the independent reviewer and GPT Ultra as the adjudicator.
8. Normalize and redact results, then write only allowlisted report metadata and findings unless `-NoReport` is active.
9. Clear secret, request, account, model-catalog, and provider-response references.

There is no failure path from Sonnet to Opus or Opus to Sonnet. Any timeout, cancellation, invalid key, quota, rate limit, unavailable provider, unsupported effort, unsupported model, malformed response, or unsafe output stops the run without a partial success report.

## Smoke and Effort Certification

The explicit owner-cost smoke gate sends the fixed non-project prompt once to Sonnet at Low and once to Opus at High, plus the existing GPT smoke. These are the lowest automatically routed efforts for the two reviewer models. The gate performs no retry.

Effort certification records model-specific support:

- Sonnet: Low, Medium, High
- Opus: High, XHigh, Max

Certification never downgrades or substitutes a model. An unsupported effort is recorded for that exact model/effort pair and the probe stops. Starting a new Codex Desktop or CLI session runs local health only and never repeats smoke or certification.

## Reports and Privacy

Analysis and smoke metadata record the exact provider, selected model, effort, latency, token counts, provider-reported cost when present, outcome, schema version, and UTC timestamp. They do not store prompts, source excerpts outside the allowlisted final report, raw responses, account data, model catalogs, identity, keys, authorization headers, or DPAPI blobs.

The existing retention, path allowlist, denylist, embedded-secret scan, output schema validation, and unsafe tool-call rejection remain unchanged.

## Test Strategy

Focused automated tests must cover:

- the complete classification/model/effort matrix;
- manual XHigh/Max upgrade to Opus;
- safety floors that cannot be manually downgraded;
- no reviewer for simple tasks;
- exact configuration shape and rejection of extra or substituted models;
- initialization accepting the documented unlimited cap;
- one account call and one model-list call while validating both required Claude IDs;
- no DPAPI write when either model is missing;
- request-local provider projection without shared configuration mutation;
- request body and normalized report containing the selected exact model;
- zero retry and zero fallback for every provider error category;
- smoke calling both Claude models exactly once;
- model-specific effort-certification metadata;
- stable launcher, runtime-manifest, ACL, and repository-binding regressions.

After focused tests pass, the package gate runs the complete local AI-analysis suite, `git diff --check`, and bounded Gitleaks scanning of `tool/ai-analysis`. The immutable runtime is installed only from a committed source state.

## Acceptance Criteria

- Secure initialization creates `claude-reviewer.dpapi` only after both exact model IDs are discovered.
- Routine analysis evidence shows Sonnet and high-risk analysis evidence shows Opus according to the matrix.
- Manual effort cannot bypass a safety floor.
- Provider failure never causes another model or provider call.
- Both Claude smoke requests and the GPT smoke request pass once without retry.
- Health passes from the canonical checkout and linked worktree.
- A fresh Codex CLI session discovers the launcher through repository instructions without reading or printing any key.
- All bounded tests and secret checks pass, and the independent checkpoint reviewer reports no unresolved P0-P2 findings.

## Rollback

The runtime remains commit-addressed and immutable. Rollback checks out the prior reviewed source commit and reruns the project runtime installer. The stable launcher atomically switches to that runtime. Existing DPAPI blobs are not copied into the repository and are replaced only through explicit secure initialization.
