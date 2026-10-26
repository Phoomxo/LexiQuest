---
target: Cycle 12 post-fix native Android account entry
total_score: 39
max_score: 40
na_heuristics:
p0_count: 0
p1_count: 0
target_identity: "file:C:\\Users\\Phet\\.codex\\worktrees\\cycle12-release\\LexiQuest\\lib\\screens\\login_screen.dart"
target_fingerprint: "sha256:17390b6944199f1839cd97785abee48299191059d48bdeaaa952a991166a6146"
target_path: "C:\\Users\\Phet\\.codex\\worktrees\\cycle12-release\\LexiQuest\\lib\\screens\\login_screen.dart"
timestamp: 2026-10-26T11-42-56Z
slug: lib-screens-login-screen-dart
---
Method: design review only (detector not applicable, native Android)

## Design Health Score

| # | Heuristic | Score | Evidence |
| --- | --- | ---: | --- |
| 1 | Visibility of System Status | 4 | Local/cloud availability is visible before interaction; busy and errors remain live regions |
| 2 | Match System / Real World | 4 | Plain Thai labels describe learning, account and local storage outcomes |
| 3 | User Control and Freedom | 4 | Local learning stays available; research decline and account recovery are non-destructive |
| 4 | Consistency and Standards | 4 | Material 3 actions, 48dp targets and familiar account hierarchy |
| 5 | Error Prevention | 4 | Unavailable account actions are disabled before input; duplicate actions keep busy guards |
| 6 | Recognition Rather Than Recall | 4 | Local mode, provider state and next action are stated in place |
| 7 | Flexibility and Efficiency | 4 | Autofill, Google, password and local learning paths adapt to provider availability |
| 8 | Aesthetic and Minimalist Design | 4 | One primary action per runtime state; secondary actions no longer compete |
| 9 | Error Recovery | 4 | App Check failure preserves local learning and committed deletion recovery |
| 10 | Help and Documentation | 3 | Consent exposes retention, risk and privacy URL; approved public support contact remains external |
| **Total** | | **39/40** | **P0=0, P1=0; engineering design gate passes** |

## Resolved priority issues

- Local/degraded mode now explains account unavailability immediately and makes
  “เริ่มเรียนในเครื่อง” the filled primary action.
- Registration disables impossible account input before the user spends effort.
- Research consent now states the 30-day trial, 180-day retention, Cloud boundary,
  remaining risks and the full privacy-notice URL.
- Export success announces a human-readable filename and size instead of a raw
  Android `content://` URI.

## Remaining acceptance evidence

- Human TalkBack spoken order and physical tablet/Fold visual UAT still require
  observation on the exact signed artifact; automated semantics cannot certify them.
- A public support/deletion contact must come from the owner-approved release record,
  not from invented UI copy.

Questions skipped: all remaining decisions depend on external owner-approved contact and human device evidence.
