# ADLC checkpoint — MiroFish synthetic UAT boundary

Date: 2026-10-26 (Asia/Bangkok)

Branch: `codex/cycle12-release`

Base commit: `7f2ed7b6adead6e4bfaa1f6e9af7bebb6689d0a4`

Classification: local synthetic engineering evidence; production disabled

## Intent and disposition

Use the safe portion of MiroFish immediately without presenting a social-agent
simulation as Android automation or human UAT. The implemented boundary is an
offline packager plus an untrusted-report validator. It does not call MiroFish,
LLM, Zep, Firebase, a device, or any production service.

Disposition: **engineering-complete for the offline/report-only boundary**.
The first live simulation remains an external, cost-bearing pilot and is not
release evidence.

## Implementation

- `docs/testing/mirofish-synthetic-uat.md`: curated synthetic seed with six
  fictional personas, bounded flows, and a normalized JSON report contract.
- `docs/runbooks/mirofish-synthetic-uat.md`: upstream pin, localhost-only
  controls, credential/data boundary, and operator commands.
- `tool/cli/new-mirofish-synthetic-uat.ps1`: creates an offline seed,
  simulation request, and provenance manifest.
- `tool/cli/verify-mirofish-synthetic-uat.ps1`: validates decoded JSON,
  provenance, bounds, enums, and synthetic-only content without executing it.
- `tool/cli/lib/mirofish-synthetic-uat.ps1`: shared deterministic validators.
- `tool/cli/tests/mirofish-synthetic-uat.tests.ps1`: RED/GREEN contract tests.

MiroFish is pinned as an external tool at `v0.1.2`, commit
`985f89f49acbb44ee14d9d680682c741a44eeebe`. No MiroFish source, package,
submodule, container, or AGPL-derived implementation is included in LexiQuest.

## Evidence

TDD evidence:

1. RED: test exited 1 because the packager/library/validator did not exist.
2. GREEN: 27/27 contract assertions passed.
3. Security RED: JSON-escaped email bypass produced 1 failing assertion.
4. Security GREEN: validation moved to decoded JSON; 28/28 passed.
5. Review RED: raw secret shapes, modified manifests, uncontracted fields,
   unpinned simulation requests, and JSON type coercion exposed missing gates.
6. Final GREEN: 41/41 contract assertions passed after closing those bypasses.

Generated pilot pack:

- path:
  `C:\Users\Phet\Documents\LexiQuest\output\mirofish-synthetic-uat-cycle12-2026-10-26\`
- disposition: `REPORT_ONLY`
- personas: 6
- maximum rounds: 10
- contains real user data: false
- seed and simulation-request SHA-256 values are recorded in the generated
  `manifest.json` and recomputed by the validator.

During final attestation, the pack is regenerated from the committed integration
snapshot so its manifest pins the simulation-request hash and source commit.

## Review boundary

- A valid P0/P1 MiroFish finding still exits zero because it is a hypothesis,
  not a deterministic release failure.
- Invalid provenance, malformed JSON, non-synthetic classification, PII-shaped
  content, credential material, or an unbounded report fails that pilot.
- A finding can affect product/release decisions only after conversion to a
  Flutter, ADB/device, TalkBack, or human-UAT check with independent evidence.
- Raw transcripts, persona memory, uploads, logs, and research/user data do not
  enter Git.

## External dependencies

A live pilot was not started because the current host has no active Docker
engine, Python is 3.14 while upstream requires 3.11–3.12, and no LLM/Zep keys
are configured in the process environment. Starting a live pilot would also
send the synthetic seed to external LLM and Zep services and consume credits.
Those conditions require a separate explicit runtime/cost/data decision.
