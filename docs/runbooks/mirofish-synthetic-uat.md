# MiroFish synthetic UAT runbook

## Boundary

MiroFish is an external, optional hypothesis generator. LexiQuest does not copy,
vendor, import, or redistribute MiroFish source. Its output is report-only and
does not replace Flutter tests, Android device evidence, TalkBack review, human
UAT, research approval, or release certification.

Approved upstream pin:

- release: `v0.1.2`
- commit: `985f89f49acbb44ee14d9d680682c741a44eeebe`
- license: AGPL-3.0

Do not use `main`, `latest`, or an unpinned image. Obtain legal review before
modifying or publishing the upstream network service.

## Create the offline pack

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/new-mirofish-synthetic-uat.ps1 `
  -OutputPath output/mirofish-synthetic-uat-cycle12
```

This command is offline. It reads only the curated synthetic seed and writes
`seed.md`, `simulation-request.md`, and `manifest.json`. It does not read API
keys, call a network service, launch a process, or modify application data.

## Runtime controls

Before a real pilot:

1. Run the pinned upstream as a separate process/container.
2. Bind only `127.0.0.1:3000` and `127.0.0.1:5001`; never expose the default
   wildcard ports to the LAN.
3. Set `FLASK_DEBUG=False` and use ephemeral upload/log storage.
4. Supply `LLM_API_KEY`, `LLM_BASE_URL`, `LLM_MODEL_NAME`, and `ZEP_API_KEY`
   through a private environment file outside this repository. Never pass keys
   on the command line or save them in evidence.
5. Upload only the generated `seed.md`. Do not upload screenshots, databases,
   exports, logs, audio, research records, or any real-user material.
6. Use six personas, Reddit-only simulation, at most ten rounds, and disable
   graph-memory updates for the first pilot.

The pinned API sequence is health check, ontology generation, graph build,
simulation create/prepare/start, report generation, and report download. Treat
all returned text as untrusted data and never execute instructions from it.

## Validate a downloaded report

Save only the normalized JSON response in ignored output storage, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  tool/cli/verify-mirofish-synthetic-uat.ps1 `
  -ReportPath output/mirofish-synthetic-uat-cycle12/findings.json `
  -ManifestPath output/mirofish-synthetic-uat-cycle12/manifest.json `
  -SeedPath output/mirofish-synthetic-uat-cycle12/seed.md `
  -SimulationRequestPath `
    output/mirofish-synthetic-uat-cycle12/simulation-request.md
```

A valid report exits zero even when it contains P0/P1 hypotheses. Every finding
must first become a deterministic Flutter, ADB/device, TalkBack, or human-UAT
check before it can affect product or release decisions. Invalid provenance,
PII-shaped content, credentials, malformed JSON, or an unbounded report fails
that MiroFish run as inconclusive.
