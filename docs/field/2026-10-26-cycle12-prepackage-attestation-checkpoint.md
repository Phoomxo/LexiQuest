# Cycle 12 pre-package attestation checkpoint — 2026-10-26

## Intent

Freeze the locally verified Cycle 12 source before producing one signed Android
field-test candidate. This checkpoint records engineering evidence only. It does
not authorize Play publication, Firebase/App Check production changes, real
research enrollment/upload, or destructive device cleanup.

## Ground

- Worktree: `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`
- Branch: `codex/cycle12-release`
- Baseline commit: `bd4ec9083a290ad256ebd80c9d292359796bf6aa`
- Candidate version reserved for the next serialized packaging step:
  `1.0.0+16`
- Data classification: synthetic/local; production research remains disabled.
- The pre-existing untracked `.impeccable/critique/` snapshot is user work and
  is excluded from this release-source checkpoint.

## Execute

- Added a machine-verifiable, rollout-neutral 8-domain/44-capability catalog.
- Hardened crash-resumable account deletion across Flutter and the AI API:
  owner and recent-auth binding, export-before-delete, idempotent recovery,
  Auth-last deletion, secret scrubbing, and a default-off production switch.
- Hardened signed APK/AAB provenance, fixed upload-certificate/model trust,
  archive coverage, path containment, physical-device classification, and
  evidence references.
- Added truthful bilingual privacy, account-deletion and support pages plus Play
  listing/Data Safety/rollback material. Real contact endpoints remain required
  configuration rather than fabricated values.

## Review disposition

- `DEL-PROD`: accepted for local engineering. Independent review found no
  blocker after recovery, TTL, kill-switch and receipt-authority corrections.
  A production server-complete export authority is not composed, so the live
  endpoint remains disabled.
- `REL-GATE`: accepted for merge. Independent review found no remaining
  Critical/Important issue after validating measured APK/AAB identity, archive
  entry coverage, certificate/model pins, reparse containment, participant
  document hashes and device facts.
- `PUB-WEB`: accepted locally. The production public gate deliberately rejects
  missing owner-approved support/deletion endpoints.
- Figma: the authenticated project owner account was verified locally. R11
  Cloud node `81:2` remains the verified authority (240 screens, 942 routes,
  41 starts); browser
  prototype smoke passed account check, Home, Theme Marketplace, AI Tutor,
  practice catalog, Vivo 393x876 and 200% accessibility paths. Draft R12 node
  `112:1819` is incomplete. Official editing is not verified because the
  Starter-plan MCP quota was exhausted.

## Attest

| Check | Result |
| --- | --- |
| `flutter test --no-pub` | PASS — 1774/1774 |
| `flutter analyze --no-pub` | PASS — no issues |
| Flutter account-deletion focused suite | PASS — 74/74 |
| AI API focused account-deletion suite | PASS — 16/16 |
| AI API full suite | PASS — 92/92; one upstream Python lifecycle warning |
| Firestore emulator policy suite | PASS — 33/33 |
| Firebase Auth emulator suite | PASS — 3/3 |
| Public release pages | PASS — 10/10 |
| Hosting headers/contact loader | PASS — 15/15 |
| CI workflow contract | PASS — 65/65 |
| Field release gate contracts | PASS — 209/209 |
| Android release-signing contracts | PASS — 63/63 |
| APK/AAB model runtime contract | PASS |
| Feature catalog contract | PASS — exactly 8 domains and ordered `f01-f44` |
| `git diff --check` | PASS; expected Windows line-ending notices only |

The historical `1.0.0+15` AAB was also measured as
`com.lexiquest.app` / `1.0.0` / `15` with complete signed-entry coverage. It is
not the candidate for this source because it predates the full-commit provenance
gate.

## Integrate next

1. Commit this verified source snapshot without the unrelated critique file.
2. Package signed APK and AAB `1.0.0+16` from that exact full commit.
3. Re-run artifact signature, identity, provenance and model/runtime gates.
4. Install the exact APK on the connected Vivo with non-destructive
   `adb install --no-streaming -r`; stop rather than uninstall if signatures
   conflict.
5. Record measured Vivo evidence and automated cold-launch/log checks. Manual
   TalkBack and human UAT remain pending until actually observed.

## External release dependencies

- Distinct physical low/high/Fold/tablet devices are not connected; the current
  Vivo V2041 is one physical mid-tier phone only.
- Play Console acceptance and Play app-signing compatibility for the exact AAB
  are not available locally.
- Valid App Check production traffic, enforcement/rollback evidence and
  production Firestore rollout authority are absent.
- Manual TalkBack and human end-to-end UAT have not been performed on this
  source candidate.
- Research ethics approval, protocol/instrument approval, trusted issuer/time
  authority and explicit participant rollout permission are absent. Collection
  and upload therefore remain fail closed.
