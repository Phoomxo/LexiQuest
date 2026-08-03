# LexiQuest Codex Guardrails

- Do not invoke, install, resume, or recommend Codex Security, Security Scan, Deep Scan, or any Codex Security worker workflow for this repository.
- Do not treat historical references to Codex Security in `docs/` as active requirements.
- Use bounded local verification instead: Flutter analysis/tests, backend tests, Firestore/Supabase policy tests, Gitleaks, OSV Scanner, dependency audits, and focused manual diff review.
- Never run multi-agent implementation concurrently with security or repository-wide analysis.
- Stop and report immediately if a tool enters a retry loop, repeats the same filesystem error, or makes no measurable progress for 10 minutes.
