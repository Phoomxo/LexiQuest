# LexiQuest Development Guardrails

- Execute one major work package at a time. Do not start background implementation workers.
- Do not invoke, install, resume, or recommend Codex Security, Security Scan, Deep Scan, or a Codex Security worker workflow.
- Use `tool/cli/verify-scope.ps1` for bounded targeted and subsystem checks. Run the full release verifier only on a frozen PR or release SHA.
- Do not rerun a passed gate when its recorded source fingerprint is unchanged.
- Do not run full Flutter tests, full backend tests, Android builds, or GPU checks concurrently.
- Stop and report when the same command failure repeats, a filesystem error repeats, or a command makes no measurable progress for 10 minutes.
- Keep research activation, remote research synchronization, study assignment, statistical reporting, and unrelated document work outside the production-system work packages.
