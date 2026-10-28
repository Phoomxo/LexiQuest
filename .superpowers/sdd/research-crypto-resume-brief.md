# Resume bounded R3 P-256 signature verifier

Worktree: C:/Users/Phet/Documents/LexiQuest/.worktrees/research.
Read AGENTS.md (updated recovery rules). User explicitly resumed implementation.

Write scope: lib/features/research/data/research_p256_signature_verifier.dart,
test/features/research/research_p256_signature_verifier_test.dart,
.superpowers/sdd/research-crypto-resume-report.md only. No commits.

Complete existing RED suite (previously 40 passed/36 failed); do not weaken tests.
Implement ResearchPermitSignatureVerifier: P-256 ECDSA/SHA256 over UTF-8 canonical
payload, raw 64-byte r||s signature transported as strict canonical base64,
immutable allowlisted uncompressed SEC1 public keys (130 hex chars, prefix04).
Reject unknown issuer, malformed encodings, off-curve/infinity/out-of-range points,
invalid scalar r/s (0 or >=n), changed payload/signature without throwing.
Use existing pointycastle4.0.0 direct dependency; no homemade cryptography or keys
in production. Inspect package source if necessary; known crypto vectors already
exist in tests. Preserve interface. Keep file bounded.

You have EXCLUSIVE Flutter/Dart test/analyzer slot until you report DONE or release
it to main. Run focused suite and focused two-file analyzer only, no full suite,
pub-get, generators or security scanners. Notify main promptly when test slot released.
Follow TDD/root-cause diagnosis. Use apply_patch. Record RED/GREEN commands/results,
changed files, concerns and self-review in report; final under15lines.
